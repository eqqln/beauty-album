import Foundation
import CryptoKit

/// 应用锁口令。只保存 SHA256 摘要，不保存明文。
enum LockCode {
    private static let salt = "meirong-album::v1::"
    static let length = 4

    static func hash(_ code: String) -> String {
        let digest = SHA256.hash(data: Data((salt + code).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
