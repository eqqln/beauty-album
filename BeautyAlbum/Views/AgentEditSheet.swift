import SwiftUI
import UIKit

// MARK: - 代理编辑 / 新建

struct AgentEditSheet: View {
    /// nil 表示新建
    let agentID: UUID?

    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var phone = ""
    @State private var wechat = ""
    @State private var region = ""
    @State private var level: AgentLevel = .first
    @State private var discount: Double = 0.6
    @State private var parentID: UUID? = nil
    @State private var joinedAt = Date()
    @State private var note = ""
    @State private var loaded = false
    /// 手动调过折扣后，改等级不再覆盖折扣
    @State private var discountTouched = false

    private var isNew: Bool { agentID == nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var f: FeatureFlags { store.settings.features }

    /// 可选上级：排除自己和自己的下级，避免成环
    private var parentOptions: [Agent] {
        store.agents
            .filter { a in
                guard let me = agentID else { return true }
                return a.id != me && !store.isDescendant(a.id, of: me)
            }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var parentLabel: String {
        guard let pid = parentID, let p = store.agent(pid) else { return "无（顶层代理）" }
        return "\(p.name) · \(p.level.rawValue)"
    }

    private var discountText: String {
        if discount >= 0.999 { return "不打折" }
        let zhe = discount * 10
        if zhe == zhe.rounded() { return "\(Int(zhe)) 折" }
        return String(format: "%.1f 折", zhe)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("姓名", text: $name)
                        .textInputAutocapitalization(.never)
                    TextField("手机号", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("微信号", text: $wechat)
                        .textInputAutocapitalization(.never)
                    TextField("地区 / 门店", text: $region)
                } header: {
                    Text("基本信息")
                }

                Section {
                    Picker("等级", selection: $level) {
                        ForEach(AgentLevel.allCases) { l in
                            Text(l.rawValue).tag(l)
                        }
                    }
                    .onChange(of: level) { newValue in
                        guard !discountTouched else { return }
                        discount = newValue.defaultDiscount
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("拿货折扣")
                            Spacer()
                            Text(discountText)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Theme.roseDeep)
                        }
                        Slider(value: Binding(
                            get: { discount },
                            set: { v in
                                discount = v
                                discountTouched = true
                            }
                        ), in: 0.3...1.0, step: 0.05)
                        .tint(Theme.roseDeep)
                    }
                } header: {
                    Text("等级与折扣")
                } footer: {
                    Text("折扣用于记拿货时自动带出单价。改等级会带出该等级的默认折扣，手动拖过滑块后就不再跟着变了。")
                }

                if f.agentParent {
                    Section {
                        Menu {
                            Button("无（顶层代理）") { parentID = nil }
                            if parentOptions.isEmpty {
                                Text("暂无可选上级")
                            } else {
                                ForEach(parentOptions) { a in
                                    Button("\(a.name) · \(a.level.rawValue)") {
                                        parentID = a.id
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("上级代理").foregroundColor(Theme.ink)
                                Spacer()
                                Text(parentLabel)
                                    .foregroundColor(Theme.muted)
                                    .lineLimit(1)
                            }
                        }
                    } header: {
                        Text("父级关系")
                    } footer: {
                        Text("下级代理会显示在上级的详情页里，可以逐层往下看。已在「设置 → 功能模块」开启。")
                    }
                }

                if f.agentTime {
                    Section {
                        DatePicker("加入时间", selection: $joinedAt,
                                   displayedComponents: [.date, .hourAndMinute])
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                    } footer: {
                        Text("默认是当前时间。补录老代理时改成当初的日期，列表按加入时间倒序。")
                    }
                }

                Section {
                    TextEditor(text: $note)
                        .frame(minHeight: 100)
                        .overlay(alignment: .topLeading) {
                            if note.isEmpty {
                                Text("拿货习惯、结算方式、性格特点……")
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
                    Text("备注和拿货记录都会随备份一起导出。")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.cream)
            .navigationTitle(isNew ? "新建代理" : "编辑代理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil)
                    }
                    .fontWeight(.semibold)
                }
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

        guard let id = agentID, let a = store.agent(id) else {
            discount = level.defaultDiscount
            return
        }
        // 先标记已手动设定，避免赋值 level 时把自定义折扣冲掉
        discountTouched = true
        name = a.name
        phone = a.phone
        wechat = a.wechat
        region = a.region
        level = a.level
        discount = a.discount
        parentID = a.parentID
        joinedAt = a.joinedAt
        note = a.note
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        let p = phone.trimmingCharacters(in: .whitespaces)
        let w = wechat.trimmingCharacters(in: .whitespaces)
        let r = region.trimmingCharacters(in: .whitespaces)

        if let id = agentID, var cur = store.agent(id) {
            cur.name = n
            cur.phone = p
            cur.wechat = w
            cur.region = r
            cur.level = level
            cur.discount = discount
            cur.parentID = parentID
            cur.joinedAt = joinedAt
            cur.note = note
            store.updateAgent(cur)
        } else {
            let a = Agent(name: n, phone: p, wechat: w, level: level, region: r,
                          discount: discount, parentID: parentID, parentName: "",
                          clientIDs: [], orders: [], note: note, joinedAt: joinedAt)
            store.addAgent(a)
        }
        dismiss()
    }
}

// MARK: - 拿货记录

struct AgentOrderSheet: View {
    let agentID: UUID
    /// nil 表示新增
    let orderID: UUID?

    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var productID: UUID? = nil
    @State private var productName = ""
    @State private var specName = ""
    @State private var quantity = 1
    @State private var unitPriceText = ""
    @State private var paidText = ""
    @State private var createdAt = Date()
    @State private var note = ""
    @State private var loaded = false

    private var isNew: Bool { orderID == nil }
    private var f: FeatureFlags { store.settings.features }

    private var agent: Agent? { store.agent(agentID) }
    private var discount: Double { agent?.discount ?? 1.0 }

    private var unitPrice: Double { Double(unitPriceText) ?? 0 }
    private var paid: Double { Double(paidText) ?? 0 }
    private var amount: Double { Double(max(0, quantity)) * unitPrice }
    private var unpaid: Double { max(0, amount - paid) }

    /// 折扣后价格，用于选中产品时自动带出
    private func discounted(_ price: Double) -> Double {
        (price * discount * 100).rounded() / 100
    }

    private func priceText(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v))" : String(format: "%.2f", v)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Menu {
                        Button("不关联产品（手填）") {
                            productID = nil
                        }
                        ForEach(store.sortedProducts) { p in
                            Button(p.name.isEmpty ? "未命名产品" : p.name) {
                                productID = p.id
                                productName = p.name
                                if let s = p.specs.first {
                                    specName = s.name
                                    unitPriceText = priceText(discounted(s.price))
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("产品").foregroundColor(Theme.ink)
                            Spacer()
                            Text(productID == nil ? "手填" : (productName.isEmpty ? "已选" : productName))
                                .foregroundColor(Theme.muted)
                                .lineLimit(1)
                        }
                    }

                    TextField("产品名称", text: $productName)

                    TextField("规格（例如 30ml）", text: $specName)

                    if let pid = productID, let p = store.product(pid), !p.specs.isEmpty {
                        Menu {
                            ForEach(p.specs) { s in
                                Button(s.displayName) {
                                    specName = s.name
                                    unitPriceText = priceText(discounted(s.price))
                                }
                            }
                        } label: {
                            HStack {
                                Text("选择规格").foregroundColor(Theme.ink)
                                Spacer()
                                Text(specName.isEmpty ? "未选" : specName)
                                    .foregroundColor(Theme.muted)
                            }
                        }
                    }
                } header: {
                    Text("拿的什么")
                } footer: {
                    if discount < 0.999 {
                        Text("这位代理的折扣是 \(agent?.discountText ?? "")，选规格时已按折扣带出单价，可以手动改。")
                    }
                }

                if f.agentQuantity {
                    Section {
                        Stepper(value: $quantity, in: 1...9999) {
                            HStack {
                                Text("数量")
                                Spacer()
                                Text("\(quantity) 件")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Theme.roseDeep)
                            }
                        }

                        HStack {
                            Text("单价")
                            Spacer()
                            TextField("0", text: $unitPriceText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                            Text("元").foregroundColor(Theme.muted)
                        }

                        HStack {
                            Text("已付")
                            Spacer()
                            TextField("0", text: $paidText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                            Text("元").foregroundColor(Theme.muted)
                        }

                        HStack {
                            Text("本单金额").font(.system(size: 14, weight: .medium))
                            Spacer()
                            Text(Fmt.money(amount))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Theme.ink)
                        }

                        if unpaid > 0 {
                            HStack {
                                Text("未结")
                                Spacer()
                                Text(Fmt.money(unpaid))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Theme.roseDeep)
                            }
                        }
                    } header: {
                        Text("数量与金额")
                    }
                } else {
                    // 数量功能关掉时仍可记金额，只是不显示件数汇总
                    Section {
                        HStack {
                            Text("金额")
                            Spacer()
                            TextField("0", text: $unitPriceText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                            Text("元").foregroundColor(Theme.muted)
                        }
                        HStack {
                            Text("已付")
                            Spacer()
                            TextField("0", text: $paidText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                            Text("元").foregroundColor(Theme.muted)
                        }
                    } header: {
                        Text("金额")
                    }
                }

                if f.agentTime {
                    Section {
                        DatePicker("拿货时间", selection: $createdAt,
                                   displayedComponents: [.date, .hourAndMinute])
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                    } footer: {
                        Text("默认是当前时间，补录以前的单子可以改成实际发货日期。")
                    }
                }

                Section {
                    TextEditor(text: $note)
                        .frame(minHeight: 70)
                        .overlay(alignment: .topLeading) {
                            if note.isEmpty {
                                Text("物流、赠品、结算约定……")
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.muted.opacity(0.7))
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("备注")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.cream)
            .navigationTitle(isNew ? "记一笔拿货" : "编辑这一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil)
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let oid = orderID,
              let o = store.agent(agentID)?.orders.first(where: { $0.id == oid }) else { return }
        productID = o.productID
        productName = o.productName
        specName = o.specName
        quantity = o.quantity
        unitPriceText = o.unitPrice == 0 ? "" : priceText(o.unitPrice)
        paidText = o.paid == 0 ? "" : priceText(o.paid)
        createdAt = o.createdAt
        note = o.note
    }

    private func save() {
        let n = productName.trimmingCharacters(in: .whitespaces)
        let spec = specName.trimmingCharacters(in: .whitespaces)

        if let oid = orderID,
           var cur = store.agent(agentID),
           let i = cur.orders.firstIndex(where: { $0.id == oid }) {
            cur.orders[i].productID = productID
            cur.orders[i].productName = n
            cur.orders[i].specName = spec
            cur.orders[i].quantity = max(1, quantity)
            cur.orders[i].unitPrice = unitPrice
            cur.orders[i].paid = paid
            cur.orders[i].createdAt = createdAt
            cur.orders[i].note = note
            store.updateAgent(cur)
        } else {
            let o = AgentOrder(productID: productID, productName: n, specName: spec,
                               quantity: max(1, quantity), unitPrice: unitPrice,
                               paid: paid, note: note, createdAt: createdAt)
            store.addOrder(o, to: agentID)
        }
        dismiss()
    }
}
