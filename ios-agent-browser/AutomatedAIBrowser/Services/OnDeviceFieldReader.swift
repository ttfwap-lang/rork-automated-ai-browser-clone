import Foundation
import FoundationModels

/// The third free pass: your iPhone reads the labels the phrase table could not
/// place.
///
/// This asks for a real Swift value rather than text. Guided generation
/// constrains sampling to `Reading`, whose `fact` is a `DossierFieldKind` — so an
/// invented fact name is not an error case that has to be caught, it is an answer
/// the model is incapable of producing. Because there is no case for a password,
/// a card or a security code, it also cannot ask for one. The old defence was a
/// whitelist applied after parsing; this one is enforced while the answer is
/// being sampled.
///
/// It still cannot be trusted about *which* field: a number it returns is checked
/// against the fields actually asked about, and an unknown number is dropped. A
/// dropped reading costs nothing, so being strict is free.
nonisolated enum OnDeviceFieldReader {

    /// Labels sent in one ask. Past this, a small model starts skipping entries.
    static let batchSize = 12

    /// The most it is worth asking about in a single form. Beyond this the field
    /// is genuinely unusual and belongs to the agent.
    static let maxFields = 24

    /// One label the model recognised.
    @Generable(description: "One numbered form label matched to the detail it asks for")
    struct Reading: Equatable, Sendable {
        @Guide(description: "The number printed before the label")
        var field: Int

        @Guide(description: "Which personal detail that label is asking for")
        var fact: DossierFieldKind
    }

    /// Everything the model recognised in one batch.
    @Generable(description: "The labels you recognised")
    struct Sheet: Equatable, Sendable {
        @Guide(description: "One entry for each numbered label you are confident about. Omit a label entirely when unsure.")
        var readings: [Reading]
    }

    /// Instructions for the guided ask. Note there is no "answer none" rule to
    /// obey — omission *is* the refusal, and the shape of the answer enforces it.
    static let guidedInstructions = """
    You match numbered form field labels from one web form to the kind of personal detail each label is asking for.

    Rules:
    - Only include a label when you are genuinely confident. Omitting a label is always a safe answer.
    - Never include a label that asks for a password, a card number or a security code.
    - Only use numbers that appear in the list you are given.
    """

    /// The guided ask. Labels only — no page text, no values, nothing from the
    /// dossier at all, not even the names of the facts: the schema carries those.
    static func guidedPrompt(for probes: [FormFieldProbe]) -> String {
        var lines = ["LABELS:"]
        for probe in probes {
            let words = probe.label.isEmpty ? probe.attribute : probe.label
            lines.append("\(probe.id)=\(String(words.prefix(60)))")
        }
        return lines.joined(separator: "\n")
    }

    /// Turns a guided answer into matches, keeping only fields that were actually
    /// asked about and only the first reading for each.
    ///
    /// The fact needs no checking: it arrived as a real case of the enumeration.
    static func resolve(_ sheet: Sheet, asking probes: [FormFieldProbe]) -> [FieldMatch] {
        let byID = Dictionary(uniqueKeysWithValues: probes.map { ($0.id, $0) })
        var matches: [FieldMatch] = []
        var claimed = Set<Int>()

        for reading in sheet.readings {
            guard let probe = byID[reading.field], !claimed.contains(reading.field) else { continue }
            claimed.insert(reading.field)
            matches.append(FieldMatch(probe: probe, kind: reading.fact, source: .meaning))
        }

        return matches
    }

    /// Kept for the fallback path: if guided generation cannot run at all, a plain
    /// prose ask is still better than leaving every odd field to a paid call.
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
