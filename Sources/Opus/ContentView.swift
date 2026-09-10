import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum Editor: Identifiable {
    case course(Course), rule(QuizRule)
    var id: String { switch self { case .course(let value): value.id; case .rule(let value): value.id } }
}
struct ContentView: View {
    @Bindable var store: Store
    @State private var selection: String? = "today"
    @State private var query = ""
    @State private var editor: Editor?
    @State private var selectedTask: String?
    @State private var narrowTask: StudyTask?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var sidebarWidth: CGFloat = 0
    @State private var quickTitle = ""
    @State private var quickKind: TaskKind = .checkbox
    @State private var quickCourse: String?
    @State private var quickDue: String? = Day.adding(1)
    @State private var quickStart = 1
    @State private var quickEnd = 30
    @State private var newEntryRequest = 0
    @State private var showSettings = false
    @State private var confirmDeleteArchive = false
    @AppStorage("appearance") private var appearance = "system"
    @FocusState private var quickFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    private var course: Course? { store.course(selection) }
    private var isCalendar: Bool { selection == "upcoming" || selection == "schedule" }
    private var archivedCount: Int { store.state.tasks.filter { $0.kind != .progress && $0.completed }.count }
    private var archiveDeleteMessage: String {
        let noun = archivedCount == 1 ? "task" : "tasks"
        return "Permanently removes \(archivedCount) completed \(noun). Undo with ⌥⌘Z."
    }
    private func matchesQuery(title: String, details: String = "", courseID: String?) -> Bool {
        query.isEmpty ||
        title.localizedCaseInsensitiveContains(query) ||
        details.localizedCaseInsensitiveContains(query) ||
        (store.course(courseID)?.name.localizedCaseInsensitiveContains(query) ?? false)
    }
    private var heading: String {
        switch selection {
        case "today": Date().formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        case "all": "Tasks"
        case "inbox": "Inbox"
        case "archive": "Archive"
        case "routines": "Rhythm"
        default: course?.name ?? "Today"
        }
    }
    private var matchingItems: [StudyTask] {
        let sorted = store.state.tasks.filter { task in
            let matches: Bool
            switch selection {
            case "all": matches = true
            case "inbox": matches = task.courseID == nil
            case "archive": matches = task.kind != .progress && task.completed
            case "today": matches = task.isInToday(on: Day.today)
            default: matches = task.courseID == selection
            }
            let visible = selection == "archive" || task.kind == .progress || !task.completed
            return matches && visible && matchesQuery(title: task.title, details: task.notes, courseID: task.courseID)
        }
        return sorted
    }
    private func nextRhythms(_ items: [StudyTask]) -> [StudyTask] {
        var seenRules = Set<String>()
        return items.filter { task in
            guard let ruleID = task.ruleID else { return true }
            return seenRules.insert(ruleID).inserted
        }
    }
    private var tasks: [StudyTask] { nextRhythms(matchingItems.filter { $0.kind != .progress }) }
    private var progressItems: [StudyTask] { nextRhythms(matchingItems.filter { $0.kind == .progress }) }
    private var assessments: [Assessment] {
        let courseID = course?.id
        guard courseID != nil || selection == "today" || selection == "all" else { return [] }
        var seenRules = Set<String>()
        return store.state.assessments
            .filter {
                (courseID == nil || $0.courseID == courseID) && $0.day >= Day.today &&
                matchesQuery(title: $0.title, details: $0.topics, courseID: $0.courseID)
            }
            .sorted { $0.day == $1.day ? $0.title < $1.title : $0.day < $1.day }
            .filter { item in
                guard let ruleID = item.ruleID else { return true }
                return seenRules.insert(ruleID).inserted
            }
    }
    var body: some View {
        root
            .onAppear(perform: applyAppearance)
            .onChange(of: appearance) { _, _ in applyAppearance() }
    }
    private var root: some View {
        splitView
            .sheet(item: $editor, content: editorSheet)
            .sheet(isPresented: $showSettings) { settingsView }
            .alert("Couldn't save changes", isPresented: saveErrorPresented) {
                Button("OK") { store.error = nil }
            } message: {
                Text(store.error ?? "")
            }
            .confirmationDialog("Delete all archived tasks?", isPresented: $confirmDeleteArchive, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) { store.deleteArchivedTasks() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(archiveDeleteMessage)
            }
            .onChange(of: selection) { _, _ in selectedTask = nil; narrowTask = nil; quickCourse = course?.id }
            .onChange(of: scenePhase) { _, phase in if phase == .active { store.refreshOccurrences() } }
            .onChange(of: store.state.tasks.map(\.id)) { _, ids in
                if let selectedTask, !ids.contains(selectedTask) {
                    self.selectedTask = nil
                    narrowTask = nil
                }
            }
    }
    private func applyAppearance() {
        switch appearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
    private var saveErrorPresented: Binding<Bool> {
        Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
    }
    @ViewBuilder private func editorSheet(_ item: Editor) -> some View {
        switch item {
        case .course(let course): CourseEditor(store: store, course: course)
        case .rule(let rule): RuleEditor(store: store, rule: rule)
        }
    }
    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail
        }
        .onPreferenceChange(SidebarWidthKey.self) { sidebarWidth = $0 }
    }
    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill").font(.title2).foregroundStyle(.teal)
                Text("Opus").font(.title2.weight(.semibold)); Spacer()
            }.padding(20)
            List(selection: $selection) {
                Label("Today", systemImage: "sun.max").tag("today")
                Label("Tasks", systemImage: "checklist").tag("all")
                Label("Inbox", systemImage: "tray").tag("inbox")
                Label("Archive", systemImage: "archivebox").tag("archive")
                Section {
                    Label("Calendar", systemImage: "calendar").tag("upcoming")
                    Label("Schedule", systemImage: "clock").tag("schedule")
                    Label("Rhythm", systemImage: "repeat").tag("routines")
                }
                Section("Your lists") {
                    ForEach(store.state.courses) { course in
                        Label { Text(course.name) } icon: { Circle().fill(course.tint).frame(width: 8, height: 8) }.tag(course.id)
                            .contextMenu { Button("Edit list…") { editor = .course(course) } }
                    }
                }
            }.listStyle(.sidebar)
            HStack {
                Button { editor = .course(Course(name: "")) } label: { Label("New list", systemImage: "plus") }.buttonStyle(.plain)
                Spacer()
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).help("Settings").frame(width: 28, height: 24)
            }.padding(16)
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: SidebarWidthKey.self, value: geometry.size.width)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 215, max: 260)
    }
    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !store.state.setupComplete { welcome }
            else if selection == "upcoming" {
                AssessmentCalendar(store: store, query: query, newEntryRequest: newEntryRequest, editorLeadingInset: editorLeadingInset)
            }
            else if selection == "schedule" {
                ScheduleView(store: store, query: query, newEntryRequest: newEntryRequest, editorLeadingInset: editorLeadingInset)
            }
            else {
                if selection != "all" && selection != "inbox" && selection != "routines" {
                    detailHeading
                }
                if selection == "routines" { routines } else { taskContent }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!store.canUndo).help("Undo change (⌥⌘Z)") }
            ToolbarItem(placement: .primaryAction) { Button(action: add) { Label("Add", systemImage: "plus") }.keyboardShortcut("n").help("Add (⌘N)") }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search")
    }
    private var detailHeading: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(heading).font(.system(size: 26, weight: .bold)).lineLimit(1)
            Spacer()
            if selection == "archive" {
                Button("Delete All") { confirmDeleteArchive = true }
                    .disabled(archivedCount == 0)
                    .help("Delete all archived tasks")
            }
        }.padding(.horizontal, 22).padding(.top, 18).padding(.bottom, course != nil ? 2 : 12)
    }
    private var editorLeadingInset: CGFloat {
        columnVisibility == .detailOnly ? 0 : sidebarWidth
    }
    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings").font(.system(size: 22, weight: .semibold))
                Spacer()
                Button("Done") { showSettings = false }.keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 24)

            Text("Appearance").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.bottom, 8)
            Picker("Appearance", selection: $appearance) {
                Label("System", systemImage: "circle.lefthalf.filled").tag("system")
                Label("Light", systemImage: "sun.max").tag("light")
                Label("Dark", systemImage: "moon").tag("dark")
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Divider().padding(.vertical, 22)

            Text("Data").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.bottom, 8)
            VStack(spacing: 8) {
                Button { exportData() } label: {
                    Label("Export all data…", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([store.location])
                } label: {
                    Label("Show database in Finder", systemImage: "folder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .roundedControls()
    }
    private var taskContent: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 740
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if selection != "archive" { quickEntry }
                    List {
                        if !assessments.isEmpty {
                            listHeading("Assessments")
                            ForEach(assessments) { item in
                                Button { openAssessment(item) } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: item.confirmed ? "calendar" : "questionmark.circle")
                                            .foregroundStyle(store.course(item.courseID)?.tint ?? .teal).frame(width: 18)
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 5) {
                                                Text(item.title).font(.system(size: 14, weight: .medium)).lineLimit(2)
                                                if item.ruleID != nil { RepeatBadge() }
                                            }
                                            Text(assessmentSubtitle(item))
                                                .font(.system(size: 11)).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }.padding(.vertical, 5).contentShape(Rectangle())
                                }.buttonStyle(.plain).listRowSeparator(.hidden)
                            }
                        }
                        if !progressItems.isEmpty {
                            listHeading("Progress")
                            ForEach(progressItems) { item in
                                ProgressLine(store: store, task: item) {
                                    selectedTask = item.id
                                    if !wide { narrowTask = item }
                                }
                                .listRowSeparator(.hidden)
                                .listRowBackground(selectedTask == item.id && wide ? Color.accentColor.opacity(0.065) : Color.clear)
                                .popover(isPresented: Binding(get: { !wide && narrowTask?.id == item.id }, set: { if !$0 { narrowTask = nil } })) {
                                    TaskInspector(store: store, task: item) { narrowTask = nil }.frame(width: 350, height: 530)
                                }
                                .contextMenu {
                                    Button("Details") { selectedTask = item.id; if !wide { narrowTask = item } }
                                    Menu("Move to list") {
                                        Button("Inbox") { var copy = item; copy.courseID = nil; store.save(copy) }
                                        ForEach(store.state.courses) { list in Button(list.name) { var copy = item; copy.courseID = list.id; store.save(copy) } }
                                    }
                                    Button("Delete", role: .destructive) { store.deleteTask(item.id) }
                                }
                            }
                        }
                        if !tasks.isEmpty && (!assessments.isEmpty || !progressItems.isEmpty) { listHeading("Tasks") }
                        ForEach(tasks) { task in
                                TaskLine(store: store, task: task, selected: selectedTask == task.id) {
                                    selectedTask = task.id
                                    if !wide { narrowTask = task }
                                }
                                .listRowSeparator(.hidden)
                                .listRowBackground(selectedTask == task.id && wide ? Color.accentColor.opacity(0.065) : Color.clear)
                                .popover(isPresented: Binding(get: { !wide && narrowTask?.id == task.id }, set: { if !$0 { narrowTask = nil } })) {
                                    TaskInspector(store: store, task: task) { narrowTask = nil }.frame(width: 350, height: 530)
                                }
                                .contextMenu {
                                    Button("Details") { selectedTask = task.id; if !wide { narrowTask = task } }
                                    Menu("Move to list") {
                                        Button("Inbox") { var copy = task; copy.courseID = nil; store.save(copy) }
                                        ForEach(store.state.courses) { list in Button(list.name) { var copy = task; copy.courseID = list.id; store.save(copy) } }
                                    }
                                    Button("Delete", role: .destructive) { store.deleteTask(task.id) }
                                }
                        }.onMove { offsets, destination in
                            var reordered = tasks; reordered.move(fromOffsets: offsets, toOffset: destination)
                            let ids = Set(reordered.map(\.id))
                            var iterator = reordered.makeIterator()
                            store.change { state in state.tasks = state.tasks.map { ids.contains($0.id) ? iterator.next()! : $0 } }
                        }
                        if tasks.isEmpty && progressItems.isEmpty && assessments.isEmpty && !query.isEmpty {
                            Text("No matches.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 12).listRowSeparator(.hidden)
                        }
                    }.listStyle(.inset).scrollContentBackground(.hidden)
                }.frame(maxWidth: .infinity)
                if wide, let id = selectedTask, let task = store.state.tasks.first(where: { $0.id == id }) {
                    TaskInspector(store: store, task: task) { selectedTask = nil }.id(id).frame(width: 320)
                }
            }
        }
    }
    private func listHeading(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.top, 12).padding(.bottom, 3)
            .listRowSeparator(.hidden)
    }
    private func assessmentSubtitle(_ item: Assessment) -> String {
        let date = Day.label(item.day) + (item.confirmed ? "" : " · Tentative")
        return store.course(item.courseID).map { $0.shortName + " · " + date } ?? date
    }
    private var quickEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField(quickKind == .progress ? "Add progress…" : "Add a task…", text: $quickTitle).textFieldStyle(.plain).font(.system(size: 14)).focused($quickFocused).onSubmit(capture)
                if !quickTitle.isEmpty { Button(action: capture) { Image(systemName: "return") }.buttonStyle(.plain).help("Add task") }
            }
            if quickFocused || !quickTitle.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { entryOptions }
                    VStack(alignment: .leading, spacing: 8) { entryOptions }
                }
                if quickKind == .progress {
                    HStack(spacing: 8) {
                        Text("Pages").foregroundStyle(.secondary)
                        TextField("First page", value: $quickStart, format: .number.grouping(.never)).frame(width: 48)
                        Text("to").foregroundStyle(.secondary)
                        TextField("Last page", value: $quickEnd, format: .number.grouping(.never)).frame(width: 48)
                        Spacer()
                    }.textFieldStyle(.roundedBorder).font(.callout)
                }
            }
        }.padding(.horizontal, 22).padding(.vertical, 10)
    }
    @ViewBuilder private var entryOptions: some View {
        PillPicker("List", label: store.course(quickCourse)?.shortName ?? "Inbox", selection: $quickCourse) {
            Text("Inbox").tag(nil as String?)
            ForEach(store.state.courses) { Text($0.shortName).tag(Optional($0.id)) }
        }.labelsHidden().fixedSize()
        PillPicker("Type", label: quickKind == .progress ? "Progress" : quickKind.rawValue, selection: $quickKind) { ForEach([TaskKind.checkbox, .progress]) { Text($0.rawValue).tag($0) } }.labelsHidden().fixedSize()
        DateMenu(title: "Due date", value: $quickDue, prefix: "Due")
    }
    private var routines: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(store.state.rules.filter { $0.kind != .schedule && matchesQuery(title: $0.title, details: $0.notes ?? "", courseID: $0.courseID) }) { rule in
                    HStack(spacing: 12) {
                        Image(systemName: rule.kind == .task ? "checkmark.circle" : rule.kind == .assessment ? "calendar" : "clock").foregroundStyle(store.course(rule.courseID)?.tint ?? .teal)
                        Button { editor = .rule(rule) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rule.title).font(.system(size: 14, weight: .medium))
                                Text(rule.summary + (rule.enabled ? "" : " · Paused")).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                        Text(store.course(rule.courseID)?.shortName ?? rule.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6).listRowSeparator(.hidden).contextMenu {
                        Button(rule.enabled ? "Pause" : "Resume") { var copy = rule; copy.enabled.toggle(); store.saveRule(copy) }
                        Button("Delete", role: .destructive) { store.deleteRule(rule.id) }
                    }
                }
                Button { editor = .rule(QuizRule(itemKind: .task, startDate: Day.today)) } label: { Label("Add a rhythm", systemImage: "plus") }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.vertical, 8)
            }.listStyle(.inset).scrollContentBackground(.hidden)
        }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Welcome to Opus").font(.title.bold())
            Text("Tasks, notes, and a little structure for your school day.").foregroundStyle(.secondary)
            HStack {
                Button("Get started") { store.setup(personalized: true) }.buttonStyle(.borderedProminent)
                Button("Start empty") { store.setup(personalized: false) }
            }
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    private func capture() {
        let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, quickKind != .progress || (quickStart > 0 && quickEnd >= quickStart && quickEnd <= 1000000) else { return }
        let planned = selection == "today" && quickDue == nil ? Day.today : nil
        let task = StudyTask(courseID: quickCourse, title: title, kind: quickKind, planned: planned, due: quickDue, start: quickKind == .progress ? quickStart : 1, target: quickKind == .progress ? quickEnd : 30, current: quickKind == .progress ? quickStart - 1 : 0)
        store.save(task)
        if store.error == nil { quickTitle = ""; quickDue = Day.adding(1); quickFocused = true }
    }
    private func add() {
        if isCalendar { newEntryRequest += 1 }
        else if selection == "routines" { editor = .rule(QuizRule(itemKind: .task, startDate: Day.today)) }
        else { quickFocused = true }
    }
    private func openAssessment(_ item: Assessment) {
        selection = "upcoming"
        Task { @MainActor in
            await Task.yield()
            store.calendarFocus = CalendarFocus(day: item.day)
        }
    }
    private func exportData() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Opus-\(Day.today).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(store.state).write(to: url, options: .atomic) }
        catch { store.error = error.localizedDescription }
    }
}
