import Foundation
import UIKit

// MARK: - 照片阶段（使用前 / 使用后）

enum PhotoPhase: String, Codable, CaseIterable, Identifiable {
    case before
    case after

    var id: String { rawValue }
}

// MARK: - 媒体类型（照片 / 视频）

enum PhotoKind: String, Codable, CaseIterable {
    case image
    case video

    var isVideo: Bool { self == .video }
    var label: String { self == .video ? "视频" : "照片" }
}

// MARK: - 照片 / 视频

struct PhotoItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// 磁盘上的文件名。照片是 "<photoID>.jpg"，视频是 "<photoID>.mp4"，都放在 media/<clientID>/ 下
    var fileName: String = ""
    var phase: PhotoPhase = .before
    /// 部位 / 项目标签，例如「面部」「颈部」
    var tag: String = ""
    /// 单条备注
    var caption: String = ""
    var createdAt: Date = Date()
    /// 照片还是视频
    var kind: PhotoKind = .image
    /// 视频时长（秒），照片为 0
    var duration: Double = 0
    /// 视频封面图文件名（jpg），照片为空
    var thumbName: String = ""

    var isVideo: Bool { kind == .video }

    /// 列表上显示用：视频显示 0:12
    var durationText: String {
        guard isVideo, duration > 0 else { return "" }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    init(id: UUID = UUID(), fileName: String = "", phase: PhotoPhase = .before,
         tag: String = "", caption: String = "", createdAt: Date = Date(),
         kind: PhotoKind = .image, duration: Double = 0, thumbName: String = "") {
        self.id = id
        self.fileName = fileName
        self.phase = phase
        self.tag = tag
        self.caption = caption
        self.createdAt = createdAt
        self.kind = kind
        self.duration = duration
        self.thumbName = thumbName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        phase = try c.decodeIfPresent(PhotoPhase.self, forKey: .phase) ?? .before
        tag = try c.decodeIfPresent(String.self, forKey: .tag) ?? ""
        caption = try c.decodeIfPresent(String.self, forKey: .caption) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        kind = try c.decodeIfPresent(PhotoKind.self, forKey: .kind) ?? .image
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        thumbName = try c.decodeIfPresent(String.self, forKey: .thumbName) ?? ""
    }
}

// MARK: - 流程步骤

