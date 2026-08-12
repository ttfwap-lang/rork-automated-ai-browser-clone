import Foundation
import FoundationModels
import Observation

/// This iPhone's own free, private AI — Apple's on-device foundation model.
///
/// The app's minimum is iOS 26, so the framework is always present and imported
/// plainly. What is still not guaranteed is the *model*: it exists only on some
/// devices, Apple Intelligence can be switched off mid-run, and the model can
/// refuse a request outright. So availability is re-read constantly and no entry
/// point throws into the run loop — callers get an honest answer or an honest
/// refusal and fall back to the cloud.
///
/// Two ways to ask:
/// - `ask(instructions:prompt:)` returns prose, for jobs whose answer is prose.
/// - `ask(instructions:prompt:generating:)` returns a real Swift value via guided
///   generation. The framework constrains sampling to the shape of the type, so a
///   malformed answer is not a case that has to be handled — it cannot be
///   produced. Every job with a structured answer uses this one.
@Observable
final class OnDeviceModel {
    /// Longest a free prose answer may take before the cloud takes the step over.
    /// The on-device model is small, and a slow answer costs the user the very
    /// time it was supposed to save.
    static let timeout: Duration = .seconds(6)

    /// Guided generation has to satisfy a schema as well as answer, so it gets a
    /// slightly longer leash before the cloud takes over.
    static let guidedTimeout: Duration = .seconds(9)

    private(set) var state: OnDeviceState

    /// The framework handles one request per session at a time, and asking twice
    /// at once is a runtime error rather than a recoverable one.
    private var isBusy = false
    /// Holds the warmed-up session so the first answer of a run is instant.
    private var warmSession: LanguageModelSession?

    init() {
        state = Self.currentState()
    }

    /// True when the free tier may be offered at all.
    var isReady: Bool { state.isReady }

    /// Re-reads availability. Cheap, and iOS can change its answer at any moment
    /// — Apple Intelligence can be switched off in the middle of a run.
    func refresh() {
        state = Self.currentState()
    }

    /// Loads the model into memory so the first free answer of a run is instant
    /// rather than sluggish. Safe to call when unavailable: it does nothing.
    func warmUp() {
        refresh()
        guard state.isReady else {
            warmSession = nil
            return
        }
        let session = LanguageModelSession()
        session.prewarm()
        warmSession = session
    }

    /// Releases the warmed model at the end of a run.
    func coolDown() {
        warmSession = nil
    }

    // MARK: - Prose

    /// Asks for one short prose answer, one request at a time. Never throws.
    func ask(instructions: String, prompt: String) async -> OnDeviceAnswer {
        refresh()
        guard state.isReady else { return .unavailable(state) }
        guard !isBusy else { return .failed("your iPhone's model was already busy") }
        isBusy = true
        defer { isBusy = false }

        // A fresh session per ask: our requests are one-shot and independent, so
        // a shared transcript would only leak stale context and eat the window.
        let session = LanguageModelSession(instructions: instructions)
        let work = Task { try await session.respond(to: prompt).content }

        switch await Self.race(work, budget: Self.timeout) {
        case .success(let answer):
            let text = answer.trimmed
            return text.isEmpty ? .failed("your iPhone's model returned nothing") : .answered(text)
        case .timedOut:
            return .timedOut
        case .failure(let error):
            return Self.classify(error)
        }
    }

    // MARK: - Guided generation

    /// Asks for a real Swift value rather than text to parse.
    ///
    /// The framework constrains what the model may emit to the shape of `Value`,
    /// so there is no malformed-output path to defend against and no string
    /// parsing to get wrong. Where `Value` contains an enumeration, the model
    /// physically cannot name a case that does not exist.
    func ask<Value>(
        instructions: String,
        prompt: String,
        generating type: Value.Type
    ) async -> OnDeviceTyped<Value> where Value: Generable & Sendable {
        refresh()
        guard state.isReady else { return .declined(.unavailable(state)) }
        guard !isBusy else { return .declined(.failed("your iPhone's model was already busy")) }
        isBusy = true
        defer { isBusy = false }

        let session = LanguageModelSession(instructions: instructions)
        let work = Task { try await session.respond(to: prompt, generating: type).content }

        switch await Self.race(work, budget: Self.guidedTimeout) {
        case .success(let value):
            return .answered(value)
        case .timedOut:
            return .declined(.timedOut)
        case .failure(let error):
            return .declined(Self.classify(error))
        }
    }

    // MARK: - Racing a request against its budget

    private enum Race<Value> {
        case success(Value)
        case timedOut
        case failure(Error)
    }

    /// Runs `work` against a wall-clock budget, cancelling it if the budget goes.
    /// Kept in one place so prose and guided asks time out identically.
    private static func race<Value>(
        _ work: Task<Value, Error>,
        budget: Duration
    ) async -> Race<Value> where Value: Sendable {
        let watchdog = Task {
            try? await Task.sleep(for: budget)
            work.cancel()
        }
        defer { watchdog.cancel() }

        do {
            return .success(try await work.value)
        } catch is CancellationError {
            return .timedOut
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Availability

    /// Reads availability, collapsing the framework's reasons into our four
    /// honest states.
    static func currentState() -> OnDeviceState {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .notEligible
            case .appleIntelligenceNotEnabled: return .notEnabled
            case .modelNotReady: return .downloading
            @unknown default: return .unavailable
            }
        @unknown default:
            return .unavailable
        }
    }

    /// Sorts a framework error into an outcome the run loop can act on.
    ///
    /// Deliberately matched on the error's description rather than on concrete
    /// case names: the exact cases have shifted between iOS releases, and a
    /// missing case name here would be a build failure on a feature whose whole
    /// promise is that it degrades quietly.
    nonisolated static func classify(_ error: Error) -> OnDeviceAnswer {
        let text = String(describing: error).lowercased()
        if text.contains("guardrail") || text.contains("safety") || text.contains("unsafe") {
            return .refused("your iPhone's model declined this one on safety grounds")
        }
        if text.contains("context") {
            return .failed("the request was too long for your iPhone's model")
        }
        if text.contains("notready") || text.contains("not ready") || text.contains("downloading") {
            return .unavailable(.downloading)
        }
        if text.contains("assetsunavailable") || text.contains("unavailable") {
            return .unavailable(.unavailable)
        }
        if text.contains("language") || text.contains("locale") {
            return .failed("your iPhone's model doesn't support this language")
        }
        if text.contains("ratelimit") || text.contains("rate limit") {
            return .failed("your iPhone's model is rate limited right now")
        }
        return .failed("your iPhone's model couldn't answer")
    }
}
