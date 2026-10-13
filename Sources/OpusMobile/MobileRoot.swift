#if os(iOS)
import SwiftUI
import OpusCore
import UniformTypeIdentifiers

@available(iOS 26.0, *)
public struct OpusMobileRoot: View {
    @State private var store: Store?
    @State private var sync: ICloudSync?
    @State private var startupError: String?
    @Environment(\.scenePhase) private var phase
    public init() {}
    public var body: some View {
        Group {
            if let store { PhoneHome(store: store, sync: sync) }
            else if let startupError { ContentUnavailableView("Unable to open Opus", systemImage: "externaldrive.badge.exclamationmark", description: Text(startupError)) }
            else { ProgressView("Opening Opus…") }
        }
        .task {
            guard store == nil, startupError == nil else { return }
            do {
                var root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Opus")
                #if DEBUG
                if ProcessInfo.processInfo.environment["OPUS_UI_TESTING"] == "1" {
                    root = FileManager.default.temporaryDirectory.appendingPathComponent("OpusUITests/" + UUID().uuidString)
                }
                #endif
                let opened = try Store(database: Database(url: root.appendingPathComponent("Opus.sqlite")))
                store = opened
                var syncDefaults = UserDefaults.standard
                #if DEBUG
                if ProcessInfo.processInfo.environment["OPUS_UI_TESTING"] == "1" {
                    syncDefaults = UserDefaults(suiteName: "OpusUITests." + UUID().uuidString)!
                }
                #endif
                do { sync = try ICloudSync(store: opened, defaults: syncDefaults) }
                catch { opened.error = "iCloud sync could not start: \(error.localizedDescription)" }
                #if DEBUG
                if ProcessInfo.processInfo.environment["OPUS_UI_TESTING"] == "1" { sync?.setEnabled(false) }
                #endif
                await sync?.sync()
            } catch { startupError = error.localizedDescription }
        }
        .onChange(of: phase) { _, value in
            if value == .active { store?.refreshOccurrences(); Task { await sync?.sync() } }
        }
    }
}

enum PhoneSheet: Identifiable {
    case task(StudyTask), course(Course), assessment(Assessment), schedule(ScheduleBlock), rhythm(QuizRule)
    var id: String {
        switch self {
        case .task(let value): "task:" + value.id
        case .course(let value): "course:" + value.id
        case .assessment(let value): "assessment:" + value.id
        case .schedule(let value): "schedule:" + value.id
        case .rhythm(let value): "rhythm:" + value.id
        }
    }
}

