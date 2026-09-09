import SwiftUI

struct InlineProgress: View {
    var store: Store
    var task: StudyTask
    @State private var value: Double
    @State private var number: Int
    @FocusState private var editing: Bool
    init(store: Store, task: StudyTask) {
        self.store = store; self.task = task
        _value = State(initialValue: Double(task.current)); _number = State(initialValue: task.current)
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { controls; progressSlider.frame(width: 140) }
            VStack(alignment: .leading, spacing: 3) { controls; progressSlider.frame(maxWidth: 240) }
        }
        .onChange(of: editing) { old, new in if old && !new { apply(number) } }
        .onChange(of: task.current) { _, current in value = Double(current); number = current }
    }
    private var controls: some View {
        HStack(spacing: 6) {
            Text(task.unit == "pages" ? "Page" : "Through").font(.caption).foregroundStyle(.secondary).fixedSize()
            TextField("Current progress", value: $number, format: .number.grouping(.never)).textFieldStyle(.plain).multilineTextAlignment(.trailing)
                .font(.system(size: 13, weight: .medium, design: .monospaced)).frame(width: 45).focused($editing).onSubmit { apply(number) }
                .padding(.horizontal, 5).padding(.vertical, 3).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
            Text("/ \(task.target)").font(.caption).foregroundStyle(.secondary).fixedSize()
            Button { apply(task.current - 1) } label: { Image(systemName: "minus").frame(width: 20, height: 20) }.buttonStyle(.borderless).disabled(task.current < task.start).help("Previous \(task.unit == "pages" ? "page" : "unit")")
            Button { apply(task.current + 1) } label: { Image(systemName: "plus").frame(width: 20, height: 20) }.buttonStyle(.borderless).disabled(task.current >= task.target).help("Next \(task.unit == "pages" ? "page" : "unit")")
        }.fixedSize()
    }
    private var progressSlider: some View {
        Slider(value: $value, in: Double(task.start - 1)...Double(max(task.start, task.target))) { isDragging in
            if !isDragging { apply(Int(value.rounded())) }
        }.controlSize(.small).tint(store.course(task.courseID)?.tint ?? .accentColor)
            .accessibilityLabel("Progress for " + task.title)
            .onChange(of: value) { _, new in if !editing { number = Int(new.rounded()) } }
    }
    private func apply(_ updated: Int) {
        let bounded = min(task.target, max(task.start - 1, updated))
        store.updateProgress(task.id, to: bounded)
        value = Double(bounded); number = bounded
    }
}

struct TaskLine: View {
    var store: Store
    var task: StudyTask
    var selected: Bool
    var openDetails: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    var updated = task; updated.completed.toggle(); store.save(updated)
                } label: {
                    Image(systemName: task.completed ? "checkmark.circle.fill" : "circle").font(.system(size: 18)).foregroundStyle(task.completed ? Color.accentColor : Color.secondary)
                }.buttonStyle(.borderless).help(task.completed ? "Reopen task" : "Complete task")
                VStack(alignment: .leading, spacing: 3) {
                    Button(action: openDetails) { Text(task.title).font(.system(size: 14, weight: .medium)).strikethrough(task.completed).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                    HStack(spacing: 5) {
                        if let course = store.course(task.courseID) { Circle().fill(course.tint).frame(width: 5, height: 5); Text(course.shortName) }
                        if task.kind == .progress { Text(task.progressLabel) }
                        if let due = task.due { Text("· Due " + Day.label(due)).foregroundStyle(due < Day.today && !task.completed ? Color.red : .secondary) }
                        if task.ruleID != nil { Image(systemName: "repeat") }
                        if !task.notes.isEmpty { Image(systemName: "note.text") }
                    }.font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if task.kind == .progress { InlineProgress(store: store, task: task).padding(.leading, 28) }
            if task.kind == .practice {
                HStack {
                    let sessions = store.state.activities.filter { $0.taskID == task.id }
                    Text("\(sessions.count) sessions" + (sessions.last.map { " · " + Day.label(Day.string($0.date)) } ?? "")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Log session") { store.record(task, value: nil, note: "Practiced") }.buttonStyle(.borderless)
                    Menu {
                        ForEach(["Reviewed", "Attempted", "Solved with help", "Solved independently"], id: \.self) { outcome in
                            Button(outcome) { store.record(task, value: nil, note: outcome) }
                        }
                    } label: { Image(systemName: "chevron.down") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28, height: 24)
                }.padding(.leading, 28)
            }
        }.padding(.vertical, task.kind == .progress ? 8 : 5).contentShape(Rectangle()).opacity(task.completed ? 0.55 : 1)
    }
}

