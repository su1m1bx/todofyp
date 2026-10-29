import AppKit
import ServiceManagement
import SwiftUI
import TodoCore

struct SettingsView: View {
    @ObservedObject var store: AppStore
    let windows: WindowCoordinator
    @State private var categoryName = ""
    @State private var editingCategory: UUID?
    @State private var deletingCategory: TodoCore.Category?

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "설정", subtitle: "나에게 편한 모습으로.") {
                PanelIconButton(symbol: "minus", label: "숨기기", action: windows.hide)
                Button { store.showingSettings = false } label: { Text("완료").foregroundStyle(.primary) }
                    .buttonStyle(.glass).controlSize(.small).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SoftSection(title: "외형", symbol: "paintpalette") {
                        Picker("화면 모드", selection: setting(\.appearance)) {
                            Text("시스템").tag(AppAppearance.system)
                            Text("라이트").tag(AppAppearance.light)
                            Text("다크").tag(AppAppearance.dark)
                        }
                        .pickerStyle(.segmented)
                        Text("시스템을 선택하면 Mac의 화면 모드를 따라갑니다.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        ColorPicker("배경 색상", selection: colorBinding(\.background), supportsOpacity: false)
                        ColorPicker("완료 체크 색상", selection: colorBinding(\.checkColor), supportsOpacity: false)
                        Toggle("이미지 배경", isOn: setting(\.useImage)).disabled(store.document.settings.image == nil)
                        Button { store.importImage(parent: windows.panel) } label: {
                            Label("이미지 선택…", systemImage: "photo").foregroundStyle(.primary)
                        }.buttonStyle(.glass).controlSize(.small)
                        Text("PNG, JPEG, HEIC · 10MiB / 24MP 이하\n원본은 그대로, 사본만 보관해요.").font(.system(size: 11)).foregroundStyle(.tertiary)
                        if store.document.settings.image != nil {
                            Picker("이미지 맞춤", selection: setting(\.imageFill)) {
                                Text("채우기").tag(true)
                                Text("맞추기").tag(false)
                            }
                            .pickerStyle(.segmented)
                            Text("배경 위 가독성").font(.caption).foregroundStyle(.secondary)
                            Slider(value: setting(\.overlay), in: 0...1).accessibilityLabel("이미지 가독성 오버레이")
                            Button("이미지 제거", role: .destructive) { store.update { $0.settings.image = nil; $0.settings.useImage = false } }
                                .buttonStyle(.link)
                        }
                    }
                    SoftSection(title: "카테고리", symbol: "tag") {
                        HStack(spacing: 6) {
                            TextField(editingCategory == nil ? "새 카테고리" : "이름 변경", text: $categoryName)
                                .softInput().onSubmit(saveCategory)
                            Button(action: saveCategory) { Text(editingCategory == nil ? "추가" : "저장").foregroundStyle(.primary) }
                                .buttonStyle(.glass).controlSize(.small)
                        }
                        if editingCategory != nil { Button("이름 변경 취소") { editingCategory = nil; categoryName = "" }.buttonStyle(.link) }
                        ForEach(store.document.categories) { category in
                            HStack {
                                Text(category.name).font(.system(size: 13))
                                Spacer()
                                PanelIconButton(symbol: "pencil", label: "\(category.name) 이름 변경") { editingCategory = category.id; categoryName = category.name }
                                PanelIconButton(symbol: "trash", label: "\(category.name) 삭제") { deletingCategory = category }
                            }
                        }
                        if let category = deletingCategory {
                            let count = store.document.todos.filter { $0.categoryIDs.contains(category.id) }.count
                            Text("‘\(category.name)’ 삭제 시 \(count)개의 연결만 제거해요. 할 일은 유지됩니다.").font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("취소") { deletingCategory = nil }
                                Button("카테고리 삭제", role: .destructive) {
                                    if store.update({ $0.deleteCategory(category.id) }) {
                                        if editingCategory == category.id { editingCategory = nil; categoryName = "" }
                                        deletingCategory = nil
                                    }
                                }
                            }
                        }
                    }
                    SoftSection(title: "실행 및 복구", symbol: "menubar.rectangle") {
                        Toggle("로그인 시 시작", isOn: Binding(get: { store.loginEnabled }, set: store.setLogin)).disabled(store.loginBusy)
                        Text(store.loginStatus).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("상태 새로 고침") { store.refreshLoginStatus() }
                            Spacer()
                            Button("시스템 설정…") { SMAppService.openSystemSettingsLoginItems() }
                        }.buttonStyle(.link).font(.caption)
                        Divider().opacity(0.4)
                        Text("메뉴 막대 아이콘 클릭: 표시/숨기기. 보조 클릭: 보기·설정·종료. 아이콘이 안 보이면 Finder에서 앱을 다시 실행하세요. 기존 창을 복구합니다.").font(.caption)
                        Text("전체 화면·Spaces·Stage Manager는 실기기 검증 전이에요. 잠금 화면·시스템 보안 UI 위 표시는 보장하지 않습니다.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("앱 종료") { NSApp.terminate(nil) }
                        .buttonStyle(QuietButtonStyle()).frame(maxWidth: .infinity)
                }
                .toggleStyle(.switch).controlSize(.small)
                .padding(.horizontal, 16).padding(.bottom, 16).disabled(!store.writable)
            }
        }
        .onAppear {
            store.refreshLoginStatus()
            NSColorPanel.shared.level = windows.panel.level
            NSColorPanel.shared.collectionBehavior = windows.panel.collectionBehavior
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.refreshLoginStatus() }
    }

    private func setting<T>(_ path: WritableKeyPath<TodoCore.Settings, T>) -> Binding<T> {
        Binding(get: { store.document.settings[keyPath: path] }, set: { value in store.update { $0.settings[keyPath: path] = value } })
    }

    private func colorBinding(_ path: WritableKeyPath<TodoCore.Settings, RGBA>) -> Binding<Color> {
        Binding(get: { store.document.settings[keyPath: path].color }, set: { value in
            NSColorPanel.shared.level = windows.panel.level
            store.update { $0.settings[keyPath: path] = RGBA(color: value) }
        })
    }

    private func saveCategory() {
        if store.update({ try $0.saveCategory(id: editingCategory, name: categoryName) }) {
            editingCategory = nil; categoryName = ""
        }
    }
}
