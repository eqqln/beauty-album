import SwiftUI

enum DetailTab: String, CaseIterable, Identifiable {
    case album = "相册"
    case compare = "对比"
    case steps = "流程"
    case notes = "记录"
    case products = "产品"
    case pay = "收款"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .album: return "photo.on.rectangle.angled"
        case .compare: return "rectangle.split.2x1"
        case .steps: return "list.bullet.clipboard"
        case .notes: return "text.alignleft"
        case .products: return "shippingbox"
        case .pay: return "qrcode"
        }
    }
}

struct ClientDetailView: View {
    let clientID: UUID
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var tab: DetailTab = .album
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showCreatedEditor = false
    @State private var createdDraft = Date()

    private var index: Int? { store.index(of: clientID) }
    private var client: Client? { index.map { store.clients[$0] } }

    private var clientBinding: Binding<Client> {
        Binding(
            get: { self.client ?? Client() },
            set: { newValue in
                if let i = store.index(of: clientID) { store.clients[i] = newValue }
            }
        )
    }

    /// 受功能开关控制的可显示标签页
    private var availableTabs: [DetailTab] {
        let f = store.settings.features
        var list: [DetailTab] = [.album]
        if f.compare { list.append(.compare) }
        if f.steps { list.append(.steps) }
        if f.notes { list.append(.notes) }
        if f.products { list.append(.products) }
        if f.payments { list.append(.pay) }
        return list
    }

    var body: some View {
        ZStack {
            Theme.cream.ignoresSafeArea()

            if let client {
                VStack(spacing: 0) {
                    header(client)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                    SegmentedTabs(selection: $tab, tabs: availableTabs)
                        .padding(.bottom, 10)

                    ScrollView {
                        VStack(spacing: 14) {
                            switch tab {
                            case .album:
                                AlbumView(clientID: clientID, client: clientBinding)
                            case .compare:
                                CompareView(clientID: clientID, client: clientBinding)
                            case .steps:
                                StepsView(client: clientBinding)
                            case .notes:
                                NotesView(client: clientBinding)
                            case .products:
                                ClientProductsView(client: clientBinding)
                            case .pay:
                                PaymentView(clientID: clientID, client: clientBinding)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 40)
                    }
                }
            } else {
                EmptyHint(icon: "person.crop.circle.badge.questionmark",
                          title: "客户不存在", subtitle: "可能已被删除")
            }
        }
        .onAppear {
            if !availableTabs.contains(tab) { tab = .album }
        }
        .navigationTitle(client?.name ?? "客户")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showEdit = true
                    } label: {
                        Label("编辑资料", systemImage: "square.and.pencil")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("删除客户", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            ClientEditSheet(clientID: clientID)
        }
        .sheet(isPresented: $showCreatedEditor) {
            DateTimeEditorSheet(
                title: "修改建档时间",
                hint: "建档时间会随备份一起保存，补录老客户时可以直接改成当初添加的日期。",
                initial: createdDraft
            ) { d in
                store.updateClient(clientID) { $0.createdAt = d }
                store.save()
            }
        }
        .alert("删除客户", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                store.deleteClient(clientID)
                dismiss()
            }
        } message: {
            Text("将删除该客户的全部照片与记录，无法撤销。")
        }
    }

    // MARK: 头部

    private func header(_ c: Client) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.roseLight)
                    Text(String(c.name.prefix(1)))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(Theme.roseDeep)
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 4) {
                    Text(c.name.isEmpty ? "未命名客户" : c.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.ink)
                    if c.phone.isEmpty {
                        Text("未填写联系方式")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.muted)
                    } else {
                        Button {
                            call(c.phone)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "phone.fill").font(.system(size: 10))
                                Text(c.phone).font(.system(size: 12))
                            }
                            .foregroundColor(Theme.roseDeep)
                        }
                    }
                }
                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(c.photos.count)")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Theme.ink)
                    Text("张照片")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.muted)
                }
            }

            VStack(spacing: 6) {
                HStack {
                    Text(c.currentStageTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.inkSoft)
                        .lineLimit(1)
                    Spacer()
                    Text("\(c.sequentialDoneCount)/\(c.steps.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.roseDeep)
                }
                ProgressBar(value: c.progress)

                // 建档（添加）时间，点一下就能改
                HStack(spacing: 4) {
                    Button {
                        createdDraft = c.createdAt
                        showCreatedEditor = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 9, weight: .medium))
                            Text("建档 \(Fmt.dateTime.string(from: c.createdAt))")
                                .font(.system(size: 10))
                            Image(systemName: "pencil")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .foregroundColor(Theme.muted)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    if let last = c.steps.compactMap({ $0.doneAt }).max() {
                        Text("最近进展 \(Fmt.dateOnly.string(from: last))")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.muted.opacity(0.85))
                    }
                }
                .frame(height: 13)
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.line, lineWidth: 0.8)
        )
    }

    private func call(_ phone: String) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty, let url = URL(string: "tel://\(digits)") else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - 分段标签

struct SegmentedTabs: View {
    @Binding var selection: DetailTab
    let tabs: [DetailTab]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(tabs) { t in
                    let active = t == selection
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) { selection = t }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: t.icon)
                                .font(.system(size: 9, weight: .medium))
                            Text(t.rawValue)
                                .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                        }
                        .foregroundColor(active ? .white : Theme.inkSoft)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(
                            Group {
                                if active {
                                    AnyView(Theme.gradRose)
                                } else {
                                    AnyView(Theme.card)
                                }
                            }
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(active ? Color.clear : Theme.line, lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - 客户编辑

struct ClientEditSheet: View {
    /// nil 表示新建
    let clientID: UUID?

    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var phone = ""
    @State private var note = ""
    @State private var createdAt = Date()
    @State private var loaded = false

    private var isNew: Bool { clientID == nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("姓名", text: $name)
                        .textInputAutocapitalization(.never)
                    TextField("联系方式（手机号 / 微信）", text: $phone)
                        .keyboardType(.default)
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("基本信息")
                }

                Section {
                    DatePicker("建档时间", selection: $createdAt,
                               displayedComponents: [.date, .hourAndMinute])
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                } footer: {
                    Text("默认是当前时间。补录老客户时改成当初添加的日期即可，之后在客户详情页也能随时修改。")
                }

                Section {
                    TextEditor(text: $note)
                        .frame(minHeight: 110)
                        .overlay(alignment: .topLeading) {
                            if note.isEmpty {
                                Text("客户偏好、皮肤状况、过敏史、消费习惯……")
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.muted.opacity(0.7))
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("备注")
                } footer: {
                    Text("备注会随备份一起导出，恢复后完整保留。")
                }

                if isNew {
                    Section {
                        HStack {
                            Text("默认流程")
                            Spacer()
                            Text(store.settings.stepTemplate.joined(separator: " → "))
                                .font(.system(size: 12))
                                .foregroundColor(Theme.muted)
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                        }
                    } footer: {
                        Text("可在「设置 → 流程模板」中修改，之后还能针对单个客户调整。")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.cream)
            .navigationTitle(isNew ? "新建客户" : "编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let id = clientID, let c = store.client(id) {
            name = c.name
            phone = c.phone
            note = c.note
            createdAt = c.createdAt
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let p = phone.trimmingCharacters(in: .whitespaces)
        if let id = clientID {
            store.updateClient(id) { c in
                c.name = n
                c.phone = p
                c.note = note
                c.createdAt = createdAt
            }
            store.save()
        } else {
            _ = store.addClient(name: n, phone: p, note: note, createdAt: createdAt)
        }
        dismiss()
    }
}
