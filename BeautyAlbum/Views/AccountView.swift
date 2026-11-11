import SwiftUI

/// 我的：会员注册 / 登录 / 套餐开通
struct AccountView: View {
    @EnvironmentObject var store: Store

    @State private var mode: AuthMode = .login
    @State private var phone = ""
    @State private var code = ""
    @State private var password = ""
    @State private var name = ""

    @State private var busy = false
    @State private var sending = false
    @State private var countdown = 0
    @State private var tip: String?
    @State private var tipIsError = false

    @State private var member: CloudMember?
    @State private var packages: [CloudPackage] = []
    @State private var loadingPackages = false
    @State private var activatingID: Int?
    @State private var showSiteSheet = false

    @State private var wallet: CloudWallet?
    @State private var showRecharge = false
    @State private var rechargeNotice: String?

    @FocusState private var focus: Field?
    private enum Field { case phone, code, password, name }

    private var token: String {
        get { UserDefaults.standard.string(forKey: "cloud.token") ?? "" }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: "cloud.token") }
    }

    private var isLoggedIn: Bool { !token.isEmpty }

    enum AuthMode: String, CaseIterable {
        case login = "登录"
        case register = "注册"
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    if isLoggedIn {
                        profileCard
                        walletSection
                        packagesSection
                    } else {
                        authCard
                    }
                    ShopSyncCard()
                    siteCard
                }
                .padding(.horizontal, Metrics.hPadding)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSiteSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundColor(Theme.roseDeep)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focus = nil }
                        .foregroundColor(Theme.roseDeep)
                }
            }
            .sheet(isPresented: $showSiteSheet) {
                ServerSettingSheet()
            }
            .sheet(isPresented: $showRecharge) {
                RechargeSheet(token: token, notice: rechargeNotice) { newMember in
                    member = newMember
                    Task { await loadWallet() }
                }
            }
            .task { await refreshAll() }
        }
    }

    // MARK: 顶部

    private var headerCard: some View {
        ZStack(alignment: .bottomLeading) {
            Theme.gradRose
            VStack(alignment: .leading, spacing: 6) {
                Text(store.settings.shopName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Text(isLoggedIn ? "会员中心 · 套餐与服务" : "注册会员，随时查看套餐与记录")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(18)
        }
        .frame(height: 108)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: 登录 / 注册

    private var authCard: some View {
        CardBox {
            VStack(spacing: 14) {
                Picker("", selection: $mode) {
                    ForEach(AuthMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)

                field(icon: "iphone", placeholder: "手机号", text: $phone,
                      keyboard: .numberPad, focusValue: .phone)

                HStack(spacing: 8) {
                    field(icon: "checkmark.shield", placeholder: "验证码", text: $code,
                          keyboard: .numberPad, focusValue: .code)
                    Button {
                        Task { await sendCode() }
                    } label: {
                        Text(sending ? "发送中" : (countdown > 0 ? "\(countdown)s" : "获取验证码"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(countdown > 0 ? Theme.muted : Theme.roseDeep)
                            .frame(width: 92)
                            .padding(.vertical, 12)
                            .background(Theme.roseLight)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .disabled(sending || countdown > 0)
                }

                field(icon: "lock", placeholder: mode == .register ? "设置密码（至少 6 位）" : "密码",
                      text: $password, keyboard: .default, focusValue: .password, secure: true)

                if mode == .register {
                    field(icon: "person", placeholder: "你的称呼（可留空）", text: $name,
                          keyboard: .default, focusValue: .name)
                }

                if let t = tip {
                    HStack(spacing: 6) {
                        Image(systemName: tipIsError ? "exclamationmark.circle" : "info.circle")
                        Text(t).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(tipIsError ? .red : Theme.roseDeep)
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView().tint(.white) }
                        Text(busy ? "请稍候…" : (mode == .register ? "注册并登录" : "登录"))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)

                Text("注册即成为本店会员，可在 App 内查看套餐并开通。")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.muted)
            }
        }
    }

    private func field(icon: String, placeholder: String, text: Binding<String>,
                       keyboard: UIKeyboardType, focusValue: Field, secure: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(Theme.muted)
                .frame(width: 18)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.system(size: 15))
            .keyboardType(keyboard)
            .focused($focus, equals: focusValue)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(Theme.placeholder.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    // MARK: 已登录

    private var profileCard: some View {
        CardBox {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Theme.roseLight)
                        Text(String((member?.name ?? "会").prefix(1)))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Theme.roseDeep)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(member?.name ?? "会员")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Theme.ink)
                            if let lv = member?.level {
                                Text(lv)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Theme.roseDeep)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Theme.roseLight)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(member?.phone ?? "")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }

                Divider().background(Theme.line)

                HStack(spacing: 0) {
                    infoCell("当前套餐", member?.package?.name ?? "未开通")
                    Divider().frame(height: 28).background(Theme.line)
                    infoCell("到期时间", member?.expireText ?? "—")
                    Divider().frame(height: 28).background(Theme.line)
                    infoCell("积分", "\(member?.points ?? 0)")
                }

                Divider().background(Theme.line)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("账户余额")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.muted)
                        Text(member?.balanceText ?? "¥0")
                            .font(.system(size: 25, weight: .bold))
                            .foregroundColor(Theme.roseDeep)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("累计充值")
                            .font(.system(size: 10.5))
                            .foregroundColor(Theme.muted)
                        Text(member?.totalRechargeText ?? "¥0")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(Theme.inkSoft)
                    }
                    Spacer(minLength: 0)
                    Button {
                        showRecharge = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "creditcard.fill")
                                .font(.system(size: 12))
                            Text("充值")
                                .font(.system(size: 13.5, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Theme.gradRose)
                        .clipShape(Capsule())
                    }
                }

                if let p = member?.package, member?.isExpired == true {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.badge.exclamationmark")
                        Text("「\(p.name)」已到期，续费后可继续使用")
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await loadPackages(); await loadWallet() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SoftButtonStyle())

                    Button {
                        showRecharge = true
                    } label: {
                        Label("输入卡密", systemImage: "key.fill")
                    }
                    .buttonStyle(SoftButtonStyle())

                    Button {
                        Task { await doLogout() }
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(SoftButtonStyle())
                }
            }
        }
    }

    // MARK: 钱包流水

    private var walletSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "钱包流水",
                          trailing: "\(wallet?.logs?.count ?? 0) 条")

            if let logs = wallet?.logs, !logs.isEmpty {
                CardBox {
                    VStack(spacing: 0) {
                        ForEach(Array(logs.prefix(12).enumerated()), id: \.element.id) { idx, log in
                            if idx > 0 { Divider().background(Theme.line) }
                            walletRow(log)
                        }
                    }
                }
            } else {
                CardBox {
                    EmptyHint(icon: "creditcard",
                              title: "还没有充值记录",
                              subtitle: "点上面的「充值」，输入卡号卡密即可到账")
                }
            }
        }
    }

    private func walletRow(_ log: CloudWalletLog) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(log.kind ?? "变动")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.ink)
                Text(log.note ?? log.ref ?? log.timeText)
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(log.amountText)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor((log.amount ?? 0) > 0 ? Theme.roseDeep : Theme.muted)
                if (log.points ?? 0) != 0 {
                    Text("积分 " + log.pointsText)
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.muted)
                }
            }
        }
        .padding(.vertical, 9)
    }

    private func infoCell(_ k: String, _ v: String) -> some View {
        VStack(spacing: 4) {
            Text(k).font(.system(size: 10.5)).foregroundColor(Theme.muted)
            Text(v)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 套餐

    private var packagesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "可选套餐", trailing: loadingPackages ? "加载中…" : "\(packages.count) 个")

            if packages.isEmpty {
                CardBox {
                    EmptyHint(icon: "gift",
                              title: loadingPackages ? "正在加载套餐" : "暂时没有上架套餐",
                              subtitle: loadingPackages ? "请稍候" : "请让店长在后台添加套餐")
                }
            } else {
                ForEach(packages) { p in
                    packageCard(p)
                }
            }
        }
    }

    private func packageCard(_ p: CloudPackage) -> some View {
        CardBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(p.name)
                                .font(.system(size: 15.5, weight: .bold))
                                .foregroundColor(Theme.ink)
                            if let b = p.badge, !b.isEmpty {
                                Text(b)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Theme.rose)
                                    .clipShape(Capsule())
                            }
                        }
                        Text("有效期 \(p.days) 天")
                            .font(.system(size: 11.5))
                            .foregroundColor(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    Text(p.priceText)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Theme.roseDeep)
                }

                if let d = p.desc, !d.isEmpty {
                    Text(d)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !p.lineItems.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(p.lineItems.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.rose)
                                    .padding(.top, 3)
                                Text(item)
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(10)
                    .background(Theme.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Button {
                    Task { await activate(p) }
                } label: {
                    HStack(spacing: 6) {
                        if activatingID == p.id {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        }
                        Text(activatingID == p.id ? "开通中…" : "开通这个套餐")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(activatingID != nil)
            }
        }
    }

    private var siteCard: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.muted)
                    Text("服务器")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.inkSoft)
                    Spacer()
                    Button("修改") { showSiteSheet = true }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.roseDeep)
                }
                Text(ServerURL.display(CloudAPI.shared.baseURL))
                    .font(.system(size: 11.5, design: ServerURL.isEncrypted ? .monospaced : .default))
                    .foregroundColor(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text("账号与套餐数据保存在这地址对应的后台，换服务器后需要重新登录。")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 动作

    private func refreshAll() async {
        await loadSiteInfo()
        if isLoggedIn {
            await loadMe()
            await loadWallet()
            await loadPackages()
        }
    }

    private func loadSiteInfo() async {
        if let info = try? await CloudAPI.shared.siteInfo() {
            /* 网址显示方式由后台控制，取回来立刻生效 */
            if let m = info.urlDisplay, !m.isEmpty {
                ServerURL.displayMode = m
            }
            await MainActor.run { rechargeNotice = info.rechargeNotice }
        }
    }

    private func loadWallet() async {
        guard isLoggedIn else { return }
        do {
            let w = try await CloudAPI.shared.wallet(token: token)
            await MainActor.run { wallet = w }
        } catch {
            // 静默失败，不影响主流程
        }
    }

    private func loadMe() async {
        do {
            let m = try await CloudAPI.shared.me(token: token)
            await MainActor.run { member = m }
        } catch {
            // token 失效就清掉，回到登录态
            if let e = error as? CloudError, case .message(let msg) = e, msg.contains("登录") {
                await MainActor.run { token = ""; member = nil }
            }
        }
    }

    private func loadPackages() async {
        await MainActor.run { loadingPackages = true }
        do {
            let list = try await CloudAPI.shared.packages()
            await MainActor.run { packages = list; loadingPackages = false }
        } catch {
            await MainActor.run {
                loadingPackages = false
                showTip(error.localizedDescription, isError: true)
            }
        }
    }

    private func sendCode() async {
        let p = phone.trimmingCharacters(in: .whitespaces)
        guard p.count == 11, p.hasPrefix("1") else {
            showTip("请填写 11 位手机号", isError: true)
            return
        }
        await MainActor.run { sending = true; tip = nil }
        do {
            let r = try await CloudAPI.shared.sendCode(phone: p)
            await MainActor.run {
                sending = false
                countdown = 60
                if let dc = r.debugCode, !dc.isEmpty {
                    showTip("调试模式验证码：\(dc)", isError: false)
                    code = dc
                } else {
                    showTip(r.msg ?? "验证码已发送", isError: false)
                }
            }
            startCountdown()
        } catch {
            await MainActor.run {
                sending = false
                showTip(error.localizedDescription, isError: true)
            }
        }
    }

    private func startCountdown() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            if countdown <= 1 {
                countdown = 0
                t.invalidate()
            } else {
                countdown -= 1
            }
        }
    }

    private func submit() async {
        let p = phone.trimmingCharacters(in: .whitespaces)
        guard p.count == 11, p.hasPrefix("1") else {
            showTip("请填写 11 位手机号", isError: true)
            return
        }
        guard password.count >= 6 else {
            showTip("密码至少 6 位", isError: true)
            return
        }
        await MainActor.run { busy = true; tip = nil; focus = nil }
        do {
            let r: CloudAuthResult
            if mode == .register {
                let c = code.trimmingCharacters(in: .whitespaces)
                guard !c.isEmpty else {
                    await MainActor.run { busy = false }
                    showTip("请先获取并填写验证码", isError: true)
                    return
                }
                r = try await CloudAPI.shared.register(phone: p, code: c, password: password,
                                                       name: name.trimmingCharacters(in: .whitespaces))
            } else {
                r = try await CloudAPI.shared.login(phone: p, password: password)
            }
            await MainActor.run {
                token = r.token
                member = r.member
                busy = false
                code = ""
                password = ""
                showTip(mode == .register ? "注册成功，已为你登录" : "登录成功", isError: false)
            }
            await loadPackages()
            await loadWallet()
        } catch {
            await MainActor.run {
                busy = false
                showTip(error.localizedDescription, isError: true)
            }
        }
    }

    private func activate(_ p: CloudPackage) async {
        guard !token.isEmpty else { return }
        await MainActor.run { activatingID = p.id; tip = nil }
        do {
            let m = try await CloudAPI.shared.activate(packageID: p.id, token: token)
            await MainActor.run {
                member = m
                activatingID = nil
                showTip("「\(p.name)」开通成功，有效期至 \(m.expireText)", isError: false)
            }
        } catch {
            await MainActor.run {
                activatingID = nil
                showTip(error.localizedDescription, isError: true)
            }
        }
    }

    private func doLogout() async {
        let t = token
        if !t.isEmpty { await CloudAPI.shared.logout(token: t) }
        await MainActor.run {
            token = ""
            member = nil
            tip = nil
            mode = .login
        }
    }

    private func showTip(_ t: String, isError: Bool) {
        tip = t
        tipIsError = isError
    }
}

