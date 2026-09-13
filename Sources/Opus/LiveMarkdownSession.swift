import AppKit
import OpusCore

/// The stored document is independent of its presentation. Only the active
/// paragraph exposes syntax; selections and edits are translated back to source.
@MainActor final class LiveMarkdownSession {
    unowned let coordinator: JournalNativeEditor.Coordinator
    private(set) var document = NSAttributedString(string: "")
    private(set) var sourceSelection = NSRange(location: 0, length: 0)
    private var mapping = MarkdownOffsetMap(source: "", display: "")
    private var rebuilding = false
    private var activeRanges: [NSRange] = []
    private var previewCache: [String: NSAttributedString] = [:]

    init(coordinator: JournalNativeEditor.Coordinator) { self.coordinator = coordinator }

    func load(_ markdown: String, in editor: JournalTextView) {
        previewCache.removeAll()
        document = JournalRichText.attributed(markdown)
        coordinator.source = markdown
        sourceSelection = NSRange(location: min(sourceSelection.location, document.length), length: 0)
        editor.onReplace = { [weak self, weak editor] value, range in
            guard let self, let editor else { return }
            let replacement: NSAttributedString
            if let value = value as? NSAttributedString { replacement = value }
            else { replacement = JournalRichText.attributed(String(describing: value)) }
            self.replace(range, with: replacement, in: editor)
        }
        editor.onCopy = { [weak self] range in
            guard let self else { return "" }
            return JournalRichText.markdown(self.document.attributedSubstring(from: self.mapping.sourceRange(range)))
        }
        editor.onCheckbox = { [weak self, weak editor] index in
            guard let self, let editor else { return }
            self.toggleCheckbox(at: index, in: editor)
        }
        editor.onNewline = { [weak self, weak editor] in
            guard let self, let editor else { return }
            self.insertNewline(in: editor)
        }
        rebuild(in: editor)
    }

    private func replaceSource(_ range: NSRange, with replacement: String, caret: NSRange? = nil, in editor: JournalTextView) {
        let next = NSMutableAttributedString(attributedString: document)
        next.replaceCharacters(in: range, with: JournalRichText.attributed(replacement))
        var selection = caret ?? NSRange(location: range.location + (replacement as NSString).length, length: 0)
        if caret == nil, let inside = caretInsideFreshlyClosedFence(in: next.string, after: selection) {
            selection = inside
        }
        apply(next, selection: selection, in: editor, undo: true)
    }

