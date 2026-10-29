import AppKit

/// Opt-in checks inspect only this app's own objects and files.
@MainActor
enum RichTextChecks {
    static func run() -> [String: Bool] {
        let text = FormattingTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 160))
        text.isRichText = true
        text.textStorage?.setAttributedString(NSAttributedString(string: "한글 hello", attributes: [.font: NSFont.systemFont(ofSize: 13)]))
        text.setSelectedRange(NSRange(location: 3, length: 5))
        text.toggleTrait(.boldFontMask)
        text.toggleTrait(.italicFontMask)
        text.toggleUnderline()
        let font = text.textStorage?.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
        let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
        let rtf = text.rtf(from: NSRange(location: 0, length: text.string.utf16.count))
        let restored = rtf.flatMap { try? NSAttributedString(data: $0, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) }
        let restoredFont = restored?.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
        let restoredTraits = restoredFont.map { NSFontManager.shared.traits(of: $0) } ?? []
        let attachment = NSMutableAttributedString(string: "keep")
        attachment.append(NSAttributedString(attachment: NSTextAttachment()))
        let cleaned = FormattingTextView.textOnly(attachment)
        let legacy = NSAttributedString(string: "legacy note", attributes: [.foregroundColor: NSColor.black])
        let adaptive = FormattingTextView.textOnly(legacy).attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        return [
            "selectionBoldItalic": traits.contains([.boldFontMask, .italicFontMask]),
            "underline": text.textStorage?.attribute(.underlineStyle, at: 3, effectiveRange: nil) as? Int == 1,
            "rtfRoundTrip": restored?.string == text.string && restoredTraits.contains([.boldFontMask, .italicFontMask]) && restored?.attribute(.underlineStyle, at: 3, effectiveRange: nil) as? Int == 1,
            "attachmentsRemoved": cleaned.string == "keep",
            "adaptiveNoteColor": adaptive == .labelColor
        ]
    }
}

/// LaunchServices recovery test protocol. Does not activate/control other apps.
@MainActor
final class LaunchCheck {
    private let windows: WindowCoordinator
    private let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/ImportantTodo/launch-check.json")
    private var ready = false
    init(windows: WindowCoordinator) { self.windows = windows }

    func begin() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.windows.hide()
            self.ready = true
            self.write(["state": "hidden", "pid": ProcessInfo.processInfo.processIdentifier])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            self.write(["state": "timeout", "passed": false])
            exit(1)
        }
    }

    func reopened(wasHidden: Bool) {
        guard ready else { return }
        let passed = wasHidden && windows.panel.isVisible
        write([
            "state": "reopened", "passed": passed,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "wasHidden": wasHidden, "visible": windows.panel.isVisible,
            "ownTodoPanelCount": NSApp.windows.filter { $0 is TodoPanel }.count
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(passed ? 0 : 1) }
    }

    private func write(_ result: [String: Any]) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
        } catch { fputs("Launch check report failed: \(error)\n", stderr); exit(1) }
    }
}