// MARK: - 充值（卡号 + 卡密）

struct RechargeSheet: View {
    @Environment(\.dismiss) private var dismiss

    let token: String
    let notice: String?
    var onSuccess: (CloudMember) -> Void

    @State private var cardNo = ""
    @State private var secret = ""
    @State private var busy = false
    @State private var tip: String?
    @State private var tipIsError = false
    @State private var done: CloudRechargeResult?

    @FocusState private var focus: Field?
    private enum Field { case card, secret }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    introCard
                    if let r = done {
                        successCard(r)
                    } else {
                        formCard
                    }
                }
                .padding(.horizontal, Metrics.hPadding)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("充值")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focus = nil }
                        .foregroundColor(Theme.roseDeep)
                }
            }
        }
    }

    // MARK: 顶部说明

    private var introCard: some View {
        ZStack(alignment: .bottomLeading) {
            Theme.gradRose
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 13))
                    Text("充值卡充值")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundColor(.white)
                Text("刮开卡片涂层，输入卡号与卡密即可到账")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.92))
            }
            .padding(18)
        }
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: 表单

    private var formCard: some View {
        CardBox {
            VStack(spacing: 14) {
                inputField(icon: "number", placeholder: "卡号（如 MY2611XXXXXXXX）",
                           text: $cardNo, f: .card)
                inputField(icon: "key.fill", placeholder: "卡密（12 位字母数字）",
                           text: $secret, f: .secret)

                if let t = tip {
                    HStack(spacing: 6) {
                        Image(systemName: tipIsError ? "exclamationmark.circle" : "info.circle")
                        Text(t).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(tipIsError ? .red : Theme.roseDeep)
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 8) {
                        if busy { ProgressView().tint(.white) }
                        Text(busy ? "充值中…" : "确认充值")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)

                if let n = notice, !n.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(n)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func inputField(icon: String, placeholder: String,
                            text: Binding<String>, f: Field) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(Theme.muted)
                .frame(width: 18)
            TextField(placeholder, text: text)
                .font(.system(size: 15))
                .keyboardType(.asciiCapable)
                .focused($focus, equals: f)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(Theme.placeholder.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    // MARK: 成功

    private func successCard(_ r: CloudRechargeResult) -> some View {
        CardBox {
            VStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.roseLight)
                    Image(systemName: "checkmark")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(Theme.roseDeep)
                }
                .frame(width: 62, height: 62)

                Text("充值成功")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Theme.ink)

                if let c = r.card, let label = c.label, !label.isEmpty {
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.inkSoft)
                }

                HStack(spacing: 0) {
                    statCell("到账金额",
                             CloudMember.moneyText((r.card?.amount ?? 0) + (r.card?.bonus ?? 0)))
                    Divider().frame(height: 30).background(Theme.line)
                    statCell("当前余额", r.member.balanceText)
                    Divider().frame(height: 30).background(Theme.line)
                    statCell("积分", "\(r.member.points ?? 0)")
                }

                Button {
                    dismiss()
                } label: {
                    Text("完成")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("再充一张") { reset() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.roseDeep)
            }
        }
    }

    private func statCell(_ k: String, _ v: String) -> some View {
        VStack(spacing: 4) {
            Text(k).font(.system(size: 10.5)).foregroundColor(Theme.muted)
            Text(v)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundColor(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 动作

    private func submit() async {
        let no = normalize(cardNo)
        let sc = normalize(secret)
        guard !no.isEmpty, !sc.isEmpty else {
            show("请填写卡号与卡密", true)
            return
        }
        await MainActor.run { busy = true; tip = nil; focus = nil }
        do {
            let r = try await CloudAPI.shared.rechargeCard(cardNo: no, secret: sc, token: token)
            await MainActor.run {
                busy = false
                done = r
                onSuccess(r.member)
            }
        } catch {
            await MainActor.run {
                busy = false
                show(error.localizedDescription, true)
            }
        }
    }

    private func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
    }

    private func reset() {
        cardNo = ""
        secret = ""
        tip = nil
        done = nil
        focus = .card
    }

    private func show(_ t: String, _ isError: Bool) {
        tip = t
        tipIsError = isError
    }
}

// MARK: - 服务器地址设置

struct ServerSettingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = CloudAPI.shared.baseURL
    @State private var checking = false
    @State private var result: String?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("https://你的域名", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("后台地址")
                } footer: {
                    Text("填后台域名即可，不用带路径。改完点「测试连接」确认能通。")
                }

                Section {
                    Button {
                        Task { await test() }
                    } label: {
                        HStack {
                            Text(checking ? "测试中…" : "测试连接")
                            Spacer()
                            if checking { ProgressView() }
                        }
                    }
                    .disabled(checking)

                    if let r = result {
                        Text(r)
                            .font(.system(size: 12))
                            .foregroundColor(r.hasPrefix("连接正常") ? .green : .red)
                    }
                }
            }
            .navigationTitle("服务器设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var v = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        while v.hasSuffix("/") { v.removeLast() }
                        CloudAPI.shared.baseURL = v
                        dismiss()
                    }
                }
            }
        }
    }

    private func test() async {
        var v = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while v.hasSuffix("/") { v.removeLast() }
        let old = CloudAPI.shared.baseURL
        CloudAPI.shared.baseURL = v
        await MainActor.run { checking = true; result = nil }
        do {
            let info = try await CloudAPI.shared.siteInfo()
            await MainActor.run {
                checking = false
                result = "连接正常 · \(info.shopName ?? "未命名店铺")"
            }
        } catch {
            CloudAPI.shared.baseURL = old
            await MainActor.run {
                checking = false
                result = "连接失败：\(error.localizedDescription)"
            }
        }
    }
}
