import SwiftUI

enum ApptFilter: String, CaseIterable, Identifiable {
    case upcoming = "即将到来"
    case today = "今天"
    case all = "全部"
    case history = "已结束"

    var id: String { rawValue }
}

struct AppointmentListView: View {
    @EnvironmentObject var store: Store

    @State private var filter: ApptFilter = .upcoming
    @State private var showAdd = false
    @State private var editing: Appointment?
    @State private var pendingDelete: Appointment?

    private var filtered: [Appointment] {
        switch filter {
        case .upcoming:
            return store.appointments
                .filter { $0.isUpcoming }
                .sorted { $0.date < $1.date }
        case .today:
            return store.todayAppointments
        case .all:
            return store.appointments.sorted { $0.date > $1.date }
        case .history:
            return store.appointments
                .filter { $0.status == .done || $0.status == .cancelled || $0.date < Date() }
                .sorted { $0.date > $1.date }
        }
    }

    private struct DayGroup: Identifiable {
        var id: Date { day }
        let day: Date
        let items: [Appointment]
    }

    private var grouped: [DayGroup] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.date) }
        return dict.keys.sorted().map {
            DayGroup(day: $0, items: dict[$0]!.sorted { a, b in a.date < b.date })
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.cream.ignoresSafeArea()

                VStack(spacing: 0) {
                    filterBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                    if filtered.isEmpty {
                        Spacer()
                        EmptyHint(icon: "calendar.badge.plus",
                                  title: "没有\(filter.rawValue)的预约",
                                  subtitle: "点右上角 + 为客户安排一次服务",
                                  action: { showAdd = true },
                                  actionTitle: "新建预约")
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                                ForEach(grouped) { group in
                                    Section {
                                        ForEach(group.items) { a in
                                            row(a)
                                        }
                                    } header: {
                                        dayHeader(group.day, count: group.items.count)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 30)
                        }
                    }
                }
            }
            .navigationTitle("预约")
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
            .sheet(isPresented: $showAdd) {
                AppointmentEditSheet(appointmentID: nil, presetTeacherID: nil)
            }
            .sheet(item: $editing) { a in
                AppointmentEditSheet(appointmentID: a.id, presetTeacherID: nil)
            }
            .alert("删除预约", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ), presenting: pendingDelete) { a in
                Button("取消", role: .cancel) { pendingDelete = nil }
                Button("删除", role: .destructive) {
                    store.deleteAppointment(a.id)
                    pendingDelete = nil
                }
            } message: { a in
                Text("删除后无法恢复：\(a.clientName) · \(Fmt.dateTime.string(from: a.date))")
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(ApptFilter.allCases) { f in
                let active = f == filter
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { filter = f }
                } label: {
                    Text(f.rawValue)
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

    private func dayHeader(_ day: Date, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(Fmt.dateOnly.string(from: day))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.ink)
            Text(Fmt.weekday(day))
                .font(.system(size: 11))
                .foregroundColor(Theme.muted)
            if Calendar.current.isDateInToday(day) {
                Text("今天")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.rose)
                    .clipShape(Capsule())
            }
            Spacer()
            Text("\(count) 个")
                .font(.system(size: 10))
                .foregroundColor(Theme.muted)
        }
        .padding(.vertical, 6)
        .background(Theme.cream)
    }

    private func row(_ a: Appointment) -> some View {
        Button {
            editing = a
        } label: {
            HStack(spacing: 11) {
                VStack(spacing: 2) {
                    Text(Fmt.time(a.date))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.roseDeep)
                    Text("\(a.durationMinutes)分")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.muted)
                }
                .frame(width: 44)

                Rectangle().fill(Theme.line).frame(width: 0.8, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(a.clientName.isEmpty ? "散客" : a.clientName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.ink)
                        if !a.phone.isEmpty {
                            Text(a.phone)
                                .font(.system(size: 10))
                                .foregroundColor(Theme.muted)
                        }
                    }
                    HStack(spacing: 6) {
                        Label(a.teacherName.isEmpty ? "未指定老师" : a.teacherName,
                              systemImage: "person.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.muted)
                        if !a.service.isEmpty {
                            Text("· \(a.service)")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.muted)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 0)

                Text(a.status.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(red: a.status.color.r,
                                           green: a.status.color.g,
                                           blue: a.status.color.b))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(red: a.status.color.r,
                                      green: a.status.color.g,
                                      blue: a.status.color.b).opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(11)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.line, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(AppointmentStatus.allCases) { s in
                Button {
                    var copy = a
                    copy.status = s
                    store.updateAppointment(copy)
                } label: {
                    Label("标记为\(s.rawValue)", systemImage: a.status == s ? "checkmark" : "circle")
                }
            }
            Divider()
            Button(role: .destructive) {
                pendingDelete = a
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

// MARK: - 预约编辑

struct AppointmentEditSheet: View {
    let appointmentID: UUID?
    let presetTeacherID: UUID?

    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var teacherID: UUID?
    @State private var clientID: UUID?
    @State private var clientName = ""
    @State private var phone = ""
    @State private var service = ""
    @State private var date = Date().addingTimeInterval(3600)
    @State private var duration = 60
    @State private var status: AppointmentStatus = .pending
    @State private var note = ""
    @State private var loaded = false

    private var isNew: Bool { appointmentID == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("老师") {
                    if store.teachers.isEmpty {
                        Text("还没有老师，请先在「老师」页添加")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.muted)
                    } else {
                        Picker("选择老师", selection: $teacherID) {
                            Text("未指定").tag(UUID?.none)
                            ForEach(store.sortedTeachers) { t in
                                Text("\(t.name)（\(t.displayTitle)）").tag(UUID?.some(t.id))
                            }
                        }
                    }
                }

                Section("客户") {
                    Picker("关联客户", selection: $clientID) {
                        Text("不关联 / 手填").tag(UUID?.none)
                        ForEach(store.clients) { c in
                            Text(c.name).tag(UUID?.some(c.id))
                        }
                    }
                    .onChange(of: clientID) { id in
                        guard let id, let c = store.client(id) else { return }
                        clientName = c.name
                        phone = c.phone
                    }

                    TextField("客户姓名", text: $clientName)
                    TextField("联系电话", text: $phone)
                        .keyboardType(.phonePad)
                }

                Section("服务") {
                    TextField("项目，例如 面部补水护理", text: $service)
                    DatePicker("时间", selection: $date,
                               displayedComponents: [.date, .hourAndMinute])
                    Picker("时长", selection: $duration) {
                        ForEach([30, 45, 60, 90, 120, 150, 180], id: \.self) { m in
                            Text("\(m) 分钟").tag(m)
                        }
                    }
                    Picker("状态", selection: $status) {
                        ForEach(AppointmentStatus.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                }

                Section("备注") {
                    TextField("特殊要求、注意事项", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.cream)
            .navigationTitle(isNew ? "新建预约" : "编辑预约")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true

        if let id = appointmentID, let a = store.appointments.first(where: { $0.id == id }) {
            teacherID = a.teacherID
            clientID = a.clientID
            clientName = a.clientName
            phone = a.phone
            service = a.service
            date = a.date
            duration = a.durationMinutes
            status = a.status
            note = a.note
        } else {
            teacherID = presetTeacherID ?? store.sortedTeachers.first(where: \.available)?.id
        }
    }

    private func save() {
        let name = clientName.trimmingCharacters(in: .whitespaces)
        let tid = teacherID ?? UUID()
        let tname = teacherID.map { store.teacherName($0) } ?? ""

        if let id = appointmentID,
           var a = store.appointments.first(where: { $0.id == id }) {
            a.teacherID = tid
            a.teacherName = tname
            a.clientID = clientID
            a.clientName = name
            a.phone = phone
            a.service = service
            a.date = date
            a.durationMinutes = duration
            a.status = status
            a.note = note
            store.updateAppointment(a)
        } else {
            let a = Appointment(teacherID: tid, teacherName: tname,
                                clientID: clientID, clientName: name, phone: phone,
                                service: service, date: date, durationMinutes: duration,
                                status: status, note: note)
            store.addAppointment(a)
        }
        dismiss()
    }
}
