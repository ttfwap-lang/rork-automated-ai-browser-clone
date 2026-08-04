import Foundation

/// The contract every free answer has to pass before it is allowed to touch the
/// page.
///
/// The on-device model is small, so nothing it produces is trusted on faith. The
/// move has to be one of the few it is allowed to make, the element it names has
/// to actually exist on the live page, be reachable, and be the kind of thing it
/// claims. Anything else is rejected and the step is silently re-run in the
/// cloud — the user loses a moment, never a step, and no bad move ever lands.
nonisolated enum OnDeviceGate {

    nonisolated enum Ruling: Equatable {
        /// Cleared to run, normalized to safe parameters.
        case allowed(AgentAction)
        /// Rejected, with the reason recorded on the step.
        case rejected(String)

        var action: AgentAction? {
            if case .allowed(let action) = self { return action }
            return nil
        }

        var isAllowed: Bool {
            if case .allowed = self { return true }
            return false
        }
    }

    /// The entire move set the free tier may use. Deliberately tiny: everything
    /// here is cheap to get wrong and easy to undo.
    static let allowedKinds: Set<AgentActionKind> = [.scroll, .wait, .back, .tapElement]

    /// Names that mark a button as a cookie wall or dialog dismissal — the one
    /// class of tap the free tier is explicitly meant to handle.
    static let dismissalWords = [
        "accept", "agree", "got it", "ok", "okay", "allow", "dismiss", "close",
        "continue", "understood", "reject all", "decline", "no thanks", "maybe later",
    ]

    /// Widest scroll the free tier may ask for, in CSS pixels.
    private static let maxScrollAmount: Double = 2_000
    private static let minScrollAmount: Double = 100

    /// Reviews one proposed free move against the live page.
    static func review(_ action: AgentAction, against observation: PageObservation?) -> Ruling {
        guard allowedKinds.contains(action.kind) else {
            return .rejected("\(action.kind.label.lowercased()) is not a move your iPhone's model may make")
        }

        switch action.kind {
        case .wait:
            return .allowed(AgentAction(type: AgentActionKind.wait.rawValue))

        case .back:
            return .allowed(AgentAction(type: AgentActionKind.back.rawValue))

        case .scroll:
            let direction = (action.direction ?? "down").lowercased()
            guard direction == "down" || direction == "up" else {
                return .rejected("your iPhone's model asked to scroll \"\(direction)\", which is not a direction")
            }
            var scroll = AgentAction(type: AgentActionKind.scroll.rawValue)
            scroll.direction = direction
            scroll.amount = min(max(action.amount ?? 600, minScrollAmount), maxScrollAmount)
            return .allowed(scroll)

        case .tapElement:
            return reviewTap(action, against: observation)

        default:
            return .rejected("\(action.kind.label.lowercased()) is not a move your iPhone's model may make")
        }
    }

    /// A tap has to name a real, reachable, clearly-labelled, reversible target.
    private static func reviewTap(_ action: AgentAction, against observation: PageObservation?) -> Ruling {
        guard let observation else {
            return .rejected("the page scan is unavailable, so a free tap cannot be checked")
        }
        guard let id = action.element else {
            return .rejected("your iPhone's model asked for a tap without saying which element")
        }
        guard let element = observation.element(withID: id) else {
            return .rejected("element \(id) is not on this page")
        }
        guard element.kind == .button || element.kind == .link else {
            return .rejected("element \(id) is a \(element.kind.rawValue), not a button your iPhone's model may press")
        }
        guard !element.name.trimmed.isEmpty else {
            return .rejected("element \(id) has no visible label, so a free tap cannot be certain of it")
        }
        guard isReachable(element, in: observation) else {
            return .rejected("element \(id) is not reachable on screen")
        }
        guard !isIrreversible(element.name) else {
            return .rejected("element \(id) (\(element.shortDescriptor)) looks irreversible — that decision is never free")
        }

        var tap = AgentAction(type: AgentActionKind.tapElement.rawValue)
        tap.element = id
        tap.elementName = element.shortDescriptor
        return .allowed(tap)
    }

    /// On screen, with real size, inside the viewport it was measured against.
    static func isReachable(_ element: ScannedElement, in observation: PageObservation) -> Bool {
        guard element.width > 0, element.height > 0 else { return false }
        let centerX = element.x + element.width / 2
        let centerY = element.y + element.height / 2
        let slack = 2.0
        return centerX >= -slack
            && centerY >= -slack
            && centerX <= observation.viewportWidth + slack
            && centerY <= observation.viewportHeight + slack
    }

    /// Anything that buys, sends, deletes or confirms stays with the frontier
    /// model, exactly as the routing rules already decided.
    static func isIrreversible(_ name: String) -> Bool {
        let lower = name.lowercased()
        return DifficultyScout.irreversibleWords.contains { lower.contains($0) }
    }

    /// True when a button reads like a cookie wall or dialog dismissal.
    static func isDismissal(_ name: String) -> Bool {
        let lower = name.trimmed.lowercased()
        guard !lower.isEmpty else { return false }
        return dismissalWords.contains { lower == $0 || lower.hasPrefix($0 + " ") || lower.contains($0) }
    }
}
