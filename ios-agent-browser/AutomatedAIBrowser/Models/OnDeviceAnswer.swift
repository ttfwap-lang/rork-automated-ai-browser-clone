import Foundation

/// What came back from this iPhone's own model.
///
/// Every failure is a value rather than a thrown error, so a free answer can
/// never break a run: the caller reads the outcome, hands the step to the cloud,
/// and says so honestly on the step card.
nonisolated enum OnDeviceAnswer: Equatable, Sendable {
    case answered(String)
    /// Declined on safety grounds — treated exactly like a hesitation.
    case refused(String)
    /// Slower than the budget, so the cloud takes the step.
    case timedOut
    /// The model is not available at all; the state says why.
    case unavailable(OnDeviceState)
    case failed(String)

    var text: String? {
        if case .answered(let value) = self { return value }
        return nil
    }

    /// The honest one-liner appended to a step when the cloud had to take over.
    /// nil when nothing was handed over.
    var handoffNote: String? {
        switch self {
        case .answered:
            nil
        case .refused(let why):
            why
        case .timedOut:
            "your iPhone's model took too long"
        case .unavailable(let state):
            state.isReady ? "your iPhone's model was unavailable" : state.label.lowercased()
        case .failed(let why):
            why
        }
    }
}
