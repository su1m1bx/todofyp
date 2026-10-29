import AppKit
import SwiftUI
import TodoCore
import UniformTypeIdentifiers

struct TodoListView: View {
    @ObservedObject var store: AppStore
    let windows: WindowCoordinator
    @State private var title = ""
    @State private var selection: UUID?
    @State private var editing: Todo?
    @State private var filter: UUID?
    @State private var categoryQuery = ""
    @State private var completedExpanded = false
    @State private var hoveredItem: UUID?
    @FocusState private var inputFocused: Bool

    private var active: [Todo] { visible(complete: false) }
    private var completed: [Todo] { visible(complete: true) }
    private var pending: [Todo] { store.document.todos.filter { $0.deleteAfter.map { $0 > store.now } ?? false } }

    var body: some View {
        VStack(spacing: 0) {
            if let error = store.error {
                VStack(alignment: .leading, spacing: 6) {
                    Label(error, systemImage: "exclamationmark.circle.fill").font(.caption).textSelection(.enabled)
                    if !store.writable { Button("데이터 다시 열기") { store.load() } }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                .padding([.horizontal, .top], 12)
            }
            if let editing {
                DetailView(store: store, original: editing, hide: windows.hide) { self.editing = nil }
                    .id(editing.id)
            } else if store.showingSettings {
                SettingsView(store: store, windows: windows)
            } else {
                listContent
            }
        }
        // Only the backdrop extends into the title bar; controls respect its safe area.
        .background {
            BackgroundView(settings: store.document.settings, image: store.backgroundImage)
                .ignoresSafeArea(.container, edges: .top)
        }
        .onChange(of: store.showingSettings) { _, showing in
            // The status menu must not discard an in-progress detail draft.
            if showing && editing != nil { store.showingSettings = false }
        }
    }

    private var listContent: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Todo List", subtitle: active.isEmpty ? "가볍게 정리하고, 하나씩." : "\(active.count)개의 할 일 · 하나씩, 차근차근") {
                PanelIconButton(symbol: "slider.horizontal.3", label: "설정 및 카테고리 관리") { store.showingSettings = true }
                PanelIconButton(symbol: "minus", label: "숨기기", action: windows.hide)
            }

            HStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                TextField("어떤 일을 할까요?", text: $title)
                    .textFieldStyle(.plain).font(.system(size: 14))
                    .focused($inputFocused).onSubmit(add)
                    .accessibilityLabel("새 할 일")
                Button(action: add) {
                    Image(systemName: "arrow.up").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.white)
                        .frame(width: 26, height: 26)
                        .background(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.primary.opacity(0.05) : Color.accentColor, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("할 일 추가").help("할 일 추가 (↩)")
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 11)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.accentColor.opacity(inputFocused ? 0.35 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 16).padding(.bottom, 12)
            .disabled(!store.writable)

