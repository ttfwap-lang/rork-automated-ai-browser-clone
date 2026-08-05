import Foundation
import Observation
import Security

/// Your details, held on this device only.
///
/// Three promises are kept structurally rather than by good intentions:
///
/// 1. **The values never reach a model.** `value(for:)` exists for one caller —
///    the moment a matched field is typed into. Briefings, plans, memories,
///    lessons, saved replays and run history are all built from
///    `filledKinds`, which is a set of field *names* and holds no values at all.
/// 2. **Secrets cannot be stored.** `DossierFieldKind` has no case for a
///    password, a card number or a security code, so there is nothing to leak.
/// 3. **Reading it requires you.** The editor is sealed until `DossierGuard`
///    passes, and re-seals every time the app restarts.
@Observable
final class Dossier {

    /// Values keyed by field-kind raw value. Private: no view and no service can
    /// enumerate this.
    private var values: [String: String] = [:]

    /// True once you have proven who you are in this app session.
    private(set) var isUnlocked = false
    /// Why the last unlock attempt didn't pass, in plain words.
    private(set) var lockNote: String?
    /// Honest note about where the details ended up when the Keychain refused.
    private(set) var storageNote: String?
    /// True when the details are on disk under file protection rather than in the
    /// Keychain — same device, same protection class, worth stating plainly.
    private(set) var usesFileFallback = false

    private let keychainService: String
    private let keychainAccount = "dossier.v1"
    private let fallbackURL: URL

    init() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.rork.agentbrowser"
        keychainService = "\(bundleID).dossier"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fallbackURL = docs.appendingPathComponent("dossier.json")
        load()
    }

    // MARK: - What the rest of the app is allowed to know

    /// Which facts you have filled in. Names only — this is what briefings, the
    /// planner and the fill report are built from.
    var filledKinds: Set<DossierFieldKind> {
        Set(values.compactMap { key, value in
            value.trimmed.isEmpty ? nil : DossierFieldKind(rawValue: key)
        })
    }

    var isEmpty: Bool { filledKinds.isEmpty }

    var filledCount: Int { filledKinds.count }

    /// 0–1, for the progress ring in the editor.
    var completion: Double {
        Double(filledCount) / Double(DossierFieldKind.allCases.count)
    }

    /// True when there is enough here to be worth offering on a form. One lone
    /// fact would waste a move.
    var canHelpWithForms: Bool { filledCount >= 3 }

    /// Whether a specific fact exists — without revealing it.
    func has(_ kind: DossierFieldKind) -> Bool {
        !(values[kind.rawValue] ?? "").trimmed.isEmpty
    }

    /// The one caller that legitimately needs a value: typing it into the page.
    /// Never route this into a prompt, a log line or a stored run.
    func value(for kind: DossierFieldKind) -> String? {
        let value = (values[kind.rawValue] ?? "").trimmed
        return value.isEmpty ? nil : value
    }

    /// What the editor shows while sealed: the shape of the answer, not the answer.
    func masked(_ kind: DossierFieldKind) -> String {
        guard let value = value(for: kind) else { return "" }
        return String(repeating: "\u{2022}", count: min(max(value.count, 4), 12))
    }

    /// The facts available, as the agent is told about them: a plain list of
    /// names, capped so a long dossier cannot bloat a briefing.
    func availableFactNames(limit: Int = 40) -> [String] {
        DossierFieldKind.allCases
            .filter { has($0) }
            .prefix(limit)
            .map(\.briefingName)
    }

    // MARK: - Editing (only meaningful once unlocked)

    /// Reads a value back for editing. Sealed until you have unlocked.
    func editableValue(for kind: DossierFieldKind) -> String {
        guard isUnlocked else { return "" }
        return values[kind.rawValue] ?? ""
    }

    func set(_ raw: String, for kind: DossierFieldKind) {
        guard isUnlocked else { return }
        let clean = String(raw.prefix(kind.isLongForm ? 1_200 : 200))
        if clean.trimmed.isEmpty {
            values.removeValue(forKey: kind.rawValue)
        } else {
            values[kind.rawValue] = clean
        }
        save()
    }

    func clear(_ kind: DossierFieldKind) {
        guard isUnlocked else { return }
        values.removeValue(forKey: kind.rawValue)
        save()
    }

    /// Deletes everything, everywhere. Available whether or not you unlocked —
    /// being unable to delete your own data would be the wrong kind of lock.
    func wipe() {
        values = [:]
        var query = baseQuery()
        query[kSecMatchLimit as String] = nil
        SecItemDelete(query as CFDictionary)
        try? FileManager.default.removeItem(at: fallbackURL)
        usesFileFallback = false
        storageNote = nil
    }

    // MARK: - The lock

    /// Asks for Face ID, Touch ID or your passcode. Re-sealed on every launch.
    func unlock() async {
        guard !isUnlocked else { return }
        let outcome = await DossierGuard.unlock(reason: "Unlock your dossier so you can read and edit your details")
        switch outcome {
        case .unlocked:
            isUnlocked = true
            lockNote = nil
        case .refused(let note):
            isUnlocked = false
            lockNote = note
        case .unavailable(let note):
            // A device that genuinely cannot ask must not be left unable to use
            // the feature — but it is told exactly what protection it is missing.
            isUnlocked = true
            lockNote = note
        }
    }

    func seal() {
        isUnlocked = false
        lockNote = nil
    }

    // MARK: - Storage

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
    }

    private func load() {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            values = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
            return
        }

        // The Keychain can be unavailable to an app depending on how it was
        // signed. Falling back to a protected file keeps the data on the device
        // and says so, rather than silently losing everything the user typed.
        if let data = try? Data(contentsOf: fallbackURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            values = decoded
            usesFileFallback = true
            storageNote = "Stored in this app's private, encrypted storage on your iPhone."
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(values) else { return }

        if !usesFileFallback {
            var query = baseQuery()
            let attributes: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if updateStatus == errSecSuccess {
                storageNote = nil
                return
            }
            if updateStatus == errSecItemNotFound {
                query[kSecValueData as String] = data
                query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                if SecItemAdd(query as CFDictionary, nil) == errSecSuccess {
                    storageNote = nil
                    return
                }
            }
            usesFileFallback = true
            storageNote = "Stored in this app's private, encrypted storage on your iPhone."
        }

        writeFallback(data)
    }

    private func writeFallback(_ data: Data) {
        do {
            try data.write(to: fallbackURL, options: [.atomic, .completeFileProtection])
        } catch {
            storageNote = "Couldn't save your details to this iPhone. They will be lost when the app closes."
        }
    }
}
