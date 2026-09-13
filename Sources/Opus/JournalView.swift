import AppKit
import OpusCore
import SwiftUI
import UniformTypeIdentifiers

struct JournalView: View {
    var store: Store
    var query: String
    var newEntryRequest: Int
    @State private var anchor = Date()
    @State private var choosingDate = false
    @State private var choosingTask = false
    @State private var focusRequest = 0
    @State private var pendingEmbed: JournalEmbedOption?

    private var day: String { Day.string(anchor) }
    private var document: JournalEntry? { store.journalDocument(on: day) }

    var body: some View {
        VStack(spacing: 0) {
            heading
            if let document {
                JournalDocumentEditor(
                    store: store,
                    document: document,
                    focusRequest: focusRequest,
                    pendingEmbed: $pendingEmbed,
                    onTaskCommand: { _ in
                        choosingTask = true
                    }
                )
                .id(document.id)
                .popover(isPresented: $choosingTask, arrowEdge: .top) {
                    JournalEmbedPicker(store: store, day: day) { option in
                        store.save(JournalEntry(day: day, title: option.title, link: option.link))
                        pendingEmbed = option
                        choosingTask = false
                        focusRequest += 1
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear { store.ensureJournalDocument(on: day) }
        .onChange(of: day) { _, day in store.ensureJournalDocument(on: day) }
        .onChange(of: newEntryRequest) { _, _ in focusRequest += 1 }
    }

    private var heading: some View {
        HStack(spacing: 12) {
            Button {
                choosingDate = true
            } label: {
                HStack(spacing: 6) {
                    Text(anchor.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
                .font(.system(size: 22, weight: .semibold))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $choosingDate) {
                CompactDatePicker(
                    value: Binding(
                        get: { day },
                        set: { if let value = $0 { anchor = Day.date(value) } }
                    ),
                    allowsClear: false,
                    close: { choosingDate = false }
                )
            }
            Spacer()
            HStack(spacing: 4) {
                Button { move(-1) } label: { Image(systemName: "chevron.left") }
                Button("Today") { anchor = Date() }
                Button { move(1) } label: { Image(systemName: "chevron.right") }
            }
            .roundedControls()
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private func move(_ amount: Int) {
        anchor = Calendar.current.date(byAdding: .day, value: amount, to: anchor) ?? anchor
    }
}

private struct JournalEmbedPicker: View {
    var store: Store
    var day: String
    var onPick: (JournalEmbedOption) -> Void
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var searchFocused: Bool

    private var options: [JournalEmbedOption] {
        JournalWork.embedOptions(in: store.state, from: day).filter {
            query.isEmpty ||
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.detail.localizedCaseInsensitiveContains(query) ||
            (store.course($0.courseID)?.name.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Embed").font(.headline)
            TextField("Search tasks, assessments, or lists", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.return) { confirm(); return .handled }
            if options.isEmpty {
                ContentUnavailableView("No matches", systemImage: "magnifyingglass", description: Text("Try another title or list."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                                Button { onPick(option) } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: option.icon)
                                            .foregroundStyle(store.course(option.courseID)?.tint ?? .teal)
                                            .frame(width: 18)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(option.title).lineLimit(2)
                                            Text(option.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 6).padding(.horizontal, 8)
                                    .background(index == selected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .id(option.id)
                            }
                        }
                    }
                    .onChange(of: selected) { _, id in
                        if options.indices.contains(id) { reader.scrollTo(options[id].id, anchor: .center) }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 440, height: 520)
        .onAppear {
            searchFocused = true
            selected = 0
        }
        .onChange(of: query) { _, _ in selected = 0 }
        .onChange(of: options.map(\.id)) { _, ids in
            if selected >= ids.count { selected = max(0, ids.count - 1) }
        }
    }

    private func move(_ amount: Int) {
        guard !options.isEmpty else { return }
        selected = min(options.count - 1, max(0, selected + amount))
    }
    private func confirm() {
        guard options.indices.contains(selected) else { return }
        onPick(options[selected])
    }
}

private struct JournalDocumentEditor: View {
    var store: Store
    var document: JournalEntry
    @State private var draft: JournalEntry
    var focusRequest: Int
    @Binding var pendingEmbed: JournalEmbedOption?
    var onTaskCommand: (Int) -> Void
    @State private var pendingSave: Task<Void, Never>?
    @State private var dragging: String?
    @State private var insertCaret: Int?

    init(store: Store, document: JournalEntry, focusRequest: Int, pendingEmbed: Binding<JournalEmbedOption?>, onTaskCommand: @escaping (Int) -> Void) {
        self.store = store
        self.document = document
        _draft = State(initialValue: document)
        self.focusRequest = focusRequest
        _pendingEmbed = pendingEmbed
        self.onTaskCommand = onTaskCommand
    }

    private var blocks: [JournalBlock] { JournalMarkdown.blocks(from: draft.markdown) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    switch block {
                    case .text(let text):
                        LiveMarkdownEditor(
                            text: binding(for: index, text: text),
                            focusRequest: index == lastTextIndex ? focusRequest : 0,
                            onTaskCommand: { caret in
                                insertCaret = caretOffset(of: index, plus: caret)
                                onTaskCommand(insertCaret ?? caret)
                            }
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 28)
                        .onDrop(of: [UTType.plainText], isTargeted: nil) { _ in
                            drop(before: index)
                        }
                    case .embed(let link):
                        embedCard(for: link)
                            .onDrag {
                                dragging = link.embedToken
                                return NSItemProvider(object: link.embedToken as NSString)
                            }
                            .onDrop(of: [UTType.plainText], isTargeted: nil) { _ in
                                drop(before: index)
                            }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 48)
        }
        .onChange(of: document.markdown) { _, markdown in
            if markdown != draft.markdown { draft.markdown = markdown }
        }
        .onChange(of: draft.markdown) { _, _ in scheduleSave() }
        .onChange(of: pendingEmbed) { _, option in
            guard let option else { return }
            if !draft.markdown.contains(option.link.embedToken) {
                draft.markdown = JournalMarkdown.inserting(option.link.embedToken, into: draft.markdown, at: insertCaret ?? 0)
            }
            insertCaret = nil
            pendingEmbed = nil
        }
        .onDisappear {
            pendingSave?.cancel()
            store.save(draft)
        }
    }

    private var lastTextIndex: Int {
        blocks.lastIndex { if case .text = $0 { true } else { false } } ?? 0
    }
    private func binding(for index: Int, text: String) -> Binding<String> {
        Binding(
            get: { text },
            set: { newValue in
                var next = blocks
                guard next.indices.contains(index), case .text = next[index] else { return }
                next[index] = .text(newValue)
                draft.markdown = JournalMarkdown.markdown(from: next)
            }
        )
    }
    private func caretOffset(of index: Int, plus caret: Int) -> Int {
        let prefix = JournalMarkdown.markdown(from: Array(blocks.prefix(index)))
        let separator = prefix.isEmpty ? 0 : 1
        return prefix.utf16.count + separator + caret
    }
    @ViewBuilder private func embedCard(for link: JournalLink) -> some View {
        if let entry = store.journalTaskEmbeds(on: draft.day).first(where: { $0.link == link }) {
            JournalTaskEmbedCard(store: store, entry: entry)
        } else {
            JournalTaskEmbedCard(store: store, entry: JournalEntry(day: draft.day, title: "Embed", link: link))
        }
    }
    private func drop(before index: Int) -> Bool {
        guard let token = dragging, let link = JournalLink.fromEmbedToken(token) else { return false }
        var next = blocks.filter {
            if case .embed(let existing) = $0 { return existing != link }
            return true
        }
        let destination = min(index, next.count)
        next.insert(.embed(link), at: destination)
        draft.markdown = JournalMarkdown.markdown(from: next)
        dragging = nil
        return true
    }
    private func scheduleSave() {
        pendingSave?.cancel()
        let value = draft
        pendingSave = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            store.save(value)
        }
    }
}

private struct JournalTaskEmbedCard: View {
    var store: Store
    @State private var entry: JournalEntry
    @State private var pendingSave: Task<Void, Never>?
    @State private var removed = false

    init(store: Store, entry: JournalEntry) {
        self.store = store
        _entry = State(initialValue: entry)
    }

    private var task: StudyTask? {
        guard case .task(let id) = entry.link else { return nil }
        return store.state.tasks.first { $0.id == id }
    }
    private var assessment: Assessment? {
        guard case .assessment(let id) = entry.link else { return nil }
        return store.state.assessments.first { $0.id == id }
    }
    private var rhythm: QuizRule? {
        guard case .rhythm(let id) = entry.link else { return nil }
        return store.rule(id)
    }
    private var commentHeight: CGFloat {
        let lines = entry.markdown.isEmpty ? 1 : min(5, max(1, entry.markdown.components(separatedBy: "\n").count))
        return CGFloat(lines) * 20
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            leadingControl
                .frame(width: 18, height: 18, alignment: .top)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(headingTitle).font(.system(size: 14, weight: .semibold))
                        .strikethrough(task.map { $0.kind != .progress && $0.completed } ?? false)
                    Spacer()
                    Button(action: remove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Remove from journal")
                }
                Text(headingDetail).font(.caption).foregroundStyle(.secondary)
                JournalCommentField(text: $entry.markdown)
                    .frame(height: commentHeight, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        .contextMenu {
            Button("Remove embed", role: .destructive, action: remove)
        }
        .onChange(of: entry.markdown) { _, _ in scheduleSave() }
        .onDisappear {
            pendingSave?.cancel()
            if !removed { store.save(entry) }
        }
    }

    private var headingTitle: String {
        task?.title ?? assessment?.title ?? rhythm?.title ?? entry.title
    }
    private var headingDetail: String {
        if let task {
            var parts = [store.course(task.courseID)?.name ?? "Inbox"]
            if let due = task.due { parts.append("Due \(Day.label(due))") }
            if task.kind == .progress { parts.append(task.progressLabel) }
            return parts.joined(separator: " · ")
        }
        if let assessment {
            return [store.course(assessment.courseID)?.name ?? "Inbox", Day.label(assessment.day)].joined(separator: " · ")
        }
        if let rhythm {
            return [store.course(rhythm.courseID)?.name ?? "Inbox", rhythm.repeatsLabel].joined(separator: " · ")
        }
        return "Deleted item"
    }
    @ViewBuilder private var leadingControl: some View {
        if let task {
            if task.kind == .progress {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(store.course(task.courseID)?.tint ?? .teal)
            } else {
                Button {
                    var copy = task
                    copy.completed.toggle()
                    store.save(copy)
                } label: {
                    Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(task.completed ? .secondary : store.course(task.courseID)?.tint ?? .teal)
            }
        } else if assessment != nil {
            Image(systemName: "calendar").foregroundStyle(store.course(assessment?.courseID)?.tint ?? .teal)
        } else if rhythm != nil {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(store.course(rhythm?.courseID)?.tint ?? .teal)
        } else {
            Image(systemName: "link.badge.plus").foregroundStyle(.secondary)
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let value = entry
        pendingSave = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            store.save(value)
        }
    }
    private func remove() {
        removed = true
        pendingSave?.cancel()
        store.deleteJournalEntry(entry.id)
    }
}

private struct JournalCommentField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true

        let editor = NSTextView()
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.importsGraphics = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.drawsBackground = false
        editor.allowsUndo = true
        editor.font = .systemFont(ofSize: 14)
        editor.textColor = .labelColor
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.minSize = NSSize(width: 0, height: 20)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.string = text
        editor.setAccessibilityPlaceholderValue("Add a journal comment…")
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text { editor.string = text }
        let lines = text.isEmpty ? 1 : min(5, max(1, text.components(separatedBy: "\n").count))
        scroll.hasVerticalScroller = lines >= 5
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JournalCommentField
        init(parent: JournalCommentField) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}

private struct LiveMarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var focusRequest: Int
    var onTaskCommand: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> HeightReportingTextView {
        let editor = HeightReportingTextView()
        editor.delegate = context.coordinator
        editor.isRichText = true
        editor.importsGraphics = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.drawsBackground = false
        editor.allowsUndo = true
        editor.textContainerInset = NSSize(width: 0, height: 4)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.lineFragmentPadding = 0
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.minSize = NSSize(width: 0, height: 28)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.string = text
        context.coordinator.applyStyles(to: editor)
        return editor
    }
    func updateNSView(_ editor: HeightReportingTextView, context: Context) {
        context.coordinator.parent = self
        if editor.string != text {
            editor.string = text
            context.coordinator.applyStyles(to: editor)
        }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { editor.window?.makeFirstResponder(editor) }
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LiveMarkdownEditor
        var lastFocusRequest = 0
        private var applying = false
        init(parent: LiveMarkdownEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !applying, let editor = notification.object as? NSTextView else { return }
            if consumeTaskCommand(in: editor) { return }
            parent.text = markdown(from: editor)
            applyStyles(to: editor)
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !applying, let editor = notification.object as? NSTextView else { return }
            applyStyles(to: editor)
        }
        private func consumeTaskCommand(in editor: NSTextView) -> Bool {
            let selection = editor.selectedRange()
            guard selection.length == 0, selection.location >= 5 else { return false }
            let source = editor.string as NSString
            let range = NSRange(location: selection.location - 5, length: 5)
            guard source.substring(with: range) == "/task" else { return false }
            applying = true
            editor.textStorage?.replaceCharacters(in: range, with: "")
            editor.setSelectedRange(NSRange(location: range.location, length: 0))
            applying = false
            parent.text = markdown(from: editor)
            applyStyles(to: editor)
            let caret = range.location
            DispatchQueue.main.async { self.parent.onTaskCommand(caret) }
            return true
        }
        private func markdown(from editor: NSTextView) -> String { editor.string }

        func applyStyles(to editor: NSTextView) {
            guard !applying, let storage = editor.textStorage else { return }
            applying = true
            defer { applying = false }
            let source = editor.string
            let selection = editor.selectedRange()
            let full = NSRange(location: 0, length: (source as NSString).length)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 5
            storage.setAttributes([
                .font: NSFont.systemFont(ofSize: 17),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ], range: full)

            styleHeadings(source, storage: storage, selection: selection)
            styleInline(#"\*\*(.+?)\*\*"#, source: source, storage: storage, selection: selection, font: .systemFont(ofSize: 17, weight: .bold))
            styleInline(#"`([^`\n]+)`"#, source: source, storage: storage, selection: selection, font: .monospacedSystemFont(ofSize: 16, weight: .regular), background: .quaternaryLabelColor)
            styleLinks(source, storage: storage, selection: selection)
            editor.typingAttributes = [
                .font: NSFont.systemFont(ofSize: 17),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        }

        private func styleHeadings(_ source: String, storage: NSTextStorage, selection: NSRange) {
            guard let expression = try? NSRegularExpression(pattern: #"(?m)^(#{1,3})\s+(.*)$"#) else { return }
            let full = NSRange(location: 0, length: (source as NSString).length)
            for match in expression.matches(in: source, range: full) {
                let level = match.range(at: 1).length
                let font: NSFont = level == 1 ? .systemFont(ofSize: 28, weight: .bold) : level == 2 ? .systemFont(ofSize: 23, weight: .bold) : .systemFont(ofSize: 19, weight: .semibold)
                storage.addAttribute(.font, value: font, range: match.range)
                if !isActive(match.range, selection: selection) {
                    hide(NSRange(location: match.range.location, length: match.range(at: 1).length + 1), storage: storage)
                }
            }
        }
        private func styleInline(_ pattern: String, source: String, storage: NSTextStorage, selection: NSRange, font: NSFont, background: NSColor? = nil) {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
            let full = NSRange(location: 0, length: (source as NSString).length)
            for match in expression.matches(in: source, range: full) {
                let content = match.range(at: 1)
                storage.addAttribute(.font, value: font, range: content)
                if let background { storage.addAttribute(.backgroundColor, value: background, range: content) }
                if !isActive(match.range, selection: selection) {
                    hide(NSRange(location: match.range.location, length: content.location - match.range.location), storage: storage)
                    hide(NSRange(location: NSMaxRange(content), length: NSMaxRange(match.range) - NSMaxRange(content)), storage: storage)
                }
            }
        }
        private func styleLinks(_ source: String, storage: NSTextStorage, selection: NSRange) {
            guard let expression = try? NSRegularExpression(pattern: #"\[([^\]\n]+)\]\(([^\)\n]+)\)"#) else { return }
            let full = NSRange(location: 0, length: (source as NSString).length)
            for match in expression.matches(in: source, range: full) {
                let label = match.range(at: 1)
                storage.addAttributes([.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue], range: label)
                if !isActive(match.range, selection: selection) {
                    hide(NSRange(location: match.range.location, length: 1), storage: storage)
                    hide(NSRange(location: NSMaxRange(label), length: NSMaxRange(match.range) - NSMaxRange(label)), storage: storage)
                }
            }
        }
        private func hide(_ range: NSRange, storage: NSTextStorage) {
            guard range.length > 0 else { return }
            storage.addAttributes([.foregroundColor: NSColor.clear, .font: NSFont.systemFont(ofSize: 0.1)], range: range)
        }
        private func isActive(_ range: NSRange, selection: NSRange) -> Bool {
            let caretIsInside = selection.location >= range.location && selection.location <= NSMaxRange(range)
            return caretIsInside || NSIntersectionRange(range, selection).length > 0
        }
    }
}

private final class HeightReportingTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let container = textContainer, let layout = layoutManager else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 28)
        }
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(28, ceil(used.height) + textContainerInset.height * 2))
    }
    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }
}