            if !store.document.settings.hasSeenRecovery {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "menubar.arrow.up.rectangle").foregroundStyle(.secondary).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("언제든 다시, 여기서").font(.system(size: 11, weight: .semibold))
                        Text("아이콘이 안 보이면 Finder에서 앱을 다시 열어주세요.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    PanelIconButton(symbol: "xmark", label: "복구 안내 확인") {
                        store.update { $0.settings.hasSeenRecovery = true }
                    }
                }
                .padding(10)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16).padding(.bottom, 10)
            }

            if !store.document.categories.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.tertiary)
                    TextField("카테고리 검색", text: $categoryQuery).textFieldStyle(.plain).font(.system(size: 12))
                    Menu {
                        Button("전체 목록") { filter = nil; categoryQuery = "" }
                        ForEach(store.document.categories.filter { categoryQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(categoryQuery) }) { category in
                            Button(category.name) { filter = category.id }
                        }
                    } label: {
                        Label(store.document.categories.first(where: { $0.id == filter })?.name ?? "전체", systemImage: "line.3.horizontal.decrease")
                            .font(.system(size: 11, weight: .medium)).lineLimit(1)
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    if filter != nil {
                        PanelIconButton(symbol: "xmark.circle.fill", label: "필터 해제") { filter = nil; categoryQuery = "" }
                    }
                }.padding(.horizontal, 22).padding(.bottom, 8)
            }

            List(selection: $selection) {
                ForEach(active) { item in row(item) }
                if !completed.isEmpty {
                    DisclosureGroup(isExpanded: $completedExpanded) {
                        ForEach(completed) { item in row(item) }
                    } label: {
                        Text("완료 \(completed.count)")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                            .padding(.vertical, 7)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .contentMargins(.horizontal, 8, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .onKeyPress(.return) {
                guard !inputFocused, let id = selection,
                      let item = store.document.todos.first(where: { $0.id == id && $0.deleteAfter == nil }) else { return .ignored }
                editing = item; return .handled
            }
            .onKeyPress(keys: [.upArrow], phases: .down) { press in reorderKey(press, direction: -1) }
            .onKeyPress(keys: [.downArrow], phases: .down) { press in reorderKey(press, direction: 1) }
            .overlay {
                if active.isEmpty && completed.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: filter == nil ? "checkmark.circle" : "line.3.horizontal.decrease.circle")
                            .font(.system(size: 34, weight: .ultraLight)).foregroundStyle(.tertiary)
                        Text(filter == nil ? "조금 더 가벼운 하루" : "아직 할 일이 없어요")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                        Text(filter == nil ? "떠오르는 일을 위에 적어보세요." : "다른 카테고리도 확인해 보세요.")
                            .font(.system(size: 12)).foregroundStyle(.tertiary)
                    }.padding(.bottom, 24).allowsHitTesting(false)
                }
            }

            if !pending.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(pending) { item in
                            HStack(spacing: 8) {
                                Image(systemName: "trash").foregroundStyle(.secondary)
                                Text("삭제됨: \(item.title)").lineLimit(1).foregroundStyle(.secondary)
                                Spacer()
                                Button("실행 취소") { store.update { try $0.undoDelete(item.id) } }
                                    .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                                    .accessibilityLabel("\(item.title) 삭제 실행 취소")
                            }.font(.caption)
                        }
                    }.padding(12)
                }
                .frame(maxHeight: 82)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
        .onChange(of: store.document.categories) { _, categories in
            if let filter, !categories.contains(where: { $0.id == filter }) { self.filter = nil }
        }
    }

    private func visible(complete: Bool) -> [Todo] {
        store.document.todos.filter { $0.deleteAfter == nil && $0.isComplete == complete && (filter == nil || $0.categoryIDs.contains(filter!)) }
    }

    private func row(_ item: Todo) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Button { store.update { try $0.toggle(item.id) } } label: {
                Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(item.isComplete ? store.document.settings.checkColor.color : Color(nsColor: .tertiaryLabelColor))
                    .frame(width: 26, height: 28)
            }
            .accessibilityLabel("\(item.title), \(item.isComplete ? "완료 취소" : "완료")")
            .accessibilityValue(item.isComplete ? "완료됨" : "미완료")

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.system(size: 14)).lineLimit(2).strikethrough(item.isComplete)
                    .foregroundStyle(item.isComplete ? .secondary : .primary)
                    .padding(.top, 4)
                if let due = item.due {
                    Label { Text(due.date(), style: .date) } icon: { Image(systemName: "calendar") }
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                let names = store.document.categories.filter { item.categoryIDs.contains($0.id) }.map(\.name)
                if !names.isEmpty { Text(names.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { editing = item }
            .onTapGesture { selection = item.id }

            HStack(spacing: 0) {
                PanelIconButton(symbol: "ellipsis", label: "\(item.title) 상세 열기") { editing = item }
                PanelIconButton(symbol: "trash", label: "\(item.title) 삭제") { store.update { try $0.delete(item.id) } }
            }
            .opacity(hoveredItem == item.id || selection == item.id ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
        .tag(item.id)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.primary.opacity(hoveredItem == item.id ? 0.035 : 0))
        .onHover { hovering in hoveredItem = hovering ? item.id : (hoveredItem == item.id ? nil : hoveredItem) }
        .disabled(!store.writable)
        .onDrag { NSItemProvider(object: item.id.uuidString as NSString) }
        .onDrop(of: [UTType.text], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                guard let text, let id = UUID(uuidString: text) else { return }
                Task { @MainActor in store.update { $0.move(id, before: item.id) } }
            }
            return true
        }
        .contextMenu {
            Button("상세 열기") { editing = item }
            Button("위로 이동 (⌥↑)") { move(item.id, direction: -1) }
            Button("아래로 이동 (⌥↓)") { move(item.id, direction: 1) }
        }
    }

    private func reorderKey(_ press: KeyPress, direction: Int) -> KeyPress.Result {
        guard press.modifiers.contains(.option), let selection else { return .ignored }
        move(selection, direction: direction)
        return .handled
    }

    private func move(_ id: UUID, direction: Int) {
        let items = active.contains(where: { $0.id == id }) ? active : completed
        guard let index = items.firstIndex(where: { $0.id == id }), items.indices.contains(index + direction) else { return }
        let target = items[index + direction].id
        store.update { if direction < 0 { $0.move(id, before: target) } else { $0.move(id, after: target) } }
    }

    private func add() {
        if store.update({ try $0.add(title: title) }) { title = ""; inputFocused = true }
    }
}

private struct BackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let settings: TodoCore.Settings
    let image: NSImage?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if reduceTransparency {
                    Color(nsColor: .windowBackgroundColor)
                } else {
                    PanelMaterial()
                }
                settings.background.color.opacity(colorScheme == .dark ? 0.08 : 0.28)
                if settings.useImage, let image {
                    Image(nsImage: image).resizable()
                        .aspectRatio(contentMode: settings.imageFill ? .fill : .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    Color(nsColor: .windowBackgroundColor).opacity(settings.overlay)
                }
            }
        }.clipped().allowsHitTesting(false)
    }
}
