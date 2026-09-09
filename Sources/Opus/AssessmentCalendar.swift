import SwiftUI
import UniformTypeIdentifiers

enum CalendarPeriod: String, CaseIterable { case day = "Day", week = "Week", month = "Month" }

struct CalendarHeading: View {
    @Binding var anchor: Date
    @Binding var period: CalendarPeriod
    var schedule = false
    var body: some View {
        HStack(spacing: 12) {
            Text(anchor.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 22, weight: .semibold)).lineLimit(1).layoutPriority(1)
            Spacer(minLength: 8)
            Menu {
                ForEach(CalendarPeriod.allCases.filter { !schedule || $0 != .month }, id: \.self) { option in
                    Button(option.rawValue) { period = option }
                }
            } label: {
                HStack(spacing: 7) { Text(period.rawValue); Image(systemName: "chevron.down").font(.caption) }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            HStack(spacing: 4) {
                Button { advance(-1) } label: { Image(systemName: "chevron.left").frame(width: 16) }
                    .help("Previous " + period.rawValue.lowercased())
                Button("Today") { anchor = Date() }
                Button { advance(1) } label: { Image(systemName: "chevron.right").frame(width: 16) }
                    .help("Next " + period.rawValue.lowercased())
            }.fixedSize().roundedControls()
        }.padding(.horizontal, 20).padding(.vertical, 14)
    }
    private func advance(_ value: Int) {
        let unit: Calendar.Component = period == .month ? .month : period == .week ? .weekOfYear : .day
        anchor = Calendar.current.date(byAdding: unit, value: value, to: anchor)!
    }
}

struct AssessmentCalendar: View {
    var store: Store
    var query: String
    var newEntryRequest: Int
    @State private var anchor = Date()
    @State private var period = CalendarPeriod.month
    @State private var selectedDay = Day.today
    private var days: [String] { period == .day ? [Day.string(anchor)] : CalendarLayout.days(containing: anchor, week: period == .week) }
    var body: some View {
        VStack(spacing: 0) {
            CalendarHeading(anchor: $anchor, period: $period)
            HStack(spacing: 0) {
                ForEach(Array(days.prefix(period == .day ? 1 : 7)), id: \.self) { day in
                    Text(Day.date(day).formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 13)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 12)
                }
            }.padding(.bottom, 7)
            Divider()
            GeometryReader { geometry in
                let columns = period == .day ? 1 : 7
                let rows = days.count / columns
                let height = max(period == .month ? 96 : 180, geometry.size.height / CGFloat(rows))
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(0..<rows, id: \.self) { row in
                            HStack(spacing: 0) {
                                ForEach(Array(days[(row*columns)..<(row*columns+columns)]), id: \.self) { day in
                                    CalendarDayCell(store: store, day: day, inMonth: period != .month || Calendar.current.isDate(Day.date(day), equalTo: anchor, toGranularity: .month), query: query, capacity: max(1, Int((height - 52) / 23)), wide: period == .day, selected: selectedDay == day, newEntryRequest: newEntryRequest, select: { selectedDay = day })
                                        .frame(width: geometry.size.width / CGFloat(columns), height: height)
                                }
                            }
                        }
                    }
                }.scrollIndicators(.hidden)
            }
        }
        .onChange(of: anchor) { _, _ in selectedDay = Day.string(anchor); ensureOccurrences() }
        .onChange(of: period) { _, _ in if !days.contains(selectedDay) { selectedDay = Day.string(anchor) }; ensureOccurrences() }
        .onAppear(perform: ensureOccurrences)
    }
    private func ensureOccurrences() { store.refreshOccurrences(through: days.last) }
}

