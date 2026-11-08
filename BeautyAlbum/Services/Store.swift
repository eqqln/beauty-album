import Foundation
import SwiftUI
import Combine
import UIKit

/// 全局数据仓库：JSON 元数据 + 文件系统图片。
/// 选择文件系统而非数据库，是为了让「备份 = 打包目录」这件事天然成立。
final class Store: ObservableObject {
    static let shared = Store()

    @Published var clients: [Client] = []
    @Published var teachers: [Teacher] = []
    @Published var appointments: [Appointment] = []
    @Published var products: [Product] = []
    @Published var settings: AppSettings = AppSettings()
    @Published var lastError: String?
    /// 密码锁是否已解锁。未开启锁时恒为 true。
    @Published var isUnlocked: Bool = true

    /// Documents/BeautyAlbum/
    let rootURL: URL

    private var cancellables = Set<AnyCancellable>()
    private var isLoading = false

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        rootURL = docs.appendingPathComponent("BeautyAlbum", isDirectory: true)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: qrURL, withIntermediateDirectories: true)

        load()
        isUnlocked = !settings.lockEnabled

        // 改动后 0.4 秒落盘，避免连续编辑时频繁写文件
        $clients
            .dropFirst()
            .debounce(for: .seconds(0.4), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)

        $settings
            .dropFirst()
            .debounce(for: .seconds(0.4), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)

        $teachers
            .dropFirst()
            .debounce(for: .seconds(0.4), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)

        $appointments
            .dropFirst()
            .debounce(for: .seconds(0.4), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)

        $products
            .dropFirst()
            .debounce(for: .seconds(0.4), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
    }

    // MARK: - 路径

    var mediaURL: URL { rootURL.appendingPathComponent("media", isDirectory: true) }
    var qrURL: URL { rootURL.appendingPathComponent("qrcode", isDirectory: true) }
    var dataURL: URL { rootURL.appendingPathComponent("data.json") }
    var settingsURL: URL { rootURL.appendingPathComponent("settings.json") }

    func clientDirectory(_ clientID: UUID) -> URL {
        mediaURL.appendingPathComponent(clientID.uuidString, isDirectory: true)
    }

    func photoURL(clientID: UUID, fileName: String) -> URL {
        clientDirectory(clientID).appendingPathComponent(fileName)
    }

    // MARK: - 读写

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func load() {
        isLoading = true
        defer { isLoading = false }

        if let data = try? Data(contentsOf: dataURL),
           let snap = try? Store.makeDecoder().decode(StoreSnapshot.self, from: data) {
            clients = snap.clients
            teachers = snap.teachers
            appointments = snap.appointments
            products = snap.products
        }
        if let data = try? Data(contentsOf: settingsURL),
           let s = try? Store.makeDecoder().decode(AppSettings.self, from: data) {
            settings = s
        } else if let snapData = try? Data(contentsOf: dataURL),
                  let snap = try? Store.makeDecoder().decode(StoreSnapshot.self, from: snapData),
                  let s = snap.settings {
            settings = s
        }
    }

    func save() {
        guard !isLoading else { return }
        do {
            let snap = StoreSnapshot(clients: clients, settings: settings,
                                     teachers: teachers, appointments: appointments,
                                     products: products)
            let data = try Store.makeEncoder().encode(snap)
            try data.write(to: dataURL, options: .atomic)

            let sData = try Store.makeEncoder().encode(settings)
            try sData.write(to: settingsURL, options: .atomic)
        } catch {
            lastError = "保存失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 客户操作

    func index(of id: UUID) -> Int? {
        clients.firstIndex { $0.id == id }
    }

    func client(_ id: UUID) -> Client? {
        guard let i = index(of: id) else { return nil }
        return clients[i]
    }

    @discardableResult
    func addClient(name: String, phone: String, note: String,
                   createdAt: Date = Date()) -> UUID {
        var c = Client(name: name, phone: phone, note: note, createdAt: createdAt)
        c.steps = settings.stepTemplate.map { StepItem(title: $0) }
        clients.append(c)
        try? FileManager.default.createDirectory(at: clientDirectory(c.id), withIntermediateDirectories: true)
        save()
        return c.id
    }

    func deleteClient(_ id: UUID) {
        clients.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: clientDirectory(id))
        save()
    }

    func updateClient(_ id: UUID, _ mutate: (inout Client) -> Void) {
        guard let i = index(of: id) else { return }
        mutate(&clients[i])
    }

    // MARK: - 自动备份

    /// 正在跑自动备份（防止重复触发）
    @Published var autoBackupRunning = false
    /// 最近一次自动备份的结果，给设置页显示
    @Published var autoBackupNote: String?

    /// App 回到前台时调用：到期了才真正打包
    func runAutoBackupIfNeeded() {
        guard !autoBackupRunning, settings.autoBackupDue() else { return }
        performAutoBackup()
    }

    /// 立刻做一次自动备份（也用于「现在备份一次」按钮）
    func performAutoBackup() {
        guard !autoBackupRunning else { return }
        autoBackupRunning = true
        autoBackupNote = "正在备份…"
        Task { @MainActor in
            defer { autoBackupRunning = false }
            do {
                let r = try await BackupService.build(store: self)
                _ = BackupService.markAsAuto(r.url)
                settings.lastAutoBackupAt = Date()
                BackupService.trimAutoBackups(in: exportsURL, keep: settings.autoBackupKeep)
                save()
                autoBackupNote = "备份完成 · \(Fmt.fileSize(r.bytes)) · \(Fmt.dateTime.string(from: Date()))"
            } catch {
                autoBackupNote = "备份失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - 图片

    /// 导入一张图片，返回写入的文件名
    func importImage(_ image: UIImage, clientID: UUID) -> String? {
        let prepared = image.downscaled(maxDimension: 1800)
        guard let data = prepared.jpegData(compressionQuality: 0.85) else { return nil }
        let name = UUID().uuidString + ".jpg"
        let dir = clientDirectory(clientID)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            lastError = "照片写入失败：\(error.localizedDescription)"
            return nil
        }
    }

    func deletePhoto(clientID: UUID, photo: PhotoItem) {
        let url = photoURL(clientID: clientID, fileName: photo.fileName)
        ImageCache.shared.remove(url)
        try? FileManager.default.removeItem(at: url)
        updateClient(clientID) { c in
            c.photos.removeAll { $0.id == photo.id }
        }
        save()
    }

    func movePhoto(clientID: UUID, photoID: UUID, to phase: PhotoPhase) {
        updateClient(clientID) { c in
            if let i = c.photos.firstIndex(where: { $0.id == photoID }) {
                c.photos[i].phase = phase
            }
        }
        save()
    }

    // MARK: - 老师

    var teachersURL: URL { mediaURL.appendingPathComponent("teachers", isDirectory: true) }

    func teacherImageURL(_ id: UUID) -> URL {
        teachersURL.appendingPathComponent(id.uuidString + ".jpg")
    }

    func teacherImage(_ id: UUID) -> UIImage? {
        UIImage(contentsOfFile: teacherImageURL(id).path)
    }

    var sortedTeachers: [Teacher] {
        teachers.sorted {
            if $0.sortIndex != $1.sortIndex { return $0.sortIndex < $1.sortIndex }
            return $0.createdAt < $1.createdAt
        }
    }

    @discardableResult
    func addTeacher(_ t: Teacher) -> UUID {
        var copy = t
        if copy.sortIndex == 0 {
            copy.sortIndex = (teachers.map(\.sortIndex).max() ?? 0) + 1
        }
        teachers.append(copy)
        try? FileManager.default.createDirectory(at: teachersURL, withIntermediateDirectories: true)
        save()
        return copy.id
    }

    func updateTeacher(_ t: Teacher) {
        guard let i = teachers.firstIndex(where: { $0.id == t.id }) else { return }
        teachers[i] = t
        save()
    }

    func deleteTeacher(_ id: UUID) {
        teachers.removeAll { $0.id == id }
        ImageCache.shared.remove(teacherImageURL(id))
        try? FileManager.default.removeItem(at: teacherImageURL(id))
        save()
    }

    func saveTeacherImage(_ image: UIImage, teacherID: UUID) -> Bool {
        let prepared = image.downscaled(maxDimension: 1200)
        guard let data = prepared.jpegData(compressionQuality: 0.85) else { return false }
        do {
            try FileManager.default.createDirectory(at: teachersURL, withIntermediateDirectories: true)
            try data.write(to: teacherImageURL(teacherID), options: .atomic)
            ImageCache.shared.remove(teacherImageURL(teacherID))
            return true
        } catch {
            lastError = "头像保存失败：\(error.localizedDescription)"
            return false
        }
    }

    func moveTeacher(_ id: UUID, delta: Int) {
        var list = sortedTeachers
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        let target = i + delta
        guard target >= 0, target < list.count else { return }
        list.swapAt(i, target)
        for (idx, t) in list.enumerated() {
            if let j = teachers.firstIndex(where: { $0.id == t.id }) {
                teachers[j].sortIndex = idx + 1
            }
        }
        save()
    }

    // MARK: - 预约

    @discardableResult
    func addAppointment(_ a: Appointment) -> UUID {
        appointments.append(a)
        save()
        return a.id
    }

    func updateAppointment(_ a: Appointment) {
        guard let i = appointments.firstIndex(where: { $0.id == a.id }) else { return }
        appointments[i] = a
        save()
    }

    func deleteAppointment(_ id: UUID) {
        appointments.removeAll { $0.id == id }
        save()
    }

    func appointments(for teacherID: UUID) -> [Appointment] {
        appointments.filter { $0.teacherID == teacherID }.sorted { $0.date > $1.date }
    }

    var upcomingAppointments: [Appointment] {
        appointments.filter { $0.isUpcoming }.sorted { $0.date < $1.date }
    }

    var todayAppointments: [Appointment] {
        let cal = Calendar.current
        return appointments
            .filter { cal.isDateInToday($0.date) && $0.status != .cancelled }
            .sorted { $0.date < $1.date }
    }

    func teacherName(_ id: UUID) -> String {
        teachers.first { $0.id == id }?.name ?? "已删除老师"
    }

    // MARK: - 产品

    var productsURL: URL { mediaURL.appendingPathComponent("products", isDirectory: true) }

    func productDirectory(_ id: UUID) -> URL {
        productsURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func productImageURL(_ productID: UUID, name: String) -> URL {
        productDirectory(productID).appendingPathComponent(name)
    }

    func productCover(_ product: Product) -> URL? {
        guard let first = product.imageNames.first else { return nil }
        return productImageURL(product.id, name: first)
    }

    func product(_ id: UUID) -> Product? {
        products.first { $0.id == id }
    }

    var sortedProducts: [Product] {
        products.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func addProduct(_ p: Product) -> UUID {
        products.append(p)
        try? FileManager.default.createDirectory(at: productDirectory(p.id), withIntermediateDirectories: true)
        save()
        return p.id
    }

    func updateProduct(_ p: Product) {
        guard let i = products.firstIndex(where: { $0.id == p.id }) else { return }
        products[i] = p
        save()
    }

    func deleteProduct(_ id: UUID) {
        products.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: productDirectory(id))
        save()
    }

    func importProductImage(_ image: UIImage, productID: UUID) -> String? {
        let prepared = image.downscaled(maxDimension: 1600)
        guard let data = prepared.jpegData(compressionQuality: 0.85) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            let dir = productDirectory(productID)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            lastError = "产品图保存失败：\(error.localizedDescription)"
            return nil
        }
    }

    func deleteProductImage(productID: UUID, name: String) {
        try? FileManager.default.removeItem(at: productImageURL(productID, name: name))
    }

    /// 某产品的领取统计
    func claimStats(productID: UUID) -> (claimed: Int, pending: Int) {
        var claimed = 0, pending = 0
        for client in clients {
            for claim in client.claims where claim.productID == productID {
                if claim.claimed { claimed += 1 } else { pending += 1 }
            }
        }
        return (claimed, pending)
    }

    // MARK: - 收款码

    func savePaymentQR(image: UIImage, kind: PaymentQRKind) -> Bool {
        let prepared = image.downscaled(maxDimension: 1000)
        guard let data = prepared.jpegData(compressionQuality: 0.9) else { return false }
        let name = "\(kind.rawValue).jpg"
        do {
            try FileManager.default.createDirectory(at: qrURL, withIntermediateDirectories: true)
            try data.write(to: qrURL.appendingPathComponent(name), options: .atomic)
            switch kind {
            case .wechat: settings.wechatQR = name
            case .alipay: settings.alipayQR = name
            }
            save()
            return true
        } catch {
            lastError = "收款码保存失败：\(error.localizedDescription)"
            return false
        }
    }

    func paymentQRImage(kind: PaymentQRKind) -> UIImage? {
        let name: String?
        switch kind {
        case .wechat: name = settings.wechatQR
        case .alipay: name = settings.alipayQR
        }
        guard let n = name else { return nil }
        return UIImage(contentsOfFile: qrURL.appendingPathComponent(n).path)
    }

    func removePaymentQR(kind: PaymentQRKind) {
        switch kind {
        case .wechat: settings.wechatQR = nil
        case .alipay: settings.alipayQR = nil
        }
        try? FileManager.default.removeItem(at: qrURL.appendingPathComponent("\(kind.rawValue).jpg"))
        save()
    }

    // MARK: - 密码锁

    var hasLockCode: Bool { !settings.lockHash.isEmpty }

    func enableLock(code: String) {
        settings.lockHash = LockCode.hash(code)
        settings.lockEnabled = true
        isUnlocked = true
        save()
    }

    func disableLock() {
        settings.lockEnabled = false
        settings.lockHash = ""
        isUnlocked = true
        save()
    }

    func changeLockCode(to code: String) {
        settings.lockHash = LockCode.hash(code)
        save()
    }

    func verifyLockCode(_ code: String) -> Bool {
        guard hasLockCode else { return true }
        return settings.lockHash == LockCode.hash(code)
    }

    @discardableResult
    func unlock(with code: String) -> Bool {
        guard verifyLockCode(code) else { return false }
        isUnlocked = true
        return true
    }

    func lockNow() {
        guard settings.lockEnabled else { return }
        isUnlocked = false
    }

    /// 忘记密码时的兜底：清空本机数据并关闭锁
    func resetAllData() {
        clients = []
        settings = AppSettings()
        try? FileManager.default.removeItem(at: mediaURL)
        try? FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: qrURL)
        try? FileManager.default.createDirectory(at: qrURL, withIntermediateDirectories: true)
        isUnlocked = true
        save()
    }

    // MARK: - 统计

    var totalPhotoCount: Int { clients.reduce(0) { $0 + $1.photos.count } }
    var totalPaid: Double { clients.reduce(0) { $0 + $1.totalPaid } }
    /// 应收合计（只统计设置了应收的客户）
    var totalQuoted: Double { clients.reduce(0) { $0 + $1.quotedPrice } }
    /// 未收合计
    var totalUnpaid: Double { clients.reduce(0) { $0 + $1.unpaidAmount } }
    /// 欠款客户数
    var unpaidClientCount: Int { clients.filter { $0.unpaidAmount > 0 }.count }

    func storageBytes() -> Int64 {
        guard let en = FileManager.default.enumerator(at: rootURL,
                                                     includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in en {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    // MARK: - 恢复用

    /// 用外部快照整体替换本地数据（备份恢复）
    func replaceAll(with snapshot: StoreSnapshot, imageResolver: (UUID) -> Data?) {
        // 清空旧图片目录
        if let dirs = try? FileManager.default.contentsOfDirectory(at: mediaURL, includingPropertiesForKeys: nil) {
            for d in dirs { try? FileManager.default.removeItem(at: d) }
        }
        clients = snapshot.clients
        teachers = snapshot.teachers
        appointments = snapshot.appointments
        products = snapshot.products

        for c in clients {
            let dir = clientDirectory(c.id)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for p in c.photos {
                if let data = imageResolver(p.id) {
                    try? data.write(to: dir.appendingPathComponent(p.fileName), options: .atomic)
                }
            }
        }

        try? FileManager.default.createDirectory(at: teachersURL, withIntermediateDirectories: true)
        for t in teachers {
            if let data = imageResolver(t.id) {
                try? data.write(to: teacherImageURL(t.id), options: .atomic)
            }
        }

        try? FileManager.default.createDirectory(at: productsURL, withIntermediateDirectories: true)
        for p in products {
            let dir = productDirectory(p.id)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for name in p.imageNames {
                let key = (name as NSString).deletingPathExtension
                if let data = imageResolver(UUID(uuidString: key) ?? p.id) {
                    try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
                }
            }
        }

        if let s = snapshot.settings {
            settings = s
        }
        ImageCache.shared.removeAll()
        save()
    }

    /// 合并恢复：按客户 id 去重，已存在则跳过
    func merge(with snapshot: StoreSnapshot, imageResolver: (UUID) -> Data?) {
        let existing = Set(clients.map(\.id))
        for c in snapshot.clients where !existing.contains(c.id) {
            var copy = c
            let dir = clientDirectory(copy.id)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for p in copy.photos {
                if let data = imageResolver(p.id) {
                    try? data.write(to: dir.appendingPathComponent(p.fileName), options: .atomic)
                }
            }
            copy.photos = copy.photos.filter { p in
                FileManager.default.fileExists(atPath: photoURL(clientID: copy.id, fileName: p.fileName).path)
            }
            clients.append(copy)
        }

        let existingTeachers = Set(teachers.map(\.id))
        try? FileManager.default.createDirectory(at: teachersURL, withIntermediateDirectories: true)
        for t in snapshot.teachers where !existingTeachers.contains(t.id) {
            if let data = imageResolver(t.id) {
                try? data.write(to: teacherImageURL(t.id), options: .atomic)
            }
            teachers.append(t)
        }

        let existingAppointments = Set(appointments.map(\.id))
        for a in snapshot.appointments where !existingAppointments.contains(a.id) {
            appointments.append(a)
        }

        let existingProducts = Set(products.map(\.id))
        for p in snapshot.products where !existingProducts.contains(p.id) {
            let dir = productDirectory(p.id)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for name in p.imageNames {
                let key = (name as NSString).deletingPathExtension
                if let data = imageResolver(UUID(uuidString: key) ?? p.id) {
                    try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
                }
            }
            products.append(p)
        }

        save()
    }
}

enum PaymentQRKind: String, CaseIterable, Identifiable {
    case wechat
    case alipay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wechat: return "微信收款码"
        case .alipay: return "支付宝收款码"
        }
    }
}