private struct PhoneHome: View {
    @Bindable var store: Store
    var sync: ICloudSync?
    @State private var sheet: PhoneSheet?
    @State private var query = ""
    @State private var day = Date()
    @State private var settings = false
    @AppStorage("appearance") private var appearance = "system"
    private var dayKey: String { Day.string(day) }
    private var filteredTasks: [StudyTask] {
        store.state.tasks.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || (store.course($0.courseID)?.name.localizedCaseInsensitiveContains(query) ?? false) }
    }
    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") {
                NavigationStack {
                    List {
                        Section("Today · " + Day.label(Day.today)) {
                            taskRows(filteredTasks.filter { !$0.isFinished && $0.isInToday(on: Day.today) })
                        }
                        Section("Assessments") {
                            ForEach(store.state.assessments.filter { $0.day == Day.today }) { assessment in
                                Button { sheet = .assessment(assessment) } label: { Label(assessment.title, systemImage: "graduationcap") }.foregroundStyle(.primary)
                            }
                        }
                        Section("Schedule") { scheduleRows(on: Day.today) }
                    }
                    .overlay { if store.state.tasks.isEmpty && store.state.assessments.isEmpty && store.state.schedule.isEmpty { ContentUnavailableView("Your day starts here", systemImage: "sun.max", description: Text("Add work with the + button.")) } }
                    .navigationTitle("Today").toolbar { mainToolbar }
                }
            }
            Tab("Tasks", systemImage: "checklist") {
                NavigationStack {
                    List {
                        Section("Open work") { taskRows(filteredTasks.filter { !$0.isFinished }) }
                        Section("Lists") {
                            ForEach(store.state.courses) { course in
                                NavigationLink {
                                    PhoneCourse(store: store, courseID: course.id, edit: { sheet = $0 })
                                } label: { Label(course.name, systemImage: "folder").foregroundStyle(phoneTint(course.color)) }
                            }
                            Button("New list", systemImage: "folder.badge.plus") { sheet = .course(Course(name: "")) }
                        }
                        Section("Archive") { taskRows(filteredTasks.filter(\.isFinished)) }
                    }
                    .searchable(text: $query, prompt: "Tasks and lists")
                    .navigationTitle("Tasks").toolbar { mainToolbar }
                }
            }
            Tab("Calendar", systemImage: "calendar") {
                NavigationStack {
                    List {
                        DatePicker("Day", selection: $day, displayedComponents: .date).datePickerStyle(.graphical)
                        Section("Work") { taskRows(store.state.tasks.filter { $0.due == dayKey || $0.planned == dayKey || ($0.isFinished && $0.completedOn == dayKey) }) }
                        Section("Assessments") {
                            ForEach(store.state.assessments.filter { $0.day == dayKey }) { value in
                                Button { sheet = .assessment(value) } label: { Label(value.title, systemImage: "graduationcap") }.foregroundStyle(.primary)
                            }
                        }
                        Section("Schedule") { scheduleRows(on: dayKey) }
                    }
                    .navigationTitle("Calendar").toolbar { mainToolbar }
                }
            }
            Tab("Journal", systemImage: "book.closed") {
                NavigationStack {
                    PhoneJournal(store: store).navigationTitle("Journal").toolbar { mainToolbar }
                }
            }
            Tab("Rhythm", systemImage: "repeat") {
                NavigationStack {
                    List {
                        ForEach(store.state.rules) { value in
                            Button { sheet = .rhythm(value) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(value.title).foregroundStyle(.primary)
                                    Text(value.summary).font(.caption).foregroundStyle(.secondary)
                                    if !value.enabled { Text("Paused").font(.caption) }
                                }.padding(.vertical, 4)
                            }
                        }
                        Button("New rhythm", systemImage: "plus") { sheet = .rhythm(QuizRule(title: "")) }
                    }
                    .navigationTitle("Rhythm").toolbar { mainToolbar }
                }
            }
        }
        .tint(.blue)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .sheet(item: $sheet) { value in
            NavigationStack {
                switch value {
                case .task(let draft): PhoneTaskEditor(store: store, draft: draft)
                case .course(let draft): PhoneCourseEditor(store: store, draft: draft)
                case .assessment(let draft): PhoneAssessmentEditor(store: store, draft: draft)
                case .schedule(let draft): PhoneScheduleEditor(store: store, draft: draft)
                case .rhythm(let draft): PhoneRhythmEditor(store: store, draft: draft)
                }
            }
        }
        .sheet(isPresented: $settings) { NavigationStack { PhoneSettings(store: store, sync: sync) } }
        .alert("Unable to save", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    @ToolbarContentBuilder private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { Button("Settings", systemImage: "gearshape") { settings = true } }
        ToolbarItem(placement: .topBarTrailing) {
            Menu("Add", systemImage: "plus") {
                Button("Task", systemImage: "checkmark.circle") { sheet = .task(StudyTask()) }
                Button("Progress", systemImage: "chart.bar") { sheet = .task(StudyTask(kind: .progress)) }
                Button("Assessment", systemImage: "graduationcap") { sheet = .assessment(Assessment(day: dayKey)) }
                Button("Schedule block", systemImage: "clock") { sheet = .schedule(ScheduleBlock(day: dayKey)) }
                Button("List", systemImage: "folder") { sheet = .course(Course(name: "")) }
                Button("Rhythm", systemImage: "repeat") { sheet = .rhythm(QuizRule(title: "")) }
            }
        }
    }
    @ViewBuilder private func taskRows(_ tasks: [StudyTask]) -> some View {
        ForEach(tasks) { value in
            HStack(spacing: 12) {
                Button {
                    if value.kind == .progress { sheet = .task(value) }
                    else { var next = value; next.completed.toggle(); store.save(next) }
                } label: {
                    Image(systemName: value.isFinished ? "checkmark.circle.fill" : value.kind == .progress ? "chart.bar" : "circle")
                        .font(.title2).frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(phoneTint(store.course(value.courseID)?.color ?? "blue"))
                    .accessibilityLabel(value.kind == .progress ? "Edit progress" : value.isFinished ? "Mark incomplete" : "Complete task")
                Button { sheet = .task(value) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(value.title).strikethrough(value.isFinished).foregroundStyle(.primary)
                        if let course = store.course(value.courseID) { Text(course.name).font(.caption).foregroundStyle(phoneTint(course.color)) }
                        if value.kind == .progress { ProgressView(value: value.fraction); Text(value.progressLabel).font(.caption).foregroundStyle(.secondary) }
                        if let due = value.due { Text("Due " + Day.label(due)).font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                }.buttonStyle(.plain)
            }
        }
    }
    @ViewBuilder private func scheduleRows(on day: String) -> some View {
        let blocks = (store.state.schedule.filter { $0.day == day } + store.state.courses.flatMap { $0.classBlocks(on: day) }).sorted { $0.startMinute < $1.startMinute }
        ForEach(blocks) { value in
            Button { if !value.id.hasPrefix("class:") { sheet = .schedule(value) } } label: {
                VStack(alignment: .leading, spacing: 5) { Text(value.title); Text(value.isAllDay ? "All day" : value.timeLabel).font(.caption).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            }.foregroundStyle(phoneTint(store.course(value.courseID)?.color ?? "blue"))
        }
    }
}

private func phoneTint(_ name: String) -> Color {
    if name.hasPrefix("#"), let value = UInt32(name.dropFirst(), radix: 16) {
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    switch name {
    case "purple": return .purple
    case "pink": return .pink
    case "orange": return .orange
    case "red": return .red
    case "green": return .green
    case "teal": return .teal
    case "indigo": return .indigo
    case "cyan": return .cyan
    case "mint": return .mint
    case "yellow": return .yellow
    case "brown": return .brown
    default: return .blue
    }
}

private struct CoursePicker: View {
    var store: Store
    @Binding var selection: String?
    var body: some View {
        Picker("List", selection: $selection) {
            Text("Inbox").tag(String?.none)
            ForEach(store.state.courses) { Text($0.name).tag(Optional($0.id)) }
        }
    }
}

private struct OptionalDayPicker: View {
    var title: String
    @Binding var value: String?
    var body: some View {
        Toggle(title, isOn: Binding(get: { value != nil }, set: { value = $0 ? Day.today : nil }))
        if value != nil {
            DatePicker(title, selection: Binding(get: { Day.date(value ?? Day.today) }, set: { value = Day.string($0) }), displayedComponents: .date)
        }
    }
}

private struct EditorActions: ToolbarContent {
    var valid: Bool
    var save: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).buttonStyle(.glassProminent).disabled(!valid) }
    }
}

