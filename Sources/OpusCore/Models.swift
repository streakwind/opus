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
    /// Kept for stored data compatibility; assessments are always treated as confirmed.
    package var confirmed = true
    package var topics = ""
    package var ruleID: String?
    package var occurrence: String?
    package init(id: String = UUID().uuidString, courseID: String? = nil, title: String = "", day: String = Day.today, confirmed: Bool = true, topics: String = "", ruleID: String? = nil, occurrence: String? = nil) {
        self.id = id
        self.courseID = courseID
        self.title = title
        self.day = day
        self.confirmed = true
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
    package var confirmsAssessments: Bool { true }
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
    package var allDay: Bool?
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
    package init(id: String = UUID().uuidString, courseID: String? = nil, title: String = "", weekday: Int = 4, enabled: Bool = true, assessmentsConfirmed: Bool? = nil, weekdays: [Int]? = nil, itemKind: RepeatItem? = nil, intervalWeeks: Int? = nil, startDate: String? = nil, endDate: String? = nil, taskKind: TaskKind? = nil, startCount: Int? = nil, targetCount: Int? = nil, startMinute: Int? = nil, duration: Int? = nil, allDay: Bool? = nil, notes: String? = nil) {
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
        self.allDay = allDay
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
    /// Optional so databases written before all-day events remain decodable.
    package var allDay: Bool?
    package var notes = ""
    package var ruleID: String?
    package var occurrence: String?
    package var endMinute: Int {
        get { min(1440, startMinute + duration) }
        set { duration = max(15, min(1440, newValue) - startMinute) }
    }
    package var isAllDay: Bool { allDay == true }
    package var timeLabel: String { ClockTime.label(startMinute) + "–" + ClockTime.label(startMinute + duration) }
    package init(id: String = UUID().uuidString, courseID: String? = nil, title: String = "", day: String = Day.today, startMinute: Int = 9 * 60, duration: Int = 60, allDay: Bool = false, notes: String = "", ruleID: String? = nil, occurrence: String? = nil) {
        self.id = id
        self.courseID = courseID
        self.title = title
        self.day = day
        self.startMinute = startMinute
        self.duration = duration
        self.allDay = allDay ? true : nil
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
package enum JournalLink: Codable, Equatable, Hashable {
    case task(String)
    case assessment(String)
    case rhythm(String)
    case schedule(String)

    package var token: String {
        switch self {
        case .task(let id): "task:" + id
        case .assessment(let id): "assessment:" + id
        case .rhythm(let id): "rhythm:" + id
        case .schedule(let id): "schedule:" + id
        }
    }
    package static func from(token: String?) -> JournalLink? {
        guard let token, let separator = token.firstIndex(of: ":") else { return nil }
        let kind = String(token[..<separator])
        let id = String(token[token.index(after: separator)...])
        switch kind {
        case "task": return .task(id)
        case "assessment": return .assessment(id)
        case "rhythm": return .rhythm(id)
        case "schedule": return .schedule(id)
        default: return nil
        }
    }
    package var embedToken: String { "![[" + token + "]]" }
    package static func fromEmbedToken(_ string: String) -> JournalLink? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("![["), trimmed.hasSuffix("]]") else { return nil }
        return from(token: String(trimmed.dropFirst(3).dropLast(2)))
    }
}

package enum JournalBlock: Equatable {
    case text(String)
    case embed(JournalLink)
}

package enum JournalMarkdown {
    private static let tokenPattern = #"!\[\[(task|assessment|rhythm|schedule):([^\]]+)\]\]"#

    package static func blocks(from markdown: String) -> [JournalBlock] {
        guard let expression = try? NSRegularExpression(pattern: tokenPattern) else {
            return [.text(markdown)]
        }
        let source = markdown as NSString
        let full = NSRange(location: 0, length: source.length)
        var blocks: [JournalBlock] = []
        var cursor = 0
        for match in expression.matches(in: markdown, range: full) {
            let text = source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            blocks.append(.text(text))
            if let link = JournalLink.fromEmbedToken(source.substring(with: match.range)) {
                blocks.append(.embed(link))
            }
            cursor = NSMaxRange(match.range)
        }
        let tail = cursor < source.length ? source.substring(from: cursor) : ""
        blocks.append(.text(tail))
        if blocks.isEmpty { blocks.append(.text("")) }
        return blocks
    }
    package static func markdown(from blocks: [JournalBlock]) -> String {
        blocks.map { block in
            switch block {
            case .text(let text): text
            case .embed(let link): link.embedToken
            }
        }.joined()
    }
    package static func links(in markdown: String) -> Set<JournalLink> {
        Set(blocks(from: markdown).compactMap { if case .embed(let link) = $0 { link } else { nil } })
    }
    package static func placingCarriedEmbeds(in markdown: String, links: [JournalLink]) -> String {
        let missing = links.filter { !markdown.contains($0.embedToken) }
        guard !missing.isEmpty else { return markdown }
        let prefix = missing.map(\.embedToken).joined(separator: "\n")
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? prefix : prefix + "\n\n" + markdown
    }
    package static func removing(_ token: String, from markdown: String) -> String {
        markdown.replacingOccurrences(of: token, with: "").replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }
    package static func inserting(_ token: String, into markdown: String, at caret: Int) -> String {
        let source = markdown as NSString
        let location = max(0, min(caret, source.length))
        let before = source.substring(to: location)
        let after = source.substring(from: location)
        let prefix = before.isEmpty || before.hasSuffix("\n") ? "" : "\n"
        let suffix = after.isEmpty || after.hasPrefix("\n") ? "" : "\n"
        return before + prefix + token + suffix + after
    }
}
package struct JournalEntry: Identifiable, Codable, Equatable {
    package var id = UUID().uuidString
    /// First day this note appears.
    package var day = Day.today
    package var title = "Untitled"
    package var markdown = ""
    package var link: JournalLink?
    /// Last day a linked note appears. Ordinary entries use their own day.
    package var throughDay: String?
    /// Embeds explicitly removed from this day, so carrying work cannot reinsert them.
    package var omittedEmbeds: [JournalLink]?

    package init(id: String = UUID().uuidString, day: String = Day.today, title: String = "Untitled", markdown: String = "", link: JournalLink? = nil, throughDay: String? = nil) {
        self.id = id
        self.day = day
        self.title = title
        self.markdown = markdown
        self.link = link
        self.throughDay = throughDay
    }
    package func appears(on selectedDay: String) -> Bool {
        guard link != nil else { return day == selectedDay }
        return selectedDay >= day && selectedDay <= (throughDay ?? day)
    }
}
package struct Snapshot: Codable {
    package var courses: [Course] = []
    package var tasks: [StudyTask] = []
    package var assessments: [Assessment] = []
    package var rules: [QuizRule] = []
    package var schedule: [ScheduleBlock] = []
    package var activities: [Activity] = []
    package var journal: [JournalEntry] = []
    // Occurrence keys survive deletion so skipped quizzes never regenerate.
    package var generated: Set<String> = []
    package var setupComplete = false
    package init(courses: [Course] = [], tasks: [StudyTask] = [], assessments: [Assessment] = [], rules: [QuizRule] = [], schedule: [ScheduleBlock] = [], activities: [Activity] = [], journal: [JournalEntry] = [], generated: Set<String> = [], setupComplete: Bool = false) {
        self.courses = courses
        self.tasks = tasks
        self.assessments = assessments
        self.rules = rules
        self.schedule = schedule
        self.activities = activities
        self.journal = journal
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

package struct JournalEmbedOption: Identifiable, Equatable {
    package var title: String
    package var detail: String
    package var icon: String
    package var courseID: String?
    package var link: JournalLink
    package var id: String { link.token }
}

package enum JournalWork {
    package static func embedOptions(in state: Snapshot, from day: String = Day.today) -> [JournalEmbedOption] {
        var options: [JournalEmbedOption] = []
        var seenTaskRules = Set<String>()
        let tasks = state.tasks
            .filter { $0.kind == .progress ? $0.current < $0.target : !$0.completed }
            .sorted {
                let left = $0.calendarDay ?? "9999"
                let right = $1.calendarDay ?? "9999"
                return left == right ? $0.title < $1.title : left < right
            }
        for task in tasks {
            if let ruleID = task.ruleID, !seenTaskRules.insert(ruleID).inserted { continue }
            var parts = [state.courses.first { $0.id == task.courseID }?.name ?? "Inbox"]
            if let due = task.due { parts.append("Due " + Day.label(due)) }
            if task.kind == .progress { parts.append(task.progressLabel) }
            if task.ruleID != nil { parts.append("Rhythm") }
            options.append(JournalEmbedOption(
                title: task.title,
                detail: parts.joined(separator: " · "),
                icon: task.kind == .progress ? "chart.bar.fill" : "circle",
                courseID: task.courseID,
                link: .task(task.id)
            ))
        }
        var seenAssessmentRules = Set<String>()
        let assessments = state.assessments
            .filter { $0.day >= day }
            .sorted { $0.day == $1.day ? $0.title < $1.title : $0.day < $1.day }
        for item in assessments {
            if let ruleID = item.ruleID, !seenAssessmentRules.insert(ruleID).inserted { continue }
            var parts = [state.courses.first { $0.id == item.courseID }?.name ?? "Inbox", Day.label(item.day)]
            if item.ruleID != nil { parts.append("Rhythm") }
            options.append(JournalEmbedOption(
                title: item.title,
                detail: parts.joined(separator: " · "),
                icon: "calendar",
                courseID: item.courseID,
                link: .assessment(item.id)
            ))
        }
        return options
    }
}

package enum ScheduleWork {
    package static func isUntimed(courseID: String?, on day: String, in state: Snapshot) -> Bool {
        guard let courseID else { return true }
        return state.courses.first { $0.id == courseID }?.classBlocks(on: day).isEmpty != false
    }
    package static func untimedTasks(on day: String, in state: Snapshot) -> [StudyTask] {
        state.tasks.filter { $0.calendarDay == day && isUntimed(courseID: $0.courseID, on: day, in: state) }
    }
    package static func untimedAssessments(on day: String, in state: Snapshot) -> [Assessment] {
        state.assessments.filter { $0.day == day && isUntimed(courseID: $0.courseID, on: day, in: state) }
    }
    package static func untimedEvents(on day: String, in state: Snapshot) -> [ScheduleBlock] {
        state.schedule.filter { $0.isAllDay && $0.day == day && isUntimed(courseID: $0.courseID, on: day, in: state) }
    }
    package static func listedEvents(courseID: String, on day: String, in state: Snapshot) -> [ScheduleBlock] {
        state.schedule.filter { $0.courseID == courseID && $0.isAllDay && $0.day == day }
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
        let week = Day.adding(7, to: today)
        if kind == .progress {
            guard current < target else { return false }
            guard ruleID != nil else { return true }
            guard let date = due ?? planned else { return true }
            return date >= today
        }
        guard !completed else { return false }
        guard let due else { return true }
        if ruleID != nil { return due >= today && due <= week }
        return due <= week
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
