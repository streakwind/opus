import SwiftUI

struct ClassScheduleCard: View {
    var store: Store
    var course: Course
    var day: String
    @State private var editingCourse = false
    @State private var showingWork = false
    var body: some View {
        Button { showingWork = true } label: {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.primary.opacity(0.0001))
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.shortName).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Text(ClockTime.label(course.classStart ?? 0)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                }.padding(4)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .foregroundStyle(.white)
            .background(course.tint.gradient, in: RoundedRectangle(cornerRadius: 5))
            .popover(isPresented: $showingWork) {
                CourseWorkPopover(store: store, course: course, from: day)
            }
            .contextMenu { Button("Edit class schedule…") { editingCourse = true } }
            .sheet(isPresented: $editingCourse) { CourseEditor(store: store, course: course) }
            .help("Open upcoming work for " + course.name)
    }
}

private struct CourseWorkPopover: View {
    var store: Store
    var course: Course
    var from: String
    private var assessments: [Assessment] {
        var seenRules = Set<String>()
        return store.state.assessments
            .filter { $0.courseID == course.id && $0.day >= from }
            .sorted { $0.day == $1.day ? $0.title < $1.title : $0.day < $1.day }
            .filter { item in
                guard let ruleID = item.ruleID else { return true }
                return seenRules.insert(ruleID).inserted
            }
    }
    private var tasks: [StudyTask] {
        var seenRules = Set<String>()
        return store.state.tasks
            .filter { $0.courseID == course.id && !$0.completed && relevantDay(for: $0) != nil }
            .sorted {
                let lhs = relevantDay(for: $0) ?? "9999"
                let rhs = relevantDay(for: $1) ?? "9999"
                return lhs == rhs ? $0.title < $1.title : lhs < rhs
            }
            .filter { item in
                guard let ruleID = item.ruleID else { return true }
                return seenRules.insert(ruleID).inserted
            }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(course.tint).frame(width: 9, height: 9)
                Text(course.name).font(.headline)
                Spacer()
                Text("Upcoming").font(.caption).foregroundStyle(.secondary)
            }.padding(.bottom, 12)

            if assessments.isEmpty && tasks.isEmpty {
                ContentUnavailableView("No upcoming work", systemImage: "checkmark.circle", description: Text("Nothing dated for this class after \(Day.label(from))."))
                    .frame(width: 320, height: 150)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !assessments.isEmpty {
                            sectionTitle("Assessments", count: assessments.count)
                            ForEach(assessments) { assessmentRow($0) }
                        }
                        if !assessments.isEmpty && !tasks.isEmpty { Divider() }
                        if !tasks.isEmpty {
                            sectionTitle("Tasks", count: tasks.count)
                            ForEach(tasks) { taskRow($0) }
                        }
                    }
                }.frame(width: 360).frame(maxHeight: 420)
            }
        }.padding(16)
    }
    private func relevantDay(for task: StudyTask) -> String? {
        [task.due, task.planned].compactMap { $0 }.filter { $0 >= from }.min()
    }
    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            Text("\(count)").font(.caption2).foregroundStyle(.tertiary)
        }
    }
    private func assessmentRow(_ item: Assessment) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: item.confirmed ? "calendar" : "questionmark.circle")
                .foregroundStyle(course.tint).frame(width: 16)
            Text(item.title).lineLimit(2)
            Spacer(minLength: 8)
            Text(Day.label(item.day)).font(.caption).foregroundStyle(.secondary).fixedSize()
        }.font(.system(size: 13))
    }
    private func taskRow(_ task: StudyTask) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Button {
                var updated = task
                updated.completed.toggle()
                store.save(updated)
            } label: {
                Image(systemName: "circle").foregroundStyle(.secondary).frame(width: 16)
            }.buttonStyle(.plain).help("Complete task")
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(task.title).lineLimit(2)
                    Spacer(minLength: 8)
                    if let date = relevantDay(for: task) {
                        Text(Day.label(date)).font(.caption).foregroundStyle(.secondary).fixedSize()
                    }
                }
                if task.kind == .progress {
                    CompactTaskProgress(store: store, task: task)
                }
            }
        }.font(.system(size: 13))
    }
}
