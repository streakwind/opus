import SwiftUI

struct CourseEditor: View {
    var store: Store
    @State var course: Course
    @State private var classTimes: [ClassTime]
    @Environment(\.dismiss) private var dismiss
    init(store: Store, course: Course) {
        self.store = store
        _course = State(initialValue: course)
        _classTimes = State(initialValue: course.resolvedClassTimes)
    }
    private var suggestedClassStart: Int {
        let starts: [String: Int] = [:]
        return starts[course.name] ?? 540
    }
    private var valid: Bool {
        !course.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        classTimes.allSatisfy { !$0.days.isEmpty && $0.startMinute >= 0 && $0.endMinute > $0.startMinute && $0.endMinute <= 1440 }
    }
    private var existing: Bool { store.state.courses.contains(where: { $0.id == course.id }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(existing ? "Edit list" : "New list").font(.system(size: 20, weight: .semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.07), in: Circle())
                }.buttonStyle(.plain).help("Close")
            }
            .padding(20)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("NAME").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        TextField("List name", text: $course.name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 18, weight: .semibold))
                            .padding(11)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("COLOR").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        HStack(spacing: 9) {
                        ForEach(Course.colors, id: \.self) { color in
                            Button { course.color = color } label: {
                                Circle().fill(Course(name: "", color: color).tint).frame(width: 20, height: 20)
                                    .overlay { if course.color == color { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) } }
                            }.buttonStyle(.plain).accessibilityLabel(color).accessibilityValue(course.color == color ? "Selected" : "")
                        }
                        }
                        ColorPicker(
                            "Custom color",
                            selection: Binding(
                                get: { course.tint },
                                set: { course.color = Course.hex(from: $0) }
                            ),
                            supportsOpacity: false
                        )
                        .font(.callout)
                        .fixedSize()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("CLASS TIMES").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Button { addClassTime() } label: { Label("Add time", systemImage: "plus") }
                        }
                        if classTimes.isEmpty {
                            Text("No class times").font(.callout).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                        }
                        ForEach($classTimes) { $time in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(ClockTime.label(time.startMinute) + "–" + ClockTime.label(time.endMinute))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button(role: .destructive) { classTimes.removeAll { $0.id == time.id } } label: {
                                        Image(systemName: "trash")
                                    }.buttonStyle(.plain).help("Remove class time")
                                }
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("Starts").font(.caption).foregroundStyle(.secondary)
                                        TimeControl(minutes: $time.startMinute)
                                    }
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("Ends").font(.caption).foregroundStyle(.secondary)
                                        TimeControl(minutes: $time.endMinute)
                                    }
                                    Spacer()
                                }
                                WeekdayPicker(days: Binding(get: { Set(time.days) }, set: { time.days = $0.sorted() }))
                                if time.endMinute <= time.startMinute {
                                    Text("End time must be after start time.").font(.caption).foregroundStyle(.orange)
                                }
                            }
                            .padding(13)
                            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxHeight: 520)

            Divider()
            HStack {
                if existing {
                    Button("Remove list", role: .destructive) { store.deleteCourse(course.id); dismiss() }.help("Move its tasks to Inbox and keep its calendar entries")
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Done") {
                    course.name = course.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    course.classTimes = classTimes
                    course.syncLegacyClassTime()
                    store.save(course)
                    if store.error == nil { dismiss() }
                }.keyboardShortcut(.defaultAction).disabled(!valid)
            }
            .padding(20)
        }
        .frame(width: 460)
        .roundedControls()
    }
    private func addClassTime() {
        let start = classTimes.last?.endMinute ?? suggestedClassStart
        classTimes.append(ClassTime(startMinute: min(start, 1395), endMinute: min(start + 50, 1440)))
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
                        ForEach([RepeatItem.task, .assessment]) { Text($0.rawValue).tag($0) }
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
                        PillPicker("Track", label: (rule.taskKind == .progress ? TaskKind.progress : .checkbox).rawValue, selection: Binding(get: { rule.taskKind == .progress ? TaskKind.progress : .checkbox }, set: { rule.taskKind = $0 })) {
                            ForEach([TaskKind.checkbox, .progress]) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().pickerStyle(.menu)
                    }
                    if rule.taskKind == .progress {
                        PropertyRow("Goal") { TextField("Pages", value: Binding(get: { rule.targetCount ?? 30 }, set: { rule.targetCount = max(1, $0) }), format: .number).frame(width: 80) }
                    }
                }
                if rule.kind == .schedule {
                    PropertyRow("Starts") { TimeControl(minutes: Binding(get: { rule.startMinute ?? 540 }, set: { rule.startMinute = $0 })) }
                    PropertyRow("Ends") {
                        TimeControl(minutes: Binding(
                            get: { min(1440, (rule.startMinute ?? 540) + (rule.duration ?? 60)) },
                            set: { rule.duration = max(15, min(1440, $0) - (rule.startMinute ?? 540)) }
                        ))
                    }
                }
            }
            Text("Repeat on").font(.callout.weight(.medium))
            WeekdayPicker(days: $days)
            VStack(spacing: 0) {
                PropertyRow("Every") {
                    PillPicker("Interval", label: (rule.intervalWeeks ?? 1) == 1 ? "Week" : "\(rule.intervalWeeks ?? 1) weeks", selection: Binding(get: { rule.intervalWeeks ?? 1 }, set: { rule.intervalWeeks = $0 })) { ForEach(1...8, id: \.self) { Text($0 == 1 ? "Week" : "\($0) weeks").tag($0) } }.labelsHidden()
                }
                PropertyRow("From") { DateMenu(title: "Today", value: $rule.startDate) }
                PropertyRow("Rhythm ends") { DateMenu(title: "No end date", value: $rule.endDate) }
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
