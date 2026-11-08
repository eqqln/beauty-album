import SwiftUI

struct ClientProductsView: View {
    @Binding var client: Client
    @EnvironmentObject var store: Store

    @State private var showPicker = false
    @State private var toast: String?

    private var claimed: [ProductClaim] {
        client.claims.filter(\.claimed).sorted { ($0.claimedAt ?? $0.createdAt) > ($1.claimedAt ?? $1.createdAt) }
    }

    private var pending: [ProductClaim] {
        client.claims.filter { !$0.claimed }.sorted { $0.createdAt > $1.createdAt }
    }

    /// 产品库里还没给这位客户登记过的产品
    private var unlinked: [Product] {
        let linked = Set(client.claims.map(\.productID))
        return store.sortedProducts.filter { !linked.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 14) {
            statsCard

            if client.claims.isEmpty && unlinked.isEmpty {
                EmptyHint(icon: "shippingbox",
                          title: "产品库还没有产品",
                          subtitle: "先在「产品」页上传产品，再回来给客户登记")
            } else {
                if !pending.isEmpty { section(title: "待领取", items: pending, isPending: true) }
                if !claimed.isEmpty { section(title: "已领取", items: claimed, isPending: false) }
                if !unlinked.isEmpty { unlinkedSection }
            }
        }
        .sheet(isPresented: $showPicker) {
            ClaimPickerSheet(clientID: client.id) { claim in
                client.claims.append(claim)
                store.save()
                flash("已添加：\(claim.productName)")
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.78))
                    .clipShape(Capsule())
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: 统计

    private var statsCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("\(claimed.reduce(0) { $0 + $1.quantity })")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Theme.roseDeep)
                    Text("已领取件数").font(.system(size: 10)).foregroundColor(Theme.muted)
                }
                .frame(maxWidth: .infinity)

                Rectangle().fill(Theme.line).frame(width: 0.8, height: 30)

                VStack(spacing: 2) {
                    Text("\(pending.reduce(0) { $0 + $1.quantity })")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color(red: 0.86, green: 0.58, blue: 0.24))
                    Text("待领取件数").font(.system(size: 10)).foregroundColor(Theme.muted)
                }
                .frame(maxWidth: .infinity)

                Rectangle().fill(Theme.line).frame(width: 0.8, height: 30)

                VStack(spacing: 2) {
                    Text("\(unlinked.count)")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Theme.inkSoft)
                    Text("未登记产品").font(.system(size: 10)).foregroundColor(Theme.muted)
                }
                .frame(maxWidth: .infinity)
            }

            Button {
                showPicker = true
            } label: {
                Label("从产品库添加", systemImage: "plus.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.gradRose)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(store.products.isEmpty)
            .opacity(store.products.isEmpty ? 0.5 : 1)
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    // MARK: 分组

    private func section(title: String, items: [ProductClaim], isPending: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title, trailing: "\(items.count) 项")
            ForEach(items) { c in
                claimRow(c)
            }
        }
    }

    private func claimRow(_ c: ProductClaim) -> some View {
        let product = store.product(c.productID)
        return HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.placeholder)
                    .frame(width: 44, height: 44)
                if let p = product, let u = store.productCover(p) {
                    LocalImage(url: u)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.muted)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(c.productName.isEmpty ? "已删除产品" : c.productName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.ink)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if !c.specName.isEmpty {
                        Text(c.specName)
                            .font(.system(size: 10))
                            .foregroundColor(Theme.muted)
                    }
                    Text("×\(c.quantity)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.roseDeep)
                    if let d = c.claimedAt, c.claimed {
                        Text(Fmt.dateOnly.string(from: d))
                            .font(.system(size: 10))
                            .foregroundColor(Theme.muted)
                    }
                    if !c.note.isEmpty {
                        Text("· \(c.note)")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.muted)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            Button {
                toggle(c)
            } label: {
                Text(c.claimed ? "已领取" : "待领取")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(c.claimed ? .white : Color(red: 0.86, green: 0.58, blue: 0.24))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(c.claimed
                                ? AnyView(Theme.rose)
                                : AnyView(Color(red: 0.99, green: 0.94, blue: 0.85)))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    changeQuantity(c, delta: 1)
                } label: {
                    Label("数量 +1", systemImage: "plus")
                }
                Button {
                    changeQuantity(c, delta: -1)
                } label: {
                    Label("数量 -1", systemImage: "minus")
                }
                Divider()
                Button(role: .destructive) {
                    client.claims.removeAll { $0.id == c.id }
                    store.save()
                } label: {
                    Label("移除记录", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.muted)
                    .frame(width: 24, height: 26)
                    .contentShape(Rectangle())
            }
        }
        .padding(10)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    private var unlinkedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "还没登记的产品", trailing: "\(unlinked.count) 个")
            Text("点击即可为这位客户登记并标记领取")
                .font(.system(size: 11))
                .foregroundColor(Theme.muted)

            ForEach(unlinked) { p in
                Button {
                    addQuick(p)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.roseDeep)
                        Text(p.name)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.ink)
                            .lineLimit(1)
                        Spacer()
                        if !p.stage.isEmpty {
                            Text(p.stage)
                                .font(.system(size: 10))
                                .foregroundColor(Theme.muted)
                        }
                        Text(p.priceRange)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.roseDeep)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.line, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 操作

    private func toggle(_ c: ProductClaim) {
        guard let i = client.claims.firstIndex(where: { $0.id == c.id }) else { return }
        client.claims[i].claimed.toggle()
        client.claims[i].claimedAt = client.claims[i].claimed ? Date() : nil
        store.save()
        flash(client.claims[i].claimed ? "已标记领取" : "已改为待领取")
    }

    private func changeQuantity(_ c: ProductClaim, delta: Int) {
        guard let i = client.claims.firstIndex(where: { $0.id == c.id }) else { return }
        client.claims[i].quantity = max(1, client.claims[i].quantity + delta)
        store.save()
    }

    private func addQuick(_ p: Product) {
        let spec = p.specs.first
        let claim = ProductClaim(productID: p.id, productName: p.name,
                                 specName: spec?.displayName ?? "",
                                 quantity: 1, claimed: true, claimedAt: Date())
        client.claims.append(claim)
        store.save()
        flash("已登记：\(p.name)")
    }

    private func flash(_ t: String) {
        withAnimation { toast = t }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { if toast == t { toast = nil } }
        }
    }
}

