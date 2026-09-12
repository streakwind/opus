import Foundation
import OpusCore

package enum LinuxEvent: Equatable, Sendable {
    case ready
    case select(String)
    case search(String)
    case newWork(WorkKind?)
    case editWork(String, WorkRowKind)
    case quickAdd(String)
    case newList(String)
    case editList(String?)
    case deleteList
    case deleteWork(String, WorkRowKind)
    case toggleTask(String)
    case updatePage(String, Int)
    case undo
    case saveWork(WorkDraftModel)
    case saveCourse(CourseDraftModel)
    case saveRule(RuleDraftModel)
    case saveSchedule(ScheduleDraftModel)
    case deleteRule(String)
    case toggleRule(String)
    case deleteSchedule(String, RecurringDeleteScope)
    case calendarPeriod(CalendarPeriod)
    case calendarNavigate(Int)
    case calendarSelectDay(String)
    case calendarDrop(payload: String, day: String)
    case schedulePeriod(CalendarPeriod)
    case scheduleNavigate(Int)
    case scheduleCreate(day: String, startY: Double, endY: Double)
    case scheduleEdit(String)
    case archiveDeleteAll
    case confirmArchiveDeleteAll
    case cancelDialog
    case openSettings
    case setAppearance(AppearanceMode)
    case exportJSON
    case revealDatabase
    case help
    case setupComplete
    case closeEditor
    case prepareTask(String)
    case moveTask(id: String, courseID: String?)
    case confirmAssessment(String, Bool)
}

package enum LinuxCommand: Equatable, Sendable {
    case render
    case openWorkEditor(WorkDraftModel)
    case openCourseEditor(CourseDraftModel)
    case openRuleEditor(RuleDraftModel)
    case openScheduleEditor(ScheduleDraftModel)
    case closeEditor
    case showError(String)
    case confirmArchiveDelete
    case openSettings
    case openHelp
    case exportJSON(Data)
    case revealDatabase(URL)
    case setAppearance(AppearanceMode)
    case quit
}

