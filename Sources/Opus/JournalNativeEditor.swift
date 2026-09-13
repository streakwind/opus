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
        let protected = JournalCode.blocks(in: markdown).map(\.range) + JournalCode.spans(in: markdown).map(\.range)
        var offset = 0
        for block in JournalMarkdown.blocks(from: markdown) {
            switch block {
            case .text(let text):
                result.append(NSAttributedString(string: text))
                offset += text.utf16.count
            case .embed(let link):
                let range = NSRange(location: offset, length: link.embedToken.utf16.count)
                offset += range.length
                if protected.contains(where: { NSIntersectionRange($0, range).length > 0 }) {
                    result.append(NSAttributedString(string: link.embedToken))
                    continue
                }
                let wrapper = FileWrapper(regularFileWithContents: Data(link.embedToken.utf8))
                wrapper.preferredFilename = "Opus-embed.txt"
                result.append(NSAttributedString(attachment: NSTextAttachment(fileWrapper: wrapper)))
            }
        }
        return result
    }
    static let sourceToken = NSAttributedString.Key("OpusMarkdownSource")
    static func markdown(_ text: NSAttributedString) -> String {
        var result = ""
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            if let token = attributes[sourceToken] as? String {
                result += (text.string as NSString).substring(with: range).replacingOccurrences(of: "\u{fffc}", with: token)
            } else if let link = link(in: attributes) {
                let substring = (text.string as NSString).substring(with: range)
                result += substring.replacingOccurrences(of: "\u{fffc}", with: link.embedToken)
            }
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
    var preview = false
    var active = true
    var live = false

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
        editor.setAccessibilityHelp("Write markdown and LaTeX. Wrap math in $inline$ or $$display$$. Type /task to embed work. Use arrow keys to move around embeds; double-click or Command-Return to edit one.")
        editor.onOpen = onOpen
        editor.onToggle = { [weak coordinator = context.coordinator] link in coordinator?.toggle(link) }
        editor.onWidthChange = { [weak coordinator = context.coordinator, weak editor] in
            guard let editor else { return }; coordinator?.refreshAttachments(editor)
        }
        scroll.documentView = editor
        context.coordinator.load(markdown, in: editor)
        return scroll
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        guard let editor = scroll.documentView as? JournalTextView else { return }
        if let session = coordinator.liveSession { editor.undoManager?.removeAllActions(withTarget: session) }
        editor.onReplace = nil
        editor.onCopy = nil
        editor.delegate = nil
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let editor = scroll.documentView as? JournalTextView else { return }
        editor.onOpen = onOpen
        editor.isEditable = !preview && active
        if !active, editor.window?.firstResponder === editor { editor.window?.makeFirstResponder(nil) }
        if (markdown != coordinator.source || coordinator.preview != preview), !editor.hasMarkedText() {
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
        if !preview, coordinator.lastFocus != focusRequest {
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
        var preview = false
        var lastFocus = 0
        var inserting = false
        var commandRange: NSRange?
        private var styling = false
        var liveSession: LiveMarkdownSession?
        init(_ parent: JournalNativeEditor) { self.parent = parent }
        func load(_ value: String, in editor: JournalTextView) {
            if parent.live {
                if liveSession == nil { liveSession = LiveMarkdownSession(coordinator: self) }
                liveSession?.load(value, in: editor)
                return
            }
            source = value
            preview = parent.preview
            editor.isEditable = !preview && parent.active
            let selection = editor.selectedRange()
            editor.textStorage?.setAttributedString(JournalRichText.attributed(value))
            editor.setSelectedRange(NSRange(location: min(selection.location, editor.string.utf16.count), length: 0))
            style(editor)
            if preview { renderPreview(editor) }
        }
        func textDidChange(_ notification: Notification) {
            guard liveSession == nil, !preview, !styling, let editor = notification.object as? JournalTextView, !editor.hasMarkedText(), let storage = editor.textStorage else { return }
            source = JournalRichText.markdown(storage)
            parent.markdown = source
            style(editor)
            let selection = editor.selectedRange()
            let range = NSRange(location: max(0, selection.location - 5), length: 5)
            if selection.length == 0, selection.location >= 5,
               (editor.string as NSString).substring(with: range) == "/task",
               !(JournalCode.blocks(in: editor.string).map(\.range) + JournalCode.spans(in: editor.string).map(\.range) + JournalMath.spans(in: editor.string).map(\.range)).contains(where: { NSIntersectionRange($0, range).length > 0 }) {
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
        func style(_ editor: JournalTextView) {
            guard !styling, let storage = editor.textStorage else { return }
            styling = true
            let full = NSRange(location: 0, length: storage.length)
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 4
            let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
            storage.beginEditing()
            // Keep attachment attributes and characters intact while restyling text.
            storage.removeAttribute(.backgroundColor, range: full)
            storage.removeAttribute(.underlineStyle, range: full)
            storage.removeAttribute(.strikethroughStyle, range: full)
            storage.removeAttribute(.link, range: full)
            storage.addAttributes(base, range: full)
            let text = storage.string
            func matches(_ pattern: String, apply: (NSTextCheckingResult) -> Void) {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
                for match in regex.matches(in: text, range: full) { apply(match) }
            }
            let codeBlocks = JournalCode.blocks(in: text)
            let inlineCode = JournalCode.spans(in: text)
            let mathRanges = JournalMath.spans(in: text)
            func insideCode(_ range: NSRange) -> Bool {
                (codeBlocks.map(\.range) + inlineCode.map(\.range) + mathRanges.map(\.range)).contains { NSIntersectionRange($0, range).length > 0 }
            }
            matches(#"(?m)^(#{1,6})\s+(.+)$"#) { match in
                guard !insideCode(match.range) else { return }
                let level = match.range(at: 1).length
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: level == 1 ? 26 : level == 2 ? 22 : 19, weight: .semibold), range: match.range)
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range(at: 1))
            }
            matches(#"\*\*([^\n]+?)\*\*"#) { match in
                guard !insideCode(match.range) else { return }
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 17, weight: .bold), range: match.range(at: 1))
            }
            matches(#"(?<!\*)\*([^*\n]+)\*(?!\*)"#) { match in
                guard !insideCode(match.range) else { return }
                storage.addAttribute(.font, value: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 17), toHaveTrait: .italicFontMask), range: match.range(at: 1))
            }
            matches(#"~~([^~\n]+)~~"#) { match in
                guard !insideCode(match.range) else { return }
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: match.range(at: 1))
            }
            matches(#"\[([^\]\n]+)\]\((https?://[^\)\n]+)\)"#) { match in
                guard !insideCode(match.range) else { return }
                let url = (text as NSString).substring(with: match.range(at: 2))
                storage.addAttribute(.link, value: url, range: match.range(at: 1))
            }
            let mono = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
            let blockFill = NSColor.labelColor.withAlphaComponent(0.055)
            for block in codeBlocks {
                storage.addAttribute(.font, value: mono, range: block.range)
                storage.addAttribute(.backgroundColor, value: blockFill, range: block.innerRange)
                storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: block.innerRange)
                let body = (text as NSString).substring(with: block.innerRange)
                for (range, kind) in CodeHighlight.tokens(in: body, language: block.language) {
                    let absolute = NSRange(location: block.innerRange.location + range.location, length: range.length)
                    guard NSMaxRange(absolute) <= storage.length else { continue }
                    storage.addAttribute(.foregroundColor, value: highlightColor(kind), range: absolute)
                }
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: block.openRange)
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: block.closeRange)
            }
            for span in JournalCode.spans(in: text) {
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 14.5, weight: .regular), range: span.range)
                storage.addAttribute(.backgroundColor, value: NSColor.labelColor.withAlphaComponent(0.07), range: span.innerRange)
            }
            for span in JournalMath.spans(in: text) {
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 16, weight: .regular), range: span.range)
                storage.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: span.range)
            }
            storage.endEditing()
            editor.typingAttributes = base
            styling = false
            refreshAttachments(editor)
            editor.needsDisplay = true
        }
        func renderPreview(_ editor: JournalTextView) {
            guard let storage = editor.textStorage else { return }
            let text = storage.string
            let blocks = JournalCode.blocks(in: text)
            let math = JournalMath.spans(in: text)
            var edits: [(NSRange, NSAttributedString)] = []
            func remove(_ range: NSRange) { edits.append((range, NSAttributedString(string: ""))) }
            for block in blocks { remove(block.openRange); remove(block.closeRange) }
            for span in math {
                guard let image = MathRenderer.image(latex: span.latex, display: span.display, color: .labelColor, fontSize: span.display ? 22 : 17) else { continue }
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = NSRect(origin: NSPoint(x: 0, y: -4), size: image.size)
                let rendered = NSMutableAttributedString(attachment: attachment)
                rendered.addAttribute(JournalRichText.sourceToken, value: (text as NSString).substring(with: span.range), range: NSRange(location: 0, length: rendered.length))
                edits.append((span.range, rendered))
            }
            // Parse prose with Foundation's Markdown parser, rather than removing
            // punctuation with regular expressions (which breaks nesting and escapes).
            let protected = (blocks.map(\.range) + math.map(\.range)).sorted { $0.location < $1.location }
            var start = 0
            for range in protected + [NSRange(location: storage.length, length: 0)] {
                if range.location > start {
                    let prose = NSRange(location: start, length: range.location - start)
                    edits.append((prose, MarkdownProse.render(storage.attributedSubstring(from: prose))))
                }
                start = max(start, NSMaxRange(range))
            }
            storage.beginEditing()
            var boundary = storage.length
            for (range, replacement) in edits.sorted(by: { $0.0.location > $1.0.location }) {
                guard NSMaxRange(range) <= boundary else { continue }
                storage.replaceCharacters(in: range, with: replacement)
                boundary = range.location
            }
            storage.endEditing()
            editor.setSelectedRange(NSRange(location: 0, length: 0))
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor = notification.object as? JournalTextView else { return }
            liveSession?.selectionChanged(in: editor)
        }
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let session = liveSession, let editor = textView as? JournalTextView else { return true }
            session.replace(affectedCharRange, with: JournalRichText.attributed(replacementString ?? ""), in: editor)
            return false
        }
        private func highlightColor(_ kind: CodeTokenKind) -> NSColor {
            switch kind {
            case .comment: .tertiaryLabelColor
            case .string: .systemOrange
            case .number: .systemBlue
            case .keyword: .systemPurple
            case .type: .systemTeal
            case .attribute: .systemPink
            }
        }
    }
}

