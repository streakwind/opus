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
        Picker("List", selection: $value) {
            Text("Inbox").tag(nil as String?)
            ForEach(courses) { Text($0.name).tag(Optional($0.id)) }
        }.labelsHidden().pickerStyle(.menu).fixedSize(horizontal: false, vertical: true)
    }
}
enum CalendarDraft: Identifiable {
    case new(String), task(StudyTask, String), assessment(Assessment)
    var id: String {
        switch self { case .new(let day): "new:" + day; case .task(let task, let day): task.id + ":" + day; case .assessment(let item): item.id }
    }
}
struct CalendarEntryEditor: View {
    var store: Store
    var source: CalendarDraft
    @State private var title: String
    @State private var course: String?
    @State private var day: String?
    @State private var kind: RepeatItem
    @State private var confirmed: Bool
    @State private var notes: String
    @State private var notesVisible: Bool
    @FocusState private var titleFocused: Bool
    @Environment(\.dismiss) private var dismiss
    init(store: Store, source: CalendarDraft) {
        self.store = store; self.source = source
        switch source {
        case .new(let day):
            _title = State(initialValue: ""); _day = State(initialValue: day); _kind = State(initialValue: .task); _confirmed = State(initialValue: true); _notes = State(initialValue: ""); _notesVisible = State(initialValue: false)
        case .task(let task, let date):
            _title = State(initialValue: task.title); _course = State(initialValue: task.courseID); _day = State(initialValue: date); _kind = State(initialValue: .task); _confirmed = State(initialValue: true); _notes = State(initialValue: task.notes); _notesVisible = State(initialValue: !task.notes.isEmpty)
        case .assessment(let item):
            _title = State(initialValue: item.title); _course = State(initialValue: item.courseID); _day = State(initialValue: item.day); _kind = State(initialValue: .assessment); _confirmed = State(initialValue: item.confirmed); _notes = State(initialValue: item.topics); _notesVisible = State(initialValue: !item.topics.isEmpty)
        }
    }
    private var isNew: Bool { if case .new = source { true } else { false } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text((isNew ? "Add to " : "On ") + Day.date(day ?? Day.today).formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.subheadline).foregroundStyle(.secondary)
            TextField("Title", text: $title).textFieldStyle(.plain).font(.system(size: 18, weight: .semibold)).focused($titleFocused).onSubmit(save)
            Divider()
            VStack(spacing: 0) {
                if isNew {
                    PropertyRow("Add as") {
                        Picker("Kind", selection: $kind) { Text("Task").tag(RepeatItem.task); Text("Assessment").tag(RepeatItem.assessment) }.labelsHidden().pickerStyle(.segmented)
                    }
                }
                PropertyRow("List") { CourseMenu(courses: store.state.courses, value: $course) }
                PropertyRow(kind == .task ? "On" : "Date") { DatePicker("Date", selection: Binding(get: { Day.date(day ?? Day.today) }, set: { day = Day.string($0) }), displayedComponents: .date).labelsHidden() }
                if kind == .assessment {
                    PropertyRow("Status") {
                        Picker("Status", selection: $confirmed) { Text("Confirmed").tag(true); Text("Tentative").tag(false) }.labelsHidden().pickerStyle(.menu)
                    }
                }
            }
            if case .task(let task, _) = source, task.kind == .progress { InlineProgress(store: store, task: store.state.tasks.first { $0.id == task.id } ?? task) }
            if notesVisible { TextField("Notes", text: $notes, axis: .vertical).textFieldStyle(.plain).lineLimit(2...6) }
            else { Button("Add notes") { notesVisible = true }.buttonStyle(.plain).foregroundStyle(.secondary).font(.caption) }
            Divider()
            HStack {
                if !isNew { Button(role: .destructive, action: delete) { Image(systemName: "trash") }.buttonStyle(.plain).help("Delete") }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Done", action: save).keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(18).frame(width: 340).roundedControls()
        .onAppear { if isNew { titleFocused = true } }
    }
    private func save() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        switch source {
        case .new:
            if kind == .task { store.save(StudyTask(courseID: course, title: name, notes: notes, planned: day ?? Day.today)) }
            else { store.save(Assessment(courseID: course, title: name, day: day ?? Day.today, confirmed: confirmed, topics: notes)) }
        case .task(let original, let originalDay):
            guard var current = store.state.tasks.first(where: { $0.id == original.id }) else { dismiss(); return }
            current.title = name; current.notes = notes; current.courseID = course
            if original.due == originalDay { current.due = day }
            else { current.planned = day }
            store.save(current)
        case .assessment(var item):
            item.title = name; item.topics = notes; item.day = day ?? Day.today; item.confirmed = confirmed; item.courseID = course; store.save(item)
        }
        if store.error == nil { dismiss() }
    }
    private func delete() {
        switch source {
        case .task(let task, _): store.deleteTask(task.id)
        case .assessment(let item): store.change { $0.assessments.removeAll { $0.id == item.id } }
        case .new: break
        }
        dismiss()
    }
}

