import Foundation

package struct ClassTime: Identifiable, Codable, Hashable {
    package var id = UUID().uuidString
    package var startMinute: Int
    package var endMinute: Int
    package var days: [Int] = Array(2...6)
    package init(id: String = UUID().uuidString, startMinute: Int, endMinute: Int, days: [Int] = Array(2...6)) {
        self.id = id
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.days = days
    }
}

package struct Course: Identifiable, Codable, Hashable {
    package var id = UUID().uuidString
    package var name: String
    package var color: String = "blue"
    package var classTimes: [ClassTime]?
    // Legacy fields remain readable and mirror the first class time on save.
    package var classStart: Int?
    package var classDuration: Int?
    package var classDays: [Int]?
    package var resolvedClassTimes: [ClassTime] {
        if let classTimes { return classTimes }
        guard let classStart else { return [] }
        return [ClassTime(id: "legacy", startMinute: classStart, endMinute: min(1440, classStart + (classDuration ?? 50)), days: classDays ?? Array(2...6))]
    }
    package func classBlocks(on day: String) -> [ScheduleBlock] {
        let weekday = Calendar.current.component(.weekday, from: Day.date(day))
        return resolvedClassTimes.filter { $0.days.contains(weekday) && $0.startMinute >= 0 && $0.startMinute < 1440 && $0.endMinute > $0.startMinute }.map { time in
            ScheduleBlock(id: "class:\(id):\(time.id):\(day)", courseID: id, title: name, day: day, startMinute: time.startMinute, duration: min(1440, time.endMinute) - time.startMinute)
        }
    }
    package func classBlock(on day: String) -> ScheduleBlock? { classBlocks(on: day).first }
    package mutating func syncLegacyClassTime() {
        guard let classTimes else { return }
        if let first = classTimes.first {
            classStart = first.startMinute
            classDuration = first.endMinute - first.startMinute
            classDays = first.days
        } else {
            classStart = nil
            classDuration = nil
            classDays = nil
        }
    }
    package init(id: String = UUID().uuidString, name: String, color: String = "blue", classTimes: [ClassTime]? = nil, classStart: Int? = nil, classDuration: Int? = nil, classDays: [Int]? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.classTimes = classTimes
        self.classStart = classStart
        self.classDuration = classDuration
        self.classDays = classDays
    }
}

