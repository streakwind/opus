import SwiftUI

struct ClassScheduleCard: View {
    var store: Store
    var course: Course
    var day: String
    @State private var entry: CalendarDraft?
    @State private var editingCourse = false
    private var tasks: [StudyTask] { store.state.tasks.filter { $0.courseID == course.id && $0.due == day } }
    private var assessments: [Assessment] { store.state.assessments.filter { $0.courseID == course.id && $0.day == day } }
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Button { editingCourse = true } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.shortName).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Text(ClockTime.label(course.classStart ?? 0)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            if !tasks.isEmpty || !assessments.isEmpty {
                Menu {
                    ForEach(tasks) { task in Button((task.completed ? "✓ " : "○ ") + task.title) { entry = .task(task, day) } }
                    ForEach(assessments) { item in Button(item.title) { entry = .assessment(item) } }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tasks.first.map { ($0.completed ? "✓ " : "○ ") + $0.title } ?? assessments.first?.title ?? "").lineLimit(1)
                        if tasks.count + assessments.count > 1 { Text("+\(tasks.count + assessments.count - 1) more").foregroundStyle(.secondary) }
                    }.font(.system(size: 10))
                }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                .frame(maxWidth: .infinity).padding(3).background(course.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            }
        }.padding(4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(course.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(course.tint).frame(width: 3) }
            .popover(item: $entry) { CalendarEntryEditor(store: store, source: $0).id($0.id) }
            .sheet(isPresented: $editingCourse) { CourseEditor(store: store, course: course) }
            .help(course.name + " · " + String(tasks.count) + " tasks due")
    }
}
