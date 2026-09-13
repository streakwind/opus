import Foundation
import Observation

package enum RecurringDeleteScope { case thisEvent, thisAndFollowing, allEvents }

@MainActor @Observable
package final class Store {
    package var state: Snapshot
    package var calendarFocus: CalendarFocus?
    package var error: String?
    private let database: Database
    private var undoStates: [Snapshot] = []
    package var canUndo: Bool { !undoStates.isEmpty }
    package var location: URL { database.url }

    package init(database: Database) throws {
        self.database = database
        state = try database.load()
        var needsSave = false
        for index in state.tasks.indices where state.tasks[index].kind == .progress && state.tasks[index].completed {
            state.tasks[index].completed = false
            needsSave = true
        }
        for index in state.tasks.indices where state.tasks[index].kind == .practice {
            state.tasks[index].kind = .checkbox
            needsSave = true
        }
        for index in state.rules.indices where state.rules[index].taskKind == .practice {
            state.rules[index].taskKind = .checkbox
            needsSave = true
        }
        for index in state.tasks.indices {
            var task = state.tasks[index]
            guard task.ruleID != nil, task.due == nil, let planned = task.planned else { continue }
            let occurrence = task.occurrence ?? planned
            guard planned == occurrence else { continue }
            task.due = planned
            task.planned = nil
            task.occurrence = occurrence
            state.tasks[index] = task
            needsSave = true
        }
        for index in state.assessments.indices where !state.assessments[index].confirmed {
            state.assessments[index].confirmed = true
            needsSave = true
        }
        for index in state.tasks.indices where !state.tasks[index].notes.isEmpty {
            state.tasks[index].notes = ""
            needsSave = true
        }
        for index in state.assessments.indices where !state.assessments[index].topics.isEmpty {
            state.assessments[index].topics = ""
            needsSave = true
        }
        for index in state.rules.indices where state.rules[index].notes != nil {
            state.rules[index].notes = nil
            needsSave = true
        }
        for index in state.schedule.indices where !state.schedule[index].notes.isEmpty {
            state.schedule[index].notes = ""
            needsSave = true
        }
        for index in state.courses.indices {
            if state.courses[index].notes == nil, let markdown = state.courses[index].notesMarkdown, !markdown.isEmpty {
                state.courses[index].notes = [ListNote(id: "legacy-list-note", markdown: markdown)]
                state.courses[index].notesMarkdown = nil
                needsSave = true
            }
        }
        let normalizedJournal = Self.normalizedJournal(state.journal)
        if normalizedJournal != state.journal {
            state.journal = normalizedJournal
            needsSave = true
        }
        if Self.migrateEmbedComments(in: &state) {
            needsSave = true
        }
        for index in state.tasks.indices where state.tasks[index].kind == .progress {
            let floor = state.tasks[index].start
            let ceiling = state.tasks[index].progressCompleteAt
            if state.tasks[index].current < floor {
                state.tasks[index].current = floor
                needsSave = true
            } else if state.tasks[index].current > ceiling {
                state.tasks[index].current = ceiling
                needsSave = true
            }
        }
        Self.syncJournalLinks(in: &state)
        if needsSave { try database.save(state) }
        refreshOccurrences()
    }
    package func change(_ mutation: (inout Snapshot) -> Void) {
        let previous = state
        var next = state
        mutation(&next)
        Self.syncJournalLinks(in: &next)
        do {
            try database.save(next)
            error = nil
            undoStates.append(previous)
            if undoStates.count > 30 { undoStates.removeFirst() }
            state = next
        } catch { self.error = error.localizedDescription }
    }
    package func undo() {
        guard let previous = undoStates.last else { return }
        do { try database.save(previous); state = previous; undoStates.removeLast() }
        catch { self.error = error.localizedDescription }
    }
    package func course(_ id: String?) -> Course? { state.courses.first { $0.id == id } }
    package func rule(_ id: String?) -> QuizRule? { id.flatMap { ruleID in state.rules.first { $0.id == ruleID } } }
    package func journalEntries(on day: String) -> [JournalEntry] {
        state.journal.filter { $0.appears(on: day) }.sorted {
            if ($0.link != nil) != ($1.link != nil) { return $0.link != nil }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }
    package func journalDocument(on day: String) -> JournalEntry? {
        state.journal.first { $0.link == nil && $0.day == day }
    }
    package func ensureJournalDocument(on day: String) {
        guard journalDocument(on: day) == nil else { return }
        save(JournalEntry(day: day, title: "Journal"))
    }
    package func journalTaskEmbeds(on day: String) -> [JournalEntry] {
        state.journal.filter { $0.day == day && $0.link != nil }
    }
    package func save(_ entry: JournalEntry) {
        var entry = entry
        if entry.link == nil, let previous = state.journal.first(where: { $0.id == entry.id }) {
            let before = JournalMarkdown.links(in: previous.markdown)
            let after = JournalMarkdown.links(in: entry.markdown)
            let omitted = Set(previous.omittedEmbeds ?? []).union(before.subtracting(after)).subtracting(after)
            entry.omittedEmbeds = omitted.isEmpty ? nil : omitted.sorted { $0.token < $1.token }
        }
        guard state.journal.first(where: { $0.id == entry.id }) != entry else { return }
        change { state in
            if let index = state.journal.firstIndex(where: { $0.id == entry.id }) { state.journal[index] = entry }
            else { state.journal.append(entry) }
        }
    }
    package func deleteJournalEntry(_ id: String) {
        change { state in
            let entry = state.journal.first { $0.id == id }
            let token = entry?.link?.embedToken
            state.journal.removeAll { $0.id == id }
            guard let token else { return }
            for index in state.journal.indices where state.journal[index].link == nil && state.journal[index].day == entry?.day {
                state.journal[index].markdown = JournalMarkdown.removing(token, from: state.journal[index].markdown)
            }
        }
    }
    private static func normalizedJournal(_ entries: [JournalEntry]) -> [JournalEntry] {
        var documents: [String: JournalEntry] = [:]
        var dayOrder: [String] = []
        var embeds: [JournalEntry] = []
        for entry in entries {
            switch entry.link {
            case .task, .assessment, .rhythm:
                embeds.append(entry)
                continue
            default:
                break
            }
            if documents[entry.day] == nil {
                var document = entry
                document.title = "Journal"
                document.markdown = ""
                document.link = nil
                document.throughDay = nil
                documents[entry.day] = document
                dayOrder.append(entry.day)
            }
            var fragment = entry.markdown
            let meaningfulTitle = !entry.title.isEmpty && entry.title != "Untitled" && entry.title != "Journal"
            if meaningfulTitle {
                fragment = "## \(entry.title)\n\n" + fragment
            }
            guard !fragment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if documents[entry.day]?.markdown.isEmpty == false { documents[entry.day]?.markdown += "\n\n" }
            documents[entry.day]?.markdown += fragment
        }
        return dayOrder.compactMap { documents[$0] } + embeds
    }
    private static func migrateEmbedComments(in state: inout Snapshot) -> Bool {
        var changed = false
        for index in state.journal.indices {
            guard let link = state.journal[index].link else { continue }
            let comment = state.journal[index].markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !comment.isEmpty else { continue }
            let day = state.journal[index].day
            var documentIndex = state.journal.firstIndex { $0.link == nil && $0.day == day }
            if documentIndex == nil {
                state.journal.append(JournalEntry(day: day, title: "Journal"))
                documentIndex = state.journal.indices.last
            }
            guard let documentIndex else { continue }
            let token = link.embedToken
            if state.journal[documentIndex].markdown.contains(token) {
                state.journal[documentIndex].markdown = state.journal[documentIndex].markdown.replacingOccurrences(
                    of: token,
                    with: token + "\n" + comment,
                    options: [],
                    range: state.journal[documentIndex].markdown.range(of: token)
                )
            } else {
                let existing = state.journal[documentIndex].markdown
                state.journal[documentIndex].markdown = comment + (existing.isEmpty ? "" : "\n\n" + existing)
            }
            state.journal[index].markdown = ""
            changed = true
        }
        return changed
    }
    private static func syncJournalLinks(in state: inout Snapshot) {
        for index in state.journal.indices {
            guard let link = state.journal[index].link else {
                state.journal[index].throughDay = nil
                continue
            }
            let resolved: (title: String, through: String?)?
            switch link {
            case .task(let id):
                resolved = state.tasks.first { $0.id == id }.map { ($0.title, $0.calendarDay) }
            case .assessment(let id):
                resolved = state.assessments.first { $0.id == id }.map { ($0.title, $0.day) }
            case .schedule(let id):
                resolved = state.schedule.first { $0.id == id }.map { ($0.title, $0.day) }
            case .rhythm(let id):
                guard let rule = state.rules.first(where: { $0.id == id }) else { resolved = nil; break }
                let occurrenceDays =
                    state.tasks.filter { $0.ruleID == id }.compactMap { $0.occurrence ?? $0.calendarDay } +
                    state.assessments.filter { $0.ruleID == id }.map { $0.occurrence ?? $0.day } +
                    state.schedule.filter { $0.ruleID == id }.map { $0.occurrence ?? $0.day }
                resolved = (rule.title, occurrenceDays.filter { $0 >= state.journal[index].day }.min() ?? rule.endDate)
            }
            guard let resolved else { continue }
            state.journal[index].title = resolved.title
            state.journal[index].throughDay = max(state.journal[index].day, resolved.through ?? state.journal[index].day)
        }
    }
    package func save(_ task: StudyTask) {
        change { state in
            if let index = state.tasks.firstIndex(where: { $0.id == task.id }) { state.tasks[index] = task }
            else { state.tasks.append(task) }
        }
    }
    package func save(_ assessment: Assessment) {
        var assessment = assessment
        assessment.confirmed = true
        change { state in
            if let index = state.assessments.firstIndex(where: { $0.id == assessment.id }) { state.assessments[index] = assessment }
            else { state.assessments.append(assessment) }
        }
    }
    package func deleteAssessment(_ id: String) {
        change { $0.assessments.removeAll { $0.id == id } }
    }
    package func save(_ course: Course) {
        var course = course
        course.syncLegacyClassTime()
        change { state in
            if let index = state.courses.firstIndex(where: { $0.id == course.id }) { state.courses[index] = course }
            else { state.courses.append(course) }
        }
    }
    package func saveListNote(_ courseID: String, _ note: ListNote) {
        guard var course = course(courseID) else { return }
        var notes = course.listNotes
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            guard notes[index] != note else { return }
            notes[index] = note
        } else {
            notes.append(note)
        }
        course.notes = notes
        course.notesMarkdown = nil
        save(course)
    }
    package func addListNote(_ courseID: String) -> ListNote? {
        let note = ListNote()
        saveListNote(courseID, note)
        return course(courseID)?.listNotes.last { $0.id == note.id }
    }
    package func deleteListNote(_ courseID: String, noteID: String) {
        guard var course = course(courseID) else { return }
        let notes = course.listNotes.filter { $0.id != noteID }
        guard notes.count != course.listNotes.count else { return }
        course.notes = notes
        course.notesMarkdown = nil
        save(course)
    }
    package func deleteCourse(_ id: String) {
        change { state in
            state.courses.removeAll { $0.id == id }
            for index in state.tasks.indices where state.tasks[index].courseID == id { state.tasks[index].courseID = nil }
            for index in state.assessments.indices where state.assessments[index].courseID == id { state.assessments[index].courseID = nil }
            for index in state.schedule.indices where state.schedule[index].courseID == id { state.schedule[index].courseID = nil }
            state.rules.removeAll { $0.courseID == id }
        }
    }
    package func deleteTask(_ id: String) {
        change { state in
            state.tasks.removeAll { $0.id == id }
            state.activities.removeAll { $0.taskID == id }
        }
    }
    package func record(_ task: StudyTask, value: Int?, note: String) {
        change { state in
            guard let index = state.tasks.firstIndex(where: { $0.id == task.id }) else { return }
            let previous = state.tasks[index].current
            if let value {
                state.tasks[index].current = value
                if task.kind != .progress { state.tasks[index].completed = value >= task.target }
            }
            state.activities.append(Activity(taskID: task.id, note: note, previous: value == nil ? nil : previous, value: value))
        }
    }
    package func refreshOccurrences(through: String? = nil) {
        var next = state
        Self.generate(in: &next, through: through)
        Self.syncJournalLinks(in: &next)
        do { try database.save(next); state = next } catch { self.error = error.localizedDescription }
    }
    package static func generate(in state: inout Snapshot, today: String = Day.today, through: String? = nil) {
        let horizon = max(56, through.map { (Calendar.current.dateComponents([.day], from: Day.date(today), to: Day.date($0)).day ?? 0) + 1 } ?? 56)
        for rule in state.rules where rule.enabled {
            let firstOffset: Int
            switch rule.kind {
            case .assessment: firstOffset = 0
            case .task: firstOffset = -1
            case .schedule:
                firstOffset = min(0, rule.startDate.map { Calendar.current.dateComponents([.day], from: Day.date(today), to: Day.date($0)).day ?? 0 } ?? 0)
            }
            for offset in firstOffset..<horizon {
                let day = Day.adding(offset, to: today)
                guard rule.occurs(on: day) else { continue }
                let key = "\(rule.id):\(day)"
                guard !state.generated.contains(key) else { continue }
                state.generated.insert(key)
                switch rule.kind {
                case .assessment:
                    state.assessments.append(Assessment(courseID: rule.courseID, title: rule.title, day: day, confirmed: true, ruleID: rule.id, occurrence: day))
                case .task:
                    let kind = (rule.taskKind == .progress) ? TaskKind.progress : .checkbox
                    let start = kind == .progress ? max(0, rule.startCount ?? 1) : 1
                    state.tasks.append(StudyTask(
                        courseID: rule.courseID,
                        title: rule.title,
                        kind: kind,
                        due: day,
                        start: start,
                        target: max(start, rule.targetCount ?? 30),
                        current: kind == .progress ? start : 0,
                        ruleID: rule.id,
                        occurrence: day
                    ))
                case .schedule:
                    state.schedule.append(ScheduleBlock(courseID: rule.courseID, title: rule.title, day: day, startMinute: rule.startMinute ?? 540, duration: rule.duration ?? 60, allDay: rule.allDay == true, ruleID: rule.id, occurrence: day))
                }
            }
        }
    }
    private static func removeUntouched(_ rule: QuizRule, in state: inout Snapshot) {
        var removedDays: [String] = []
        state.assessments.removeAll { item in
            let remove = item.ruleID == rule.id && item.day >= Day.today && item.day == item.occurrence && item.title == rule.title && item.courseID == rule.courseID
            if remove, let day = item.occurrence { removedDays.append(day) }
            return remove
        }
        let worked = Set(state.activities.map(\.taskID))
        state.tasks.removeAll { item in
            guard item.ruleID == rule.id, !item.completed, !worked.contains(item.id), item.courseID == rule.courseID else { return false }
            let kind: TaskKind = rule.taskKind == .progress ? .progress : .checkbox
            let start = kind == .progress ? max(0, rule.startCount ?? 1) : 1
            let target = max(start, rule.targetCount ?? 30)
            let current = kind == .progress ? start : 0
            guard item.title == rule.title, item.current == current, item.start == start, item.target == target, item.kind == kind else { return false }
            let remove: Bool
            if item.kind == .progress {
                remove = (item.due ?? "") >= Day.today && item.due == item.occurrence && item.planned == nil
            } else {
                remove = (item.due ?? "") >= Day.today && item.due == item.occurrence && item.planned == nil
            }
            if remove, let day = item.occurrence { removedDays.append(day) }
            return remove
        }
        state.schedule.removeAll { item in
            let remove = item.ruleID == rule.id && item.day >= Day.today && item.day == item.occurrence && item.title == rule.title && item.startMinute == (rule.startMinute ?? 540) && item.duration == (rule.duration ?? 60) && item.isAllDay == (rule.allDay == true) && item.courseID == rule.courseID
            if remove, let day = item.occurrence { removedDays.append(day) }
            return remove
        }
        for day in removedDays { state.generated.remove("\(rule.id):\(day)") }
    }
    package func saveRule(_ rule: QuizRule) {
        guard !rule.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !rule.days.isEmpty else { return }
        change { state in
            if let index = state.rules.firstIndex(where: { $0.id == rule.id }) {
                Self.removeUntouched(state.rules[index], in: &state)
                state.rules[index] = rule
            } else { state.rules.append(rule) }
            Self.generate(in: &state)
        }
    }
    package func deleteRule(_ id: String) {
        change { state in
            let taskIDs = Set(state.tasks.filter {
                $0.ruleID == id && ($0.occurrence ?? $0.calendarDay ?? "") > Day.today
            }.map(\.id))
            state.activities.removeAll { taskIDs.contains($0.taskID) }
            state.tasks.removeAll { taskIDs.contains($0.id) }
            state.assessments.removeAll {
                $0.ruleID == id && ($0.occurrence ?? $0.day) > Day.today
            }
            state.schedule.removeAll {
                $0.ruleID == id && ($0.occurrence ?? $0.day) > Day.today
            }
            for index in state.tasks.indices where state.tasks[index].ruleID == id {
                state.tasks[index].ruleID = nil
                state.tasks[index].occurrence = nil
            }
            for index in state.assessments.indices where state.assessments[index].ruleID == id {
                state.assessments[index].ruleID = nil
                state.assessments[index].occurrence = nil
            }
            for index in state.schedule.indices where state.schedule[index].ruleID == id {
                state.schedule[index].ruleID = nil
                state.schedule[index].occurrence = nil
            }
            state.generated = state.generated.filter { !$0.hasPrefix(id + ":") }
            state.rules.removeAll { $0.id == id }
        }
    }
    package func save(_ block: ScheduleBlock) {
        guard block.isAllDay || (block.startMinute >= 0 && block.duration > 0 && block.startMinute + block.duration <= 1440) else { return }
        change { state in
            if let index = state.schedule.firstIndex(where: { $0.id == block.id }) { state.schedule[index] = block }
            else { state.schedule.append(block) }
        }
    }
    package func setScheduleRuleEnd(_ id: String, to endDate: String?) {
        change { state in
            guard let index = state.rules.firstIndex(where: { $0.id == id && $0.kind == .schedule }) else { return }
            state.rules[index].endDate = endDate
            if let endDate {
                state.schedule.removeAll { $0.ruleID == id && ($0.occurrence ?? $0.day) > endDate }
                state.generated = state.generated.filter { key in
                    guard key.hasPrefix(id + ":"), let day = key.split(separator: ":").last.map(String.init) else { return true }
                    return day <= endDate
                }
            }
            Self.generate(in: &state)
        }
    }
    package func deleteSchedule(_ block: ScheduleBlock, scope: RecurringDeleteScope) {
        guard let ruleID = block.ruleID else {
            change { $0.schedule.removeAll { $0.id == block.id } }
            return
        }
        if scope == .allEvents {
            deleteRule(ruleID)
            return
        }
        let boundary = block.occurrence ?? block.day
        change { state in
            switch scope {
            case .thisEvent:
                state.schedule.removeAll { $0.id == block.id }
            case .thisAndFollowing:
                if let index = state.rules.firstIndex(where: { $0.id == ruleID }) {
                    state.rules[index].endDate = Day.adding(-1, to: boundary)
                }
                state.schedule.removeAll { $0.ruleID == ruleID && ($0.occurrence ?? $0.day) >= boundary }
                state.generated = state.generated.filter { key in
                    guard key.hasPrefix(ruleID + ":"), let day = key.split(separator: ":").last.map(String.init) else { return true }
                    return day < boundary
                }
            case .allEvents:
                break
            }
        }
    }
    package func updateProgress(_ id: String, to value: Int) {
        guard let task = state.tasks.first(where: { $0.id == id }), task.kind == .progress else { return }
        let bounded = task.clampedProgress(value)
        guard task.current != bounded else { return }
        record(task, value: bounded, note: "Finished through \(bounded)")
    }
    package func setup() {
        change { $0.setupComplete = true }
    }

}

