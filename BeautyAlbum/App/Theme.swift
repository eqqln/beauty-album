import SwiftUI
import UIKit

/// 屏幕自适应尺寸：小屏（SE 375pt）到 Pro Max（430pt）统一比例，
/// 卡片高度固定，避免内容长短不一导致网格高低错落。
enum Metrics {
    static var screenWidth: CGFloat {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.screen.bounds.width ?? UIScreen.main.bounds.width
    }

    static var isCompact: Bool { screenWidth < 390 }

    /// 页面左右边距
    static var hPadding: CGFloat { isCompact ? 12 : 16 }
    /// 网格间距
    static var gridSpacing: CGFloat { isCompact ? 8 : 12 }
    /// 两列网格单格宽度
    static var halfCardWidth: CGFloat { (screenWidth - hPadding * 2 - gridSpacing) / 2 }
    /// 两列网格图片高度（按宽度等比，随屏幕缩放）
    static var gridImageHeight: CGFloat { (halfCardWidth * 0.86).rounded() }
    /// 统一卡片高度：所有卡片等高，网格不会高低错落
    static var teacherCardHeight: CGFloat { isCompact ? 188 : 200 }
    static var productCardHeight: CGFloat { gridCoverHeight(columns: 2) + 94 }
    /// 列表行缩略图边长
    static var thumbSize: CGFloat { isCompact ? 56 : 62 }
    /// 数字键盘按键边长（小屏自动缩小，避免锁屏溢出）
    static var keypadKey: CGFloat { isCompact ? 64 : 74 }

    /// 任意列数的单格宽度（首页横排卡片用，2 / 3 列都按屏幕实算）
    static func gridCardWidth(columns: Int) -> CGFloat {
        let n = CGFloat(max(1, columns))
        let total = screenWidth - hPadding * 2 - gridSpacing * (n - 1)
        return (total / n).rounded()
    }

    /// 横排卡片封面高度（按卡片宽度等比，保证所有卡片封面一致）
    static func gridCoverHeight(columns: Int) -> CGFloat {
        (gridCardWidth(columns: columns) * 0.92).rounded()
    }

    /// 首页客户卡片总高度 = 封面 + 文字区（文字区固定 56pt）
    static func clientCardHeight(columns: Int) -> CGFloat {
        gridCoverHeight(columns: columns) + 56
    }
}

/// 美容院场景配色：米白底 + 玫瑰金主色
enum Theme {
    static let rose = Color(red: 0.84, green: 0.53, blue: 0.58)
    static let roseDeep = Color(red: 0.68, green: 0.36, blue: 0.43)
    static let roseLight = Color(red: 0.97, green: 0.89, blue: 0.90)
    static let cream = Color(red: 0.99, green: 0.975, blue: 0.965)
    static let card = Color.white
    static let ink = Color(red: 0.20, green: 0.16, blue: 0.17)
    static let inkSoft = Color(red: 0.42, green: 0.37, blue: 0.38)
    static let muted = Color(red: 0.62, green: 0.58, blue: 0.59)
    static let placeholder = Color(red: 0.95, green: 0.93, blue: 0.93)
    static let line = Color(red: 0.90, green: 0.87, blue: 0.87)

    static let gradTop = LinearGradient(
        colors: [Color(red: 0.98, green: 0.92, blue: 0.92), Color(red: 0.99, green: 0.97, blue: 0.96)],
        startPoint: .top, endPoint: .bottom
    )

    static let gradRose = LinearGradient(
        colors: [Color(red: 0.90, green: 0.60, blue: 0.64), Color(red: 0.78, green: 0.45, blue: 0.53)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

/// 统一的卡片容器
struct CardBox<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.line, lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.035), radius: 8, x: 0, y: 3)
    }
}

/// 小节标题
struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.ink)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
            }
        }
    }
}

/// 阶段徽标（使用前 / 使用后）
struct PhaseBadge: View {
    let text: String
    let phase: PhotoPhase

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(phase == .before ? Color(red: 0.55, green: 0.58, blue: 0.64) : Theme.rose)
            .clipShape(Capsule())
    }
}

/// 进度条
struct ProgressBar: View {
    let value: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.roseLight)
                Capsule()
                    .fill(Theme.gradRose)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

/// 空状态
struct EmptyHint: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var action: (() -> Void)? = nil
    var actionTitle: String = ""

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundColor(Theme.muted)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.inkSoft)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            if let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SoftButtonStyle())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

/// 柔和按钮
struct SoftButtonStyle: ButtonStyle {
    var filled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(filled ? .white : Theme.roseDeep)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                Group {
                    if filled {
                        Theme.gradRose
                    } else {
                        Theme.roseLight
                    }
                }
            )
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 主操作按钮
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.gradRose)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
