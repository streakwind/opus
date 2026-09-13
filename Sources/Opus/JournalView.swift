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
    @State private var focusRequest = 0

    private var day: String { Day.string(anchor) }
    private var document: JournalEntry? { store.journalDocument(on: day) }

    var body: some View {
        VStack(spacing: 0) {
            heading
            if let document {
                MarkdownDocumentEditor(
                    store: store,
                    day: day,
                    markdown: document.markdown,
                    documentID: document.id,
                    focusRequest: focusRequest,
                    onEmbed: { option in
                        if !store.journalTaskEmbeds(on: day).contains(where: { $0.link == option.link }) {
                            store.save(JournalEntry(day: day, title: option.title, link: option.link))
                        }
                    }
                ) { markdown in
                    guard var latest = store.journalDocument(on: day), latest.id == document.id else { return }
                    latest.markdown = markdown
                    store.save(latest)
                }
                .id(document.id)
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

struct JournalEmbedPicker: View {
    var store: Store
    var day: String
    var courseID: String? = nil
    var onPick: (JournalEmbedOption) -> Void
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var searchFocused: Bool

    private var options: [JournalEmbedOption] {
        JournalWork.embedOptions(in: store.state, from: day).filter {
            (courseID == nil || $0.courseID == courseID) &&
            (query.isEmpty ||
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.detail.localizedCaseInsensitiveContains(query) ||
            (store.course($0.courseID)?.name.localizedCaseInsensitiveContains(query) ?? false))
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

struct JournalEmbedDetails: View {
    var store: Store
    var link: JournalLink
    var day: String
    var close: () -> Void
    init(store: Store, link: JournalLink, day: String, close: @escaping () -> Void) {
        self.store = store; self.link = link; self.day = day; self.close = close
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
            case .schedule(let id):
                if let block = store.state.schedule.first(where: { $0.id == id }) {
                    ScheduleEditor(store: store, block: block, onDismiss: close)
                } else { missing }
            }
        }
    }
    private var missing: some View {
        VStack(spacing: 12) {
            Text("The linked item is no longer available.")
            Button("Done", action: close).keyboardShortcut(.defaultAction)
        }.padding(24)
    }
}
