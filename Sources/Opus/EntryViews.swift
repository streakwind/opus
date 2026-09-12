import OpusCore
import SwiftUI

struct PropertyRow<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }.font(.system(size: 13)).padding(.vertical, 6)
    }
}
struct CourseMenu: View {
    var courses: [Course]
    @Binding var value: String?
    var body: some View {
        PillPicker("List", label: courses.first { $0.id == value }?.name ?? "Inbox", selection: $value) {
            Text("Inbox").tag(nil as String?)
            ForEach(courses) { Text($0.name).tag(Optional($0.id)) }
        }.labelsHidden().pickerStyle(.menu).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("work-list-menu")
    }
}



enum WorkDraft: Identifiable {
    case new(day: String, courseID: String?, title: String, kind: WorkKind)
    case task(StudyTask)
    case assessment(Assessment)

    var id: String {
        switch self {
        case .new: "new"
        case .task(let task): "task:" + task.id
        case .assessment(let item): "assessment:" + item.id
        }
    }
}

/// Shared centered editor for tasks, progress, and assessments.
struct WorkItemEditor: View {
    var store: Store
    var source: WorkDraft
    var onDateChange: (String) -> Void
    var onDismiss: () -> Void
    @State private var title: String
    @State private var course: String?
    @State private var day: String?
    @State private var kind: WorkKind
    @State private var confirmed: Bool
    @State private var notes: String
    @State private var notesVisible: Bool
    @State private var start: Int
    @State private var target: Int
    @State private var current: Int
    @FocusState private var titleFocused: Bool

    init(store: Store, source: WorkDraft, onDateChange: @escaping (String) -> Void = { _ in }, onDismiss: @escaping () -> Void = {}) {
        self.store = store
        self.source = source
        self.onDateChange = onDateChange
        self.onDismiss = onDismiss
        switch source {
        case .new(let day, let courseID, let title, let kind):
            _title = State(initialValue: title)
            _course = State(initialValue: courseID)
            _day = State(initialValue: day)
            _kind = State(initialValue: kind)
            _confirmed = State(initialValue: true)
            _notes = State(initialValue: "")
            _notesVisible = State(initialValue: false)
            _start = State(initialValue: 1)
            _target = State(initialValue: 30)
            _current = State(initialValue: 0)
        case .task(let task):
            _title = State(initialValue: task.title)
            _course = State(initialValue: task.courseID)
            _day = State(initialValue: task.calendarDay)
            _kind = State(initialValue: task.kind == .progress ? .progress : .task)
            _confirmed = State(initialValue: true)
            _notes = State(initialValue: task.notes)
            _notesVisible = State(initialValue: !task.notes.isEmpty)
            _start = State(initialValue: task.start)
            _target = State(initialValue: task.target)
            _current = State(initialValue: task.current)
        case .assessment(let item):
            _title = State(initialValue: item.title)
            _course = State(initialValue: item.courseID)
            _day = State(initialValue: item.day)
            _kind = State(initialValue: .assessment)
            _confirmed = State(initialValue: item.confirmed)
            _notes = State(initialValue: item.topics)
            _notesVisible = State(initialValue: !item.topics.isEmpty)
            _start = State(initialValue: 1)
            _target = State(initialValue: 30)
            _current = State(initialValue: 0)
        }
    }

    private var isNew: Bool { if case .new = source { true } else { false } }
    private var canChangeKind: Bool {
        if case .new = source { return true }
        if case .task = source { return true }
        return false
    }
    private var valid: Bool {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        if kind == .progress {
            return start > 0 && target >= start && target <= 1_000_000 && current >= start - 1 && current <= target
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(headerLabel).font(.subheadline).foregroundStyle(.secondary)
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .semibold))
                .focused($titleFocused)
                .onSubmit(save)
                .accessibilityIdentifier("work-title-field")

