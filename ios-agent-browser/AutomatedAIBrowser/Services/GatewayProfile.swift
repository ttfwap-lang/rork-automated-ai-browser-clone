import Foundation

/// What the AI gateway between this app and the model providers actually
/// passes through, as measured by the probe in Settings — never assumed.
///
/// The app talks to Claude and Gemini through the Rork proxy and an
/// OpenAI-compatible gateway, and whether that gateway forwards a thinking
/// effort or a cache marker to the provider cannot be known from here. Until
/// the probe has run, nothing optional is sent: the request is exactly what
/// the app always sent, minus the temperature Claude Sonnet 5 rejects.
nonisolated struct GatewayProfile: Codable, Equatable, Sendable {

    /// How a thinking-effort level reaches the provider, if at all.
    nonisolated enum EffortStyle: String, Codable, Sendable {
        case none
        /// `"reasoning": {"effort": "low"}`
        case reasoningObject
        /// `"reasoning_effort": "low"`
        case reasoningEffort
    }

    /// How prompt caching is requested, if at all.
    nonisolated enum CacheStyle: String, Codable, Sendable {
        case none
        /// A `cache_control` marker on the system prompt's text part.
        case contentPart
    }

    var probedAt: Date?
    var effortStyle: EffortStyle = .none
    var cacheStyle: CacheStyle = .none
    /// Recorded for the report only: temperature is never sent to Claude.
    var claudeAcceptsTemperature: Bool = false

    private static let key = "gateway.profile"

    /// The saved profile, or the do-nothing default when the probe never ran.
    static var current: GatewayProfile {
        guard let data = UserDefaults.standard.data(forKey: key),
              let profile = try? JSONDecoder().decode(GatewayProfile.self, from: data)
        else { return GatewayProfile() }
        return profile
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    /// One line for Settings.
    var summary: String {
        guard let probedAt else { return "Not tested yet — optional request fields are off." }
        let when = probedAt.formatted(date: .abbreviated, time: .shortened)
        let effort = effortStyle == .none ? "no" : "yes"
        let cache = cacheStyle == .none ? "no" : "yes"
        return "Tested \(when) · thinking effort: \(effort) · prompt caching: \(cache)"
    }
}
