import SwiftUI

@MainActor @Observable
final class Store {
    var state: Snapshot
    var calendarFocus: CalendarFocus?
    var error: String?
    private let database: Database
    private var undoStates: [Snapshot] = []
    var canUndo: Bool { !undoStates.isEmpty }
    var location: URL { database.url }

    init(database: Database) throws {
        self.database = database
        state = try database.load()
        var needsSave = false
        let fixedRules = Set(state.rules.filter { $0.kind == .assessment && $0.title == "Example recurrence" && $0.assessmentsConfirmed == nil }.map(\.id))
        if !fixedRules.isEmpty {
            for index in state.rules.indices where fixedRules.contains(state.rules[index].id) { state.rules[index].assessmentsConfirmed = true }
            for index in state.assessments.indices where fixedRules.contains(state.assessments[index].ruleID ?? "") && state.assessments[index].day >= Day.today {
                state.assessments[index].confirmed = true
            }
            needsSave = true
        }
        for index in state.tasks.indices where state.tasks[index].kind == .progress && state.tasks[index].completed {
            state.tasks[index].completed = false
            needsSave = true
        }
        if needsSave { try database.save(state) }
        refreshOccurrences()
    }
    func change(_ mutation: (inout Snapshot) -> Void) {
        let previous = state
        var next = state
        mutation(&next)
        do {
            try database.save(next)
            error = nil
            undoStates.append(previous)
            if undoStates.count > 30 { undoStates.removeFirst() }
            state = next
        } catch { self.error = error.localizedDescription }
    }
    func undo() {
        guard let previous = undoStates.last else { return }
        do { try database.save(previous); state = previous; undoStates.removeLast() }
        catch { self.error = error.localizedDescription }
    }
    func course(_ id: String?) -> Course? { state.courses.first { $0.id == id } }
    func save(_ task: StudyTask) {
        change { state in
            if let index = state.tasks.firstIndex(where: { $0.id == task.id }) { state.tasks[index] = task }
            else { state.tasks.append(task) }
        }
    }
    func save(_ assessment: Assessment) {
        change { state in
            if let index = state.assessments.firstIndex(where: { $0.id == assessment.id }) { state.assessments[index] = assessment }
            else { state.assessments.append(assessment) }
        }
    }
    func save(_ course: Course) {
        var course = course
        course.syncLegacyClassTime()
        change { state in
            if let index = state.courses.firstIndex(where: { $0.id == course.id }) { state.courses[index] = course }
            else { state.courses.append(course) }
        }
    }
    func deleteCourse(_ id: String) {
        change { state in
            state.courses.removeAll { $0.id == id }
            for index in state.tasks.indices where state.tasks[index].courseID == id { state.tasks[index].courseID = nil }
            for index in state.assessments.indices where state.assessments[index].courseID == id { state.assessments[index].courseID = nil }
            for index in state.schedule.indices where state.schedule[index].courseID == id { state.schedule[index].courseID = nil }
            state.rules.removeAll { $0.courseID == id }
        }
    }
    func deleteTask(_ id: String) {
        change { state in
            state.tasks.removeAll { $0.id == id }
            state.activities.removeAll { $0.taskID == id }
        }
    }
    func record(_ task: StudyTask, value: Int?, note: String) {
        change { state in
            guard let index = state.tasks.firstIndex(where: { $0.id == task.id }) else { return }
            let previous = state.tasks[index].current
            if let value {
                state.tasks[index].current = value
                if task.kind != .progress { state.tasks[index].completed = value >= task.target }
            }
            state.activities.append(Activity(taskID: task.id, note: note, previous: value == nil ? nil : previous, value: value))
        }
    }
    func refreshOccurrences(through: String? = nil) {
        var next = state
        Self.generate(in: &next, through: through)
        do { try database.save(next); state = next } catch { self.error = error.localizedDescription }
    }
    static func generate(in state: inout Snapshot, today: String = Day.today, through: String? = nil) {
        let horizon = max(56, through.map { (Calendar.current.dateComponents([.day], from: Day.date(today), to: Day.date($0)).day ?? 0) + 1 } ?? 56)
        for rule in state.rules where rule.enabled {
            for offset in -1..<horizon {
                if offset < 0 && rule.kind != .task { continue }
                let day = Day.adding(offset, to: today)
                guard rule.occurs(on: day) else { continue }
                let key = "\(rule.id):\(day)"
                guard !state.generated.contains(key) else { continue }
                state.generated.insert(key)
                switch rule.kind {
                case .assessment:
                    state.assessments.append(Assessment(courseID: rule.courseID, title: rule.title, day: day, confirmed: rule.confirmsAssessments, topics: rule.notes ?? "", ruleID: rule.id, occurrence: day))
                case .task:
                    state.tasks.append(StudyTask(courseID: rule.courseID, title: rule.title, notes: rule.notes ?? "", kind: rule.taskKind ?? .checkbox, planned: day, target: rule.targetCount ?? 30, ruleID: rule.id, occurrence: day))
                case .schedule:
                    state.schedule.append(ScheduleBlock(courseID: rule.courseID, title: rule.title, day: day, startMinute: rule.startMinute ?? 540, duration: rule.duration ?? 60, notes: rule.notes ?? "", ruleID: rule.id, occurrence: day))
                }
            }
        }
    }
    private static func removeUntouched(_ rule: QuizRule, in state: inout Snapshot) {
        var removedDays: [String] = []
        state.assessments.removeAll { item in
            let remove = item.ruleID == rule.id && item.confirmed == rule.confirmsAssessments && item.day >= Day.today && item.day == item.occurrence && item.title == rule.title && item.topics == (rule.notes ?? "") && item.courseID == rule.courseID
            if remove, let day = item.occurrence { removedDays.append(day) }
            return remove
        }
        let worked = Set(state.activities.map(\.taskID))
        state.tasks.removeAll { item in
            let remove = item.ruleID == rule.id && !item.completed && (item.planned ?? "") >= Day.today && item.planned == item.occurrence && item.title == rule.title && item.notes == (rule.notes ?? "") && item.current == 0 && item.start == 1 && item.target == (rule.targetCount ?? 30) && item.kind == (rule.taskKind ?? .checkbox) && item.due == nil && !worked.contains(item.id) && item.courseID == rule.courseID
            if remove, let day = item.occurrence { removedDays.append(day) }
            return remove
        }
        state.schedule.removeAll { item in
            let remove = item.ruleID == rule.id && item.day >= Day.today && item.day == item.occurrence && item.title == rule.title && item.notes == (rule.notes ?? "") && item.startMinute == (rule.startMinute ?? 540) && item.duration == (rule.duration ?? 60) && item.courseID == rule.courseID
            if remove, let day = item.occurrence { removedDays.append(day) }
            return remove
        }
        for day in removedDays { state.generated.remove("\(rule.id):\(day)") }
    }
    func saveRule(_ rule: QuizRule) {
        guard !rule.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !rule.days.isEmpty else { return }
        change { state in
            if let index = state.rules.firstIndex(where: { $0.id == rule.id }) {
                Self.removeUntouched(state.rules[index], in: &state)
                state.rules[index] = rule
            } else { state.rules.append(rule) }
            Self.generate(in: &state)
        }
    }
    func deleteRule(_ id: String) {
        change { state in
            if let rule = state.rules.first(where: { $0.id == id }) { Self.removeUntouched(rule, in: &state) }
            state.rules.removeAll { $0.id == id }
        }
    }
    func save(_ block: ScheduleBlock) {
        guard block.startMinute >= 0, block.duration > 0, block.startMinute + block.duration <= 1440 else { return }
        change { state in
            if let index = state.schedule.firstIndex(where: { $0.id == block.id }) { state.schedule[index] = block }
            else { state.schedule.append(block) }
        }
    }
    func updateProgress(_ id: String, to value: Int) {
        guard let task = state.tasks.first(where: { $0.id == id }), task.kind == .progress else { return }
        let bounded = min(task.target, max(task.start - 1, value))
        guard task.current != bounded else { return }
        record(task, value: bounded, note: "Finished through \(bounded) \(task.unit)")
    }
    func setup(personalized: Bool) {
        change { $0.setupComplete = true }
    }
}

