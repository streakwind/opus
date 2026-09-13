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
        rebuild(in: editor)
    }

    func replace(_ displayRange: NSRange, with replacement: NSAttributedString, in editor: JournalTextView) {
        guard !rebuilding, editor.isEditable else { return }
        let range = mapping.sourceRange(displayRange)
        let next = NSMutableAttributedString(attributedString: document)
        next.replaceCharacters(in: range, with: replacement)
        apply(next, selection: NSRange(location: range.location + replacement.length, length: 0), in: editor, undo: true)
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

    private func blocks() -> [NSRange] {
        let text = document.string as NSString
        let groups = (JournalCode.blocks(in: document.string).map(\.range)
            + JournalMath.spans(in: document.string).filter(\.display).map(\.range))
        var result: [NSRange] = []
        var index = 0
        while index < text.length {
            var range = text.lineRange(for: NSRange(location: index, length: 0))
            for group in groups where NSIntersectionRange(group, range).length > 0 {
                range = NSUnionRange(range, text.lineRange(for: group))
            }
            result.append(range)
            index = NSMaxRange(range)
        }
        return result
    }

    private func editingRanges() -> [NSRange] {
        blocks().filter { range in
            NSIntersectionRange(sourceSelection, range).length > 0 ||
            (sourceSelection.length == 0 && NSLocationInRange(sourceSelection.location, range)) ||
            (sourceSelection.location == document.length && NSMaxRange(range) == document.length && !document.string.hasSuffix("\n"))
        }
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
            let cacheKey = JournalRichText.markdown(part)
            let visible: NSAttributedString
            if activeRanges.contains(range) { visible = part }
            else if let cached = previewCache[cacheKey] { visible = cached }
            else {
                let scratch = JournalTextView(frame: editor.bounds)
                scratch.textStorage?.setAttributedString(part)
                coordinator.renderPreview(scratch)
                visible = scratch.attributedString()
                if previewCache.count > 300 { previewCache.removeAll() }
                previewCache[cacheKey] = visible
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
