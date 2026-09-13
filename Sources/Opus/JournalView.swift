import AppKit
import OpusCore
import SwiftUI

struct JournalView: View {
    var store: Store
    var query: String
    var newEntryRequest: Int
    @State private var anchor = Date()
    @State private var choosingDate = false
    @State private var choosingTask = false
    @State private var focusRequest = 0

    private var day: String { Day.string(anchor) }
    private var document: JournalEntry? { store.journalDocument(on: day) }
    private var embeds: [JournalEntry] { store.journalTaskEmbeds(on: day) }

    var body: some View {
        VStack(spacing: 0) {
            heading
            if let document {
                VStack(alignment: .leading, spacing: 12) {
                    if !embeds.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(embeds) { entry in
                                JournalTaskEmbedCard(store: store, entry: entry)
                            }
                        }
                        .padding(.horizontal, 28)
                    }
                    JournalDocumentEditor(
                        store: store,
                        document: document,
                        focusRequest: focusRequest,
                        onTaskCommand: { choosingTask = true }
                    )
                    .id(document.id)
                    .popover(isPresented: $choosingTask, arrowEdge: .top) {
                        taskPicker
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear { ensureDocument() }
        .onChange(of: day) { _, _ in ensureDocument() }
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

    private var taskPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Embed a task").font(.headline)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(availableTasks) { task in
                        Button {
                            store.save(JournalEntry(day: day, title: task.title, link: .task(task.id)))
                            choosingTask = false
                            focusRequest += 1
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: task.kind == .progress ? "chart.bar.fill" : "circle")
                                    .foregroundStyle(store.course(task.courseID)?.tint ?? .teal)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title).lineLimit(1)
                                    Text(store.course(task.courseID)?.name ?? "Inbox")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle()).padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14).frame(width: 300, height: 320)
    }

    private var availableTasks: [StudyTask] {
        store.state.tasks.filter {
            ($0.kind == .progress ? $0.current < $0.target : !$0.completed) &&
            (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query))
        }
    }
    private func ensureDocument() {
        guard store.journalDocument(on: day) == nil else { return }
        store.save(JournalEntry(day: day, title: "Journal"))
    }
    private func move(_ amount: Int) {
        anchor = Calendar.current.date(byAdding: .day, value: amount, to: anchor) ?? anchor
    }
}

private struct JournalDocumentEditor: View {
    var store: Store
    @State private var document: JournalEntry
    var focusRequest: Int
    var onTaskCommand: () -> Void
    @State private var pendingSave: Task<Void, Never>?

    init(store: Store, document: JournalEntry, focusRequest: Int, onTaskCommand: @escaping () -> Void) {
        self.store = store
        _document = State(initialValue: document)
        self.focusRequest = focusRequest
        self.onTaskCommand = onTaskCommand
    }
    var body: some View {
        LiveMarkdownEditor(text: $document.markdown, focusRequest: focusRequest, onTaskCommand: onTaskCommand)
            .onChange(of: document.markdown) { _, _ in scheduleSave() }
            .onDisappear {
                pendingSave?.cancel()
                store.save(document)
            }
    }
    private func scheduleSave() {
        pendingSave?.cancel()
        let value = document
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

    private var taskID: String? {
        guard case .task(let id)? = entry.link else { return nil }
        return id
    }
    private var task: StudyTask? {
        guard let taskID else { return nil }
        return store.state.tasks.first { $0.id == taskID }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            leadingControl
                .frame(width: 18, height: 20, alignment: .top)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let task {
                        Text(task.title).font(.system(size: 14, weight: .semibold))
                            .strikethrough(task.kind != .progress && task.completed)
                    } else {
                        Text(entry.title).font(.system(size: 14, weight: .semibold))
                    }
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
                if let task {
                    HStack(spacing: 5) {
                        Text(store.course(task.courseID)?.name ?? "Inbox")
                        if let due = task.due { Text("· Due \(Day.label(due))") }
                        if task.kind == .progress { Text("· \(task.progressLabel)") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Deleted task").font(.caption).foregroundStyle(.secondary)
                }
                TextField("Add a journal comment…", text: $entry.markdown, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(2...4)
                    .frame(minHeight: 42, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
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

private struct LiveMarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var focusRequest: Int
    var onTaskCommand: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let editor = NSTextView()
        editor.delegate = context.coordinator
        editor.isRichText = true
        editor.importsGraphics = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.drawsBackground = false
        editor.allowsUndo = true
        editor.textContainerInset = NSSize(width: 28, height: 18)
        editor.textContainer?.widthTracksTextView = true
        editor.string = text
        scroll.documentView = editor
        context.coordinator.applyStyles(to: editor)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
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
            parent.text = editor.string
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
            parent.text = editor.string
            applyStyles(to: editor)
            DispatchQueue.main.async { self.parent.onTaskCommand() }
            return true
        }

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
