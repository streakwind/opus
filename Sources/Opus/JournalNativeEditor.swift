import AppKit
import OpusCore
import SwiftUI

/// Markdown is the storage format; attachments are a one-character editing view
/// of its link tokens. Neither conversion invents paragraph separators.
@MainActor enum JournalRichText {
    static func link(in attributes: [NSAttributedString.Key: Any]) -> JournalLink? {
        guard let attachment = attributes[.attachment] as? NSTextAttachment,
              let data = attachment.fileWrapper?.regularFileContents,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return JournalLink.fromEmbedToken(token)
    }
    static func attributed(_ markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        for block in JournalMarkdown.blocks(from: markdown) {
            switch block {
            case .text(let text): result.append(NSAttributedString(string: text))
            case .embed(let link):
                let wrapper = FileWrapper(regularFileWithContents: Data(link.embedToken.utf8))
                wrapper.preferredFilename = "Opus-embed.txt"
                result.append(NSAttributedString(attachment: NSTextAttachment(fileWrapper: wrapper)))
            }
        }
        return result
    }
    static func markdown(_ text: NSAttributedString) -> String {
        var result = ""
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            if let link = link(in: attributes) { result += link.embedToken }
            else { result += (text.string as NSString).substring(with: range) }
        }
        return result
    }
}