@MainActor
package final class LinuxSession {
    package let store: Store
    package var selection: NavigationSelection = .section(.today)
    package var query = ""
    package var calendarPeriod: CalendarPeriod = .month
    package var calendarAnchor = Day.today
    package var selectedDay = Day.today
    package var schedulePeriod: CalendarPeriod = .week
    package var scheduleAnchor = Day.today
    package var appearance: AppearanceMode = .system
    package var smoke = false
    package var pendingArchiveDelete = false
    package private(set) var lastExport: Data?

    package init(store: Store) {
        self.store = store
        if !store.state.setupComplete {
            selection = .section(.today)
        }
    }

    package var needsSetup: Bool { !store.state.setupComplete }
    package var heading: String { LinuxPresentation.heading(for: selection, courses: store.state.courses) }
    package var navItems: [NavItem] { LinuxPresentation.navItems(selection: selection, courses: store.state.courses) }
    package var canDeleteList: Bool { selection.courseID != nil }
    package var showTitle: Bool {
        if case .section(.inbox) = selection { return false }
        if case .section(.all) = selection { return false }
        return true
    }
    package var quickPlaceholder: String {
        switch selection {
        case .section(.calendar): return "Add on \(Day.label(selectedDay))…"
        case .section(.schedule): return "Add a timed event…"
        case .section(.rhythm): return "Add a rhythm…"
        case .list(let id): return "Add to \(store.course(id)?.name ?? "list")…"
        case .section(.inbox): return "Add to Inbox…"
        default: return "Add a task…"
        }
    }

    package func workRows() -> (assessments: [WorkRow], progress: [WorkRow], tasks: [WorkRow]) {
        LinuxPresentation.workRows(in: store.state, selection: selection, query: query)
    }
    package func calendarDays() -> [CalendarDayModel] {
        LinuxPresentation.calendarDays(in: store.state, period: calendarPeriod, anchor: calendarAnchor, selected: selectedDay, query: query)
    }
    package func undatedTasks() -> [WorkRow] {
        LinuxPresentation.undatedTasks(in: store.state, query: query)
    }
    package func scheduleDays() -> [String] {
        switch schedulePeriod {
        case .day: return [scheduleAnchor]
        case .week, .month: return CalendarLayout.days(containing: Day.date(scheduleAnchor), week: true)
        }
    }
    package func scheduleBlocks() -> [ScheduleBlockModel] {
        LinuxPresentation.scheduleBlocks(in: store.state, days: scheduleDays(), query: query)
    }
    package func rhythmRows() -> [RhythmRow] {
        LinuxPresentation.rhythmRows(in: store.state, query: query)
    }
    package func emptyMessage() -> String {
        LinuxPresentation.emptyMessage(for: selection, query: query)
    }

    @discardableResult
    package func handle(_ event: LinuxEvent) -> [LinuxCommand] {
        var commands: [LinuxCommand] = []
        switch event {
        case .ready:
            store.refreshOccurrences()
            if smoke { return [.render, .quit] }
            if needsSetup { commands.append(.openHelp) }
            commands.append(.render)
        case .select(let id):
            selection = NavigationSelection.parse(id)
            if selection == .section(.calendar) || selection == .section(.schedule) {
                store.refreshOccurrences(through: Day.adding(40))
            }
            commands.append(.render)
        case .search(let text):
            query = text
            commands.append(.render)
        case .newWork(let kind):
            let day: String?
            switch selection {
            case .section(.today): day = Day.today
            case .section(.calendar): day = selectedDay
            default: day = nil
            }
            commands.append(.openWorkEditor(.blank(courseID: selection.courseID, day: day, kind: kind ?? .task)))
        case .editWork(let id, let kind):
            switch kind {
            case .assessment:
                if let item = store.state.assessments.first(where: { $0.id == id }) {
                    commands.append(.openWorkEditor(.from(assessment: item)))
                }
            case .task, .progress:
                if let task = store.state.tasks.first(where: { $0.id == id }) {
                    commands.append(.openWorkEditor(.from(task: task)))
                }
            }
        case .quickAdd(let text):
            let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { break }
            if selection == .section(.rhythm) {
                var draft = RuleDraftModel(); draft.title = title; draft.courseID = selection.courseID
                commands.append(.openRuleEditor(draft)); break
            }
            if selection == .section(.schedule) {
                var draft = ScheduleDraftModel(); draft.title = title; draft.day = scheduleAnchor; draft.courseID = selection.courseID
                commands.append(.openScheduleEditor(draft)); break
            }
            let due: String?
            switch selection {
            case .section(.today): due = Day.today
            case .section(.calendar): due = selectedDay
            default: due = nil
            }
            store.save(StudyTask(courseID: selection.courseID, title: title, due: due))
            if let error = store.error { commands.append(.showError(error)) }
            if case .section(.archive) = selection { selection = .section(.inbox) }
            commands.append(.render)
        case .newList(let text):
            let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                commands.append(.openCourseEditor(CourseDraftModel()))
                break
            }
            let list = Course(name: name)
            store.save(list)
            if store.error == nil { selection = .list(list.id) }
            if let error = store.error { commands.append(.showError(error)) }
            commands.append(.render)
        case .editList(let id):
            let course = id.flatMap(store.course) ?? selection.courseID.flatMap(store.course) ?? Course(name: "")
            commands.append(.openCourseEditor(id == nil && selection.courseID == nil && course.name.isEmpty ? CourseDraftModel() : .from(course)))
        case .deleteList:
            guard let id = selection.courseID else { break }
            store.deleteCourse(id)
            if store.error == nil { selection = .section(.inbox) }
            if let error = store.error { commands.append(.showError(error)) }
            commands.append(.render)
        case .deleteWork(let id, let kind):
            switch kind {
            case .assessment: store.deleteAssessment(id)
            case .task, .progress: store.deleteTask(id)
            }
            if let error = store.error { commands.append(.showError(error)) }
            commands.append(.render)
        case .toggleTask(let id):
            if var task = store.state.tasks.first(where: { $0.id == id }) {
                task.completed.toggle()
                store.save(task)
            }
            if let error = store.error { commands.append(.showError(error)) }
            commands.append(.render)
        case .updatePage(let id, let page):
            store.updateProgress(id, to: page)
            if let error = store.error { commands.append(.showError(error)) }
            commands.append(.render)
        case .undo:
            store.undo()
            commands.append(.render)
        case .saveWork(let draft):
            if let error = draft.validationError { return [.showError(error)] }
            let name = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let on = draft.day
            switch draft.kind {
            case .assessment:
                var item = store.state.assessments.first { $0.id == draft.id } ?? Assessment()
                if draft.isNew { item = Assessment() }
                else { item.id = draft.id }
                item.title = name; item.courseID = draft.courseID; item.day = on ?? Day.today
                item.confirmed = true; item.topics = draft.notes
                store.save(item)
            case .progress:
                var task = store.state.tasks.first { $0.id == draft.id } ?? StudyTask()
                if !draft.isNew { task.id = draft.id }
                let previous = task.current
                task.title = name; task.notes = draft.notes; task.courseID = draft.courseID
                task.kind = .progress; task.completed = false
                task.start = draft.start; task.target = draft.target
                if let on { task.moveCalendarDay(to: on) } else { task.due = nil; task.planned = nil }
                store.save(task)
                let bounded = min(draft.target, max(draft.start - 1, draft.current))
                if bounded != previous { store.updateProgress(task.id, to: bounded) }
            case .task:
                var task = store.state.tasks.first { $0.id == draft.id } ?? StudyTask()
                if !draft.isNew { task.id = draft.id }
                task.title = name; task.notes = draft.notes; task.courseID = draft.courseID; task.kind = .checkbox
                if let on { task.moveCalendarDay(to: on) } else { task.due = nil; task.planned = nil }
                store.save(task)
            }
            if let error = store.error { return [.showError(error)] }
            commands.append(contentsOf: [.closeEditor, .render])
        case .saveCourse(let draft):
            if let error = draft.validationError { return [.showError(error)] }
            var course = store.course(draft.id) ?? Course(name: draft.name)
            if !draft.isNew { course.id = draft.id }
            course.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            course.color = draft.color
            course.classTimes = draft.classTimes
            course.syncLegacyClassTime()
            store.save(course)
            if store.error == nil { selection = .list(course.id) }
            if let error = store.error { return [.showError(error)] }
            commands.append(contentsOf: [.closeEditor, .render])
        case .saveRule(let draft):
            if let error = draft.validationError { return [.showError(error)] }
            store.saveRule(draft.asRule())
            if let error = store.error { return [.showError(error)] }
            selection = .section(.rhythm)
            commands.append(contentsOf: [.closeEditor, .render])
        case .saveSchedule(let draft):
            if let error = draft.validationError { return [.showError(error)] }
            if draft.repeatEnabled {
                var rule = QuizRule(courseID: draft.courseID, title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines))
                rule.itemKind = .schedule
                rule.weekdays = draft.repeatDays.sorted()
                rule.startDate = draft.day
                rule.endDate = draft.repeatEnd
                rule.startMinute = draft.startMinute
                rule.duration = draft.duration
                rule.notes = draft.notes
                store.saveRule(rule)
            } else {
                var block = store.state.schedule.first { $0.id == draft.id } ?? ScheduleBlock()
                if !draft.isNew { block.id = draft.id }
                block.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                block.courseID = draft.courseID
                block.day = draft.day
                block.startMinute = draft.startMinute
                block.duration = draft.duration
                block.notes = draft.notes
                block.ruleID = draft.ruleID
                block.occurrence = draft.occurrence
                store.save(block)
                if let ruleID = draft.ruleID { store.setScheduleRuleEnd(ruleID, to: draft.repeatEnd) }
            }
            if let error = store.error { return [.showError(error)] }
            commands.append(contentsOf: [.closeEditor, .render])
        case .deleteRule(let id):
            store.deleteRule(id)
            if let error = store.error { commands.append(.showError(error)) }
            commands.append(.render)
        case .toggleRule(let id):
            if var rule = store.rule(id) {
                rule.enabled.toggle()
                store.saveRule(rule)
            }
            if let error = store.error { commands.append(.showError(error)) }
            commands.append(.render)
        case .deleteSchedule(let id, let scope):
            if let block = store.state.schedule.first(where: { $0.id == id }) {
                store.deleteSchedule(block, scope: scope)
            }
            if let error = store.error { commands.append(.showError(error)) }
            commands.append(.render)
        case .calendarPeriod(let period):
            calendarPeriod = period
            store.refreshOccurrences(through: Day.adding(40, to: calendarAnchor))
            commands.append(.render)
        case .calendarNavigate(let delta):
            let unit: Calendar.Component = calendarPeriod == .month ? .month : .day
            let amount = calendarPeriod == .week ? delta * 7 : delta
            calendarAnchor = Day.string(Calendar.current.date(byAdding: unit, value: amount, to: Day.date(calendarAnchor))!)
            store.refreshOccurrences(through: Day.adding(40, to: calendarAnchor))
            commands.append(.render)
        case .calendarSelectDay(let day):
            selectedDay = day
            calendarAnchor = day
            commands.append(.render)
        case .calendarDrop(let payload, let day):
            _ = store.reschedule(payload, to: day)
            if let error = store.error { commands.append(.showError(error)) }
            commands.append(.render)
        case .schedulePeriod(let period):
            schedulePeriod = period == .month ? .week : period
            store.refreshOccurrences(through: Day.adding(40, to: scheduleAnchor))
            commands.append(.render)
        case .scheduleNavigate(let delta):
            let amount = schedulePeriod == .day ? delta : delta * 7
            scheduleAnchor = Day.adding(amount, to: scheduleAnchor)
            store.refreshOccurrences(through: Day.adding(40, to: scheduleAnchor))
            commands.append(.render)
        case .scheduleCreate(let day, let startY, let endY):
            let block = ScheduleLayout.block(day: day, startY: startY, endY: endY, hourHeight: 60)
            commands.append(.openScheduleEditor(.from(block)))
        case .scheduleEdit(let id):
            if id.hasPrefix("class:") {
                if let course = store.state.courses.first(where: { id.hasPrefix("class:\($0.id):") }) {
                    commands.append(.openCourseEditor(.from(course)))
                }
            } else if let block = store.state.schedule.first(where: { $0.id == id }) {
                let end = block.ruleID.flatMap { store.rule($0)?.endDate }
                commands.append(.openScheduleEditor(.from(block, repeatEnd: end)))
            }
        case .archiveDeleteAll:
            commands.append(.confirmArchiveDelete)
        case .confirmArchiveDeleteAll:
            store.deleteArchivedTasks()
            if let error = store.error { commands.append(.showError(error)) }
            commands.append(.render)
        case .cancelDialog:
            pendingArchiveDelete = false
        case .openSettings:
            commands.append(.openSettings)
        case .setAppearance(let mode):
            appearance = mode
            commands.append(.setAppearance(mode))
        case .exportJSON:
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(store.state)
                lastExport = data
                commands.append(.exportJSON(data))
            } catch {
                commands.append(.showError(error.localizedDescription))
            }
        case .revealDatabase:
            commands.append(.revealDatabase(store.location))
        case .help:
            commands.append(.openHelp)
        case .setupComplete:
            store.setup()
            commands.append(.render)
        case .closeEditor:
            commands.append(.closeEditor)
        case .prepareTask(let id):
            if let item = store.state.assessments.first(where: { $0.id == id }) {
                store.save(StudyTask(courseID: item.courseID, title: "Prepare: " + item.title, notes: item.topics, due: item.day))
            }
            if let error = store.error { commands.append(.showError(error)) }
            commands.append(.render)
        case .moveTask(let id, let courseID):
            if var task = store.state.tasks.first(where: { $0.id == id }) {
                task.courseID = courseID
                store.save(task)
            }
            if let error = store.error { commands.append(.showError(error)) }
            commands.append(.render)
        case .confirmAssessment:
            break
        }
        return commands
    }
}
