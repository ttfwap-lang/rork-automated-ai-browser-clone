import Foundation

/// The third free pass: your iPhone reads the labels the phrase table could not
/// place.
///
/// This is deliberately the smallest possible question — a list of labels, a list
/// of fact names, one line back per field — because a small model is reliable at
/// "12=city" and unreliable at anything nested. Anything it says is checked
/// against the fields that really exist and the facts that really are on the
/// list; a line that fails either check is dropped and the field stays unmatched.
/// A dropped line costs nothing, so being strict is free.
nonisolated enum OnDeviceFieldReader {

    /// Labels sent in one ask. Past this, a small model starts skipping lines.
    static let batchSize = 12

    /// The most it is worth asking about in a single form. Beyond this the field
    /// is genuinely unusual and belongs to the agent.
    static let maxFields = 24

    static let instructions = """
    You match form field labels to a fixed list of personal-detail names. You are given numbered labels from one web form.

    Answer with ONE line per numbered label, in this exact form and nothing else:
    <number>=<name>

    Rules:
    - <name> must be copied exactly from the ALLOWED NAMES list, or be the word none.
    - Use none whenever you are not sure, whenever the label asks for something not on the list, and whenever the label asks for a password, a card, or a security code. none is always a safe answer.
    - Never invent a name that is not on the list.
    - No preamble, no explanation, no blank lines, no extra text.
    """

    /// The ask. Labels only — no page text, no values, nothing from the dossier
    /// beyond the names of the facts it can hold.
    static func prompt(for probes: [FormFieldProbe]) -> String {
        var lines = ["ALLOWED NAMES:"]
        lines.append(DossierFieldKind.allCases.map(\.briefingName).joined(separator: ", "))
        lines.append("")
        lines.append("LABELS:")
        for probe in probes {
            let words = probe.label.isEmpty ? probe.attribute : probe.label
            lines.append("\(probe.id)=\(String(words.prefix(60)))")
        }
        lines.append("")
        lines.append("Answer with one line per label.")
        return lines.joined(separator: "\n")
    }

    /// Parses the answer strictly. Only fields that were actually asked about, and
    /// only names that are actually on the list, survive.
    static func parse(_ raw: String, asking probes: [FormFieldProbe]) -> [FieldMatch] {
        let byID = Dictionary(uniqueKeysWithValues: probes.map { ($0.id, $0) })
        let byName = Dictionary(
            uniqueKeysWithValues: DossierFieldKind.allCases.map { ($0.briefingName, $0) }
        )

        var matches: [FieldMatch] = []
        var claimed = Set<Int>()

        for line in raw.split(separator: "\n") {
            let text = String(line).trimmed
            guard !text.isEmpty else { continue }
            let parts = text.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let idText = String(parts[0]).trimmingCharacters(in: CharacterSet(charactersIn: " \t.-*`[]"))
            guard let id = Int(idText), let probe = byID[id], !claimed.contains(id) else { continue }

            let name = String(parts[1])
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t.`\"'"))
                .lowercased()
            guard name != "none", let kind = byName[name] else { continue }

            claimed.insert(id)
            matches.append(FieldMatch(probe: probe, kind: kind, source: .meaning))
        }

        return matches
    }

    /// Splits the leftovers into asks small enough for a small model to answer
    /// without skipping lines.
    static func batches(_ probes: [FormFieldProbe]) -> [[FormFieldProbe]] {
        // A field with no words at all cannot be read by anyone.
        let readable = probes
            .filter { !$0.label.isEmpty || !$0.attribute.isEmpty }
            .prefix(maxFields)
        guard !readable.isEmpty else { return [] }
        return stride(from: 0, to: readable.count, by: batchSize).map { start in
            Array(readable[start..<min(start + batchSize, readable.count)])
        }
    }
}
