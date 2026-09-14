import OpusCore
import SwiftUI
import Observation

@MainActor @Observable
final class TaskCompletionPresentation {
    private var pending: [String: UUID] = [:]

    func filteringTask(_ task: StudyTask) -> StudyTask {
        var result = task
        if pending[task.id] != nil { result.completed = false }
        return result
    }

    func toggle(_ task: StudyTask, store: Store) {
        guard var updated = store.state.tasks.first(where: { $0.id == task.id }) else { return }
        updated.completed.toggle()
        let token = UUID()
        if updated.completed { pending[task.id] = token }
        else { pending[task.id] = nil }
        store.save(updated)
        guard store.error == nil, updated.completed else {
            pending[task.id] = nil
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, self.pending[task.id] == token else { return }
            withAnimation(.easeInOut(duration: 0.28)) { self.pending[task.id] = nil }
        }
    }
}

struct InlineProgress: View {
    var store: Store
    var task: StudyTask
    @State private var number: Int
    @FocusState private var editing: Bool
    init(store: Store, task: StudyTask) {
        self.store = store; self.task = task
        _number = State(initialValue: task.current)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(task.progressLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(Int((task.fraction * 100).rounded()))%")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: task.fraction)
                .tint(store.course(task.courseID)?.tint ?? Color.accentColor)
            controls
            if let pace = task.pacing(on: Day.today) {
                Text(pace).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.045))
        }
        .onChange(of: editing) { old, new in if old && !new { apply(number) } }
        .onChange(of: task.current) { _, current in number = current }
    }
    private var controls: some View {
        HStack(spacing: 10) {
            Text("Through").font(.caption).foregroundStyle(.secondary)
            Spacer()
            TextField("Through", value: $number, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                .font(.system(size: 13, weight: .medium, design: .monospaced)).frame(width: 68).focused($editing).onSubmit { apply(number) }
                .accessibilityLabel("Through").help("Enter a number and press Return")
        }.help(task.progressLabel)
    }
    private func apply(_ updated: Int) {
        let bounded = task.clampedProgress(updated)
        store.updateProgress(task.id, to: bounded)
        number = bounded
    }
}

struct CompactTaskProgress: View {
    var store: Store
    var task: StudyTask
    var body: some View {
        HStack(spacing: 7) {
            ProgressView(value: task.fraction)
                .tint(store.course(task.courseID)?.tint ?? Color.accentColor)
                .frame(width: 72)
            Text(task.progressLabel).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

struct ProgressLine: View {
    var store: Store
    var task: StudyTask
    var openDetails: () -> Void
    var body: some View {
        Button(action: openDetails) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(store.course(task.courseID)?.tint ?? Color.accentColor)
                    .frame(width: 18, height: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).font(.system(size: 14, weight: .medium)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 5) {
                        if let course = store.course(task.courseID) { Circle().fill(course.tint).frame(width: 5, height: 5); Text(course.shortName) }
                        else { Text("Inbox") }
                        if let caption = task.rhythmCaption() {
                            Text("· " + caption).foregroundStyle(task.due.map { $0 < Day.today ? Color.red : .secondary } ?? .secondary)
                        } else if let due = task.due {
                            Text("· Goal " + Day.label(due)).foregroundStyle(due < Day.today ? Color.red : .secondary)
                        }
                    }.font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).padding(.top, 1)
                }
                CompactTaskProgress(store: store, task: task).frame(width: 180, alignment: .trailing)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("progress-row-\(task.id)")
    }
}

struct TaskLine: View {
    var store: Store
    var task: StudyTask
    var selected: Bool
    var completionPresentation: TaskCompletionPresentation? = nil
    var openDetails: () -> Void
    private var struck: Bool { task.completed }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: toggleComplete) {
                Image(systemName: struck ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18)).foregroundStyle(struck ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(task.completed ? "Reopen task" : "Complete task")
            .accessibilityIdentifier("task-complete-\(task.id)")

            Button(action: openDetails) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).font(.system(size: 14, weight: .medium)).strikethrough(struck).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 5) {
                        if let course = store.course(task.courseID) { Circle().fill(course.tint).frame(width: 5, height: 5); Text(course.shortName) }
                        else { Text("Inbox") }
                        if let caption = task.rhythmCaption() {
                            Text("· " + caption)
                                .foregroundStyle(task.due.map { $0 < Day.today && !struck ? Color.red : .secondary } ?? .secondary)
                        } else {
                            if let due = task.due { Text("· Due " + Day.label(due)).foregroundStyle(due < Day.today && !struck ? Color.red : .secondary) }
                            if task.planned == Day.adding(1), task.due != task.planned { Text("· Tomorrow") }
                        }
                    }.font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    .padding(.top, 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("task-row-\(task.id)")
        }
        .padding(.vertical, 5)
        .opacity(struck ? 0.55 : 1)
    }
    func toggleComplete() {
        if let completionPresentation {
            completionPresentation.toggle(task, store: store)
            return
        }
        var updated = task
        updated.completed.toggle()
        withAnimation(.easeInOut(duration: 0.28)) { store.save(updated) }
    }
}

struct DateMenu: View {
    var title: String
    @Binding var value: String?
    var prefix: String?
    @State private var calendar = false
    init(title: String, value: Binding<String?>, prefix: String? = nil) {
        self.title = title; _value = value; self.prefix = prefix
    }
    var body: some View {
        Button(label) { calendar = true }
            .buttonStyle(.plain)
            .pillChrome()
            .fixedSize()
            .popover(isPresented: $calendar) {
                CompactDatePicker(value: $value, clearLabel: title == "Due date" || title == "No deadline" ? "No due date" : "No date") { calendar = false }
            }
            .accessibilityIdentifier("date-menu")
    }
    private var label: String {
        let date = value.map(Day.label) ?? title
        return prefix.map { "\($0) · \(date)" } ?? date
    }
}