// MARK: - 添加领取

struct ClaimPickerSheet: View {
    let clientID: UUID
    let onAdd: (ProductClaim) -> Void

    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID: UUID?
    @State private var specID: UUID?
    @State private var quantity = 1
    @State private var note = ""
    @State private var markClaimed = true

    private var selected: Product? {
        guard let id = selectedID else { return nil }
        return store.product(id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("选择产品") {
                    if store.products.isEmpty {
                        Text("产品库为空").foregroundColor(Theme.muted)
                    } else {
                        Picker("产品", selection: $selectedID) {
                            Text("请选择").tag(UUID?.none)
                            ForEach(store.sortedProducts) { p in
                                Text(p.name).tag(UUID?.some(p.id))
                            }
                        }
                        .onChange(of: selectedID) { _ in
                            specID = selected?.specs.first?.id
                        }
                    }
                }

                if let p = selected {
                    if !p.specs.isEmpty {
                        Section("规格") {
                            Picker("规格", selection: $specID) {
                                Text("不指定").tag(UUID?.none)
                                ForEach(p.specs) { s in
                                    Text(s.displayName).tag(UUID?.some(s.id))
                                }
                            }
                        }
                    }

                    Section("数量与状态") {
                        Stepper("数量：\(quantity)", value: $quantity, in: 1...99)
                        Toggle("标记为已领取", isOn: $markClaimed)
                        TextField("备注", text: $note)
                    }

                    if !p.usageSteps.isEmpty {
                        Section("使用步骤") {
                            ForEach(Array(p.usageSteps.enumerated()), id: \.offset) { i, s in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(i + 1)")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(width: 17, height: 17)
                                        .background(Theme.rose)
                                        .clipShape(Circle())
                                    Text(s)
                                        .font(.system(size: 12))
                                        .foregroundColor(Theme.inkSoft)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.cream)
            .navigationTitle("登记产品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        guard let p = selected else { dismiss(); return }
                        let specName = p.specs.first { $0.id == specID }?.displayName ?? ""
                        let claim = ProductClaim(productID: p.id, productName: p.name,
                                                 specName: specName, quantity: quantity,
                                                 claimed: markClaimed,
                                                 claimedAt: markClaimed ? Date() : nil,
                                                 note: note)
                        onAdd(claim)
                        dismiss()
                    }
                    .disabled(selectedID == nil)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
