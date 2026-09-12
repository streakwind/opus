import Foundation
import OpusCore

/// Wire format for GTK ↔ Swift class times: `id|start|end|day,day;...`
/// Uses `|` so UUIDs and other ids never collide with field separators.
package enum ClassTimeCodec {
    package static func encode(_ times: [ClassTime]) -> String {
        times.map { time in
            let days = time.days.map(String.init).joined(separator: ",")
            return "\(time.id)|\(time.startMinute)|\(time.endMinute)|\(days)"
        }.joined(separator: ";")
    }

    package static func parse(_ payload: String) -> [ClassTime] {
        guard !payload.isEmpty else { return [] }
        return payload.split(separator: ";", omittingEmptySubsequences: true).compactMap { chunk in
            let parts = chunk.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count >= 3,
                  let start = Int(parts[1]),
                  let end = Int(parts[2]) else { return nil }
            let id = String(parts[0]).isEmpty ? UUID().uuidString : String(parts[0])
            let days: [Int]
            if parts.count > 3 {
                days = parts[3].split(separator: ",", omittingEmptySubsequences: true).compactMap { Int($0) }
            } else {
                days = []
            }
            return ClassTime(id: id, startMinute: start, endMinute: end, days: days)
        }
    }
}