extension Store {
    @discardableResult package func reschedule(_ payload: String, to day: String) -> Bool {
        if payload.hasPrefix("assessment:"), var item = state.assessments.first(where: { $0.id == String(payload.dropFirst(11)) }) {
            item.day = day; save(item); return error == nil
        }
        if payload.hasPrefix("planned:") || payload.hasPrefix("task:") {
            let id = String(payload.dropFirst(payload.hasPrefix("planned:") ? 8 : 5))
            guard var task = state.tasks.first(where: { $0.id == id }) else { return false }
            task.moveCalendarDay(to: day)
            save(task)
            return error == nil
        }
        if payload.hasPrefix("schedule:"), var block = state.schedule.first(where: { $0.id == String(payload.dropFirst(9)) }) {
            block.day = day; save(block); return error == nil
        }
        return false
    }
    package func deleteArchivedTasks() {
        change { state in
            let ids = Set(state.tasks.filter { $0.kind != .progress && $0.completed }.map(\.id))
            state.tasks.removeAll { ids.contains($0.id) }
            state.activities.removeAll { ids.contains($0.taskID) }
        }
    }
    package func moveTask(_ id: String, before target: String) {
        guard id != target, let task = state.tasks.first(where: { $0.id == id }), state.tasks.contains(where: { $0.id == target }) else { return }
        change { state in
            state.tasks.removeAll { $0.id == id }
            let index = state.tasks.firstIndex { $0.id == target }!
            state.tasks.insert(task, at: index)
        }
    }
}
