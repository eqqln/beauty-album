import Foundation
import SwiftUI
import UIKit

/// 软件授权状态
enum LicenseState: Equatable {
    /// 启动后正在向服务器复核
    case checking
    /// 未激活 / 已停用 / 已过期，必须输入激活码
    case inactive
    /// 已激活，可以进主界面
    case active
}

/// 激活码闸门：装完 App 第一次打开必须兑换激活码，没激活进不了主界面。
///
/// 兑换成功后服务端同时签发两样东西：
/// - `license_key`：本机授权凭证，启动时用它复核
/// - `sync_token`：设备同步凭证，直接交给 SyncService，之后所有资料全自动同步，
///   不需要再手动登录一次店铺账号
final class LicenseService: ObservableObject {
    static let shared = LicenseService()

    // MARK: 对外状态

    @Published private(set) var state: LicenseState = .checking
    @Published var notice: String = "本软件需激活后使用，激活码可向门店索取。"
    @Published var contact: String = "请联系门店获取激活码"
    @Published var shopName: String = ""
    @Published var leftText: String = ""
    @Published var expireAt: String = ""
    @Published var permanent: Bool = false
    @Published var codeText: String = ""
    @Published var busy: Bool = false
    @Published var errorText: String?
    /// 服务端是否要求激活；关掉后谁都能用（老客户应急）
    @Published var required: Bool = true

    // MARK: 存储键

    private let kDevice = "license.device.id"
    private let kKey    = "license.key"
    private let kToken  = "license.sync.token"
    private let kCode   = "license.code"
    private let kExpire = "license.expire"
    private let kPerm   = "license.permanent"
    private let kLeft   = "license.left"
    private let kGrace  = "license.grace"
    private let kShop   = "license.shop"

    private var bootstrapped = false

    private init() {
        codeText = UserDefaults.standard.string(forKey: kCode) ?? ""
        expireAt = UserDefaults.standard.string(forKey: kExpire) ?? ""
        permanent = UserDefaults.standard.bool(forKey: kPerm)
        leftText = UserDefaults.standard.string(forKey: kLeft) ?? ""
        shopName = UserDefaults.standard.string(forKey: kShop) ?? ""
    }

    // MARK: 本机标识

    /// 稳定的设备编号：首次启动生成 UUID 存本地，重装才会变
    var deviceID: String {
        if let v = UserDefaults.standard.string(forKey: kDevice), !v.isEmpty { return v }
        let v = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        UserDefaults.standard.set(v, forKey: kDevice)
        return v
    }

    var deviceShort: String { String(deviceID.suffix(8)) }

