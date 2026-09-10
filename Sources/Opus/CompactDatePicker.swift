import SwiftUI

struct CompactDatePicker: View {
    @Binding var value: String?
    var close: () -> Void
    @State private var month: Date
    init(value: Binding<String?>, close: @escaping () -> Void) {
        _value = value; self.close = close
        _month = State(initialValue: Day.date(value.wrappedValue ?? Day.today))
    }
    private var days: [String] { CalendarLayout.days(containing: month, week: false) }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { move(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Previous month")
                Button { move(1) } label: { Image(systemName: "chevron.right") }
                    .help("Next month")
            }.buttonStyle(.plain)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(days.prefix(7).enumerated()), id: \.offset) { _, day in
                    Text(Day.date(day).formatted(.dateTime.weekday(.narrow)))
                        .font(.caption).foregroundStyle(.secondary).frame(height: 24)
                }
                ForEach(days, id: \.self) { day in
                    let selected = day == value
                    let inMonth = Calendar.current.isDate(Day.date(day), equalTo: month, toGranularity: .month)
                    Button { value = day; close() } label: {
                        Text(Day.date(day).formatted(.dateTime.day()))
                            .font(.system(size: 12, weight: day == Day.today ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.white : inMonth ? Color.primary : Color.secondary)
                            .frame(width: 30, height: 30)
                            .background(selected ? Color.accentColor : day == Day.today ? Color.accentColor.opacity(0.12) : .clear, in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel(day)
                }
            }
            HStack {
                Button("Today") { value = Day.today; close() }
                Spacer()
                if value != nil { Button("Clear") { value = nil; close() } }
            }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(width: 266)
    }
    private func move(_ amount: Int) {
        month = Calendar.current.date(byAdding: .month, value: amount, to: month)!
    }
}
