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
                        if !store.journalTaskEmbeds(on: day).contains(where: { $0.link == option.link }) {
                            store.save(JournalEntry(day: day, title: option.title, link: option.link))
                        }
                        pendingEmbed = option
                        choosingTask = false
                        focusRequest += 1
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            store.ensureJournalDocument(on: day)
            focusRequest += 1
        }
        .onChange(of: day) { _, day in
            store.ensureJournalDocument(on: day)
            focusRequest += 1
        }
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
    var focusRequest: Int
    @Binding var pendingEmbed: JournalEmbedOption?
    var onTaskCommand: (Int) -> Void
    @State private var markdown: String
    @State private var savedMarkdown: String
    @State private var pendingSave: Task<Void, Never>?
    @State private var editing: EmbedSelection?

    private struct EmbedSelection: Identifiable {
        var link: JournalLink
        var id: String { link.token }
    }
    init(store: Store, document: JournalEntry, focusRequest: Int, pendingEmbed: Binding<JournalEmbedOption?>, onTaskCommand: @escaping (Int) -> Void) {
        self.store = store; self.document = document; self.focusRequest = focusRequest
        _pendingEmbed = pendingEmbed; self.onTaskCommand = onTaskCommand
        _markdown = State(initialValue: document.markdown)
        _savedMarkdown = State(initialValue: document.markdown)
    }
    var body: some View {
        JournalNativeEditor(markdown: $markdown, store: store, day: document.day,
                            focusRequest: focusRequest, pendingEmbed: $pendingEmbed,
                            onTaskCommand: onTaskCommand, onOpen: { editing = EmbedSelection(link: $0) })
            .onChange(of: markdown) { _, _ in scheduleSave() }
            .onChange(of: document.markdown) { _, value in
                if value == markdown { savedMarkdown = value }
                else if pendingSave == nil { savedMarkdown = value; markdown = value }
            }
            .onDisappear { pendingSave?.cancel(); flush() }
            .sheet(item: $editing) { target in
                JournalEmbedDetails(store: store, link: target.link, day: document.day, close: { editing = nil })
            }
    }
    private func scheduleSave() {
        pendingSave?.cancel()
        guard markdown != savedMarkdown else { pendingSave = nil; return }
        pendingSave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            pendingSave = nil
            flush()
        }
    }
    private func flush() {
        guard markdown != savedMarkdown, var latest = store.journalDocument(on: document.day), latest.id == document.id else { return }
        latest.markdown = markdown
        store.save(latest)
        if store.error == nil { savedMarkdown = markdown }
    }
}

private struct JournalEmbedDetails: View {
    var store: Store
    var link: JournalLink
    var day: String
    var close: () -> Void
    @State private var comment: String
    private let commentID: String?
    init(store: Store, link: JournalLink, day: String, close: @escaping () -> Void) {
        self.store = store; self.link = link; self.day = day; self.close = close
        let entry = store.journalTaskEmbeds(on: day).first { $0.link == link && !$0.markdown.isEmpty }
        commentID = entry?.id
        _comment = State(initialValue: entry?.markdown ?? "")
    }
    var body: some View {
        VStack(spacing: 0) {
            switch link {
            case .task(let id):
                if let task = store.state.tasks.first(where: { $0.id == id }) {
                    WorkItemEditor(store: store, source: .task(task), onDismiss: close)
                } else { missing }
            case .assessment(let id):
                if let item = store.state.assessments.first(where: { $0.id == id }) {
                    WorkItemEditor(store: store, source: .assessment(item), onDismiss: close)
                } else { missing }
            case .rhythm(let id):
                if let rule = store.rule(id) { RuleEditor(store: store, rule: rule, onDismiss: close) }
                else { missing }
            case .schedule:
                missing
            }
            if commentID != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Journal comment").font(.caption).foregroundStyle(.secondary)
                    TextField("Comment", text: $comment, axis: .vertical).lineLimit(1...6).textFieldStyle(.plain)
                }.padding([.horizontal, .bottom], 20)
            }
        }
        .onChange(of: comment) { _, value in
            guard let id = commentID, var entry = store.state.journal.first(where: { $0.id == id }) else { return }
            entry.markdown = value; store.save(entry)
        }
    }
    private var missing: some View {
        VStack(spacing: 12) {
            Text("The linked item is no longer available.")
            Button("Done", action: close).keyboardShortcut(.defaultAction)
        }.padding(24)
    }
}
