import Foundation

/// Works out what each field on a form is asking for — for nothing.
///
/// Two free passes, in order of certainty:
///
/// 1. **Declared.** The field states its own purpose in the `autocomplete`
///    attribute. This is a web standard, most serious forms use it, and it needs
///    no guessing at all.
/// 2. **Label.** Matched from the field's own visible words against a fixed
///    phrase table, on word boundaries and longest phrase first, so "state"
///    cannot be found inside "estate" and "first name" always beats "name".
///
/// Whatever survives both passes is a genuine oddity, and only those go anywhere
/// near a model. On a fifty-field application that is usually a handful.
nonisolated enum FieldMatcher {

    /// A phrase has to be at least this long to be trusted on its own. Stops a
    /// two-letter coincidence from mapping a field to the wrong fact.
    private static let minPhraseLength = 3

    // MARK: - Pass 1 + 2, both free

    /// Resolves what it can and returns the leftovers untouched.
    static func match(_ probes: [FormFieldProbe]) -> (matches: [FieldMatch], leftovers: [FormFieldProbe]) {
        var matches: [FieldMatch] = []
        var leftovers: [FormFieldProbe] = []

        for probe in probes where probe.isWorthFilling {
            if let kind = declaredKind(for: probe) {
                matches.append(FieldMatch(probe: probe, kind: kind, source: .declared))
            } else if let kind = labelKind(for: probe) {
                matches.append(FieldMatch(probe: probe, kind: kind, source: .label))
            } else {
                leftovers.append(probe)
            }
        }

        return (dedupe(matches), leftovers)
    }

    /// Pass 1: the field told us itself.
    static func declaredKind(for probe: FormFieldProbe) -> DossierFieldKind? {
        let token = probe.declared
        guard !token.isEmpty else { return nil }
        for kind in DossierFieldKind.allCases where kind.declaredTokens.contains(token) {
            return kind
        }
        // `type="email"` and `type="tel"` are declarations in all but name.
        switch probe.type {
        case "email": return .email
        case "tel": return .phone
        default: return nil
        }
    }

    /// Pass 2: matched from its own words. Longest phrase wins, so a specific
    /// label always beats a generic one.
    static func labelKind(for probe: FormFieldProbe) -> DossierFieldKind? {
        let text = probe.matchText
        guard !text.isEmpty else { return nil }

        var best: (kind: DossierFieldKind, score: Int)?
        for kind in DossierFieldKind.allCases {
            for phrase in kind.phrases where phrase.count >= minPhraseLength {
                guard containsPhrase(text, phrase) else { continue }
                // Longer phrases are more specific, and a label that IS the phrase
                // is better evidence than one that merely contains it.
                var score = phrase.count
                if text == phrase { score += 40 }
                if let current = best, current.score >= score { continue }
                best = (kind, score)
            }
        }
        return best?.kind
    }

    /// Word-boundary containment. `"state"` matches `"State / Province"` and
    /// `"home_state"`, but never `"real estate"`.
    static func containsPhrase(_ haystack: String, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return false }
        let separators = CharacterSet.alphanumerics.inverted
        let words = haystack.components(separatedBy: separators).filter { !$0.isEmpty }
        let needleWords = needle.components(separatedBy: separators).filter { !$0.isEmpty }
        guard !needleWords.isEmpty, needleWords.count <= words.count else { return false }

        for start in 0...(words.count - needleWords.count) {
            var hit = true
            for offset in 0..<needleWords.count where words[start + offset] != needleWords[offset] {
                hit = false
                break
            }
            if hit { return true }
        }
        return false
    }

    /// A form can legitimately ask for the same fact twice (email and confirm
    /// email), and both should be filled. But when two *different* fields claim
    /// the same fact by weak evidence, the more certain one wins and the other
    /// goes back to being unknown rather than being filled with the wrong thing.
    ///
    /// Confirmation fields are recognised and kept.
    static func dedupe(_ matches: [FieldMatch]) -> [FieldMatch] {
        var byKind: [DossierFieldKind: [FieldMatch]] = [:]
        for match in matches {
            byKind[match.kind, default: []].append(match)
        }

        var kept: [FieldMatch] = []
        for (_, group) in byKind {
            guard group.count > 1 else {
                kept.append(contentsOf: group)
                continue
            }
            let confirmations = group.filter { isConfirmation($0.probe) }
            let primaries = group.filter { !isConfirmation($0.probe) }
            // Keep every confirmation — they genuinely want the same value.
            kept.append(contentsOf: confirmations)
            if primaries.count <= 1 {
                kept.append(contentsOf: primaries)
            } else if let strongest = primaries.first(where: { $0.source == .declared }) {
                kept.append(strongest)
            } else {
                // Two guesses at the same fact is not evidence, it is a coin toss.
                kept.append(contentsOf: primaries.prefix(1))
            }
        }
        return kept.sorted { $0.probe.id < $1.probe.id }
    }

    /// "Confirm email", "Repeat password", "Re-enter your email".
    static func isConfirmation(_ probe: FormFieldProbe) -> Bool {
        let text = probe.matchText
        return ["confirm", "confirmation", "repeat", "re enter", "re-enter", "reenter", "verify", "again"]
            .contains { containsPhrase(text, $0) || text.contains($0) }
    }

    // MARK: - The plan

    /// Sorts every probe into what will happen to it, given what the dossier
    /// actually holds. Nothing is invented: a matched field with no stored value
    /// is reported as blank, never filled with a plausible guess.
    static func plan(
        probes: [FormFieldProbe],
        matches: [FieldMatch],
        available: Set<DossierFieldKind>
    ) -> FillPlan {
        let matchedIDs = Set(matches.map(\.id))
        var ready: [FieldMatch] = []
        var missing: [FieldMatch] = []
        for match in matches.sorted(by: { $0.probe.id < $1.probe.id }) {
            if available.contains(match.kind) {
                ready.append(match)
            } else {
                missing.append(match)
            }
        }

        var unmatched: [FormFieldProbe] = []
        var sensitive: [FormFieldProbe] = []
        var alreadyFilled: [FormFieldProbe] = []
        var unsupported: [FormFieldProbe] = []

        for probe in probes where !matchedIDs.contains(probe.id) {
            if probe.isSensitive {
                sensitive.append(probe)
            } else if !probe.widget.isFillable {
                unsupported.append(probe)
            } else if !probe.isEmpty {
                alreadyFilled.append(probe)
            } else {
                unmatched.append(probe)
            }
        }

        return FillPlan(
            ready: ready,
            missing: missing,
            unmatched: unmatched,
            sensitive: sensitive,
            alreadyFilled: alreadyFilled,
            unsupported: unsupported
        )
    }
}
