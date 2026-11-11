import SwiftUI
import UIKit

// MARK: - 激活页

/// 装完 App 第一次打开看到的第一屏：输入激活码才能进主界面。
struct ActivationView: View {
    @ObservedObject private var lic = LicenseService.shared

    @State private var code: String = ""
    @State private var showHelp = false
    @FocusState private var focused: Bool

    private var canSubmit: Bool {
        code.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6 && !lic.busy
    }

    var body: some View {
        ZStack {
            Theme.gradTop.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 46)

                    // 图标
                    ZStack {
                        Circle()
                            .fill(Theme.gradRose)
                            .frame(width: 78, height: 78)
                            .shadow(color: Theme.roseDeep.opacity(0.28), radius: 16, y: 8)
                        Image(systemName: "key.fill")
                            .font(.system(size: 30, weight: .light))
                            .foregroundColor(.white)
                            .rotationEffect(.degrees(-35))
                    }

                    Text(lic.shopName.isEmpty ? "软件激活" : lic.shopName)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(Theme.ink)
                        .padding(.top, 18)

                    Text(lic.leftText.isEmpty ? "输入激活码后即可使用" : "当前授权：\(lic.leftText)")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.muted)
                        .padding(.top, 6)

                    // 激活码输入
                    VStack(spacing: 12) {
                        TextField("MYA-XXXX-XXXX-XXXX", text: $code)
                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .focused($focused)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 14)
                            .background(Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(lic.errorText == nil ? Theme.line : Color.red.opacity(0.55),
                                            lineWidth: 1)
                            )
                            .onChange(of: code) { v in
                                let clean = v.uppercased()
                                    .filter { $0.isLetter || $0.isNumber || $0 == "-" }
                                if clean.count > 24 { code = String(clean.prefix(24)) }
                                else if clean != v { code = clean }
                            }

                        if let err = lic.errorText {
                            Text(err)
                                .font(.system(size: 12.5))
                                .foregroundColor(Color.red.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button {
                            focused = false
                            Task { await lic.redeem(code) }
                        } label: {
                            HStack(spacing: 8) {
                                if lic.busy { ProgressView().tint(.white) }
                                Text(lic.busy ? "激活中…" : "激活并开始使用")
                                    .font(.system(size: 15.5, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(canSubmit ? AnyView(Theme.gradRose) : AnyView(Color.gray.opacity(0.35)))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit)

                        HStack(spacing: 16) {
                            Button("粘贴") {
                                if let s = UIPasteboard.general.string { code = s }
                            }
                            Button("联系门店") { showHelp = true }
                            if !lic.codeText.isEmpty {
                                Button("复核授权") {
                                    Task { await lic.refresh() }
                                }
                            }
                        }
                        .font(.system(size: 12.5))
                        .foregroundColor(Theme.roseDeep)
                        .padding(.top, 2)
                    }
                    .padding(.top, 26)

                    // 说明
                    VStack(alignment: .leading, spacing: 8) {
                        Label("激活码由门店发放，一张码可授权 \(lic.permanent ? "多台" : "指定台数")设备", systemImage: "info.circle")
                        Label("激活后客户、照片、预约自动同步，无需再登录", systemImage: "arrow.triangle.2.circlepath")
                        Label("换手机或重装，用同一张码重新激活即可", systemImage: "iphone.gen3")
                    }
                    .font(.system(size: 12.5))
                    .foregroundColor(Theme.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Theme.card.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 24)

                    Spacer(minLength: 24)

                    Text("设备编号 \(lic.deviceShort)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.muted.opacity(0.8))
                        .padding(.bottom, 18)
                }
                .padding(.horizontal, 24)
            }
        }
        .onAppear {
            if code.isEmpty, !lic.codeText.isEmpty { code = lic.codeText }
        }
        .sheet(isPresented: $showHelp) {
            helpSheet
        }
    }

    private var helpSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("需要激活码")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.ink)
                Spacer()
                Button("关闭") { showHelp = false }
                    .font(.system(size: 14))
                    .foregroundColor(Theme.roseDeep)
            }

            Text(lic.notice)
                .font(.system(size: 13.5))
                .foregroundColor(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            Text(lic.contact)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.roseDeep)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .background(Theme.roseLight.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("把这串设备编号发给门店，方便他们核对授权：\(lic.deviceShort)")
                .font(.system(size: 12))
                .foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                UIPasteboard.general.string = lic.deviceShort
            } label: {
                Text("复制设备编号")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.roseDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.roseLight.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.height(360)])
    }
}

// MARK: - 启动校验中

struct ActivationCheckingView: View {
    var body: some View {
        ZStack {
            Theme.gradTop.ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Theme.gradRose)
                        .frame(width: 68, height: 68)
                    Image(systemName: "key.fill")
                        .font(.system(size: 26, weight: .light))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(-35))
                }
                ProgressView()
                    .tint(Theme.roseDeep)
                Text("正在校验授权…")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.muted)
            }
        }
    }
}
