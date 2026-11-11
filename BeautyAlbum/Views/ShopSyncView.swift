import SwiftUI

/// 「我的」页里的店铺同步卡片：登录后台账号，把本地数据与网站对齐。
struct ShopSyncCard: View {
    @ObservedObject var sync = SyncService.shared
    @ObservedObject var store = Store.shared
    @ObservedObject var license = LicenseService.shared

    @State private var showLogin = false
    @State private var confirmPush = false

    private struct CountItem: Identifiable {
        let label: String
        let value: Int
        var id: String { label }
    }

    private var countItems: [CountItem] {
        [
            CountItem(label: "客户", value: store.clients.count),
            CountItem(label: "导师", value: store.teachers.count),
            CountItem(label: "产品", value: store.products.count),
            CountItem(label: "代理", value: store.agents.count),
            CountItem(label: "预约", value: store.appointments.count),
            CountItem(label: "照片", value: store.clients.reduce(0) { $0 + $1.photos.count })
        ]
    }

    private var timeText: String {
        guard let d = sync.lastSyncAt else { return "还没同步过" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return "上次同步 " + f.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.roseDeep)
                Text("店铺数据同步")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.ink)
                Spacer()
                if sync.isLoggedIn {
                    Text(sync.shopName)
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.muted)
                }
            }

            // 授权状态：激活码决定这台机器能用多久
            HStack(spacing: 6) {
                Image(systemName: "key.fill")
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.roseDeep)
                Text(license.permanent
                     ? "软件已永久授权"
                     : (license.leftText.isEmpty ? "软件授权校验中" : "软件授权：\(license.leftText)"))
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.muted)
                Spacer()
                if !license.codeText.isEmpty {
                    Text(license.codeText)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Theme.muted.opacity(0.75))
                }
            }

            if !sync.isLoggedIn {
                Text("用网站后台的账号登录。登录后自动同步：软件里加客户、加老师、排预约，网站后台立刻就有；网站改了，手机也会自己更新。")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    showLogin = true
                } label: {
                    Text("用店铺账号登录")
                        .font(.system(size: 13.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.roseDeep)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
            } else {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(sync.running ? Theme.rose : Color.green)
                                .frame(width: 6, height: 6)
                            Text(sync.running ? "同步中…" : "自动同步已开启")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(sync.running ? Theme.roseDeep : .green)
                        }
                        Text(timeText)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.muted)
                        if let s = sync.lastSummary {
                            Text(s)
                                .font(.system(size: 11.5))
                                .foregroundColor(Theme.roseDeep)
                        }
                        if let e = sync.errorText {
                            Text(e)
                                .font(.system(size: 11.5))
                                .foregroundColor(.red)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    if sync.running {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text(sync.progressText.isEmpty ? "同步中…" : sync.progressText)
                                .font(.system(size: 12))
                                .foregroundColor(Theme.muted)
                        }
                    } else {
                        Button {
                            Task { await sync.syncNow(store: store) }
                        } label: {
                            Text("立即同步")
                                .font(.system(size: 12.5, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Theme.roseLight)
                                .foregroundColor(Theme.roseDeep)
                                .clipShape(Capsule())
                        }
                    }
                }

                // 数据条数，让店主确认到底同步了多少东西
                HStack(spacing: 0) {
                    ForEach(countItems, id: \.label) { item in
                        VStack(spacing: 3) {
                            Text("\(item.value)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Theme.ink)
                            Text(item.label)
                                .font(.system(size: 10.5))
                                .foregroundColor(Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 8)
                .background(Theme.cream)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    sync.logout()
                } label: {
                    Text("退出店铺账号")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.muted)
                }
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
        .sheet(isPresented: $showLogin) {
            ShopLoginSheet()
        }
    }
}

/// 店铺账号登录
struct ShopLoginSheet: View {
    @ObservedObject var sync = SyncService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var account = ""
    @State private var password = ""
    @State private var busy = false
    @State private var tip: String?
    @FocusState private var focus: Field?

    enum Field { case account, password }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image(systemName: "building.2.crop.circle")
                            .font(.system(size: 42))
                            .foregroundColor(Theme.roseDeep)
                        Text("登录店铺账号")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Theme.ink)
                        Text("用网站后台的管理员账号，登录后手机与网站共用同一份数据")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 10)

                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "person")
                                .foregroundColor(Theme.muted)
                                .frame(width: 20)
                            TextField("邮箱 / 姓名 / 手机号", text: $account)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focus, equals: .account)
                        }
                        .padding(12)
                        .background(Theme.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                        HStack(spacing: 10) {
                            Image(systemName: "lock")
                                .foregroundColor(Theme.muted)
                                .frame(width: 20)
                            SecureField("密码", text: $password)
                                .focused($focus, equals: .password)
                        }
                        .padding(12)
                        .background(Theme.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }

                    if let tip {
                        Text(tip)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack(spacing: 6) {
                            if busy { ProgressView().tint(.white).scaleEffect(0.8) }
                            Text(busy ? "登录中…" : "登录并同步")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.roseDeep)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(busy || account.isEmpty || password.isEmpty)
                    .opacity((busy || account.isEmpty || password.isEmpty) ? 0.55 : 1)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("店铺账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundColor(Theme.roseDeep)
                }
            }
        }
    }

    private func submit() async {
        busy = true
        tip = nil
        do {
            try await sync.login(account: account.trimmingCharacters(in: .whitespaces),
                                 password: password)
            SyncService.shared.activate(store: Store.shared)
            await sync.syncNow(store: Store.shared)
            busy = false
            dismiss()
        } catch {
            busy = false
            tip = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
