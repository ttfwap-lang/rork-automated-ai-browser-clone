import Foundation

/// Lifecycle state of a single agent step.
nonisolated enum StepStatus: String, Codable {
    case proposed
    case rejected
    case executed
    case terminal

    var label: String {
        switch self {
        case .proposed: "PROPOSED"
        case .rejected: "REJECTED"
        case .executed: "OK"
        case .terminal: "END"
        }
    }
}
