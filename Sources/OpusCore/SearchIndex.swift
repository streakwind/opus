import Foundation

package enum SearchCategory: String, CaseIterable, Identifiable {
    case pages = "Pages", lists = "Lists", tasks = "Tasks", progress = "Progress"
    case assessments = "Assessments", notes = "Notes", rhythms = "Rhythms"
    package var id: String { rawValue }
    package var icon: String {
        switch self {
        case .pages: "doc.text"
        case .lists: "folder"
        case .tasks: "checkmark.circle"
        case .progress: "chart.bar"
        case .assessments: "calendar"
        case .notes: "note.text"
        case .rhythms: "repeat"
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
    package var dueDay: String? = nil
    package var listName: String = ""
    package var id: String { category.rawValue + ":" + (courseID ?? "") + ":" + targetID }
}

package enum SearchSort: String, CaseIterable, Identifiable {
    case name = "Name", dueDate = "Due date", list = "List"
    package var id: String { rawValue }
}

/// A search snapshot excluding schedule, journal bodies, and later rhythm occurrences.
package struct SearchIndex {
    package let entries: [SearchResult]

    package init(state: Snapshot, today: String = Day.today) {
        var items: [SearchResult] = []
        func add(_ category: SearchCategory, _ id: String, _ title: String, _ detail: String, _ courseID: String? = nil, _ keywords: String = "", _ dueDay: String? = nil) {
            items.append(SearchResult(category: category, targetID: id, title: title, detail: detail, courseID: courseID, keywords: keywords, dueDay: dueDay, listName: list(courseID)))
        }
        func list(_ id: String?) -> String { state.courses.first { $0.id == id }?.name ?? "Inbox" }
        for (id, title) in [("today", "Today"), ("all", "Tasks"), ("inbox", "Inbox"), ("journal", "Journal"), ("upcoming", "Calendar"), ("routines", "Rhythm")] {
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
        var nextTasks: [String: StudyTask] = [:]
        for task in state.tasks where task.ruleID != nil {
            guard !(task.kind == .progress ? task.isProgressComplete : task.completed) else { continue }
            let key = task.ruleID!
            let day = task.calendarDay ?? task.occurrence ?? "9999"
            if let previous = nextTasks[key], (previous.calendarDay ?? previous.occurrence ?? "9999", previous.id) <= (day, task.id) { continue }
            nextTasks[key] = task
        }
        for task in state.tasks {
            if let rule = task.ruleID, nextTasks[rule]?.id != task.id { continue }
            let detail = [list(task.courseID), task.dateCaption() ?? task.calendarDay ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
            add(task.kind == .progress ? .progress : .tasks, task.id, task.title, detail, task.courseID, task.notes, task.due ?? task.planned)
        }
        var nextAssessments: [String: Assessment] = [:]
        for item in state.assessments where item.ruleID != nil && item.day >= today {
            let key = item.ruleID!
            if let previous = nextAssessments[key], (previous.day, previous.id) <= (item.day, item.id) { continue }
            nextAssessments[key] = item
        }
        for item in state.assessments {
            if let rule = item.ruleID, nextAssessments[rule]?.id != item.id { continue }
            add(.assessments, item.id, item.title, list(item.courseID) + " · " + item.day, item.courseID, item.topics, item.day)
        }
        for rule in state.rules {
            add(.rhythms, rule.id, rule.title, list(rule.courseID) + " · " + rule.compactPattern, rule.courseID)
        }
        entries = items
    }

    package func search(_ query: String, category: SearchCategory? = nil, sort: SearchSort? = nil) -> [SearchResult] {
        let normalized = Self.normalize(query).trimmingCharacters(in: .whitespacesAndNewlines)
        let words = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return entries.filter { item in
            guard category == nil || item.category == category else { return false }
            let text = Self.normalize(item.title + " " + item.detail + " " + item.keywords)
            return words.allSatisfy { text.contains($0) }
        }.sorted { lhs, rhs in
            if sort == .dueDate && lhs.dueDay != rhs.dueDay { return (lhs.dueDay ?? "9999") < (rhs.dueDay ?? "9999") }
            if sort == .list && lhs.listName != rhs.listName { return lhs.listName.localizedStandardCompare(rhs.listName) == .orderedAscending }
            if sort != nil && lhs.title != rhs.title { return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending }
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