private struct PhoneTaskEditor: View {
    var store: Store
    @State var draft: StudyTask
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section("Work") {
                TextField("Title", text: $draft.title, axis: .vertical)
                CoursePicker(store: store, selection: $draft.courseID)
                Picker("Type", selection: $draft.kind) { Text("Task").tag(TaskKind.checkbox); Text("Progress").tag(TaskKind.progress) }
                if draft.kind == .progress {
                    TextField("Start", value: $draft.start, format: .number).keyboardType(.numberPad)
                    TextField("Finish", value: $draft.target, format: .number).keyboardType(.numberPad)
                    TextField("Current page", value: $draft.current, format: .number).keyboardType(.numberPad)
                    Toggle("Finished", isOn: Binding(get: { draft.current > draft.target }, set: { draft.current = $0 ? draft.target + 1 : draft.start }))
                } else { Toggle("Completed", isOn: $draft.completed) }
            }
            Section("Dates") { OptionalDayPicker(title: "Deadline", value: $draft.due); OptionalDayPicker(title: "Planned", value: $draft.planned) }
            Section("Notes") { TextEditor(text: $draft.notes).frame(minHeight: 180) }
            if store.state.tasks.contains(where: { $0.id == draft.id }) {
                Section { Button("Delete task", role: .destructive) { store.deleteTask(draft.id); if store.error == nil { dismiss() } } }
            }
        }.navigationTitle(draft.kind == .progress ? "Progress" : "Task").navigationBarTitleDisplayMode(.inline)
        .toolbar { EditorActions(valid: !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.target >= draft.start) {
            if draft.kind == .progress { draft.current = draft.clampedProgress(draft.current) }
            store.save(draft); if store.error == nil { dismiss() }
        } }
    }
}

