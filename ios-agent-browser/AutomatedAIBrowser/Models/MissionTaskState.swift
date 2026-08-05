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

    /// Compact marker for the live thinking panel's task rail, where there is only
    /// room for a glyph and a number.
    var icon: String {
        switch self {
        case .pending: "circle"
        case .current: "circle.inset.filled"
        case .done: "checkmark"
        case .skipped: "minus"
        }
    }

    /// Done and skipped tasks are settled — they never become current again on their own.
    var isSettled: Bool {
        self == .done || self == .skipped
    }
}