/// Native attributed prose; Markdown remains untouched in the editable document.
@MainActor enum MarkdownProse {
    static func render(_ source: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        var attachments: [NSTextAttachment] = []
        source.enumerateAttribute(.attachment, in: NSRange(location: 0, length: source.length)) { value, range, _ in
            if let attachment = value as? NSTextAttachment {
                for _ in 0..<range.length { attachments.append(attachment) }
            }
        }
        var attachmentIndex = 0
        let lines = source.string.components(separatedBy: "\n")
        for (index, original) in lines.enumerated() {
            var line = original
            var size: CGFloat = 17
            var heading = false
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            if let match = line.range(of: #"^#{1,6}[ \t]+"#, options: .regularExpression) {
                let count = line[match].prefix(while: { $0 == "#" }).count
                size = count == 1 ? 26 : count == 2 ? 22 : 19
                heading = true
                line.removeSubrange(match)
            } else if line.hasPrefix("> ") {
                line.removeFirst(2)
                paragraph.firstLineHeadIndent = 16
                paragraph.headIndent = 16
            } else if let match = line.range(of: #"^([ \t]*)[-+*] "#, options: .regularExpression) {
                let indent = String(line[match].prefix(while: { $0 == " " || $0 == "\t" }))
                line.replaceSubrange(match, with: indent + "• ")
                if line.hasPrefix("• [ ] ") { line = "☐ " + line.dropFirst(6) }
                else if line.hasPrefix("• [x] ") || line.hasPrefix("• [X] ") { line = "☑ " + line.dropFirst(6) }
                paragraph.headIndent = 18
            }
            let parsed = (try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(line)
            for run in parsed.runs {
                var font = NSFont.systemFont(ofSize: size, weight: heading ? .semibold : .regular)
                let intent = run.inlinePresentationIntent ?? []
                if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
                if intent.contains(.code) {
                    attributes[.font] = NSFont.monospacedSystemFont(ofSize: 14.5, weight: .regular)
                    attributes[.backgroundColor] = NSColor.labelColor.withAlphaComponent(0.07)
                }
                if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                if let link = run.link { attributes[.link] = link }
                let rendered = NSMutableAttributedString(string: String(parsed[run.range].characters), attributes: attributes)
                let text = rendered.string as NSString
                for position in 0..<text.length where text.character(at: position) == 0xfffc {
                    if attachmentIndex < attachments.count {
                        rendered.addAttribute(.attachment, value: attachments[attachmentIndex], range: NSRange(location: position, length: 1))
                        attachmentIndex += 1
                    }
                }
                result.append(rendered)
            }
            if index < lines.count - 1 { result.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 17), .paragraphStyle: paragraph])) }
        }
        return result
    }
}

