import SwiftUI
import PhotosUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var wechatItem: PhotosPickerItem?
    @State private var alipayItem: PhotosPickerItem?
    @State private var newStep = ""
    @State private var message: String?

    @State private var showPinSheet = false
    @State private var pinMode: PinSetupSheet.Mode = .create

    var body: some View {
        NavigationStack {
            Form {
                shopSection
                labelSection
                homeSection
                featureSection
                securitySection
                paymentSection
                templateSection
                dataSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.cream)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        store.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: wechatItem) { item in
                loadQR(item, kind: .wechat)
                wechatItem = nil
            }
            .onChange(of: alipayItem) { item in
                loadQR(item, kind: .alipay)
                alipayItem = nil
            }
            .sheet(isPresented: $showPinSheet) {
                PinSetupSheet(mode: pinMode,
                              verifyOld: { store.verifyLockCode($0) },
                              onFinish: { code in
                                  if let code {
                                      store.enableLock(code: code)
                                  } else {
                                      store.disableLock()
                                  }
                              })
            }
            .alert(message ?? "", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("好") { message = nil }
            }
        }
    }

    // MARK: 系统名称

    private var shopSection: some View {
        Section {
            HStack {
                Text("系统名称")
                Spacer()
                TextField("例如 悦颜美容", text: $store.settings.shopName)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(Theme.roseDeep)
            }
        } header: {
            Text("店铺")
        } footer: {
            Text("显示在首页标题、锁屏界面、对比图和备份文件名里。")
        }
    }

    // MARK: 文字

    private var labelSection: some View {
        Section {
            HStack {
                Text("使用前文案")
                Spacer()
                TextField("使用前", text: $store.settings.beforeLabel)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(Theme.roseDeep)
            }
            HStack {
                Text("使用后文案")
                Spacer()
                TextField("使用后", text: $store.settings.afterLabel)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(Theme.roseDeep)
            }
            HStack(spacing: 8) {
                Text("预览")
                    .foregroundColor(Theme.muted)
                Spacer()
                PhaseBadge(text: store.settings.beforeLabel, phase: .before)
                PhaseBadge(text: store.settings.afterLabel, phase: .after)
            }
        } header: {
            Text("照片阶段文字")
        } footer: {
            Text("全 App 统一使用这两个称呼：相册分组、对比页、导出对比图、备份目录名都会跟着改。")
        }
    }

    // MARK: 首页客户列表

    private var homeSection: some View {
        Section {
            Picker("排列方式", selection: $store.settings.clientLayout) {
                ForEach(ClientListLayout.allCases) { l in
                    Text(l.rawValue).tag(l)
                }
            }
            .pickerStyle(.segmented)

            if store.settings.clientLayout == .grid {
                Picker("每行个数", selection: $store.settings.clientColumns) {
                    Text("2 个").tag(2)
                    Text("3 个").tag(3)
                }
                .pickerStyle(.segmented)
            }

            Picker("首页显示", selection: $store.settings.homeClientLimit) {
                Text("全部").tag(0)
                Text("5 位").tag(5)
                Text("10 位").tag(10)
                Text("15 位").tag(15)
                Text("20 位").tag(20)
                Text("30 位").tag(30)
                Text("50 位").tag(50)
            }

            Toggle(isOn: $store.settings.showClientCover) {
                featureLabel("竖排显示封面图", "photo", "关闭后列表更紧凑")
            }

            HStack(spacing: 8) {
                Text("当前共").foregroundColor(Theme.muted)
                Text("\(store.clients.count)").foregroundColor(Theme.roseDeep).fontWeight(.semibold)
                Text("位客户").foregroundColor(Theme.muted)
                Spacer()
                Text(store.settings.homeClientLimit == 0
                     ? "首页全部展示"
                     : "首页只显示前 \(store.settings.homeClientLimit) 位")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
            }
            .font(.system(size: 13))
        } header: {
            Text("首页客户列表")
        } footer: {
            Text("控制首页客户怎么排、一次显示几个。数量上限只影响首页浏览，搜索时会自动展示全部匹配结果。")
        }
    }

    // MARK: 功能开关

    private var featureSection: some View {
        Section {
            Toggle(isOn: $store.settings.features.teachers) {
                featureLabel("老师团队", "person.2.fill", "展示老师、管理资料")
            }
            Toggle(isOn: $store.settings.features.appointments) {
                featureLabel("预约管理", "calendar", "预约老师、排期与状态")
            }
            Toggle(isOn: $store.settings.features.products) {
                featureLabel("产品库", "shippingbox.fill", "产品图、规格、使用步骤")
            }
            Toggle(isOn: $store.settings.features.payments) {
                featureLabel("收款与账单", "qrcode", "应收、已付、未付、收款码")
            }
            Toggle(isOn: $store.settings.features.compare) {
                featureLabel("前后对比", "rectangle.split.2x1", "并排 / 滑块对比")
            }
            Toggle(isOn: $store.settings.features.steps) {
                featureLabel("流程进度", "list.bullet.clipboard", "记录走到哪一步")
            }
            Toggle(isOn: $store.settings.features.notes) {
                featureLabel("备注与记录", "text.alignleft", "客户备注与跟进记录")
            }
            Toggle(isOn: $store.settings.features.backup) {
                featureLabel("备份与恢复", "externaldrive.badge.timemachine", "导出 ZIP、网盘")
            }
        } header: {
            Text("功能模块")
        } footer: {
            Text("关掉的模块会从底部标签和客户详情页隐藏，已有数据不会删除，重新打开即可看到。")
        }
    }

    private func featureLabel(_ title: String, _ icon: String, _ sub: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(Theme.roseDeep)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14))
                Text(sub).font(.system(size: 10)).foregroundColor(Theme.muted)
            }
        }
    }

    // MARK: 安全

    private var securitySection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { store.settings.lockEnabled },
                set: { on in
                    if on {
                        pinMode = store.hasLockCode ? .change : .create
                        showPinSheet = true
                    } else {
                        pinMode = .disable
                        showPinSheet = true
                    }
                }
            )) {
                featureLabel("密码锁", "lock.fill", "启动或回到前台时验证")
            }

            if store.settings.lockEnabled {
                Button {
                    pinMode = .change
                    showPinSheet = true
                } label: {
                    HStack {
                        Text("修改密码")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.muted)
                    }
                }

                Picker("自动锁定", selection: $store.settings.autoLockMinutes) {
                    Text("立即").tag(0)
                    Text("1 分钟").tag(1)
                    Text("5 分钟").tag(5)
                    Text("30 分钟").tag(30)
                }

                Button {
                    store.lockNow()
                    dismiss()
                } label: {
                    Label("立即锁定", systemImage: "lock")
                        .foregroundColor(Theme.roseDeep)
                }
            }
        } header: {
            Text("安全")
        } footer: {
            Text("密码以 SHA256 摘要保存，不存明文。忘记密码可在锁屏页重置，但会清空本机数据。")
        }
    }

    // MARK: 收款

    private var paymentSection: some View {
        Section {
            qrRow(kind: .wechat, item: $wechatItem)
            qrRow(kind: .alipay, item: $alipayItem)

            HStack {
                Text("收款链接")
                Spacer()
                TextField("可留空", text: $store.settings.payLink)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(Theme.roseDeep)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            HStack {
                Text("扫码提示语")
                Spacer()
                TextField("提示语", text: $store.settings.payNote)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(Theme.roseDeep)
            }
        } header: {
            Text("收款")
        } footer: {
            Text("填了「收款链接」后，App 会用它生成带金额参数的二维码；留空则直接展示你上传的收款码图片，客户扫码后自行输入金额。")
        }
    }

    private func qrRow(kind: PaymentQRKind, item: Binding<PhotosPickerItem?>) -> some View {
        HStack(spacing: 12) {
            if let img = store.paymentQRImage(kind: kind) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 0.8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.placeholder)
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "qrcode")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.muted))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .font(.system(size: 14, weight: .medium))
                Text(store.paymentQRImage(kind: kind) == nil ? "未上传" : "已设置")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.muted)
            }

            Spacer()

            PhotosPicker(selection: item, matching: .images) {
                Text(store.paymentQRImage(kind: kind) == nil ? "上传" : "更换")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.roseDeep)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.roseLight)
                    .clipShape(Capsule())
            }

            if store.paymentQRImage(kind: kind) != nil {
                Button {
                    store.removePaymentQR(kind: kind)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: 流程模板

    private var templateSection: some View {
        Section {
            ForEach(Array(store.settings.stepTemplate.enumerated()), id: \.offset) { idx, _ in
                HStack(spacing: 8) {
                    Text("\(idx + 1)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.muted)
                        .frame(width: 18)
                    TextField("环节名称", text: Binding(
                        get: {
                            idx < store.settings.stepTemplate.count ? store.settings.stepTemplate[idx] : ""
                        },
                        set: { v in
                            if idx < store.settings.stepTemplate.count {
                                store.settings.stepTemplate[idx] = v
                            }
                        }
                    ))
                }
            }
            .onDelete { offsets in
                store.settings.stepTemplate.remove(atOffsets: offsets)
                store.save()
            }

            HStack(spacing: 8) {
                TextField("新增环节", text: $newStep)
                Button {
                    let t = newStep.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    store.settings.stepTemplate.append(t)
                    newStep = ""
                    store.save()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Theme.roseDeep)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("默认流程模板")
        } footer: {
            Text("新建客户时自动套用。已建档的客户不受影响，可在客户「流程」页单独调整。")
        }
    }

    // MARK: 数据

    private var dataSection: some View {
        Section {
            if store.settings.features.backup {
                NavigationLink {
                    BackupView()
                } label: {
                    HStack {
                        Label("备份与恢复", systemImage: "externaldrive.badge.timemachine")
                        Spacer()
                        Text(store.settings.autoBackupEnabled
                             ? "自动 · 每 \(store.settings.autoBackupDays) 天"
                             : "\(store.clients.count) 位客户")
                            .font(.system(size: 12))
                            .foregroundColor(store.settings.autoBackupEnabled
                                             ? Theme.roseDeep : Theme.muted)
                    }
                }
            }

            HStack {
                Text("客户 / 照片")
                Spacer()
                Text("\(store.clients.count) 位 · \(store.totalPhotoCount) 张")
                    .foregroundColor(Theme.muted)
            }
            HStack {
                Text("老师 / 预约")
                Spacer()
                Text("\(store.teachers.count) 位 · \(store.appointments.count) 条")
                    .foregroundColor(Theme.muted)
            }
            HStack {
                Text("产品")
                Spacer()
                Text("\(store.products.count) 个").foregroundColor(Theme.muted)
            }
            HStack {
                Text("数据占用")
                Spacer()
                Text(Fmt.fileSize(store.storageBytes())).foregroundColor(Theme.muted)
            }
            HStack {
                Text("累计收款 / 未收")
                Spacer()
                Text("\(Fmt.money(store.totalPaid)) / \(Fmt.money(store.totalUnpaid))")
                    .foregroundColor(Theme.muted)
            }
        } header: {
            Text("数据")
        } footer: {
            Text("数据保存在本机 App 沙盒内。卸载 App 会一并清除，重装前请先导出备份。")
        }
    }

    // MARK: 关于

    private var aboutSection: some View {
        Section {
            HStack {
                Text("版本")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundColor(Theme.muted)
            }
            Button {
                store.load()
                message = "已重新载入本地数据"
            } label: {
                Label("重新载入本地数据", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("关于")
        } footer: {
            Text("所有照片、客户资料与预约仅存储在本机，不上传任何服务器。")
        }
    }

    // MARK: 上传收款码

    private func loadQR(_ item: PhotosPickerItem?, kind: PaymentQRKind) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let img = UIImage(data: data) else {
                await MainActor.run { message = "图片读取失败，请重试" }
                return
            }
            await MainActor.run {
                if store.savePaymentQR(image: img, kind: kind) {
                    message = "\(kind.title)已保存"
                } else {
                    message = store.lastError ?? "保存失败"
                }
            }
        }
    }
}
