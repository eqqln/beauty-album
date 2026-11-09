import Foundation

// MARK: - 云接口数据

struct CloudPackage: Codable, Identifiable, Equatable {
    var id: Int
    var name: String
    var price: Double
    var days: Int
    var items: String?
    var desc: String?
    var badge: String?
    var itemsArr: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, price, days, items, desc, badge
        case itemsArr = "items_arr"
    }

    var lineItems: [String] {
        if let a = itemsArr, !a.isEmpty { return a }
        guard let s = items else { return [] }
        return s.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var priceText: String {
        if price == price.rounded() { return "¥\(Int(price))" }
        return String(format: "¥%.2f", price)
    }
}

struct CloudMember: Codable, Equatable {
    var id: Int
    var name: String
    var phone: String?
    var email: String?
    var level: String?
    var status: String?
    var points: Int?
    var balance: Double?
    var totalRecharge: Double?
    var totalSpent: Double?
    var totalPoints: Int?
    var expireAt: String?
    var package: CloudPackage?

    enum CodingKeys: String, CodingKey {
        case id, name, phone, email, level, status, points, balance, package
        case totalRecharge = "total_recharge"
        case totalSpent = "total_spent"
        case totalPoints = "total_points"
        case expireAt = "expire_at"
    }

    var expireText: String {
        guard let e = expireAt, e.count >= 10 else { return "未开通" }
        return String(e.prefix(10))
    }

    var isExpired: Bool {
        guard let e = expireAt else { return true }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: e) else { return false }
        return d < Date()
    }

    var balanceText: String { CloudMember.moneyText(balance ?? 0) }

    var totalRechargeText: String { CloudMember.moneyText(totalRecharge ?? 0) }

    static func moneyText(_ v: Double) -> String {
        if v == v.rounded() { return "¥\(Int(v))" }
        return String(format: "¥%.2f", v)
    }
}

// MARK: - 充值卡 / 钱包

struct CloudRechargeCard: Codable, Equatable {
    var cardNo: String?
    var label: String?
    var amount: Double?
    var bonus: Double?
    var points: Int?
    var days: Int?

    enum CodingKeys: String, CodingKey {
        case cardNo = "card_no"
        case label, amount, bonus, points, days
    }
}

struct CloudRechargeResult: Codable {
    var member: CloudMember
    var card: CloudRechargeCard?
    var balance: Double?
    var points: Int?
}

struct CloudWalletLog: Codable, Identifiable, Equatable {
    var id: Int
    var kind: String?
    var amount: Double?
    var points: Int?
    var balanceAfter: Double?
    var pointsAfter: Int?
    var ref: String?
    var note: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, amount, points, ref, note
        case balanceAfter = "balance_after"
        case pointsAfter = "points_after"
        case createdAt = "created_at"
    }

    var amountText: String {
        let n = amount ?? 0
        if n == 0 { return "—" }
        let sign = n > 0 ? "+" : "-"
        return sign + CloudMember.moneyText(abs(n))
    }

    var pointsText: String {
        let p = points ?? 0
        if p == 0 { return "—" }
        return (p > 0 ? "+" : "") + "\(p)"
    }

    var timeText: String {
        guard let s = createdAt, s.count >= 16 else { return "" }
        return String(s.prefix(16))
    }
}

struct CloudWallet: Codable {
    var balance: Double?
    var points: Int?
    var totalRecharge: Double?
    var totalSpent: Double?
    var expireAt: String?
    var logs: [CloudWalletLog]?

    enum CodingKeys: String, CodingKey {
        case balance, points, logs
        case totalRecharge = "total_recharge"
        case totalSpent = "total_spent"
        case expireAt = "expire_at"
    }
}

struct CloudSiteInfo: Codable {
    var shopName: String?
    var shopSlogan: String?
    var beforeLabel: String?
    var afterLabel: String?
    var notice: String?
    var appVersion: String?
    var contactPhone: String?
    var rechargeEnabled: String?
    var rechargeNotice: String?

    enum CodingKeys: String, CodingKey {
        case notice
        case shopName = "shop_name"
        case shopSlogan = "shop_slogan"
        case beforeLabel = "before_label"
        case afterLabel = "after_label"
        case appVersion = "app_version"
        case contactPhone = "contact_phone"
        case rechargeEnabled = "recharge_enabled"
        case rechargeNotice = "recharge_notice"
    }

    var rechargeOn: Bool { (rechargeEnabled ?? "1") != "0" }
}

struct CloudAuthResult: Codable {
    var token: String
    var member: CloudMember
}

// MARK: - 云接口客户端

