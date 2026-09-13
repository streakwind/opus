import OpusCore
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: Store
    @State private var selection: String? = "today"
    @State private var query = ""
    @State private var courseEditor: Course?
    @State private var ruleDetail: QuizRule?
    @State private var workDetail: WorkDraft?
    @State private var quickTitle = ""
    @State private var quickKind: WorkKind = .task
    @State private var quickCourse: String?
    @State private var quickDue: String? = Day.adding(1)
    @State private var quickStart = 1
    @State private var quickEnd = 30
    @State private var newEntryRequest = 0
    @State private var isSearching = false
    @State private var showSettings = false
    @State private var showTutorial = false
    @AppStorage("appearance") private var appearance = "system"
    @FocusState private var quickFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    private var course: Course? { store.course(selection) }
    private var isCalendar: Bool { selection == "upcoming" || selection == "schedule" }
    private func matchesQuery(title: String, courseID: String?) -> Bool {
        query.isEmpty ||
        title.localizedCaseInsensitiveContains(query) ||
        (store.course(courseID)?.name.localizedCaseInsensitiveContains(query) ?? false)
    }
    private var heading: String {
        switch selection {
        case "today": Date().formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        case "all": "Tasks"
        case "inbox": "Inbox"
        case "journal": "Journal"
        case "routines": "Rhythm"
        default: course?.name ?? "Today"
        }
    }
    private var matchingItems: [StudyTask] {
        store.state.tasks.filter { task in
            let matches: Bool
            switch selection {
            case "all": matches = true
            case "inbox": matches = task.courseID == nil
            case "today": matches = task.isInToday(on: Day.today)
            default: matches = task.courseID == selection
            }
            let visible = task.kind == .progress ? task.current < task.target : !task.completed
            return matches && visible && matchesQuery(title: task.title, courseID: task.courseID)
        }
    }
    private func nextRhythms(_ items: [StudyTask]) -> [StudyTask] {
        let ordered = items.sorted {
            let left = $0.calendarDay ?? "9999"
            let right = $1.calendarDay ?? "9999"
            if left == right { return $0.title < $1.title }
            return left < right
        }
        var seenRules = Set<String>()
        return ordered.filter { task in
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
                matchesQuery(title: $0.title, courseID: $0.courseID)
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
            .sheet(item: $courseEditor) { CourseEditor(store: store, course: $0) }
            .sheet(isPresented: $showSettings) { settingsView }
            .alert("Couldn't save changes", isPresented: saveErrorPresented) {
                Button("OK") { store.error = nil }
            } message: {
                Text(store.error ?? "")
            }
            .onChange(of: selection) { _, _ in workDetail = nil; ruleDetail = nil; quickCourse = course?.id }
            .onChange(of: scenePhase) { _, phase in if phase == .active { store.refreshOccurrences() } }
            .onChange(of: store.state.tasks.map(\.id)) { _, ids in
                if case .task(let task) = workDetail, !ids.contains(task.id) { workDetail = nil }
            }
            .onChange(of: store.state.assessments.map(\.id)) { _, ids in
                if case .assessment(let item) = workDetail, !ids.contains(item.id) { workDetail = nil }
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
    private var splitView: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
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
                Label("Journal", systemImage: "book.closed").tag("journal")
                Section {
                    Label("Calendar", systemImage: "calendar").tag("upcoming")
                    Label("Schedule", systemImage: "clock").tag("schedule")
                    Label("Rhythm", systemImage: "repeat").tag("routines")
                }
                Section("Your lists") {
                    ForEach(store.state.courses) { course in
                        Label { Text(course.name) } icon: { Circle().fill(course.tint).frame(width: 8, height: 8) }.tag(course.id)
                            .contextMenu { Button("Edit list…") { courseEditor = course } }
                            .accessibilityIdentifier("sidebar-list-\(course.id)")
                    }
                }
            }.listStyle(.sidebar)
            HStack {
                Button { courseEditor = Course(name: "") } label: { Label("New list", systemImage: "plus") }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("new-list-button")
                Spacer()
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).help("Settings").frame(width: 28, height: 24)
                    .accessibilityIdentifier("settings-button")
            }.padding(16)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 215, max: 260)
    }
    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !store.state.setupComplete { welcome }
            else if selection == "upcoming" {
                AssessmentCalendar(store: store, query: query, newEntryRequest: newEntryRequest) { rule in
                    ruleDetail = rule
                }
            }
            else if selection == "schedule" {
                ScheduleView(store: store, query: query, newEntryRequest: newEntryRequest) { rule in
                    ruleDetail = rule
                }
            }
            else if selection == "journal" {
                JournalView(store: store, query: query, newEntryRequest: 0)
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
            ToolbarItem(placement: .primaryAction) {
                Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!store.canUndo).help("Undo change (⌥⌘Z)")
                    .accessibilityIdentifier("undo-button")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: add) { Label("Add", systemImage: "plus") }
                    .keyboardShortcut("n").help("Add (⌘N)")
                    .accessibilityIdentifier("add-button")
            }
        }
        .opusSearchable(enabled: selection != "journal", text: $query, isPresented: $isSearching)
        .background {
            if selection != "journal" {
                Button("Search") { isSearching = true }
                    .keyboardShortcut("k", modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: selection) { _, value in
            if value == "journal" {
                isSearching = false
                query = ""
            }
        }
        .overlay {
            if let draft = workDetail, !isCalendar {
                EditorCardBackdrop {
                    WorkItemEditor(
                        store: store,
                        source: draft,
                        onEditRhythm: { rule in workDetail = nil; ruleDetail = rule },
                        onDismiss: { workDetail = nil }
                    )
                        .id(draft.id)
                        .editorCard()
                }
            } else if let rule = ruleDetail {
                EditorCardBackdrop {
                    RuleEditor(store: store, rule: rule, onDismiss: { ruleDetail = nil })
                        .id(rule.id)
                        .editorCard()
                }
            }
        }
    }
    private var detailHeading: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(heading).font(.system(size: 26, weight: .bold)).lineLimit(1)
            Spacer()
        }.padding(.horizontal, 22).padding(.top, 18).padding(.bottom, course != nil ? 2 : 12)
    }
    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings").font(.system(size: 22, weight: .semibold))
                Spacer()
                Button("Done") { showSettings = false }.keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("settings-done")
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
            .accessibilityIdentifier("appearance-picker")

            Button { showTutorial = true } label: {
                Label("Quick start tutorial", systemImage: "questionmark.circle")
            }.padding(.vertical, 20).accessibilityIdentifier("settings-tutorial")

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
        .sheet(isPresented: $showTutorial) { QuickStartView() }
        .fixedSize(horizontal: false, vertical: true)
        .roundedControls()
    }
    private var taskContent: some View {
        VStack(spacing: 0) {
            quickEntry
            List {
                if !assessments.isEmpty {
                    listHeading("Assessments")
                    ForEach(assessments) { item in
                        Button { openWork(.assessment(item)) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "calendar")
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
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .accessibilityIdentifier("assessment-row-\(item.id)")
                        .contextMenu {
                            if let rule = store.rule(item.ruleID) {
                                Button("Edit rhythm") { ruleDetail = rule }
                            } else {
                                Button("Details") { workDetail = .assessment(item) }
                            }
                            Button("Delete", role: .destructive) { store.deleteAssessment(item.id) }
                        }
                    }
                }
                if !progressItems.isEmpty {
                    listHeading("Progress")
                    ForEach(progressItems) { item in
                        ProgressLine(store: store, task: item) { openWork(.task(item)) }
                            .listRowSeparator(.hidden)
                            .listRowBackground(workDetail?.id == "task:" + item.id ? Color.accentColor.opacity(0.065) : Color.clear)
                            .contextMenu {
                                if let rule = store.rule(item.ruleID) {
                                    Button("Edit rhythm") { ruleDetail = rule }
                                } else {
                                    Button("Details") { workDetail = .task(item) }
                                }
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
                    TaskLine(store: store, task: task, selected: workDetail?.id == "task:" + task.id, markNext: task.ruleID != nil) {
                        openWork(.task(task))
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(workDetail?.id == "task:" + task.id ? Color.accentColor.opacity(0.065) : Color.clear)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                    .contextMenu {
                        if let rule = store.rule(task.ruleID) {
                            Button("Edit rhythm") { ruleDetail = rule }
                        } else {
                            Button("Details") { workDetail = .task(task) }
                        }
                        Menu("Move to list") {
                            Button("Inbox") { var copy = task; copy.courseID = nil; store.save(copy) }
                            ForEach(store.state.courses) { list in Button(list.name) { var copy = task; copy.courseID = list.id; store.save(copy) } }
                        }
                        Button("Delete", role: .destructive) { store.deleteTask(task.id) }
                    }
                }
                .onMove { offsets, destination in
                    var reordered = tasks; reordered.move(fromOffsets: offsets, toOffset: destination)
                    let ids = Set(reordered.map(\.id))
                    var iterator = reordered.makeIterator()
                    store.change { state in state.tasks = state.tasks.map { ids.contains($0.id) ? iterator.next()! : $0 } }
                }
                .animation(.easeInOut(duration: 0.28), value: tasks.map(\.id))
                if tasks.isEmpty && progressItems.isEmpty && assessments.isEmpty && !query.isEmpty {
                    Text("No matches.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 12).listRowSeparator(.hidden)
                }
            }.listStyle(.inset).scrollContentBackground(.hidden)
        }
    }
    private func listHeading(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.top, 12).padding(.bottom, 3)
            .listRowSeparator(.hidden)
    }
    private func assessmentSubtitle(_ item: Assessment) -> String {
        let date = Day.label(item.day)
        return store.course(item.courseID).map { $0.shortName + " · " + date } ?? date
    }
    private var quickEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField(quickPlaceholder, text: $quickTitle)
                    .textFieldStyle(.plain).font(.system(size: 14))
                    .focused($quickFocused).onSubmit(capture)
                    .accessibilityIdentifier("quick-entry-field")
                if !quickTitle.isEmpty {
                    Button(action: capture) { Image(systemName: "return") }
                        .buttonStyle(.plain).help("Add")
                        .accessibilityIdentifier("quick-entry-submit")
                }
            }
            .fieldChrome()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { entryOptions }
                VStack(alignment: .leading, spacing: 8) { entryOptions }
            }
        }.padding(.horizontal, 22).padding(.vertical, 10)
    }
    private var quickPlaceholder: String {
        switch quickKind {
        case .progress: "Add progress…"
        case .assessment: "Add an assessment…"
        case .task: "Add a task…"
        }
    }
    @ViewBuilder private var entryOptions: some View {
        PillPicker("List", label: store.course(quickCourse)?.shortName ?? "Inbox", selection: $quickCourse) {
            Text("Inbox").tag(nil as String?)
            ForEach(store.state.courses) { Text($0.shortName).tag(Optional($0.id)) }
        }.labelsHidden().fixedSize()
        PillPicker("Type", label: quickKind.rawValue, selection: $quickKind) {
            ForEach(WorkKind.allCases) { Text($0.rawValue).tag($0) }
        }.labelsHidden().fixedSize()
        if quickKind == .progress {
            PageRangeControl(start: $quickStart, end: $quickEnd)
        }
        DateMenu(title: quickKind == .assessment ? "Date" : "Due date", value: $quickDue, prefix: quickKind == .assessment ? nil : "Due")
    }
    private var routines: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(store.state.rules.filter { matchesQuery(title: $0.title, courseID: $0.courseID) }) { rule in
                    Button { ruleDetail = rule } label: {
                        HStack(spacing: 12) {
                            Image(systemName: rule.kind == .task ? "checkmark.circle" : rule.kind == .assessment ? "calendar" : "clock")
                                .foregroundStyle(store.course(rule.courseID)?.tint ?? .teal).frame(width: 18)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rule.title).font(.system(size: 14, weight: .medium)).lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                HStack(spacing: 5) {
                                    if let course = store.course(rule.courseID) {
                                        Circle().fill(course.tint).frame(width: 5, height: 5)
                                        Text(course.shortName)
                                    } else {
                                        Text("Inbox")
                                    }
                                    Text("· " + rule.compactPattern)
                                    if !rule.enabled { Text("· Paused") }
                                }
                                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }.buttonStyle(.plain).padding(.vertical, 6).listRowSeparator(.hidden).contextMenu {
                        Button("Edit") { ruleDetail = rule }
                        Button(rule.enabled ? "Pause" : "Resume") { var copy = rule; copy.enabled.toggle(); store.saveRule(copy) }
                        Button("Delete", role: .destructive) { store.deleteRule(rule.id) }
                    }
                }
                Button { ruleDetail = QuizRule(itemKind: .task, startDate: Day.today) } label: { Label("Add a rhythm", systemImage: "plus") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).padding(.vertical, 8)
                    .accessibilityIdentifier("add-rhythm-button")
            }.listStyle(.inset).scrollContentBackground(.hidden)
        }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Welcome to Opus").font(.title.bold())
            Text("Tasks, notes, and a little structure for your school day.").foregroundStyle(.secondary)
            HStack {
                Button("Get started") { store.setup() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("setup-empty")
            }
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    private func capture() {
        let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if quickKind == .assessment {
            store.save(Assessment(
                courseID: quickCourse,
                title: title,
                day: quickDue ?? Day.today,
                confirmed: true
            ))
            if store.error == nil {
                quickTitle = ""
                quickDue = Day.adding(1)
                quickFocused = true
            }
            return
        }
        guard quickKind != .progress || (quickStart > 0 && quickEnd >= quickStart && quickEnd <= 1_000_000) else { return }
        let planned = selection == "today" && quickDue == nil ? Day.today : nil
        let kind: TaskKind = quickKind == .progress ? .progress : .checkbox
        let task = StudyTask(
            courseID: quickCourse, title: title, kind: kind, planned: planned, due: quickDue,
            start: kind == .progress ? quickStart : 1,
            target: kind == .progress ? quickEnd : 30,
            current: kind == .progress ? quickStart - 1 : 0
        )
        store.save(task)
        if store.error == nil { quickTitle = ""; quickDue = Day.adding(1); quickFocused = true }
    }
    private func add() {
        if isCalendar { newEntryRequest += 1 }
        else if selection == "journal" {
            workDetail = .new(day: Day.today, courseID: nil, title: "", kind: .task)
        }
        else if selection == "routines" { ruleDetail = QuizRule(itemKind: .task, startDate: Day.today) }
        else { quickFocused = true }
    }
    private func openWork(_ draft: WorkDraft) {
        let rule: QuizRule?
        switch draft {
        case .task(let task): rule = store.rule(task.ruleID)
        case .assessment(let item): rule = store.rule(item.ruleID)
        case .new: rule = nil
        }
        if let rule { ruleDetail = rule }
        else { workDetail = draft }
    }
    private func exportData() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Opus-\(Day.today).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(store.state).write(to: url, options: .atomic) }
        catch { store.error = error.localizedDescription }
    }
}

private extension View {
    @ViewBuilder func opusSearchable(enabled: Bool, text: Binding<String>, isPresented: Binding<Bool>) -> some View {
        if enabled {
            searchable(text: text, isPresented: isPresented, placement: .toolbar, prompt: "Search")
        } else {
            self
        }
    }
}
