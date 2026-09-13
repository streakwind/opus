import Foundation
import OpusCore
import OpusGTKSupport
import GTKBridge
import Glibc

private struct GTKEvent: Sendable {
    let action: String
    let id: String
    let text: String
    let day: String
    let course: String
    let payload: String
    let kind: Int
    let start: Int
    let end: Int
    let page: Int
    let flags: Int
    let value: Int
    let y0: Double
    let y1: Double

    init(_ raw: UnsafePointer<OpusEventPayload>) {
        let event = raw.pointee
        func copy(_ value: UnsafePointer<CChar>?) -> String {
            guard let value else { return "" }
            return String(cString: value)
        }
        action = copy(event.action)
        id = copy(event.id)
        text = copy(event.text)
        day = copy(event.day)
        course = copy(event.course)
        payload = copy(event.payload)
        kind = Int(event.kind)
        start = Int(event.start)
        end = Int(event.end)
        page = Int(event.page)
        flags = Int(event.flags)
        value = Int(event.value)
        y0 = event.y0
        y1 = event.y1
    }
}

@MainActor
final class LinuxApp {
    let session: LinuxSession
    var exportData: Data?
    init() throws {
        session = LinuxSession(store: try Store(database: Database(url: DataLocation.linux())))
        session.smoke = CommandLine.arguments.contains("--smoke-test")
    }

    func apply(_ commands: [LinuxCommand]) {
        for command in commands {
            switch command {
            case .render: render()
            case .openWorkEditor(let draft): openWork(draft)
            case .openCourseEditor(let draft): openCourse(draft)
            case .openRuleEditor(let draft): openRule(draft)
            case .openScheduleEditor(let draft): openSchedule(draft)
            case .closeEditor: opus_editor_close()
            case .showError(let message): opus_error(message)
            case .confirmArchiveDelete:
                let count = session.store.state.tasks.filter { $0.kind != .progress && $0.completed }.count
                let noun = count == 1 ? "task" : "tasks"
                opus_confirm_archive("Permanently remove \(count) completed \(noun)?")
            case .openSettings: opus_settings_open(Int32(appearanceIndex(session.appearance)))
            case .openHelp: opus_help_open()
            case .exportJSON(let data):
                exportData = data
                opus_export_save("Opus-\(Day.today).json")
            case .revealDatabase(let url):
                opus_reveal_path(url.deletingLastPathComponent().path)
            case .setAppearance(let mode):
                opus_set_appearance(Int32(appearanceIndex(mode)))
            case .quit: opus_quit()
            }
        }
    }

    func render() {
        let view: Int32
        switch session.selection {
        case .section(.calendar): view = 1
        case .section(.schedule): view = 2
        case .section(.rhythm): view = 3
        default: view = 0
        }
        opus_shell_begin(
            session.heading,
            session.quickPlaceholder,
            session.store.canUndo ? 1 : 0,
            session.canDeleteList ? 1 : 0,
            session.showTitle ? 1 : 0,
            view,
            session.selection == .section(.archive) ? 1 : 0
        )
        for item in session.navItems {
            opus_nav(item.id, item.title, item.selected ? 1 : 0, item.color, item.separatorBefore ? 1 : 0)
        }
        switch session.selection {
        case .section(.calendar): renderCalendar()
        case .section(.schedule): renderSchedule()
        case .section(.rhythm): renderRhythm()
        default: renderTasks()
        }
        if let error = session.store.error { opus_error(error) }
    }

    private func renderTasks() {
        let rows = session.workRows()
        if !rows.assessments.isEmpty {
            opus_section("Assessments")
            rows.assessments.forEach(emit)
        }
        if !rows.progress.isEmpty {
            opus_section("Progress")
            rows.progress.forEach(emit)
        }
        if !rows.tasks.isEmpty && (!rows.assessments.isEmpty || !rows.progress.isEmpty) {
            opus_section("Tasks")
        }
        rows.tasks.forEach(emit)
        if rows.assessments.isEmpty && rows.progress.isEmpty && rows.tasks.isEmpty {
            opus_empty(session.emptyMessage())
        }
    }

    private func emit(_ row: WorkRow) {
        opus_work_row(
            row.id, row.kind.rawValue, row.title, row.detail,
            row.completed ? 1 : 0, row.progress ? 1 : 0,
            Int32(row.start), Int32(row.target), Int32(row.current),
            row.confirmed ? 1 : 0, row.color
        )
    }

    private func renderCalendar() {
        let heading = Day.date(session.calendarAnchor).formatted(.dateTime.month(.wide).year())
        opus_calendar_begin(heading, periodIndex(session.calendarPeriod), session.calendarPeriod == .day ? 1 : 7)
        for day in session.calendarDays() {
            opus_calendar_day(day.day, day.label, day.inMonth ? 1 : 0, day.isToday ? 1 : 0, day.isSelected ? 1 : 0)
            for item in day.items.prefix(5) {
                opus_calendar_item(day.day, item.id, item.kind.rawValue, item.title, item.completed ? 1 : 0, 1, item.color)
            }
        }
    }

