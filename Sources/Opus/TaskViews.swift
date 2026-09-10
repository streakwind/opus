import SwiftUI

struct InlineProgress: View {
    var store: Store
    var task: StudyTask
    var showsPace: Bool
    @State private var number: Int
    @FocusState private var editing: Bool
    init(store: Store, task: StudyTask, showsPace: Bool = true) {
        self.store = store; self.task = task; self.showsPace = showsPace
        _number = State(initialValue: task.current)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            controls
            if showsPace, let pace = task.pacing(on: Day.today) {
                Text(pace).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: editing) { old, new in if old && !new { apply(number) } }
        .onChange(of: task.current) { _, current in number = current }
    }
    private var controls: some View {
        HStack(spacing: 6) {
            Text("p.").font(.caption).foregroundStyle(.secondary).fixedSize()
            TextField("Last page read", value: $number, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                .font(.system(size: 13, weight: .medium, design: .monospaced)).frame(width: 48).focused($editing).onSubmit { apply(number) }
                .accessibilityLabel("Last page read").help("Enter a page and press Return")
            Text("/ \(task.target)").font(.caption).foregroundStyle(.secondary).fixedSize()

        }.fixedSize().help("Log the last page you read · " + task.progressLabel)
    }
    private func apply(_ updated: Int) {
        let bounded = min(task.target, max(task.start - 1, updated))
        store.updateProgress(task.id, to: bounded)
        number = bounded
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
                    Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18)).foregroundStyle(task.completed ? Color.accentColor : Color.secondary)
                }.buttonStyle(.borderless).help(task.completed ? "Reopen task" : "Complete task")
                VStack(alignment: .leading, spacing: 3) {
                    Button(action: openDetails) { Text(task.title).font(.system(size: 14, weight: .medium)).strikethrough(task.completed).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                    HStack(spacing: 5) {
                        if let course = store.course(task.courseID) { Circle().fill(course.tint).frame(width: 5, height: 5); Text(course.shortName) }
                        if let due = task.due { Text("· Due " + Day.label(due)).foregroundStyle(due < Day.today && !task.completed ? Color.red : .secondary) }
                        if task.planned == Day.adding(1), task.due != task.planned { Text("· Tomorrow") }
                        if task.ruleID != nil { Image(systemName: "repeat") }
                    }.font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                if task.kind == .progress {
                    InlineProgress(store: store, task: task, showsPace: false)
                }
            }



        }.padding(.vertical, 5).contentShape(Rectangle()).opacity(task.completed ? 0.55 : 1)
    }
}

struct TaskInspector: View {
    var store: Store
    @State var draft: StudyTask
    @State private var baseline: StudyTask
    var close: () -> Void
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
                    VStack(spacing: 0) {
                        PropertyRow("List") { CourseMenu(courses: store.state.courses, value: $draft.courseID) }
                        PropertyRow("Plan") { DateMenu(title: "Anytime", value: $draft.planned) }
                        PropertyRow("Due") { DateMenu(title: "No deadline", value: $draft.due) }
                        PropertyRow("Track") { PillPicker("Tracking", label: draft.kind == .progress ? "Textbook notes" : "Task", selection: $draft.kind) { ForEach([TaskKind.checkbox, .progress]) { Text($0 == .progress ? "Textbook notes" : "Task").tag($0) } }.labelsHidden().pickerStyle(.menu) }
                    }
                    if draft.kind == .progress {
                        VStack(spacing: 0) {
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
        Button(value.map(Day.label) ?? title) { calendar = true }.roundedControls()
            .popover(isPresented: $calendar) {
                CompactDatePicker(value: $value) { calendar = false }
            }
    }
}
