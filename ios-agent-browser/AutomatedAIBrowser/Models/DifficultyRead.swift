import Foundation

/// The difficulty read for one step, with the reasons behind it so nothing about
/// the agent's spending is a mystery.
nonisolated struct DifficultyRead: Codable, Hashable {
    let difficulty: StepDifficulty
    /// Plain reasons, e.g. "the last move got no reaction".
    let reasons: [String]
    /// True when something irreversible (buy, submit, send, delete) is on screen.
    let isIrreversible: Bool
    /// True when the page scan failed and the agent is flying on vision alone.
    let isFlyingBlind: Bool

    static let routine = DifficultyRead(
        difficulty: .routine,
        reasons: ["a simple page with few choices"],
        isIrreversible: false,
        isFlyingBlind: false
    )

    /// One-line explanation for the step card and the run log.
    var summary: String {
        reasons.isEmpty ? difficulty.label.lowercased() : reasons.joined(separator: " · ")
    }

    /// What the agent is told about the moment it is in. Only hard steps get a
    /// note — on easy steps the extra words would just be noise.
    var briefingNote: String? {
        guard difficulty == .hard else { return nil }
        return "THIS MOMENT LOOKS HARD (\(reasons.joined(separator: "; "))). Slow down and think about more than one route."
    }
}
