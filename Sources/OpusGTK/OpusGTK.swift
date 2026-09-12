import Foundation
import OpusCore
import GTKBridge
import Glibc

@MainActor
final class LinuxApp {
    let store: Store
    var selection = "today"
    var smoke = false
    init() throws { store = try Store(database: Database(url: DataLocation.linux())) }
    var courseID: String? { selection.hasPrefix("list:") ? String(selection.dropFirst(5)) : nil }
    var title: String {
        switch selection {
        case "today": "Today & Tomorrow"
        case "inbox": "Inbox"
        case "archive": "Completed"
        default: store.course(courseID)?.name ?? "All Tasks"
        }
    }
    func render() {
        opus_begin(title, "Add to \(courseID == nil ? "Inbox" : title)…", store.canUndo ? 1 : 0, courseID == nil ? 0 : 1)
        for (id, name) in [("today", "Today"), ("inbox", "Inbox"), ("all", "All Tasks"), ("archive", "Completed")] {
            opus_list(id, name, selection == id ? 1 : 0)
        }
        for course in store.state.courses {
            opus_list("list:" + course.id, course.name, course.id == courseID ? 1 : 0)
        }
        let tasks = store.state.tasks.filter { task in
            if selection == "archive" { return task.completed }
            guard !task.completed else { return false }
            switch selection {
            case "today": return task.isInToday(on: Day.today)
            case "inbox": return task.courseID == nil
            case "all": return true
            default: return task.courseID == courseID
            }
        }
        for task in tasks {
            var detail: [String] = []
            if let name = store.course(task.courseID)?.name, courseID == nil { detail.append(name) }
            if let day = task.calendarDay { detail.append(Day.label(day)) }
            if task.kind == .progress {
                detail.append("Page \(task.current) of \(task.target)")
                if let pace = task.pacing(on: Day.today) { detail.append(pace) }
            }
            opus_task(task.id, task.title, detail.joined(separator: " · "), task.completed ? 1 : 0,
                      task.kind == .progress ? 1 : 0, Int32(task.start), Int32(task.target), Int32(task.current))
        }
        if tasks.isEmpty { opus_empty(selection == "today" ? "Nothing due today or tomorrow." : "No tasks here yet.") }
        if let error = store.error { opus_error(error) }
    }
    func edit(_ id: String) {
        let task = store.state.tasks.first { $0.id == id } ?? StudyTask(courseID: courseID, due: selection == "today" ? Day.today : nil)
        opus_editor(id, task.title, task.calendarDay ?? "", task.courseID ?? "", task.kind == .progress ? 1 : 0,
                    Int32(task.start), Int32(task.target), Int32(task.current))
        opus_editor_list("", "Inbox", task.courseID == nil ? 1 : 0)
        for course in store.state.courses { opus_editor_list(course.id, course.name, task.courseID == course.id ? 1 : 0) }
    }
    func event(_ action: String, id: String, text: String, day: String, course: String, kind: Int, start: Int, end: Int, page: Int) {
        switch action {
        case "ready":
            render()
            if smoke { opus_quit() }
            return
        case "select": selection = id
        case "new": edit(""); return
        case "edit": edit(id); return
        case "add":
            let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }
            store.save(StudyTask(courseID: courseID, title: title, due: selection == "today" ? Day.today : nil))
            if selection == "archive" { selection = "inbox" }
        case "new-list":
            let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let list = Course(name: name); store.save(list)
            if store.error == nil { selection = "list:" + list.id }
        case "delete-list":
            if let courseID { store.deleteCourse(courseID); if store.error == nil { selection = "inbox" } }
        case "delete": store.deleteTask(id)
        case "toggle":
            if var task = store.state.tasks.first(where: { $0.id == id }) { task.completed.toggle(); store.save(task) }
        case "page":
            guard let value = Int(text) else { opus_error("Enter a page number, then press Enter."); return }
            store.updateProgress(id, to: value)
        case "undo": store.undo()
        case "save":
            let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { opus_error("Give the task a title."); return }
            guard day.isEmpty || (day.count == 10 && Day.string(Day.date(day)) == day) else {
                opus_error("Use a valid date in YYYY-MM-DD format."); return
            }
            guard kind == 0 || (start >= 1 && end >= start && page >= start - 1 && page <= end) else {
                opus_error("Check the page range and last page read."); return
            }
            var task = store.state.tasks.first { $0.id == id } ?? StudyTask()
            task.title = title; task.courseID = course.isEmpty ? nil : course
            task.due = day.isEmpty ? nil : day; task.planned = nil
            task.kind = kind == 1 ? .progress : .checkbox
            if kind == 1 { task.start = start; task.target = end; task.current = page; task.completed = false }
            store.save(task)
            guard store.error == nil else { opus_error(store.error!); return }
            opus_editor_close()
            selection = task.courseID.map { "list:" + $0 } ?? "inbox"
        case "help":
            render()
            opus_empty("Quick Start\n\nAdd a task and press Enter. Inbox keeps tasks without a list. Create your own lists using the sidebar.\n\nOpen a task to set its due date or track textbook notes. For textbook notes, enter the last page read beside the task and press Enter. The daily pace updates from that page.\n\nToday includes tomorrow’s tasks. Completed tasks remain in Completed. Undo restores your last change, including deleted tasks and lists.\n\nYour changes save automatically on this computer. The Linux preview currently includes tasks, lists, and textbook progress; Calendar, Schedule, and Rhythm interfaces are still being ported.")
            return
        default: return
        }
        render()
    }
}

@main
struct OpusGTK {
    @MainActor static var controller: LinuxApp?
    @MainActor static func main() {
        do {
            controller = try LinuxApp()
            controller?.smoke = CommandLine.arguments.contains("--smoke-test")
            let status = opus_run { action, id, title, day, course, kind, start, end, page in
                // GTK's blocking loop and all callbacks execute on the main thread.
                MainActor.assumeIsolated {
                    controller?.event(String(cString: action!), id: String(cString: id!), text: String(cString: title!),
                                      day: String(cString: day!), course: String(cString: course!),
                                      kind: Int(kind), start: Int(start), end: Int(end), page: Int(page))
                }
            }
            exit(status)
        } catch {
            FileHandle.standardError.write(Data("Opus could not open its database: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
