import Foundation

/// 服务器地址的混淆与显示控制。
///
/// 两个目的：
/// 1. 内置默认地址不以明文出现在二进制里 —— 直接 `strings` 搜不到域名；
/// 2. 界面上按后台开关决定显示明文还是混淆串（后台「系统设置 → 网址显示方式」）。
///
/// 算法与服务端 `util.php` 的 `url_encode/url_decode` 必须一致：
/// 逐字节 XOR 固定密钥，再标准 Base64，去掉尾部 `=`。
enum ServerURL {

    /// 与 PHP 端 `url_codec_key()` 相同
    private static let key: [UInt8] = Array("MYA2026K".utf8)

    // MARK: 编解码

    static func encode(_ plain: String) -> String {
        guard !plain.isEmpty else { return "" }
        let bytes = Array(plain.utf8)
        var out = [UInt8]()
        out.reserveCapacity(bytes.count)
        for (i, b) in bytes.enumerated() {
            out.append(b ^ key[i % key.count])
        }
        return Data(out).base64EncodedString()
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    static func decode(_ cipher: String) -> String {
        guard !cipher.isEmpty else { return "" }
        var s = cipher
        let pad = s.count % 4
        if pad > 0 { s += String(repeating: "=", count: 4 - pad) }
        guard let data = Data(base64Encoded: s) else { return "" }
        var out = [UInt8]()
        out.reserveCapacity(data.count)
        for (i, b) in data.enumerated() {
            out.append(b ^ key[i % key.count])
        }
        return String(decoding: out, as: UTF8.self)
    }

    // MARK: 内置地址

    /// `https://meiyan.shengka.net` 的混淆形态。
    /// 改域名时用同一套算法重新算一遍（后台「系统设置」里能看到当前值）。
    private static let builtinCipher = "JS01QkMIGWQgPChLUVwYOCU8L1VbUxglKC0"

    /// 内置默认地址（运行时解出来）
    static var builtin: String {
        let v = decode(builtinCipher)
        return v.isEmpty ? "https://meiyan.shengka.net" : v
    }

    // MARK: 显示方式

    private static let kMode = "site.url.display"

    /// "plain" 或 "encrypted"，由后台下发，本地缓存
    static var displayMode: String {
        get {
            let v = UserDefaults.standard.string(forKey: kMode) ?? ""
            return v == "plain" ? "plain" : "encrypted"
        }
        set {
            UserDefaults.standard.set(newValue == "plain" ? "plain" : "encrypted", forKey: kMode)
        }
    }

    static var isEncrypted: Bool { displayMode != "plain" }

    /// 界面要显示的那串字
    static func display(_ url: String) -> String {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty else { return "" }
        return isEncrypted ? encode(u) : u
    }

    /// 给用户看的说明
    static var modeHint: String {
        isEncrypted
            ? "地址已加密显示，仅供核对，不要手工修改"
            : "地址以明文显示"
    }
}
