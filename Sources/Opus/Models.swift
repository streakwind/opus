import Foundation

struct Course: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var name: String
    var color: String = "blue"
}

enum TaskKind: String, CaseIterable, Codable, Identifiable {
    case checkbox = "Task", progress = "Progress", practice = "Practice"
    var id: String { rawValue }
}
struct StudyTask: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var courseID: String?
    var title = ""
    var notes = ""
    var kind: TaskKind = .checkbox
    var planned: String?
    var due: String?
    var completed = false
    var start = 1
    var target = 30
    var current = 0
    var unit = "pages"
    var ruleID: String?
    var occurrence: String?
    var fraction: Double { min(1, max(0, Double(current - start + 1) / Double(max(1, target - start + 1)))) }
    var progressLabel: String { "\(max(0, current - start + 1)) of \(target - start + 1) \(unit)" }
}
struct Assessment: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var courseID: String?
    var title = ""
    var day = Day.today
    var confirmed = false
    var topics = ""
    var ruleID: String?
    var occurrence: String?
}
struct QuizRule: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var courseID: String?
    var title = ""
    var weekday = 4
    var enabled = true
    // Optional additions keep version-one rules readable without altering their meaning.
    var weekdays: [Int]?
    var itemKind: RepeatItem?
    var intervalWeeks: Int?
    var startDate: String?
    var endDate: String?
    var taskKind: TaskKind?
    var targetCount: Int?
    var startMinute: Int?
    var duration: Int?
    var notes: String?
    var days: Set<Int> { Set(weekdays ?? [weekday]) }
    var kind: RepeatItem { itemKind ?? .assessment }
    var summary: String {
        let names = Calendar.current.shortWeekdaySymbols
        let sorted = days.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }
        let pattern = days.count == 7 ? "Every day" : days == Set(2...6) ? "Weekdays" : sorted.map { names[$0 - 1] }.joined(separator: ", ")
        return pattern + ((intervalWeeks ?? 1) > 1 ? " · Every \(intervalWeeks!) weeks" : "")
    }
    func occurs(on day: String) -> Bool {
        guard enabled, days.contains(Calendar.current.component(.weekday, from: Day.date(day))), day >= (startDate ?? "0000"), day <= (endDate ?? "9999") else { return false }
        let interval = max(1, intervalWeeks ?? 1)
        guard interval > 1, let startDate else { return true }
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: Day.date(startDate))!.start
        let current = calendar.dateInterval(of: .weekOfYear, for: Day.date(day))!.start
        return (calendar.dateComponents([.day], from: start, to: current).day! / 7) % interval == 0
    }
}
enum RepeatItem: String, Codable, CaseIterable, Identifiable {
    case task = "Task", assessment = "Assessment", schedule = "Schedule"
    var id: String { rawValue }
}
struct ScheduleBlock: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var courseID: String?
    var title = ""
    var day = Day.today
    var startMinute = 9 * 60
    var duration = 60
    var notes = ""
    var ruleID: String?
    var occurrence: String?
    var timeLabel: String { ClockTime.label(startMinute) + "–" + ClockTime.label(startMinute + duration) }
}
enum ClockTime {
    static func label(_ minutes: Int) -> String {
        let hour = (minutes / 60) % 24
        return String(format: "%d:%02d %@", hour % 12 == 0 ? 12 : hour % 12, minutes % 60, hour < 12 ? "AM" : "PM")
    }
    static func date(_ minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: min(23, minutes / 60), minute: minutes % 60, second: 0, of: Day.date(Day.today))!
    }
    static func minutes(_ date: Date) -> Int {
        Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
    }
}
struct Activity: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var taskID: String
    var date = Date()
    var note: String
    var previous: Int?
    var value: Int?
}
struct Snapshot: Codable {
    var courses: [Course] = []
    var tasks: [StudyTask] = []
    var assessments: [Assessment] = []
    var rules: [QuizRule] = []
    var schedule: [ScheduleBlock] = []
    var activities: [Activity] = []
    // Occurrence keys survive deletion so skipped quizzes never regenerate.
    var generated: Set<String> = []
    var setupComplete = false
}

enum Day {
    static func string(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }
    static func date(_ string: String) -> Date {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) ?? Date()
    }
    static var today: String { string(Date()) }
    static func adding(_ count: Int, to day: String = today) -> String {
        string(Calendar.current.date(byAdding: .day, value: count, to: date(day))!)
    }
    static func label(_ day: String) -> String {
        if day == today { return "Today" }
        if day == adding(1) { return "Tomorrow" }
        return date(day).formatted(.dateTime.month(.abbreviated).day())
    }
}

extension StudyTask {
    static func merging(draft: StudyTask, baseline: StudyTask, latest: StudyTask) -> StudyTask {
        var result = latest
        if draft.title != baseline.title { result.title = draft.title }
        if draft.notes != baseline.notes { result.notes = draft.notes }
        if draft.courseID != baseline.courseID { result.courseID = draft.courseID }
        if draft.planned != baseline.planned { result.planned = draft.planned }
        if draft.due != baseline.due { result.due = draft.due }
        if draft.kind != baseline.kind { result.kind = draft.kind }
        if draft.start != baseline.start { result.start = draft.start }
        if draft.target != baseline.target { result.target = draft.target }
        if draft.current != baseline.current { result.current = draft.current }
        if draft.unit != baseline.unit { result.unit = draft.unit }
        if draft.completed != baseline.completed { result.completed = draft.completed }
        return result
    }
}
