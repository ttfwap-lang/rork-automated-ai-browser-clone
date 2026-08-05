import Foundation

/// Everything the matcher worked out about one form, before a single character is
/// typed.
///
/// The split matters more than the totals. A field that was matched but has no
/// stored value sits in `missing` and is left blank — the agent never invents a
/// fact that is not in your dossier. A field that could not be worked out sits in
/// `unmatched` and is handed back to the agent by name, which is the only part of
/// a long form that can ever cost a paid call.
nonisolated struct FillPlan: Equatable {
    /// Matched, with a value ready to type.
    let ready: [FieldMatch]
    /// Matched, but your dossier has nothing for it. Left blank, reported honestly.
    let missing: [FieldMatch]
    /// Could not be worked out. Handed back to the agent by name.
    let unmatched: [FormFieldProbe]
    /// Password, card, security-code and one-time-code fields. Never touched.
    let sensitive: [FormFieldProbe]
    /// Fields that already hold something — never overwritten.
    let alreadyFilled: [FormFieldProbe]
    /// Widgets no value can be written into yet (date pickers, checkboxes, choices).
    let unsupported: [FormFieldProbe]

    static let empty = FillPlan(
        ready: [], missing: [], unmatched: [], sensitive: [], alreadyFilled: [], unsupported: []
    )

    /// How many fields were resolved without spending anything.
    var freeMatchCount: Int { ready.count + missing.count }

    /// How many of those the site itself declared — the certain ones.
    var declaredCount: Int { (ready + missing).filter { $0.source == .declared }.count }

    /// How many your iPhone had to read the label for.
    var meaningCount: Int { (ready + missing).filter { $0.source == .meaning }.count }

    var isEmpty: Bool { ready.isEmpty && missing.isEmpty && unmatched.isEmpty }

    /// The values about to be typed, in page order. Held for the moment of the
    /// fill and never written anywhere else.
    func entries(from lookup: (DossierFieldKind) -> String?) -> [(match: FieldMatch, value: String)] {
        ready.compactMap { match in
            guard let value = lookup(match.kind), !value.isEmpty else { return nil }
            return (match, value)
        }
    }

    /// "14 fields matched free on your iPhone — 11 the site declared, 3 read from
    /// their labels". Shown on the step card, so the free work is visible.
    var freeLine: String? {
        guard freeMatchCount > 0 else { return nil }
        var parts: [String] = []
        if declaredCount > 0 { parts.append("\(declaredCount) the site declared") }
        let labelled = freeMatchCount - declaredCount - meaningCount
        if labelled > 0 { parts.append("\(labelled) from their labels") }
        if meaningCount > 0 { parts.append("\(meaningCount) read by your iPhone") }
        let head = "\(freeMatchCount) field\(freeMatchCount == 1 ? "" : "s") matched free"
        return parts.isEmpty ? head : "\(head) — \(parts.joined(separator: ", "))"
    }

    /// What the agent is told after the fill: what landed, what was deliberately
    /// left alone, and exactly which fields it still has to deal with itself.
    /// Never contains a single value from the dossier.
    func agentReport(filled: Int, failures: [String], submitted: Bool) -> String {
        var lines: [String] = []
        var head = "filled \(filled) of \(ready.count) matched field\(ready.count == 1 ? "" : "s") from the dossier"
        if submitted { head += filled == ready.count ? " and submitted" : " (submit attempted)" }
        lines.append(head)

        if !failures.isEmpty {
            lines.append("didn't land: \(failures.prefix(4).joined(separator: "; "))")
        }
        if !missing.isEmpty {
            let names = missing.prefix(5).map { $0.probe.descriptor }.joined(separator: ", ")
            lines.append("LEFT BLANK — the dossier has nothing stored for \(names). Nothing was invented for them. Ask the person, or skip them if the form allows.")
        }
        if !unmatched.isEmpty {
            let names = unmatched.prefix(8).map { $0.requiredDescriptor }.joined(separator: ", ")
            lines.append("NOT MATCHED — these are yours to work out: \(names)\(unmatched.count > 8 ? " (+\(unmatched.count - 8) more)" : "").")
        }
        if !unsupported.isEmpty {
            let names = unsupported.prefix(4).map { "\($0.descriptor) (\($0.widget.plainName))" }.joined(separator: ", ")
            lines.append("NOT A TEXT FIELD — handle these yourself with the normal moves: \(names)\(unsupported.count > 4 ? " (+\(unsupported.count - 4) more)" : "").")
        }
        if !sensitive.isEmpty {
            lines.append("SKIPPED ON PURPOSE — \(sensitive.count) password/card/code field\(sensitive.count == 1 ? "" : "s"). The dossier cannot hold a secret and never will; the person types those.")
        }
        if !alreadyFilled.isEmpty {
            lines.append("\(alreadyFilled.count) field\(alreadyFilled.count == 1 ? "" : "s") already held a value and \(alreadyFilled.count == 1 ? "was" : "were") left untouched.")
        }
        return lines.joined(separator: "\n")
    }
}

extension FormFieldProbe {
    /// Descriptor plus the required marker — used when handing unmatched fields
    /// back, where "required" is the thing that decides whether it matters.
    var requiredDescriptor: String {
        isRequired ? "\(descriptor) (required)" : descriptor
    }
}
