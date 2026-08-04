import Foundation

/// How steps are routed between models. Auto sends easy steps to the cheap model
/// while keeping every decision that matters on the frontier one.
nonisolated enum ModelStrategy: String, Codable, CaseIterable, Identifiable {
    case auto
    case alwaysPrecise
    case alwaysFast

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .alwaysPrecise: "Always precise"
        case .alwaysFast: "Always fast"
        }
    }

    var caption: String {
        switch self {
        case .auto: "Routine steps go to the fast model. Hard steps, the first step, irreversible moves, blind steps and retries always use the precise one."
        case .alwaysPrecise: "Every step uses the precise model, including scrolls and waits."
        case .alwaysFast: "Every step uses the fast model. Cheapest, and least reliable on hard pages."
        }
    }
}
