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
        return Fmt.cnDate(e)
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
        return Fmt.cnDateTime(s)
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
    /// 后台控制的网址显示方式：plain / encrypted
    var urlDisplay: String?
    var apiBase: String?
    var apiBaseEnc: String?

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
        case urlDisplay = "url_display"
        case apiBase = "api_base"
        case apiBaseEnc = "api_base_enc"
    }

    var rechargeOn: Bool { (rechargeEnabled ?? "1") != "0" }
}

struct CloudAuthResult: Codable {
    var token: String
    var member: CloudMember
}

// MARK: - 软件激活

struct CloudLicenseConfig: Codable {
    var required: Bool?
    var notice: String?
    var contact: String?
    var graceDays: Int?
    var serverTime: String?

    enum CodingKeys: String, CodingKey {
        case required, notice, contact
        case graceDays = "grace_days"
        case serverTime = "server_time"
    }
}

struct CloudLicenseRecharge: Codable {
    var claimed: Bool?
    var amount: Double?
    var points: Int?
    var balance: Double?
    var reason: String?
}

struct CloudLicenseRedeem: Codable {
    var licenseKey: String?
    var syncToken: String?
    var deviceID: String?
    var code: String?
    var kind: String?
    var durationText: String?
    var expireAt: String?
    var permanent: Bool?
    var leftText: String?
    var secondsLeft: Int?
    var graceDays: Int?
    var notice: String?
    var contact: String?
    var shopName: String?
    var recharge: CloudLicenseRecharge?
    var tenantID: Int?
    var ownerName: String?
    var ownerPhone: String?
    /// 服务端要求这台设备把云端资料整体恢复一遍（换手机 / 后台点了恢复）
    var restore: Bool?

    enum CodingKeys: String, CodingKey {
        case code, kind, permanent, notice, contact, recharge, restore
        case licenseKey = "license_key"
        case syncToken = "sync_token"
        case deviceID = "device_id"
        case durationText = "duration_text"
        case expireAt = "expire_at"
        case leftText = "left_text"
        case secondsLeft = "seconds_left"
        case graceDays = "grace_days"
        case shopName = "shop_name"
        case tenantID = "tenant_id"
        case ownerName = "owner_name"
        case ownerPhone = "owner_phone"
    }
}

struct CloudLicenseVerify: Codable {
    var active: Bool?
    var code: String?
    var expireAt: String?
    var permanent: Bool?
    var leftText: String?
    var secondsLeft: Int?
    var syncToken: String?
    var graceDays: Int?
    var deviceName: String?
    var serverTime: String?
    var notice: String?
    var contact: String?
    var shopName: String?
    var tenantID: Int?
    var ownerName: String?
    var ownerPhone: String?
    var restore: Bool?

