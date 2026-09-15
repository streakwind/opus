import Foundation

package enum SearchCategory: String, CaseIterable, Identifiable {
    case pages = "Pages", lists = "Lists", tasks = "Tasks", progress = "Progress"
    case assessments = "Assessments", notes = "Notes", rhythms = "Rhythms", schedule = "Schedule"
    package var id: String { rawValue }
    package var icon: String {
        switch self {
        case .pages: "app"
        case .lists: "folder"
        case .tasks: "checkmark.circle"
        case .progress: "chart.bar"
        case .assessments: "calendar"
        case .notes: "note.text"
        case .rhythms: "repeat"
        case .schedule: "clock"
        }
    }
}

package struct SearchResult: Identifiable, Equatable {
    package var category: SearchCategory
    package var targetID: String
    package var title: String
    package var detail: String
    package var courseID: String?
    package var keywords: String = ""
    package var id: String { category.rawValue + ":" + (courseID ?? "") + ":" + targetID }
}

/// A transient index of the complete snapshot, independent of the visible page.
/// Journal entries and note bodies are deliberately excluded.
package struct SearchIndex {
    package let entries: [SearchResult]

    package init(state: Snapshot) {
        var items: [SearchResult] = []
        func add(_ category: SearchCategory, _ id: String, _ title: String, _ detail: String, _ courseID: String? = nil, _ keywords: String = "") {
            items.append(SearchResult(category: category, targetID: id, title: title, detail: detail, courseID: courseID, keywords: keywords))
        }
        func list(_ id: String?) -> String { state.courses.first { $0.id == id }?.name ?? "Inbox" }
        for (id, title) in [("today", "Today"), ("all", "Tasks"), ("inbox", "Inbox"), ("journal", "Journal"), ("upcoming", "Calendar"), ("schedule", "Schedule"), ("routines", "Rhythm")] {
            add(.pages, id, title, "Open page")
        }
        for course in state.courses {
            add(.lists, course.id, course.name, "Open list", course.id)
            for note in course.listNotes {
                // Only index the name, never the markdown body.
                let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
                add(.notes, note.id, title.isEmpty ? "Untitled note" : title, course.name, course.id)
            }
        }
        for task in state.tasks {
            let completed = task.kind == .progress ? task.isProgressComplete : task.completed
            let detail = [list(task.courseID), task.calendarDay ?? "", completed ? "Completed" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
            add(task.kind == .progress ? .progress : .tasks, task.id, task.title, detail, task.courseID, task.notes)
        }
        for item in state.assessments {
            add(.assessments, item.id, item.title, list(item.courseID) + " · " + item.day, item.courseID, item.topics)
        }
        for rule in state.rules {
            add(.rhythms, rule.id, rule.title, list(rule.courseID) + " · " + rule.compactPattern, rule.courseID)
        }
        for block in state.schedule {
            add(.schedule, block.id, block.title, list(block.courseID) + " · " + block.day, block.courseID, block.notes)
        }
        entries = items
    }

    package func search(_ query: String, category: SearchCategory? = nil) -> [SearchResult] {
        let normalized = Self.normalize(query).trimmingCharacters(in: .whitespacesAndNewlines)
        let words = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return entries.filter { item in
            guard category == nil || item.category == category else { return false }
            let text = Self.normalize(item.title + " " + item.detail + " " + item.keywords)
            return words.allSatisfy { text.contains($0) }
        }.sorted { lhs, rhs in
            func rank(_ item: SearchResult) -> Int {
                let title = Self.normalize(item.title)
                if title == normalized { return 0 }
                if !normalized.isEmpty && title.hasPrefix(normalized) { return 1 }
                if !normalized.isEmpty && title.contains(normalized) { return 2 }
                return 3
            }
            if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
            if lhs.category != rhs.category {
                return SearchCategory.allCases.firstIndex(of: lhs.category)! < SearchCategory.allCases.firstIndex(of: rhs.category)!
            }
            if lhs.title != rhs.title { return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending }
            if lhs.detail != rhs.detail { return lhs.detail < rhs.detail }
            return lhs.id < rhs.id
        }
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
