import SwiftUI

struct CourseEditor: View {
    var store: Store
    @State var course: Course
    @Environment(\.dismiss) private var dismiss
    private var suggestedClassStart: Int {
        let starts: [String: Int] = [:]
        return starts[course.name] ?? 540
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("List name", text: $course.name).textFieldStyle(.plain).font(.system(size: 19, weight: .semibold))
            PropertyRow("Color") {
                HStack(spacing: 9) {
                    ForEach(Course.colors, id: \.self) { color in
                        Button { course.color = color } label: {
                            Circle().fill(Course(name: "", color: color).tint).frame(width: 20, height: 20)
                                .overlay { if course.color == color { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) } }
                        }.buttonStyle(.plain).accessibilityLabel(color).accessibilityValue(course.color == color ? "Selected" : "")
                    }
                }
            }
            Toggle("Class time", isOn: Binding(get: { course.classStart != nil }, set: { course.classStart = $0 ? suggestedClassStart : nil }))
            if course.classStart != nil {
                PropertyRow("Starts") { TimeControl(minutes: Binding(get: { course.classStart ?? 465 }, set: { course.classStart = $0 })) }
                PropertyRow("Length") {
                    PillPicker("Length", label: "\(course.classDuration ?? 50) min", selection: Binding(get: { course.classDuration ?? 50 }, set: { course.classDuration = $0 })) {
                        ForEach([30,45,50,60,75,90], id: \.self) { Text("\($0) minutes").tag($0) }
                    }
                }
                WeekdayPicker(days: Binding(get: { Set(course.classDays ?? Array(2...6)) }, set: { course.classDays = $0.sorted() }))
            }
            HStack {
                if store.state.courses.contains(where: { $0.id == course.id }) {
                    Button("Remove list", role: .destructive) { store.deleteCourse(course.id); dismiss() }.help("Move its tasks to Inbox and keep its calendar entries")
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Done") { course.name = course.name.trimmingCharacters(in: .whitespacesAndNewlines); store.save(course); if store.error == nil { dismiss() } }.keyboardShortcut(.defaultAction).disabled(course.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(width: 380).roundedControls()
    }
}
struct RuleEditor: View {
    var store: Store
    @State var rule: QuizRule
    @State private var days: Set<Int>
    @Environment(\.dismiss) private var dismiss
    init(store: Store, rule: QuizRule) {
        self.store = store; _rule = State(initialValue: rule); _days = State(initialValue: rule.days)
    }
    private var valid: Bool { !rule.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !days.isEmpty && (rule.endDate == nil || rule.endDate! >= (rule.startDate ?? Day.today)) && (rule.kind != .schedule || (rule.startMinute ?? 540) + (rule.duration ?? 60) <= 1440) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Repeat something", text: $rule.title).textFieldStyle(.plain).font(.system(size: 19, weight: .semibold))
            VStack(spacing: 0) {
                PropertyRow("Add to") {
                    PillPicker("Kind", label: rule.kind.rawValue, selection: Binding(get: { rule.kind }, set: { rule.itemKind = $0 })) {
                        ForEach(RepeatItem.allCases) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().pickerStyle(.menu)
                }
                PropertyRow("List") { CourseMenu(courses: store.state.courses, value: $rule.courseID) }
                if rule.kind == .assessment {
                    PropertyRow("Dates") {
                        PillPicker("Dates", label: rule.confirmsAssessments ? "Confirmed" : "Tentative", selection: Binding(get: { rule.confirmsAssessments }, set: { rule.assessmentsConfirmed = $0 })) {
                            Text("Confirmed").tag(true)
                            Text("Tentative").tag(false)
                        }.labelsHidden()
                    }
                }
                if rule.kind == .task {
                    PropertyRow("Track") {
                        PillPicker("Track", label: (rule.taskKind ?? .checkbox).rawValue, selection: Binding(get: { rule.taskKind ?? .checkbox }, set: { rule.taskKind = $0 })) { ForEach(TaskKind.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().pickerStyle(.menu)
                    }
                    if rule.taskKind == .progress {
                        PropertyRow("Goal") { TextField("Pages", value: Binding(get: { rule.targetCount ?? 30 }, set: { rule.targetCount = max(1, $0) }), format: .number).frame(width: 80) }
                    }
                }
                if rule.kind == .schedule {
                    PropertyRow("At") { TimeControl(minutes: Binding(get: { rule.startMinute ?? 540 }, set: { rule.startMinute = $0 })) }
                    PropertyRow("For") {
                        PillPicker("Duration", label: "\(rule.duration ?? 60) minutes", selection: Binding(get: { rule.duration ?? 60 }, set: { rule.duration = $0 })) { ForEach([15,30,45,60,90,120,180], id: \.self) { Text("\($0) minutes").tag($0) } }.labelsHidden()
                    }
                }
            }
            HStack {
                Text("Repeat on").font(.callout.weight(.medium))
                Spacer()
                Menu("Presets") {
                    Button("Every day") { days = Set(1...7) }
                    Button("Weekdays") { days = Set(2...6) }
                    Button("Mon, Tue, Wed") { days = [2,3,4] }
                    Button("Weekends") { days = [1,7] }
                }.menuStyle(.borderlessButton).fixedSize()
            }
            WeekdayPicker(days: $days)
            VStack(spacing: 0) {
                PropertyRow("Every") {
                    PillPicker("Interval", label: (rule.intervalWeeks ?? 1) == 1 ? "Week" : "\(rule.intervalWeeks ?? 1) weeks", selection: Binding(get: { rule.intervalWeeks ?? 1 }, set: { rule.intervalWeeks = $0 })) { ForEach(1...8, id: \.self) { Text($0 == 1 ? "Week" : "\($0) weeks").tag($0) } }.labelsHidden()
                }
                PropertyRow("From") { DateMenu(title: "Today", value: $rule.startDate) }
                PropertyRow("Until") { DateMenu(title: "No end date", value: $rule.endDate) }
                PropertyRow("Active") { Toggle("Active", isOn: $rule.enabled).labelsHidden().toggleStyle(.switch).controlSize(.small) }
            }
            Text("Changes apply to future untouched occurrences. Completed or individually edited items stay as they are.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if store.state.rules.contains(where: { $0.id == rule.id }) { Button("Delete", role: .destructive) { store.deleteRule(rule.id); dismiss() } }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Done") {
                    rule.weekdays = days.sorted(); rule.startDate = rule.startDate ?? Day.today
                    store.saveRule(rule); if store.error == nil { dismiss() }
                }.keyboardShortcut(.defaultAction).disabled(!valid)
            }
        }.padding(20).frame(width: 360).roundedControls()
    }
}
