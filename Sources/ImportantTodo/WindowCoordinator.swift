import AppKit
import SwiftUI

final class TodoPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    let panel = TodoPanel(
        contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
        styleMask: [.titled, .resizable, .nonactivatingPanel, .fullSizeContentView],
        backing: .buffered, defer: false
    )
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var openSettings: (() -> Void)?
    var frameChanged: ((NSRect) -> Void)?

    func install(content: AnyView) {
        panel.title = "Todo List"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.toolbarStyle = .unified
        panel.isFloatingPanel = true
        // Setting isFloatingPanel resets the level; apply the overlay level afterwards.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let nativeContent = NSWindow.contentRect(forFrameRect: panel.frame, styleMask: [.titled])
        let titlebarHeight = max(0, panel.frame.height - nativeContent.height)
        let hosting = NSHostingView(rootView: content.frame(minWidth: 280, minHeight: max(0, 240 - titlebarHeight)))
        // Publish a real minimum without allowing content changes to resize the window.
        // Empty sizingOptions makes NSHostingView reset the native minimum to zero.
        hosting.sizingOptions = [.minSize]
        panel.contentView = hosting
        // Assigning the hosting view can reset window sizing; apply bounds afterwards.
        panel.minSize = NSSize(width: 280, height: 240)
        panel.setContentSize(NSSize(width: 360, height: 480))
        panel.center()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "투두 표시 또는 숨기기. 보조 클릭으로 메뉴 열기")
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func show() {
        clampToScreen()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.attachedSheet?.cancelOperation(nil)
        NSColorPanel.shared.orderOut(nil)
        panel.orderOut(nil)
    }
    func toggle() { panel.isVisible ? hide() : show() }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            let menu = NSMenu()
            for (title, action) in [("투두 보기", #selector(showFromMenu)), ("설정", #selector(settingsFromMenu)), ("종료", #selector(quit))] {
                let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
                item.target = self
            }
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else { toggle() }
    }

    @objc private func showFromMenu() { show() }
    @objc private func settingsFromMenu() { show(); openSettings?() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func screensChanged() { clampToScreen() }

    func restoreFrame(_ frame: NSRect) { panel.setFrame(frame, display: false); clampToScreen() }

    func clampToScreen() {
        let current = panel.frame
        guard let screen = NSScreen.screens.max(by: {
            intersectionArea(current, $0.visibleFrame) < intersectionArea(current, $1.visibleFrame)
        }) ?? NSScreen.main else { return }
        let bounds = screen.visibleFrame
        var frame = current
        frame.size.width = min(max(frame.width, panel.minSize.width), bounds.width)
        frame.size.height = min(max(frame.height, panel.minSize.height), bounds.height)
        frame.origin.x = min(max(frame.minX, bounds.minX), bounds.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, bounds.minY), bounds.maxY - frame.height)
        if frame != current { panel.setFrame(frame, display: true) }
    }

    private func intersectionArea(_ a: NSRect, _ b: NSRect) -> CGFloat {
        let intersection = a.intersection(b)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    func windowDidMove(_ notification: Notification) { frameChanged?(panel.frame) }
    func windowDidResize(_ notification: Notification) { frameChanged?(panel.frame) }
}