    enum CodingKeys: String, CodingKey {
        case active, code, permanent, notice, contact, restore
        case expireAt = "expire_at"
        case leftText = "left_text"
        case secondsLeft = "seconds_left"
        case syncToken = "sync_token"
        case graceDays = "grace_days"
        case deviceName = "device_name"
        case serverTime = "server_time"
        case shopName = "shop_name"
        case tenantID = "tenant_id"
        case ownerName = "owner_name"
        case ownerPhone = "owner_phone"
    }
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
            /* 默认地址不明文写在这里，由 ServerURL 运行时解出来 */
            return v.isEmpty ? ServerURL.builtin : v
        }
        set { UserDefaults.standard.set(newValue, forKey: "cloud.base") }
    }

    private var endpoint: String {
        var b = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        return b + "/meiyan-api/index.php"
    }

    // MARK: 通用请求

    /// 设备同步凭证：激活后由服务端签发，存在 UserDefaults。
    /// 会员注册/登录这类不带 token 的请求也要带上它，服务端才知道该落到哪个板块。
    private var deviceToken: String {
        UserDefaults.standard.string(forKey: "license.sync.token") ?? ""
    }

    private func authToken(_ explicit: String?) -> String? {
        if let t = explicit, !t.isEmpty { return t }
        let d = deviceToken
        return d.isEmpty ? nil : d
    }

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
        if let t = authToken(token) {
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

    // MARK: 软件激活

    /// 公开配置：决定要不要弹激活页
    func licenseConfig() async throws -> CloudLicenseConfig {
        try await call("license/config", as: CloudLicenseConfig.self)
    }

    /// 兑换激活码：拿到本机授权凭证 + 设备同步凭证
    func licenseRedeem(code: String, name: String, phone: String,
                       deviceID: String, deviceName: String,
                       platform: String, appVersion: String) async throws -> CloudLicenseRedeem {
        try await call("license/redeem", method: "POST",
                       body: ["code": code,
                              "name": name,
                              "phone": phone,
                              "device_id": deviceID,
                              "device_name": deviceName,
                              "platform": platform,
                              "app_version": appVersion],
                       as: CloudLicenseRedeem.self)
    }

    /// 恢复完成后回报服务端，清掉「待恢复」标志
    func licenseRestoreAck(token: String) async {
        try? await callVoid("license/restore-ack", method: "POST", body: [:], token: token)
    }

    /// 启动 / 回前台复核授权
    func licenseVerify(deviceID: String, licenseKey: String, appVersion: String) async throws -> CloudLicenseVerify {
        try await call("license/verify", method: "POST",
                       body: ["device_id": deviceID,
                              "license_key": licenseKey,
                              "app_version": appVersion],
                       as: CloudLicenseVerify.self)
    }

    // MARK: 全店同步（店铺账号）

    /// 同步接口返回的是动态结构，直接拿原始 JSON
    private func callRaw(_ route: String,
                         method: String = "GET",
                         query: [String: String] = [:],
                         body: [String: Any]? = nil,
                         token: String? = nil) async throws -> Any {
        var comps = URLComponents(string: endpoint)
        var items = [URLQueryItem(name: "r", value: route)]
        for (k, v) in query { items.append(URLQueryItem(name: k, value: v)) }
        comps?.queryItems = items
        guard let url = comps?.url else { throw CloudError.message("服务器地址不正确") }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let t = authToken(token) {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        if let b = body {
            req.httpBody = try JSONSerialization.data(withJSONObject: b, options: [])
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: req)
        } catch {
            throw CloudError.network
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudError.message("服务器返回异常，请稍后重试")
        }
        guard (obj["ok"] as? Bool) == true else {
            throw CloudError.message((obj["msg"] as? String) ?? "同步失败")
        }
        return obj["data"] ?? [:]
    }

    struct SyncLoginResult {
        var token: String
        var name: String
        var counts: [String: Int]
    }

    /// 用后台店铺账号登录，换取同步用的 token
    func syncLogin(account: String, password: String) async throws -> SyncLoginResult {
        let raw = try await callRaw("sync/login", method: "POST",
                                    body: ["account": account, "password": password])
        let dict = raw as? [String: Any] ?? [:]
        let token = (dict["token"] as? String) ?? ""
        if token.isEmpty { throw CloudError.message("登录失败，请检查账号密码") }
        let admin = dict["admin"] as? [String: Any] ?? [:]
        var counts: [String: Int] = [:]
        if let c = dict["counts"] as? [String: Any] {
            for (k, v) in c { counts[k] = (v as? NSNumber)?.intValue ?? 0 }
        }
        return SyncLoginResult(token: token,
                               name: (admin["name"] as? String) ?? account,
                               counts: counts)
    }

    /// 拉取云端数据。since 为空则全量。
    func syncPull(since: String?, token: String) async throws -> [String: Any] {
        var q: [String: String] = [:]
        if let s = since, !s.isEmpty { q["since"] = s }
        let raw = try await callRaw("sync/pull", query: q, token: token)
        return raw as? [String: Any] ?? [:]
    }

    /// 推送本地改动
    func syncPush(_ payload: [String: Any], token: String) async throws -> [String: Any] {
        let raw = try await callRaw("sync/push", method: "POST",
                                    body: ["data": payload], token: token)
        return raw as? [String: Any] ?? [:]
    }

    /// 通知云端删除
    func syncDelete(_ payload: [String: Any], token: String) async throws -> [String: Any] {
        let raw = try await callRaw("sync/delete", method: "POST",
                                    body: ["data": payload], token: token)
        return raw as? [String: Any] ?? [:]
    }

    /// 上传一个文件（图片或视频），返回可访问 URL
    func uploadImage(_ data: Data, fileName: String, token: String) async throws -> String {
        guard let url = URL(string: endpoint + "?r=upload") else {
            throw CloudError.message("服务器地址不正确")
        }
        let ext = (fileName as NSString).pathExtension.lowercased()
        let isVideo = ["mp4", "mov", "m4v", "qt"].contains(ext)
        let mime: String
        switch ext {
        case "mp4", "m4v": mime = "video/mp4"
        case "mov", "qt":  mime = "video/quicktime"
        case "png":        mime = "image/png"
        case "gif":        mime = "image/gif"
        case "webp":       mime = "image/webp"
        default:           mime = "image/jpeg"
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        // 视频动辄几十上百 MB，60 秒会超时
        req.timeoutInterval = isVideo ? 900 : 90
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)",
                     forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n"
                        .data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = isVideo ? 900 : 90
        cfg.timeoutIntervalForResource = isVideo ? 1800 : 180
        let session = URLSession(configuration: cfg)

        // 大文件（视频）落盘再流式上传，避免 multipart 在内存里翻倍把 App 撑爆
        var tmpURL: URL?
        defer { if let t = tmpURL { try? FileManager.default.removeItem(at: t) } }

        let respData: Data
        do {
            if body.count > 24 * 1024 * 1024 {
                let t = FileManager.default.temporaryDirectory
                    .appendingPathComponent("up-\(UUID().uuidString).part")
                try body.write(to: t)
                tmpURL = t
                body = Data()   // 及时释放
                (respData, _) = try await session.upload(for: req, fromFile: t)
            } else {
                req.httpBody = body
                (respData, _) = try await session.data(for: req)
            }
        } catch {
            throw CloudError.network
        }
        guard let obj = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
              (obj["ok"] as? Bool) == true,
              let d = obj["data"] as? [String: Any],
              let path = d["url"] as? String else {
            throw CloudError.message(isVideo ? "视频上传失败" : "图片上传失败")
        }
        return path
    }
}
