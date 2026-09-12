import Foundation
package struct SchedulePlacement: Identifiable {
    package var block: ScheduleBlock
    package var column: Int
    package var columns: Int
    package var id: String { block.id }
    package init(block: ScheduleBlock, column: Int, columns: Int) {
        self.block = block
        self.column = column
        self.columns = columns
    }
}
package enum ScheduleLayout {
    package static func minute(at y: CGFloat, hourHeight: CGFloat = 60) -> Int {
        min(1425, max(0, Int(y / hourHeight * 60 / 15) * 15))
    }
    package static func range(startY: CGFloat, endY: CGFloat, hourHeight: CGFloat = 60) -> (start: Int, duration: Int) {
        let start = minute(at: startY, hourHeight: hourHeight)
        let rawEnd = endY / hourHeight * 60
        let snappedEnd = min(1440, max(0, Int((rawEnd / 15).rounded()) * 15))
        let lower = min(start, snappedEnd)
        let upper = max(start, snappedEnd)
        return (lower, max(15, min(1440, upper == lower ? lower + 15 : upper) - lower))
    }
    package static func block(day: String, startY: CGFloat, endY: CGFloat, hourHeight: CGFloat = 60) -> ScheduleBlock {
        let range = range(startY: startY, endY: endY, hourHeight: hourHeight)
        return ScheduleBlock(day: day, startMinute: range.start, duration: range.duration)
    }
    package static func placements(_ blocks: [ScheduleBlock]) -> [SchedulePlacement] {
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
