#if os(iOS)
import SwiftUI
import OpusCore
import UniformTypeIdentifiers

struct PhoneCourse: View {
    var store: Store
    var courseID: String
    var edit: (PhoneSheet) -> Void
    @State private var note: ListNote?
    private var course: Course? { store.course(courseID) }
    var body: some View {
        List {
            Section("Work") {
                ForEach(store.state.tasks.filter { $0.courseID == courseID }) { task in
                    Button { edit(.task(task)) } label: {
                        Label(task.title, systemImage: task.isFinished ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(.primary).padding(.vertical, 6)
                    }
                }
                Button("Add task", systemImage: "plus") { edit(.task(StudyTask(courseID: courseID))) }
            }
            Section("Assessments") {
                ForEach(store.state.assessments.filter { $0.courseID == courseID }) { value in Button(value.title) { edit(.assessment(value)) } }
                Button("Add assessment", systemImage: "plus") { edit(.assessment(Assessment(courseID: courseID))) }
            }
            Section("Notes") {
                ForEach(course?.listNotes ?? []) { value in Button(value.displayTitle) { note = value } }
                Button("New note", systemImage: "square.and.pencil") { note = ListNote() }
            }
        }
        .navigationTitle(course?.name ?? "List")
        .toolbar { if let course { Button("Edit list", systemImage: "slider.horizontal.3") { edit(.course(course)) } } }
        .sheet(item: $note) { value in NavigationStack { PhoneNoteEditor(store: store, courseID: courseID, draft: value) } }
    }
}

private struct PhoneNoteEditor: View {
    var store: Store
    var courseID: String
    @State var draft: ListNote
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            TextField("Title", text: $draft.title)
            Section("Markdown") { TextEditor(text: $draft.markdown).frame(minHeight: 300).font(.body) }
            Section { DisclosureGroup("Preview") { PhoneMarkdownPreview(markdown: draft.markdown) } }
            if store.course(courseID)?.listNotes.contains(where: { $0.id == draft.id }) == true {
                Button("Delete note", role: .destructive) { store.deleteListNote(courseID, noteID: draft.id); if store.error == nil { dismiss() } }
            }
        }
        .navigationTitle("Note").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { store.saveListNote(courseID, draft); if store.error == nil { dismiss() } }.buttonStyle(.glassProminent) }
        }
    }
}

struct PhoneJournal: View {
    var store: Store
    @State private var date = Date()
    @State private var inserting = false
    @State private var selectedLink: JournalLink?
    private var day: String { Day.string(date) }
    private var markdown: Binding<String> {
        Binding(get: { store.journalDocument(on: day)?.markdown ?? "" }, set: { text in
            guard var document = store.journalDocument(on: day) else { return }
            document.markdown = text; store.save(document)
        })
    }
    var body: some View {
        Form {
            DatePicker("Day", selection: $date, displayedComponents: .date)
            Section("Markdown · saved as you type") {
                TextEditor(text: markdown).font(.body).frame(minHeight: 320).accessibilityLabel("Journal text")
                Button("Embed work", systemImage: "link") { inserting = true }.buttonStyle(.glass)
            }
            Section { DisclosureGroup("Preview") { PhoneMarkdownPreview(markdown: markdown.wrappedValue) } }
            Section("Linked work") {
                ForEach(store.journalTaskEmbeds(on: day)) { entry in
                    Button(entry.title) { selectedLink = entry.link }
                }
            }
        }
        .onAppear { store.ensureJournalDocument(on: day) }
        .onChange(of: day) { _, next in store.ensureJournalDocument(on: next) }
        .sheet(isPresented: $inserting) {
            NavigationStack {
                List(JournalWork.embedOptions(in: store.state, from: day)) { option in
                    Button {
                        guard var document = store.journalDocument(on: day) else { return }
                        document.markdown += "\n" + option.link.embedToken + "\n"
                        store.save(document)
                        if !store.journalTaskEmbeds(on: day).contains(where: { $0.link == option.link }) {
                            store.save(JournalEntry(day: day, title: option.title, link: option.link))
                        }
                        inserting = false
                    } label: { VStack(alignment: .leading) { Label(option.title, systemImage: option.icon); Text(option.detail).font(.caption).foregroundStyle(.secondary) } }
                }.navigationTitle("Embed work")
                    .toolbar { Button("Done") { inserting = false } }
            }
        }
        .sheet(isPresented: Binding(get: { selectedLink != nil }, set: { if !$0 { selectedLink = nil } })) {
            NavigationStack {
                List {
                    if let link = selectedLink {
                        switch link {
                        case .task(let id):
                            if let task = store.state.tasks.first(where: { $0.id == id }) { Text(task.title); Text(task.notes); Text(task.dateCaption() ?? ""); Text(task.kind == .progress ? task.progressLabel : task.isFinished ? "Completed" : "Open") }
                        case .assessment(let id):
                            if let value = store.state.assessments.first(where: { $0.id == id }) { Text(value.title); Text(value.topics); Text(Day.label(value.day)) }
                        default: Text("Open this linked list or rhythm from Tasks or Rhythm.")
                        }
                    }
                }.navigationTitle("Linked work").toolbar { Button("Done") { selectedLink = nil } }
            }
        }
    }
}

struct PhoneMarkdownPreview: View {
    var markdown: String
    var body: some View {
        Text((try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .full))) ?? AttributedString(markdown))
            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(.vertical, 8)
    }
}

private struct SnapshotDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct PhoneSettings: View {
    var store: Store
    var sync: ICloudSync?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"
    @State private var exporting = false
    @State private var document: SnapshotDocument?
    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
            }
            Section("iCloud") {
                if let sync {
                    Toggle("Sync with iCloud", isOn: Binding(get: { sync.enabled }, set: { sync.setEnabled($0) }))
                    Text(sync.status).font(.caption).foregroundStyle(.secondary)
                    Button("Sync now") { Task { await sync.sync() } }.disabled(!sync.enabled)
                } else { Text("Sync could not start. Your local data remains available.") }
                Text("Use the same Apple Account and iCloud Drive on Mac and iPhone. Deletions also sync. When the same item is edited on both devices, the latest revision wins.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Data") {
                Button("Undo last saved change", systemImage: "arrow.uturn.backward") { store.undo() }.disabled(!store.canUndo)
                Button("Export all data", systemImage: "square.and.arrow.up") {
                    do {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        document = SnapshotDocument(data: try encoder.encode(store.state)); exporting = true
                    } catch { store.error = error.localizedDescription }
                }
            }
            Section("Quick start") {
                Text("Add a list in Tasks, then use + to create tasks, progress, assessments, or schedule blocks. Calendar shows a day at a time. Rhythm repeats work on selected weekdays.")
                Text("Journal and notes accept Markdown. Notes save with Save; journal saves as you type. Embed work adds a link to the current journal day.")
            }
        }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Done") { dismiss() } }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Opus-" + Day.today) { result in
            if case .failure(let error) = result { store.error = error.localizedDescription }
        }
    }
}
#endif