package enum TaskKind: String, CaseIterable, Codable, Identifiable {
    case checkbox = "Task", progress = "Progress", practice = "Practice"
    package var id: String { rawValue }
}
package struct StudyTask: Identifiable, Codable, Equatable {
    package var id = UUID().uuidString
    package var courseID: String?
    package var title = ""
    package var notes = ""
    package var kind: TaskKind = .checkbox
    package var planned: String?
    package var due: String?
    package var completed = false
    package var start = 1
    package var target = 30
    package var current = 0
    package var unit = "pages"
    package var ruleID: String?
    package var occurrence: String?
    package var fraction: Double { min(1, max(0, Double(current - start + 1) / Double(max(1, target - start + 1)))) }
    package var progressLabel: String { "\(max(0, current - start + 1)) of \(target - start + 1) \(unit)" }
    package init(id: String = UUID().uuidString, courseID: String? = nil, title: String = "", notes: String = "", kind: TaskKind = .checkbox, planned: String? = nil, due: String? = nil, completed: Bool = false, start: Int = 1, target: Int = 30, current: Int = 0, unit: String = "pages", ruleID: String? = nil, occurrence: String? = nil) {
        self.id = id
        self.courseID = courseID
        self.title = title
        self.notes = notes
        self.kind = kind
        self.planned = planned
        self.due = due
        self.completed = completed
        self.start = start
        self.target = target
        self.current = current
        self.unit = unit
        self.ruleID = ruleID
        self.occurrence = occurrence
    }
}
package struct Assessment: Identifiable, Codable, Equatable {
    package var id = UUID().uuidString
    package var courseID: String?
    package var title = ""
    package var day = Day.today
    package var confirmed = false
    package var topics = ""
    package var ruleID: String?
    package var occurrence: String?
    package init(id: String = UUID().uuidString, courseID: String? = nil, title: String = "", day: String = Day.today, confirmed: Bool = false, topics: String = "", ruleID: String? = nil, occurrence: String? = nil) {
        self.id = id
        self.courseID = courseID
        self.title = title
        self.day = day
        self.confirmed = confirmed
        self.topics = topics
        self.ruleID = ruleID
        self.occurrence = occurrence
    }
}
package struct QuizRule: Identifiable, Codable, Equatable {
    package var id = UUID().uuidString
    package var courseID: String?
    package var title = ""
    package var weekday = 4
    package var enabled = true
    // Optional additions keep version-one rules readable without altering their meaning.
    package var assessmentsConfirmed: Bool?
    package var confirmsAssessments: Bool { assessmentsConfirmed ?? false }
    package var weekdays: [Int]?
    package var itemKind: RepeatItem?
    package var intervalWeeks: Int?
    package var startDate: String?
    package var endDate: String?
    package var taskKind: TaskKind?
    package var startCount: Int?
    package var targetCount: Int?
    package var startMinute: Int?
    package var duration: Int?
    package var notes: String?
    package var days: Set<Int> { Set(weekdays ?? [weekday]) }
    package var kind: RepeatItem { itemKind ?? .assessment }
    package var workKind: WorkKind {
        get {
            if kind == .assessment { return .assessment }
            return taskKind == .progress ? .progress : .task
        }
        set {
            switch newValue {
            case .task:
                itemKind = .task
                taskKind = .checkbox
            case .progress:
                itemKind = .task
                taskKind = .progress
            case .assessment:
                itemKind = .assessment
                taskKind = nil
            }
        }
    }
    package var summary: String {
        let pattern = compactPattern
        var parts = [pattern]
        if (intervalWeeks ?? 1) > 1 { parts[0] = pattern + " · Every \(intervalWeeks!) weeks" }
        if let endDate { parts.append("ends " + Day.label(endDate)) }
        return parts.joined(separator: " · ")
    }
    package var compactPattern: String {
        let names = Calendar.current.shortWeekdaySymbols
        let sorted = days.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }
        if days.count == 7 { return "Every day" }
        if days == Set(2...6) { return "Weekdays" }
        return sorted.map { names[$0 - 1] }.joined(separator: ", ")
    }
    package var repeatsLabel: String { "Repeats " + compactPattern }
    package func occurs(on day: String) -> Bool {
        guard enabled, days.contains(Calendar.current.component(.weekday, from: Day.date(day))), day >= (startDate ?? "0000"), day <= (endDate ?? "9999") else { return false }
        let interval = max(1, intervalWeeks ?? 1)
        guard interval > 1, let startDate else { return true }
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: Day.date(startDate))!.start
        let current = calendar.dateInterval(of: .weekOfYear, for: Day.date(day))!.start
        return (calendar.dateComponents([.day], from: start, to: current).day! / 7) % interval == 0
    }
    package init(id: String = UUID().uuidString, courseID: String? = nil, title: String = "", weekday: Int = 4, enabled: Bool = true, assessmentsConfirmed: Bool? = nil, weekdays: [Int]? = nil, itemKind: RepeatItem? = nil, intervalWeeks: Int? = nil, startDate: String? = nil, endDate: String? = nil, taskKind: TaskKind? = nil, startCount: Int? = nil, targetCount: Int? = nil, startMinute: Int? = nil, duration: Int? = nil, notes: String? = nil) {
        self.id = id
        self.courseID = courseID
        self.title = title
        self.weekday = weekday
        self.enabled = enabled
        self.assessmentsConfirmed = assessmentsConfirmed
        self.weekdays = weekdays
        self.itemKind = itemKind
        self.intervalWeeks = intervalWeeks
        self.startDate = startDate
        self.endDate = endDate
        self.taskKind = taskKind
        self.startCount = startCount
        self.targetCount = targetCount
        self.startMinute = startMinute
        self.duration = duration
        self.notes = notes
    }
}
package enum RepeatItem: String, Codable, CaseIterable, Identifiable {
    case task = "Task", assessment = "Assessment", schedule = "Schedule"
    package var id: String { rawValue }
}
package struct ScheduleBlock: Identifiable, Codable, Equatable {
    package var id = UUID().uuidString
    package var courseID: String?
    package var title = ""
    package var day = Day.today
    package var startMinute = 9 * 60
    package var duration = 60
    package var notes = ""
    package var ruleID: String?
    package var occurrence: String?
    package var endMinute: Int {
        get { min(1440, startMinute + duration) }
        set { duration = max(15, min(1440, newValue) - startMinute) }
    }
    package var timeLabel: String { ClockTime.label(startMinute) + "–" + ClockTime.label(startMinute + duration) }
    package init(id: String = UUID().uuidString, courseID: String? = nil, title: String = "", day: String = Day.today, startMinute: Int = 9 * 60, duration: Int = 60, notes: String = "", ruleID: String? = nil, occurrence: String? = nil) {
        self.id = id
        self.courseID = courseID
        self.title = title
        self.day = day
        self.startMinute = startMinute
        self.duration = duration
        self.notes = notes
        self.ruleID = ruleID
        self.occurrence = occurrence
    }
}
package enum ClockTime {
    package static func label(_ minutes: Int) -> String {
        let hour = (minutes / 60) % 24
        return String(format: "%d:%02d %@", hour % 12 == 0 ? 12 : hour % 12, minutes % 60, hour < 12 ? "AM" : "PM")
    }
    package static func date(_ minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: min(23, minutes / 60), minute: minutes % 60, second: 0, of: Day.date(Day.today))!
    }
    package static func minutes(_ date: Date) -> Int {
        Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
    }
}
package struct Activity: Identifiable, Codable, Equatable {
    package var id = UUID().uuidString
    package var taskID: String
    package var date = Date()
    package var note: String
    package var previous: Int?
    package var value: Int?
    package init(id: String = UUID().uuidString, taskID: String, date: Date = Date(), note: String, previous: Int? = nil, value: Int? = nil) {
        self.id = id
        self.taskID = taskID
        self.date = date
        self.note = note
        self.previous = previous
        self.value = value
    }
}
package struct Snapshot: Codable {
    package var courses: [Course] = []
    package var tasks: [StudyTask] = []
    package var assessments: [Assessment] = []
    package var rules: [QuizRule] = []
    package var schedule: [ScheduleBlock] = []
    package var activities: [Activity] = []
    // Occurrence keys survive deletion so skipped quizzes never regenerate.
    package var generated: Set<String> = []
    package var setupComplete = false
    package init(courses: [Course] = [], tasks: [StudyTask] = [], assessments: [Assessment] = [], rules: [QuizRule] = [], schedule: [ScheduleBlock] = [], activities: [Activity] = [], generated: Set<String> = [], setupComplete: Bool = false) {
        self.courses = courses
        self.tasks = tasks
        self.assessments = assessments
        self.rules = rules
        self.schedule = schedule
        self.activities = activities
        self.generated = generated
        self.setupComplete = setupComplete
    }
}

