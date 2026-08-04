import Foundation

/// Live state of one checklist task inside a mission plan.
nonisolated enum MissionTaskState: String, Codable, Hashable {
    case pending
    case current
    case done
    case skipped

    var label: String {
        switch self {
        case .pending: "TODO"
        case .current: "NOW"
        case .done: "DONE"
        case .skipped: "SKIPPED"
        }
    }

    /// Done and skipped tasks are settled — they never become current again on their own.
    var isSettled: Bool {
        self == .done || self == .skipped
    }
}