            VStack(spacing: 0) {
                if canChangeKind {
                    PropertyRow("Type") {
                        PillPicker("Type", label: kind.rawValue, selection: $kind) {
                            ForEach(WorkKind.allCases) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().fixedSize()
                    }
                }
                PropertyRow("List") { CourseMenu(courses: store.state.courses, value: $course) }
                PropertyRow(kind == .assessment ? "Date" : "Due") {
                    DateMenu(title: kind == .assessment ? "Date" : "No deadline", value: $day)
                }
                if kind == .assessment {
                    PropertyRow("Status") {
                        PillPicker("Status", label: confirmed ? "Confirmed" : "Tentative", selection: $confirmed) {
                            Text("Confirmed").tag(true)
                            Text("Tentative").tag(false)
                        }.labelsHidden().pickerStyle(.menu)
                    }
                }
                if kind == .progress {
                    PropertyRow("Range") {
                        HStack {
                            TextField("Start", value: $start, format: .number.grouping(.never)).frame(width: 55)
                            Text("to").foregroundStyle(.secondary)
                            TextField("End", value: $target, format: .number.grouping(.never)).frame(width: 55)
                        }.textFieldStyle(.roundedBorder)
                    }
                    PropertyRow("Read") {
                        TextField("Last page", value: $current, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 68)
                            .accessibilityIdentifier("work-progress-current")
                    }
                    if let pace = pacingHint {
                        Text(pace).font(.caption).foregroundStyle(.secondary).padding(.leading, 76)
                    }
                }
            }

            if notesVisible {
                TextField(kind == .assessment ? "Topics" : "Details", text: $notes, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(2...6)
            } else {
                Button(kind == .assessment ? "Add topics" : "Add details") { notesVisible = true }
                    .buttonStyle(.plain).foregroundStyle(.secondary).font(.caption)
            }

            if let rhythmNote {
                Text(rhythmNote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            if !valid {
                Text(kind == .progress ? "Check the title and page range." : "Enter a title.")
                    .font(.caption).foregroundStyle(.orange)
            }

            HStack {
                if !isNew {
                    Button(role: .destructive, action: delete) {
                        Image(systemName: "trash")
                    }.buttonStyle(.plain).help("Delete").accessibilityIdentifier("work-delete")
                }
                Spacer()
                Button("Cancel", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("work-cancel")
                Button(isNew ? "Add" : "Done", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!valid)
                    .accessibilityIdentifier("work-save")
            }
        }
        .padding(18)
        .frame(width: 360)
        .roundedControls()
        .onAppear { titleFocused = true }
        .onChange(of: day) { _, day in if let day { onDateChange(day) } }
        .onChange(of: start) { old, new in if current == old - 1 { current = new - 1 } }
        .onChange(of: kind) { _, new in
            if new == .progress, current < start - 1 { current = start - 1 }
        }
    }

    private var headerLabel: String {
        let date = Day.date(day ?? Day.today).formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        return (isNew ? "Add · " : "Edit · ") + date
    }

    private var pacingHint: String? {
        let draft = StudyTask(kind: .progress, due: day, start: start, target: target, current: current)
        return draft.pacing(on: Day.today)
    }

    private var rhythmNote: String? {
        guard case .task(let task) = source, let rule = store.rule(task.ruleID) else { return nil }
        var parts = [rule.repeatsLabel]
        if let end = rule.endDate { parts.append("Rhythm ends " + Day.label(end)) }
        return parts.joined(separator: " · ")
    }

    private func save() {
        guard valid else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let on = day ?? Day.today
        switch source {
        case .new:
            switch kind {
            case .task:
                store.save(StudyTask(courseID: course, title: name, notes: notes, due: on))
            case .progress:
                store.save(StudyTask(
                    courseID: course, title: name, notes: notes, kind: .progress, due: on,
                    start: start, target: target, current: min(target, max(start - 1, current))
                ))
            case .assessment:
                store.save(Assessment(courseID: course, title: name, day: on, confirmed: confirmed, topics: notes))
            }
        case .task(let original):
            guard var currentTask = store.state.tasks.first(where: { $0.id == original.id }) else { onDismiss(); return }
            let previousCurrent = currentTask.current
            currentTask.title = name
            currentTask.notes = notes
            currentTask.courseID = course
            if kind == .progress {
                currentTask.kind = .progress
                currentTask.completed = false
                currentTask.start = start
                currentTask.target = target
                currentTask.moveCalendarDay(to: on)
                store.save(currentTask)
                let bounded = min(target, max(start - 1, current))
                if bounded != previousCurrent {
                    store.updateProgress(currentTask.id, to: bounded)
                }
            } else {
                currentTask.kind = .checkbox
                if let day { currentTask.moveCalendarDay(to: day) }
                else { currentTask.due = nil; currentTask.planned = nil }
                store.save(currentTask)
            }
        case .assessment(var item):
            item.title = name
            item.topics = notes
            item.day = on
            item.confirmed = confirmed
            item.courseID = course
            store.save(item)
        }
        if store.error == nil {
            store.calendarFocus = CalendarFocus(day: on)
            onDismiss()
        }
    }

    private func delete() {
        switch source {
        case .task(let task): store.deleteTask(task.id)
        case .assessment(let item): store.deleteAssessment(item.id)
        case .new: break
        }
        onDismiss()
    }
}

typealias CalendarDraft = WorkDraft
typealias CalendarEntryEditor = WorkItemEditor

struct ScheduleEditor: View {
    var store: Store
    @State var block: ScheduleBlock
    var onChange: (ScheduleBlock) -> Void = { _ in }
    var onDismiss: () -> Void
    @State private var repeatBlock = false
    @State private var repeatDays: Set<Int> = []
    @State private var repeatEnd: String?
    private let originalRepeatEnd: String?
    @FocusState private var titleFocused: Bool
    init(store: Store, block: ScheduleBlock, onChange: @escaping (ScheduleBlock) -> Void = { _ in }, onDismiss: @escaping () -> Void = {}) {
        self.store = store
        _block = State(initialValue: block)
        self.onChange = onChange
        self.onDismiss = onDismiss
        let end = block.ruleID.flatMap { id in store.state.rules.first { $0.id == id }?.endDate }
        _repeatEnd = State(initialValue: end)
        originalRepeatEnd = end
    }
    private var existing: Bool { store.state.schedule.contains { $0.id == block.id } }
    private var valid: Bool { !block.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && block.duration > 0 && block.startMinute + block.duration <= 1440 && (!repeatBlock || !repeatDays.isEmpty) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Day.date(block.day).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + " · " + block.timeLabel).font(.caption).foregroundStyle(.secondary)
            TextField("Class, study session, or event", text: $block.title).textFieldStyle(.plain).font(.system(size: 18, weight: .semibold)).focused($titleFocused).onSubmit(save)
                .accessibilityIdentifier("schedule-title-field")
            VStack(spacing: 0) {
                PropertyRow("List") { CourseMenu(courses: store.state.courses, value: $block.courseID) }
                PropertyRow("Date") { DateMenu(title: "Date", value: Binding(get: { block.day }, set: { block.day = $0 ?? Day.today })) }
                PropertyRow("Starts") { TimeControl(minutes: $block.startMinute) }
                PropertyRow("Ends") { TimeControl(minutes: Binding(get: { block.endMinute }, set: { block.endMinute = $0 })) }
            }
            if !existing {
                Toggle("Repeat", isOn: $repeatBlock).toggleStyle(.checkbox)
                if repeatBlock {
                    WeekdayPicker(days: $repeatDays)
                    PropertyRow("Until") { DateMenu(title: "No end date", value: $repeatEnd) }
                }
            } else if block.ruleID != nil {
                PropertyRow("Until") { DateMenu(title: "No end date", value: $repeatEnd) }
            }
            if !block.notes.isEmpty { TextField("Details", text: $block.notes, axis: .vertical).textFieldStyle(.plain).lineLimit(1...4) }
            if block.startMinute + block.duration > 1440 { Text("Choose a duration that ends before midnight.").font(.caption).foregroundStyle(.orange) }
            HStack {
                if existing {
                    if block.ruleID != nil {
                        Menu {
                            Button("Delete this event") { delete(.thisEvent) }
                            Button("Delete this and following") { delete(.thisAndFollowing) }
                            Button("Delete all events", role: .destructive) { delete(.allEvents) }
                        } label: { Image(systemName: "trash") }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
                    } else {
                        Button(role: .destructive) { delete(.thisEvent) } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                    }
                }
                Spacer()
                Button("Cancel", action: onDismiss).keyboardShortcut(.cancelAction)
                Button(existing ? "Done" : "Add", action: save).keyboardShortcut(.defaultAction).disabled(!valid)
                    .accessibilityIdentifier("schedule-save")
            }
        }.padding(18).frame(width: 350).roundedControls()
        .onChange(of: block) { _, updated in onChange(updated) }
        .onAppear { if !existing { titleFocused = true }; repeatDays = [Calendar.current.component(.weekday, from: Day.date(block.day))] }
    }
    private func save() {
        guard valid else { return }
        if repeatBlock {
            var rule = QuizRule(courseID: block.courseID, title: block.title)
            rule.itemKind = .schedule; rule.weekdays = repeatDays.sorted(); rule.startDate = block.day; rule.endDate = repeatEnd; rule.startMinute = block.startMinute; rule.duration = block.duration; rule.notes = block.notes
            store.saveRule(rule)
        } else {
            store.save(block)
            if let ruleID = block.ruleID, repeatEnd != originalRepeatEnd { store.setScheduleRuleEnd(ruleID, to: repeatEnd) }
        }
        if store.error == nil { onDismiss() }
    }
    private func delete(_ scope: RecurringDeleteScope) {
        store.deleteSchedule(block, scope: scope)
        if store.error == nil { onDismiss() }
    }
}

struct WeekdayPicker: View {
    @Binding var days: Set<Int>
    var body: some View {
        HStack(spacing: 5) {
            ForEach([2,3,4,5,6,7,1], id: \.self) { day in
                Button {
                    if days.contains(day) { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(Calendar.current.shortWeekdaySymbols[day-1]).font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(days.contains(day) ? Color.accentColor : Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(days.contains(day) ? Color.white : Color.primary)
                }.buttonStyle(.plain).accessibilityLabel(Calendar.current.weekdaySymbols[day-1]).accessibilityValue(days.contains(day) ? "Selected" : "Not selected")
            }
        }
    }
}
