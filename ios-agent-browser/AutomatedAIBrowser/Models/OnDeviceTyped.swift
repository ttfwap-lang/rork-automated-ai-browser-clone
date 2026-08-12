import Foundation

/// What came back from a *guided* request to this iPhone's own model.
///
/// Guided generation returns a real Swift value or nothing at all — there is no
/// half-parsed middle ground to handle. So this has exactly two arms: the value,
/// or the honest reason there isn't one, reusing `OnDeviceAnswer` so every
/// handoff note in the app reads the same way.
nonisolated enum OnDeviceTyped<Value>: Sendable where Value: Sendable {
    case answered(Value)
    case declined(OnDeviceAnswer)

    var value: Value? {
        if case .answered(let value) = self { return value }
        return nil
    }

    /// The honest one-liner for the step card when the free tier could not answer.
    var handoffNote: String? {
        if case .declined(let answer) = self { return answer.handoffNote }
        return nil
    }
}
