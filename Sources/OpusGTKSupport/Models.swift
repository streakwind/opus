import Foundation
import OpusCore

package enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case today, all, inbox, archive, calendar, schedule, rhythm
    package var id: String { rawValue }
    package var title: String {
        switch self {
        case .today: "Today"
        case .all: "Tasks"
        case .inbox: "Inbox"
        case .archive: "Archive"
        case .calendar: "Calendar"
        case .schedule: "Schedule"
        case .rhythm: "Rhythm"
        }
    }
}

package enum NavigationSelection: Equatable, Sendable {
    case section(AppSection)
    case list(String)

    package var id: String {
        switch self {
        case .section(let section): section.rawValue
        case .list(let id): "list:" + id
        }
    }
    package var courseID: String? {
        if case .list(let id) = self { return id }
        return nil
    }
    package var section: AppSection? {
        if case .section(let section) = self { return section }
        return nil
    }
    package static func parse(_ id: String) -> NavigationSelection {
        if id.hasPrefix("list:") { return .list(String(id.dropFirst(5))) }
        return .section(AppSection(rawValue: id) ?? .today)
    }
}

package enum CalendarPeriod: String, CaseIterable, Identifiable, Sendable {
    case day, week, month
    package var id: String { rawValue }
}

package enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    package var id: String { rawValue }
    package var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

package enum WorkRowKind: String, Sendable {
    case task, progress, assessment
}

package struct WorkRow: Equatable, Identifiable, Sendable {
    package var id: String
    package var kind: WorkRowKind
    package var title: String
    package var detail: String
    package var completed: Bool
    package var progress: Bool
    package var start: Int
    package var target: Int
    package var current: Int
    package var confirmed: Bool
    package var courseID: String?
    package var day: String?
    package var color: String
    package var markNext: Bool
}

package struct NavItem: Equatable, Identifiable, Sendable {
    package var id: String
    package var title: String
    package var selected: Bool
    package var color: String?
    package var separatorBefore: Bool
}

package struct CalendarDayModel: Equatable, Identifiable, Sendable {
    package var id: String { day }
    package var day: String
    package var label: String
    package var inMonth: Bool
    package var isToday: Bool
    package var isSelected: Bool
    package var items: [WorkRow]
}

package struct ScheduleBlockModel: Equatable, Identifiable, Sendable {
    package var id: String
    package var title: String
    package var detail: String
    package var day: String
    package var startMinute: Int
    package var duration: Int
    package var column: Int
    package var columns: Int
    package var color: String
    package var isClass: Bool
    package var courseID: String?
    package var ruleID: String?
}

package struct RhythmRow: Equatable, Identifiable, Sendable {
    package var id: String
    package var title: String
    package var detail: String
    package var enabled: Bool
    package var color: String
    package var kind: String
}

package struct QuickStartPage: Equatable, Sendable {
    package var title: String
    package var text: String
}

package enum QuickStart {
    package static let pages: [QuickStartPage] = [
        QuickStartPage(title: "Capture a task", text: "Press Ctrl+N or use Add a task, type a title, and press Return. Inbox holds tasks that do not belong to a list."),
        QuickStartPage(title: "Plan your work", text: "Create your own lists from the sidebar. Today brings together upcoming and overdue work. Open a task to change its list or dates; use its checkbox when it is done."),
        QuickStartPage(title: "Track textbook notes", text: "Choose Progress when creating a task. Set the page range, then enter your last-read page as you work. Open the task for its pace suggestion."),
        QuickStartPage(title: "Use the calendars", text: "Calendar shows dated tasks and assessments. Click a day to add an item. Schedule is for timed events and class blocks; configure class times by editing a list."),
        QuickStartPage(title: "Repeat only what you need", text: "Rhythm repeats work on the days you choose. Create a rule, select its days, and adjust or remove it whenever your routine changes.")
    ]
}
