import OpusCore
import SwiftUI

struct ClassScheduleCard: View {
    var store: Store
    var course: Course
    var block: ScheduleBlock
    @State private var editingCourse = false
    @State private var showingWork = false
    private var assessments: [Assessment] { CourseWork.assessments(courseID: course.id, from: block.day, in: store.state) }
    private var tasks: [StudyTask] { CourseWork.tasks(courseID: course.id, from: block.day, in: store.state, progress: false) }
    private var progress: [StudyTask] { CourseWork.tasks(courseID: course.id, from: block.day, in: store.state, progress: true, exactDay: true) }
    var body: some View {
        Button { showingWork = true } label: {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.primary.opacity(0.0001))
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.shortName).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    HStack(spacing: 5) {
                        Text(ClockTime.label(block.startMinute)).lineLimit(1)
                        Spacer(minLength: 2)
                        if !tasks.isEmpty { Label("\(tasks.count)", systemImage: "checkmark.circle").labelStyle(.titleAndIcon) }
                        if !progress.isEmpty { Label("\(progress.count)", systemImage: "chart.bar.fill").labelStyle(.titleAndIcon) }
                        if !assessments.isEmpty { Label("\(assessments.count)", systemImage: "calendar").labelStyle(.titleAndIcon) }
                    }.font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.86))
                }.padding(4)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .foregroundStyle(.white)
            .background(course.scheduleGradient, in: RoundedRectangle(cornerRadius: 5))
            .popover(isPresented: $showingWork) {
                CourseWorkPopover(store: store, course: course, from: block.day)
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
    private var assessments: [Assessment] { CourseWork.assessments(courseID: course.id, from: from, in: store.state) }
    private var tasks: [StudyTask] { CourseWork.tasks(courseID: course.id, from: from, in: store.state, progress: false) }
    private var progress: [StudyTask] { CourseWork.tasks(courseID: course.id, from: from, in: store.state, progress: true, exactDay: true) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(course.tint).frame(width: 9, height: 9)
                Text(course.name).font(.headline)
                Spacer()
                Text("Upcoming").font(.caption).foregroundStyle(.secondary)
            }.padding(.bottom, 12)

            if assessments.isEmpty && tasks.isEmpty && progress.isEmpty {
                ContentUnavailableView("No upcoming work", systemImage: "checkmark.circle", description: Text("Nothing dated for this class after \(Day.label(from))."))
                    .frame(width: 320, height: 150)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !assessments.isEmpty {
                            sectionTitle("Assessments", count: assessments.count)
                            ForEach(assessments) { assessmentRow($0) }
                        }
                        if !tasks.isEmpty {
                            sectionTitle("Tasks", count: tasks.count)
                            ForEach(tasks) { taskRow($0) }
                        }
                        if !progress.isEmpty {
                            sectionTitle("Progress", count: progress.count)
                            ForEach(progress) { progressRow($0) }
                        }
                    }
                }.frame(width: 360).frame(maxHeight: 420)
            }
        }.padding(16)
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
            if item.ruleID != nil { RepeatBadge() }
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
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.completed ? course.tint : .secondary)
                    .frame(width: 16)
            }.buttonStyle(.plain).help(task.completed ? "Reopen task" : "Complete task")
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(task.title).strikethrough(task.completed).lineLimit(2)
                    Spacer(minLength: 8)
                    if task.ruleID != nil { RepeatBadge() }
                    if let date = CourseWork.relevantDay(for: task, from: from) {
                        Text(Day.label(date)).font(.caption).foregroundStyle(.secondary).fixedSize()
                    }
                }
            }
        }.font(.system(size: 13)).opacity(task.completed ? 0.55 : 1)
    }
    private func progressRow(_ task: StudyTask) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "chart.bar.fill").foregroundStyle(course.tint).frame(width: 16)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(task.title).lineLimit(2)
                    if task.ruleID != nil { RepeatBadge() }
                    Spacer(minLength: 8)
                    if let date = CourseWork.relevantDay(for: task, from: from) {
                        Text(Day.label(date)).font(.caption).foregroundStyle(.secondary).fixedSize()
                    }
                }
                CompactTaskProgress(store: store, task: task)
            }
        }.font(.system(size: 13))
    }
}