    func insertNewline(in editor: JournalTextView) {
        guard !rebuilding, editor.isEditable else { return }
        let text = document.string as NSString
        let caret = min(sourceSelection.length == 0 ? sourceSelection.location : NSMaxRange(sourceSelection), text.length)
        if text.length == 0 {
            replaceSource(NSRange(location: 0, length: 0), with: "\n", in: editor)
            return
        }
        let line = text.lineRange(for: NSRange(location: min(caret, text.length - 1), length: 0))
        let prefix = text.substring(with: NSRange(location: line.location, length: max(0, caret - line.location)))
        if let opening = try? NSRegularExpression(pattern: #"^([ ]{0,3})(`{3,}|~{3,})[^\n]*$"#).firstMatch(
            in: prefix,
            range: NSRange(location: 0, length: prefix.utf16.count)
        ), JournalCode.blocks(in: document.string).contains(where: {
            $0.closeRange.length == 0 && $0.openRange.location == line.location
        }) {
            let ns = prefix as NSString
            replaceSource(
                NSRange(location: caret, length: 0),
                with: "\n\n" + ns.substring(with: opening.range(at: 1)) + ns.substring(with: opening.range(at: 2)) + "\n",
                caret: NSRange(location: caret + 1, length: 0),
                in: editor
            )
            return
        }
        if let block = JournalCode.blocks(in: document.string).first(where: {
            $0.closeRange.length > 0 && caret >= $0.closeRange.location && caret < NSMaxRange($0.range)
        }) {
            let after = NSMaxRange(block.range)
            if after == text.length, text.length > 0, text.character(at: after - 1) != 10 {
                replaceSource(NSRange(location: after, length: 0), with: "\n", in: editor)
            } else {
                apply(document, selection: NSRange(location: after, length: 0), in: editor, undo: false)
            }
            return
        }
        if let block = JournalCode.blocks(in: document.string).first(where: {
            caret >= NSMaxRange($0.openRange) && ($0.closeRange.length == 0 || caret < $0.closeRange.location)
        }) {
            if NSLocationInRange(caret, block.openRange) {
                replaceSource(NSRange(location: caret, length: 0), with: "\n", in: editor)
                return
            }
            let indent = String(prefix.prefix(while: { $0 == " " || $0 == "\t" }))
            replaceSource(NSRange(location: bodyInsertion(caret, in: document.string), length: 0), with: "\n" + indent, in: editor)
            return
        }
        let list = #"^([ \t]*)([-+*]|[0-9]+[.)]|>)([ \t]+)(\[[ xX]?\][ \t]*)?(.*)$"#
        if let match = try? NSRegularExpression(pattern: list).firstMatch(
            in: prefix,
            range: NSRange(location: 0, length: prefix.utf16.count)
        ) {
            let ns = prefix as NSString
            if ns.substring(with: match.range(at: 5)).isEmpty {
                replaceSource(NSRange(location: line.location, length: caret - line.location), with: "", in: editor)
                return
            }
            var marker = ns.substring(with: match.range(at: 2))
            if let number = Int(marker.dropLast()) { marker = "\(number + 1)" + marker.suffix(1) }
            let checkbox = match.range(at: 4).location == NSNotFound ? "" : "[ ] "
            replaceSource(
                NSRange(location: caret, length: 0),
                with: "\n" + ns.substring(with: match.range(at: 1)) + marker + " " + checkbox,
                in: editor
            )
            return
        }
        replaceSource(NSRange(location: caret, length: 0), with: "\n", in: editor)
    }

    func replace(_ displayRange: NSRange, with replacement: NSAttributedString, in editor: JournalTextView) {
        guard !rebuilding, editor.isEditable else { return }
        var range = mapping.sourceRange(displayRange)
        range.location = bodyInsertion(range.location, in: document.string)
        let insertion = NSMutableAttributedString(attributedString: replacement)
        if let prefix = newlineAfterClosedFence(at: range, inserting: replacement.string) {
            insertion.insert(JournalRichText.attributed(prefix), at: 0)
        }
        let next = NSMutableAttributedString(attributedString: document)
        next.replaceCharacters(in: range, with: insertion)
        var selection = NSRange(location: range.location + insertion.length, length: 0)
        if let inside = caretInsideFreshlyClosedFence(in: next.string, after: selection) {
            selection = inside
        }
        apply(next, selection: selection, in: editor, undo: true)
        let caret = sourceSelection.location
        if caret >= 5, (document.string as NSString).substring(with: NSRange(location: caret - 5, length: 5)) == "/task",
           !JournalCode.blocks(in: document.string).contains(where: { NSLocationInRange(caret - 1, $0.range) }),
           !JournalCode.spans(in: document.string).contains(where: { NSLocationInRange(caret - 1, $0.range) }) {
            coordinator.commandRange = mapping.displayRange(NSRange(location: caret - 5, length: 5))
            coordinator.parent.onTaskCommand(caret - 5)
        } else { coordinator.commandRange = nil }
    }

    private func apply(_ next: NSAttributedString, selection: NSRange, in editor: JournalTextView, undo: Bool) {
        if undo {
            let previous = document
            let previousSelection = sourceSelection
            editor.undoManager?.registerUndo(withTarget: self) { [weak editor] session in
                guard let editor else { return }
                session.apply(previous, selection: previousSelection, in: editor, undo: true)
            }
            editor.undoManager?.setActionName("Edit Markdown")
        }
        document = next
        sourceSelection = selection
        coordinator.source = JournalRichText.markdown(document)
        coordinator.parent.markdown = coordinator.source
        rebuild(in: editor)
        editor.scrollRangeToVisible(editor.selectedRange())
    }