package enum CourseWork {
    package static func relevantDay(for task: StudyTask, from day: String) -> String? {
        guard let calendarDay = task.calendarDay, calendarDay >= day else { return nil }
        return calendarDay
    }
    package static func assessments(courseID: String, from day: String, in state: Snapshot) -> [Assessment] {
        var seenRules = Set<String>()
        return state.assessments
            .filter { $0.courseID == courseID && $0.day >= day }
            .sorted { $0.day == $1.day ? $0.title < $1.title : $0.day < $1.day }
            .filter { item in
                guard let ruleID = item.ruleID else { return true }
                return seenRules.insert(ruleID).inserted
            }
    }
    package static func tasks(courseID: String, from day: String, in state: Snapshot, progress: Bool, exactDay: Bool = false) -> [StudyTask] {
        var seenRules = Set<String>()
        return state.tasks
            .filter {
                $0.courseID == courseID &&
                ($0.kind == .progress) == progress &&
                (progress || !$0.completed) &&
                relevantDay(for: $0, from: day).map { !exactDay || $0 == day } == true
            }
            .sorted {
                let lhs = relevantDay(for: $0, from: day) ?? "9999"
                let rhs = relevantDay(for: $1, from: day) ?? "9999"
                return lhs == rhs ? $0.title < $1.title : lhs < rhs
            }
            .filter { item in
                guard let ruleID = item.ruleID else { return true }
                return seenRules.insert(ruleID).inserted
            }
    }
}

