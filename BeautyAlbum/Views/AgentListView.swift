import SwiftUI

// MARK: - 代理头像

struct AgentAvatar: View {
    let agent: Agent
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle().fill(Theme.roseLight)
            Text(agent.initial)
                .font(.system(size: size * 0.40, weight: .medium))
                .foregroundColor(Theme.roseDeep)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Theme.card, lineWidth: 2))
    }
}

// MARK: - 等级徽标

struct AgentLevelBadge: View {
    let level: AgentLevel
    var compact: Bool = false

    private var tint: Color {
        switch level {
        case .partner: return Color(red: 0.72, green: 0.52, blue: 0.20)
        case .general: return Theme.roseDeep
        case .first: return Color(red: 0.44, green: 0.48, blue: 0.66)
        case .second: return Color(red: 0.36, green: 0.58, blue: 0.50)
        case .retail: return Theme.muted
        }
    }

    var body: some View {
        Text(level.rawValue)
            .font(.system(size: compact ? 9 : 10, weight: .semibold))
            .foregroundColor(tint)
            .padding(.horizontal, compact ? 5 : 6)
            .padding(.vertical, compact ? 1.5 : 2)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - 代理列表

struct AgentListView: View {
    @EnvironmentObject var store: Store

    @State private var query = ""
    @State private var showAdd = false
    @State private var pendingDelete: Agent?
    @State private var path = NavigationPath()

    private var f: FeatureFlags { store.settings.features }

    private var filtered: [Agent] {
        var list = store.sortedAgents
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(q) ||
                $0.phone.localizedCaseInsensitiveContains(q) ||
                $0.wechat.localizedCaseInsensitiveContains(q) ||
                $0.region.localizedCaseInsensitiveContains(q) ||
                $0.level.rawValue.localizedCaseInsensitiveContains(q) ||
                $0.parentName.localizedCaseInsensitiveContains(q)
            }
        }
        return list
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.cream.ignoresSafeArea()

                if store.agents.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: Metrics.gridSpacing) {
                            summaryBar

                            if filtered.isEmpty {
                                EmptyHint(icon: "magnifyingglass", title: "没有匹配的代理",
                                          subtitle: "换个姓名、电话或地区试试")
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(filtered) { a in
                                        NavigationLink(value: a.id) {
                                            AgentRow(agent: a,
                                                     showParent: f.agentParent,
                                                     showTime: f.agentTime,
                                                     showQuantity: f.agentQuantity,
                                                     showRelation: f.agentRelation)
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button {
                                                path.append(a.id)
                                            } label: {
                                                Label("打开详情", systemImage: "person.text.rectangle")
                                            }
                                            Button(role: .destructive) {
                                                pendingDelete = a
                                            } label: {
                                                Label("删除代理", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, Metrics.hPadding)
                        .padding(.top, 4)
                        .padding(.bottom, 28)
                    }
                }
            }
            .navigationTitle("代理商")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "搜索姓名、电话、上级")
            .toolbar {
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
                AgentDetailView(agentID: id)
            }
            .sheet(isPresented: $showAdd) {
                AgentEditSheet(agentID: nil)
            }
            .alert("删除代理", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ), presenting: pendingDelete) { a in
                Button("取消", role: .cancel) { pendingDelete = nil }
                Button("删除", role: .destructive) {
                    store.deleteAgent(a.id)
                    pendingDelete = nil
                }
            } message: { a in
                Text("将删除「\(a.name)」的档案和 \(a.orderCount) 条拿货记录。名下下级代理会变成顶层，不会被删除。")
            }
        }
    }

    // MARK: 统计条

    private var summaryBar: some View {
        CardBox(padding: 14) {
            HStack(spacing: 0) {
                statItem("\(store.agents.count)", "代理总数")

                if f.agentParent {
                    statDivider
                    statItem("\(store.rootAgents.count)", "顶层")
                }

                if f.agentQuantity {
                    statDivider
                    statItem("\(store.totalAgentOrderQuantity)", "累计件数")
                    statDivider
                    statItem(Fmt.money(store.totalAgentOrderAmount), "累计拿货")
                }
            }
        }
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(width: 0.8, height: 26)
    }

    private func statItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Theme.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 空状态

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 14) {
                EmptyHint(icon: "person.crop.circle.badge.plus",
                          title: "还没有代理",
                          subtitle: "把拿货的代理建进来，记录加入时间、上下级关系、拿货数量与名下客户",
                          action: { showAdd = true },
                          actionTitle: "添加第一位代理")

                if f.agentParent || f.agentQuantity || f.agentRelation || f.agentTime {
                    CardBox(padding: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("当前开启的代理功能")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.inkSoft)
                            featureLine(f.agentParent, "父级关系", "上级与下级树")
                            featureLine(f.agentQuantity, "数量", "拿货件数与金额")
                            featureLine(f.agentRelation, "人物关系", "代理名下客户")
                            featureLine(f.agentTime, "时间", "加入时间、拿货时间")
                        }
                    }
                }
            }
            .padding(.horizontal, Metrics.hPadding)
            .padding(.top, 20)
        }
    }

    private func featureLine(_ on: Bool, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundColor(on ? Theme.roseDeep : Theme.muted)
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(on ? Theme.ink : Theme.muted)
            Text(sub)
                .font(.system(size: 11))
                .foregroundColor(Theme.muted)
            Spacer()
        }
    }
}

// MARK: - 列表行

struct AgentRow: View {
    @EnvironmentObject var store: Store

    let agent: Agent
    var showParent: Bool
    var showTime: Bool
    var showQuantity: Bool
    var showRelation: Bool

    private var metaText: String {
        var parts: [String] = []
        if showParent {
            parts.append(agent.parentName.isEmpty ? "顶层代理" : "上级 \(agent.parentName)")
        }
        if showTime {
            parts.append("加入 " + Fmt.dateOnly.string(from: agent.joinedAt))
        }
        if parts.isEmpty {
            parts.append(agent.displayRegion)
        }
        return parts.joined(separator: " · ")
    }

    private var amountText: String {
        var parts: [String] = []
        if showQuantity {
            parts.append("\(agent.totalQuantity) 件")
            parts.append(Fmt.money(agent.totalAmount))
            if agent.totalUnpaid > 0 {
                parts.append("未结 " + Fmt.money(agent.totalUnpaid))
            }
        }
        if showParent {
            let n = store.descendantCount(of: agent.id)
            if n > 0 { parts.append("下级 \(n) 人") }
        }
        if showRelation, !agent.clientIDs.isEmpty {
            parts.append("客户 \(agent.clientIDs.count) 人")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 11) {
            AgentAvatar(agent: agent, size: 46)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(agent.name.isEmpty ? "未命名" : agent.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.ink)
                        .lineLimit(1)
                    AgentLevelBadge(level: agent.level)
                    Spacer(minLength: 0)
                }
                .frame(height: 22)

                Text(metaText)
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.inkSoft)
                    .lineLimit(1)
                    .frame(height: 16)

                if amountText.isEmpty {
                    Text(agent.phone.isEmpty ? "未留电话" : agent.phone)
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.muted)
                        .lineLimit(1)
                        .frame(height: 16)
                } else {
                    Text(amountText)
                        .font(.system(size: 11.5))
                        .foregroundColor(agent.totalUnpaid > 0 ? Theme.roseDeep : Theme.muted)
                        .lineLimit(1)
                        .frame(height: 16)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.muted.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: 78)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.line, lineWidth: 0.8)
        )
    }
}
