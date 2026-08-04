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
        if inputs.read.isIrreversible {
            return Route(choice: .precise, reason: "an irreversible move is on screen", isForced: true)
        }
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

    /// Where the step goes when the free tier is not used, or when its answer is
    /// rejected. Never returns the on-device tier.
    static func cloudRoute(_ inputs: Inputs) -> Route {
        var withoutFreeTier = inputs
        withoutFreeTier.onDeviceReady = false
        return route(withoutFreeTier)
    }
}