struct JournalNativeEditor: NSViewRepresentable {
    @Binding var markdown: String
    var store: Store
    var day: String
    var focusRequest: Int
    @Binding var pendingEmbed: JournalEmbedOption?
    var onTaskCommand: (Int) -> Void
    var onOpen: (JournalLink) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let editor = JournalTextView(frame: scroll.bounds)
        editor.delegate = context.coordinator
        editor.isRichText = true
        editor.importsGraphics = false
        editor.allowsImageEditing = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.usesFindBar = true
        editor.isIncrementalSearchingEnabled = true
        editor.textContainerInset = NSSize(width: 28, height: 10)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize.height = .greatestFiniteMagnitude
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.autoresizingMask = [.width]
        editor.setAccessibilityIdentifier("journal-editor")
        editor.setAccessibilityLabel("Journal entry")
        editor.setAccessibilityHelp("Write anywhere. Type /task to embed work. Use arrow keys to move around embeds; double-click or Command-Return to edit one.")
        editor.onOpen = onOpen
        editor.onToggle = { [weak coordinator = context.coordinator] link in coordinator?.toggle(link) }
        editor.onWidthChange = { [weak coordinator = context.coordinator, weak editor] in
            guard let editor else { return }; coordinator?.refreshAttachments(editor)
        }
        scroll.documentView = editor
        context.coordinator.load(markdown, in: editor)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let editor = scroll.documentView as? JournalTextView else { return }
        editor.onOpen = onOpen
        if markdown != coordinator.source, !editor.hasMarkedText() {
            coordinator.load(markdown, in: editor)
            editor.undoManager?.removeAllActions()
        } else { coordinator.refreshAttachments(editor) }
        if let option = pendingEmbed, !coordinator.inserting {
            coordinator.inserting = true
            DispatchQueue.main.async { [weak editor, weak coordinator] in
                guard let editor, let coordinator else { return }
                defer { coordinator.inserting = false }
                let range = coordinator.commandRange ?? editor.selectedRange()
                coordinator.commandRange = nil
                editor.insertEmbed(option.link, replacing: range)
                coordinator.parent.pendingEmbed = nil
                editor.window?.makeFirstResponder(editor)
            }
        }
        if coordinator.lastFocus != focusRequest {
            coordinator.lastFocus = focusRequest
            DispatchQueue.main.async { [weak editor] in
                guard let editor else { return }
                editor.window?.makeFirstResponder(editor)
            }
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JournalNativeEditor
        var source = ""
        var lastFocus = 0
        var inserting = false
        var commandRange: NSRange?
        private var styling = false
        init(_ parent: JournalNativeEditor) { self.parent = parent }
        func load(_ value: String, in editor: JournalTextView) {
            source = value
            let selection = editor.selectedRange()
            editor.textStorage?.setAttributedString(JournalRichText.attributed(value))
            editor.setSelectedRange(NSRange(location: min(selection.location, editor.string.utf16.count), length: 0))
            style(editor)
        }
        func textDidChange(_ notification: Notification) {
            guard !styling, let editor = notification.object as? JournalTextView, !editor.hasMarkedText(), let storage = editor.textStorage else { return }
            source = JournalRichText.markdown(storage)
            parent.markdown = source
            style(editor)
            let selection = editor.selectedRange()
            let range = NSRange(location: max(0, selection.location - 5), length: 5)
            if selection.length == 0, selection.location >= 5,
               (editor.string as NSString).substring(with: range) == "/task" {
                guard commandRange != range else { return }
                commandRange = range
                DispatchQueue.main.async { self.parent.onTaskCommand(range.location) }
            } else { commandRange = nil }
        }
        func toggle(_ link: JournalLink) {
            guard case .task(let id) = link, var task = parent.store.state.tasks.first(where: { $0.id == id }), task.kind != .progress else { return }
            task.completed.toggle(); parent.store.save(task)
        }
        func refreshAttachments(_ editor: JournalTextView) {
            guard !styling, let storage = editor.textStorage else { return }
            let width = max(120, min(640, editor.bounds.width - 2 * editor.textContainerInset.width - 4))
            var changed = false
            storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, range, _ in
                guard let link = JournalRichText.link(in: attributes), let attachment = attributes[.attachment] as? NSTextAttachment else { return }
                let presentation = JournalEmbedPresentation(link: link, store: parent.store, day: parent.day)
                if let cell = attachment.attachmentCell as? JournalAttachmentCell, cell.presentation == presentation, cell.width == width { return }
                attachment.attachmentCell = JournalAttachmentCell(presentation: presentation, width: width)
                editor.layoutManager?.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                changed = true
            }
            if changed { editor.needsDisplay = true }
        }
        private func style(_ editor: JournalTextView) {
            guard !styling, let storage = editor.textStorage else { return }
            styling = true
            let full = NSRange(location: 0, length: storage.length)
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 4
            let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
            storage.beginEditing()
            // Keep attachment attributes and characters intact while restyling text.
            storage.removeAttribute(.backgroundColor, range: full)
            storage.removeAttribute(.underlineStyle, range: full)
            storage.removeAttribute(.link, range: full)
            storage.addAttributes(base, range: full)
            let text = storage.string
            func matches(_ pattern: String, apply: (NSTextCheckingResult) -> Void) {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
                for match in regex.matches(in: text, range: full) { apply(match) }
            }
            matches(#"(?m)^(#{1,3})\s+(.+)$"#) { match in
                let level = match.range(at: 1).length
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: level == 1 ? 26 : level == 2 ? 22 : 19, weight: .semibold), range: match.range)
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range(at: 1))
            }
            matches(#"\*\*([^\n]+?)\*\*"#) { match in
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 17, weight: .bold), range: match.range(at: 1))
            }
            matches(#"`([^`\n]+)`"#) { match in
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 16, weight: .regular), range: match.range(at: 1))
                storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: match.range(at: 1))
            }
            matches(#"\[([^\]\n]+)\]\((https?://[^\)\n]+)\)"#) { match in
                let url = (text as NSString).substring(with: match.range(at: 2))
                storage.addAttribute(.link, value: url, range: match.range(at: 1))
            }
            storage.endEditing()
            editor.typingAttributes = base
            styling = false
            refreshAttachments(editor)
        }
    }
}

