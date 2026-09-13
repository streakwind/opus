import Foundation
import OpusCore

package struct WorkDraftModel: Equatable, Sendable {
    package var id: String = ""
    package var title = ""
    package var courseID: String?
    package var day: String?
    package var kind: WorkKind = .task
    package var confirmed = true
    package var notes = ""
    package var start = 1
    package var target = 30
    package var current = 0
    package var isNew: Bool { id.isEmpty }

    package init(
        id: String = "",
        title: String = "",
        courseID: String? = nil,
        day: String? = nil,
        kind: WorkKind = .task,
        confirmed: Bool = true,
        notes: String = "",
        start: Int = 1,
        target: Int = 30,
        current: Int = 0
    ) {
        self.id = id
        self.title = title
        self.courseID = courseID
        self.day = day
        self.kind = kind
        self.confirmed = confirmed
        self.notes = notes
        self.start = start
        self.target = target
        self.current = current
    }

    package static func from(task: StudyTask) -> WorkDraftModel {
        WorkDraftModel(
            id: task.id,
            title: task.title,
            courseID: task.courseID,
            day: task.calendarDay,
            kind: task.kind == .progress ? .progress : .task,
            notes: task.notes,
            start: task.start,
            target: task.target,
            current: task.current
        )
    }
    package static func from(assessment: Assessment) -> WorkDraftModel {
        WorkDraftModel(
            id: assessment.id,
            title: assessment.title,
            courseID: assessment.courseID,
            day: assessment.day,
            kind: .assessment,
            confirmed: true,
            notes: assessment.topics
        )
    }
    package static func blank(courseID: String?, day: String?, kind: WorkKind = .task) -> WorkDraftModel {
        WorkDraftModel(courseID: courseID, day: day, kind: kind, current: kind == .progress ? 0 : 0)
    }
    package var validationError: String? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Enter a title." }
        if let day, !(day.count == 10 && Day.string(Day.date(day)) == day) {
            return "Use a valid date in YYYY-MM-DD format."
        }
        if kind == .progress {
            guard start > 0, target >= start, target <= 1_000_000, current >= start - 1, current <= target else {
                return "Check the page range and last page read."
            }
        }
        return nil
    }
}

package struct CourseDraftModel: Equatable, Sendable {
    package var id: String = ""
    package var name = ""
    package var color = "blue"
    package var classTimes: [ClassTime] = []
    package var listOnly = false
    package var isNew: Bool { id.isEmpty }

    package init(
        id: String = "",
        name: String = "",
        color: String = "blue",
        classTimes: [ClassTime] = [],
        listOnly: Bool = false
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.classTimes = classTimes
        self.listOnly = listOnly
    }

    package static func from(_ course: Course) -> CourseDraftModel {
        CourseDraftModel(id: course.id, name: course.name, color: course.color, classTimes: course.resolvedClassTimes, listOnly: course.isListOnly)
    }
    package var validationError: String? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Enter a list name." }
        guard classTimes.allSatisfy({ !$0.days.isEmpty && $0.startMinute >= 0 && $0.endMinute > $0.startMinute && $0.endMinute <= 1440 }) else {
            return "Check class times."
        }
        return nil
    }
}