struct StepItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String = ""
    var done: Bool = false
    var doneAt: Date? = nil
    var note: String = ""

    init(id: UUID = UUID(), title: String = "", done: Bool = false,
         doneAt: Date? = nil, note: String = "") {
        self.id = id
        self.title = title
        self.done = done
        self.doneAt = doneAt
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        doneAt = try c.decodeIfPresent(Date.self, forKey: .doneAt)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

// MARK: - 文本记录

struct TextNote: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var content: String = ""
    var createdAt: Date = Date()

    init(id: UUID = UUID(), content: String = "", createdAt: Date = Date()) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

// MARK: - 收款记录

struct PaymentRecord: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var amount: Double = 0
    var method: String = "微信"
    var note: String = ""
    var createdAt: Date = Date()

    init(id: UUID = UUID(), amount: Double = 0, method: String = "微信",
         note: String = "", createdAt: Date = Date()) {
        self.id = id
        self.amount = amount
        self.method = method
        self.note = note
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        amount = try c.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        method = try c.decodeIfPresent(String.self, forKey: .method) ?? "微信"
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

// MARK: - 客户（= 相册）

/// 账单状态
enum PaymentStatus: String, Codable {
    case none = "未设应收"
    case unpaid = "未付款"
    case partial = "部分付款"
    case paid = "已结清"

    var isSettled: Bool { self == .paid }
}

struct Client: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var phone: String = ""
    /// 客户备注（长期信息）
    var note: String = ""
    /// 应收总额（套餐价 / 疗程价），0 表示未设置
    var quotedPrice: Double = 0
    var createdAt: Date = Date()
    var photos: [PhotoItem] = []
    var steps: [StepItem] = []
    var notes: [TextNote] = []
    var payments: [PaymentRecord] = []
    /// 产品领取记录
    var claims: [ProductClaim] = []

    init(id: UUID = UUID(), name: String = "", phone: String = "", note: String = "",
         quotedPrice: Double = 0, createdAt: Date = Date(), photos: [PhotoItem] = [],
         steps: [StepItem] = [], notes: [TextNote] = [], payments: [PaymentRecord] = [],
         claims: [ProductClaim] = []) {
        self.id = id
        self.name = name
        self.phone = phone
        self.note = note
        self.quotedPrice = quotedPrice
        self.createdAt = createdAt
        self.photos = photos
        self.steps = steps
        self.notes = notes
        self.payments = payments
        self.claims = claims
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        quotedPrice = try c.decodeIfPresent(Double.self, forKey: .quotedPrice) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        photos = try c.decodeIfPresent([PhotoItem].self, forKey: .photos) ?? []
        steps = try c.decodeIfPresent([StepItem].self, forKey: .steps) ?? []
        notes = try c.decodeIfPresent([TextNote].self, forKey: .notes) ?? []
        payments = try c.decodeIfPresent([PaymentRecord].self, forKey: .payments) ?? []
        claims = try c.decodeIfPresent([ProductClaim].self, forKey: .claims) ?? []
    }

    // MARK: 派生属性

    var beforePhotos: [PhotoItem] { photos.filter { $0.phase == .before } }
    var afterPhotos: [PhotoItem] { photos.filter { $0.phase == .after } }

    var doneStepCount: Int { steps.filter(\.done).count }

    /// 顺序推进时已完成的环节数：从第一步往后数，遇到第一个没打勾的就停
    var sequentialDoneCount: Int { steps.prefix(while: { $0.done }).count }

    /// 当前进行到第几步（从 1 起算，全部完成时等于总步数）
    var currentStepNumber: Int {
        guard !steps.isEmpty else { return 0 }
        return min(steps.count, sequentialDoneCount + 1)
    }

    /// 六个环节是不是全部走完了
    var isAllStepsDone: Bool {
        !steps.isEmpty && sequentialDoneCount == steps.count
    }

    var progress: Double {
        guard !steps.isEmpty else { return 0 }
        return Double(sequentialDoneCount) / Double(steps.count)
    }

    /// 当前所处环节，例如「第 2 步 · 第 1 次护理」
    var currentStageTitle: String {
        guard !steps.isEmpty else { return "未设置流程" }
        if isAllStepsDone { return "已完成全部 \(steps.count) 步" }
        return "第 \(currentStepNumber) 步 · \(steps[currentStepNumber - 1].title)"
    }

    /// 已付金额
    var totalPaid: Double { payments.reduce(0) { $0 + $1.amount } }
    var paidAmount: Double { totalPaid }

    /// 未付金额
    var unpaidAmount: Double { max(0, quotedPrice - paidAmount) }

    /// 多收 / 预存
    var overpaidAmount: Double { max(0, paidAmount - quotedPrice) }

    var paymentStatus: PaymentStatus {
        if quotedPrice <= 0 {
            return payments.isEmpty ? .none : .paid
        }
        if paidAmount <= 0 { return .unpaid }
        if paidAmount + 0.001 >= quotedPrice { return .paid }
        return .partial
    }

    /// 收款进度 0~1
    var paymentProgress: Double {
        guard quotedPrice > 0 else { return payments.isEmpty ? 0 : 1 }
        return min(1, paidAmount / quotedPrice)
    }

    /// 列表封面：优先使用第一张「使用前」照片
    var coverPhoto: PhotoItem? { photos.first }
}

// MARK: - 老师 / 技师

struct Teacher: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    /// 职位，例如「高级美容师」
    var title: String = ""
    var phone: String = ""
    var intro: String = ""
    /// 擅长项目标签
    var tags: [String] = []
    /// 是否接受预约
    var available: Bool = true
    /// 展示排序，越小越靠前
    var sortIndex: Int = 0
    var createdAt: Date = Date()

    init(id: UUID = UUID(), name: String = "", title: String = "", phone: String = "",
         intro: String = "", tags: [String] = [], available: Bool = true,
         sortIndex: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.title = title
        self.phone = phone
        self.intro = intro
        self.tags = tags
        self.available = available
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        intro = try c.decodeIfPresent(String.self, forKey: .intro) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        available = try c.decodeIfPresent(Bool.self, forKey: .available) ?? true
        sortIndex = try c.decodeIfPresent(Int.self, forKey: .sortIndex) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    var displayTitle: String { title.isEmpty ? "美容师" : title }
}

// MARK: - 预约

enum AppointmentStatus: String, Codable, CaseIterable, Identifiable {
    case pending = "待确认"
    case confirmed = "已确认"
    case done = "已完成"
    case cancelled = "已取消"

    var id: String { rawValue }

    var color: (r: Double, g: Double, b: Double) {
        switch self {
        case .pending: return (0.86, 0.58, 0.24)
        case .confirmed: return (0.68, 0.36, 0.43)
        case .done: return (0.36, 0.60, 0.45)
        case .cancelled: return (0.62, 0.58, 0.59)
        }
    }
}

struct Appointment: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var teacherID: UUID = UUID()
    /// 冗余保存老师姓名，老师被删除后预约记录仍可读
    var teacherName: String = ""
    var clientID: UUID? = nil
    var clientName: String = ""
    var phone: String = ""
    var service: String = ""
    var date: Date = Date()
    var durationMinutes: Int = 60
    var status: AppointmentStatus = .pending
    var note: String = ""
    var createdAt: Date = Date()

    init(id: UUID = UUID(), teacherID: UUID = UUID(), teacherName: String = "",
         clientID: UUID? = nil, clientName: String = "", phone: String = "",
         service: String = "", date: Date = Date(), durationMinutes: Int = 60,
         status: AppointmentStatus = .pending, note: String = "", createdAt: Date = Date()) {
        self.id = id
        self.teacherID = teacherID
        self.teacherName = teacherName
        self.clientID = clientID
        self.clientName = clientName
        self.phone = phone
        self.service = service
        self.date = date
        self.durationMinutes = durationMinutes
        self.status = status
        self.note = note
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        teacherID = try c.decodeIfPresent(UUID.self, forKey: .teacherID) ?? UUID()
        teacherName = try c.decodeIfPresent(String.self, forKey: .teacherName) ?? ""
        clientID = try c.decodeIfPresent(UUID.self, forKey: .clientID)
        clientName = try c.decodeIfPresent(String.self, forKey: .clientName) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        service = try c.decodeIfPresent(String.self, forKey: .service) ?? ""
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 60
        status = try c.decodeIfPresent(AppointmentStatus.self, forKey: .status) ?? .pending
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    var isUpcoming: Bool { date >= Date() && status != .cancelled && status != .done }
}

// MARK: - 产品

struct ProductSpec: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// 规格名，例如「30ml」「50ml / 加强版」
    var name: String = ""
    var price: Double = 0
    var stock: Int = 0

    init(id: UUID = UUID(), name: String = "", price: Double = 0, stock: Int = 0) {
        self.id = id
        self.name = name
        self.price = price
        self.stock = stock
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        price = try c.decodeIfPresent(Double.self, forKey: .price) ?? 0
        stock = try c.decodeIfPresent(Int.self, forKey: .stock) ?? 0
    }

    var displayName: String { name.isEmpty ? "默认规格" : name }
}

