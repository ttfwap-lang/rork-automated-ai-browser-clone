import Foundation

/// How a run ended.
nonisolated enum RunOutcome: String, Codable, Hashable {
    case completed
    /// The agent claimed success but the independent check could not stand behind
    /// it — never shown as a green run.
    case unconfirmed
    case failed
    case stopped

    var label: String {
        switch self {
        case .completed: "COMPLETED"
        case .unconfirmed: "DONE, NOT CONFIRMED"
        case .failed: "FAILED"
        case .stopped: "STOPPED"
        }
    }

    var icon: String {
        switch self {
        case .completed: "checkmark.seal.fill"
        case .unconfirmed: "exclamationmark.shield.fill"
        case .failed: "xmark.octagon.fill"
        case .stopped: "hand.raised.fill"
        }
    }
}
