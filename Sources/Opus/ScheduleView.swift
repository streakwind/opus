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
    @State private var anchor = Date()
    @State private var period = CalendarPeriod.week
    @State private var editing: ScheduleBlock?
    @State private var editorDay = Day.today
    @State private var scrollOffset: CGFloat = 420
    @State private var selectedMinute = 7 * 60
    private let hourHeight: CGFloat = 60
    private var days: [String] { period == .day ? [Day.string(anchor)] : CalendarLayout.days(containing: anchor, week: true) }
    var body: some View {
        VStack(spacing: 0) {
            CalendarHeading(anchor: $anchor, period: $period, schedule: true, workCount: period == .day ? workCount(on: days[0]) : nil)
            if period == .week {
                HStack(spacing: 0) {
                    Color.clear.frame(width: 56, height: 52)
                    ForEach(days, id: \.self) { day in
                        Button {
                            anchor = Day.date(day); period = .day
                        } label: {
                            VStack(spacing: 3) {
                                Text(Day.date(day).formatted(.dateTime.weekday(.abbreviated))).font(.caption).foregroundStyle(.secondary)
                                ZStack(alignment: .topTrailing) {
                                    Text(Day.date(day).formatted(.dateTime.day())).font(.system(size: 18)).foregroundStyle(day == Day.today ? .white : .primary).frame(width: 30, height: 30).background(day == Day.today ? Color.accentColor : .clear, in: Circle())
                                    let count = workCount(on: day)
                                    if count > 0 {
                                        Text("\(count)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                            .frame(minWidth: 15, minHeight: 15)
                                            .background(Color.secondary, in: Capsule())
                                            .offset(x: 9, y: -4)
                                    }
                                }
                            }.frame(maxWidth: .infinity)
                        }.buttonStyle(.plain).help(workCountLabel(on: day))
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
                        .background(GeometryReader { content in
                            Color.clear.preference(key: ScheduleScrollOffset.self, value: -content.frame(in: .named("scheduleViewport")).minY)
                        })
                    }.coordinateSpace(name: "scheduleViewport")
                    .onPreferenceChange(ScheduleScrollOffset.self) { scrollOffset = $0 }
                    .onAppear { reader.scrollTo(selectedMinute / 60, anchor: .top) }
                    .onChange(of: period) { _, _ in reader.scrollTo(selectedMinute / 60, anchor: .top) }
                    .onChange(of: anchor) { _, _ in reader.scrollTo(selectedMinute / 60, anchor: .top) }
                }
                .overlay(alignment: .topLeading) {
                    let column = days.firstIndex(of: editing?.day ?? editorDay) ?? 0
                    Color.clear.frame(width: 1, height: 1)
                        .position(x: 56 + (CGFloat(column) + 0.5) * columnWidth,
                                  y: min(geometry.size.height - 20, max(20, CGFloat(editing?.startMinute ?? 540) - scrollOffset)))
                        .popover(item: $editing) { draft in
                            ScheduleEditor(store: store, block: draft, onChange: { updated in
                                editing = updated; selectedMinute = updated.startMinute
                                if editorDay != updated.day {
                                    editorDay = updated.day; anchor = Day.date(updated.day)
                                }
                            }).id(draft.id)
                        }
                }
            }
        }
        .onChange(of: newEntryRequest) { _, _ in editorDay = Day.string(anchor); editing = ScheduleBlock(day: editorDay, startMinute: min(1380, ClockTime.minutes(Date()) / 15 * 15)) }
        .onChange(of: anchor) { _, _ in store.refreshOccurrences(through: days.last) }
        .onAppear { store.refreshOccurrences(through: days.last) }
    }
    private func dayColumn(_ day: String, width: CGFloat) -> some View {
        let classes = store.state.courses.compactMap { $0.classBlock(on: day) }
        let displayed = classes + store.state.schedule.filter { $0.id != editing?.id } + (editing.map { [$0] } ?? [])
        let blocks = displayed.filter { $0.day == day && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<24) { _ in
                    VStack(spacing: 0) {
                        Rectangle().fill(Color.primary.opacity(0.13)).frame(height: 0.5)
                        Spacer(minLength: 0)
                    }.frame(height: hourHeight)
                }
            }.frame(width: width).background(Calendar.current.isDateInWeekend(Day.date(day)) ? Color.primary.opacity(0.025) : Color.clear)
                .contentShape(Rectangle()).onTapGesture(coordinateSpace: .local) { point in
                    selectedMinute = ScheduleLayout.minute(at: point.y, hourHeight: hourHeight)
                    editorDay = day; editing = ScheduleBlock(day: day, startMinute: selectedMinute, duration: min(60, 1440 - selectedMinute))
                }
            ForEach(ScheduleLayout.placements(blocks)) { placement in
                let block = placement.block
                let blockWidth = max(10, width / CGFloat(placement.columns) - 3)
                let blockHeight = max(15, CGFloat(block.duration) / 60 * hourHeight - 2)
                Group {
                    if block.id.hasPrefix("class:"), let course = store.course(block.courseID) {
                        ClassScheduleCard(store: store, course: course, day: day)
                    } else {
                        ScheduleEventCard(block: block, tint: store.course(block.courseID)?.tint ?? .teal, edit: { editorDay = day; editing = block }, delete: { store.change { $0.schedule.removeAll { $0.id == block.id } } })
                    }
                }
                .frame(width: blockWidth, height: blockHeight).clipped()
                .offset(x: CGFloat(placement.column) * width / CGFloat(placement.columns) + 1, y: CGFloat(block.startMinute) / 60 * hourHeight)


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
    private func workCount(on day: String) -> Int {
        let assessments = store.state.assessments.filter { $0.day == day }.count
        let tasks = store.state.tasks.filter { !$0.completed && ($0.due == day || $0.planned == day) }.count
        return assessments + tasks
    }
    private func workCountLabel(on day: String) -> String {
        let count = workCount(on: day)
        return count == 0 ? "No work due" : "\(count) \(count == 1 ? "item" : "items") due"
    }
}

private struct ScheduleEventCard: View {
    var block: ScheduleBlock
    var tint: Color
    var edit: () -> Void
    var delete: () -> Void
    var body: some View {
        Button(action: edit) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(block.title.isEmpty ? "New event" : block.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    if block.ruleID != nil { Image(systemName: "repeat").font(.system(size: 8, weight: .semibold)) }
                }
                if block.duration >= 45 { Text(ClockTime.label(block.startMinute)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.8)).lineLimit(1) }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(4)
                .foregroundStyle(.white)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain).help(block.title + " · " + block.timeLabel).draggable("schedule:" + block.id)
            .contextMenu { Button("Delete", role: .destructive, action: delete) }
    }
}

private struct ScheduleScrollOffset: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
