import SwiftUI

// MARK: - 密码点阵

struct PinDots: View {
    let count: Int
    let filled: Int
    var isError: Bool = false

    var body: some View {
        HStack(spacing: 18) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i < filled ? (isError ? Color.red : Theme.roseDeep) : Color.clear)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle().stroke(i < filled ? Color.clear : Theme.muted.opacity(0.45),
                                        lineWidth: 1.5)
                    )
                    .scaleEffect(i < filled ? 1.0 : 0.9)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: filled)
            }
        }
    }
}

// MARK: - 数字键盘

struct NumberPad: View {
    var onDigit: (Int) -> Void
    var onDelete: () -> Void

    private let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "del"]]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 22) {
                    ForEach(row, id: \.self) { key in
                        if key.isEmpty {
                            Color.clear.frame(width: Metrics.keypadKey, height: Metrics.keypadKey)
                        } else if key == "del" {
                            Button {
                                onDelete()
                            } label: {
                                Image(systemName: "delete.left")
                                    .font(.system(size: 21, weight: .regular))
                                    .foregroundColor(Theme.inkSoft)
                                    .frame(width: Metrics.keypadKey, height: Metrics.keypadKey)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                if let n = Int(key) { onDigit(n) }
                            } label: {
                                Text(key)
                                    .font(.system(size: 27, weight: .light, design: .rounded))
                                    .foregroundColor(Theme.ink)
                                    .frame(width: Metrics.keypadKey, height: Metrics.keypadKey)
                                    .background(Theme.card)
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 锁屏

struct LockScreen: View {
    @EnvironmentObject var store: Store

    @State private var input = ""
    @State private var errorText: String?
    @State private var shakeOffset: CGFloat = 0
    @State private var showForgot = false

    var body: some View {
        ZStack {
            Theme.gradTop.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 40)

                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Theme.gradRose)
                            .frame(width: 74, height: 74)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 27, weight: .light))
                            .foregroundColor(.white)
                    }
                    Text(store.settings.shopName)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(Theme.ink)
                    Text(errorText ?? "请输入 \(LockCode.length) 位密码")
                        .font(.system(size: 13))
                        .foregroundColor(errorText == nil ? Theme.muted : Color.red)
                }

                PinDots(count: LockCode.length, filled: input.count, isError: errorText != nil)
                    .padding(.top, 26)
                    .offset(x: shakeOffset)

                Spacer(minLength: 20)

                NumberPad(onDigit: tap, onDelete: delete)
                    .padding(.bottom, 18)

                Button("忘记密码？") {
                    showForgot = true
                }
                .font(.system(size: 12))
                .foregroundColor(Theme.muted)
                .padding(.bottom, 26)
            }
        }
        .alert("忘记密码", isPresented: $showForgot) {
            Button("取消", role: .cancel) {}
            Button("清空并重置", role: .destructive) {
                store.resetAllData()
            }
        } message: {
            Text("重置会清除本机全部客户、照片与预约数据，且无法恢复。若之前导出过备份，重置后可在「设置 → 备份与恢复」中导入。")
        }
    }

    private func tap(_ d: Int) {
        guard input.count < LockCode.length else { return }
        errorText = nil
        input += String(d)
        if input.count == LockCode.length {
            verify()
        }
    }

    private func delete() {
        guard !input.isEmpty else { return }
        input.removeLast()
        errorText = nil
    }

    private func verify() {
        let code = input
        // 延迟一点点，让最后一个圆点先画出来
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            if store.unlock(with: code) {
                input = ""
            } else {
                errorText = "密码错误，请重试"
                shake()
                input = ""
            }
        }
    }

    private func shake() {
        withAnimation(.linear(duration: 0.05).repeatCount(6, autoreverses: true)) {
            shakeOffset = 11
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(.linear(duration: 0.05)) { shakeOffset = 0 }
        }
    }
}

// MARK: - 设置 / 修改密码

struct PinSetupSheet: View {
    enum Mode {
        case create
        case change
        case disable
    }

    let mode: Mode
    /// 校验旧密码（修改 / 关闭时用）
    let verifyOld: (String) -> Bool
    let onFinish: (String?) -> Void   // create/change 返回新密码，disable 返回 nil

    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var firstEntry = ""
    @State private var stage = 0
    @State private var errorText: String?

    private var title: String {
        switch mode {
        case .create:
            return stage == 0 ? "设置密码" : "再输一次"
        case .change:
            return stage == 0 ? "输入当前密码" : (stage == 1 ? "设置新密码" : "再输一次")
        case .disable:
            return "输入当前密码"
        }
    }

    private var subtitle: String {
        switch mode {
        case .create:
            return stage == 0 ? "设置 \(LockCode.length) 位数字密码" : "确认刚才的密码"
        case .change:
            return stage == 0 ? "验证后即可修改" : (stage == 1 ? "设置 \(LockCode.length) 位数字密码" : "确认新密码")
        case .disable:
            return "验证后关闭密码锁"
        }
    }

    var body: some View {
        ZStack {
            Theme.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button("取消") { dismiss() }
                        .foregroundColor(Theme.inkSoft)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer(minLength: 20)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.ink)
                    Text(errorText ?? subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(errorText == nil ? Theme.muted : Color.red)
                }

                PinDots(count: LockCode.length, filled: input.count, isError: errorText != nil)
                    .padding(.top, 22)

                Spacer(minLength: 16)

                NumberPad(onDigit: tap, onDelete: {
                    if !input.isEmpty { input.removeLast() }
                    errorText = nil
                })
                .padding(.bottom, 30)
            }
        }
    }

    private func tap(_ d: Int) {
        guard input.count < LockCode.length else { return }
        errorText = nil
        input += String(d)
        if input.count == LockCode.length {
            advance(with: input)
        }
    }

    private func advance(with code: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            switch mode {
            case .disable:
                if verifyOld(code) {
                    onFinish(nil)
                    dismiss()
                } else {
                    errorText = "密码错误"
                    input = ""
                }

            case .create:
                if stage == 0 {
                    firstEntry = code
                    input = ""
                    stage = 1
                } else {
                    if code == firstEntry {
                        onFinish(code)
                        dismiss()
                    } else {
                        errorText = "两次输入不一致，请重新设置"
                        input = ""
                        firstEntry = ""
                        stage = 0
                    }
                }

            case .change:
                if stage == 0 {
                    if verifyOld(code) {
                        input = ""
                        stage = 1
                    } else {
                        errorText = "当前密码错误"
                        input = ""
                    }
                } else if stage == 1 {
                    firstEntry = code
                    input = ""
                    stage = 2
                } else {
                    if code == firstEntry {
                        onFinish(code)
                        dismiss()
                    } else {
                        errorText = "两次输入不一致"
                        input = ""
                        firstEntry = ""
                        stage = 1
                    }
                }
            }
        }
    }
}
