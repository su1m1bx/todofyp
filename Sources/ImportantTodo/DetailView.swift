import SwiftUI
import TodoCore

struct DetailView: View {
    @ObservedObject var store: AppStore
    let original: Todo
    let hide: () -> Void
    let close: () -> Void
    @State private var draft: Todo
    @State private var confirmingDiscard = false
    @StateObject private var formatting = RichTextController()

    init(store: AppStore, original: Todo, hide: @escaping () -> Void, close: @escaping () -> Void) {
        self.store = store; self.original = original; self.hide = hide; self.close = close
        _draft = State(initialValue: original)
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "상세", subtitle: "생각을 조금 더 자세히.") {
                PanelIconButton(symbol: "minus", label: "숨기기", action: hide)
                Button("취소", action: cancel).keyboardShortcut(.cancelAction).buttonStyle(QuietButtonStyle())
                Button {
                    if store.update({ try $0.edit(draft) }) { close() }
                } label: { Text("저장").foregroundStyle(.white) }
                .buttonStyle(.glassProminent).controlSize(.small)
                .keyboardShortcut("s", modifiers: .command).disabled(!store.writable)
            }
            if confirmingDiscard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("변경 사항을 버릴까요?", systemImage: "exclamationmark.circle").font(.system(size: 12, weight: .medium))
                    HStack {
                        Button("계속 편집") { confirmingDiscard = false }
                        Button("변경 버리기", role: .destructive, action: close)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("제목", text: $draft.title, axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: 21, weight: .semibold))
                        .lineLimit(1...3).padding(.horizontal, 4).padding(.top, 4)
                    VStack(spacing: 0) {
                        HStack(spacing: 2) {
                            PanelIconButton(symbol: "bold", label: "선택한 텍스트 굵게 (⌘B)", action: formatting.bold)
                            PanelIconButton(symbol: "italic", label: "선택한 텍스트 기울임 (⌘I)", action: formatting.italic)
                            PanelIconButton(symbol: "underline", label: "선택한 텍스트 밑줄 (⌘U)", action: formatting.underline)
                            Spacer()
                            Text("메모").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.trailing, 6)
                        }.padding(6)
                        RichTextEditor(data: $draft.richText, controller: formatting).frame(height: 150)
                    }
                    .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    SoftSection(title: "기한", symbol: "calendar") {
                        Toggle("날짜 지정", isOn: Binding(get: { draft.due != nil }, set: { draft.due = $0 ? Day(date: .now) : nil }))
                            .toggleStyle(.switch).controlSize(.small)
                        if draft.due != nil {
                            DatePicker("기한", selection: Binding(get: { draft.due?.date() ?? .now }, set: { draft.due = Day(date: $0) }), displayedComponents: .date)
                            Button("기한 없음") { draft.due = nil }.buttonStyle(.link)
                        }
                    }
                    SoftSection(title: "카테고리", symbol: "tag") {
                        if store.document.categories.isEmpty {
                            Text("설정에서 나만의 카테고리를 만들어보세요.").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(store.document.categories) { category in
                            Toggle(category.name, isOn: Binding(
                                get: { draft.categoryIDs.contains(category.id) },
                                set: { if $0 { draft.categoryIDs.insert(category.id) } else { draft.categoryIDs.remove(category.id) } }
                            )).toggleStyle(.checkbox)
                        }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 20)
            }
        }
        .onExitCommand(perform: cancel)
    }

    private func cancel() {
        if draft != original { confirmingDiscard = true } else { close() }
    }
}
