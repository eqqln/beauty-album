import SwiftUI
import PhotosUI
import UIKit

struct ProductListView: View {
    @EnvironmentObject var store: Store

    @State private var query = ""
    @State private var category: String = "全部"
    @State private var showAdd = false
    @State private var path = NavigationPath()

    private var categories: [String] {
        var set = Set(store.products.map(\.category).filter { !$0.isEmpty })
        set.insert("全部")
        return Array(set).sorted()
    }

    private var filtered: [Product] {
        var list = store.sortedProducts
        if category != "全部" {
            list = list.filter { $0.category == category }
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(q) ||
                $0.brand.localizedCaseInsensitiveContains(q) ||
                $0.intro.localizedCaseInsensitiveContains(q) ||
                $0.usageSteps.joined().localizedCaseInsensitiveContains(q)
            }
        }
        return list
    }

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: Metrics.gridSpacing),
         GridItem(.flexible(), spacing: Metrics.gridSpacing)]
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.cream.ignoresSafeArea()

                if store.products.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: Metrics.gridSpacing) {
                            if categories.count > 2 { categoryBar }
                            LazyVGrid(columns: columns, spacing: Metrics.gridSpacing) {
                                ForEach(filtered) { p in
                                    NavigationLink(value: p.id) {
                                        card(p)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            if filtered.isEmpty {
                                EmptyHint(icon: "magnifyingglass", title: "没有匹配的产品")
                                    .padding(.top, 30)
                            }
                        }
                        .padding(.horizontal, Metrics.hPadding)
                        .padding(.top, Metrics.hPadding)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("产品库")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: "搜索产品、品牌、用法")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 20))
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                ProductDetailView(productID: id)
            }
            .sheet(isPresented: $showAdd) {
                ProductEditSheet(productID: nil)
            }
        }
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { c in
                    let active = c == category
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { category = c }
                    } label: {
                        Text(c)
                            .font(.system(size: 12, weight: active ? .semibold : .regular))
                            .foregroundColor(active ? .white : Theme.inkSoft)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(active ? AnyView(Theme.gradRose) : AnyView(Theme.card))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(active ? Color.clear : Theme.line, lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func card(_ p: Product) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Rectangle().fill(Theme.placeholder)
                if let u = store.productCover(p) {
                    LocalImage(url: u)
                } else {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 26, weight: .ultraLight))
                        .foregroundColor(Theme.muted)
                }
            }
            .frame(height: Metrics.gridCoverHeight(columns: 2))
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(p.name.isEmpty ? "未命名产品" : p.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.ink)
                    .lineLimit(1)
                    .frame(height: 18)

                Text(p.brand.isEmpty ? "未填品牌" : p.brand)
                    .font(.system(size: 10))
                    .foregroundColor(p.brand.isEmpty ? Theme.muted.opacity(0.6) : Theme.muted)
                    .lineLimit(1)
                    .frame(height: 13)

                HStack(spacing: 5) {
                    Text(p.priceRange)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.roseDeep)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if !p.specs.isEmpty {
                        Text("\(p.specs.count) 规格")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.muted)
                    }
                }
                .frame(height: 15)

                // 阶段区固定高度：有没有阶段都不改变卡片高度
                Group {
                    if p.stage.isEmpty {
                        Text("未设适用阶段")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.muted.opacity(0.6))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.placeholder.opacity(0.6))
                            .clipShape(Capsule())
                    } else {
                        Text("适用 · \(p.stage)")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.roseDeep)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.roseLight)
                            .clipShape(Capsule())
                    }
                }
                .frame(height: 16, alignment: .leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.productCardHeight)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Theme.roseLight).frame(width: 92, height: 92)
                Image(systemName: "shippingbox")
                    .font(.system(size: 36, weight: .ultraLight))
                    .foregroundColor(Theme.roseDeep)
            }
            VStack(spacing: 5) {
                Text("产品库是空的")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.ink)
                Text("上传产品图、写清规格与使用步骤\n还能关联到客户的护理阶段")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            Button {
                showAdd = true
            } label: {
                Label("添加第一个产品", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .frame(maxWidth: 210)
        }
        .padding(32)
    }
}

// MARK: - 详情

struct ProductDetailView: View {
    let productID: UUID
    @EnvironmentObject var store: Store

    @State private var showEdit = false
    @State private var previewImage: String?

