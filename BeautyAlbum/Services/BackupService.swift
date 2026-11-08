import Foundation
import UIKit

extension Store {
    /// 导出的备份文件存放处（在「文件」App 中可见）
    var exportsURL: URL {
        let u = rootURL.appendingPathComponent("exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}

enum BackupService {

    struct BuildResult {
        var url: URL
        var clientCount: Int
        var photoCount: Int
        var bytes: Int64
    }

    struct RestoreResult {
        var clientCount: Int
        var photoCount: Int
        var merged: Bool
    }

    // MARK: - 生成备份

    @MainActor
    static func build(store: Store) async throws -> BuildResult {
        let clients = store.clients
        let teachers = store.teachers
        let appointments = store.appointments
        let products = store.products
        let settings = store.settings
        let media = store.mediaURL
        let qr = store.qrURL
        let exports = store.exportsURL

        return try await Task.detached(priority: .userInitiated) {
            try buildArchive(clients: clients, teachers: teachers, appointments: appointments,
                             products: products, settings: settings,
                             mediaURL: media, qrURL: qr, exportsURL: exports)
        }.value
    }

    private static func buildArchive(clients: [Client], teachers: [Teacher],
                                     appointments: [Appointment], products: [Product],
                                     settings: AppSettings,
                                     mediaURL: URL, qrURL: URL, exportsURL: URL) throws -> BuildResult {
        let fm = FileManager.default
        let stamp = Fmt.stamp.string(from: Date())
        let rootName = "\(sanitize(settings.shopName, fallback: "美容院"))_备份_\(stamp)"

        let work = fm.temporaryDirectory.appendingPathComponent("backup-\(UUID().uuidString)", isDirectory: true)
        let root = work.appendingPathComponent(rootName, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        // 1. 元数据（恢复时据此重建，图片按 ID 匹配）
        let snap = StoreSnapshot(clients: clients, settings: settings,
                                 teachers: teachers, appointments: appointments,
                                 products: products)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(snap).write(to: root.appendingPathComponent("data.json"), options: .atomic)

        // 2. 按客户名 / 阶段文字 建立目录
        let beforeDir = sanitize(settings.beforeLabel, fallback: "使用前")
        let afterDir = sanitize(settings.afterLabel, fallback: "使用后")
        var usedNames = Set<String>()
        var photoCount = 0

        for client in clients {
            var dirName = sanitize(client.name.isEmpty ? "未命名客户" : client.name, fallback: "未命名客户")
            if usedNames.contains(dirName) {
                let short = client.id.uuidString.prefix(4)
                dirName += "_\(short)"
            }
            usedNames.insert(dirName)

            let cDir = root.appendingPathComponent(dirName, isDirectory: true)
            try fm.createDirectory(at: cDir, withIntermediateDirectories: true)

            for phase in PhotoPhase.allCases {
                let photos = client.photos.filter { $0.phase == phase }
                guard !photos.isEmpty else { continue }
                let pDir = cDir.appendingPathComponent(phase == .before ? beforeDir : afterDir,
                                                       isDirectory: true)
                try fm.createDirectory(at: pDir, withIntermediateDirectories: true)
                for p in photos {
                    let src = mediaURL
                        .appendingPathComponent(client.id.uuidString, isDirectory: true)
                        .appendingPathComponent(p.fileName)
                    guard fm.fileExists(atPath: src.path) else { continue }
                    let dst = pDir.appendingPathComponent(p.id.uuidString + ".jpg")
                    try? fm.copyItem(at: src, to: dst)
                    photoCount += 1
                }
            }

            // 3. 可读的文本档案
            write(cInfo(client, settings: settings), to: cDir.appendingPathComponent("客户信息.txt"))
            write(stepsInfo(client, settings: settings), to: cDir.appendingPathComponent("流程进度.txt"))
            write(notesInfo(client), to: cDir.appendingPathComponent("跟进记录.txt"))
            write(paymentsInfo(client), to: cDir.appendingPathComponent("收款记录.txt"))
        }

        // 4. 收款码
        let qrDir = root.appendingPathComponent("收款码", isDirectory: true)
        try? fm.createDirectory(at: qrDir, withIntermediateDirectories: true)
        for kind in PaymentQRKind.allCases {
            let name = kind == .wechat ? settings.wechatQR : settings.alipayQR
            guard let n = name else { continue }
            let src = qrURL.appendingPathComponent(n)
            if fm.fileExists(atPath: src.path) {
                try? fm.copyItem(at: src, to: qrDir.appendingPathComponent("\(kind.title).jpg"))
            }
        }

        // 5. 老师
        if !teachers.isEmpty {
            let tRoot = root.appendingPathComponent("老师", isDirectory: true)
            try? fm.createDirectory(at: tRoot, withIntermediateDirectories: true)
            let tMedia = mediaURL.appendingPathComponent("teachers", isDirectory: true)
            for t in teachers {
                let src = tMedia.appendingPathComponent(t.id.uuidString + ".jpg")
                if fm.fileExists(atPath: src.path) {
                    try? fm.copyItem(at: src, to: tRoot.appendingPathComponent(t.id.uuidString + ".jpg"))
                }
                let infoName = sanitize(t.name, fallback: "老师") + "_"
                    + String(t.id.uuidString.prefix(4)) + ".txt"
                write(teacherInfo(t), to: tRoot.appendingPathComponent(infoName))
            }
        }

        // 6. 产品
        if !products.isEmpty {
            let pRoot = root.appendingPathComponent("产品", isDirectory: true)
            try? fm.createDirectory(at: pRoot, withIntermediateDirectories: true)
            let pMedia = mediaURL.appendingPathComponent("products", isDirectory: true)
            for p in products {
                let d = pRoot.appendingPathComponent(sanitize(p.name, fallback: "产品"), isDirectory: true)
                try? fm.createDirectory(at: d, withIntermediateDirectories: true)
                for name in p.imageNames {
                    let src = pMedia
                        .appendingPathComponent(p.id.uuidString, isDirectory: true)
                        .appendingPathComponent(name)
                    if fm.fileExists(atPath: src.path) {
                        try? fm.copyItem(at: src, to: d.appendingPathComponent(name))
                    }
                }
                write(productInfo(p), to: d.appendingPathComponent("产品信息.txt"))
            }
        }

        // 7. 预约
        if !appointments.isEmpty {
            write(appointmentsInfo(appointments), to: root.appendingPathComponent("预约记录.txt"))
        }

        // 8. 打包
        let zipURL = exportsURL.appendingPathComponent(rootName + ".zip")
        let writer = try ZipWriter(url: zipURL)
        try writer.addDirectory(rootName)
        try addTree(writer: writer, base: root, prefix: rootName)
        try writer.finish()

        let attrs = try? fm.attributesOfItem(atPath: zipURL.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0

        return BuildResult(url: zipURL, clientCount: clients.count,
                           photoCount: photoCount, bytes: size)
    }

    private static func addTree(writer: ZipWriter, base: URL, prefix: String) throws {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for case let url as URL in en {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let rel = url.path.replacingOccurrences(of: base.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !rel.isEmpty else { continue }
            let path = prefix + "/" + rel
            if isDir {
                try writer.addDirectory(path)
            } else {
                try writer.addFile(path: path, fileURL: url)
            }
        }
    }

    // MARK: - 文本档案

    private static func write(_ text: String, to url: URL) {
        var data = Data([0xEF, 0xBB, 0xBF])   // BOM，Windows 记事本不乱码
        data.append(Data(text.utf8))
        try? data.write(to: url, options: .atomic)
    }

    private static func cInfo(_ c: Client, settings: AppSettings) -> String {
        var s = """
        姓名：\(c.name)
        电话：\(c.phone.isEmpty ? "未填写" : c.phone)
        建档时间：\(Fmt.dateTime.string(from: c.createdAt))
        照片数量：\(c.photos.count)（\(settings.beforeLabel) \(c.beforePhotos.count) / \(settings.afterLabel) \(c.afterPhotos.count)）
        当前环节：\(c.currentStageTitle)
        完成进度：\(c.sequentialDoneCount)/\(c.steps.count)

        —— 账单 ——
        应收：\(c.quotedPrice > 0 ? Fmt.money(c.quotedPrice) : "未设置")
        已付：\(Fmt.money(c.paidAmount))（\(c.payments.count) 笔）
        未付：\(Fmt.money(c.unpaidAmount))
        状态：\(c.paymentStatus.rawValue)

        —— 备注 ——
        \(c.note.isEmpty ? "（无）" : c.note)

        """

        if !c.claims.isEmpty {
            s += "\n—— 产品领取 ——\n"
            let claimed = c.claims.filter(\.claimed)
            let pending = c.claims.filter { !$0.claimed }
            s += "已领取：\n"
            if claimed.isEmpty {
                s += "  （无）\n"
            } else {
                for x in claimed {
                    s += "  ✓ \(x.productName) \(x.specName) ×\(x.quantity)"
                    if let d = x.claimedAt { s += "  \(Fmt.dateOnly.string(from: d))" }
                    s += "\n"
                }
            }
            s += "待领取：\n"
            if pending.isEmpty {
                s += "  （无）\n"
            } else {
                for x in pending {
                    s += "  ○ \(x.productName) \(x.specName) ×\(x.quantity)\n"
                }
            }
        }

        return s
    }

    private static func teacherInfo(_ t: Teacher) -> String {
        """
        姓名：\(t.name)
        职位：\(t.displayTitle)
        电话：\(t.phone.isEmpty ? "未填写" : t.phone)
        可预约：\(t.available ? "是" : "否")
        擅长项目：\(t.tags.isEmpty ? "未填写" : t.tags.joined(separator: "、"))

        —— 简介 ——
        \(t.intro.isEmpty ? "（无）" : t.intro)
        """
    }

    private static func productInfo(_ p: Product) -> String {
        var s = """
        产品名称：\(p.name)
        品牌：\(p.brand.isEmpty ? "未填写" : p.brand)
        分类：\(p.category.isEmpty ? "未填写" : p.category)
        适用阶段：\(p.stage.isEmpty ? "未指定" : p.stage)
        价格区间：\(p.priceRange)
        总库存：\(p.totalStock)

        —— 规格 ——
        """
        if p.specs.isEmpty {
            s += "（无）\n"
        } else {
            for spec in p.specs {
                s += "\(spec.displayName)  \(spec.price > 0 ? Fmt.money(spec.price) : "未定价")  库存 \(spec.stock)\n"
            }
        }

        s += "\n—— 使用步骤 ——\n"
        if p.usageSteps.isEmpty {
            s += "（无）\n"
        } else {
            for (i, step) in p.usageSteps.enumerated() {
                s += "\(i + 1). \(step)\n"
            }
        }

        s += "\n—— 产品说明 ——\n\(p.intro.isEmpty ? "（无）" : p.intro)\n"
        return s
    }

    private static func appointmentsInfo(_ list: [Appointment]) -> String {
        var s = "共 \(list.count) 条预约\n\n"
        let sorted = list.sorted { $0.date > $1.date }
        var currentDay = ""
        for a in sorted {
            let day = Fmt.dateOnly.string(from: a.date)
            if day != currentDay {
                currentDay = day
                s += "\n【\(day) \(Fmt.weekday(a.date))】\n"
            }
            s += "  \(Fmt.time(a.date))  \(a.durationMinutes)分钟  "
            s += "\(a.clientName.isEmpty ? "散客" : a.clientName)"
            s += "  老师：\(a.teacherName.isEmpty ? "未指定" : a.teacherName)"
            if !a.service.isEmpty { s += "  项目：\(a.service)" }
            s += "  [\(a.status.rawValue)]"
            if !a.note.isEmpty { s += "  备注：\(a.note)" }
            s += "\n"
        }
        return s
    }

    private static func stepsInfo(_ c: Client, settings: AppSettings) -> String {
        var s = "当前环节：\(c.currentStageTitle)\n进度：\(c.sequentialDoneCount)/\(c.steps.count)\n\n"
        for (i, st) in c.steps.enumerated() {
            let mark = st.done ? "[已完成]" : "[未完成]"
            let time = st.doneAt.map { "  \(Fmt.dateTime.string(from: $0))" } ?? ""
            s += "\(i + 1). \(mark) \(st.title)\(time)\n"
            if !st.note.isEmpty { s += "     备注：\(st.note)\n" }
        }
        return s
    }

    private static func notesInfo(_ c: Client) -> String {
        if c.notes.isEmpty { return "（暂无跟进记录）\n" }
        return c.notes
            .sorted { $0.createdAt > $1.createdAt }
            .map { "\(Fmt.dateTime.string(from: $0.createdAt))\n\($0.content)\n" }
            .joined(separator: "\n----------------\n\n")
    }

    private static func paymentsInfo(_ c: Client) -> String {
        if c.payments.isEmpty { return "（暂无收款记录）\n" }
        var s = "合计：\(Fmt.money(c.totalPaid))\n\n"
        for p in c.payments.sorted(by: { $0.createdAt > $1.createdAt }) {
            s += "\(Fmt.dateTime.string(from: p.createdAt))  \(Fmt.money(p.amount))  \(p.method)"
            if !p.note.isEmpty { s += "  \(p.note)" }
            s += "\n"
        }
        return s
    }

    // MARK: - 恢复

    @MainActor
    static func restore(zipURL: URL, store: Store, merge: Bool) async throws -> RestoreResult {
        let targetMedia = store.mediaURL

        return try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("restore-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: work) }

            let reader = try ZipReader(url: zipURL)
            try reader.extract(to: work)

            // 找到 data.json（备份里可能有一层根目录）
            guard let dataJSON = findFile(named: "data.json", under: work) else {
                throw ZipError.ioFailure("备份包中缺少 data.json，可能不是本应用的备份文件")
            }
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            let snap = try dec.decode(StoreSnapshot.self, from: Data(contentsOf: dataJSON))

            // 建立 photoID -> 文件 索引
            var index: [String: URL] = [:]
            if let en = fm.enumerator(at: work, includingPropertiesForKeys: [.isDirectoryKey]) {
                for case let u as URL in en {
                    let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if isDir { continue }
                    let key = u.deletingPathExtension().lastPathComponent.lowercased()
                    if index[key] == nil { index[key] = u }
                }
            }

            let resolver: (UUID) -> Data? = { pid in
                guard let u = index[pid.uuidString.lowercased()] else { return nil }
                return try? Data(contentsOf: u)
            }

            await MainActor.run {
                if merge {
                    store.merge(with: snap, imageResolver: resolver)
                } else {
                    store.replaceAll(with: snap, imageResolver: resolver)
                }
            }

            let photos = snap.clients.reduce(0) { $0 + $1.photos.count }
            return RestoreResult(clientCount: snap.clients.count, photoCount: photos, merged: merge)
        }.value
    }

    private static func findFile(named name: String, under dir: URL) -> URL? {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return nil }
        var best: URL?
        for case let u as URL in en where u.lastPathComponent == name {
            if best == nil || u.pathComponents.count < best!.pathComponents.count {
                best = u
            }
        }
        return best
    }

    // MARK: - 已有备份列表

    static func existingBackups(in dir: URL) -> [(url: URL, date: Date, size: Int64)] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
        else { return [] }
        return files
            .filter { $0.pathExtension.lowercased() == "zip" }
            .compactMap { u -> (URL, Date, Int64)? in
                let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                return (u, v?.contentModificationDate ?? Date(), Int64(v?.fileSize ?? 0))
            }
            .sorted { $0.1 > $1.1 }
    }

    // MARK: - 工具

    static func sanitize(_ s: String, fallback: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        t = t.components(separatedBy: illegal).joined(separator: "_")
        if t.isEmpty { t = fallback }
        if t.count > 40 { t = String(t.prefix(40)) }
        return t
    }
}
