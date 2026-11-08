import SwiftUI
import PhotosUI
import UIKit

// MARK: - 头像

struct TeacherAvatar: View {
    let teacher: Teacher
    var size: CGFloat = 60
    @EnvironmentObject var store: Store

    private var url: URL { store.teacherImageURL(teacher.id) }

    var body: some View {
        ZStack {
            Circle().fill(Theme.roseLight)
            if FileManager.default.fileExists(atPath: url.path) {
                LocalImage(url: url)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Text(String(teacher.name.prefix(1)))
                    .font(.system(size: size * 0.38, weight: .medium))
                    .foregroundColor(Theme.roseDeep)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Theme.card, lineWidth: 2))
    }
}

// MARK: - 列表

struct TeacherListView: View {
    @EnvironmentObject var store: Store

    @State private var showAdd = false
    @State private var editing: Teacher?
    @State private var pendingDelete: Teacher?
    @State private var path = NavigationPath()

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: Metrics.gridSpacing),
         GridItem(.flexible(), spacing: Metrics.gridSpacing)]
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.cream.ignoresSafeArea()

                if store.teachers.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            introCard
                            LazyVGrid(columns: columns, spacing: Metrics.gridSpacing) {
                                ForEach(store.sortedTeachers) { t in
                                    NavigationLink(value: t.id) {
                                        card(t)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            editing = t
                                        } label: {
                                            Label("编辑资料", systemImage: "pencil")
                                        }
                                        Button {
                                            store.moveTeacher(t.id, delta: -1)
                                        } label: {
                                            Label("前移", systemImage: "arrow.up")
                                        }
                                        Button {
                                            store.moveTeacher(t.id, delta: 1)
                                        } label: {
                                            Label("后移", systemImage: "arrow.down")
                                        }
                                        Button(role: .destructive) {
                                            pendingDelete = t
                                        } label: {
                                            Label("删除老师", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, Metrics.hPadding)
                        .padding(.top, Metrics.hPadding)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("老师团队")
            .navigationBarTitleDisplayMode(.large)
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
                TeacherDetailView(teacherID: id)
            }
            .sheet(isPresented: $showAdd) {
                TeacherEditSheet(teacherID: nil)
            }
            .sheet(item: $editing) { t in
                TeacherEditSheet(teacherID: t.id)
            }
            .alert("删除老师", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ), presenting: pendingDelete) { t in
                Button("取消", role: .cancel) { pendingDelete = nil }
                Button("删除", role: .destructive) {
                    store.deleteTeacher(t.id)
                    pendingDelete = nil
                }
            } message: { t in
                Text("会删除「\(t.name)」的资料和头像。已有的预约记录会保留。")
            }
        }
    }

    private var introCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundColor(Theme.roseDeep)
            Text("共 \(store.teachers.count) 位老师 · \(store.teachers.filter(\.available).count) 位可预约")
                .font(.system(size: 12))
                .foregroundColor(Theme.inkSoft)
            Spacer()
        }
        .padding(12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    private func card(_ t: Teacher) -> some View {
        VStack(spacing: 8) {
            TeacherAvatar(teacher: t, size: Metrics.isCompact ? 64 : 72)

            VStack(spacing: 2) {
                Text(t.name.isEmpty ? "未命名" : t.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.ink)
                    .lineLimit(1)
                    .frame(height: 19)
                Text(t.displayTitle)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.muted)
                    .lineLimit(1)
                    .frame(height: 14)
            }

            // 标签区固定高度，有没有标签都不改变卡片高度
            Group {
                if t.tags.isEmpty {
                    Text("暂无标签")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.muted.opacity(0.5))
                } else {
                    Text(t.tags.prefix(2).joined(separator: " · "))
                        .font(.system(size: 10))
                        .foregroundColor(Theme.roseDeep)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.roseLight)
                        .clipShape(Capsule())
                }
            }
            .frame(height: 20)

            HStack(spacing: 4) {
                Circle()
                    .fill(t.available ? Color(red: 0.36, green: 0.65, blue: 0.45) : Theme.muted.opacity(0.5))
                    .frame(width: 5, height: 5)
                Text(t.available ? "可预约" : "暂不接单")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.muted)
            }
            .frame(height: 13)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.teacherCardHeight)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Theme.roseLight).frame(width: 92, height: 92)
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 36, weight: .ultraLight))
                    .foregroundColor(Theme.roseDeep)
            }
            VStack(spacing: 5) {
                Text("还没有老师")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.ink)
                Text("添加老师后，可展示团队、接受预约")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.muted)
            }
            Button {
                showAdd = true
            } label: {
                Label("添加第一位老师", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .frame(maxWidth: 210)
        }
        .padding(32)
    }
}

