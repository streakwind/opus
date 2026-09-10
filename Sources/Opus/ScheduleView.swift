import SwiftUI

struct SchedulePlacement: Identifiable {
    var block: ScheduleBlock
    var column: Int
    var columns: Int
    var id: String { block.id }
}
enum ScheduleLayout {
    static func minute(at y: CGFloat, hourHeight: CGFloat = 60) -> Int {
        min(1425, max(0, Int(y / hourHeight * 60 / 15) * 15))
    }
    static func range(startY: CGFloat, endY: CGFloat, hourHeight: CGFloat = 60) -> (start: Int, duration: Int) {
        let start = minute(at: startY, hourHeight: hourHeight)
        let rawEnd = endY / hourHeight * 60
        let snappedEnd = min(1440, max(0, Int((rawEnd / 15).rounded()) * 15))
        let lower = min(start, snappedEnd)
        let upper = max(start, snappedEnd)
        return (lower, max(15, min(1440, upper == lower ? lower + 15 : upper) - lower))
    }
    static func block(day: String, startY: CGFloat, endY: CGFloat, hourHeight: CGFloat = 60) -> ScheduleBlock {
        let range = range(startY: startY, endY: endY, hourHeight: hourHeight)
        return ScheduleBlock(day: day, startMinute: range.start, duration: range.duration)
    }
    static func placements(_ blocks: [ScheduleBlock]) -> [SchedulePlacement] {
        let sorted = blocks.sorted { $0.startMinute == $1.startMinute ? $0.id < $1.id : $0.startMinute < $1.startMinute }
        var result: [SchedulePlacement] = []
        var group: [SchedulePlacement] = []
        var ends: [Int] = []
        func flush() {
            for var item in group { item.columns = ends.count; result.append(item) }
            group = []; ends = []
        }
        for block in sorted {
            if !ends.isEmpty && block.startMinute >= ends.max()! { flush() }
            let column = ends.firstIndex { $0 <= block.startMinute } ?? ends.count
            if column == ends.count { ends.append(block.startMinute + block.duration) }
            else { ends[column] = block.startMinute + block.duration }
            group.append(SchedulePlacement(block: block, column: column, columns: 1))
        }
        flush()
        return result
    }
}
struct ScheduleView: View {
    var store: Store
    var query: String
    var newEntryRequest: Int
    var editorLeadingInset: CGFloat = 0
    @State private var anchor = Date()
    @State private var period = CalendarPeriod.week
    @State private var editing: ScheduleBlock?
    @State private var creating: ScheduleBlock?
    @State private var selectedMinute = 7 * 60
    private let hourHeight: CGFloat = 60
    private var days: [String] { period == .day ? [Day.string(anchor)] : CalendarLayout.days(containing: anchor, week: true) }
    var body: some View {
        VStack(spacing: 0) {
            CalendarHeading(anchor: $anchor, period: $period, schedule: true)
            if period == .week {
                HStack(spacing: 0) {
                    Color.clear.frame(width: 56, height: 52)
                    ForEach(days, id: \.self) { day in
                        Button {
                            anchor = Day.date(day); period = .day
                        } label: {
                            VStack(spacing: 3) {
                                Text(Day.date(day).formatted(.dateTime.weekday(.abbreviated))).font(.caption).foregroundStyle(.secondary)
                                Text(Day.date(day).formatted(.dateTime.day())).font(.system(size: 18)).foregroundStyle(day == Day.today ? .white : .primary).frame(width: 30, height: 30).background(day == Day.today ? Color.accentColor : .clear, in: Circle())
                            }.frame(maxWidth: .infinity)
                        }.buttonStyle(.plain)
                    }
                }.frame(height: 58).padding(.bottom, 8)
            }
            GeometryReader { geometry in
                let columnWidth = max(1, (geometry.size.width - 56) / CGFloat(days.count))
                ScrollViewReader { reader in
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 0) {
                            VStack(spacing: 0) {
                                ForEach(0..<24) { hour in
                                    Text(ClockTime.label(hour * 60)).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 50, height: hourHeight, alignment: .topTrailing).padding(.trailing, 6).id(hour)
                                }
                            }
                            ForEach(days, id: \.self) { day in
                                dayColumn(day, width: columnWidth)
                            }
                        }.frame(height: hourHeight * 24)
                    }
                    .onAppear { reader.scrollTo(selectedMinute / 60, anchor: .top) }
                    .onChange(of: period) { _, _ in reader.scrollTo(selectedMinute / 60, anchor: .top) }
                    .onChange(of: anchor) { _, _ in reader.scrollTo(selectedMinute / 60, anchor: .top) }
                }
            }
        }
        .overlay {
            if let draft = editing {
                EditorCardBackdrop(leadingInset: editorLeadingInset) {
                    ScheduleEditor(
                        store: store,
                        block: draft,
                        onChange: { updated in
                            editing = updated
                            selectedMinute = updated.startMinute
                            if !days.contains(updated.day) { anchor = Day.date(updated.day) }
                        },
                        onDismiss: { editing = nil }
                    )
                    .id(draft.id)
                    .editorCard()
                }
            }
        }
        .onChange(of: newEntryRequest) { _, _ in
            let day = Day.string(anchor)
            editing = ScheduleBlock(day: day, startMinute: min(1410, ClockTime.minutes(Date()) / 15 * 15), duration: 30)
        }
        .onChange(of: anchor) { _, _ in store.refreshOccurrences(through: days.last) }
        .onAppear { store.refreshOccurrences(through: days.last) }
    }
    private func dayColumn(_ day: String, width: CGFloat) -> some View {
        let classes = store.state.courses.flatMap { $0.classBlocks(on: day) }
        let displayed = classes + store.state.schedule.filter { $0.id != editing?.id } + (editing.map { [$0] } ?? [])
        let blocks = displayed.filter {
            $0.day == day &&
            (query.isEmpty ||
             $0.title.localizedCaseInsensitiveContains(query) ||
             (store.course($0.courseID)?.name.localizedCaseInsensitiveContains(query) ?? false))
        }
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<24) { _ in
                    VStack(spacing: 0) {
                        Rectangle().fill(Color.primary.opacity(0.13)).frame(height: 0.5)
                        Spacer(minLength: 0)
                    }.frame(height: hourHeight)
                }
            }.frame(width: width).background(Calendar.current.isDateInWeekend(Day.date(day)) ? Color.primary.opacity(0.025) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { point in
                    selectedMinute = ScheduleLayout.minute(at: point.y, hourHeight: hourHeight)
                    editing = ScheduleBlock(day: day, startMinute: selectedMinute, duration: min(30, 1440 - selectedMinute))
                }
                .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .local)
                    .onChanged { value in
                        creating = ScheduleLayout.block(day: day, startY: value.startLocation.y, endY: value.location.y, hourHeight: hourHeight)
                    }
                    .onEnded { value in
                        let block = ScheduleLayout.block(day: day, startY: value.startLocation.y, endY: value.location.y, hourHeight: hourHeight)
                        creating = nil
                        selectedMinute = block.startMinute
                        editing = block
                    })
            if let creating, creating.day == day {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor.opacity(0.45))
                    .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
                    .frame(width: max(10, width - 10), height: max(15, CGFloat(creating.duration) / 60 * hourHeight - 2))
                    .offset(x: 1, y: CGFloat(creating.startMinute) / 60 * hourHeight)
                    .allowsHitTesting(false)
            }
            ForEach(ScheduleLayout.placements(blocks)) { placement in
                let block = placement.block
                let usableWidth = max(10, width - 9)
                let blockWidth = max(10, usableWidth / CGFloat(placement.columns) - 3)
                let blockHeight = max(15, CGFloat(block.duration) / 60 * hourHeight - 2)
                Group {
                    if block.id.hasPrefix("class:"), let course = store.course(block.courseID) {
                        ClassScheduleCard(store: store, course: course, block: block)
                    } else {
                        ScheduleEventCard(store: store, block: block, fill: store.course(block.courseID)?.scheduleGradient ?? Course(name: "", color: "teal").scheduleGradient, edit: {
                            editing = block
                            selectedMinute = block.startMinute
                        })
                    }
                }
                .frame(width: blockWidth, height: blockHeight).clipped()
                .offset(x: CGFloat(placement.column) * usableWidth / CGFloat(placement.columns) + 1, y: CGFloat(block.startMinute) / 60 * hourHeight)
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                if day == Day.string(context.date) {
                    Rectangle().fill(Color.accentColor).frame(height: 1)
                        .overlay(alignment: .leading) { Circle().fill(Color.accentColor).frame(width: 5, height: 5) }
                        .offset(y: CGFloat(ClockTime.minutes(context.date)) / 60 * hourHeight)
                }
            }.allowsHitTesting(false)
        }.frame(width: width, height: hourHeight * 24)
            .overlay(alignment: .trailing) { Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 0.5) }
            .dropDestination(for: String.self) { values, location in
                guard let payload = values.first, payload.hasPrefix("schedule:"), var block = store.state.schedule.first(where: { $0.id == String(payload.dropFirst(9)) }) else { return false }
                block.day = day; block.startMinute = min(1440 - block.duration, max(0, Int(location.y / hourHeight * 60 / 15) * 15))
                store.save(block); return store.error == nil
            }
    }
}
private struct ScheduleEventCard: View {
    var store: Store
    var block: ScheduleBlock
    var fill: LinearGradient
    var edit: () -> Void
    var body: some View {
        Button(action: edit) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(block.title.isEmpty ? "New event" : block.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    if block.ruleID != nil { RepeatBadge(style: .fill) }
                }
                if block.duration >= 45 { Text(ClockTime.label(block.startMinute)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.8)).lineLimit(1) }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(4)
                .foregroundStyle(.white)
                .background(fill, in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain).help(block.title + " · " + block.timeLabel).draggable("schedule:" + block.id)
            .contextMenu {
                if block.ruleID != nil {
                    Button("Delete this event") { store.deleteSchedule(block, scope: .thisEvent) }
                    Button("Delete this and following") { store.deleteSchedule(block, scope: .thisAndFollowing) }
                    Button("Delete all events", role: .destructive) { store.deleteSchedule(block, scope: .allEvents) }
                } else {
                    Button("Delete", role: .destructive) { store.deleteSchedule(block, scope: .thisEvent) }
                }
            }
    }
}