    private func renderSchedule() {
        let days = session.scheduleDays()
        opus_schedule_begin(session.heading, periodIndex(session.schedulePeriod), Int32(days.count))
        for day in days {
            let label = Day.date(day).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            opus_schedule_day(day, label)
        }
        let blocks = session.scheduleBlocks()
        for block in blocks {
            opus_schedule_block(
                block.id, block.title, block.detail, block.day,
                Int32(block.startMinute), Int32(block.duration),
                Int32(block.column), Int32(block.columns),
                block.color, block.isClass ? 1 : 0
            )
        }
        if blocks.isEmpty { opus_empty(session.emptyMessage()) }
    }

    private func renderRhythm() {
        let rows = session.rhythmRows()
        for row in rows {
            opus_rhythm_row(row.id, row.title, row.detail, row.enabled ? 1 : 0, row.color)
        }
        if rows.isEmpty { opus_empty(session.emptyMessage()) }
    }

    private func openWork(_ draft: WorkDraftModel) {
        opus_work_editor_open(
            draft.id, draft.title, draft.day ?? "", draft.courseID ?? "",
            Int32(draft.kind == .task ? 0 : draft.kind == .progress ? 1 : 2),
            draft.confirmed ? 1 : 0, draft.notes,
            Int32(draft.start), Int32(draft.target), Int32(draft.current)
        )
        opus_work_editor_list("", "Inbox", draft.courseID == nil ? 1 : 0)
        for course in session.store.state.courses {
            opus_work_editor_list(course.id, course.name, draft.courseID == course.id ? 1 : 0)
        }
    }

    private func openCourse(_ draft: CourseDraftModel) {
        opus_course_editor_open(draft.id, draft.name, draft.color, draft.listOnly ? 1 : 0)
        for time in draft.classTimes {
            opus_course_editor_time(time.id, Int32(time.startMinute), Int32(time.endMinute), time.days.map(String.init).joined(separator: ","))
        }
    }

    private func openRule(_ draft: RuleDraftModel) {
        opus_rule_editor_open(
            draft.id, draft.title, draft.courseID ?? "",
            Int32(draft.workKind == .task ? 0 : draft.workKind == .progress ? 1 : 2),
            draft.weekdays.sorted().map(String.init).joined(separator: ","),
            Int32(draft.intervalWeeks), draft.startDate ?? "", draft.endDate ?? "",
            draft.enabled ? 1 : 0, draft.confirmed ? 1 : 0, draft.notes,
            Int32(draft.startCount), Int32(draft.targetCount),
            Int32(draft.startMinute), Int32(draft.duration), draft.schedule ? 1 : 0
        )
        opus_rule_editor_list("", "Inbox", draft.courseID == nil ? 1 : 0)
        for course in session.store.state.courses {
            opus_rule_editor_list(course.id, course.name, draft.courseID == course.id ? 1 : 0)
        }
    }

    private func openSchedule(_ draft: ScheduleDraftModel) {
        opus_schedule_editor_open(
            draft.id, draft.title, draft.courseID ?? "", draft.day,
            Int32(draft.startMinute), Int32(draft.duration), draft.notes,
            draft.exists ? 1 : 0, draft.ruleID == nil ? 0 : 1, draft.repeatEnd ?? "",
            draft.ruleID ?? ""
        )
        opus_schedule_editor_list("", "Inbox", draft.courseID == nil ? 1 : 0)
        for course in session.store.state.courses {
            opus_schedule_editor_list(course.id, course.name, draft.courseID == course.id ? 1 : 0)
        }
    }

