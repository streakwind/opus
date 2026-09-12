import OpusCore
import SwiftUI

struct JournalView: View {
    var store: Store
    var query: String
    var newEntryRequest: Int
    @State private var anchor = Date()
    @State private var selectedID: String?

    private var day: String { Day.string(anchor) }
    private var entries: [JournalEntry] {
        store.journalEntries(on: day).filter {
            query.isEmpty ||
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.markdown.localizedCaseInsensitiveContains(query)
        }
    }
    private var selected: JournalEntry? {
        entries.first { $0.id == selectedID } ?? entries.first
    }

    var body: some View {
        VStack(spacing: 0) {
            heading
            HSplitView {
                entryList.frame(minWidth: 190, idealWidth: 230, maxWidth: 290)
                if let selected {
                    JournalEditor(store: store, entry: selected, linkOptions: linkOptions)
                        .id(selected.id)
                } else {
                    ContentUnavailableView(
                        "No journal entries",
                        systemImage: "book.closed",
                        description: Text("Write for this day or link a note to upcoming work.")
                    )
                }
            }
        }
        .onAppear { selectFirst() }
        .onChange(of: anchor) { _, _ in selectFirst() }
        .onChange(of: entries.map(\.id)) { _, _ in selectFirst() }
        .onChange(of: newEntryRequest) { _, _ in create() }
    }

    private var heading: some View {
        HStack(spacing: 12) {
            Text(anchor.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                .font(.system(size: 22, weight: .semibold))
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

    private var entryList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Entries").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("New entry", action: create)
                    if !linkOptions.isEmpty {
                        Divider()
                        ForEach(linkOptions, id: \.link.token) { option in
                            Button(option.title) { create(link: option.link, title: option.title) }
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .help("New journal entry")
            }
            .padding(12)

            List(selection: $selectedID) {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            if entry.link != nil { Image(systemName: "link").font(.caption2) }
                            Text(entry.title.isEmpty ? "Untitled" : entry.title).lineLimit(1)
                        }
                        Text(summary(entry.markdown))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    .padding(.vertical, 4)
                    .tag(entry.id)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private var linkOptions: [(link: JournalLink, title: String)] {
        let tasks = store.state.tasks
            .filter { $0.kind == .progress ? $0.current < $0.target : !$0.completed }
            .map { (JournalLink.task($0.id), $0.title) }
        let assessments = store.state.assessments
            .filter { $0.day >= day }
            .map { (JournalLink.assessment($0.id), $0.title) }
        let rhythms = store.state.rules.map { (JournalLink.rhythm($0.id), $0.title + " · Rhythm") }
        let events = store.state.schedule
            .filter { $0.day >= day }
            .map { (JournalLink.schedule($0.id), $0.title) }
        return tasks + assessments + rhythms + events
    }

    private func create() { create(link: nil, title: "Untitled") }
    private func create(link: JournalLink?, title: String) {
        let entry = JournalEntry(day: day, title: title, link: link)
        store.save(entry)
        selectedID = entry.id
    }
    private func selectFirst() {
        if !entries.contains(where: { $0.id == selectedID }) { selectedID = entries.first?.id }
    }
    private func move(_ amount: Int) {
        anchor = Calendar.current.date(byAdding: .day, value: amount, to: anchor) ?? anchor
    }
    private func summary(_ markdown: String) -> String {
        markdown.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Empty note"
    }
}

private struct JournalEditor: View {
    var store: Store
    var linkOptions: [(link: JournalLink, title: String)]
    @State private var entry: JournalEntry
    @State private var preview = false

    init(store: Store, entry: JournalEntry, linkOptions: [(link: JournalLink, title: String)]) {
        self.store = store
        self.linkOptions = linkOptions
        _entry = State(initialValue: entry)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Entry title", text: $entry.title)
                    .textFieldStyle(.plain).font(.title3.weight(.semibold))
                Spacer()
                Picker("Mode", selection: $preview) {
                    Text("Write").tag(false)
                    Text("Preview").tag(true)
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 150)
            }
            HStack(spacing: 6) {
                Menu {
                    Button("No link") { entry.link = nil; entry.throughDay = nil }
                    Divider()
                    ForEach(linkOptions, id: \.link.token) { option in
                        Button(option.title) {
                            entry.link = option.link
                            entry.title = option.title.replacingOccurrences(of: " · Rhythm", with: "")
                        }
                    }
                } label: {
                    Label(entry.link == nil ? "Link to work" : linkCaption, systemImage: "link")
                }
                .menuStyle(.borderlessButton).fixedSize()
                if let through = entry.throughDay {
                    Text("through \(Day.label(through))")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            if preview {
                ScrollView {
                    Text(rendered)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(14)
                }
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
            } else {
                TextEditor(text: $entry.markdown)
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                Button("Delete", role: .destructive) { store.deleteJournalEntry(entry.id) }
                Spacer()
                Button("Save") { store.save(entry) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
    }

    private var rendered: AttributedString {
        (try? AttributedString(markdown: entry.markdown)) ?? AttributedString(entry.markdown)
    }
    private var linkCaption: String {
        switch entry.link {
        case .task: "Task"
        case .assessment: "Assessment"
        case .rhythm: "Rhythm"
        case .schedule: "Schedule event"
        case nil: ""
        }
    }
}