// MARK: - 详情

struct TeacherDetailView: View {
    let teacherID: UUID
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var showEdit = false
    @State private var showBooking = false

    private var teacher: Teacher? { store.teachers.first { $0.id == teacherID } }
    private var appts: [Appointment] { store.appointments(for: teacherID) }

    var body: some View {
        ZStack {
            Theme.cream.ignoresSafeArea()

            if let t = teacher {
                ScrollView {
                    VStack(spacing: 14) {
                        header(t)
                        if !t.tags.isEmpty { tagsCard(t) }
                        if !t.intro.isEmpty { introCard(t) }
                        appointmentsCard(t)
                    }
                    .padding(16)
                    .padding(.bottom, 100)
                }

                VStack {
                    Spacer()
                    Button {
                        showBooking = true
                    } label: {
                        Label("预约 \(t.name)", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .disabled(!t.available)
                    .opacity(t.available ? 1 : 0.5)
                }
            } else {
                EmptyHint(icon: "person.crop.circle.badge.questionmark", title: "老师不存在")
            }
        }
        .navigationTitle(teacher?.name ?? "老师")
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
            TeacherEditSheet(teacherID: teacherID)
        }
        .sheet(isPresented: $showBooking) {
            AppointmentEditSheet(appointmentID: nil, presetTeacherID: teacherID)
        }
    }

    private func header(_ t: Teacher) -> some View {
        VStack(spacing: 10) {
            TeacherAvatar(teacher: t, size: 96)
                .padding(.top, 6)
            Text(t.name)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Theme.ink)
            Text(t.displayTitle)
                .font(.system(size: 13))
                .foregroundColor(Theme.roseDeep)

            HStack(spacing: 14) {
                if !t.phone.isEmpty {
                    Button {
                        let digits = t.phone.filter { $0.isNumber || $0 == "+" }
                        if let u = URL(string: "tel://\(digits)") { UIApplication.shared.open(u) }
                    } label: {
                        Label(t.phone, systemImage: "phone.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.inkSoft)
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(t.available ? Color(red: 0.36, green: 0.65, blue: 0.45) : Theme.muted)
                        .frame(width: 6, height: 6)
                    Text(t.available ? "可预约" : "暂不接单")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.muted)
                }
            }
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    private func tagsCard(_ t: Teacher) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "擅长项目")
            FlowTags(tags: t.tags)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    private func introCard(_ t: Teacher) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "简介")
            Text(t.intro)
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

    private func appointmentsCard(_ t: Teacher) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "预约记录", trailing: "\(appts.count) 条")

            if appts.isEmpty {
                Text("暂无预约")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
                    .padding(.vertical, 6)
            } else {
                ForEach(appts.prefix(20)) { a in
                    HStack(spacing: 10) {
                        VStack(spacing: 1) {
                            Text(Fmt.dayNumber(a.date))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Theme.roseDeep)
                            Text(Fmt.monthLabel(a.date))
                                .font(.system(size: 9))
                                .foregroundColor(Theme.muted)
                        }
                        .frame(width: 38)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Fmt.time(a.date))  \(a.clientName.isEmpty ? "散客" : a.clientName)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.ink)
                            Text(a.service.isEmpty ? "未填写项目" : a.service)
                                .font(.system(size: 11))
                                .foregroundColor(Theme.muted)
                        }
                        Spacer()
                        Text(a.status.rawValue)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(red: a.status.color.r,
                                                   green: a.status.color.g,
                                                   blue: a.status.color.b))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(red: a.status.color.r,
                                              green: a.status.color.g,
                                              blue: a.status.color.b).opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 5)
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

