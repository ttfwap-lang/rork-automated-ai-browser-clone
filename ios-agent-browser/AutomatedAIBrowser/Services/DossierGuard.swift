import Foundation
import LocalAuthentication

/// The Face ID gate in front of your own details.
///
/// The threat this actually defends against is someone holding your unlocked
/// phone: without this, tapping one button would show them your address, your
/// date of birth and your salary expectation. So reading or editing the dossier
/// requires your face, your fingerprint, or your passcode — every time the app
/// starts.
///
/// Nothing here ever throws into the UI: every path returns one of three honest
/// outcomes.
nonisolated enum DossierGuard {

    nonisolated enum Outcome: Equatable {
        case unlocked
        /// You cancelled, or the check did not pass.
        case refused(String)
        /// This device cannot ask — no passcode set, biometrics locked out.
        case unavailable(String)

        var isUnlocked: Bool { self == .unlocked }

        var note: String? {
            switch self {
            case .unlocked: nil
            case .refused(let text), .unavailable(let text): text
            }
        }
    }

    /// "Face ID", "Touch ID", "Optic ID", or "your passcode" when there is no
    /// biometric sensor to speak of.
    static func methodName() -> String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "your passcode"
        }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "your passcode"
        }
    }

    /// True when this device can ask for anything at all. A device with no
    /// passcode cannot, and pretending otherwise would leave the dossier
    /// unprotected while claiming it was locked.
    static func canAsk() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// Asks for your face, fingerprint or passcode. Biometrics first, with the
    /// passcode as the fallback the system offers itself.
    static func unlock(reason: String = "Unlock your dossier") async -> Outcome {
        let context = LAContext()
        context.localizedCancelTitle = "Not now"

        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            return .unavailable(describe(policyError))
        }

        do {
            let passed = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return passed ? .unlocked : .refused("\(methodName()) didn't pass — your details stay hidden.")
        } catch {
            return classify(error)
        }
    }

    /// Sorts an authentication failure into something a person can act on.
    static func classify(_ error: Error) -> Outcome {
        guard let code = (error as? LAError)?.code else {
            return .refused("\(methodName()) couldn't complete — your details stay hidden.")
        }
        switch code {
        case .userCancel, .appCancel, .systemCancel:
            return .refused("Cancelled — your details stay hidden.")
        case .authenticationFailed:
            return .refused("That didn't match. Try again when you're ready.")
        case .userFallback:
            return .refused("Cancelled — your details stay hidden.")
        case .passcodeNotSet:
            return .unavailable("This iPhone has no passcode set, so there is nothing to lock your details behind. Set a passcode in Settings first.")
        case .biometryNotAvailable:
            return .unavailable("\(methodName()) isn't available on this device — your passcode will be used instead.")
        case .biometryNotEnrolled:
            return .unavailable("\(methodName()) isn't set up yet, so your passcode will be used instead.")
        case .biometryLockout:
            return .unavailable("\(methodName()) is locked out after too many attempts. Lock and unlock your iPhone, then try again.")
        default:
            return .refused("\(methodName()) couldn't complete — your details stay hidden.")
        }
    }

    private static func describe(_ error: NSError?) -> String {
        guard let error, let code = LAError.Code(rawValue: error.code) else {
            return "This device can't ask for your identity, so the dossier can't be unlocked here."
        }
        return classify(LAError(code)).note
            ?? "This device can't ask for your identity, so the dossier can't be unlocked here."
    }
}