    fileprivate func event(_ payload: GTKEvent) {
        let action = payload.action
        let id = payload.id
        let text = payload.text
        let day = payload.day
        let course = payload.course
        let drag = payload.payload
        let kind = payload.kind
        let start = payload.start
        let end = payload.end
        let page = payload.page
        let flags = payload.flags
        let value = payload.value

        let mapped: LinuxEvent?
        switch action {
        case "ready": mapped = .ready
        case "select": mapped = .select(id)
        case "search": mapped = .search(text)
        case "new": mapped = .newWork(nil)
        case "new-work": mapped = .newWork(kind == 1 ? .progress : kind == 2 ? .assessment : .task)
        case "edit-work": mapped = .editWork(id, kind == 2 ? .assessment : kind == 1 ? .progress : .task)
        case "add": mapped = .quickAdd(text)
        case "new-list": mapped = .newList(text)
        case "edit-list": mapped = .editList(id.isEmpty ? nil : id)
        case "delete-list": mapped = .deleteList
        case "delete-work": mapped = .deleteWork(id, kind == 2 ? .assessment : kind == 1 ? .progress : .task)
        case "toggle": mapped = .toggleTask(id)
        case "page":
            guard let number = Int(text) else { opus_error("Enter a page number, then press Enter."); return }
            mapped = .updatePage(id, number)
        case "undo": mapped = .undo
        case "save-work":
            mapped = .saveWork(WorkDraftModel(
                id: id, title: text, courseID: course.isEmpty ? nil : course, day: day.isEmpty ? nil : day,
                kind: kind == 1 ? .progress : kind == 2 ? .assessment : .task,
                confirmed: flags != 0, notes: drag, start: start, target: end, current: page
            ))
        case "save-course":
            mapped = .saveCourse(CourseDraftModel(id: id, name: text, color: day.isEmpty ? "blue" : day, classTimes: ClassTimeCodec.parse(drag), listOnly: flags != 0))
        case "save-rule":
            let meta = drag.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            mapped = .saveRule(RuleDraftModel(
                id: id, title: text, courseID: course.isEmpty ? nil : course,
                workKind: kind == 1 ? .progress : kind == 2 ? .assessment : .task,
                weekdays: Set(day.split(separator: ",").compactMap { Int($0) }),
                intervalWeeks: max(1, value),
                startDate: meta.indices.contains(0) && !meta[0].isEmpty ? meta[0] : Day.today,
                endDate: meta.indices.contains(1) && !meta[1].isEmpty ? meta[1] : nil,
                enabled: flags & 1 != 0, confirmed: flags & 2 != 0,
                notes: meta.indices.contains(2) ? meta[2] : "",
                startCount: start, targetCount: end, startMinute: page,
                duration: max(15, Int(payload.y0)), schedule: Int(payload.y1) != 0
            ))
        case "save-schedule":
            let parts = drag.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            mapped = .saveSchedule(ScheduleDraftModel(
                id: id, title: text, courseID: course.isEmpty ? nil : course, day: day.isEmpty ? Day.today : day,
                startMinute: start, duration: end,
                notes: parts.indices.contains(2) ? parts[2] : "",
                ruleID: flags & 4 != 0 ? parts.first : nil,
                repeatEnabled: flags & 2 != 0,
                repeatDays: Set((parts.first ?? "").split(separator: ",").compactMap { Int($0) }),
                repeatEnd: parts.indices.contains(1) && !parts[1].isEmpty ? parts[1] : nil,
                exists: flags & 1 != 0
            ))
        case "delete-rule": mapped = .deleteRule(id)
        case "toggle-rule": mapped = .toggleRule(id)
        case "edit-rule":
            if let rule = session.store.rule(id) { apply([.openRuleEditor(.from(rule))]) }
            return
        case "delete-schedule":
            mapped = .deleteSchedule(id, value == 2 ? .allEvents : value == 1 ? .thisAndFollowing : .thisEvent)
        case "calendar-period": mapped = .calendarPeriod(periodFrom(value))
        case "calendar-nav": mapped = .calendarNavigate(value)
        case "calendar-select-day": mapped = .calendarSelectDay(day.isEmpty ? id : day)
        case "calendar-drop": mapped = .calendarDrop(payload: drag.isEmpty ? text : drag, day: day)
        case "schedule-period": mapped = .schedulePeriod(periodFrom(value))
        case "schedule-nav": mapped = .scheduleNavigate(value)
        case "schedule-create": mapped = .scheduleCreate(day: day, startY: payload.y0, endY: payload.y1)
        case "schedule-edit": mapped = .scheduleEdit(id)
        case "archive-delete-all": mapped = .archiveDeleteAll
        case "confirm-archive-delete": mapped = .confirmArchiveDeleteAll
        case "cancel-dialog": mapped = .cancelDialog
        case "settings": mapped = .openSettings
        case "set-appearance": mapped = .setAppearance(value == 1 ? .light : value == 2 ? .dark : .system)
        case "export": mapped = .exportJSON
        case "export-path":
            if let data = exportData {
                do { try data.write(to: URL(fileURLWithPath: text), options: .atomic) }
                catch { opus_error(error.localizedDescription) }
            }
            return
        case "reveal-database": mapped = .revealDatabase
        case "help": mapped = .help
        case "setup-complete": mapped = .setupComplete
        case "editor-cancel", "close-editor": mapped = .closeEditor
        case "prepare-task": mapped = .prepareTask(id)
        case "move-task": mapped = .moveTask(id: id, courseID: course.isEmpty ? nil : course)
        case "confirm-assessment": mapped = .confirmAssessment(id, flags != 0)
        default: return
        }
        if let mapped { apply(session.handle(mapped)) }
    }

    private func appearanceIndex(_ mode: AppearanceMode) -> Int {
        switch mode { case .system: 0; case .light: 1; case .dark: 2 }
    }
    private func periodIndex(_ period: CalendarPeriod) -> Int32 {
        switch period { case .day: 0; case .week: 1; case .month: 2 }
    }
    private func periodFrom(_ value: Int) -> CalendarPeriod {
        value == 0 ? .day : value == 2 ? .month : .week
    }
}

@main
struct OpusGTK {
    @MainActor static var controller: LinuxApp?
    @MainActor static func main() {
        do {
            controller = try LinuxApp()
            exit(opus_run(handleGTKEvent))
        } catch {
            FileHandle.standardError.write(Data("Opus could not open its database: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

private func handleGTKEvent(_ payload: UnsafePointer<OpusEventPayload>?) {
    guard let payload else { return }
    let event = GTKEvent(payload)
    MainActor.assumeIsolated {
        OpusGTK.controller?.event(event)
    }
}