struct Product: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var brand: String = ""
    /// 分类，例如「精华」「面膜」「仪器」
    var category: String = ""
    var intro: String = ""
    var specs: [ProductSpec] = []
    /// 使用步骤
    var usageSteps: [String] = []
    /// 适用阶段，对应客户流程里的环节名
    var stage: String = ""
    /// 多张产品图的文件名
    var imageNames: [String] = []
    var createdAt: Date = Date()

    init(id: UUID = UUID(), name: String = "", brand: String = "", category: String = "",
         intro: String = "", specs: [ProductSpec] = [], usageSteps: [String] = [],
         stage: String = "", imageNames: [String] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.brand = brand
        self.category = category
        self.intro = intro
        self.specs = specs
        self.usageSteps = usageSteps
        self.stage = stage
        self.imageNames = imageNames
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        brand = try c.decodeIfPresent(String.self, forKey: .brand) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        intro = try c.decodeIfPresent(String.self, forKey: .intro) ?? ""
        specs = try c.decodeIfPresent([ProductSpec].self, forKey: .specs) ?? []
        usageSteps = try c.decodeIfPresent([String].self, forKey: .usageSteps) ?? []
        stage = try c.decodeIfPresent(String.self, forKey: .stage) ?? ""
        imageNames = try c.decodeIfPresent([String].self, forKey: .imageNames) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    var priceRange: String {
        let prices = specs.map(\.price).filter { $0 > 0 }
        guard let min = prices.min(), let max = prices.max() else { return "价格未设置" }
        if min == max { return Fmt.money(min) }
        return "\(Fmt.money(min)) ~ \(Fmt.money(max))"
    }

    var totalStock: Int { specs.reduce(0) { $0 + $1.stock } }
}

