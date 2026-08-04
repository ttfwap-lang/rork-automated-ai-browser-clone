import Foundation

/// A model that can decide a step. Two of them are cloud models the user picks
/// between; the third is this iPhone's own, which is free and never selectable
/// as a "preferred model" because it is offered per-step, not per-run.
nonisolated enum ModelChoice: String, Codable, CaseIterable, Identifiable {
    case precise
    case fast
    /// Apple's on-device model. Costs nothing and never reaches the network.
    case onDevice

    var id: String { rawValue }

    /// The two cloud models the user chooses between in Settings.
    static let cloudCases: [ModelChoice] = [.precise, .fast]

    /// False for the on-device tier — it never reaches the gateway, and nothing
    /// it decides is paid for.
    var isCloud: Bool { self != .onDevice }

    /// Vercel AI Gateway model ID sent to the Rork proxy. The on-device tier
    /// never makes a gateway call; it reports the fast model's ID purely so a
    /// mis-wired caller degrades to the cheapest cloud model instead of crashing.
    var modelID: String {
        switch self {
        case .precise: "anthropic/claude-sonnet-5"
        case .fast: "google/gemini-3.5-flash"
        case .onDevice: "google/gemini-3.5-flash"
        }
    }

    var label: String {
        switch self {
        case .precise: "Precise — Claude Sonnet 5"
        case .fast: "Fast — Gemini 3.5 Flash"
        case .onDevice: "Free — on your iPhone"
        }
    }

    /// Chip text for step cards and telemetry.
    var shortLabel: String {
        switch self {
        case .precise: "PRECISE"
        case .fast: "FAST"
        case .onDevice: "FREE"
        }
    }

    var caption: String {
        switch self {
        case .precise: "Best at reading pages and aiming taps. Recommended."
        case .fast: "Quicker and cheaper per step, slightly less accurate."
        case .onDevice: "Runs on your iPhone. Costs nothing, works offline, and nothing leaves the device."
        }
    }
}
