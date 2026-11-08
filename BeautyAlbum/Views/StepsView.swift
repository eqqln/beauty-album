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
    /// 快进到第 N 步（index）
    @State private var skipIndex: Int?
    /// 撤销到第 N 步（index）
    @State private var undoIndex: Int?

    // MARK: 顺序推进的状态

    /// 从头数，连续打勾的环节数
    private var donePrefix: Int { client.steps.prefix(while: { $0.done }).count }
    /// 当前该做的那一步的下标；全部做完为 nil
    private var currentIndex: Int? {
        donePrefix < client.steps.count ? donePrefix : nil
    }
    private var allDone: Bool {
        !client.steps.isEmpty && donePrefix == client.steps.count
    }

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
        .onAppear(perform: normalize)
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

        .alert("跳到第 \((skipIndex ?? 0) + 1) 步？", isPresented: Binding(
            get: { skipIndex != nil },
            set: { if !$0 { skipIndex = nil } }
        )) {
            Button("取消", role: .cancel) { skipIndex = nil }
            Button("跳过中间环节") { commitSkip() }
        } message: {
            Text(skipMessage)
        }

        .alert("撤销到第 \((undoIndex ?? 0) + 1) 步？", isPresented: Binding(
            get: { undoIndex != nil },
            set: { if !$0 { undoIndex = nil } }
        )) {
            Button("取消", role: .cancel) { undoIndex = nil }
            Button("撤销", role: .destructive) { commitUndo() }
        } message: {
            Text(undoMessage)
        }
    }

    private var skipMessage: String {
        guard let i = skipIndex else { return "" }
        let skipped = i - donePrefix
        return "「\(client.steps[i].title)」会成为当前环节，中间 \(skipped) 个环节标记为已完成。"
    }

    private var undoMessage: String {
        guard let i = undoIndex else { return "" }
        let redo = donePrefix - i
        return "「\(client.steps[i].title)」会变回未完成，后面 \(max(0, redo - 1)) 个已完成的环节也会一起撤销。"
    }

    // MARK: 进度卡

    private var progressCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(allDone ? "全部完成" : "当前环节")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.muted)

                    if allDone {
                        Text("疗程已走完")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Theme.ink)
                    } else {
                        // 步数可以直接改：左右箭头逐步走，点中间数字跳到任意一步
                        HStack(spacing: 8) {
                            Button {
                                stepBack()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(donePrefix == 0 ? Theme.muted.opacity(0.4) : Theme.roseDeep)
                                    .frame(width: 28, height: 28)
                                    .background(Theme.roseLight)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(donePrefix == 0)

                            Menu {
                                ForEach(Array(client.steps.enumerated()), id: \.element.id) { idx, st in
                                    Button {
                                        jump(to: idx)
                                    } label: {
                                        if idx < donePrefix {
                                            Label("第 \(idx + 1) 步 · \(st.title)（已完成）",
                                                  systemImage: "checkmark.circle")
                                        } else if idx == donePrefix {
                                            Label("第 \(idx + 1) 步 · \(st.title)（当前）",
                                                  systemImage: "smallcircle.filled.circle")
                                        } else {
                                            Label("第 \(idx + 1) 步 · \(st.title)",
                                                  systemImage: "circle")
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Text("第 \(client.currentStepNumber) 步")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(Theme.roseDeep)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(Theme.roseDeep.opacity(0.7))
                                }
                            }

                            Button {
                                completeCurrent()
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Theme.rose)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }

                        Text("共 \(client.steps.count) 步 · 点数字可跳到任意一步")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.muted)

                        if !client.steps.isEmpty {
                            Text(client.steps[min(client.currentStepNumber - 1,
                                                  client.steps.count - 1)].title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Theme.ink)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 8)

                VStack(spacing: 1) {
                    Text("\(donePrefix)/\(client.steps.count)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Theme.roseDeep)
                    Text("已完成")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.muted)
                }
            }

            ProgressBar(value: client.progress, height: 8)

            if allDone {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 0.36, green: 0.65, blue: 0.45))
                    Text(finishedText)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.inkSoft)
                    Spacer()
                    Button {
                        resetProgress()
                    } label: {
                        Text("重新开始")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.muted)
                    }
                    .buttonStyle(.plain)
                }
            } else if let i = currentIndex {
                Button {
                    completeCurrent()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                        Text("完成「\(client.steps[i].title)」，进入下一步")
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 0.8))
    }

    private var finishedText: String {
        if let d = client.steps.compactMap({ $0.doneAt }).max() {
            return "最后一步完成于 \(Fmt.dateOnly.string(from: d))"
        }
        return "所有环节都已完成"
    }

    // MARK: 单行

    private func row(index: Int, step: StepItem) -> some View {
        let isDone = index < donePrefix
        let isCurrent = index == donePrefix && index < client.steps.count

        return HStack(spacing: 11) {
            Button {
                tapStep(index: index)
            } label: {
                ZStack {
                    Circle()
                        .stroke(isDone ? Color.clear : (isCurrent ? Theme.rose : Theme.line),
                                lineWidth: isCurrent ? 2 : 1.5)
                        .background(Circle().fill(isDone ? Theme.rose : Color.clear))
                        .frame(width: 26, height: 26)
                    if isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: isCurrent ? .bold : .medium))
                            .foregroundColor(isCurrent ? Theme.roseDeep : Theme.muted)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(step.title)
                        .font(.system(size: 14, weight: isCurrent || isDone ? .medium : .regular))
                        .foregroundColor(isDone ? Theme.inkSoft : (isCurrent ? Theme.ink : Theme.muted))
                        .lineLimit(1)
                    if isCurrent {
                        Text("当前")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.rose)
                            .clipShape(Capsule())
                    }
                }
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
                    if !isDone && !isCurrent {
                        Text("点一下可快进")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.muted.opacity(0.7))
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
                    normalize()
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
        .background(isCurrent ? Theme.card : Theme.card.opacity(isDone ? 0.85 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isCurrent ? Theme.rose : Theme.line, lineWidth: isCurrent ? 1.2 : 0.8)
        )
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
            if donePrefix > 0 {
                Button {
                    resetProgress()
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

    /// 点圆圈：当前这一步→完成；其它→跳过去（后面确认，前面撤销）
    private func tapStep(index: Int) {
        if index == donePrefix {
            completeCurrent()
        } else {
            jump(to: index)
        }
    }

    private func completeCurrent() {
        guard let i = currentIndex else { return }
        client.steps[i].done = true
        client.steps[i].doneAt = Date()
        store.save()
    }

    /// 回退一步：上一步变回未完成
    private func stepBack() {
        guard donePrefix > 0 else { return }
        jump(to: donePrefix - 1)
    }

    /// 跳到第 index 步，让它成为当前环节。
    /// 往前跳 = 撤销后面的勾；往后跳 = 把中间的补成已完成。
    private func jump(to index: Int) {
        guard index >= 0, index < client.steps.count else { return }
        if index < donePrefix {
            undoIndex = index
            if donePrefix - index <= 1 { commitUndo() }
        } else if index > donePrefix {
            skipIndex = index
        }
    }

    private func commitSkip() {
        guard let target = skipIndex else { return }
        let now = Date()
        for i in donePrefix..<min(target, client.steps.count) {
            client.steps[i].done = true
            client.steps[i].doneAt = now
        }
        skipIndex = nil
        store.save()
    }

    private func commitUndo() {
        guard let target = undoIndex else { return }
        for i in target..<client.steps.count {
            client.steps[i].done = false
            client.steps[i].doneAt = nil
        }
        undoIndex = nil
        store.save()
    }

    private func resetProgress() {
        for i in client.steps.indices {
            client.steps[i].done = false
            client.steps[i].doneAt = nil
        }
        store.save()
    }

    private func move(index: Int, delta: Int) {
        let target = index + delta
        guard target >= 0, target < client.steps.count else { return }
        let item = client.steps.remove(at: index)
        client.steps.insert(item, at: target)
        normalize()
        store.save()
    }

    /// 保证「已完成」永远是开头连续的一段，否则第 N 步会算错
    private func normalize() {
        var seenUndone = false
        var changed = false
        for i in client.steps.indices {
            if !client.steps[i].done { seenUndone = true }
            if client.steps[i].done && seenUndone {
                client.steps[i].done = false
                client.steps[i].doneAt = nil
                changed = true
            }
        }
        if changed { store.save() }
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