struct ProductClaim: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var productID: UUID = UUID()
    /// 冗余保存产品名，产品被删除后记录仍可读
    var productName: String = ""
    var specName: String = ""
    var quantity: Int = 1
    var claimed: Bool = false
    var claimedAt: Date? = nil
    var note: String = ""
    var createdAt: Date = Date()

    init(id: UUID = UUID(), productID: UUID = UUID(), productName: String = "",
         specName: String = "", quantity: Int = 1, claimed: Bool = false,
         claimedAt: Date? = nil, note: String = "", createdAt: Date = Date()) {
        self.id = id
        self.productID = productID
        self.productName = productName
        self.specName = specName
        self.quantity = quantity
        self.claimed = claimed
        self.claimedAt = claimedAt
        self.note = note
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        productID = try c.decodeIfPresent(UUID.self, forKey: .productID) ?? UUID()
        productName = try c.decodeIfPresent(String.self, forKey: .productName) ?? ""
        specName = try c.decodeIfPresent(String.self, forKey: .specName) ?? ""
        quantity = try c.decodeIfPresent(Int.self, forKey: .quantity) ?? 1
        claimed = try c.decodeIfPresent(Bool.self, forKey: .claimed) ?? false
        claimedAt = try c.decodeIfPresent(Date.self, forKey: .claimedAt)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

// MARK: - 代理等级

enum AgentLevel: String, Codable, CaseIterable, Identifiable {
    case partner = "合伙人"
    case general = "总代"
    case first = "一级代理"
    case second = "二级代理"
    case retail = "零售"

    var id: String { rawValue }

    /// 默认拿货折扣，0.6 = 6 折
    var defaultDiscount: Double {
        switch self {
        case .partner: return 0.45
        case .general: return 0.50
        case .first: return 0.60
        case .second: return 0.70
        case .retail: return 1.00
        }
    }

    /// 等级高低，数字越小级别越高，用于上级校验
    var rank: Int {
        switch self {
        case .partner: return 0
        case .general: return 1
        case .first: return 2
        case .second: return 3
        case .retail: return 4
        }
    }
}

// MARK: - 代理拿货记录

struct AgentOrder: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var productID: UUID? = nil
    /// 冗余保存产品名，产品被删除后记录仍可读
    var productName: String = ""
    var specName: String = ""
    var quantity: Int = 1
    var unitPrice: Double = 0
    var paid: Double = 0
    var note: String = ""
    /// 拿货时间，可改
    var createdAt: Date = Date()

    init(id: UUID = UUID(), productID: UUID? = nil, productName: String = "",
         specName: String = "", quantity: Int = 1, unitPrice: Double = 0,
         paid: Double = 0, note: String = "", createdAt: Date = Date()) {
        self.id = id
        self.productID = productID
        self.productName = productName
        self.specName = specName
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.paid = paid
        self.note = note
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        productID = try c.decodeIfPresent(UUID.self, forKey: .productID)
        productName = try c.decodeIfPresent(String.self, forKey: .productName) ?? ""
        specName = try c.decodeIfPresent(String.self, forKey: .specName) ?? ""
        quantity = try c.decodeIfPresent(Int.self, forKey: .quantity) ?? 1
        unitPrice = try c.decodeIfPresent(Double.self, forKey: .unitPrice) ?? 0
        paid = try c.decodeIfPresent(Double.self, forKey: .paid) ?? 0
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    /// 本单金额 = 数量 × 单价
    var amount: Double { Double(max(0, quantity)) * unitPrice }
    /// 本单未结
    var unpaid: Double { max(0, amount - paid) }
    var displayName: String { productName.isEmpty ? "未填产品" : productName }
}

// MARK: - 代理商

struct Agent: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var phone: String = ""
    var wechat: String = ""
    var level: AgentLevel = .first
    /// 地区 / 门店
    var region: String = ""
    /// 拿货折扣，0.6 = 6 折；1.0 = 不打折
    var discount: Double = 0.6

    /// 上级代理
    var parentID: UUID? = nil
    /// 冗余保存上级姓名，上级被删除后仍可读
    var parentName: String = ""

    /// 名下客户（人物关系）
    var clientIDs: [UUID] = []
    /// 拿货记录
    var orders: [AgentOrder] = []

    var note: String = ""
    /// 加入 / 建档时间，可改
    var joinedAt: Date = Date()

    init(id: UUID = UUID(), name: String = "", phone: String = "", wechat: String = "",
         level: AgentLevel = .first, region: String = "", discount: Double = 0.6,
         parentID: UUID? = nil, parentName: String = "", clientIDs: [UUID] = [],
         orders: [AgentOrder] = [], note: String = "", joinedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.phone = phone
        self.wechat = wechat
        self.level = level
        self.region = region
        self.discount = discount
        self.parentID = parentID
        self.parentName = parentName
        self.clientIDs = clientIDs
        self.orders = orders
        self.note = note
        self.joinedAt = joinedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        wechat = try c.decodeIfPresent(String.self, forKey: .wechat) ?? ""
        level = try c.decodeIfPresent(AgentLevel.self, forKey: .level) ?? .first
        region = try c.decodeIfPresent(String.self, forKey: .region) ?? ""
        discount = try c.decodeIfPresent(Double.self, forKey: .discount) ?? 0.6
        parentID = try c.decodeIfPresent(UUID.self, forKey: .parentID)
        parentName = try c.decodeIfPresent(String.self, forKey: .parentName) ?? ""
        clientIDs = try c.decodeIfPresent([UUID].self, forKey: .clientIDs) ?? []
        orders = try c.decodeIfPresent([AgentOrder].self, forKey: .orders) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        joinedAt = try c.decodeIfPresent(Date.self, forKey: .joinedAt) ?? Date()
    }

    // MARK: 派生属性

    /// 累计拿货数量
    var totalQuantity: Int { orders.reduce(0) { $0 + max(0, $1.quantity) } }
    /// 累计拿货金额
    var totalAmount: Double { orders.reduce(0) { $0 + $1.amount } }
    /// 累计已付
    var totalPaid: Double { orders.reduce(0) { $0 + $1.paid } }
    /// 累计未结
    var totalUnpaid: Double { orders.reduce(0) { $0 + $1.unpaid } }
    var orderCount: Int { orders.count }
    var lastOrderAt: Date? { orders.map(\.createdAt).max() }

    /// 折扣文字，例如「6 折」
    var discountText: String {
        if discount >= 0.999 { return "不打折" }
        let zhe = discount * 10
        if zhe == zhe.rounded() { return "\(Int(zhe)) 折" }
        return String(format: "%.1f 折", zhe)
    }

    var displayRegion: String { region.isEmpty ? "未填地区" : region }

    /// 头像首字
    var initial: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard let f = n.first else { return "代" }
        return String(f)
    }

    /// 是否已建档超过 N 天
    func daysSinceJoined(now: Date = Date()) -> Int {
        let cal = Calendar.current
        let d = cal.dateComponents([.day], from: cal.startOfDay(for: joinedAt),
                                   to: cal.startOfDay(for: now)).day ?? 0
        return max(0, d)
    }
}