extension Course {
    static let colors = ["blue", "purple", "pink", "orange", "red", "brown", "green", "teal"]
    var tint: Color {
        switch color {
        case "purple": .purple
        case "pink": .pink
        case "orange": .orange
        case "red": .red
        case "brown": .brown
        case "green": .green
        case "teal": .teal
        default: .blue
        }
    }
    var scheduleGradient: LinearGradient {
        let colors: [Color]
        switch color {
        case "purple": colors = [Color(red: 0.47, green: 0.30, blue: 0.76), Color(red: 0.39, green: 0.23, blue: 0.66)]
        case "pink": colors = [Color(red: 0.78, green: 0.30, blue: 0.52), Color(red: 0.68, green: 0.22, blue: 0.44)]
        case "orange": colors = [Color(red: 0.87, green: 0.43, blue: 0.16), Color(red: 0.76, green: 0.34, blue: 0.10)]
        case "red": colors = [Color(red: 0.78, green: 0.25, blue: 0.28), Color(red: 0.68, green: 0.18, blue: 0.22)]
        case "brown": colors = [Color(red: 0.58, green: 0.39, blue: 0.27), Color(red: 0.49, green: 0.31, blue: 0.21)]
        case "green": colors = [Color(red: 0.20, green: 0.58, blue: 0.38), Color(red: 0.14, green: 0.48, blue: 0.31)]
        case "teal": colors = [Color(red: 0.13, green: 0.57, blue: 0.61), Color(red: 0.09, green: 0.47, blue: 0.52)]
        default: colors = [Color(red: 0.25, green: 0.48, blue: 0.86), Color(red: 0.18, green: 0.38, blue: 0.76)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Course {
    var shortName: String {
        name.replacingOccurrences(of: "AP ", with: "").replacingOccurrences(of: "Honors ", with: "")
    }
}
extension Store {
    @discardableResult func reschedule(_ payload: String, to day: String) -> Bool {
        if payload.hasPrefix("assessment:"), var item = state.assessments.first(where: { $0.id == String(payload.dropFirst(11)) }) {
            item.day = day; save(item); return error == nil
        }
        if payload.hasPrefix("planned:"), var task = state.tasks.first(where: { $0.id == String(payload.dropFirst(8)) }) {
            task.planned = day; save(task); return error == nil
        }
        if payload.hasPrefix("schedule:"), var block = state.schedule.first(where: { $0.id == String(payload.dropFirst(9)) }) {
            block.day = day; save(block); return error == nil
        }
        if payload.hasPrefix("task:"), var task = state.tasks.first(where: { $0.id == String(payload.dropFirst(5)) }) {
            task.due = day; save(task); return error == nil
        }
        return false
    }
    func moveTask(_ id: String, before target: String) {
        guard id != target, let task = state.tasks.first(where: { $0.id == id }), state.tasks.contains(where: { $0.id == target }) else { return }
        change { state in
            state.tasks.removeAll { $0.id == id }
            let index = state.tasks.firstIndex { $0.id == target }!
            state.tasks.insert(task, at: index)
        }
    }
}
