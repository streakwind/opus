import Foundation

enum CalendarLayout {
    static func days(containing date: Date, week: Bool, calendar: Calendar = .current) -> [String] {
        let interval = calendar.dateInterval(of: week ? .weekOfYear : .month, for: date)!
        let start = calendar.dateInterval(of: .weekOfYear, for: interval.start)!.start
        let count: Int
        if week { count = 7 }
        else {
            let distance = calendar.dateComponents([.day], from: start, to: interval.end).day!
            count = ((distance + 6) / 7) * 7
        }
        return (0..<count).map { offset in
            Day.string(calendar.date(byAdding: .day, value: offset, to: start)!)
        }
    }
}