package struct RuleDraftModel: Equatable, Sendable {
    package var id: String = ""
    package var title = ""
    package var courseID: String?
    package var workKind: WorkKind = .task
    package var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    package var intervalWeeks = 1
    package var startDate: String? = Day.today
    package var endDate: String?
    package var enabled = true
    package var confirmed = true
    package var notes = ""
    package var startCount = 1
    package var targetCount = 30
    package var startMinute = 540
    package var duration = 60
    package var schedule = false
    package var isNew: Bool { id.isEmpty }

    package init(
        id: String = "",
        title: String = "",
        courseID: String? = nil,
        workKind: WorkKind = .task,
        weekdays: Set<Int> = [2, 3, 4, 5, 6],
        intervalWeeks: Int = 1,
        startDate: String? = Day.today,
        endDate: String? = nil,
        enabled: Bool = true,
        confirmed: Bool = true,
        notes: String = "",
        startCount: Int = 1,
        targetCount: Int = 30,
        startMinute: Int = 540,
        duration: Int = 60,
        schedule: Bool = false
    ) {
        self.id = id
        self.title = title
        self.courseID = courseID
        self.workKind = workKind
        self.weekdays = weekdays
        self.intervalWeeks = intervalWeeks
        self.startDate = startDate
        self.endDate = endDate
        self.enabled = enabled
        self.confirmed = confirmed
        self.notes = notes
        self.startCount = startCount
        self.targetCount = targetCount
        self.startMinute = startMinute
        self.duration = duration
        self.schedule = schedule
    }

    package static func from(_ rule: QuizRule) -> RuleDraftModel {
        RuleDraftModel(
            id: rule.id,
            title: rule.title,
            courseID: rule.courseID,
            workKind: rule.kind == .schedule ? .task : rule.workKind,
            weekdays: rule.days,
            intervalWeeks: rule.intervalWeeks ?? 1,
            startDate: rule.startDate,
            endDate: rule.endDate,
            enabled: rule.enabled,
            confirmed: rule.confirmsAssessments,
            notes: rule.notes ?? "",
            startCount: rule.startCount ?? 1,
            targetCount: rule.targetCount ?? 30,
            startMinute: rule.startMinute ?? 540,
            duration: rule.duration ?? 60,
            schedule: rule.kind == .schedule
        )
    }
    package var validationError: String? {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Enter a title." }
        guard !weekdays.isEmpty else { return "Choose at least one day." }
        if let endDate, let startDate, endDate < startDate { return "Rhythm end must be on or after the start date." }
        if workKind == .progress {
            guard startCount > 0, targetCount >= startCount else { return "Check the page range." }
        }
        if schedule, startMinute + duration > 1440 { return "Choose a duration that ends before midnight." }
        return nil
    }
    package func asRule() -> QuizRule {
        var rule = QuizRule(
            id: isNew ? UUID().uuidString : id,
            courseID: courseID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            weekday: weekdays.sorted().first ?? 4,
            enabled: enabled,
            assessmentsConfirmed: workKind == .assessment ? true : nil,
            weekdays: weekdays.sorted(),
            itemKind: schedule ? .schedule : (workKind == .assessment ? .assessment : .task),
            intervalWeeks: intervalWeeks,
            startDate: startDate ?? Day.today,
            endDate: endDate,
            taskKind: schedule ? nil : (workKind == .progress ? .progress : .checkbox),
            startCount: workKind == .progress ? startCount : nil,
            targetCount: workKind == .progress ? targetCount : nil,
            startMinute: schedule ? startMinute : nil,
            duration: schedule ? duration : nil,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if !schedule { rule.workKind = workKind }
        return rule
    }
}

package struct ScheduleDraftModel: Equatable, Sendable {
    package var id: String = ""
    package var title = ""
    package var courseID: String?
    package var day = Day.today
    package var startMinute = 540
    package var duration = 60
    package var notes = ""
    package var ruleID: String?
    package var occurrence: String?
    package var repeatEnabled = false
    package var repeatDays: Set<Int> = []
    package var repeatEnd: String?
    package var isNew: Bool { id.isEmpty || !exists }
    package var exists = false

    package init(
        id: String = "",
        title: String = "",
        courseID: String? = nil,
        day: String = Day.today,
        startMinute: Int = 540,
        duration: Int = 60,
        notes: String = "",
        ruleID: String? = nil,
        occurrence: String? = nil,
        repeatEnabled: Bool = false,
        repeatDays: Set<Int> = [],
        repeatEnd: String? = nil,
        exists: Bool = false
    ) {
        self.id = id
        self.title = title
        self.courseID = courseID
        self.day = day
        self.startMinute = startMinute
        self.duration = duration
        self.notes = notes
        self.ruleID = ruleID
        self.occurrence = occurrence
        self.repeatEnabled = repeatEnabled
        self.repeatDays = repeatDays
        self.repeatEnd = repeatEnd
        self.exists = exists
    }

    package static func from(_ block: ScheduleBlock, repeatEnd: String? = nil) -> ScheduleDraftModel {
        ScheduleDraftModel(
            id: block.id,
            title: block.title,
            courseID: block.courseID,
            day: block.day,
            startMinute: block.startMinute,
            duration: block.duration,
            notes: block.notes,
            ruleID: block.ruleID,
            occurrence: block.occurrence,
            repeatEnd: repeatEnd,
            exists: true
        )
    }
    package var validationError: String? {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Enter a title." }
        guard duration > 0, startMinute + duration <= 1440 else { return "Choose a duration that ends before midnight." }
        if repeatEnabled && repeatDays.isEmpty { return "Choose at least one day." }
        return nil
    }
}