struct TaskInspector: View {
    var store: Store
    @State var draft: StudyTask
    @State private var baseline: StudyTask
    var close: () -> Void
    @State private var preview = false
    init(store: Store, task: StudyTask, close: @escaping () -> Void) {
        self.store = store; self.close = close
        _draft = State(initialValue: task); _baseline = State(initialValue: task)
    }
    private var valid: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (draft.kind != .progress || (draft.start > 0 && draft.target >= draft.start && draft.target <= 1000000 && draft.current >= draft.start - 1 && draft.current <= draft.target))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Task details").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.caption) }.buttonStyle(.plain).help("Close details")
            }.padding(16)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Task title", text: $draft.title, axis: .vertical).textFieldStyle(.plain).font(.system(size: 19, weight: .semibold)).lineLimit(1...5)
                    Divider()
                    VStack(spacing: 0) {
                        PropertyRow("List") { CourseMenu(courses: store.state.courses, value: $draft.courseID) }
                        PropertyRow("Plan") { DateMenu(title: "Anytime", value: $draft.planned) }
                        PropertyRow("Due") { DateMenu(title: "No deadline", value: $draft.due) }
                        PropertyRow("Track") { Picker("Tracking", selection: $draft.kind) { ForEach(TaskKind.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().pickerStyle(.menu) }
                    }
                    if draft.kind == .progress {
                        Divider()
                        VStack(spacing: 0) {
                            PropertyRow("Unit") { TextField("pages", text: $draft.unit).textFieldStyle(.plain) }
                            PropertyRow("Range") {
                                HStack {
                                    TextField("Start", value: $draft.start, format: .number.grouping(.never)).frame(width: 55)
                                    Text("to").foregroundStyle(.secondary)
                                    TextField("End", value: $draft.target, format: .number.grouping(.never)).frame(width: 55)
                                }.textFieldStyle(.roundedBorder)
                            }
                        }
                        InlineProgress(store: store, task: store.state.tasks.first { $0.id == draft.id } ?? draft)
                    }
                    Divider()
                    HStack {
                        Text("Notes").font(.system(size: 13, weight: .medium))
                        Spacer()
                        Button(preview ? "Edit" : "Preview") { preview.toggle() }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                    }
                    if preview { NotesPreview(text: $draft.notes).frame(maxWidth: .infinity, alignment: .leading) }
                    else {
                        ZStack(alignment: .topLeading) {
                            if draft.notes.isEmpty { Text("Notes, links, or a checklist…").font(.callout).foregroundStyle(.tertiary).padding(.leading, 4).allowsHitTesting(false) }
                            TextEditor(text: $draft.notes).font(.system(size: 13)).scrollContentBackground(.hidden).frame(minHeight: 120)
                        }
                    }
                    let entries = store.state.activities.filter { $0.taskID == draft.id }.suffix(5).reversed()
                    if !entries.isEmpty {
                        DisclosureGroup("Recent activity") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(entries) { entry in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.note)
                                        Text(entry.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                                    }.font(.caption)
                                }
                            }.padding(.top, 8)
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    if !valid { Text("Check the title and progress range.").font(.caption).foregroundStyle(.orange) }
                }.padding(.horizontal, 16).padding(.bottom, 16)
            }
        }.background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .task(id: draft) { do { try await Task.sleep(for: .milliseconds(400)); commit() } catch { } }
        .onDisappear { commit() }
        .onChange(of: draft.start) { old, new in if draft.current == old - 1 { draft.current = new - 1 } }
        .onChange(of: store.state.tasks.first { $0.id == draft.id }) { _, current in
            if let current, current != baseline { let merged = StudyTask.merging(draft: draft, baseline: baseline, latest: current); baseline = current; draft = merged }
        }
    }
    private func commit() {
        guard valid, draft != baseline, let latest = store.state.tasks.first(where: { $0.id == draft.id }) else { return }
        var saved = StudyTask.merging(draft: draft, baseline: baseline, latest: latest)
        saved.title = saved.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if saved.kind == .progress && (saved.current != baseline.current || saved.target != baseline.target) { saved.completed = saved.current >= saved.target }
        store.save(saved)
        if store.error == nil { baseline = saved; draft = saved }
    }
}

struct DateMenu: View {
    var title: String
    @Binding var value: String?
    @State private var calendar = false
    var body: some View {
        Menu {
            Button("Today") { value = Day.today }
            Button("Tomorrow") { value = Day.adding(1) }
            Button("Choose date…") { calendar = true }
            if value != nil { Divider(); Button("Clear date") { value = nil } }
        } label: { Text(value.map(Day.label) ?? title) }.menuStyle(.borderlessButton).fixedSize()
            .popover(isPresented: $calendar) {
                VStack {
                    DatePicker(title, selection: Binding(get: { Day.date(value ?? Day.today) }, set: { value = Day.string($0) }), displayedComponents: .date).datePickerStyle(.graphical)
                    Button("Done") { if value == nil { value = Day.today }; calendar = false }
                }.padding(12)
            }
    }
}

struct NotesPreview: View {
    @Binding var text: String
    var body: some View {
        let lines = text.components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                    let checked = !line.hasPrefix("- [ ] ")
                    Toggle(isOn: Binding(get: { checked }, set: { value in
                        var changed = text.components(separatedBy: "\n")
                        guard index < changed.count else { return }
                        changed[index] = (value ? "- [x] " : "- [ ] ") + String(changed[index].dropFirst(6))
                        text = changed.joined(separator: "\n")
                    })) { Text(.init(String(line.dropFirst(6)))).strikethrough(checked) }.toggleStyle(.checkbox)
                } else if line.hasPrefix("# ") { Text(String(line.dropFirst(2))).font(.title3.bold()) }
                else if line.hasPrefix("## ") { Text(String(line.dropFirst(3))).font(.headline) }
                else { Text(.init(line.isEmpty ? " " : line)).textSelection(.enabled) }
            }
        }.font(.callout)
    }
}
