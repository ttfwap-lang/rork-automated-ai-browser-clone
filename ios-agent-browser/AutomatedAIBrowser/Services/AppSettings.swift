import Foundation
import Observation

/// User preferences persisted in UserDefaults.
@Observable
final class AppSettings {
    var defaultMode: AgentMode {
        didSet { UserDefaults.standard.set(defaultMode.rawValue, forKey: Keys.mode) }
    }

    var maxSteps: Int {
        didSet { UserDefaults.standard.set(maxSteps, forKey: Keys.maxSteps) }
    }

    var model: ModelChoice {
        didSet { UserDefaults.standard.set(model.rawValue, forKey: Keys.model) }
    }

    /// Which model writes the mission plan, or whether planning runs at all.
    var planning: PlanningPreference {
        didSet { UserDefaults.standard.set(planning.rawValue, forKey: Keys.planning) }
    }

    /// Require an independent check before any run can be called complete.
    var verifyBeforeDone: Bool {
        didSet { UserDefaults.standard.set(verifyBeforeDone, forKey: Keys.verify) }
    }

    /// Run the check on the model the steps are NOT using, so reviewer and doer
    /// don't share a blind spot.
    var crossCheckWithOtherModel: Bool {
        didSet { UserDefaults.standard.set(crossCheckWithOtherModel, forKey: Keys.crossCheck) }
    }

    /// How steps are routed between the fast and precise models.
    var modelStrategy: ModelStrategy {
        didSet { UserDefaults.standard.set(modelStrategy.rawValue, forKey: Keys.strategy) }
    }

    /// Ask for a shortlist of moves on hard steps instead of a single guess.
    var weighAlternatives: Bool {
        didSet { UserDefaults.standard.set(weighAlternatives, forKey: Keys.weigh) }
    }

    /// Capture page checkpoints so the agent can rewind out of dead ends.
    var bookmarksEnabled: Bool {
        didSet { UserDefaults.standard.set(bookmarksEnabled, forKey: Keys.bookmarks) }
    }

    /// Offer routine steps to this iPhone's own free model first. Off restores
    /// exactly the cloud-only behavior.
    var onDeviceFirst: Bool {
        didSet { UserDefaults.standard.set(onDeviceFirst, forKey: Keys.onDevice) }
    }

    /// Remember the route that worked on a site after a confirmed success.
    var memoryEnabled: Bool {
        didSet { UserDefaults.standard.set(memoryEnabled, forKey: Keys.memory) }
    }

    /// Replay the opening moves of a proven route without paying for decisions.
    var headStartEnabled: Bool {
        didSet { UserDefaults.standard.set(headStartEnabled, forKey: Keys.headStart) }
    }

    /// Learn from failures on a site and carry the cautions into later runs.
    var lessonsEnabled: Bool {
        didSet { UserDefaults.standard.set(lessonsEnabled, forKey: Keys.lessons) }
    }

    /// Let a saved one-tap replay repair a step the site has moved instead of
    /// giving up. Off makes replays strict: any mismatch hands over to the agent.
    var selfHealEnabled: Bool {
        didSet { UserDefaults.standard.set(selfHealEnabled, forKey: Keys.selfHeal) }
    }

    let homepage = "https://duckduckgo.com"

    private enum Keys {
        static let mode = "settings.defaultMode"
        static let maxSteps = "settings.maxSteps"
        static let model = "settings.model"
        static let planning = "settings.planning"
        static let verify = "settings.verifyBeforeDone"
        static let crossCheck = "settings.crossCheckModel"
        static let strategy = "settings.modelStrategy"
        static let weigh = "settings.weighAlternatives"
        static let bookmarks = "settings.bookmarksEnabled"
        static let onDevice = "settings.onDeviceFirst"
        static let memory = "settings.memoryEnabled"
        static let headStart = "settings.headStartEnabled"
        static let lessons = "settings.lessonsEnabled"
        static let selfHeal = "settings.selfHealEnabled"
    }

    init() {
        let defaults = UserDefaults.standard
        defaultMode = AgentMode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .autopilot
        let storedSteps = defaults.integer(forKey: Keys.maxSteps)
        maxSteps = storedSteps == 0 ? 12 : min(max(storedSteps, 5), 25)
        model = ModelChoice(rawValue: defaults.string(forKey: Keys.model) ?? "") ?? .precise
        planning = PlanningPreference(rawValue: defaults.string(forKey: Keys.planning) ?? "") ?? .strong
        verifyBeforeDone = defaults.object(forKey: Keys.verify) as? Bool ?? true
        crossCheckWithOtherModel = defaults.object(forKey: Keys.crossCheck) as? Bool ?? false
        modelStrategy = ModelStrategy(rawValue: defaults.string(forKey: Keys.strategy) ?? "") ?? .auto
        weighAlternatives = defaults.object(forKey: Keys.weigh) as? Bool ?? true
        bookmarksEnabled = defaults.object(forKey: Keys.bookmarks) as? Bool ?? true
        onDeviceFirst = defaults.object(forKey: Keys.onDevice) as? Bool ?? true
        memoryEnabled = defaults.object(forKey: Keys.memory) as? Bool ?? true
        headStartEnabled = defaults.object(forKey: Keys.headStart) as? Bool ?? true
        lessonsEnabled = defaults.object(forKey: Keys.lessons) as? Bool ?? true
        selfHealEnabled = defaults.object(forKey: Keys.selfHeal) as? Bool ?? true
    }
}
