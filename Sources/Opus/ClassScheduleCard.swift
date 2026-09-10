import SwiftUI

struct ClassScheduleCard: View {
    var store: Store
    var course: Course
    var day: String
    @State private var editingCourse = false
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Button { editingCourse = true } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.shortName).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Text(ClockTime.label(course.classStart ?? 0)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)

        }.padding(4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(course.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(course.tint).frame(width: 3) }
            .sheet(isPresented: $editingCourse) { CourseEditor(store: store, course: course) }
            .help(course.name)
    }
}