struct ScheduleEditor: View {
    var store: Store
    @State var block: ScheduleBlock
    @State private var repeatBlock = false
    @State private var repeatDays: Set<Int> = []
    @FocusState private var titleFocused: Bool
    @Environment(\.dismiss) private var dismiss
    private var existing: Bool { store.state.schedule.contains { $0.id == block.id } }
    private var valid: Bool { !block.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && block.duration > 0 && block.startMinute + block.duration <= 1440 && (!repeatBlock || !repeatDays.isEmpty) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Class, study session, or event", text: $block.title).textFieldStyle(.plain).font(.system(size: 18, weight: .semibold)).focused($titleFocused).onSubmit(save)
            Divider()
            VStack(spacing: 0) {
                PropertyRow("List") { CourseMenu(courses: store.state.courses, value: $block.courseID) }
                PropertyRow("Date") { DateMenu(title: "Date", value: Binding(get: { block.day }, set: { block.day = $0 ?? Day.today })) }
                PropertyRow("From") { DatePicker("From", selection: Binding(get: { ClockTime.date(block.startMinute) }, set: { block.startMinute = ClockTime.minutes($0) }), displayedComponents: .hourAndMinute).labelsHidden() }
                PropertyRow("For") {
                    Picker("Duration", selection: $block.duration) {
                        ForEach(Array(Set([15,30,45,60,90,120,180,block.duration])).sorted(), id: \.self) { Text("\($0) minutes").tag($0) }
                    }.labelsHidden().pickerStyle(.menu)
                }
            }
            if !existing {
                Toggle("Repeat", isOn: $repeatBlock).toggleStyle(.checkbox)
                if repeatBlock { WeekdayPicker(days: $repeatDays) }
            }
            TextField("Notes (optional)", text: $block.notes, axis: .vertical).textFieldStyle(.plain).lineLimit(1...4)
            if block.startMinute + block.duration > 1440 { Text("Choose a duration that ends before midnight.").font(.caption).foregroundStyle(.orange) }
            Divider()
            HStack {
                if existing { Button(role: .destructive) { store.change { $0.schedule.removeAll { $0.id == block.id } }; dismiss() } label: { Image(systemName: "trash") }.buttonStyle(.plain) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(existing ? "Done" : "Add", action: save).keyboardShortcut(.defaultAction).disabled(!valid)
            }
        }.padding(18).frame(width: 350).roundedControls()
        .onAppear { if !existing { titleFocused = true }; repeatDays = [Calendar.current.component(.weekday, from: Day.date(block.day))] }
    }
    private func save() {
        guard valid else { return }
        if repeatBlock {
            var rule = QuizRule(courseID: block.courseID, title: block.title)
            rule.itemKind = .schedule; rule.weekdays = repeatDays.sorted(); rule.startDate = block.day; rule.startMinute = block.startMinute; rule.duration = block.duration; rule.notes = block.notes
            store.saveRule(rule)
        } else { store.save(block) }
        if store.error == nil { dismiss() }
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