enum CloudError: LocalizedError {
    case message(String)
    case network

    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        case .network: return "网络连接失败，请检查网络后重试"
        }
    }
}

final class CloudAPI {
    static let shared = CloudAPI()

    /// 后台地址，可在「设置 → 服务器与账号」里改
    var baseURL: String {
        get {
            let v = UserDefaults.standard.string(forKey: "cloud.base") ?? ""
            return v.isEmpty ? "https://meiyan.shengka.net" : v
        }
        set { UserDefaults.standard.set(newValue, forKey: "cloud.base") }
    }

    private var endpoint: String {
        var b = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        return b + "/meiyan-api/index.php"
    }

    // MARK: 通用请求

    private func call<T: Decodable>(_ route: String,
                                    method: String = "GET",
                                    query: [String: String] = [:],
                                    body: [String: Any]? = nil,
                                    token: String? = nil,
                                    as type: T.Type) async throws -> T {
        var comps = URLComponents(string: endpoint)
        var items = [URLQueryItem(name: "r", value: route)]
        for (k, v) in query { items.append(URLQueryItem(name: k, value: v)) }
        comps?.queryItems = items
        guard let url = comps?.url else { throw CloudError.message("服务器地址不正确") }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let t = token, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        if let b = body {
            req.httpBody = try JSONSerialization.data(withJSONObject: b, options: [])
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw CloudError.network
        }
        _ = resp

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudError.message("服务器返回异常，请稍后重试")
        }
        let ok = (obj["ok"] as? Bool) ?? false
        let msg = (obj["msg"] as? String) ?? "请求失败"
        guard ok else { throw CloudError.message(msg) }

        guard let payload = obj["data"], !(payload is NSNull) else {
            // 无返回体：用空 JSON 解一个占位类型时可能失败，交给调用方处理
            if let empty = "{}".data(using: .utf8), let v = try? JSONDecoder().decode(T.self, from: empty) {
                return v
            }
            throw CloudError.message(msg)
        }
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])
        return try JSONDecoder().decode(T.self, from: payloadData)
    }

    /// 无返回体的调用（返回 String 忽略）
    private func callVoid(_ route: String, method: String = "POST",
                          body: [String: Any]? = nil, token: String? = nil) async throws {
        struct Empty: Codable {}
        _ = try? await call(route, method: method, body: body, token: token, as: Empty.self)
    }

    // MARK: 站点信息

    func siteInfo() async throws -> CloudSiteInfo {
        try await call("site/info", as: CloudSiteInfo.self)
    }

    // MARK: 套餐

    func packages() async throws -> [CloudPackage] {
        try await call("packages/list", as: [CloudPackage].self)
    }

    // MARK: 会员

    struct SendCodeResult: Codable {
        var sent: Bool?
        var msg: String?
        var debugCode: String?

        enum CodingKeys: String, CodingKey {
            case sent, msg
            case debugCode = "debug_code"
        }
    }

    func sendCode(phone: String) async throws -> SendCodeResult {
        try await call("member/send-code", method: "POST",
                       body: ["phone": phone], as: SendCodeResult.self)
    }

    func register(phone: String, code: String, password: String, name: String) async throws -> CloudAuthResult {
        try await call("member/register", method: "POST",
                       body: ["phone": phone, "code": code, "password": password, "name": name],
                       as: CloudAuthResult.self)
    }

    func login(phone: String, password: String) async throws -> CloudAuthResult {
        try await call("member/login", method: "POST",
                       body: ["phone": phone, "password": password],
                       as: CloudAuthResult.self)
    }

    func me(token: String) async throws -> CloudMember {
        try await call("member/me", token: token, as: CloudMember.self)
    }

    func activate(packageID: Int, token: String) async throws -> CloudMember {
        struct ActivateResult: Codable { var member: CloudMember }
        let r = try await call("member/activate", method: "POST",
                               body: ["package_id": packageID], token: token,
                               as: ActivateResult.self)
        return r.member
    }

    // MARK: 充值卡 / 钱包

    /// 用充值卡充值
    func rechargeCard(cardNo: String, secret: String, token: String) async throws -> CloudRechargeResult {
        try await call("member/recharge", method: "POST",
                       body: ["card_no": cardNo, "card_secret": secret],
                       token: token, as: CloudRechargeResult.self)
    }

    /// 余额与流水
    func wallet(token: String, size: Int = 30) async throws -> CloudWallet {
        try await call("member/wallet", query: ["size": "\(size)"], token: token, as: CloudWallet.self)
    }

    func logout(token: String) async {
        try? await callVoid("member/logout", token: token)
    }
}
