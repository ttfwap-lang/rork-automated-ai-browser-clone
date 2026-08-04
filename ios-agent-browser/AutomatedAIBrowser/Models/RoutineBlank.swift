import Foundation

/// One thing a saved replay has to ask for before it can run.
///
/// This is where the privacy guarantee and the usefulness of a one-tap replay
/// meet. A useful replay almost always needs something typed — a search term, a
/// postcode, an order number — and a stored route deliberately never keeps what
/// was typed. So the route keeps the QUESTION and throws the ANSWER away: "type
/// ⟨what you're looking for⟩ into Search". You fill it in at launch, and the
/// guarantee holds by construction rather than by policy.
nonisolated struct RoutineBlank: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    /// What to ask for, in the user's words: "what you're looking for".
    var label: String
    /// Which move of the routine this fills.
    let moveIndex: Int

    init(id: UUID = UUID(), label: String, moveIndex: Int) {
        self.id = id
        self.label = label
        self.moveIndex = moveIndex
    }

    /// The placeholder as it appears inside the goal template.
    var token: String { "⟨\(label)⟩" }

    /// The prompt shown above the field at launch.
    var question: String {
        "What should go in for “\(label)”?"
    }
}
