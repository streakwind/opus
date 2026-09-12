import SwiftUI

struct QuickStartView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    private let pages: [(title: String, symbol: String, text: String)] = [
        ("Capture a task", "plus", "Press ⌘N or use Add a task, type a title, and press Return. Inbox holds tasks that do not belong to a list."),
        ("Plan your work", "checklist", "Create your own lists from the sidebar. Today brings together upcoming and overdue work. Open a task to change its list or dates; use its checkbox when it is done."),
        ("Track textbook notes", "book", "Choose Textbook notes when creating a task. Set the page range, then enter your last-read page as you work. Open the task for its pace suggestion."),
        ("Use the calendars", "calendar", "Calendar shows dated tasks and assessments. Click a day to add an item. Schedule is for timed events and class blocks; configure class times by editing a list."),
        ("Repeat only what you need", "repeat", "Rhythm repeats work on the days you choose. Create a rule, select its days, and adjust or remove it whenever your routine changes. Nothing is added until you create it.")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Quick start").font(.headline)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Image(systemName: pages[step].symbol).font(.system(size: 28)).foregroundStyle(.secondary)
            Text(pages[step].title).font(.title2.weight(.semibold))
            Text(pages[step].text).font(.body).fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 95, alignment: .top)
            HStack {
                Text("\(step + 1) of \(pages.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if step > 0 { Button("Back") { step -= 1 } }
                Button(step == pages.count - 1 ? "Done" : "Next") {
                    if step == pages.count - 1 { dismiss() } else { step += 1 }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 420).roundedControls()
    }
}
