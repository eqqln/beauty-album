import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var scenePhase

    @State private var backgroundedAt: Date?
    @State private var tab: Int = 0

    var body: some View {
        Group {
            if store.settings.lockEnabled && !store.isUnlocked {
                LockScreen()
            } else {
                mainTabs
            }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                backgroundedAt = Date()
            case .active:
                if let t = backgroundedAt {
                    let limit = Double(max(0, store.settings.autoLockMinutes)) * 60
                    if Date().timeIntervalSince(t) >= limit {
                        store.lockNow()
                    }
                }
                backgroundedAt = nil
            default:
                break
            }
        }
        .onChange(of: store.settings.features) { _ in
            if !isTabAvailable(tab) { tab = 0 }
        }
    }

    private var mainTabs: some View {
        TabView(selection: $tab) {
            ClientListView()
                .tag(0)
                .tabItem { Label("客户", systemImage: "person.2.fill") }

            if store.settings.features.teachers {
                TeacherListView()
                    .tag(1)
                    .tabItem { Label("老师", systemImage: "sparkles") }
            }

            if store.settings.features.appointments {
                AppointmentListView()
                    .tag(2)
                    .tabItem { Label("预约", systemImage: "calendar") }
            }

            if store.settings.features.products {
                ProductListView()
                    .tag(3)
                    .tabItem { Label("产品", systemImage: "shippingbox.fill") }
            }
        }
        .tint(Theme.roseDeep)
    }

    private func isTabAvailable(_ t: Int) -> Bool {
        switch t {
        case 1: return store.settings.features.teachers
        case 2: return store.settings.features.appointments
        case 3: return store.settings.features.products
        default: return true
        }
    }
}

enum ClientSort: String, CaseIterable, Identifiable {
    case recent = "最近建档"
    case name = "按姓名"
    case progress = "按进度"

    var id: String { rawValue }
}

struct ClientListView: View {
    @EnvironmentObject var store: Store

    @State private var query = ""
    @State private var sort: ClientSort = .recent
    @State private var showAdd = false
    @State private var showSettings = false
    @State private var pendingDelete: Client?
    @State private var path = NavigationPath()
    /// 临时展开全部客户（不改变后台设置）
    @State private var showAll = false

    private var layout: ClientListLayout { store.settings.clientLayout }
    private var columns: Int { min(3, max(2, store.settings.clientColumns)) }
    private var limit: Int { max(0, store.settings.homeClientLimit) }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    /// 被数量上限截掉的客户数
    private var hiddenCount: Int { max(0, filtered.count - shown.count) }

    /// 实际渲染的客户：搜索时不受数量上限影响，方便找人
    private var shown: [Client] {
        guard limit > 0, !showAll, !isSearching else { return filtered }
        return Array(filtered.prefix(limit))
    }

