import SwiftUI

struct StepsView: View {
    @Binding var client: Client
    @EnvironmentObject var store: Store

    @State private var newTitle = ""
    @State private var renameTarget: StepItem?
    @State private var renameText = ""
    @State private var noteTarget: StepItem?
    @State private var noteText = ""
    @State private var showResetConfirm = false

    var body: some View {
        VStack(spacing: 12) {
            progressCard

            if client.steps.isEmpty {
                EmptyHint(icon: "list.bullet.clipboard",
                          title: "还没有流程环节",
                          subtitle: "在下方添加，或一键套用设置里的模板")
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(client.steps.enumerated()), id: \.element.id) { idx, step in
                        row(index: idx, step: step)
                    }
                }
            }

            addRow
            templateRow
        }
        .alert("修改环节名称", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("环节名称", text: $renameText)
            Button("取消", role: .cancel) { renameTarget = nil }
            Button("保存") { commitRename() }
        }

        .sheet(item: $noteTarget) { target in
            NavigationStack {
                Form {
                    Section("环节备注") {
                        TextEditor(text: $noteText)
                            .frame(minHeight: 130)
                    }
                }
                .navigationTitle(target.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { noteTarget = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            if let i = client.steps.firstIndex(where: { $0.id == target.id }) {
                                client.steps[i].note = noteText
                                store.save()
                            }
                            noteTarget = nil
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium])
        }

        .alert("套用流程模板？", isPresented: $showResetConfirm) {
            Button("取消", role: .cancel) {}
            Button("替换", role: .destructive) { applyTemplate() }
        } message: {
            Text("会用设置中的模板（\(store.settings.stepTemplate.joined(separator: " → "))）替换当前流程，已完成记录会丢失。")
        }
    }

    // MARK: 进度卡

    private var progressCard: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("当前环节")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.muted)
                    Text(client.currentStageTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.ink)
                }
                Spacer()
                Text("\(client.doneStepCount)/\(client.steps.count)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.roseDeep)
            }
            ProgressBar(value: client.progress, height: 8)
            HStack {
                Text("完成度 \(Int(client.progress * 100))%")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.muted)
                Spacer()
                if let last = client.steps.last(where: { $0.done }), let d = last.doneAt {
                    Text("最近更新 \(Fmt.dateOnly.string(from: d))")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.muted)
                }
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    // MARK: 单行

    private func row(index: Int, step: StepItem) -> some View {
        HStack(spacing: 11) {
            Button {
                toggle(step)
            } label: {
                ZStack {
                    Circle()
                        .stroke(step.done ? Color.clear : Theme.line, lineWidth: 1.5)
                        .background(Circle().fill(step.done ? Theme.rose : Color.clear))
                        .frame(width: 24, height: 24)
                    if step.done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.muted)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.system(size: 14, weight: step.done ? .medium : .regular))
                    .foregroundColor(step.done ? Theme.ink : Theme.inkSoft)
                    .strikethrough(false)
                HStack(spacing: 6) {
                    if let d = step.doneAt {
                        Text(Fmt.dateTime.string(from: d))
                            .font(.system(size: 10))
                            .foregroundColor(Theme.muted)
                    }
                    if !step.note.isEmpty {
                        Text(step.note)
                            .font(.system(size: 10))
                            .foregroundColor(Theme.muted)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            Menu {
                Button {
                    renameTarget = step
                    renameText = step.title
                } label: {
                    Label("重命名", systemImage: "pencil")
                }
                Button {
                    noteTarget = step
                    noteText = step.note
                } label: {
                    Label("备注", systemImage: "text.bubble")
                }
                Button {
                    move(index: index, delta: -1)
                } label: {
                    Label("上移", systemImage: "arrow.up")
                }
                Button {
                    move(index: index, delta: 1)
                } label: {
                    Label("下移", systemImage: "arrow.down")
                }
                Button(role: .destructive) {
                    client.steps.removeAll { $0.id == step.id }
                    store.save()
                } label: {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.muted)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    // MARK: 添加

    private var addRow: some View {
        HStack(spacing: 8) {
            TextField("新增环节，例如「第 4 次护理」", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.line, lineWidth: 0.8))

            Button {
                let t = newTitle.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty else { return }
                client.steps.append(StepItem(title: t))
                newTitle = ""
                store.save()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Theme.gradRose)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(newTitle.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
    }

    private var templateRow: some View {
        HStack {
            Button {
                showResetConfirm = true
            } label: {
                Label("套用流程模板", systemImage: "square.on.square")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.roseDeep)
            }
            Spacer()
            if client.doneStepCount > 0 {
                Button {
                    for i in client.steps.indices {
                        client.steps[i].done = false
                        client.steps[i].doneAt = nil
                    }
                    store.save()
                } label: {
                    Text("清空进度")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.muted)
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: 操作

    private func toggle(_ step: StepItem) {
        guard let i = client.steps.firstIndex(where: { $0.id == step.id }) else { return }
        client.steps[i].done.toggle()
        client.steps[i].doneAt = client.steps[i].done ? Date() : nil
        store.save()
    }

    private func move(index: Int, delta: Int) {
        let target = index + delta
        guard target >= 0, target < client.steps.count else { return }
        let item = client.steps.remove(at: index)
        client.steps.insert(item, at: target)
        store.save()
    }

    private func commitRename() {
        guard let t = renameTarget,
              let i = client.steps.firstIndex(where: { $0.id == t.id }) else {
            renameTarget = nil
            return
        }
        let v = renameText.trimmingCharacters(in: .whitespaces)
        if !v.isEmpty { client.steps[i].title = v }
        renameTarget = nil
        store.save()
    }

    private func applyTemplate() {
        client.steps = store.settings.stepTemplate.map { StepItem(title: $0) }
        store.save()
    }
}
