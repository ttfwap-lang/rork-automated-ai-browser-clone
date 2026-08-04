import Foundation

/// Repairs one broken step of a saved routine.
///
/// Sites are redesigned, buttons get renamed, panels move. A saved automation
/// that only knows "press the thing called X" dies the day X becomes "X now".
/// This is the ladder it climbs instead, cheapest rung first:
///
/// 1. **Exact** — name, kind, neighbourhood and rough position still agree. Free.
/// 2. **Relaxed** — same kind of control, clearly the same thing under a
///    different label, in roughly the same place. Free.
/// 3. **Judgement** — a shortlist of things that could be it, handed first to
///    this iPhone's free model and only then to one paid call.
/// 4. **Impossible** — nothing on the page could be it, said plainly instead of
///    pretending.
///
/// The guardrail that matters is in rung 3: the model is never asked "where is
/// the button?", it is asked to choose from elements that provably exist on the
/// live page right now. A healer allowed to invent a target is a healer that
/// confidently presses the wrong thing.
nonisolated enum StepHealer {

    /// How alike two labels have to be before they can be the same control.
    static let minimumNameAffinity = 0.5
    /// Overall closeness needed to accept a relaxed match without asking anyone.
    static let relaxedThreshold = 0.62
    /// Below this a candidate is not worth putting on a shortlist.
    static let candidateFloor = 0.18
    /// A shortlist longer than this is not a shortlist.
    static let maxCandidates = 6

    nonisolated struct Candidate: Equatable, Sendable, Identifiable {
        let id: Int
        let descriptor: String
        let closeness: Double

        var line: String { "[\(id)] \(descriptor)" }
    }

    nonisolated enum Repair: Equatable {
        /// The remembered target is still exactly there.
        case exact(Int)
        /// Something else is clearly the same control, with the reason why.
        case relaxed(Int, String)
        /// It needs a decision, from these real page elements only.
        case needsJudgement([Candidate])
        /// Nothing here could be it.
        case impossible(String)

        var elementID: Int? {
            switch self {
            case .exact(let id), .relaxed(let id, _): id
            case .needsJudgement, .impossible: nil
            }
        }
    }

    /// Finds the remembered target on the live page, or works out what to do next.
    static func repair(for target: ElementFingerprint, in observation: PageObservation?) -> Repair {
        guard let observation else {
            return .impossible("the page scan is unavailable, so the saved step cannot be matched")
        }
        guard !target.name.trimmed.isEmpty else {
            return .impossible("the saved step has no target to look for")
        }

        // Rung 1: the fingerprint's own test — name and kind must agree exactly.
        let exact = observation.elements
            .map { (element: $0, score: target.score(against: $0, in: observation)) }
            .filter { $0.score > 0 }
            .max { $0.score < $1.score }
        if let exact {
            return .exact(exact.element.id)
        }

        // Rungs 2 and 3 read the same shortlist, so there is one rule for what
        // could possibly be this control rather than two that can drift apart.
        let shortlist = candidates(for: target, in: observation)

        if let best = shortlist.first, best.closeness >= relaxedThreshold {
            return .relaxed(
                best.id,
                "\(best.descriptor) is where “\(target.name)” used to be, and matches it closely enough to be the same control"
            )
        }

        if !shortlist.isEmpty {
            return .needsJudgement(shortlist)
        }

        return .impossible("nothing on this page resembles the \(target.kind.rawValue) “\(target.name)”")
    }

    /// Everything on the page that could plausibly be this control, best first.
    /// This is what a model is briefed with, so it can only ever choose something
    /// that really is on the page.
    static func candidates(for target: ElementFingerprint, in observation: PageObservation) -> [Candidate] {
        observation.elements
            .filter { $0.kind == target.kind }
            .filter { !$0.name.trimmed.isEmpty }
            .map { Candidate(id: $0.id, descriptor: $0.shortDescriptor, closeness: closeness(of: $0, to: target, in: observation)) }
            .filter { $0.closeness >= candidateFloor }
            .sorted { $0.closeness > $1.closeness }
            .prefix(maxCandidates)
            .map { $0 }
    }

    /// How likely this element is the remembered one, 0–1.
    ///
    /// The label carries most of the weight because it is what a person would use
    /// to recognise a control. Neighbours and position are corroboration only:
    /// position alone is exactly how replay goes wrong.
    static func closeness(of element: ScannedElement, to target: ElementFingerprint, in observation: PageObservation) -> Double {
        guard element.kind == target.kind else { return 0 }
        let affinity = nameAffinity(element.name, target.name)
        guard affinity >= minimumNameAffinity else { return 0 }

        let liveNeighbours = Set(
            observation.elements
                .filter { $0.id != element.id && !$0.name.trimmed.isEmpty }
                .map { $0.name.trimmed.lowercased() }
        )
        let remembered = Set(target.neighbourhood.map { $0.lowercased() }.filter { !$0.isEmpty })
        let neighbourOverlap = remembered.isEmpty
            ? 0.5
            : Double(remembered.intersection(liveNeighbours).count) / Double(remembered.count)

        let width = max(observation.viewportWidth, 1)
        let height = max(observation.viewportHeight, 1)
        let liveX = (element.x + element.width / 2) / width
        let liveY = (element.y + element.height / 2) / height
        let dx = liveX - target.approxX
        let dy = liveY - target.approxY
        let drift = (dx * dx + dy * dy).squareRoot()
        let proximity = max(0, 1 - drift)

        return 0.6 * affinity + 0.25 * neighbourOverlap + 0.15 * proximity
    }

    /// How alike two visible labels are, 0–1.
    static func nameAffinity(_ left: String, _ right: String) -> Double {
        let a = left.trimmed.lowercased()
        let b = right.trimmed.lowercased()
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame { return 1 }
        if a.contains(b) || b.contains(a) { return 0.85 }

        let left = tokens(a)
        let right = tokens(b)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let shared = left.intersection(right).count
        return Double(shared) / Double(min(left.count, right.count))
    }

    /// Words worth comparing inside a label.
    static func tokens(_ text: String) -> Set<String> {
        Set(
            text
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 1 }
        )
    }

    /// The honest line written into the log when a step had to be repaired.
    static func repairLine(_ note: String) -> String {
        "the saved step no longer matched, and was repaired: \(note)"
    }
}
