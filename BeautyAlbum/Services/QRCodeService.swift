import Foundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum QRCodeService {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// 生成二维码图像
    static func make(_ text: String, scale: CGFloat = 10) -> UIImage? {
        guard !text.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// 收款二维码的载荷：优先用商户收款链接，否则生成一段可读的收款信息文本
    static func paymentPayload(shop: String, amount: Double, clientName: String,
                               link: String) -> String {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if amount > 0 {
                let sep = trimmed.contains("?") ? "&" : "?"
                return trimmed + sep + "amount=" + String(format: "%.2f", amount)
            }
            return trimmed
        }
        let amountText = amount > 0 ? String(format: "%.2f", amount) : "待输入"
        return """
        收款方：\(shop)
        客户：\(clientName.isEmpty ? "散客" : clientName)
        金额：¥\(amountText)
        """
    }
}