    func selectionChanged(in editor: JournalTextView) {
        guard !rebuilding else { return }
        sourceSelection = mapping.sourceRange(editor.selectedRange())
        let ranges = editingRanges()
        guard ranges != activeRanges else { return }
        rebuild(in: editor)
    }

    func toggleCheckbox(at displayIndex: Int, in editor: JournalTextView) {
        guard displayIndex >= 0, displayIndex < editor.string.utf16.count else { return }
        let sourceIndex = mapping.sourceRange(NSRange(location: displayIndex, length: 1)).location
        let text = document.string as NSString
        guard text.length > 0 else { return }
        let line = text.lineRange(for: NSRange(location: min(sourceIndex, text.length - 1), length: 0))
        let value = text.substring(with: line)
        guard let regex = try? NSRegularExpression(pattern: #"\[[ xX]?\]"#),
              let box = regex.firstMatch(in: value, range: NSRange(location: 0, length: (value as NSString).length)) else { return }
        let current = (value as NSString).substring(with: box.range)
        let next = current.lowercased().contains("x") ? "[ ]" : "[x]"
        let range = NSRange(location: line.location + box.range.location, length: box.range.length)
        let updated = NSMutableAttributedString(attributedString: document)
        updated.replaceCharacters(in: range, with: next)
        apply(updated, selection: sourceSelection, in: editor, undo: true)
    }

    func appearanceChanged(in editor: JournalTextView) {
        previewCache.removeAll()
        rebuild(in: editor)
    }

    private func blocks() -> [NSRange] {
        let text = document.string as NSString
        let groups = (JournalCode.blocks(in: document.string).map(\.range)
            + JournalMath.spans(in: document.string).filter(\.display).map(\.range))
        var result: [NSRange] = []
        var index = 0
        while index < text.length {
            var range = text.lineRange(for: NSRange(location: index, length: 0))
            for group in groups where NSIntersectionRange(group, range).length > 0 {
                range = text.lineRange(for: NSUnionRange(range, group))
            }
            result.append(range)
            index = NSMaxRange(range)
        }
        return result
    }

    /// Preview maps the end of a fenced body onto the closing ```. Inserting there
    /// would become `h``` `; step back onto the body's trailing newline instead.
    private func bodyInsertion(_ location: Int, in text: String) -> Int {
        guard let block = JournalCode.blocks(in: text).first(where: {
            $0.closeRange.length > 0 && location == $0.closeRange.location
        }), block.innerRange.length > 0,
              (text as NSString).character(at: location - 1) == 10 else { return location }
        return location - 1
    }

    private func newlineAfterClosedFence(at range: NSRange, inserting replacement: String) -> String? {
        guard range.length == 0, range.location == document.length, document.length > 0,
              (document.string as NSString).character(at: document.length - 1) != 10,
              !replacement.hasPrefix("\n"),
              JournalCode.blocks(in: document.string).contains(where: {
                  $0.closeRange.length > 0 && NSMaxRange($0.range) == document.length
              }) else { return nil }
        return "\n"
    }

    private func caretInsideFreshlyClosedFence(in text: String, after selection: NSRange) -> NSRange? {
        guard selection.length == 0,
              let block = JournalCode.blocks(in: text).first(where: {
                  $0.closeRange.length > 0 && selection.location == NSMaxRange($0.range)
              }) else { return nil }
        let inner = (text as NSString).substring(with: block.innerRange)
        guard inner.unicodeScalars.allSatisfy({ $0 == "\n" || $0 == "\r" || $0 == " " || $0 == "\t" }) else { return nil }
        let openEnd = NSMaxRange(block.openRange)
        let ns = text as NSString
        if openEnd > 0, ns.character(at: openEnd - 1) == 10 {
            return NSRange(location: openEnd, length: 0)
        }
        if openEnd < ns.length, ns.character(at: openEnd) == 10 {
            return NSRange(location: openEnd + 1, length: 0)
        }
        return NSRange(location: openEnd, length: 0)
    }

    private func editingRanges() -> [NSRange] {
        guard let line = blocks().first(where: caretTouches) else { return [] }
        if JournalCode.blocks(in: document.string).contains(where: { NSIntersectionRange($0.range, line).length > 0 }) {
            return [line]
        }
        if JournalMath.spans(in: document.string).contains(where: { $0.display && NSIntersectionRange($0.range, line).length > 0 }) {
            return [line]
        }
        let value = (document.string as NSString).substring(with: line)
        if value.range(of: #"^(?: {0,3}#{1,6}[ \t]+|[ \t]*>[ \t]+)"#, options: .regularExpression) != nil {
            return [line]
        }
        if value.range(of: #"^[ \t]*(?:[-+*]|\d+[.)])[ \t]*(?:\[[ xX]?)?$"#, options: .regularExpression) != nil {
            return [line]
        }
        let active = inlineConstructs(in: line).filter(selectionTouches)
        guard !active.isEmpty else { return [] }
        let start = active.map(\.location).min() ?? 0
        let end = active.map(NSMaxRange).max() ?? start
        return [NSRange(location: start, length: end - start)]
    }

    private func caretTouches(_ range: NSRange) -> Bool {
        if sourceSelection.length > 0 { return NSIntersectionRange(sourceSelection, range).length > 0 }
        let caret = sourceSelection.location
        if let block = JournalCode.blocks(in: document.string).first(where: {
            $0.closeRange.length > 0 && NSIntersectionRange($0.range, range).length > 0
        }), caret >= NSMaxRange(block.range) {
            return false
        }
        if caret == document.length, document.length > 0,
           (document.string as NSString).character(at: document.length - 1) == 10,
           NSMaxRange(range) == document.length {
            return false
        }
        return NSLocationInRange(caret, range)
            || (caret == document.length && NSMaxRange(range) == document.length)
    }

    private func selectionTouches(_ range: NSRange) -> Bool {
        if sourceSelection.length > 0 {
            return NSIntersectionRange(sourceSelection, range).length > 0
        }
        return sourceSelection.location >= range.location && sourceSelection.location <= NSMaxRange(range)
    }

    private func inlineConstructs(in line: NSRange) -> [NSRange] {
        var ranges = JournalCode.spans(in: document.string).map(\.range)
            + JournalMath.spans(in: document.string).filter { !$0.display }.map(\.range)
        if let marker = listMarkerRange(in: line) { ranges.append(marker) }
        let patterns = [
            #"\*\*[^*\n]+?\*\*"#,
            #"__[^_\n]+?__"#,
            #"~~[^~\n]+?~~"#,
            #"(?<!\*)\*[^*\n]+?\*(?!\*)"#,
            #"(?<!_)_[^_\n]+?_(?!_)"#,
            #"!?\[[^\]\n]+\]\([^\)\n]+\)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            ranges += regex.matches(in: document.string, range: line).map(\.range)
        }
        return ranges.filter { NSIntersectionRange($0, line).length == $0.length }
            .sorted { $0.location == $1.location ? $0.length > $1.length : $0.location < $1.location }
    }

    private func listMarkerRange(in line: NSRange) -> NSRange? {
        let value = (document.string as NSString).substring(with: line)
        guard let match = try? NSRegularExpression(
            pattern: #"^([ \t]*(?:[-+*]|\d+[.)])[ \t]+(?:\[[ xX]?\][ \t]*)?)"#
        ).firstMatch(in: value, range: NSRange(location: 0, length: (value as NSString).length)) else { return nil }
        let marker = (value as NSString).substring(with: match.range(at: 1))
        if marker.contains("[") && !marker.contains("]") { return nil }
        return NSRange(location: line.location + match.range(at: 1).location, length: match.range(at: 1).length)
    }

    private func mixedPreview(
        source part: NSAttributedString,
        sourceRange: NSRange,
        rendered preview: NSAttributedString
    ) -> NSAttributedString {
        let localRanges = activeRanges.compactMap { range -> NSRange? in
            let overlap = NSIntersectionRange(range, sourceRange)
            guard overlap.length > 0 else { return nil }
            return NSRange(location: overlap.location - sourceRange.location, length: overlap.length)
        }
        guard !localRanges.isEmpty else { return preview }
        let map = MarkdownOffsetMap(source: part.string, display: preview.string)
        let result = NSMutableAttributedString(attributedString: preview)
        for range in localRanges.sorted(by: { $0.location > $1.location }) {
            result.replaceCharacters(in: map.displayRange(range), with: part.attributedSubstring(from: range))
        }
        return result
    }

    private func rebuild(in editor: JournalTextView) {
        guard !rebuilding else { return }
        rebuilding = true
        defer { rebuilding = false }
        // Presentation changes must never enter native undo or mutate Markdown.
        editor.undoManager?.disableUndoRegistration()
        defer { editor.undoManager?.enableUndoRegistration() }
        editor.textStorage?.setAttributedString(document)
        coordinator.style(editor)
        let styled = editor.attributedString()
        let rendered = NSMutableAttributedString(string: "")
        activeRanges = editingRanges()
        var parts: [(String, String)] = []
        for range in blocks() {
            let part = styled.attributedSubstring(from: range)
            let appearance = editor.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])?.rawValue ?? ""
            let cacheKey = appearance + "\u{0}" + JournalRichText.markdown(part)
            let visible: NSAttributedString
            if activeRanges.contains(range) {
                let editing = NSMutableAttributedString(attributedString: part)
                if editing.attribute(JournalRichText.codeBlock, at: 0, effectiveRange: nil) != nil {
                    editing.addAttribute(JournalRichText.codeBlock, value: "", range: NSRange(location: 0, length: editing.length))
                }
                visible = editing
            }
            else {
                let preview: NSAttributedString
                if let cached = previewCache[cacheKey] {
                    preview = cached
                } else {
                    let scratch = JournalTextView(frame: editor.bounds)
                    scratch.appearance = editor.effectiveAppearance
                    scratch.textStorage?.setAttributedString(part)
                    coordinator.renderPreview(scratch)
                    preview = scratch.attributedString()
                    if previewCache.count > 300 { previewCache.removeAll() }
                    previewCache[cacheKey] = preview
                }
                let isCode = part.length > 0 && part.attribute(JournalRichText.codeBlock, at: 0, effectiveRange: nil) != nil
                let sourceHasMarkup = !part.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let previewIsEmpty = preview.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                visible = sourceHasMarkup && previewIsEmpty && !isCode
                    ? part
                    : mixedPreview(source: part, sourceRange: range, rendered: preview)
            }
            rendered.append(visible)
            parts.append((part.string, visible.string))
        }
        mapping = MarkdownOffsetMap(parts: parts)
        editor.textStorage?.setAttributedString(rendered)
        coordinator.refreshAttachments(editor)
        editor.setSelectedRange(mapping.displayRange(sourceSelection))
    }
}

