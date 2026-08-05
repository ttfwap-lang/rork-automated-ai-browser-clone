import Foundation

/// One move of a proven route, described so it can be found again later.
///
/// Typed values are deliberately absent. A move remembers "the field named
/// Search" and that something goes there — never what was typed into it. The
/// user's data cannot leak through a memory, by construction rather than by
/// policy.
nonisolated struct RecipeMove: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    /// The move, as an action kind's raw value.
    let action: String
    /// How to find the target again; nil for moves with no target.
    let target: ElementFingerprint?
    /// What the page did last time, so a replay can tell whether it still holds.
    let expectedReaction: String?
    /// True when this move submits, buys, sends or deletes. Never replayed.
    let isCommitting: Bool
    /// For typing moves: what kind of thing belongs here, never the value itself.
    let valueKind: String?
    /// True when this move pressed Enter afterwards. Optional so routes saved by
    /// earlier builds keep decoding.
    let submits: Bool?
    /// For scrolls.
    let direction: String?
    let amount: Double?
    /// A remembered address, stored only when it carries no query of its own.
    let urlString: String?

    init(
        id: UUID = UUID(),
        action: String,
        target: ElementFingerprint? = nil,
        expectedReaction: String? = nil,
        isCommitting: Bool = false,
        valueKind: String? = nil,
        submits: Bool? = nil,
        direction: String? = nil,
        amount: Double? = nil,
        urlString: String? = nil
    ) {
        self.id = id
        self.action = action
        self.target = target
        self.expectedReaction = expectedReaction
        self.isCommitting = isCommitting
        self.valueKind = valueKind
        self.submits = submits
        self.direction = direction
        self.amount = amount
        self.urlString = urlString
    }

    var kind: AgentActionKind { AgentActionKind(rawValue: action) ?? .unknown }

    /// True when this move may be replayed without asking the AI to decide it.
    ///
    /// A memory can save the setup; it never makes the commitment. Nothing that
    /// submits, buys, sends or deletes qualifies, and neither does anything that
    /// would need a value remembered from an earlier run.
    var isSafeToReplay: Bool {
        guard !isCommitting else { return false }
        switch kind {
        case .wait, .back:
            return true
        case .scroll:
            let direction = (direction ?? "down").lowercased()
            return direction == "down" || direction == "up"
        case .tapElement:
            return !(target?.name.trimmed.isEmpty ?? true)
        case .navigate:
            // A bare route is a route. A URL carrying a query is carrying
            // something somebody typed, and remembered values are never replayed.
            guard let urlString, let url = URL(string: urlString) else { return false }
            let hasQuery = !(url.query ?? "").isEmpty
            let hasFragment = !(url.fragment ?? "").isEmpty
            return !hasQuery && !hasFragment
        default:
            return false
        }
    }

    /// True when a saved one-tap replay may run this move unattended.
    ///
    /// Wider than `isSafeToReplay` in exactly one way: typing is allowed, because
    /// a routine's values come from the blank you filled in at launch rather than
    /// from anything remembered. Anything that commits is still excluded — those
    /// stop for a yes instead.
    var isReplayableInRoutine: Bool {
        guard !isCommitting else { return false }
        switch kind {
        case .wait, .back, .scroll, .navigate, .tapElement:
            return isSafeToReplay
        case .typeInto, .selectOption:
            return !(target?.name.trimmed.isEmpty ?? true)
        default:
            return false
        }
    }

    /// The same move, pointing at where the control actually is now.
    ///
    /// Everything except the target is carried across untouched — including
    /// `submits`. Losing that one flag would be the nastiest bug in the repair
    /// path: the repaired step would find the search box, type into it, and
    /// silently never press Enter, so the repair would look like a success while
    /// the search never ran.
    func retargeted(to target: ElementFingerprint) -> RecipeMove {
        RecipeMove(
            id: id,
            action: action,
            target: target,
            expectedReaction: expectedReaction,
            isCommitting: isCommitting,
            valueKind: valueKind,
            submits: submits,
            direction: direction,
            amount: amount,
            urlString: urlString
        )
    }

    /// True when a saved one-tap replay can actually PERFORM this move — either
    /// unattended, or by stopping for a yes first.
    ///
    /// This is the rule for what may be written into a routine at all. Without
    /// it a run could be saved as a replay that stops dead half way through with
    /// “this step needs something a saved replay never stores”, which is a
    /// promise broken at the worst possible moment. A move that cannot be
    /// performed is refused at save time instead.
    var isSavableInRoutine: Bool {
        guard isCommitting else { return isReplayableInRoutine }
        // Committing moves are allowed in a routine — they stop and ask you — but
        // only the kinds a replay knows how to run at all.
        switch kind {
        case .tapElement, .typeInto, .selectOption:
            return !(target?.name.trimmed.isEmpty ?? true)
        default:
            return false
        }
    }

    /// One line of the route in plain language, for the Memory screen.
    var plainLine: String {
        switch kind {
        case .tapElement:
            let name = target?.name ?? ""
            let kindWord = target?.kind.rawValue ?? "control"
            return name.isEmpty ? "tap a \(kindWord)" : "tap the \(kindWord) “\(name)”"
        case .typeInto, .typeText:
            let name = target?.name ?? ""
            let what = valueKind ?? "what you're looking for"
            return name.isEmpty ? "type \(what)" : "type \(what) into “\(name)”"
        case .fillForm:
            return "fill in the form"
        case .selectOption:
            let name = target?.name ?? "a dropdown"
            return "choose from “\(name)”"
        case .setToggle:
            return "flip “\(target?.name ?? "a switch")”"
        case .setSlider:
            return "set “\(target?.name ?? "a slider")”"
        case .scroll:
            return "scroll \(direction ?? "down")"
        case .navigate:
            return "open \(RecipeMove.shortAddress(urlString ?? ""))"
        case .back:
            return "go back"
        case .wait:
            return "wait for the page"
        case .extract:
            return "read the page"
        case .pageOverview:
            return "look at the whole page"
        default:
            return kind.label.lowercased()
        }
    }

    /// `site.com/deals` from a full address.
    static func shortAddress(_ urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else {
            return String(urlString.prefix(40))
        }
        let trimmedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = url.path == "/" ? "" : url.path
        return String((trimmedHost + path).prefix(48))
    }
}
