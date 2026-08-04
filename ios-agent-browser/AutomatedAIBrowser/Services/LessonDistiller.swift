import Foundation

/// Reads a finished run and works out what the site taught the agent.
///
/// Every category here is decided in code from what actually happened — which
/// control did nothing, which banner had to go first, whether the check refused
/// the claim. No paid call is ever made to learn a lesson, and no model is asked
/// "what went wrong", because a model asked that question writes a plausible
/// story rather than a fact.
///
/// A model is offered exactly one job: shortening the wording of a single
/// caution, on this iPhone, for free. If it declines, the mechanical wording
/// stands and nothing is lost.
nonisolated enum LessonDistiller {

    /// What the run left behind, in the form the distiller needs to read it.
    nonisolated struct Evidence: Sendable {
        let moves: [RecipeDistiller.Move]
        let outcome: RunOutcome
        let verdict: VerificationVerdict?
        let failReason: String?
        /// True when a scan reported something covering the page.
        let overlaySeen: Bool
        /// True when the run ran out of steps rather than finishing.
        let hitStepLimit: Bool
        /// Honest handover notes from a replay that stopped matching the site.
        let mismatchNotes: [String]

        init(
            moves: [RecipeDistiller.Move],
            outcome: RunOutcome,
            verdict: VerificationVerdict? = nil,
            failReason: String? = nil,
            overlaySeen: Bool = false,
            hitStepLimit: Bool = false,
            mismatchNotes: [String] = []
        ) {
            self.moves = moves
            self.outcome = outcome
            self.verdict = verdict
            self.failReason = failReason
            self.overlaySeen = overlaySeen
            self.hitStepLimit = hitStepLimit
            self.mismatchNotes = mismatchNotes
        }
    }

    nonisolated struct Draft: Equatable, Sendable {
        let kind: LessonKind
        let subject: String?
        let caution: String
    }

    /// Never more than this from one run. A run that "learned" six things learned
    /// nothing.
    static let maxDrafts = 3

    /// Words that mark a real wall rather than a route the agent gave up on.
    static let wallWords = [
        "captcha", "robot", "bot check", "log in", "login", "logged in", "sign in",
        "signin", "sign-in", "account", "paywall", "subscription", "subscribe",
        "verify you", "403", "blocked", "not a human", "human",
    ]

    // MARK: - The mechanical read

    /// The lessons this run actually evidenced, strongest first.
    static func read(_ evidence: Evidence) -> [Draft] {
        var drafts: [Draft] = []

        // A wall is the most useful thing to know about a site, so it goes first.
        if let reason = evidence.failReason, readsAsWall(reason) {
            drafts.append(make(.gate, subject: nil))
        }

        // A banner that had to be cleared before the page would work.
        if let dismissal = evidence.moves.first(where: { move in
            move.kind == .tapElement
                && OnDeviceGate.isDismissal(move.fingerprint?.name ?? "")
        }) {
            drafts.append(make(.overlay, subject: dismissal.fingerprint?.name))
        } else if evidence.overlaySeen {
            drafts.append(make(.overlay, subject: nil))
        }

        // Controls that were pressed and did nothing, and fields that dropped
        // what was typed into them.
        for move in evidence.moves where ReactionWatch.readsAsFailure(move.result ?? "") {
            let name = move.fingerprint?.name
            switch move.kind {
            case .typeInto, .typeText, .fillForm:
                drafts.append(make(.typingIgnored, subject: name))
            case .tapElement, .tap, .longPress, .hover, .swipe, .selectOption, .setToggle, .setSlider:
                drafts.append(make(.deadControl, subject: name))
            default:
                break
            }
        }

        // A replay that stopped matching means the page has moved on.
        if evidence.mismatchNotes.contains(where: { readsAsVanished($0) }) {
            drafts.append(make(.vanished, subject: nil))
        }

        // A claim the independent check refused is worth remembering per site:
        // some pages look finished when they are not.
        if evidence.verdict == .rejected || evidence.outcome == .unconfirmed {
            drafts.append(make(.falseClaim, subject: nil))
        }

        if evidence.hitStepLimit {
            drafts.append(make(.deadEnd, subject: nil))
        }

        // The same caution twice from one run is still one caution.
        var seen: Set<String> = []
        let unique = drafts.filter { draft in
            let key = "\(draft.kind.rawValue)|\((draft.subject ?? "").lowercased())"
            return seen.insert(key).inserted
        }
        return Array(unique.prefix(maxDrafts))
    }

    /// The kinds of failure this run actually showed. Used to age out cautions
    /// that no longer match the site: a lesson is only doubted when the run
    /// worked the site and found no sign of it.
    static func observedKinds(_ evidence: Evidence) -> Set<LessonKind> {
        Set(read(evidence).map { $0.kind })
    }

    static func make(_ kind: LessonKind, subject: String?) -> Draft {
        let clean = (subject ?? "").trimmed
        let named = clean.isEmpty ? nil : String(clean.prefix(48))
        return Draft(kind: kind, subject: named, caution: kind.mechanicalCaution(subject: named))
    }

    /// True when a give-up reason describes a wall rather than a dead end.
    static func readsAsWall(_ reason: String) -> Bool {
        let lower = reason.lowercased()
        return wallWords.contains { lower.contains($0) }
    }

    /// True when a handover note says the page no longer matches what was known.
    static func readsAsVanished(_ note: String) -> Bool {
        let lower = note.lowercased()
        return lower.contains("not on this page any more")
            || lower.contains("was supposed to")
            || lower.contains("is missing")
            || lower.contains("no longer")
    }

    // MARK: - The written part, free or not at all

    static let instructions = """
    You shorten one caution about a website into something a person would say.

    Answer with exactly one line and nothing else:
    CAUTION: <the caution, at most 14 words, plain language, no preamble>

    Rules:
    - Keep the meaning EXACTLY. Never add a cause, a fix, or advice that was not given to you.
    - If the caution names a control in quotes, keep that name, in quotes, unchanged.
    - Never invent a page, a button or a reason. Never mention a search term or anything a person typed.
    - No preamble, no second line.
    """

    static func prompt(host: String, caution: String) -> String {
        """
        THE SITE: \(host)
        THE CAUTION, AS THE APP RECORDED IT: \(caution)

        Answer with the one CAUTION line.
        """
    }

    /// Parses the polished caution, strictly, and only accepts it when it still
    /// means what the mechanical one meant. A shorter caution that drifted is a
    /// worse caution than a clumsy one that is true.
    static func parseCaution(_ raw: String, original: Draft) -> String? {
        let line = raw
            .split(separator: "\n")
            .map { String($0).trimmed }
            .first { $0.lowercased().hasPrefix("caution:") }
        guard let line else { return nil }

        let text = String(line.dropFirst("caution:".count)).trimmed
        guard !text.isEmpty, text.count <= 120, text.count >= 8 else { return nil }
        guard !text.contains("\n") else { return nil }

        // A named control has to survive the rewrite, or the caution is about
        // something else now.
        if let subject = original.subject, !subject.isEmpty {
            guard text.localizedCaseInsensitiveContains(subject) else { return nil }
        }
        return text
    }
}