    private var product: Product? { store.products.first { $0.id == productID } }

    var body: some View {
        ZStack {
            Theme.cream.ignoresSafeArea()

            if let p = product {
                ScrollView {
                    VStack(spacing: 14) {
                        gallery(p)
                        headCard(p)
                        if !p.specs.isEmpty { specsCard(p) }
                        if !p.usageSteps.isEmpty { stepsCard(p) }
                        if !p.intro.isEmpty { introCard(p) }
                        claimCard(p)
                    }
                    .padding(16)
                    .padding(.bottom, 30)
                }
            } else {
                EmptyHint(icon: "shippingbox", title: "产品不存在")
            }
        }
        .navigationTitle(product?.name ?? "产品")
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
        .sheet(isPresented: $showEdit) {
            ProductEditSheet(productID: productID)
        }
        .fullScreenCover(isPresented: Binding(
            get: { previewImage != nil },
            set: { if !$0 { previewImage = nil } }
        )) {
            ZStack {
                Color.black.ignoresSafeArea()
                if let name = previewImage {
                    LocalImage(url: store.productImageURL(productID, name: name), contentMode: .fit)
                }
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            previewImage = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.18))
                                .clipShape(Circle())
                        }
                    }
                    .padding(16)
                    Spacer()
                }
            }
        }
    }

    private func gallery(_ p: Product) -> some View {
        Group {
            if p.imageNames.isEmpty {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.placeholder)
                    .frame(height: 190)
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "photo")
                                .font(.system(size: 30, weight: .ultraLight))
                                .foregroundColor(Theme.muted)
                            Text("还没有产品图")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.muted)
                        }
                    )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(p.imageNames, id: \.self) { name in
                            Button {
                                previewImage = name
                            } label: {
                                LocalImage(url: store.productImageURL(productID, name: name))
                                    .frame(width: 210, height: 190)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func headCard(_ p: Product) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(p.name)
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(Theme.ink)

            HStack(spacing: 8) {
                if !p.brand.isEmpty { chip(p.brand) }
                if !p.category.isEmpty { chip(p.category) }
                if !p.stage.isEmpty {
                    Text("适用阶段：\(p.stage)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.roseDeep)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.roseLight)
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 14) {
                Text(p.priceRange)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.roseDeep)
                Text("库存 \(p.totalStock)")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    private func chip(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 11))
            .foregroundColor(Theme.inkSoft)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.cream)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: 0.8))
    }

    private func specsCard(_ p: Product) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "规格", trailing: "\(p.specs.count) 种")
            ForEach(p.specs) { s in
                HStack {
                    Text(s.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.ink)
                    Spacer()
                    Text(s.price > 0 ? Fmt.money(s.price) : "未定价")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.roseDeep)
                    Text("库存 \(s.stock)")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.muted)
                        .frame(width: 58, alignment: .trailing)
                }
                .padding(.vertical, 6)
                Divider().opacity(0.4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    private func stepsCard(_ p: Product) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "使用步骤")
            ForEach(Array(p.usageSteps.enumerated()), id: \.offset) { i, s in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Theme.rose)
                        .clipShape(Circle())
                    Text(s)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    private func introCard(_ p: Product) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "产品说明")
            Text(p.intro)
                .font(.system(size: 13))
                .foregroundColor(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    private func claimCard(_ p: Product) -> some View {
        let stats = store.claimStats(productID: p.id)
        let holders = store.clients.filter { c in c.claims.contains { $0.productID == p.id } }

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "领取情况", trailing: "\(holders.count) 位客户")

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("\(stats.claimed)")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.roseDeep)
                    Text("已领取").font(.system(size: 10)).foregroundColor(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                Rectangle().fill(Theme.line).frame(width: 0.8, height: 26)
                VStack(spacing: 2) {
                    Text("\(stats.pending)")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 0.86, green: 0.58, blue: 0.24))
                    Text("待领取").font(.system(size: 10)).foregroundColor(Theme.muted)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 4)

            if holders.isEmpty {
                Text("还没有客户关联这个产品，可在客户「产品」页添加")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.muted)
            } else {
                ForEach(holders.prefix(8)) { c in
                    let claim = c.claims.first { $0.productID == p.id }
                    HStack(spacing: 8) {
                        Text(c.name.isEmpty ? "未命名" : c.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.ink)
                        if let claim, !claim.specName.isEmpty {
                            Text(claim.specName)
                                .font(.system(size: 10))
                                .foregroundColor(Theme.muted)
                        }
                        Spacer()
                        Text(claim?.claimed == true ? "已领取" : "待领取")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(claim?.claimed == true ? Theme.roseDeep
                                             : Color(red: 0.86, green: 0.58, blue: 0.24))
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }
}

// MARK: - 编辑

struct ProductEditSheet: View {
    let productID: UUID?

    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var brand = ""
    @State private var category = ""
    @State private var intro = ""
    @State private var specs: [ProductSpec] = [ProductSpec()]
    @State private var steps: [String] = [""]
    @State private var stage = ""
    @State private var existingNames: [String] = []
    @State private var pendingImages: [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var loaded = false
    @State private var newStep = ""
    @State private var newSpecName = ""

    private var isNew: Bool { productID == nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private var stageOptions: [String] {
        var list = store.settings.stepTemplate
        if !stage.isEmpty && !list.contains(stage) { list.append(stage) }
        return list
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("图片") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(existingNames, id: \.self) { n in
                                ZStack(alignment: .topTrailing) {
                                    if let id = productID {
                                        LocalImage(url: store.productImageURL(id, name: n))
                                            .frame(width: 84, height: 84)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    Button {
                                        existingNames.removeAll { $0 == n }
                                        if let id = productID {
                                            store.deleteProductImage(productID: id, name: n)
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(.white)
                                            .background(Circle().fill(Color.black.opacity(0.5)))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 4, y: -4)
                                }
                            }

                            ForEach(Array(pendingImages.enumerated()), id: \.offset) { idx, img in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 84, height: 84)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    Button {
                                        pendingImages.remove(at: idx)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(.white)
                                            .background(Circle().fill(Color.black.opacity(0.5)))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 4, y: -4)
                                }
                            }

                            PhotosPicker(selection: $pickerItems,
                                         maxSelectionCount: 9,
                                         matching: .images) {
                                VStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 18, weight: .light))
                                    Text("上传").font(.system(size: 10))
                                }
                                .foregroundColor(Theme.roseDeep)
                                .frame(width: 84, height: 84)
                                .background(Theme.roseLight)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("基本信息") {
                    TextField("产品名称", text: $name)
                    TextField("品牌", text: $brand)
                    TextField("分类，例如 精华 / 面膜 / 仪器", text: $category)
                }

                Section {
                    Picker("适用阶段", selection: $stage) {
                        Text("不指定").tag("")
                        ForEach(stageOptions, id: \.self) { s in
                            Text(s).tag(s)
                        }
                    }
                    TextField("或自定义阶段名", text: $stage)
                } header: {
                    Text("适用阶段")
                } footer: {
                    Text("对应客户流程里的环节，例如「第 2 次护理」。客户流程走到这一步时就知道该用哪个产品。")
                }

                Section {
                    ForEach(Array(specs.enumerated()), id: \.element.id) { idx, _ in
                        VStack(spacing: 6) {
                            HStack {
                                TextField("规格名，如 30ml", text: Binding(
                                    get: { idx < specs.count ? specs[idx].name : "" },
                                    set: { if idx < specs.count { specs[idx].name = $0 } }
                                ))
                                Button {
                                    if idx < specs.count { specs.remove(at: idx) }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(Theme.muted)
                                }
                                .buttonStyle(.plain)
                            }
                            HStack(spacing: 10) {
                                HStack(spacing: 4) {
                                    Text("¥").font(.system(size: 12)).foregroundColor(Theme.muted)
                                    TextField("价格", text: Binding(
                                        get: {
                                            idx < specs.count
                                            ? (specs[idx].price > 0 ? String(format: "%.0f", specs[idx].price) : "")
                                            : ""
                                        },
                                        set: { if idx < specs.count { specs[idx].price = Double($0) ?? 0 } }
                                    ))
                                    .keyboardType(.decimalPad)
                                }
                                HStack(spacing: 4) {
                                    Text("库存").font(.system(size: 12)).foregroundColor(Theme.muted)
                                    TextField("0", text: Binding(
                                        get: {
                                            idx < specs.count && specs[idx].stock > 0
                                            ? String(specs[idx].stock) : ""
                                        },
                                        set: { if idx < specs.count { specs[idx].stock = Int($0) ?? 0 } }
                                    ))
                                    .keyboardType(.numberPad)
                                }
                            }
                            .font(.system(size: 14))
                        }
                        .padding(.vertical, 2)
                    }

                    HStack(spacing: 8) {
                        TextField("新增规格", text: $newSpecName)
                        Button {
                            let t = newSpecName.trimmingCharacters(in: .whitespaces)
                            guard !t.isEmpty else { return }
                            specs.append(ProductSpec(name: t))
                            newSpecName = ""
                        } label: {
                            Image(systemName: "plus.circle.fill").foregroundColor(Theme.roseDeep)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("规格")
                } footer: {
                    Text("一个产品可以有多个规格，价格和库存分开记。")
                }

                Section {
                    ForEach(Array(steps.enumerated()), id: \.offset) { idx, _ in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(idx + 1)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 18, height: 18)
                                .background(Theme.rose)
                                .clipShape(Circle())
                            TextField("步骤内容", text: Binding(
                                get: { idx < steps.count ? steps[idx] : "" },
                                set: { if idx < steps.count { steps[idx] = $0 } }
                            ), axis: .vertical)
                            .lineLimit(1...3)
                            Button {
                                if idx < steps.count { steps.remove(at: idx) }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(Theme.muted)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("新增使用步骤", text: $newStep)
                        Button {
                            let t = newStep.trimmingCharacters(in: .whitespaces)
                            guard !t.isEmpty else { return }
                            steps.append(t)
                            newStep = ""
                        } label: {
                            Image(systemName: "plus.circle.fill").foregroundColor(Theme.roseDeep)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("使用步骤")
                }

                Section("产品说明") {
                    TextEditor(text: $intro)
                        .frame(minHeight: 90)
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            if let id = productID {
                                store.deleteProduct(id)
                            }
                            dismiss()
                        } label: {
                            Label("删除这个产品", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.cream)
            .navigationTitle(isNew ? "添加产品" : "编辑产品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 数字键盘没有回车键，补一个「完成」收键盘
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
            .onAppear(perform: load)
            .onChange(of: pickerItems) { items in
                guard !items.isEmpty else { return }
                Task {
                    var imgs: [UIImage] = []
                    for item in items {
                        if let d = try? await item.loadTransferable(type: Data.self),
                           let img = UIImage(data: d) {
                            imgs.append(img)
                        }
                    }
                    let final = imgs
                    await MainActor.run {
                        pendingImages.append(contentsOf: final)
                        pickerItems = []
                    }
                }
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let id = productID, let p = store.products.first(where: { $0.id == id }) else { return }
        name = p.name
        brand = p.brand
        category = p.category
        intro = p.intro
        specs = p.specs.isEmpty ? [ProductSpec()] : p.specs
        steps = p.usageSteps.isEmpty ? [""] : p.usageSteps
        stage = p.stage
        existingNames = p.imageNames
    }

    private func save() {
        let cleanSpecs = specs.filter {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty || $0.price > 0 || $0.stock > 0
        }
        let cleanSteps = steps
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var targetID: UUID

        if let id = productID, var p = store.products.first(where: { $0.id == id }) {
            targetID = id
            p.name = name.trimmingCharacters(in: .whitespaces)
            p.brand = brand.trimmingCharacters(in: .whitespaces)
            p.category = category.trimmingCharacters(in: .whitespaces)
            p.intro = intro
            p.specs = cleanSpecs
            p.usageSteps = cleanSteps
            p.stage = stage.trimmingCharacters(in: .whitespaces)
            p.imageNames = existingNames
            store.updateProduct(p)
        } else {
            var p = Product(name: name.trimmingCharacters(in: .whitespaces),
                            brand: brand.trimmingCharacters(in: .whitespaces),
                            category: category.trimmingCharacters(in: .whitespaces),
                            intro: intro, specs: cleanSpecs, usageSteps: cleanSteps,
                            stage: stage.trimmingCharacters(in: .whitespaces))
            targetID = UUID()
            p.id = targetID
            store.addProduct(p)
        }

        if !pendingImages.isEmpty {
            var names: [String] = []
            for img in pendingImages {
                if let n = store.importProductImage(img, productID: targetID) {
                    names.append(n)
                }
            }
            if let i = store.products.firstIndex(where: { $0.id == targetID }) {
                store.products[i].imageNames.append(contentsOf: names)
                store.save()
            }
        }

        dismiss()
    }
}