// MARK: - 标签流式布局

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

struct FlowTags: View {
    let tags: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                Text(tag)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.roseDeep)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.roseLight)
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - 编辑

struct TeacherEditSheet: View {
    let teacherID: UUID?

    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var title = ""
    @State private var phone = ""
    @State private var intro = ""
    @State private var tagText = ""
    @State private var available = true
    @State private var loaded = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var pendingID: UUID?

    private var isNew: Bool { teacherID == nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            ZStack {
                                Circle().fill(Theme.roseLight).frame(width: 88, height: 88)
                                if let img = previewImage {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 88, height: 88)
                                        .clipShape(Circle())
                                } else if let id = teacherID ?? pendingID,
                                          FileManager.default.fileExists(atPath: store.teacherImageURL(id).path) {
                                    LocalImage(url: store.teacherImageURL(id))
                                        .frame(width: 88, height: 88)
                                        .clipShape(Circle())
                                } else {
                                    Text(String(name.prefix(1)))
                                        .font(.system(size: 32, weight: .medium))
                                        .foregroundColor(Theme.roseDeep)
                                }
                            }
                            PhotosPicker(selection: $pickerItem, matching: .images) {
                                Text("选择头像")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Theme.roseDeep)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }

                Section("基本信息") {
                    TextField("姓名", text: $name)
                    TextField("职位，例如 高级美容师", text: $title)
                    TextField("联系电话", text: $phone)
                        .keyboardType(.phonePad)
                    Toggle("接受预约", isOn: $available)
                }

                Section {
                    TextField("擅长项目，用逗号分隔", text: $tagText, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text("擅长项目")
                } footer: {
                    Text("例如：补水、抗衰、面部护理。会以标签形式展示在老师卡片上。")
                }

                Section("简介") {
                    TextEditor(text: $intro)
                        .frame(minHeight: 110)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.cream)
            .navigationTitle(isNew ? "添加老师" : "编辑老师")
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
            .onAppear(perform: load)
            .onChange(of: pickerItem) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await MainActor.run { previewImage = img }
                    }
                    await MainActor.run { pickerItem = nil }
                }
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let id = teacherID, let t = store.teachers.first(where: { $0.id == id }) {
            name = t.name
            title = t.title
            phone = t.phone
            intro = t.intro
            tagText = t.tags.joined(separator: "、")
            available = t.available
        }
    }

    private func save() {
        let tags = tagText
            .components(separatedBy: CharacterSet(charactersIn: ",，、;；\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var targetID: UUID

        if let id = teacherID {
            targetID = id
            var t = store.teachers.first(where: { $0.id == id }) ?? Teacher()
            t.name = name.trimmingCharacters(in: .whitespaces)
            t.title = title.trimmingCharacters(in: .whitespaces)
            t.phone = phone.trimmingCharacters(in: .whitespaces)
            t.intro = intro
            t.tags = tags
            t.available = available
            store.updateTeacher(t)
        } else {
            let t = Teacher(name: name.trimmingCharacters(in: .whitespaces),
                            title: title.trimmingCharacters(in: .whitespaces),
                            phone: phone.trimmingCharacters(in: .whitespaces),
                            intro: intro, tags: tags, available: available)
            targetID = store.addTeacher(t)
            pendingID = targetID
        }

        if let img = previewImage {
            _ = store.saveTeacherImage(img, teacherID: targetID)
        }
        store.save()
        dismiss()
    }
}
