import Foundation

/// Where one step's time went, and what its AI calls cost — so a slow run
/// says which part was slow instead of just being slow.
nonisolated struct StepTiming: Equatable, Sendable {
    /// Phases in the order they happened, e.g. ("settle", 0.4).
    private(set) var phases: [(label: String, seconds: TimeInterval)] = []
    private var lastLap = Date()

    init(start: Date = Date()) {
        lastLap = start
    }

    /// Records the time since the previous lap under `label`. A label used
    /// twice accumulates, so a phase split by other work still reads as one.
    mutating func lap(_ label: String, now: Date = Date()) {
        let seconds = max(0, now.timeIntervalSince(lastLap))
        lastLap = now
        if let index = phases.firstIndex(where: { $0.label == label }) {
            phases[index].seconds += seconds
        } else {
            phases.append((label, seconds))
        }
    }

    /// `settle 0.4s · scan 0.2s · decide 6.1s · act 1.2s · 1 call · 14.2k in …`
    func line(calls: CallTotals) -> String {
        var parts = phases
            .filter { $0.seconds >= 0.05 }
            .map { "\($0.label) \(String(format: "%.1fs", $0.seconds))" }
        if calls.calls > 0 { parts.append(calls.line) }
        return parts.joined(separator: " · ")
    }

    static func == (lhs: StepTiming, rhs: StepTiming) -> Bool {
        lhs.phases.map(\.label) == rhs.phases.map(\.label)
            && lhs.phases.map(\.seconds) == rhs.phases.map(\.seconds)
    }
}