/// One text system provides caret movement, multiline selection, and native undo
/// across both prose and embeds. There are no nested editors or synthetic rows.
@MainActor final class JournalTextView: NSTextView {
    var onReplace: ((Any, NSRange) -> Void)?
    var onCopy: ((NSRange) -> String)?
    var onOpen: ((JournalLink) -> Void)?
    var onToggle: ((JournalLink) -> Void)?
    var onWidthChange: (() -> Void)?
    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize.width != frame.width
        super.setFrameSize(newSize)
        if changed { onWidthChange?() }
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if let onReplace {
            onReplace(insertString, replacementRange.location == NSNotFound ? selectedRange() : replacementRange)
        } else { super.insertText(insertString, replacementRange: replacementRange) }
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
    override func insertNewline(_ sender: Any?) {
        guard isEditable else { return }
        let selected = selectedRange()
        let ns = string as NSString
        let line = ns.lineRange(for: NSRange(location: selected.location, length: 0))
        let prefix = ns.substring(with: NSRange(location: line.location, length: selected.location - line.location))
        if JournalCode.blocks(in: string).contains(where: { NSLocationInRange(selected.location, $0.innerRange) || selected.location == NSMaxRange($0.innerRange) && $0.closeRange.length == 0 }) {
            let indent = String(prefix.prefix(while: { $0 == " " || $0 == "\t" }))
            insertText("\n" + indent, replacementRange: selected)
            return
        }
        let pattern = #"^([ \t]*)([-+*]|[0-9]+[.)]|>)([ \t]+)(\[[ xX]\] )?(.*)$"#
        if let match = try? NSRegularExpression(pattern: pattern).firstMatch(in: prefix, range: NSRange(location: 0, length: prefix.utf16.count)) {
            let text = prefix as NSString
            if text.substring(with: match.range(at: 5)).isEmpty {
                insertText("", replacementRange: NSRange(location: line.location, length: selected.location - line.location))
                return
            }
            var marker = text.substring(with: match.range(at: 2))
            if let number = Int(marker.dropLast()) { marker = "\(number + 1)" + marker.suffix(1) }
            let checkbox = match.range(at: 4).location == NSNotFound ? "" : "[ ] "
            insertText("\n" + text.substring(with: match.range(at: 1)) + marker + " " + checkbox, replacementRange: selected)
            return
        }
        super.insertNewline(sender)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isEditable, window?.firstResponder === self,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            if event.charactersIgnoringModifiers == "b" { wrapSelection("**"); return true }
            if event.charactersIgnoringModifiers == "i" { wrapSelection("*"); return true }
        }
        return super.performKeyEquivalent(with: event)
    }
    @objc func toggleBoldface(_ sender: Any?) { wrapSelection("**") }
    @objc func toggleItalics(_ sender: Any?) { wrapSelection("*") }
    private func wrapSelection(_ marker: String) {
        guard isEditable else { return }
        let selected = selectedRange()
        let content = (string as NSString).substring(with: selected)
        insertText(marker + content + marker, replacementRange: selected)
        setSelectedRange(NSRange(location: selected.location + marker.utf16.count, length: selected.length))
    }
    override func paste(_ sender: Any?) {
        if let text = NSPasteboard.general.string(forType: .string) {
            insertText(JournalRichText.attributed(text), replacementRange: selectedRange())
        } else { super.paste(sender) }
    }
    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if type == .string, let onCopy { return pboard.setString(onCopy(selectedRange()), forType: .string) }
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
            let click = convert(event.locationInWindow, from: nil)
            if click.x < rect.minX + 38,
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
        if isEditable {
            let remove = menu.addItem(withTitle: "Remove embed", action: #selector(removeSelectedEmbed), keyEquivalent: "")
            remove.target = self
        }
        return menu
    }
    @objc private func openSelectedEmbed() {
        guard let storage = textStorage, selectedRange().location < storage.length,
              let link = JournalRichText.link(in: storage.attributes(at: selectedRange().location, effectiveRange: nil)) else { return }
        onOpen?(link)
    }
    @objc private func removeSelectedEmbed() {
        guard isEditable else { return }
        insertText("", replacementRange: selectedRange())
    }
}

