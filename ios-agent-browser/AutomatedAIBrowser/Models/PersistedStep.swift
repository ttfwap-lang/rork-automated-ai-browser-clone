import Foundation

/// Disk-friendly form of an agent step stored in run history.
/// New fields are optional so runs saved by earlier builds keep decoding.
nonisolated struct PersistedStep: Codable, Identifiable, Hashable {
    let id: UUID
    let index: Int
    let actionType: String
    let actionDetail: String
    let reasoning: String
    let result: String?
    let statusRaw: String
    let thumbnailFile: String?
    /// Mission-plan task this move served.
    var taskNumber: Int? = nil
    var taskTitle: String? = nil
    /// Independent-check verdict, on check entries.
    var verdictRaw: String? = nil
    /// Which model decided this step.
    var modelRaw: String? = nil
    /// The app's difficulty read for this step.
    var difficultyRaw: String? = nil
    /// How many moves were weighed before this one was played.
    var weighedCount: Int? = nil
    /// True when this move was replayed from a remembered route rather than decided.
    var wasReplayed: Bool? = nil
    /// True when a saved step had to be repaired because the site had moved it.
    var wasHealed: Bool? = nil

    var kind: AgentActionKind {
        AgentActionKind(rawValue: actionType) ?? .unknown
    }

    var status: StepStatus {
        StepStatus(rawValue: statusRaw) ?? .executed
    }

    var verdict: VerificationVerdict? {
        verdictRaw.flatMap { VerificationVerdict(rawValue: $0) }
    }

    var model: ModelChoice? {
        modelRaw.flatMap { ModelChoice(rawValue: $0) }
    }

    var difficulty: StepDifficulty? {
        difficultyRaw.flatMap { StepDifficulty(rawValue: $0) }
    }

    /// What the saved log shows in the number slot. Check entries get a tick —
    /// including runs saved when they still borrowed the previous step's number.
    var displayNumber: String {
        if kind == .headStart { return "»" }
        if kind == .replay { return "▸" }
        if kind == .verify || index == 0 { return "✓" }
        return String(format: "%02d", index)
    }
}
