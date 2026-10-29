import AppKit
import SwiftUI

@MainActor
final class RichTextController: ObservableObject {
    weak var view: FormattingTextView?
    func bold() { view?.toggleTrait(.boldFontMask) }
    func italic() { view?.toggleTrait(.italicFontMask) }
    func underline() { view?.toggleUnderline() }
}

final class FormattingTextView: NSTextView {
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.rtf, .string] }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        let value: NSAttributedString?
        if type == .rtf, let data = pboard.data(forType: .rtf) {
            value = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        } else if let string = pboard.string(forType: .string) {
            value = NSAttributedString(string: string, attributes: typingAttributes)
        } else { value = nil }
        guard let value else { return false }
        let clean = Self.textOnly(value)
        insertText(clean, replacementRange: selectedRange())
        return true
    }

    static func textOnly(_ value: NSAttributedString) -> NSAttributedString {
        let clean = NSMutableAttributedString(attributedString: value)
        let all = NSRange(location: 0, length: clean.length)
        var attachmentRanges: [NSRange] = []
        clean.enumerateAttribute(.attachment, in: all) { attachment, range, _ in
            if attachment != nil { attachmentRanges.append(range) }
        }
        clean.removeAttribute(.link, range: all)
        // Notes support traits, not text colors. Keep existing/pasted RTF readable
        // in either appearance instead of retaining a serialized black/white color.
        clean.addAttribute(.foregroundColor, value: NSColor.labelColor, range: all)
        for range in attachmentRanges.reversed() { clean.deleteCharacters(in: range) }
        return clean
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .function]) == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "b": toggleTrait(.boldFontMask); return true
            case "i": toggleTrait(.italicFontMask); return true
            case "u": toggleUnderline(); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    func toggleTrait(_ trait: NSFontTraitMask) {
        let manager = NSFontManager.shared
        let selection = selectedRange()
        let font = (selection.length > 0 ? textStorage?.attribute(.font, at: selection.location, effectiveRange: nil) : typingAttributes[.font]) as? NSFont ?? .systemFont(ofSize: 13)
        let removing = manager.traits(of: font).contains(trait)
        if selection.length == 0 {
            typingAttributes[.font] = removing ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait)
            window?.makeFirstResponder(self)
            return
        }
        guard let storage = textStorage, shouldChangeText(in: selection, replacementString: nil) else { return }
        let original = NSAttributedString(attributedString: storage)
        storage.beginEditing()
        original.enumerateAttribute(.font, in: selection) { value, range, _ in
            let current = value as? NSFont ?? .systemFont(ofSize: 13)
            storage.addAttribute(.font, value: removing ? manager.convert(current, toNotHaveTrait: trait) : manager.convert(current, toHaveTrait: trait), range: range)
        }
        storage.endEditing()
        didChangeText()
        window?.makeFirstResponder(self)
    }

    func toggleUnderline() {
        let selection = selectedRange()
        let value = (selection.length > 0 ? textStorage?.attribute(.underlineStyle, at: selection.location, effectiveRange: nil) : typingAttributes[.underlineStyle]) as? Int ?? 0
        let next = value == 0 ? NSUnderlineStyle.single.rawValue : 0
        if selection.length == 0 { typingAttributes[.underlineStyle] = next }
        else if let storage = textStorage, shouldChangeText(in: selection, replacementString: nil) {
            storage.addAttribute(.underlineStyle, value: next, range: selection)
            didChangeText()
        }
        window?.makeFirstResponder(self)
    }
}

struct RichTextEditor: NSViewRepresentable {
    @Binding var data: Data?
    let controller: RichTextController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        let text = FormattingTextView(frame: .zero)
        text.isRichText = true
        text.drawsBackground = false
        text.textColor = .labelColor
        text.importsGraphics = false
        text.allowsImageEditing = false
        text.allowsUndo = true
        text.isAutomaticLinkDetectionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainerInset = NSSize(width: 10, height: 12)
        text.font = .systemFont(ofSize: 14)
        text.setAccessibilityLabel("상세 내용, 서식 있는 텍스트")
        text.delegate = context.coordinator
        scroll.documentView = text
        controller.view = text
        context.coordinator.install(data, into: text)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let text = scroll.documentView as? FormattingTextView else { return }
        controller.view = text
        if context.coordinator.lastData != data { context.coordinator.install(data, into: text) }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        var lastData: Data?
        init(_ parent: RichTextEditor) { self.parent = parent }
        func install(_ data: Data?, into text: NSTextView) {
            lastData = data
            if let data, let value = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
                text.textStorage?.setAttributedString(FormattingTextView.textOnly(value))
            } else { text.string = "" }
        }
        func textDidChange(_ notification: Notification) {
            guard let text = notification.object as? NSTextView else { return }
            let range = NSRange(location: 0, length: text.textStorage?.length ?? 0)
            let data = text.rtf(from: range)
            lastData = data
            parent.data = data
        }
    }
}