@MainActor struct JournalEmbedPresentation: Equatable {
    var title: String
    var detail: String
    var icon: String
    var checkable = false
    var completed = false
    init(placeholder: String) {
        title = placeholder; detail = ""; icon = "link"
    }
    init(link: JournalLink, store: Store, day: String) {
        let entry = store.journalTaskEmbeds(on: day).first { $0.link == link }
        title = entry?.title ?? "Unavailable item"
        detail = "The linked item was deleted"
        icon = "link"
        switch link {
        case .task(let id):
            guard let task = store.state.tasks.first(where: { $0.id == id }) else { return }
            title = task.title; checkable = task.kind != .progress; completed = task.completed
            icon = checkable ? (completed ? "checkmark.circle.fill" : "circle") : "book.closed"
            var parts = [store.course(task.courseID)?.name ?? "Inbox"]
            if let due = task.due { parts.append(Day.label(due)) }
            if task.kind == .progress {
                parts.append("\(task.pagesRead) of \(task.pagesTotal) \(task.unit)")
                parts.append("\(task.pagesTotal - task.pagesRead) left")
            }
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
    override func cellSize() -> NSSize {
        NSSize(width: width, height: 54)
    }
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -6) }
    override func draw(withFrame frame: NSRect, in controlView: NSView?) {
        let rect = frame.insetBy(dx: 0, dy: 2)
        let rule = NSBezierPath()
        rule.move(to: NSPoint(x: rect.minX + 1, y: rect.minY + 7))
        rule.line(to: NSPoint(x: rect.minX + 1, y: rect.maxY - 7))
        NSColor.controlAccentColor.withAlphaComponent(0.7).setStroke()
        rule.lineWidth = 2
        rule.lineCapStyle = .round
        rule.stroke()
        let flipped = controlView?.isFlipped ?? true
        func row(_ y: CGFloat, _ h: CGFloat, x: CGFloat = 40, width: CGFloat? = nil) -> NSRect {
            NSRect(x: rect.minX + x, y: flipped ? rect.minY + y : rect.maxY - y - h, width: width ?? max(1, rect.width - x - 12), height: h)
        }
        if let image = NSImage(systemSymbolName: presentation.icon, accessibilityDescription: nil) {
            let color: NSColor = presentation.completed ? .controlAccentColor : .secondaryLabelColor
            let symbol = image.withSymbolConfiguration(.init(paletteColors: [color])) ?? image
            symbol.draw(in: row(8, 19, x: 12, width: 19), from: .zero, operation: .sourceOver, fraction: presentation.completed ? 0.5 : 0.85, respectFlipped: true, hints: nil)
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        var titleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: presentation.completed ? NSColor.secondaryLabelColor : NSColor.labelColor, .paragraphStyle: paragraph]
        if presentation.completed { titleAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        (presentation.title as NSString).draw(in: row(5, 22), withAttributes: titleAttributes)
        let caption: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph]
        (presentation.detail as NSString).draw(in: row(28, 18), withAttributes: caption)
    }
}
