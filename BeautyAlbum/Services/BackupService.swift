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
        let agents = store.agents
        let settings = store.settings
        let media = store.mediaURL
        let qr = store.qrURL
        let exports = store.exportsURL

        return try await Task.detached(priority: .userInitiated) {
            try buildArchive(clients: clients, teachers: teachers, appointments: appointments,
                             products: products, agents: agents, settings: settings,
                             mediaURL: media, qrURL: qr, exportsURL: exports)
        }.value
    }

    private static func buildArchive(clients: [Client], teachers: [Teacher],
                                     appointments: [Appointment], products: [Product],
                                     agents: [Agent], settings: AppSettings,
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
                                 products: products, agents: agents)
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

        // 8. 代理：一位一个文件夹，放档案与拿货明细
        if !agents.isEmpty {
            let aRoot = root.appendingPathComponent("代理", isDirectory: true)
            try? fm.createDirectory(at: aRoot, withIntermediateDirectories: true)
            for a in agents.sorted(by: { $0.joinedAt < $1.joinedAt }) {
                let dirName = sanitize(a.name, fallback: "代理") + "_"
                    + String(a.id.uuidString.prefix(4))
                let d = aRoot.appendingPathComponent(dirName, isDirectory: true)
                try? fm.createDirectory(at: d, withIntermediateDirectories: true)
                write(agentInfo(a, clients: clients), to: d.appendingPathComponent("代理信息.txt"))
                write(agentOrdersInfo(a), to: d.appendingPathComponent("拿货记录.txt"))
            }
            write(agentOverviewInfo(agents, clients: clients),
                  to: root.appendingPathComponent("代理总览.txt"))
        }

        // 9. 备份说明与客户总览（打开压缩包第一眼就能看懂里面有什么）
        write(readmeInfo(clients: clients, settings: settings, photoCount: photoCount,
                         teachers: teachers, appointments: appointments,
                         products: products, agents: agents),
              to: root.appendingPathComponent("备份说明.txt"))
        write(overviewInfo(clients), to: root.appendingPathComponent("客户总览.txt"))

        // 10. 打包
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

    /// 备份包根目录的说明文件
    private static func readmeInfo(clients: [Client], settings: AppSettings, photoCount: Int,
                                   teachers: [Teacher], appointments: [Appointment],
                                   products: [Product], agents: [Agent]) -> String {
        """
        【店铺】\(settings.shopName)
        【导出时间】\(Fmt.dateTime.string(from: Date()))
        【数据量】客户 \(clients.count) 位 · 照片 \(photoCount) 张 · 老师 \(teachers.count) 位 · 预约 \(appointments.count) 条 · 产品 \(products.count) 个 · 代理 \(agents.count) 位
        【照片阶段叫法】\(settings.beforeLabel) / \(settings.afterLabel)

        —— 每位客户一个文件夹，里面是 ——
        \(settings.beforeLabel)/          这一阶段的原始照片
        \(settings.afterLabel)/           这一阶段的原始照片（前后对比图就是用这两组照片生成的）
        客户信息.txt      姓名、电话、建档时间、账单、备注、产品领取
        流程进度.txt      每一步做没做、什么时候做的、环节备注
        跟进记录.txt      每次沟通记录
        收款记录.txt      每笔收款的时间、金额、方式

        —— 根目录还有 ——
        客户总览.txt      所有客户一行一个，方便快速核对
        老师/             老师照片和资料
        产品/             产品图片、规格、价格、库存、使用步骤
        代理/             每位代理一个文件夹：代理信息、拿货记录
        代理总览.txt      所有代理一行一个，含上级、加入时间、拿货件数与金额
        预约记录.txt      全部预约
        收款码/           微信、支付宝收款码
        data.json         完整数据，App 内「从备份恢复」靠这个文件重建全部内容

        —— 怎么恢复 ——
        App 里：设置 → 备份与恢复 → 从备份恢复 → 选这个 zip
        选「覆盖恢复」清空后还原，选「合并恢复」保留现有客户再追加
        """
    }

    /// 代理总览：一行一个，含上级、加入时间、件数、金额
    private static func agentOverviewInfo(_ agents: [Agent], clients: [Client]) -> String {
        var s = "代理总览（共 \(agents.count) 位）\n\n"
        s += "序号  姓名          等级        上级          加入        客户  件数   拿货额    未结\n"
        let sorted = agents.sorted { $0.joinedAt < $1.joinedAt }
        for (i, a) in sorted.enumerated() {
            let name = pad(a.name.isEmpty ? "未命名" : a.name, 12)
            let level = pad(a.level.rawValue, 10)
            let parent = pad(a.parentName.isEmpty ? "-" : a.parentName, 12)
            let joined = pad(Fmt.dateOnly.string(from: a.joinedAt), 10)
            let cn = pad("\(a.clientIDs.count) 位", 5)
            let qty = pad("\(a.totalQuantity)", 5)
            let amount = pad(Fmt.money(a.totalAmount), 9)
            let unpaid = a.totalUnpaid > 0 ? Fmt.money(a.totalUnpaid) : "-"
            s += "\(pad("\(i + 1)", 5))\(name)\(level)\(parent)\(joined)\(cn)\(qty)\(amount)\(unpaid)\n"
        }

        let totalQty = agents.reduce(0) { $0 + $1.totalQuantity }
        let totalAmount = agents.reduce(0) { $0 + $1.totalAmount }
        let totalPaid = agents.reduce(0) { $0 + $1.totalPaid }
        let totalUnpaid = agents.reduce(0) { $0 + $1.totalUnpaid }
        s += "\n合计：件数 \(totalQty) · 拿货额 \(Fmt.money(totalAmount)) · 已付 \(Fmt.money(totalPaid)) · 未结 \(Fmt.money(totalUnpaid))\n"
        return s
    }

    /// 单个代理的档案
    private static func agentInfo(_ a: Agent, clients: [Client]) -> String {
        var s = """
        姓名：\(a.name)
        等级：\(a.level.rawValue)
        拿货折扣：\(a.discountText)
        电话：\(a.phone.isEmpty ? "未填写" : a.phone)
        微信：\(a.wechat.isEmpty ? "未填写" : a.wechat)
        地区：\(a.displayRegion)
        上级代理：\(a.parentName.isEmpty ? "无（顶层）" : a.parentName)
        加入时间：\(Fmt.dateTime.string(from: a.joinedAt))（已 \(a.daysSinceJoined()) 天）

        —— 拿货汇总 ——
        记录笔数：\(a.orderCount)
        累计件数：\(a.totalQuantity)
        累计金额：\(Fmt.money(a.totalAmount))
        已付：\(Fmt.money(a.totalPaid))
        未结：\(Fmt.money(a.totalUnpaid))
        最近拿货：\(a.lastOrderAt.map { Fmt.dateTime.string(from: $0) } ?? "无")

        —— 名下客户 ——
        """

        if a.clientIDs.isEmpty {
            s += "（无）\n"
        } else {
            s += "共 \(a.clientIDs.count) 位：\n"
            for id in a.clientIDs {
                if let c = clients.first(where: { $0.id == id }) {
                    s += "  · \(c.name.isEmpty ? "未命名" : c.name)　\(c.phone.isEmpty ? "未留电话" : c.phone)\n"
                } else {
                    s += "  · （客户已删除 \(id.uuidString.prefix(8))）\n"
                }
            }
        }

        s += "\n—— 备注 ——\n\(a.note.isEmpty ? "（无）" : a.note)\n"
        return s
    }

    /// 拿货记录明细
    private static func agentOrdersInfo(_ a: Agent) -> String {
        var s = "拿货记录（\(a.name)）共 \(a.orderCount) 笔\n\n"
        guard !a.orders.isEmpty else { return s + "（暂无记录）\n" }

        s += "时间              产品            规格        数量   单价      金额      已付      未结\n"
        let sorted = a.orders.sorted { $0.createdAt < $1.createdAt }
        for o in sorted {
            let t = pad(Fmt.dateTime.string(from: o.createdAt), 18)
            let p = pad(o.displayName, 16)
            let spec = pad(o.specName.isEmpty ? "-" : o.specName, 12)
            let q = pad("\(o.quantity)", 7)
            let price = pad(Fmt.money(o.unitPrice), 10)
            let amt = pad(Fmt.money(o.amount), 10)
            let paid = pad(Fmt.money(o.paid), 10)
            let unpaid = o.unpaid > 0 ? Fmt.money(o.unpaid) : "-"
            s += "\(t)\(p)\(spec)\(q)\(price)\(amt)\(paid)\(unpaid)\n"
        }

        s += "\n合计：件数 \(a.totalQuantity) · 金额 \(Fmt.money(a.totalAmount)) · 已付 \(Fmt.money(a.totalPaid)) · 未结 \(Fmt.money(a.totalUnpaid))\n"

        let noted = sorted.filter { !$0.note.isEmpty }
        if !noted.isEmpty {
            s += "\n—— 备注 ——\n"
            for o in noted {
                s += "\(Fmt.dateOnly.string(from: o.createdAt))　\(o.displayName)：\(o.note)\n"
            }
        }
        return s
    }

    /// 所有客户一行一个，方便对账
    private static func overviewInfo(_ clients: [Client]) -> String {
        var s = "客户总览（共 \(clients.count) 位）\n\n"
        s += "序号  姓名          电话              建档        照片  进度      应收      已付      未付\n"
        for (i, c) in clients.enumerated() {
            let name = pad(c.name.isEmpty ? "未命名" : c.name, 12)
            let phone = pad(c.phone.isEmpty ? "未填" : c.phone, 16)
            let created = pad(Fmt.dateOnly.string(from: c.createdAt), 12)
            let photos = pad("\(c.photos.count) 张", 5)
            let step = pad("\(c.sequentialDoneCount)/\(c.steps.count) 步", 9)
            let quoted = pad(c.quotedPrice > 0 ? Fmt.money(c.quotedPrice) : "-", 9)
            let paid = pad(Fmt.money(c.paidAmount), 9)
            let unpaid = c.unpaidAmount > 0 ? Fmt.money(c.unpaidAmount) : "-"
            s += "\(pad("\(i + 1)", 5))\(name)\(phone)\(created)\(photos)\(step)\(quoted)\(paid)\(unpaid)\n"
        }
        let totalQuoted = clients.reduce(0) { $0 + $1.quotedPrice }
        let totalPaid = clients.reduce(0) { $0 + $1.paidAmount }
        let totalUnpaid = clients.reduce(0) { $0 + $1.unpaidAmount }
        s += "\n合计：应收 \(Fmt.money(totalQuoted)) · 已付 \(Fmt.money(totalPaid)) · 未收 \(Fmt.money(totalUnpaid))\n"
        return s
    }

    /// 按显示宽度补空格（中文按两个字符算）
    private static func pad(_ text: String, _ width: Int) -> String {
        var w = 0
        for ch in text.unicodeScalars {
            w += ch.value > 0x2E80 ? 2 : 1
        }
        if w >= width { return text + "  " }
        return text + String(repeating: " ", count: width - w)
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

    // MARK: - 自动备份

    /// 只看文件头是不是 ZIP（PK\x03\x04 / PK\x05\x06 / PK\x07\x08），
    /// 防止用户在文件选择器里选到别的文件
    static func looksLikeZip(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        let head = h.readData(ofLength: 4)
        guard head.count == 4 else { return false }
        let b = [UInt8](head)
        return b[0] == 0x50 && b[1] == 0x4B
            && (b[2] == 0x03 || b[2] == 0x05 || b[2] == 0x07)
    }

    /// 把刚生成的备份改名成「自动备份」，方便和手动备份区分
    @discardableResult
    static func markAsAuto(_ url: URL) -> URL {
        let name = url.deletingPathExtension().lastPathComponent
        guard !name.contains("自动备份") else { return url }
        let newName = name.replacingOccurrences(of: "_备份_", with: "_自动备份_")
        let dst = url.deletingLastPathComponent()
            .appendingPathComponent(newName)
            .appendingPathExtension("zip")
        guard dst.path != url.path else { return url }
        try? FileManager.default.removeItem(at: dst)
        do {
            try FileManager.default.moveItem(at: url, to: dst)
            return dst
        } catch {
            return url
        }
    }

    /// 只保留最近 keep 份自动备份，多的删掉
    static func trimAutoBackups(in dir: URL, keep: Int) {
        let fm = FileManager.default
        guard keep > 0,
              let files = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }

        let autos = files
            .filter { $0.pathExtension.lowercased() == "zip" && $0.lastPathComponent.contains("自动备份") }
            .compactMap { u -> (URL, Date)? in
                let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                return (u, d ?? Date())
            }
            .sorted { $0.1 > $1.1 }

        for (u, _) in autos.dropFirst(keep) {
            try? fm.removeItem(at: u)
        }
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
