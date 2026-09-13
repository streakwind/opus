import Foundation
import OpusCore

package enum LinuxPresentation {
    package static func matchesQuery(_ query: String, title: String, details: String = "", courseName: String? = nil) -> Bool {
        query.isEmpty ||
        title.localizedCaseInsensitiveContains(query) ||
        details.localizedCaseInsensitiveContains(query) ||
        (courseName?.localizedCaseInsensitiveContains(query) ?? false)
    }

    package static func heading(for selection: NavigationSelection, courses: [Course], today: String = Day.today) -> String {
        switch selection {
        case .section(.today):
            return Day.date(today).formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        case .section(let section): return section.title
        case .list(let id): return courses.first { $0.id == id }?.name ?? "List"
        }
    }

    package static func navItems(selection: NavigationSelection, courses: [Course]) -> [NavItem] {
        var items: [NavItem] = AppSection.allCases.map {
            NavItem(id: $0.rawValue, title: $0.title, selected: selection.id == $0.rawValue, color: nil, separatorBefore: $0 == .calendar)
        }
        for (index, course) in courses.enumerated() {
            items.append(NavItem(
                id: "list:" + course.id,
                title: course.name,
                selected: selection.id == "list:" + course.id,
                color: course.color,
                separatorBefore: index == 0
            ))
        }
        return items
    }

    package static func matchingTasks(in state: Snapshot, selection: NavigationSelection, query: String, today: String = Day.today) -> [StudyTask] {
        state.tasks.filter { task in
            let matches: Bool
            switch selection {
            case .section(.all): matches = state.showsInOverview(task.courseID)
            case .section(.inbox): matches = task.courseID == nil
            case .section(.archive): matches = task.kind != .progress && task.completed
            case .section(.today): matches = task.isInToday(on: today) && state.showsInOverview(task.courseID)
            case .list(let id): matches = task.courseID == id
            case .section(.calendar), .section(.schedule), .section(.rhythm): matches = false
            }
            let visible: Bool
            if case .section(.archive) = selection { visible = true }
            else { visible = task.kind == .progress || !task.completed }
            let courseName = state.courses.first { $0.id == task.courseID }?.name
            return matches && visible && matchesQuery(query, title: task.title, details: task.notes, courseName: courseName)
        }
    }

    package static func nextRhythms(_ items: [StudyTask], archive: Bool) -> [StudyTask] {
        if archive {
            return items.sorted {
                let left = $0.calendarDay ?? ""
                let right = $1.calendarDay ?? ""
                if left == right { return $0.title < $1.title }
                return left > right
            }
        }
        let ordered = items.sorted {
            let left = $0.calendarDay ?? "9999"
            let right = $1.calendarDay ?? "9999"
            if left == right { return $0.title < $1.title }
            return left < right
        }
        var seen = Set<String>()
        return ordered.filter { task in
            guard let ruleID = task.ruleID else { return true }
            return seen.insert(ruleID).inserted
        }
    }

    package static func assessments(in state: Snapshot, selection: NavigationSelection, query: String, today: String = Day.today) -> [Assessment] {
        let courseID = selection.courseID
        guard courseID != nil || selection == .section(.today) || selection == .section(.all) else { return [] }
        var seen = Set<String>()
        let matching = state.assessments.filter { item in
            let courseName = state.courses.first { course in course.id == item.courseID }?.name
            return (courseID == nil || item.courseID == courseID) &&
                (courseID != nil || state.showsInOverview(item.courseID)) &&
                item.day >= today &&
                matchesQuery(query, title: item.title, details: item.topics, courseName: courseName)
        }
        let ordered = matching.sorted { left, right in
            left.day == right.day ? left.title < right.title : left.day < right.day
        }
        return ordered.filter { item in
            guard let ruleID = item.ruleID else { return true }
            return seen.insert(ruleID).inserted
        }
    }

    package static func workRows(in state: Snapshot, selection: NavigationSelection, query: String, today: String = Day.today) -> (assessments: [WorkRow], progress: [WorkRow], tasks: [WorkRow]) {
        let archive = selection == .section(.archive)
        let matching = matchingTasks(in: state, selection: selection, query: query, today: today)
        let progress = nextRhythms(matching.filter { $0.kind == .progress }, archive: archive).map { row(for: $0, in: state, markNext: !archive) }
        let tasks = nextRhythms(matching.filter { $0.kind != .progress }, archive: archive).map { row(for: $0, in: state, markNext: !archive) }
        let assessments = assessments(in: state, selection: selection, query: query, today: today).map { row(for: $0, in: state) }
        return (assessments, progress, tasks)
    }

    package static func row(for task: StudyTask, in state: Snapshot, markNext: Bool) -> WorkRow {
        let course = state.courses.first { $0.id == task.courseID }
        var detail: [String] = []
        if let name = course?.name { detail.append(name) }
        if let caption = task.rhythmCaption() {
            detail.append(caption)
        } else if let day = task.calendarDay {
            detail.append(task.kind == .progress ? "Goal " + Day.label(day) : "Due " + Day.label(day))
        }
        if task.kind == .progress {
            detail.append(task.progressLabel)
            if let pace = task.pacing(on: Day.today) { detail.append(pace) }
        }
        return WorkRow(
            id: task.id,
            kind: task.kind == .progress ? .progress : .task,
            title: task.title,
            detail: detail.joined(separator: " · "),
            completed: task.completed,
            progress: task.kind == .progress,
            start: task.start,
            target: task.target,
            current: task.current,
            confirmed: true,
            courseID: task.courseID,
            day: task.calendarDay,
            color: course?.color ?? "blue",
            markNext: markNext && task.ruleID != nil && !task.completed
        )
    }

    package static func row(for item: Assessment, in state: Snapshot) -> WorkRow {
        let course = state.courses.first { $0.id == item.courseID }
        var detail = [Day.label(item.day)]
        if let name = course?.name { detail.insert(name, at: 0) }
        if !item.topics.isEmpty { detail.append(item.topics) }
        return WorkRow(
            id: item.id,
            kind: .assessment,
            title: item.title,
            detail: detail.joined(separator: " · "),
            completed: false,
            progress: false,
            start: 0,
            target: 0,
            current: 0,
            confirmed: true,
            courseID: item.courseID,
            day: item.day,
            color: course?.color ?? "blue",
            markNext: false
        )
    }

    package static func calendarDays(in state: Snapshot, period: CalendarPeriod, anchor: String, selected: String, query: String) -> [CalendarDayModel] {
        let date = Day.date(anchor)
        let days: [String]
        switch period {
        case .day: days = [anchor]
        case .week: days = CalendarLayout.days(containing: date, week: true)
        case .month: days = CalendarLayout.days(containing: date, week: false)
        }
        let month = Calendar.current.component(.month, from: date)
        return days.map { day in
            let assessments = state.assessments
                .filter {
                    $0.day == day &&
                    state.showsInOverview($0.courseID) &&
                    matchesQuery(query, title: $0.title, details: $0.topics)
                }
                .map { row(for: $0, in: state) }
            let tasks = state.tasks
                .filter {
                    $0.due == day &&
                    state.showsInOverview($0.courseID) &&
                    ($0.kind == .progress || !$0.completed) &&
                    matchesQuery(query, title: $0.title, details: $0.notes)
                }
                .map { row(for: $0, in: state, markNext: false) }
            return CalendarDayModel(
                day: day,
                label: String(Calendar.current.component(.day, from: Day.date(day))),
                inMonth: Calendar.current.component(.month, from: Day.date(day)) == month,
                isToday: day == Day.today,
                isSelected: day == selected,
                items: assessments + tasks
            )
        }
    }

    package static func scheduleBlocks(in state: Snapshot, days: [String], query: String) -> [ScheduleBlockModel] {
        var models: [ScheduleBlockModel] = []
        for day in days {
            var blocks = state.schedule.filter {
                $0.day == day && matchesQuery(query, title: $0.title, details: $0.notes)
            }
            for course in state.courses {
                blocks += course.classBlocks(on: day).filter { matchesQuery(query, title: $0.title) }
            }
            for placement in ScheduleLayout.placements(blocks) {
                let course = state.courses.first { $0.id == placement.block.courseID }
                models.append(ScheduleBlockModel(
                    id: placement.block.id,
                    title: placement.block.title,
                    detail: placement.block.timeLabel,
                    day: placement.block.day,
                    startMinute: placement.block.startMinute,
                    duration: placement.block.duration,
                    column: placement.column,
                    columns: placement.columns,
                    color: course?.color ?? "blue",
                    isClass: placement.block.id.hasPrefix("class:"),
                    courseID: placement.block.courseID,
                    ruleID: placement.block.ruleID
                ))
            }
        }
        return models
    }

    package static func rhythmRows(in state: Snapshot, query: String) -> [RhythmRow] {
        state.rules
            .filter { $0.kind != .schedule && matchesQuery(query, title: $0.title, details: $0.notes ?? "") }
            .map { rule in
                let course = state.courses.first { $0.id == rule.courseID }
                var detail = [rule.summary]
                if !rule.enabled { detail.append("Paused") }
                detail.insert(rule.workKind.rawValue, at: 0)
                if let name = course?.name { detail.insert(name, at: 0) }
                return RhythmRow(
                    id: rule.id,
                    title: rule.title,
                    detail: detail.joined(separator: " · "),
                    enabled: rule.enabled,
                    color: course?.color ?? "teal",
                    kind: rule.workKind.rawValue
                )
            }
    }

    package static func emptyMessage(for selection: NavigationSelection, query: String) -> String {
        if !query.isEmpty { return "No matches." }
        switch selection {
        case .section(.today): return "Nothing due today or tomorrow."
        case .section(.archive): return "No completed tasks yet."
        case .section(.calendar): return "No dated work in this range."
        case .section(.schedule): return "No events in this range."
        case .section(.rhythm): return "No rhythms yet."
        default: return "No tasks here yet."
        }
    }
}
