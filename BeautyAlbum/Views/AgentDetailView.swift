import SwiftUI
import UIKit

// MARK: - 代理详情

struct AgentDetailView: View {
    let agentID: UUID

    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var showEdit = false
    @State private var showOrder = false
    @State private var editingOrder: AgentOrder?
    @State private var showClientPicker = false
    @State private var showDeleteConfirm = false
    @State private var timeTarget: TimeTarget?
    @State private var copied: String?

    /// 改时间的目标：加入时间 / 某条拿货记录
    private enum TimeTarget: Identifiable, Equatable {
        case joined
        case order(UUID)

        var id: String {
            switch self {
            case .joined: return "joined"
            case .order(let oid): return oid.uuidString
            }
        }
    }

    private var a: Agent? { store.agent(agentID) }
    private var f: FeatureFlags { store.settings.features }

    var body: some View {
        ZStack {
            Theme.cream.ignoresSafeArea()

            if let a = a {
                ScrollView {
                    VStack(spacing: 12) {
                        header(a)

                        if f.agentParent { parentCard(a) }
                        if f.agentTime { timeCard(a) }
                        if f.agentQuantity { orderCard(a) }
                        if f.agentRelation { relationCard(a) }

                        noteCard(a)
                        deleteButton(a)
                    }
                    .padding(.horizontal, Metrics.hPadding)
                    .padding(.top, 6)
                    .padding(.bottom, 32)
                }
            } else {
                EmptyHint(icon: "person.crop.circle.badge.questionmark",
                          title: "代理已删除",
                          subtitle: "返回列表看看其他代理")
            }
        }
        .navigationTitle(a?.name ?? "代理详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showEdit = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let t = copied {
                Text(t)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.72))
                    .clipShape(Capsule())
                    .padding(.bottom, 26)
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showEdit) {
            AgentEditSheet(agentID: agentID)
        }
        .sheet(isPresented: $showOrder) {
            AgentOrderSheet(agentID: agentID, orderID: nil)
        }
        .sheet(item: $editingOrder) { o in
            AgentOrderSheet(agentID: agentID, orderID: o.id)
        }
        .sheet(isPresented: $showClientPicker) {
            AgentClientPicker(selected: Set(a?.clientIDs ?? [])) { set in
                guard var cur = store.agent(agentID) else { return }
                // 保持客户原有顺序，新增的按姓名排在后面
                let kept = cur.clientIDs.filter { set.contains($0) }
                let added = set.subtracting(kept)
                    .compactMap { store.client($0) }
                    .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
                    .map(\.id)
                cur.clientIDs = kept + added
                store.updateAgent(cur)
            }
        }
        .sheet(item: $timeTarget) { t in
            DateTimeEditorSheet(title: t == .joined ? "加入时间" : "拿货时间",
                                hint: hint(for: t),
                                initial: initialDate(for: t)) { d in
                applyTime(t, d)
            }
        }
        .alert("删除代理", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                store.deleteAgent(agentID)
                dismiss()
            }
        } message: {
            Text("将删除「\(a?.name ?? "")」的档案和 \(a?.orderCount ?? 0) 条拿货记录，无法撤销。")
        }
    }

    // MARK: 头部

    private func header(_ a: Agent) -> some View {
        CardBox(padding: 16) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    AgentAvatar(agent: a, size: 56)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(a.name.isEmpty ? "未命名" : a.name)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(Theme.ink)
                                .lineLimit(1)
                            AgentLevelBadge(level: a.level)
                        }
                        HStack(spacing: 8) {
                            Text("拿货 \(a.discountText)")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(Theme.roseDeep)
                            Text(a.displayRegion)
                                .font(.system(size: 11.5))
                                .foregroundColor(Theme.muted)
                        }
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                Rectangle().fill(Theme.line).frame(height: 0.8)

                HStack(spacing: 8) {
                    contactChip(icon: "phone.fill",
                                text: a.phone.isEmpty ? "未留电话" : a.phone,
                                copyText: a.phone)
                    contactChip(icon: "message.fill",
                                text: a.wechat.isEmpty ? "未填微信" : a.wechat,
                                copyText: a.wechat)
                }
            }
        }
    }

    private func contactChip(icon: String, text: String, copyText: String) -> some View {
        Button {
            guard !copyText.isEmpty else { return }
            UIPasteboard.general.string = copyText
            flash("已复制 \(copyText)")
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(text)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundColor(copyText.isEmpty ? Theme.muted : Theme.inkSoft)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            .background(Theme.cream)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: 父级关系

    private func parentCard(_ a: Agent) -> some View {
        let children = store.childAgents(of: a.id)
        let depth = store.agentDepth(a.id)
        let total = store.descendantCount(of: a.id)

        return CardBox(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "父级关系",
                              trailing: total > 0 ? "第 \(depth) 层 · 团队 \(total + 1) 人" : "第 \(depth) 层")

                // 上级
                HStack(spacing: 8) {
                    Text("上级")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.muted)
                        .frame(width: 40, alignment: .leading)

                    if let pid = a.parentID, let p = store.agent(pid) {
                        NavigationLink(value: p.id) {
                            HStack(spacing: 5) {
                                Text(p.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Theme.roseDeep)
                                AgentLevelBadge(level: p.level, compact: true)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(Theme.muted)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(a.parentName.isEmpty ? "无（顶层代理）" : "\(a.parentName)（已删除）")
                            .font(.system(size: 13))
                            .foregroundColor(a.parentName.isEmpty ? Theme.inkSoft : Theme.muted)
                    }
                    Spacer(minLength: 0)
                }

                // 完整链路
                let chain = store.ancestors(of: a.id)
                if chain.count > 1 {
                    HStack(spacing: 4) {
                        Text("链路")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.muted)
                            .frame(width: 40, alignment: .leading)
                        Text(chain.map(\.name).joined(separator: " › ") + " › \(a.name)")
                            .font(.system(size: 11.5))
                            .foregroundColor(Theme.inkSoft)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                }

                Rectangle().fill(Theme.line).frame(height: 0.8)

                // 直属下级
                HStack(spacing: 8) {
                    Text("下级")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.muted)
                        .frame(width: 40, alignment: .leading)
                    Text(children.isEmpty ? "暂无直属下级" : "直属 \(children.count) 人")
                        .font(.system(size: 12.5))
                        .foregroundColor(children.isEmpty ? Theme.muted : Theme.ink)
                    Spacer(minLength: 0)
                }

                ForEach(children) { c in
                    NavigationLink(value: c.id) {
                        HStack(spacing: 8) {
                            AgentAvatar(agent: c, size: 26)
                            Text(c.name.isEmpty ? "未命名" : c.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.ink)
                            AgentLevelBadge(level: c.level, compact: true)
                            Spacer(minLength: 0)
                            if f.agentQuantity {
                                Text(Fmt.money(c.totalAmount))
                                    .font(.system(size: 11.5))
                                    .foregroundColor(Theme.muted)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Theme.muted.opacity(0.6))
                        }
                        .padding(.leading, 40)
                        .frame(height: 30)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 时间

    private func timeCard(_ a: Agent) -> some View {
        CardBox(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "时间", trailing: "第 \(a.daysSinceJoined()) 天")

                timeRow("加入时间",
                        value: Fmt.dateTime.string(from: a.joinedAt),
                        editable: true) { timeTarget = .joined }

                if let last = a.lastOrderAt {
                    timeRow("最近拿货", value: Fmt.dateTime.string(from: last), editable: false, onEdit: nil)
                }
            }
        }
    }

    private func timeRow(_ title: String, value: String, editable: Bool,
                         onEdit: (() -> Void)?) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(Theme.muted)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.inkSoft)
            Spacer(minLength: 0)
            if editable, let onEdit = onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.roseDeep)
                        .frame(width: 26, height: 26)
                        .background(Theme.roseLight)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 拿货

    private func orderCard(_ a: Agent) -> some View {
        let sorted = a.orders.sorted { $0.createdAt > $1.createdAt }

        return CardBox(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "拿货记录", trailing: "\(a.orderCount) 笔")

                HStack(spacing: 0) {
                    miniStat("\(a.totalQuantity)", "件数")
                    miniStat(Fmt.money(a.totalAmount), "金额")
                    miniStat(Fmt.money(a.totalPaid), "已付")
                    miniStat(Fmt.money(a.totalUnpaid), "未结", highlight: a.totalUnpaid > 0)
                }

                if sorted.isEmpty {
                    Text("还没有拿货记录，点下面「记一笔」开始")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.muted)
                        .padding(.vertical, 6)
                } else {
                    Rectangle().fill(Theme.line).frame(height: 0.8)
                    ForEach(sorted) { o in
                        orderRow(o)
                    }
                }

                Button {
                    showOrder = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 12))
                        Text("记一笔拿货").font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(Theme.roseDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.roseLight)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func miniStat(_ value: String, _ label: String, highlight: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(highlight ? Theme.roseDeep : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private func orderRow(_ o: AgentOrder) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(o.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.ink)
                        .lineLimit(1)
                    if !o.specName.isEmpty {
                        Text(o.specName)
                            .font(.system(size: 10))
                            .foregroundColor(Theme.muted)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.cream)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 5) {
                    if f.agentTime {
                        Text(Fmt.dateOnly.string(from: o.createdAt))
                            .font(.system(size: 10.5))
                            .foregroundColor(Theme.muted)
                        Text("·")
                            .font(.system(size: 10.5))
                            .foregroundColor(Theme.muted)
                    }
                    Text("\(o.quantity) 件 × \(Fmt.money(o.unitPrice))")
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.muted)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.money(o.amount))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.ink)
                if o.unpaid > 0 {
                    Text("未结 \(Fmt.money(o.unpaid))")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.roseDeep)
                } else {
                    Text("已结清")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.muted)
                }
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                editingOrder = o
            } label: {
                Label("编辑这一笔", systemImage: "pencil")
            }
            if f.agentTime {
                Button {
                    timeTarget = .order(o.id)
                } label: {
                    Label("修改拿货时间", systemImage: "clock")
                }
            }
            Button(role: .destructive) {
                store.deleteOrder(o.id, agentID: agentID)
            } label: {
                Label("删除这一笔", systemImage: "trash")
            }
        }
        .onTapGesture {
            editingOrder = o
        }
    }

    // MARK: 人物关系（名下客户）

    private func relationCard(_ a: Agent) -> some View {
        let list = a.clientIDs.compactMap { store.client($0) }

        return CardBox(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "名下客户", trailing: "\(list.count) 位")

                if list.isEmpty {
                    Text("还没有关联客户，代理带来的客户可以挂在这里")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.muted)
                        .padding(.vertical, 4)
                } else {
                    ForEach(list) { c in
                        HStack(spacing: 8) {
                            ZStack {
                                Circle().fill(Theme.roseLight)
                                Text(String(c.name.prefix(1)))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Theme.roseDeep)
                            }
                            .frame(width: 26, height: 26)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.name.isEmpty ? "未命名" : c.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Theme.ink)
                                    .lineLimit(1)
                                Text(c.phone.isEmpty ? "未留电话" : c.phone)
                                    .font(.system(size: 10.5))
                                    .foregroundColor(Theme.muted)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Text("\(c.photos.count) 张")
                                .font(.system(size: 10.5))
                                .foregroundColor(Theme.muted)
                            Button {
                                guard var cur = store.agent(agentID) else { return }
                                cur.clientIDs.removeAll { $0 == c.id }
                                store.updateAgent(cur)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.muted)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(height: 34)
                    }
                }

                Button {
                    showClientPicker = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "person.badge.plus").font(.system(size: 12))
                        Text("关联客户").font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(Theme.roseDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.roseLight)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 备注

    private func noteCard(_ a: Agent) -> some View {
        CardBox(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "备注")
                Text(a.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? "暂无备注，点右上角编辑补充"
                     : a.note)
                    .font(.system(size: 13))
                    .foregroundColor(a.note.isEmpty ? Theme.muted : Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func deleteButton(_ a: Agent) -> some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Text("删除这位代理")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(red: 0.78, green: 0.28, blue: 0.30))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color(red: 0.98, green: 0.92, blue: 0.92))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: 时间处理

    private func initialDate(for t: TimeTarget) -> Date {
        guard let cur = store.agent(agentID) else { return Date() }
        switch t {
        case .joined:
            return cur.joinedAt
        case .order(let oid):
            return cur.orders.first { $0.id == oid }?.createdAt ?? Date()
        }
    }

    private func hint(for t: TimeTarget) -> String {
        switch t {
        case .joined:
            return "补录老代理时，可以把加入时间改成当初的日期，列表按它排序。"
        case .order:
            return "拿货时间用于按月统计业绩，改成实际发货日期更准确。"
        }
    }

    private func applyTime(_ t: TimeTarget, _ d: Date) {
        guard var cur = store.agent(agentID) else { return }
        switch t {
        case .joined:
            cur.joinedAt = d
            store.updateAgent(cur)
        case .order(let oid):
            guard let i = cur.orders.firstIndex(where: { $0.id == oid }) else { return }
            cur.orders[i].createdAt = d
            store.updateAgent(cur)
        }
    }

    private func flash(_ t: String) {
        withAnimation { copied = t }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation { copied = nil }
        }
    }
}

// MARK: - 客户关联选择器

struct AgentClientPicker: View {
    let onCommit: (Set<UUID>) -> Void

    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Set<UUID>
    @State private var query = ""

    init(selected: Set<UUID>, onCommit: @escaping (Set<UUID>) -> Void) {
        self.onCommit = onCommit
        _draft = State(initialValue: selected)
    }

    private var filtered: [Client] {
        let list = store.clients.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return list }
        return list.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.phone.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.clients.isEmpty {
                    Text("还没有客户，先去「客户」里建档")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.muted)
                }
                ForEach(filtered) { c in
                    Button {
                        if draft.contains(c.id) {
                            draft.remove(c.id)
                        } else {
                            draft.insert(c.id)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: draft.contains(c.id)
                                  ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 17))
                                .foregroundColor(draft.contains(c.id) ? Theme.roseDeep : Theme.muted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name.isEmpty ? "未命名" : c.name)
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.ink)
                                Text(c.phone.isEmpty ? "未留电话" : c.phone)
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.muted)
                            }
                            Spacer()
                            Text("\(c.photos.count) 张")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.muted)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .background(Theme.cream)
            .scrollContentBackground(.hidden)
            .navigationTitle("关联客户")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索姓名或电话")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onCommit(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