package enum Day {
    package static func string(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }
    package static func date(_ string: String) -> Date {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) ?? Date()
    }
    package static var today: String { string(Date()) }
    package static func adding(_ count: Int, to day: String = today) -> String {
        string(Calendar.current.date(byAdding: .day, value: count, to: date(day))!)
    }
    package static func label(_ day: String) -> String {
        if day == today { return "Today" }
        if day == adding(1) { return "Tomorrow" }
        return date(day).formatted(.dateTime.month(.abbreviated).day())
    }
}

extension StudyTask {
    /// One calendar day for placement: due wins; otherwise planned.
    package var calendarDay: String? {
        if kind == .progress { return due }
        return due ?? planned
    }
    package mutating func moveCalendarDay(to day: String) {
        if kind == .progress || due != nil {
            due = day
            planned = nil
        } else {
            planned = day
        }
    }
    package static func merging(draft: StudyTask, baseline: StudyTask, latest: StudyTask) -> StudyTask {
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


extension StudyTask {
    /// Recalculate a realistic daily quota from the actual stopping point.
    package func pacing(on today: String) -> String? {
        guard kind == .progress, current < target else { return nil }
        guard let due else { return "Set a due date to plan your daily pace" }
        let remaining = target - max(start - 1, current)
        if due < today { return "Overdue · \(remaining) \(unit) left" }
        let days = max(1, (Calendar.current.dateComponents([.day], from: Day.date(today), to: Day.date(due)).day ?? 0) + 1)
        let quota = Int(ceil(Double(remaining) / Double(days)))
        let stop = min(target, max(start - 1, current) + quota)
        let goal = unit == "pages" ? "Read through page \(stop) today" : "Complete \(quota) \(unit) today"
        return "\(goal) · \(quota) \(unit)/day over \(days) \(days == 1 ? "day" : "days")"
    }
}


extension StudyTask {
    package func isInToday(on today: String) -> Bool {
        let tomorrow = Day.adding(1, to: today)
        if let due {
            if ruleID != nil { return due >= today && due <= tomorrow }
            return due <= tomorrow
        }
        if let planned {
            if ruleID != nil { return planned >= today && planned <= tomorrow }
            return planned <= tomorrow
        }
        return false
    }
    package func rhythmCaption(rule: QuizRule?, markNext: Bool) -> String? {
        guard ruleID != nil else { return nil }
        var parts: [String] = []
        if markNext && !completed { parts.append("Next") }
        if let due { parts.append("Due " + Day.label(due)) }
        else if let planned { parts.append(Day.label(planned)) }
        if let rule {
            parts.append(rule.repeatsLabel)
            if let end = rule.endDate { parts.append("ends " + Day.label(end)) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

package struct CalendarFocus: Equatable {
    package var id = UUID()
    package var day: String
    package init(id: UUID = UUID(), day: String) {
        self.id = id
        self.day = day
    }
}
