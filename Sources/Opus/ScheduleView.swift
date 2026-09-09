import SwiftUI

struct SchedulePlacement: Identifiable {
    var block: ScheduleBlock
    var column: Int
    var columns: Int
    var id: String { block.id }
}
enum ScheduleLayout {
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
    private let hourHeight: CGFloat = 60
    private var days: [String] { period == .day ? [Day.string(anchor)] : CalendarLayout.days(containing: anchor, week: true) }
    var body: some View {
        VStack(spacing: 0) {
            CalendarHeading(anchor: $anchor, period: $period, schedule: true)
                .popover(item: $editing) { ScheduleEditor(store: store, block: $0).id($0.id) }
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
            Divider()
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
                    }.onAppear { reader.scrollTo(7, anchor: .top) }
                }
            }
        }
        .onChange(of: newEntryRequest) { _, _ in editing = ScheduleBlock(day: Day.string(anchor)) }
        .onChange(of: anchor) { _, _ in store.refreshOccurrences(through: days.last) }
        .onAppear { store.refreshOccurrences(through: days.last) }
    }
    private func dayColumn(_ day: String, width: CGFloat) -> some View {
        let blocks = store.state.schedule.filter { $0.day == day && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
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
                    editing = ScheduleBlock(day: day, startMinute: min(1380, max(0, Int(point.y / hourHeight * 60 / 15) * 15)))
                }
            ForEach(ScheduleLayout.placements(blocks)) { placement in
                let block = placement.block
                let blockWidth = max(10, width / CGFloat(placement.columns) - 3)
                let blockHeight = max(15, CGFloat(block.duration) / 60 * hourHeight - 2)
                ScheduleEventCard(block: block, tint: store.course(block.courseID)?.tint ?? .teal, edit: { editing = block }, delete: { store.change { $0.schedule.removeAll { $0.id == block.id } } })
                    .frame(width: blockWidth, height: blockHeight).clipped()
                    .offset(x: CGFloat(placement.column) * width / CGFloat(placement.columns) + 1, y: CGFloat(block.startMinute) / 60 * hourHeight)

            }
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
    var block: ScheduleBlock
    var tint: Color
    var edit: () -> Void
    var delete: () -> Void
    var body: some View {
        Button(action: edit) {
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title).font(.system(size: 11, weight: .medium)).lineLimit(block.duration >= 60 ? 2 : 1)
                if block.duration >= 45 { Text(ClockTime.label(block.startMinute)).font(.system(size: 10)).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(4)
                .background(tint.opacity(0.17), in: RoundedRectangle(cornerRadius: 4))
                .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 3) }
        }.buttonStyle(.plain).help(block.title + " · " + block.timeLabel).draggable("schedule:" + block.id)
            .contextMenu { Button("Delete", role: .destructive, action: delete) }
    }
}
