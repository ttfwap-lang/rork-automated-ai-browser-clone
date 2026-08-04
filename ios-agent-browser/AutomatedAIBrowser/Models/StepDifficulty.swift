import Foundation

/// The app's honest opinion of how hard the current moment is. Costs nothing —
/// it is read from signals the app already has — and drives both which model
/// decides the step and whether the agent is asked to draft alternatives.
nonisolated enum StepDifficulty: String, Codable, Hashable {
    case routine
    case normal
    case hard

    var label: String {
        switch self {
        case .routine: "ROUTINE"
        case .normal: "NORMAL"
        case .hard: "HARD"
        }
    }

    var icon: String {
        switch self {
        case .routine: "gauge.low"
        case .normal: "gauge.medium"
        case .hard: "gauge.high"
        }
    }
}