private struct PhoneCourseEditor: View {
    var store: Store
    @State var draft: Course
    @Environment(\.dismiss) private var dismiss
    @State private var delete = false
    var body: some View {
        Form {
            Section("List") {
                TextField("Name", text: $draft.name)
                Picker("Color", selection: $draft.color) {
                    ForEach(["blue", "purple", "pink", "orange", "red", "brown", "green", "teal", "indigo", "cyan", "mint", "yellow"], id: \.self) { Text($0.capitalized).tag($0) }
                    if draft.color.hasPrefix("#") { Text("Custom").tag(draft.color) }
                }
                TextField("Group", text: Binding(get: { draft.group ?? "" }, set: { draft.group = $0.isEmpty ? nil : $0 }))
            }
            Section("Class times") {
                ForEach(Array((draft.classTimes ?? draft.resolvedClassTimes).enumerated()), id: \.element.id) { index, time in
                    VStack(alignment: .leading) {
                        Text(time.days.sorted().map { Calendar.current.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", "))
                        Text(ClockTime.label(time.startMinute) + "–" + ClockTime.label(time.endMinute)).foregroundStyle(.secondary)
                        Button("Remove time", role: .destructive) { var times = draft.classTimes ?? draft.resolvedClassTimes; times.remove(at: index); draft.classTimes = times }
                    }
                }
                PhoneClassTimeAdder { time in draft.classTimes = (draft.classTimes ?? draft.resolvedClassTimes) + [time] }
            }
            if store.state.courses.contains(where: { $0.id == draft.id }) { Section { Button("Delete list", role: .destructive) { delete = true } } }
        }.navigationTitle("List").navigationBarTitleDisplayMode(.inline)
        .toolbar { EditorActions(valid: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { store.save(draft); if store.error == nil { dismiss() } } }
        .confirmationDialog("Delete this list? Its work will move to Inbox. List notes will be deleted.", isPresented: $delete, titleVisibility: .visible) {
            Button("Delete list", role: .destructive) { store.deleteCourse(draft.id); if store.error == nil { dismiss() } }
        }
    }
}

private struct PhoneClassTimeAdder: View {
    var add: (ClassTime) -> Void
    @State private var days: Set<Int> = Set(2...6)
    @State private var start = 540
    @State private var end = 590
    var body: some View {
        DisclosureGroup("Add class time") {
            WeekdaysPicker(days: $days)
            MinutePicker(title: "Start", minute: $start)
            MinutePicker(title: "End", minute: $end)
            Button("Add time") { add(ClassTime(startMinute: start, endMinute: end, days: days.sorted())) }.disabled(days.isEmpty || end <= start)
        }
    }
}

private struct WeekdaysPicker: View {
    @Binding var days: Set<Int>
    var body: some View {
        ForEach(1...7, id: \.self) { day in
            Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(get: { days.contains(day) }, set: { if $0 { days.insert(day) } else { days.remove(day) } }))
        }
    }
}
private struct MinutePicker: View {
    var title: String
    @Binding var minute: Int
    var body: some View {
        DatePicker(title, selection: Binding(get: {
            Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(minute * 60))
        }, set: { minute = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) }), displayedComponents: .hourAndMinute)
    }
}

private struct PhoneAssessmentEditor: View {
    var store: Store
    @State var draft: Assessment
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            TextField("Title", text: $draft.title, axis: .vertical)
            CoursePicker(store: store, selection: $draft.courseID)
            DatePicker("Date", selection: Binding(get: { Day.date(draft.day) }, set: { draft.day = Day.string($0) }), displayedComponents: .date)
            Section("Topics") { TextEditor(text: $draft.topics).frame(minHeight: 180) }
            if store.state.assessments.contains(where: { $0.id == draft.id }) { Button("Delete assessment", role: .destructive) { store.deleteAssessment(draft.id); if store.error == nil { dismiss() } } }
        }.navigationTitle("Assessment").navigationBarTitleDisplayMode(.inline)
        .toolbar { EditorActions(valid: !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { store.save(draft); if store.error == nil { dismiss() } } }
    }
}

