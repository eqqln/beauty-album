import SwiftUI
import UniformTypeIdentifiers

struct BackupView: View {
    @EnvironmentObject var store: Store

    @State private var building = false
    @State private var lastResult: BackupService.BuildResult?
    @State private var restoring = false
    @State private var showImporter = false
    @State private var pendingZip: URL?
    @State private var showRestoreChoice = false
    @State private var message: String?
    @State private var messageIsError = false
    @State private var existing: [(url: URL, date: Date, size: Int64)] = []

    var body: some View {
        ZStack {
            Theme.cream.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    statsCard
                    autoCard
                    backupCard
                    restoreCard
                    cloudCard
                    existingCard
                }
                .padding(16)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshList() }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: false) { result in
            handlePicked(result)
        }
        .confirmationDialog("恢复方式", isPresented: $showRestoreChoice, titleVisibility: .visible) {
            Button("覆盖恢复（清空现有数据）", role: .destructive) {
                if let z = pendingZip { runRestore(z, merge: false) }
            }
            Button("合并恢复（保留现有，追加新客户）") {
                if let z = pendingZip { runRestore(z, merge: true) }
            }
            Button("取消", role: .cancel) { pendingZip = nil }
        } message: {
            Text("覆盖恢复会用备份完全替换当前全部客户数据；合并恢复只补充备份里当前不存在的客户。")
        }
        .alert(message ?? "", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好") { message = nil }
        }
    }

    // MARK: 统计

    private var statsCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                stat("\(store.clients.count)", "客户")
                divider
                stat("\(store.totalPhotoCount)", "照片")
                divider
                stat(Fmt.fileSize(store.storageBytes()), "占用")
            }
            if building || restoring {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text(building ? "正在打包，请勿退出……" : "正在恢复数据……")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.inkSoft)
                }
            }
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 3) {
            Text(v)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.roseDeep)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(l).font(.system(size: 11)).foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(width: 0.8, height: 26)
    }

    // MARK: 自动备份

    private var autoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SectionHeader(title: "自动备份")
                Spacer()
                Toggle("", isOn: $store.settings.autoBackupEnabled)
                    .labelsHidden()
                    .tint(Theme.rose)
            }

            if store.settings.autoBackupEnabled {
                HStack {
                    Text("每隔几天备份")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.inkSoft)
                    Spacer()
                    Picker("", selection: $store.settings.autoBackupDays) {
                        ForEach([2, 3, 5, 7, 10, 15, 30], id: \.self) { d in
                            Text("\(d) 天").tag(d)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.roseDeep)
                }

                HStack {
                    Text("每天几点执行")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.inkSoft)
                    Spacer()
                    DatePicker("", selection: autoTimeBinding,
                               displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                }

                HStack {
                    Text("最多保留")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.inkSoft)
                    Spacer()
                    Picker("", selection: $store.settings.autoBackupKeep) {
                        ForEach([3, 5, 10, 20], id: \.self) { k in
                            Text("\(k) 份").tag(k)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.roseDeep)
                }

                Divider().background(Theme.line)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10))
                        Text("下次备份：\(nextAutoText)")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(Theme.inkSoft)

                    if let last = store.settings.lastAutoBackupAt {
                        Text("上次完成：\(Fmt.dateTime.string(from: last))")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.muted)
                    } else {
                        Text("还没执行过，点下方按钮可以立刻备一次")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.muted)
                    }

                    if let note = store.autoBackupNote {
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.roseDeep)
                    }
                }

                Button {
                    store.performAutoBackup()
                } label: {
                    HStack(spacing: 6) {
                        if store.autoBackupRunning {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "bolt.fill")
                        }
                        Text(store.autoBackupRunning ? "备份中…" : "现在备份一次")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.roseDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.roseLight)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(store.autoBackupRunning || building || restoring)

                Text("iOS 不允许 App 在后台自己定时跑，所以到点后需要打开一次 App 才会执行；开着 App 时到点也会自动跑。备份文件存在「文件 → 我的 iPhone → 美颜相册 → exports」。")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("开启后，每隔几天自动把全部客户数据打包一份到本机，不用记着手动导。")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    private var autoTimeBinding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = store.settings.autoBackupHour
                comps.minute = store.settings.autoBackupMinute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                store.settings.autoBackupHour = c.hour ?? 21
                store.settings.autoBackupMinute = c.minute ?? 0
            }
        )
    }

    private var nextAutoText: String {
        let s = store.settings
        let cal = Calendar.current
        guard let base = s.lastAutoBackupAt ?? Date(),
              let due = cal.date(byAdding: .day, value: max(1, s.autoBackupDays), to: base),
              let slot = cal.date(bySettingHour: s.autoBackupHour,
                                  minute: s.autoBackupMinute, second: 0, of: due)
        else { return "—" }
        return Fmt.dateTime.string(from: slot)
    }

    // MARK: 备份

    private var backupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "导出备份", trailing: "ZIP")

            Text("把所有客户的照片、备注、流程进度、收款记录打包成一个 ZIP。\n目录按「客户姓名 / \(store.settings.beforeLabel) · \(store.settings.afterLabel)」整理，解压后可直接翻看。")
                .font(.system(size: 12))
                .foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                build()
            } label: {
                HStack(spacing: 6) {
                    if building {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        Image(systemName: "shippingbox")
                    }
                    Text(building ? "打包中…" : "生成备份文件")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(building || restoring)

            if let r = lastResult {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(Theme.roseDeep)
                        Text("已生成：\(r.clientCount) 位客户 · \(r.photoCount) 张照片 · \(Fmt.fileSize(r.bytes))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.ink)
                    }

                    HStack(spacing: 8) {
                        ShareLink(item: r.url) {
                            Label("存储到文件 / 网盘", systemImage: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Theme.gradRose)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        Text(r.url.lastPathComponent)
                            .font(.system(size: 10))
                            .foregroundColor(Theme.muted)
                            .lineLimit(2)
                    }
                }
                .padding(12)
                .background(Theme.roseLight.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    // MARK: 恢复

    private var restoreCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "从备份恢复")

            Text("选择之前导出的 ZIP 文件。换手机、重装 App 后用它把数据搬回来。\n如果备份就在本机，直接点下方「本机备份」右侧的 ↻ 按钮，不用再选一次。")
                .font(.system(size: 12))
                .foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showImporter = true
            } label: {
                HStack(spacing: 6) {
                    if restoring {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.down.doc")
                    }
                    Text(restoring ? "恢复中…" : "选择备份文件")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.roseDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.roseLight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(building || restoring)
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    // MARK: 网盘

    private var cloudCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "备份到网盘")

            Text("点「存储到文件 / 网盘」后，在系统分享面板里选择已安装的网盘 App，即可直接上传：")
                .font(.system(size: 12))
                .foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 7) {
                cloudRow("百度网盘", "选择「保存到百度网盘」", "cloud.fill")
                cloudRow("夸克网盘", "选择「保存到夸克」", "cloud.fill")
                cloudRow("阿里云盘 / 腾讯微云 / 115", "同一入口，选择对应 App", "cloud.fill")
                cloudRow("iCloud Drive / 本机「文件」", "选择「存储到文件」", "folder.fill")
            }

            Text("第一次使用需先在网盘 App 里登录并允许本应用访问。恢复时从网盘下载 ZIP 到「文件」，再回到这里选择。")
                .font(.system(size: 11))
                .foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    private func cloudRow(_ name: String, _ hint: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(Theme.roseDeep)
                .frame(width: 18)
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.ink)
            Spacer()
            Text(hint)
                .font(.system(size: 11))
                .foregroundColor(Theme.muted)
        }
    }

    // MARK: 已有备份

    private var existingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "本机备份", trailing: existing.isEmpty ? nil : "\(existing.count) 个")

            if existing.isEmpty {
                Text("还没有生成过备份")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
            } else {
                ForEach(Array(existing.prefix(8).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 10) {
                        Image(systemName: "doc.zipper")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.roseDeep)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.url.deletingPathExtension().lastPathComponent)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Theme.ink)
                                .lineLimit(1)
                            Text("\(Fmt.dateTime.string(from: item.date)) · \(Fmt.fileSize(item.size))")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.muted)
                        }
                        Spacer()
                        Button {
                            pendingZip = item.url
                            showRestoreChoice = true
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(Theme.rose)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        ShareLink(item: item.url) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.roseDeep)
                                .frame(width: 30, height: 30)
                        }
                        Button {
                            try? FileManager.default.removeItem(at: item.url)
                            refreshList()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.muted)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    // MARK: 动作

    private func refreshList() {
        existing = BackupService.existingBackups(in: store.exportsURL)
    }

    /// 从「文件」里选到备份包之后
    private func handlePicked(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let u = urls.first else { return }
            let accessed = u.startAccessingSecurityScopedResource()
            defer { if accessed { u.stopAccessingSecurityScopedResource() } }

            // 网盘 / 外置目录里的文件先拷到本地，避免恢复中途读不到
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("import-\(UUID().uuidString).zip")
            try? FileManager.default.removeItem(at: copy)
            do {
                try FileManager.default.copyItem(at: u, to: copy)
            } catch {
                show("这个文件读不出来：\(error.localizedDescription)\n如果在网盘里，先下载到「文件」再选。", error: true)
                return
            }

            guard BackupService.looksLikeZip(copy) else {
                try? FileManager.default.removeItem(at: copy)
                show("选中的不是备份 ZIP，请选导出时生成的那个 .zip 文件。", error: true)
                return
            }

            pendingZip = copy
            showRestoreChoice = true

        case .failure(let e):
            show("选择文件失败：\(e.localizedDescription)", error: true)
        }
    }

    private func build() {
        building = true
        lastResult = nil
        Task {
            do {
                let r = try await BackupService.build(store: store)
                await MainActor.run {
                    lastResult = r
                    building = false
                    refreshList()
                    show("备份完成：\(Fmt.fileSize(r.bytes))", error: false)
                }
            } catch {
                await MainActor.run {
                    building = false
                    show("备份失败：\(error.localizedDescription)", error: true)
                }
            }
        }
    }

    private func runRestore(_ zip: URL, merge: Bool) {
        restoring = true
        pendingZip = nil
        Task {
            do {
                let r = try await BackupService.restore(zipURL: zip, store: store, merge: merge)
                await MainActor.run {
                    restoring = false
                    refreshList()
                    show("\(r.merged ? "合并" : "覆盖")恢复完成：\(r.clientCount) 位客户、\(r.photoCount) 张照片", error: false)
                }
            } catch {
                await MainActor.run {
                    restoring = false
                    show("恢复失败：\(error.localizedDescription)", error: true)
                }
            }
        }
    }

    private func show(_ text: String, error: Bool) {
        messageIsError = error
        message = text
    }
}
