import Foundation

/// The independent check's ruling on a claimed success, with the on-screen
/// evidence behind it. Produced by a reviewer that never sees the agent's own
/// reasoning — agent self-justification is what inflates reviewers into false
/// agreement, so it is withheld by design.
nonisolated struct VerificationResult: Codable, Hashable {
    let verdict: VerificationVerdict
    /// The specific evidence on the fresh screen or page text behind the verdict.
    let evidence: String
    /// Written objection naming what is missing or wrong (rejections).
    let objection: String?
    /// The right answer, when the agent's summary misstated something visible.
    let correctedAnswer: String?
    /// Which model performed the check, for the audit trail.
    var checkedBy: String?

    init(
        verdict: VerificationVerdict,
        evidence: String,
        objection: String? = nil,
        correctedAnswer: String? = nil,
        checkedBy: String? = nil
    ) {
        self.verdict = verdict
        self.evidence = evidence
        self.objection = objection
        self.correctedAnswer = correctedAnswer
        self.checkedBy = checkedBy
    }

    /// The objection to hand back to the agent, falling back to the evidence.
    var pushback: String {
        if let objection, !objection.isEmpty { return objection }
        return evidence.isEmpty ? "the check could not see the goal achieved on the page" : evidence
    }
}