/// One text system provides caret movement, multiline selection, and native undo
/// across both prose and embeds. There are no nested editors or synthetic rows.
@MainActor final class JournalTextView: NSTextView {
    var onOpen: ((JournalLink) -> Void)?
    var onToggle: ((JournalLink) -> Void)?
    var onWidthChange: (() -> Void)?
    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize.width != frame.width
        super.setFrameSize(newSize)
        if changed { onWidthChange?() }
    }
    func insertEmbed(_ link: JournalLink, replacing proposed: NSRange) {
        let location = min(proposed.location, string.utf16.count)
        let range = NSRange(location: location, length: min(proposed.length, string.utf16.count - location))
        let text = string as NSString
        let before = text.substring(to: range.location)
        let after = text.substring(from: NSMaxRange(range))
        let prefix = before.isEmpty || before.hasSuffix("\n") ? "" : "\n"
        // An insertion creates a place to continue typing even at end of document.
        let suffix = after.hasPrefix("\n") ? "" : "\n"
        let insertion = JournalRichText.attributed(prefix + link.embedToken + suffix)
        insertText(insertion, replacementRange: range)
        if after.hasPrefix("\n") { setSelectedRange(NSRange(location: selectedRange().location + 1, length: 0)) }
        scrollRangeToVisible(selectedRange())
    }
    override func paste(_ sender: Any?) {
        if let text = NSPasteboard.general.string(forType: .string) {
            insertText(JournalRichText.attributed(text), replacementRange: selectedRange())
        } else { super.paste(sender) }
    }
    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if type == .string, let storage = textStorage {
            return pboard.setString(JournalRichText.markdown(storage.attributedSubstring(from: selectedRange())), forType: .string)
        }
        return super.writeSelection(to: pboard, type: type)
    }
    private func hit(_ event: NSEvent) -> (JournalLink, Int, NSRect)? {
        guard let container = textContainer, let manager = layoutManager, let storage = textStorage, storage.length > 0 else { return nil }
        let location = convert(event.locationInWindow, from: nil)
        let point = NSPoint(x: location.x - textContainerOrigin.x, y: location.y - textContainerOrigin.y)
        let glyph = manager.glyphIndex(for: point, in: container)
        guard glyph < manager.numberOfGlyphs else { return nil }
        let index = manager.characterIndexForGlyph(at: glyph)
        let rect = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        guard rect.contains(point), let link = JournalRichText.link(in: storage.attributes(at: index, effectiveRange: nil)) else { return nil }
        return (link, index, rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y))
    }
    override func mouseDown(with event: NSEvent) {
        if let (link, index, rect) = hit(event) {
            if event.clickCount == 2 { onOpen?(link); return }
            let point = convert(event.locationInWindow, from: nil)
            if point.x < rect.minX + 38,
               let attachment = textStorage?.attribute(.attachment, at: index, effectiveRange: nil) as? NSTextAttachment,
               (attachment.attachmentCell as? JournalAttachmentCell)?.presentation.checkable == true {
                onToggle?(link); return
            }
        }
        super.mouseDown(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, event.modifierFlags.contains(.command), selectedRange().length == 1,
           let storage = textStorage, selectedRange().location < storage.length,
           let link = JournalRichText.link(in: storage.attributes(at: selectedRange().location, effectiveRange: nil)) {
            onOpen?(link); return
        }
        super.keyDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let (_, index, _) = hit(event) else { return super.menu(for: event) }
        setSelectedRange(NSRange(location: index, length: 1))
        let menu = NSMenu()
        let open = menu.addItem(withTitle: "Open linked item", action: #selector(openSelectedEmbed), keyEquivalent: "")
        open.target = self
        let remove = menu.addItem(withTitle: "Remove embed from this day", action: #selector(removeSelectedEmbed), keyEquivalent: "")
        remove.target = self
        return menu
    }
    @objc private func openSelectedEmbed() {
        guard let storage = textStorage, selectedRange().location < storage.length,
              let link = JournalRichText.link(in: storage.attributes(at: selectedRange().location, effectiveRange: nil)) else { return }
        onOpen?(link)
    }
    @objc private func removeSelectedEmbed() { insertText("", replacementRange: selectedRange()) }
}

@MainActor struct JournalEmbedPresentation: Equatable {
    var title: String
    var detail: String
    var comment: String
    var icon: String
    var checkable = false
    var completed = false
    init(placeholder: String) {
        title = placeholder; detail = ""; comment = ""; icon = "link"
    }
    init(link: JournalLink, store: Store, day: String) {
        let entry = store.journalTaskEmbeds(on: day).first { $0.link == link }
        title = entry?.title ?? "Unavailable item"
        detail = "The linked item was deleted"
        comment = entry?.markdown ?? ""
        icon = "link"
        switch link {
        case .task(let id):
            guard let task = store.state.tasks.first(where: { $0.id == id }) else { return }
            title = task.title; checkable = task.kind != .progress; completed = task.completed
            icon = checkable ? (completed ? "checkmark.circle.fill" : "circle") : "book.closed"
            var parts = [store.course(task.courseID)?.name ?? "Inbox"]
            if let due = task.due { parts.append(Day.label(due)) }
            if task.kind == .progress { parts.append("Page \(task.current) of \(task.target)") }
            detail = parts.joined(separator: " · ")
        case .assessment(let id):
            guard let item = store.state.assessments.first(where: { $0.id == id }) else { return }
            title = item.title; icon = "calendar"
            detail = [store.course(item.courseID)?.name ?? "Inbox", Day.label(item.day)].joined(separator: " · ")
        case .rhythm(let id):
            guard let rule = store.rule(id) else { return }
            title = rule.title; icon = "arrow.triangle.2.circlepath"; detail = rule.repeatsLabel
        case .schedule(let id):
            guard let item = store.state.schedule.first(where: { $0.id == id }) else { return }
            title = item.title; icon = "clock"; detail = item.timeLabel
        }
    }
}

@MainActor final class JournalAttachmentCell: NSTextAttachmentCell {
    let presentation: JournalEmbedPresentation
    let width: CGFloat
    init(presentation: JournalEmbedPresentation, width: CGFloat) {
        self.presentation = presentation; self.width = width
        super.init(textCell: presentation.title)
    }
    required init(coder: NSCoder) {
        presentation = JournalEmbedPresentation(placeholder: "Linked item")
        width = 320
        super.init(textCell: "Linked item")
    }
    override func cellSize() -> NSSize { NSSize(width: width, height: presentation.comment.isEmpty ? 58 : 80) }
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -8) }
    override func draw(withFrame frame: NSRect, in controlView: NSView?) {
        let rect = frame.insetBy(dx: 0, dy: 3)
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        let flipped = controlView?.isFlipped ?? true
        func row(_ y: CGFloat, _ h: CGFloat, x: CGFloat = 38, width: CGFloat? = nil) -> NSRect {
            NSRect(x: rect.minX + x, y: flipped ? rect.minY + y : rect.maxY - y - h, width: width ?? max(1, rect.width - x - 12), height: h)
        }
        if let image = NSImage(systemSymbolName: presentation.icon, accessibilityDescription: nil) {
            image.draw(in: row(9, 19, x: 10, width: 19), from: .zero, operation: .sourceOver, fraction: presentation.completed ? 0.5 : 0.85, respectFlipped: true, hints: nil)
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        var titleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: presentation.completed ? NSColor.secondaryLabelColor : NSColor.labelColor, .paragraphStyle: paragraph]
        if presentation.completed { titleAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        (presentation.title as NSString).draw(in: row(6, 22), withAttributes: titleAttributes)
        let caption: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph]
        (presentation.detail as NSString).draw(in: row(29, 18), withAttributes: caption)
        if !presentation.comment.isEmpty {
            (presentation.comment.replacingOccurrences(of: "\n", with: " ") as NSString).draw(in: row(51, 18), withAttributes: caption)
        }
    }
}