    private var cachedKey: String {
        UserDefaults.standard.string(forKey: kKey) ?? ""
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v)(\(b))"
    }

    private var platform: String {
        "iOS \(UIDevice.current.systemVersion)"
    }

    private var deviceName: String {
        let n = UIDevice.current.name
        return n.isEmpty ? "iPhone" : n
    }

    // MARK: 启动复核

    /// App 启动时调一次：先看本地授权，再向服务器复核
    @MainActor
    func bootstrap() async {
        if bootstrapped, state != .checking { return }
        bootstrapped = true

        // 1. 先读公开配置，拿到提示文案和「是否强制激活」
        if let cfg = try? await CloudAPI.shared.licenseConfig() {
            required = cfg.required ?? true
            if let s = cfg.notice, !s.isEmpty { notice = s }
            if let s = cfg.contact, !s.isEmpty { contact = s }
        }

        // 2. 服务端关掉了闸门 → 直接放行
        guard required else {
            state = .active
            return
        }

        // 3. 本地没有凭证 → 进激活页
        guard !cachedKey.isEmpty else {
            state = .inactive
            return
        }

        // 4. 本地到期判断：过了有效期且超出宽限期，直接拦下（离线也拦）
        if isLocallyExpired() {
            state = .inactive
            errorText = "软件授权已到期，请输入新的激活码充能续期"
            return
        }

        // 5. 有凭证先放行，再静默向服务器复核；失败（停用/过期）才踢回激活页
        state = .active
        await verifyQuietly()
    }

    /// 回到前台 / 启动后的静默复核
    @MainActor
    func verifyQuietly() async {
        let key = cachedKey
        guard !key.isEmpty else { return }
        do {
            let r = try await CloudAPI.shared.licenseVerify(deviceID: deviceID,
                                                           licenseKey: key,
                                                           appVersion: appVersion)
            apply(r)
            state = .active
            errorText = nil
        } catch {
            // 网络问题不锁人，只有服务端明确拒绝（停用 / 过期 / 解绑）才锁
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if msg.contains("激活") || msg.contains("停用") || msg.contains("到期") || msg.contains("解绑") {
                state = .inactive
                errorText = msg
            }
        }
    }

    /// 手动「重新激活」（激活页上的复核按钮）
    @MainActor
    func refresh() async {
        guard !cachedKey.isEmpty else { return }
        busy = true
        defer { busy = false }
        await verifyQuietly()
        if state == .active { errorText = nil }
    }

    // MARK: 兑换激活码

    @MainActor
    func redeem(_ raw: String) async {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            errorText = "请输入激活码"
            return
        }
        busy = true
        errorText = nil
        defer { busy = false }

        do {
            let r = try await CloudAPI.shared.licenseRedeem(code: code,
                                                            deviceID: deviceID,
                                                            deviceName: deviceName,
                                                            platform: platform,
                                                            appVersion: appVersion)
            let d = UserDefaults.standard
            d.set(r.licenseKey, forKey: kKey)
            d.set(r.code ?? code, forKey: kCode)
            d.set(r.expireAt ?? "", forKey: kExpire)
            d.set(r.permanent ?? false, forKey: kPerm)
            d.set(r.leftText ?? "", forKey: kLeft)
            d.set(r.graceDays ?? 7, forKey: kGrace)
            if let s = r.shopName, !s.isEmpty {
                shopName = s
                d.set(s, forKey: kShop)
            }
            codeText = r.code ?? code
            expireAt = r.expireAt ?? ""
            permanent = r.permanent ?? false
            leftText = r.leftText ?? ""
            if let s = r.notice, !s.isEmpty { notice = s }
            if let s = r.contact, !s.isEmpty { contact = s }

            // 设备凭证直接接管同步：激活完就开始自动同步，不用再登录一次
            if let token = r.syncToken, !token.isEmpty {
                d.set(token, forKey: kToken)
                SyncService.shared.adopt(token: token, name: r.shopName ?? shopName)
            }

            state = .active

            // 随卡充值的结果提示（有金额/积分才提）
            if let rc = r.recharge, rc.claimed == true, (rc.amount ?? 0) > 0 || (rc.points ?? 0) > 0 {
                let amount = rc.amount ?? 0
                let pts = rc.points ?? 0
                var parts: [String] = []
                if amount > 0 { parts.append("余额 +\(CloudMember.moneyText(amount))") }
                if pts > 0 { parts.append("积分 +\(pts)") }
                notice = "随卡充值已到账：" + parts.joined(separator: "、")
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: 工具

    private func apply(_ r: CloudLicenseVerify) {
        let d = UserDefaults.standard
        if let s = r.syncToken, !s.isEmpty {
            d.set(s, forKey: kToken)
            SyncService.shared.adopt(token: s, name: r.shopName ?? shopName)
        }
        if let s = r.code { codeText = s; d.set(s, forKey: kCode) }
        if let s = r.expireAt { expireAt = s; d.set(s, forKey: kExpire) }
        if let b = r.permanent { permanent = b; d.set(b, forKey: kPerm) }
        if let s = r.leftText { leftText = s; d.set(s, forKey: kLeft) }
        if let n = r.graceDays { d.set(n, forKey: kGrace) }
        if let s = r.notice, !s.isEmpty { notice = s }
        if let s = r.contact, !s.isEmpty { contact = s }
        if let s = r.shopName, !s.isEmpty { shopName = s; d.set(s, forKey: kShop) }
    }

    /// 本地判断是否已过期（含宽限期）。永久授权或没写到期时间视为不过期
    private func isLocallyExpired() -> Bool {
        if permanent { return false }
        guard !expireAt.isEmpty else { return false }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: expireAt) else { return false }
        let grace = Double(UserDefaults.standard.integer(forKey: kGrace))
        return Date() > d.addingTimeInterval(max(0, grace) * 86400)
    }
}