    private var filtered: [Client] {
        var list = store.clients
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(q) ||
                $0.phone.localizedCaseInsensitiveContains(q) ||
                $0.note.localizedCaseInsensitiveContains(q)
            }
        }
        switch sort {
        case .recent: list.sort { $0.createdAt > $1.createdAt }
        case .name: list.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .progress: list.sort { $0.progress > $1.progress }
        }
        return list
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.cream.ignoresSafeArea()

                if store.clients.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: Metrics.gridSpacing) {
                            summaryBar

                            if layout == .grid {
                                gridContent
                            } else {
                                listContent
                            }

                            if filtered.isEmpty {
                                EmptyHint(icon: "magnifyingglass", title: "没有匹配的客户",
                                          subtitle: "换个姓名或电话试试")
                            } else if hiddenCount > 0 {
                                moreButton
                            } else if showAll && limit > 0 && !isSearching {
                                collapseButton
                            }
                        }
                        .padding(.horizontal, Metrics.hPadding)
                        .padding(.top, 4)
                        .padding(.bottom, 28)
                    }
                }
            }
            .navigationTitle(store.settings.shopName)
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "搜索姓名或电话")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Picker("排序", selection: $sort) {
                            ForEach(ClientSort.allCases) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                ClientDetailView(clientID: id)
            }
            .sheet(isPresented: $showAdd) {
                ClientEditSheet(clientID: nil)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onChange(of: store.settings.homeClientLimit) { _ in showAll = false }
            .onChange(of: store.settings.clientLayout) { _ in showAll = false }
            .alert("删除客户", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ), presenting: pendingDelete) { c in
                Button("取消", role: .cancel) { pendingDelete = nil }
                Button("删除", role: .destructive) {
                    store.deleteClient(c.id)
                    pendingDelete = nil
                }
            } message: { c in
                Text("将同时删除「\(c.name)」的 \(c.photos.count) 张照片和全部记录，无法撤销。建议先做一次备份。")
            }
        }
    }

    // MARK: 横排 / 竖排

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Metrics.gridSpacing), count: columns)
    }

    private var gridContent: some View {
        LazyVGrid(columns: gridColumns, spacing: Metrics.gridSpacing) {
            ForEach(shown) { client in
                NavigationLink(value: client.id) {
                    ClientGridCard(client: client, columns: columns)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        path.append(client.id)
                    } label: {
                        Label("打开相册", systemImage: "photo.on.rectangle")
                    }
                    Button(role: .destructive) {
                        pendingDelete = client
                    } label: {
                        Label("删除客户", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var listContent: some View {
        VStack(spacing: 8) {
            ForEach(shown) { client in
                NavigationLink(value: client.id) {
                    ClientRow(client: client, showsCover: store.settings.showClientCover)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        path.append(client.id)
                    } label: {
                        Label("打开相册", systemImage: "photo.on.rectangle")
                    }
                    Button(role: .destructive) {
                        pendingDelete = client
                    } label: {
                        Label("删除客户", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var moreButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { showAll = true }
        } label: {
            HStack(spacing: 5) {
                Text("查看全部 \(filtered.count) 位客户")
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Theme.roseDeep)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Theme.roseLight)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private var collapseButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { showAll = false }
        } label: {
            HStack(spacing: 5) {
                Text("收起，只看前 \(limit) 位")
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Theme.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.line, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    // MARK: 统计条

    private var summaryBar: some View {
        HStack(spacing: 0) {
            statItem(value: "\(store.clients.count)", label: "客户")
            divider
            statItem(value: "\(store.totalPhotoCount)", label: "照片")
            divider
            statItem(value: Fmt.money(store.totalPaid), label: "累计收款")
        }
        .padding(.vertical, 12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.line, lineWidth: 0.8)
        )
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(width: 0.8, height: 26)
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.roseDeep)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 空状态

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Theme.roseLight)
                    .frame(width: 96, height: 96)
                Image(systemName: "photo.stack")
                    .font(.system(size: 38, weight: .ultraLight))
                    .foregroundColor(Theme.roseDeep)
            }
            VStack(spacing: 6) {
                Text("还没有客户")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.ink)
                Text("每位客户一个独立相册\n记录\(store.settings.beforeLabel)与\(store.settings.afterLabel)对比")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            Button {
                showAdd = true
            } label: {
                Label("新建第一位客户", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .frame(maxWidth: 220)
            .padding(.top, 4)

            Button("先做备份 / 恢复设置") { showSettings = true }
                .font(.system(size: 13))
                .foregroundColor(Theme.roseDeep)
                .padding(.top, 2)
        }
        .padding(32)
    }
}

// MARK: - 客户行

struct ClientRow: View {
    let client: Client
    var showsCover: Bool = true
    @EnvironmentObject var store: Store

    private var coverURL: URL? {
        guard let p = client.coverPhoto else { return nil }
        return store.photoURL(clientID: client.id, fileName: p.fileName)
    }

    var body: some View {
        HStack(spacing: 12) {
            if showsCover {
                LocalImage(url: coverURL)
                    .frame(width: Metrics.thumbSize, height: Metrics.thumbSize)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.line, lineWidth: 0.8)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(client.name.isEmpty ? "未命名客户" : client.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(client.photos.count) 张")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.muted)
                }
                .frame(height: 19)

                Text(client.phone.isEmpty ? "未留电话" : client.phone)
                    .font(.system(size: 12))
                    .foregroundColor(client.phone.isEmpty ? Theme.muted.opacity(0.7) : Theme.inkSoft)
                    .lineLimit(1)
                    .frame(height: 15)

                HStack(spacing: 6) {
                    ProgressBar(value: client.progress, height: 4)
                        .frame(width: 62)
                    Text(client.currentStageTitle)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.muted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if client.totalPaid > 0 {
                        Text(Fmt.money(client.totalPaid))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.roseDeep)
                    }
                }
                .frame(height: 14)
            }
            .frame(height: 56)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.muted.opacity(0.6))
        }
        .padding(12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.line, lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 2)
    }
}

// MARK: - 横排客户卡片

/// 首页横排布局用的大卡片：封面 + 姓名 + 电话/阶段 + 进度。
/// 高度由 `Metrics.clientCardHeight(columns:)` 固定，任意客户都等高。
struct ClientGridCard: View {
    let client: Client
    let columns: Int
    @EnvironmentObject var store: Store

    private var coverURL: URL? {
        guard let p = client.coverPhoto else { return nil }
        return store.photoURL(clientID: client.id, fileName: p.fileName)
    }

    private var subtitle: String {
        if !client.phone.isEmpty { return client.phone }
        return client.currentStageTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(Theme.placeholder)
                LocalImage(url: coverURL)

                HStack(spacing: 3) {
                    Image(systemName: "photo")
                        .font(.system(size: 8, weight: .semibold))
                    Text("\(client.photos.count)")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.34))
                .clipShape(Capsule())
                .padding(6)
            }
            .frame(height: Metrics.gridCoverHeight(columns: columns))
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(client.name.isEmpty ? "未命名客户" : client.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.ink)
                    .lineLimit(1)
                    .frame(height: 18)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.muted)
                    .lineLimit(1)
                    .frame(height: 13)

                ProgressBar(value: client.progress, height: 3)
            }
            .padding(.horizontal, 8)
            .padding(.top, 7)
            .frame(height: 56, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.clientCardHeight(columns: columns))
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.line, lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 2)
    }
}