/// UTF-16 boundary maps preserve native text-system coordinates across hidden
/// syntax, rendered equations, emoji, and ordinary attachment characters.
struct MarkdownOffsetMap {
    private var toSource: [Int]
    private var toDisplay: [Int]
    init(parts: [(String, String)]) {
        toSource = [0]; toDisplay = [0]
        var sourceOffset = 0, displayOffset = 0
        for (source, display) in parts {
            let part = MarkdownOffsetMap(source: source, display: display)
            toSource.removeLast(); toDisplay.removeLast()
            toSource += part.toSource.map { $0 + sourceOffset }
            toDisplay += part.toDisplay.map { $0 + displayOffset }
            sourceOffset += source.utf16.count
            displayOffset += display.utf16.count
        }
    }
    init(source: String, display: String) {
        if let mapped = MarkdownOffsetMap.codeFenceMap(source: source, display: display)
            ?? MarkdownOffsetMap.listMarkerMap(source: source, display: display) {
            self = mapped
            return
        }
        let original = Array(source.utf16), visible = Array(display.utf16)
        var deleted = Set<Int>(), inserted = Set<Int>()
        for change in visible.difference(from: original) {
            switch change {
            case .remove(let offset, _, _): deleted.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        toSource = Array(repeating: 0, count: visible.count + 1)
        toDisplay = Array(repeating: 0, count: original.count + 1)
        var s = 0, d = 0
        while s < original.count || d < visible.count {
            if s < original.count, deleted.contains(s) {
                toDisplay[s] = d; s += 1
            } else if d < visible.count, inserted.contains(d) {
                toSource[d] = s; d += 1
            } else {
                toSource[d] = s; toDisplay[s] = d
                s += 1; d += 1
            }
        }
        toSource[visible.count] = original.count
        toDisplay[original.count] = visible.count
    }
    private init(toSource: [Int], toDisplay: [Int]) {
        self.toSource = toSource
        self.toDisplay = toDisplay
    }
    private static func listMarker(_ line: String) -> (marker: String, body: String)? {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        let patterns = [
            #"^([ \t]*(?:[-+*]|\d+[.)])[ \t]+(?:\[[ xX]?\][ \t]*)?)"#,
            #"^([ \t]*[☐☑•][ \t]*)"#
        ]
        for pattern in patterns {
            guard let match = try? NSRegularExpression(pattern: pattern).firstMatch(in: line, range: full) else { continue }
            let marker = ns.substring(with: match.range(at: 1))
            return (marker, ns.substring(from: marker.utf16.count))
        }
        return nil
    }
    private static func listMarkerMap(source: String, display: String) -> MarkdownOffsetMap? {
        guard let from = listMarker(source), let to = listMarker(display),
              from.body == to.body, from.marker != to.marker else { return nil }
        let prefix = from.marker.utf16.count
        let shown = to.marker.utf16.count
        let body = from.body.utf16.count
        var toSource: [Int] = (0..<shown).map { prefix * $0 / max(shown, 1) }
        toSource.append(prefix)
        toSource += (0..<body).map { prefix + $0 + 1 }
        var toDisplay: [Int] = (0..<prefix).map { shown * $0 / max(prefix, 1) }
        toDisplay += (0...body).map { shown + $0 }
        return MarkdownOffsetMap(toSource: toSource, toDisplay: toDisplay)
    }
    private static func codeFenceMap(source: String, display: String) -> MarkdownOffsetMap? {
        let ns = source as NSString
        guard let block = JournalCode.blocks(in: source).first,
              block.range == NSRange(location: 0, length: ns.length),
              ns.substring(with: block.innerRange) == display else { return nil }
        let prefix = block.openRange.length
        let visible = block.innerRange.length
        let suffix = block.closeRange.length
        // Display end is the extra line after a trailing inner newline — after the
        // fence, not the first ` of ``` (which turns the next keystroke into `h``` `).
        let after = prefix + visible + suffix
        return MarkdownOffsetMap(
            toSource: Array(prefix..<(prefix + visible)) + [after],
            toDisplay: Array(repeating: 0, count: prefix) + Array(0...visible) + Array(repeating: visible, count: suffix)
        )
    }
    func sourceRange(_ range: NSRange) -> NSRange {
        if range.location == 0, range.length == toSource.count - 1, range.length > 0 { return NSRange(location: 0, length: toDisplay.count - 1) }
        return translated(range, through: toSource)
    }
    func displayRange(_ range: NSRange) -> NSRange { translated(range, through: toDisplay) }
    private func translated(_ range: NSRange, through map: [Int]) -> NSRange {
        let start = map[min(range.location, map.count - 1)]
        let end = map[min(NSMaxRange(range), map.count - 1)]
        return NSRange(location: start, length: max(0, end - start))
    }
}
