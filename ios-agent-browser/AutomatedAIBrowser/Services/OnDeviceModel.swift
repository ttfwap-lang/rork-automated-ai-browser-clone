import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// This iPhone's own free, private AI — Apple's on-device foundation model.
///
/// Everything here is deliberately defensive. The framework only exists on
/// iOS 26 and later, the model only exists on some devices, it can be switched
/// off mid-run, and it can refuse a request outright. No entry point throws into
/// the run loop: callers get an honest answer or an honest refusal and fall back
/// to the cloud.
@Observable
final class OnDeviceModel {
    /// Longest a free answer may take before the cloud takes the step over. The
    /// on-device model is small, and a slow answer costs the user the very time
    /// it was supposed to save.
    static let timeout: Duration = .seconds(6)

    private(set) var state: OnDeviceState

    /// The framework handles one request per session at a time, and asking twice
    /// at once is a runtime error rather than a recoverable one.
    private var isBusy = false
    /// Holds the warmed-up session so the first answer of a run is instant.
    private var warmSession: Any?

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
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession()
            session.prewarm()
            warmSession = session
        }
        #endif
    }

    /// Releases the warmed model at the end of a run.
    func coolDown() {
        warmSession = nil
    }

    /// Asks for one short answer, one request at a time. Never throws.
    func ask(instructions: String, prompt: String) async -> OnDeviceAnswer {
        refresh()
        guard state.isReady else { return .unavailable(state) }
        guard !isBusy else { return .failed("your iPhone's model was already busy") }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            isBusy = true
            defer { isBusy = false }
            return await respond(instructions: instructions, prompt: prompt)
        }
        return .unavailable(.notEligible)
        #else
        return .unavailable(.notEligible)
        #endif
    }

    // MARK: - The framework, walled off behind availability

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func respond(instructions: String, prompt: String) async -> OnDeviceAnswer {
        // A fresh session per ask: our requests are one-shot and independent, so
        // a shared transcript would only leak stale context and eat the window.
        let session = LanguageModelSession(instructions: instructions)
        let work = Task { try await session.respond(to: prompt).content }
        let watchdog = Task {
            try? await Task.sleep(for: Self.timeout)
            work.cancel()
        }
        defer { watchdog.cancel() }

        do {
            let answer = try await work.value.trimmed
            return answer.isEmpty ? .failed("your iPhone's model returned nothing") : .answered(answer)
        } catch is CancellationError {
            return .timedOut
        } catch {
            return Self.classify(error)
        }
    }
    #endif

    /// Reads availability, collapsing the framework's reasons into our four
    /// honest states.
    static func currentState() -> OnDeviceState {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return .notEligible }
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
        #else
        return .notEligible
        #endif
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