// MARK: - 功能开关

struct FeatureFlags: Codable, Equatable {
    var teachers: Bool = true
    var appointments: Bool = true
    var products: Bool = true
    var payments: Bool = true
    var compare: Bool = true
    var steps: Bool = true
    var notes: Bool = true
    var backup: Bool = true

    // MARK: 代理模块（总开关 + 四项子功能，都能单独关）
    var agents: Bool = true
    /// 父级关系：显示上级与下级代理
    var agentParent: Bool = true
    /// 数量：拿货数量与件数统计
    var agentQuantity: Bool = true
    /// 人物关系：代理名下的客户
    var agentRelation: Bool = true
    /// 时间：加入时间、拿货时间
    var agentTime: Bool = true

    /// 会员账号（注册 / 登录 / 套餐）
    var account: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        teachers = try c.decodeIfPresent(Bool.self, forKey: .teachers) ?? true
        appointments = try c.decodeIfPresent(Bool.self, forKey: .appointments) ?? true
        products = try c.decodeIfPresent(Bool.self, forKey: .products) ?? true
        payments = try c.decodeIfPresent(Bool.self, forKey: .payments) ?? true
        compare = try c.decodeIfPresent(Bool.self, forKey: .compare) ?? true
        steps = try c.decodeIfPresent(Bool.self, forKey: .steps) ?? true
        notes = try c.decodeIfPresent(Bool.self, forKey: .notes) ?? true
        backup = try c.decodeIfPresent(Bool.self, forKey: .backup) ?? true

