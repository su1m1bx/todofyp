import AppKit
import SwiftUI
import TodoCore

@main
enum AppMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: WindowCoordinator!
    private var store: AppStore?
    private var smokeDirectory: URL?
    private var launchCheck: LaunchCheck?

    func applicationDidFinishLaunching(_ notification: Notification) {
        windows = WindowCoordinator()
        installMainMenu()
        if CommandLine.arguments.contains("--prototype") || CommandLine.arguments.contains("--self-check") || CommandLine.arguments.contains("--launch-check") {
            windows.install(content: AnyView(PrototypeView(hide: { [weak self] in self?.windows.hide() })))
        } else {
            if CommandLine.arguments.contains("--smoke-check") {
                smokeDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ImportantTodo-smoke-\(UUID().uuidString)")
            }
            let store = AppStore(storageURL: smokeDirectory?.appendingPathComponent("document.json"))
            self.store = store
            windows.install(content: AnyView(TodoListView(store: store, windows: windows)))
            if let frame = store.document.settings.windowFrame {
                windows.restoreFrame(NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height))
            }
            windows.frameChanged = { [weak store] in store?.queueFrame($0) }
            windows.openSettings = { [weak store] in store?.showingSettings = true }
        }
        windows.show()
        if CommandLine.arguments.contains("--launch-check") {
            launchCheck = LaunchCheck(windows: windows)
            launchCheck?.begin()
        }
        if CommandLine.arguments.contains("--self-check") || CommandLine.arguments.contains("--smoke-check") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                await runSelfCheck()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let wasHidden = windows?.panel.isVisible == false
        windows?.show()
        launchCheck?.reopened(wasHidden: wasHidden)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store?.flushFrame() == false else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "마지막 창 위치를 저장하지 못했습니다."
        alert.informativeText = store?.error ?? "이전에 저장된 위치는 유지됩니다."
        alert.addButton(withTitle: "돌아가기")
        alert.addButton(withTitle: "저장하지 않고 종료")
        alert.window.level = windows.panel.level
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    private func installMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "편집")
        for (title, selector, key) in [
            ("실행 취소", Selector(("undo:")), "z"),
            ("오려두기", #selector(NSText.cut(_:)), "x"),
            ("복사", #selector(NSText.copy(_:)), "c"),
            ("붙여넣기", #selector(NSText.paste(_:)), "v"),
            ("모두 선택", #selector(NSText.selectAll(_:)), "a")
        ] { editMenu.addItem(withTitle: title, action: selector, keyEquivalent: key) }
        let redo = editMenu.addItem(withTitle: "다시 실행", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    private func runSelfCheck() async {
        let initial = windows.panel.isVisible
        windows.hide()
        let hidden = !windows.panel.isVisible && !windows.panel.isMiniaturized
        windows.toggle()
        let restored = windows.panel.isVisible
        windows.hide()
        _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
        let reopened = windows.panel.isVisible
        windows.panel.makeKey()
        var results: [String: Any] = [
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "initialVisible": initial, "hideWithoutMinimize": hidden,
            "toggleRestores": restored, "reopenHandlerRestores": reopened,
            "canBecomeKey": windows.panel.canBecomeKey,
            "becameKey": windows.panel.isKeyWindow,
            "statusItemInstalled": windows.statusItem.button != nil,
            "accessoryPolicy": NSApp.activationPolicy() == .accessory,
            "windowLevel": windows.panel.level.rawValue,
            "collectionBehavior": windows.panel.collectionBehavior.rawValue,
            "initialFrame": NSStringFromRect(windows.panel.frame),
            "initialMinimum": NSStringFromSize(windows.panel.minSize),
            "sandboxHome": NSHomeDirectory(),
            "scope": "Own-window state only; no visual, Spaces, full-screen, Stage Manager or actual relaunch validation"
        ]
        var passed = initial && hidden && restored && reopened && windows.panel.isKeyWindow && windows.panel.level == .screenSaver
            && windows.panel.frame.width >= 280 && windows.panel.frame.height >= 240
        if let store, let smokeDirectory {
            let size = windows.panel.frame.size
            let saved = store.update { document in
                for index in 1...125 { try document.add(title: "검사 항목 \(index)") }
            }
            // Let SwiftUI actually reconcile the changed list before measuring it.
            try? await Task.sleep(for: .milliseconds(200))
            windows.panel.contentView?.layoutSubtreeIfNeeded()
            let stableSize = windows.panel.frame.size == size
            results["saved125Items"] = saved && store.document.todos.count == 125
            results["listWindowSizeUnchanged"] = stableSize
            let roundTrip = (try? Repository(url: smokeDirectory.appendingPathComponent("document.json")).document) == store.document
            results["sandboxStorageRoundTrip"] = roundTrip
            let formatting = RichTextChecks.run()
            results["richTextChecks"] = formatting
            var appearanceChecks: [String: Bool] = [:]
            for mode in AppAppearance.allCases {
                let savedMode = store.update { $0.settings.appearance = mode }
                try? await Task.sleep(for: .milliseconds(100))
                let match = windows.panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
                switch mode {
                case .system: appearanceChecks[mode.rawValue] = savedMode && NSApp.appearance == nil
                case .light: appearanceChecks[mode.rawValue] = savedMode && match == .aqua
                case .dark: appearanceChecks[mode.rawValue] = savedMode && match == .darkAqua
                }
            }
            store.update { $0.settings.appearance = .system }
            results["appearanceChecks"] = appearanceChecks
            let originalFrame = windows.panel.frame
            windows.panel.setFrame(NSRect(origin: originalFrame.origin, size: windows.panel.minSize), display: true)
            try? await Task.sleep(for: .milliseconds(100))
            windows.panel.contentView?.layoutSubtreeIfNeeded()
            let titlebarInset = windows.panel.contentView?.safeAreaInsets.top ?? 0
            results["minimumWindowTitlebarInset"] = titlebarInset
            results["titlebarMetrics"] = [
                "frame": NSStringFromRect(windows.panel.frame),
                "content": NSStringFromRect(windows.panel.contentView?.frame ?? .zero),
                "layout": NSStringFromRect(windows.panel.contentLayoutRect),
                "additionalTop": windows.panel.contentView?.additionalSafeAreaInsets.top ?? 0
            ] as [String: Any]
            windows.panel.setFrame(originalFrame, display: true)
            results["scope"] = "MVP own-window layout, sandbox storage and NSTextView formatting only; no visual/interaction acceptance"
            passed = passed && saved && stableSize && roundTrip && formatting.values.allSatisfy { $0 }
                && appearanceChecks.values.allSatisfy { $0 } && titlebarInset > 0
            try? FileManager.default.removeItem(at: smokeDirectory)
        }
        results["passed"] = passed
        if let data = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print(text) }
        exit(passed ? 0 : 1)
    }
}