private struct PhoneScheduleEditor: View {
    var store: Store
    @State var draft: ScheduleBlock
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            TextField("Title", text: $draft.title, axis: .vertical)
            CoursePicker(store: store, selection: $draft.courseID)
            DatePicker("Date", selection: Binding(get: { Day.date(draft.day) }, set: { draft.day = Day.string($0) }), displayedComponents: .date)
            Toggle("All day", isOn: Binding(get: { draft.isAllDay }, set: { draft.allDay = $0 }))
            if !draft.isAllDay {
                MinutePicker(title: "Start", minute: $draft.startMinute)
                Stepper("Duration: \(draft.duration) minutes", value: $draft.duration, in: 5...1440, step: 5)
            }
            Section("Notes") { TextEditor(text: $draft.notes).frame(minHeight: 180) }
            if store.state.schedule.contains(where: { $0.id == draft.id }) { Button("Delete this block", role: .destructive) { store.deleteSchedule(draft, scope: .thisEvent); if store.error == nil { dismiss() } } }
        }.navigationTitle("Schedule block").navigationBarTitleDisplayMode(.inline)
        .toolbar { EditorActions(valid: !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (draft.isAllDay || draft.startMinute + draft.duration <= 1440)) { store.save(draft); if store.error == nil { dismiss() } } }
    }
}

private struct PhoneRhythmEditor: View {
    var store: Store
    @State var draft: QuizRule
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            TextField("Title", text: $draft.title, axis: .vertical)
            CoursePicker(store: store, selection: $draft.courseID)
            Toggle("Enabled", isOn: $draft.enabled)
            Picker("Repeats", selection: Binding(get: { draft.kind }, set: { draft.itemKind = $0 })) { ForEach(RepeatItem.allCases) { Text($0.rawValue).tag($0) } }
            if draft.kind == .task {
                Picker("Task type", selection: Binding(get: { draft.taskKind ?? .checkbox }, set: { draft.taskKind = $0 })) { Text("Task").tag(TaskKind.checkbox); Text("Progress").tag(TaskKind.progress) }
                if draft.taskKind == .progress {
                    TextField("Start", value: Binding(get: { draft.startCount ?? 1 }, set: { draft.startCount = $0 }), format: .number).keyboardType(.numberPad)
                    TextField("Finish", value: Binding(get: { draft.targetCount ?? 30 }, set: { draft.targetCount = $0 }), format: .number).keyboardType(.numberPad)
                }
            }
            Section("Days") { WeekdaysPicker(days: Binding(get: { draft.days }, set: { draft.weekdays = $0.sorted() })) }
            Stepper("Every \(draft.intervalWeeks ?? 1) week(s)", value: Binding(get: { draft.intervalWeeks ?? 1 }, set: { draft.intervalWeeks = $0 }), in: 1...52)
            OptionalDayPicker(title: "Start date", value: $draft.startDate)
            OptionalDayPicker(title: "End date", value: $draft.endDate)
            if draft.kind == .schedule {
                MinutePicker(title: "Start", minute: Binding(get: { draft.startMinute ?? 540 }, set: { draft.startMinute = $0 }))
                Stepper("Duration: \(draft.duration ?? 60) minutes", value: Binding(get: { draft.duration ?? 60 }, set: { draft.duration = $0 }), in: 5...1440, step: 5)
            }
            Section("Notes") { TextEditor(text: Binding(get: { draft.notes ?? "" }, set: { draft.notes = $0 })).frame(minHeight: 160) }
            if store.state.rules.contains(where: { $0.id == draft.id }) { Button("Delete rhythm and its future occurrences", role: .destructive) { store.deleteRule(draft.id); if store.error == nil { dismiss() } } }
        }.navigationTitle("Rhythm").navigationBarTitleDisplayMode(.inline)
        .toolbar { EditorActions(valid: !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draft.days.isEmpty && (draft.endDate == nil || draft.startDate == nil || draft.endDate! >= draft.startDate!) && (draft.taskKind != .progress || (draft.targetCount ?? 30) >= (draft.startCount ?? 1)) && (draft.kind != .schedule || (draft.startMinute ?? 540) + (draft.duration ?? 60) <= 1440)) { store.saveRule(draft); if store.error == nil { dismiss() } } }
    }
}
#endif