        agents = try c.decodeIfPresent(Bool.self, forKey: .agents) ?? true
        agentParent = try c.decodeIfPresent(Bool.self, forKey: .agentParent) ?? true
        agentQuantity = try c.decodeIfPresent(Bool.self, forKey: .agentQuantity) ?? true
        agentRelation = try c.decodeIfPresent(Bool.self, forKey: .agentRelation) ?? true
        agentTime = try c.decodeIfPresent(Bool.self, forKey: .agentTime) ?? true
        account = try c.decodeIfPresent(Bool.self, forKey: .account) ?? true
    }
}

// MARK: - 首页客户列表样式

/// 首页客户列表的两种排列：竖排一行一个 / 横排网格多列
enum ClientListLayout: String, Codable, CaseIterable, Identifiable {
    case list = "竖排列表"
    case grid = "横排卡片"

    var id: String { rawValue }

    var icon: String { self == .list ? "list.bullet" : "square.grid.2x2" }
}

// MARK: - 全局设置

struct AppSettings: Codable {
    var shopName: String = "我的美容院"
    /// 可自定义的「使用前」文字
    var beforeLabel: String = "使用前"
    /// 可自定义的「使用后」文字
    var afterLabel: String = "使用后"
    /// 微信收款码图片文件名
    var wechatQR: String? = nil
    /// 支付宝收款码图片文件名
    var alipayQR: String? = nil
    /// 商户收款链接（有则生成带金额的二维码）
    var payLink: String = ""
    var payNote: String = "扫码后请输入本次金额"
    /// 新客户默认流程模板
    var stepTemplate: [String] = ["初次咨询", "拍照建档", "第 1 次护理", "第 2 次护理", "第 3 次护理", "疗程结束"]
    /// 密码锁开关
    var lockEnabled: Bool = false
    /// 密码的 SHA256 摘要（不存明文）
    var lockHash: String = ""
    /// 退到后台多少分钟后自动重新上锁
    var autoLockMinutes: Int = 1
    /// 功能模块开关
    var features: FeatureFlags = FeatureFlags()
    /// 首页客户列表排列方式
    var clientLayout: ClientListLayout = .list
    /// 横排时每行几个（2 或 3）
    var clientColumns: Int = 2
    /// 首页最多显示几位客户，0 表示全部
    var homeClientLimit: Int = 0
    /// 首页列表缩略图是否显示封面图（关闭后更省内存）
    var showClientCover: Bool = true

    // MARK: 自动备份

    /// 是否开启自动备份
    var autoBackupEnabled: Bool = false
    /// 每隔几天备份一次
    var autoBackupDays: Int = 5
    /// 备份时刻（0-23）
    var autoBackupHour: Int = 21
    /// 备份分钟（0 或 30）
    var autoBackupMinute: Int = 0
    /// 最多保留几份自动备份
    var autoBackupKeep: Int = 5
    /// 上次自动备份完成的时间
    var lastAutoBackupAt: Date? = nil

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shopName = try c.decodeIfPresent(String.self, forKey: .shopName) ?? "我的美容院"
        beforeLabel = try c.decodeIfPresent(String.self, forKey: .beforeLabel) ?? "使用前"
        afterLabel = try c.decodeIfPresent(String.self, forKey: .afterLabel) ?? "使用后"
        wechatQR = try c.decodeIfPresent(String.self, forKey: .wechatQR)
        alipayQR = try c.decodeIfPresent(String.self, forKey: .alipayQR)
        payLink = try c.decodeIfPresent(String.self, forKey: .payLink) ?? ""
        payNote = try c.decodeIfPresent(String.self, forKey: .payNote) ?? "扫码后请输入本次金额"
        stepTemplate = try c.decodeIfPresent([String].self, forKey: .stepTemplate)
            ?? ["初次咨询", "拍照建档", "第 1 次护理", "第 2 次护理", "第 3 次护理", "疗程结束"]
        lockEnabled = try c.decodeIfPresent(Bool.self, forKey: .lockEnabled) ?? false
        lockHash = try c.decodeIfPresent(String.self, forKey: .lockHash) ?? ""
        autoLockMinutes = try c.decodeIfPresent(Int.self, forKey: .autoLockMinutes) ?? 1
        features = try c.decodeIfPresent(FeatureFlags.self, forKey: .features) ?? FeatureFlags()
        clientLayout = try c.decodeIfPresent(ClientListLayout.self, forKey: .clientLayout) ?? .list
        let cols = try c.decodeIfPresent(Int.self, forKey: .clientColumns) ?? 2
        clientColumns = min(3, max(2, cols))
        let lim = try c.decodeIfPresent(Int.self, forKey: .homeClientLimit) ?? 0
        homeClientLimit = max(0, lim)
        showClientCover = try c.decodeIfPresent(Bool.self, forKey: .showClientCover) ?? true

        autoBackupEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoBackupEnabled) ?? false
        let days = try c.decodeIfPresent(Int.self, forKey: .autoBackupDays) ?? 5
        autoBackupDays = min(90, max(1, days))
        let hour = try c.decodeIfPresent(Int.self, forKey: .autoBackupHour) ?? 21
        autoBackupHour = min(23, max(0, hour))
        let minute = try c.decodeIfPresent(Int.self, forKey: .autoBackupMinute) ?? 0
        autoBackupMinute = min(59, max(0, minute))
        let keep = try c.decodeIfPresent(Int.self, forKey: .autoBackupKeep) ?? 5
        autoBackupKeep = min(30, max(1, keep))
        lastAutoBackupAt = try c.decodeIfPresent(Date.self, forKey: .lastAutoBackupAt)
    }

    /// 到点了吗：距上次备份满 N 天，且已经过了设定的钟点
    func autoBackupDue(now: Date = Date()) -> Bool {
        guard autoBackupEnabled else { return false }
        let cal = Calendar.current
        let days = max(1, autoBackupDays)

        guard let last = lastAutoBackupAt else {
            // 从没备份过：今天过了钟点就补一次
            guard let slot = cal.date(bySettingHour: autoBackupHour,
                                      minute: autoBackupMinute, second: 0, of: now)
            else { return true }
            return now >= slot
        }

        guard let dueDay = cal.date(byAdding: .day, value: days, to: last) else { return false }
        let slot = cal.date(bySettingHour: autoBackupHour,
                            minute: autoBackupMinute, second: 0, of: dueDay) ?? dueDay
        return now >= slot
    }

    /// 「21:00」这种时刻文字
    var autoBackupTimeText: String {
        String(format: "%02d:%02d", autoBackupHour, autoBackupMinute)
    }

    func label(for phase: PhotoPhase) -> String {
        phase == .before ? beforeLabel : afterLabel
    }
}

// MARK: - 备份快照

struct StoreSnapshot: Codable {
    var version: Int = 4
    var exportedAt: Date = Date()
    var clients: [Client] = []
    var settings: AppSettings? = nil
    var teachers: [Teacher] = []
    var appointments: [Appointment] = []
    var products: [Product] = []
    var agents: [Agent] = []

    init(version: Int = 4, exportedAt: Date = Date(), clients: [Client],
         settings: AppSettings? = nil, teachers: [Teacher] = [],
         appointments: [Appointment] = [], products: [Product] = [],
         agents: [Agent] = []) {
        self.version = version
        self.exportedAt = exportedAt
        self.clients = clients
        self.settings = settings
        self.teachers = teachers
        self.appointments = appointments
        self.products = products
        self.agents = agents
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        clients = try c.decodeIfPresent([Client].self, forKey: .clients) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings)
        teachers = try c.decodeIfPresent([Teacher].self, forKey: .teachers) ?? []
        appointments = try c.decodeIfPresent([Appointment].self, forKey: .appointments) ?? []
        products = try c.decodeIfPresent([Product].self, forKey: .products) ?? []
        agents = try c.decodeIfPresent([Agent].self, forKey: .agents) ?? []
    }
}

// MARK: - UIImage 工具

extension UIImage {
    /// 等比缩放，长边不超过 maxDimension
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension, maxSide > 0 else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - 格式化工具

enum Fmt {
    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmm"
        return f
    }()

    static let timeOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f
    }()

    static let dayOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "dd"
        return f
    }()

    static let monthOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月"
        return f
    }()

    static let weekdayOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEE"
        return f
    }()

    static func time(_ d: Date) -> String { timeOnly.string(from: d) }
    static func dayNumber(_ d: Date) -> String { dayOnly.string(from: d) }
    static func monthLabel(_ d: Date) -> String { monthOnly.string(from: d) }
    static func weekday(_ d: Date) -> String { weekdayOnly.string(from: d) }

    static func money(_ value: Double) -> String {
        if value == value.rounded() {
            return "¥\(Int(value))"
        }
        return String(format: "¥%.2f", value)
    }

    static func fileSize(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}
