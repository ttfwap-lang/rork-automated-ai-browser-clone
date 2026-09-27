import Foundation

/// Decides which model gets each step. Routine steps go to the fast model; every
/// decision that actually matters stays on the frontier one.
nonisolated enum ModelRouter {

    nonisolated struct Route: Hashable {
        let choice: ModelChoice
        /// Plain reason, shown on the step card.
        let reason: String
        /// True when a rule forced the frontier model regardless of the read.
        let isForced: Bool
    }

    nonisolated struct Inputs {
        let strategy: ModelStrategy
        /// The user's model preference, used for normal steps under Auto.
        let preferred: ModelChoice
        let read: DifficultyRead
        let isFirstStep: Bool
        /// True when the previous attempt failed or the verifier pushed back —
        /// a step is never retried twice on the cheap model.
        let mustEscalate: Bool
        /// True when this iPhone's own free model is switched on and ready. It
        /// gets first refusal on routine steps only, and never on a step any
        /// forced-frontier rule claims.
        var onDeviceReady: Bool

        init(
            strategy: ModelStrategy,
            preferred: ModelChoice,
            read: DifficultyRead,
            isFirstStep: Bool,
            mustEscalate: Bool,
            onDeviceReady: Bool = false
        ) {
            self.strategy = strategy
            self.preferred = preferred
            self.read = read
            self.isFirstStep = isFirstStep
            self.mustEscalate = mustEscalate
            self.onDeviceReady = onDeviceReady
        }
    }

    static func route(_ inputs: Inputs) -> Route {
        switch inputs.strategy {
        case .alwaysPrecise:
            return Route(choice: .precise, reason: "always precise", isForced: false)
        case .alwaysFast:
            return Route(choice: .fast, reason: "always fast", isForced: false)
        case .auto:
            break
        }

        if inputs.isFirstStep {
            return Route(choice: .precise, reason: "first step of the mission", isForced: true)
        }
        if inputs.read.isFlyingBlind {
            return Route(choice: .precise, reason: "no page scan — flying on vision alone", isForced: true)
        }
        // An irreversible control merely being on screen is not a reason to pay
        // for the frontier model — most shop and form pages have one. The loop
        // checks the move actually chosen and re-decides it on the precise model
        // when that move commits (`escalationForCommittingMove`).
        if inputs.mustEscalate {
            return Route(choice: .precise, reason: "escalated after the last step failed", isForced: true)
        }

        switch inputs.read.difficulty {
        case .hard:
            return Route(choice: .precise, reason: "hard step", isForced: true)
        case .routine:
            if inputs.onDeviceReady {
                return Route(choice: .onDevice, reason: "routine step — free, on your iPhone", isForced: false)
            }
            return Route(choice: .fast, reason: "routine step", isForced: false)
        case .normal:
            return Route(choice: inputs.preferred, reason: "normal step — your preference", isForced: false)
        }
    }

    /// When a cheaper model chose a move that commits — buys, sends, deletes,
    /// submits — that one decision is taken again on the precise model. The
    /// route to re-decide on, or nil when the move is fine as it stands.
    static func escalationForCommittingMove(
        _ action: AgentAction,
        decidedOn choice: ModelChoice,
        strategy: ModelStrategy,
        in observation: PageObservation?
    ) -> Route? {
        guard strategy == .auto, choice != .precise else { return nil }
        guard isCommitting(action, in: observation) else { return nil }
        return Route(choice: .precise, reason: "the chosen move commits — double-checked on the precise model", isForced: true)
    }

    /// True for a move that cannot be taken back: pressing a control whose
    /// name reads as a commitment, or any submit/Enter outside a search box.
    static func isCommitting(_ action: AgentAction, in observation: PageObservation?) -> Bool {
        if let moves = action.moves, !moves.isEmpty {
            return moves.contains { isCommitting($0, in: observation) }
        }
        var names: [String] = []
        if let name = action.elementName { names.append(name) }
        for id in [action.element, action.from, action.to].compactMap({ $0 }) {
            if let element = observation?.element(withID: id) { names.append(element.name) }
        }
        if let option = action.option { names.append(option) }
        if names.contains(where: OnDeviceGate.isIrreversible) { return true }
        if action.kind == .fillForm, action.submit == true { return true }
        if action.submit == true {
            let field = action.element.flatMap { observation?.element(withID: $0) }
            return !RecipeDistiller.isSearchLike(field?.name)
        }
        return false
    }

    /// Where the step goes when the free tier is not used, or when its answer is
    /// rejected. Never returns the on-device tier.
    static func cloudRoute(_ inputs: Inputs) -> Route {
        var withoutFreeTier = inputs
        withoutFreeTier.onDeviceReady = false
        return route(withoutFreeTier)
    }
}
