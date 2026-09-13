import OpusCore
import SwiftUI

struct NoteDraft: Identifiable, Equatable {
    var courseID: String
    var note: ListNote
    var id: String { courseID + ":" + note.id }
}

struct ListNoteEditor: View {
    var store: Store
    @State var draft: NoteDraft
    var onDismiss: () -> Void
    @State private var focusRequest = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("Title", text: $draft.note.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Button("Done") {
                    persist()
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Divider()
            MarkdownDocumentEditor(
                store: store,
                day: Day.today,
                markdown: draft.note.markdown,
                documentID: draft.note.id,
                focusRequest: focusRequest,
                embedCourseID: draft.courseID
            ) { markdown in
                draft.note.markdown = markdown
                persist()
            }
        }
        .frame(width: 560, height: 520)
        .onAppear { focusRequest += 1 }
        .onChange(of: draft.note.title) { _, _ in persist() }
        .onDisappear { persist() }
    }

    private func persist() {
        store.saveListNote(draft.courseID, draft.note)
    }
}
