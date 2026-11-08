import SwiftUI

struct NotesView: View {
    @Binding var client: Client
    @EnvironmentObject var store: Store

    @State private var draft = ""
    @State private var editTarget: TextNote?
    @State private var editText = ""
    @State private var showNoteEditor = false

    private var sortedNotes: [TextNote] {
        client.notes.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 14) {
            noteCard
            recordsSection
            composer
        }
        .sheet(item: $editTarget) { target in
            NavigationStack {
                Form {
                    Section("内容") {
                        TextEditor(text: $editText)
                            .frame(minHeight: 160)
                    }
                }
                .navigationTitle("编辑记录")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { editTarget = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            if let i = client.notes.firstIndex(where: { $0.id == target.id }) {
                                client.notes[i].content = editText
                                store.save()
                            }
                            editTarget = nil
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: 客户备注

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "客户备注", trailing: "长期信息")
            TextEditor(text: $client.note)
                .font(.system(size: 14))
                .frame(minHeight: 96)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Theme.cream)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if client.note.isEmpty {
                        Text("皮肤状况、过敏史、偏好、忌讳、消费习惯……")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.muted.opacity(0.7))
                            .padding(.top, 16)
                            .padding(.leading, 13)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: client.note) { _ in store.save() }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    // MARK: 跟进记录

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "跟进记录", trailing: "\(client.notes.count) 条")

            if sortedNotes.isEmpty {
                Text("每次护理后的反馈、客户诉求、下次预约……都记在这里")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
                    .padding(.vertical, 8)
            } else {
                ForEach(sortedNotes) { n in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(Fmt.dateTime.string(from: n.createdAt))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Theme.roseDeep)
                            Spacer()
                            Menu {
                                Button {
                                    editTarget = n
                                    editText = n.content
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    client.notes.removeAll { $0.id == n.id }
                                    store.save()
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Theme.muted)
                                    .frame(width: 26, height: 22)
                                    .contentShape(Rectangle())
                            }
                        }
                        Text(n.content)
                            .font(.system(size: 14))
                            .foregroundColor(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.line, lineWidth: 0.8))
                }
            }
        }
    }

    // MARK: 输入

    private var composer: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                TextField("写一条新记录……", text: $draft, axis: .vertical)
                    .font(.system(size: 14))
                    .lineLimit(1...5)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.line, lineWidth: 0.8))

                Button {
                    addNote()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 42, height: 42)
                        .background(Theme.gradRose)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }
        }
    }

    private func addNote() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        client.notes.append(TextNote(content: t))
        draft = ""
        store.save()
    }
}