private struct CalendarDayCell: View {
    var store: Store
    var day: String
    var inMonth: Bool
    var query: String
    var capacity: Int
    var wide: Bool
    var selected: Bool
    var newEntryRequest: Int
    var select: () -> Void
    @State private var editing: CalendarDraft?
    @State private var overflow = false
    @State private var targeted = false
    private var assessments: [Assessment] {
        store.state.assessments.filter { $0.day == day && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || (store.course($0.courseID)?.name.localizedCaseInsensitiveContains(query) ?? false)) }.sorted { $0.title < $1.title }
    }
    private var tasks: [StudyTask] {
        store.state.tasks.filter { ($0.planned == day || $0.due == day) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }.sorted { !$0.completed && $1.completed }
    }
    private var count: Int { assessments.count + tasks.count }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Spacer()
                Button { select(); editing = .new(day) } label: {
                    Text(Day.date(day).formatted(.dateTime.day())).font(.system(size: 17, weight: .regular))
                        .foregroundStyle(day == Day.today ? Color.white : inMonth ? Color.primary : Color.secondary.opacity(0.5))
                        .frame(width: 30, height: 30).background(day == Day.today ? Color.accentColor : .clear, in: Circle())
                }.buttonStyle(.plain).help("Add task or assessment on " + day).accessibilityLabel("Add on " + day)
            }.padding(.horizontal, 7).padding(.vertical, 3)
            ForEach(assessments.prefix(capacity)) { item in assessmentLine(item) }
            ForEach(tasks.prefix(max(0, capacity - assessments.count))) { task in taskLine(task) }
            if count > capacity {
                Button("+\(count-capacity) more") { overflow = true }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).padding(.leading, 9)
                    .popover(isPresented: $overflow) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(Day.date(day).formatted(.dateTime.weekday(.wide).month().day())).font(.headline)
                            ScrollView {
                                VStack(spacing: 5) {
                                    ForEach(assessments) { assessmentLine($0) }
                                    ForEach(tasks) { taskLine($0) }
                                }
                            }.frame(maxHeight: 330)
                            Button("Add…") { overflow = false; select(); editing = .new(day) }
                        }.padding(16).frame(width: 320)
                    }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(targeted || selected ? Color.accentColor.opacity(0.08) : background)
        .overlay { if selected { Rectangle().strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1) } }
        .overlay(alignment: .trailing) { Rectangle().fill(Color.primary.opacity(0.13)).frame(width: 0.5) }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.13)).frame(height: 0.5) }
        .contentShape(Rectangle()).onTapGesture { select(); editing = .new(day) }
        .onDrop(of: [UTType.text], isTargeted: $targeted) { providers in
            guard let provider = providers.first else { return false }
            let targetDay = day; let targetStore = store
            _ = provider.loadObject(ofClass: String.self) { value, _ in
                guard let value else { return }; Task { @MainActor in targetStore.reschedule(value, to: targetDay) }
            }
            return true
        }
        .onChange(of: newEntryRequest) { _, _ in if selected { editing = .new(day) } }
        .popover(item: $editing) { CalendarEntryEditor(store: store, source: $0).id($0.id) }
    }
    private var background: Color {
        if !inMonth { return Color.primary.opacity(0.035) }
        return Calendar.current.isDateInWeekend(Day.date(day)) ? Color.primary.opacity(0.025) : Color(nsColor: .textBackgroundColor)
    }
    private func assessmentLine(_ item: Assessment) -> some View {
        let tint = store.course(item.courseID)?.tint ?? .teal
        return Button { overflow = false; editing = .assessment(item) } label: {
            HStack(spacing: 4) {
                Capsule().fill(tint).frame(width: 3, height: 14)
                Text((store.course(item.courseID)?.shortName).map { $0 + " · " } ?? "") + Text(item.title == "Example recurrence" ? "Quiz" : item.title)
                if !item.confirmed { Image(systemName: "questionmark.circle").font(.system(size: 9)).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }.font(.system(size: wide ? 13 : 11)).lineLimit(1).frame(height: 21).foregroundStyle(.primary)
        }.buttonStyle(.plain).padding(.horizontal, 5)
            .help(item.title + (item.confirmed ? "" : " · Tentative"))
            .onDrag { NSItemProvider(object: ("assessment:" + item.id) as NSString) }
            .contextMenu {
                Button("Edit") { editing = .assessment(item) }
                Button(item.confirmed ? "Mark tentative" : "Confirm") { var copy = item; copy.confirmed.toggle(); store.save(copy) }
                Button("Add preparation task") { store.save(StudyTask(courseID: item.courseID, title: "Prepare: " + item.title, notes: item.topics, planned: Day.today, due: item.day)) }
                Divider()
                Button("Delete", role: .destructive) { store.change { $0.assessments.removeAll { $0.id == item.id } } }
            }
    }
    private func taskLine(_ task: StudyTask) -> some View {
        HStack(spacing: 4) {
            Button {
                var copy = task; copy.completed.toggle(); store.save(copy)
            } label: { Image(systemName: task.completed ? "checkmark.circle.fill" : "circle").font(.system(size: 11)) }.buttonStyle(.plain).help(task.completed ? "Reopen task" : "Complete task")
            Button { overflow = false; editing = .task(task, day) } label: {
                Text(task.title).strikethrough(task.completed).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            if task.due == day { Image(systemName: "flag.fill").font(.system(size: 8)).foregroundStyle(.secondary) }
        }.font(.system(size: wide ? 13 : 11)).frame(height: 21).padding(.horizontal, 5).opacity(task.completed ? 0.45 : 1)
            .help(task.title + (task.due == day ? " · Due" : " · Planned"))
            .onDrag { NSItemProvider(object: ((task.due == day ? "task:" : "planned:") + task.id) as NSString) }
    }
}
