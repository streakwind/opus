import Foundation

/// Per-item last-writer-wins revisions. Tombstones survive offline devices returning.
/// Each installation publishes its own ledger, so concurrent uploads never replace
/// another device's file. SQLite itself is never placed in iCloud Drive.
package struct SyncLedger: Codable, Sendable {
    package struct Record: Codable, Equatable, Sendable {
        var payload: Data?
        var position: Int
        var clock: Int64
        package var device: String
    }
    var version = 1
    package var device: String = UUID().uuidString
    package var records: [String: Record] = [:]

    package init() {}

    package mutating func capture(_ snapshot: Snapshot, now: Date = Date()) throws {
        let values = try Self.values(snapshot)
        let clock = max(Int64(now.timeIntervalSince1970 * 1000), (records.values.map(\.clock).max() ?? 0) + 1)
        for (key, value) in values where records[key]?.payload != value.0 || records[key]?.position != value.1 {
            records[key] = Record(payload: value.0, position: value.1, clock: clock, device: device)
        }
        for key in Array(records.keys) where values[key] == nil && records[key]?.payload != nil {
            records[key] = Record(payload: nil, position: records[key]!.position, clock: clock, device: device)
        }
    }

    package mutating func merge(_ other: SyncLedger) throws {
        guard other.version == 1 else { throw StorageError.message("iCloud data requires a newer Opus version.") }
        for (key, incoming) in other.records {
            if let local = records[key],
               local.clock > incoming.clock || (local.clock == incoming.clock && local.device >= incoming.device) { continue }
            records[key] = incoming
        }
    }

    package func snapshot() throws -> Snapshot {
        func items<T: Decodable>(_ table: String) throws -> [T] {
            try records.filter { $0.key.hasPrefix(table + "/") && $0.value.payload != nil }
                .sorted { $0.value.position == $1.value.position ? $0.key < $1.key : $0.value.position < $1.value.position }
                .map { try JSONDecoder().decode(T.self, from: $0.value.payload!) }
        }
        var result = Snapshot()
        result.courses = try items("courses")
        result.tasks = try items("tasks")
        result.assessments = try items("assessments")
        result.rules = try items("rules")
        result.schedule = try items("schedule")
        result.activities = try items("activities")
        result.journal = try items("journal")
        result.generated = Set(try items("generated") as [String])
        if let payload = records["metadata/setup"]?.payload { result.setupComplete = try JSONDecoder().decode(Bool.self, from: payload) }
        // A deleted list moves its surviving work to Inbox. Deleted tasks cannot
        // leave activities with invalid foreign keys.
        let courses = Set(result.courses.map(\.id))
        for i in result.tasks.indices where !courses.contains(result.tasks[i].courseID ?? "") { result.tasks[i].courseID = nil }
        for i in result.assessments.indices where !courses.contains(result.assessments[i].courseID ?? "") { result.assessments[i].courseID = nil }
        for i in result.rules.indices where !courses.contains(result.rules[i].courseID ?? "") { result.rules[i].courseID = nil }
        for i in result.schedule.indices where !courses.contains(result.schedule[i].courseID ?? "") { result.schedule[i].courseID = nil }
        let tasks = Set(result.tasks.map(\.id))
        result.activities.removeAll { !tasks.contains($0.taskID) }
        return result
    }

    private static func values(_ snapshot: Snapshot) throws -> [String: (Data, Int)] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var values: [String: (Data, Int)] = [:]
        func add<T: Encodable & Identifiable>(_ table: String, _ items: [T]) throws where T.ID == String {
            for (position, item) in items.enumerated() { values[table + "/" + item.id] = (try encoder.encode(item), position) }
        }
        try add("courses", snapshot.courses)
        try add("tasks", snapshot.tasks)
        try add("assessments", snapshot.assessments)
        try add("rules", snapshot.rules)
        try add("schedule", snapshot.schedule)
        try add("activities", snapshot.activities)
        try add("journal", snapshot.journal)
        for key in snapshot.generated { values["generated/" + key] = (try encoder.encode(key), 0) }
        values["metadata/setup"] = (try encoder.encode(snapshot.setupComplete), 0)
        return values
    }
}
