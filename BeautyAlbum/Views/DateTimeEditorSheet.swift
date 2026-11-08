import SwiftUI

/// 通用「日期 + 时间」编辑器
/// 建档时间、环节完成时间都用它，保证各处改时间的手感一致
struct DateTimeEditorSheet: View {
    let title: String
    let hint: String
    let onCommit: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Date

    init(title: String, hint: String, initial: Date, onCommit: @escaping (Date) -> Void) {
        self.title = title
        self.hint = hint
        self.onCommit = onCommit
        _draft = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("时间", selection: $draft, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                } header: {
                    Text("选择时间")
                } footer: {
                    Text(hint)
                }

                Section {
                    Button {
                        draft = Date()
                    } label: {
                        Label("设为现在", systemImage: "clock.arrow.circlepath")
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                        Text(Fmt.dateTime.string(from: draft))
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(Fmt.weekday(draft))
                            .font(.system(size: 12))
                            .foregroundColor(Theme.muted)
                    }
                    .foregroundColor(Theme.inkSoft)
                }
            }
            .background(Theme.cream)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onCommit(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
