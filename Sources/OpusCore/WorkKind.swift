import Foundation
package enum WorkKind: String, CaseIterable, Identifiable {
    case task = "Task", progress = "Progress", assessment = "Assessment"
    package var id: String { rawValue }
}
