import UIKit

/// A live (in-memory) step of the current run, including exactly what the AI
/// saw: the badged snapshot, the element map briefing, and — when the previous
/// step captured one — the stitched whole-page overview.
struct AgentStep: Identifiable {
    let id = UUID()
    let index: Int
    let action: AgentAction
    let reasoning: String
    var result: String?
    var status: StepStatus
    /// The screenshot sent to the AI (with numbered badges when the scan worked).
    /// Downscaled once the step is no longer recent, so a long run's memory
    /// ceiling stops growing.
    var snapshot: UIImage?
    /// The element map text sent to the AI; nil when the page scan was unavailable.
    let pageMap: String?
    /// The stitched whole-page overview also sent to the AI this step, if any.
    var overviewImage: UIImage? = nil
    /// Coverage note for the overview, e.g. "covers the whole page (~4 screens)".
    var overviewNote: String? = nil
    /// Mission-plan task this move served, resolved to its title by the app.
    var taskNumber: Int? = nil
    var taskTitle: String? = nil
    /// Set only on independent-check entries — the verdict and its evidence.
    var verification: VerificationResult? = nil
    /// Which model decided this step, and why it was routed there. nil on moves
    /// replayed from memory — no model decided those.
    var modelChoice: ModelChoice? = nil
    var routingReason: String? = nil
    /// Set on a move replayed from a remembered route, instead of a model chip.
    var isReplayed = false
    /// Set when a saved step no longer matched the page and had to be repaired.
    var wasHealed = false
    /// How the repair was found, in plain words.
    var healNote: String? = nil
    /// How this move's target could be found again on a later visit. Captured at
    /// act time, and never holds anything typed.
    var targetFingerprint: ElementFingerprint? = nil
    /// The app's read of how hard this moment was.
    var difficulty: StepDifficulty? = nil
    var difficultyReason: String? = nil
    /// The shortlist the agent weighed on a hard step, best-first with scores.
    var candidates: [MoveCandidate] = []
    /// Where a rewind landed — shown instead of the pre-rewind snapshot.
    var destinationSnapshot: UIImage? = nil
    /// True once this step's stored images have been shrunk for memory.
    var imagesTrimmed = false
    let timestamp = Date()

    /// True for the app's own independent-check log entry.
    var isCheckEntry: Bool { action.kind == .verify }

    /// True for the app's own head-start summary entry.
    var isHeadStartEntry: Bool { action.kind == .headStart }

    /// True for the app's own one-tap replay summary entry.
    var isReplayEntry: Bool { action.kind == .replay }

    /// What the log shows in the number slot. Neither the independent check nor
    /// the head-start summary is a step you paid a decision for, so each gets its
    /// own marker instead of borrowing a step number.
    var displayNumber: String {
        if isCheckEntry { return "✓" }
        if isHeadStartEntry { return "»" }
        if isReplayEntry { return "▸" }
        return String(format: "%02d", index)
    }

    /// The image to show on the card: a rewind shows where it landed.
    var displaySnapshot: UIImage? { destinationSnapshot ?? snapshot }
}
