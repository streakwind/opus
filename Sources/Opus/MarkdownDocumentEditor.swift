import AppKit
import OpusCore
import SwiftUI

struct MarkdownDocumentEditor: View {
    var store: Store
    var day: String
    var markdown: String
    var documentID: String
    var focusRequest: Int
    var embedCourseID: String?
    var onEmbed: ((JournalEmbedOption) -> Void)?
    var onSave: (String) -> Void
    @State private var draft: String
    @State private var saved: String
    @State private var pendingSave: Task<Void, Never>?
    @State private var pendingEmbed: JournalEmbedOption?
    @State private var choosingTask = false
    @State private var editing: EmbedSelection?

    private struct EmbedSelection: Identifiable {
        var link: JournalLink
        var id: String { link.token }
    }

    init(store: Store, day: String, markdown: String, documentID: String, focusRequest: Int, embedCourseID: String? = nil, onEmbed: ((JournalEmbedOption) -> Void)? = nil, onSave: @escaping (String) -> Void) {
        self.store = store
        self.day = day
        self.markdown = markdown
        self.documentID = documentID
        self.focusRequest = focusRequest
        self.embedCourseID = embedCourseID
        self.onEmbed = onEmbed
        self.onSave = onSave
        _draft = State(initialValue: markdown)
        _saved = State(initialValue: markdown)
    }

    var body: some View {
        nativeEditor()
        .onChange(of: draft) { _, _ in scheduleSave() }
        .onChange(of: markdown) { _, value in
            if value == draft { saved = value }
            else if pendingSave == nil { saved = value; draft = value }
        }
        .onChange(of: documentID) { _, _ in
            pendingSave?.cancel()
            pendingSave = nil
            draft = markdown
            saved = markdown
        }
        .onDisappear { pendingSave?.cancel(); flush() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            pendingSave?.cancel(); pendingSave = nil; flush()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            pendingSave?.cancel(); pendingSave = nil; flush()
        }
        .popover(isPresented: $choosingTask, arrowEdge: .top) {
            JournalEmbedPicker(store: store, day: day, courseID: embedCourseID) { option in
                onEmbed?(option)
                pendingEmbed = option
                choosingTask = false
            }
        }
        .sheet(item: $editing) { target in
            JournalEmbedDetails(store: store, link: target.link, day: day, close: { editing = nil })
        }
    }

    private func nativeEditor() -> some View {
        JournalNativeEditor(
            markdown: $draft,
            store: store, day: day, focusRequest: focusRequest,
            pendingEmbed: $pendingEmbed,
            onTaskCommand: { _ in choosingTask = true },
            onOpen: { editing = EmbedSelection(link: $0) },
            live: true
        )
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        guard draft != saved else { pendingSave = nil; return }
        pendingSave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            pendingSave = nil
            flush()
        }
    }
    private func flush() {
        guard draft != saved else { return }
        onSave(draft)
        if store.error == nil { saved = draft }
    }
}
