import Foundation

/// The free rung of the repair ladder: this iPhone's own model choosing which
/// live element a moved step meant.
///
/// It is asked the narrowest possible question — a numbered shortlist the app
/// built from the live page, pick one or pass — because that is the shape of
/// question a small model answers well. Anything other than one of those exact
/// numbers is thrown away, so the worst case is that the step falls through to
/// the paid rung, never that something wrong gets pressed.
nonisolated enum OnDeviceRepairer {

    static let instructions = """
    You match a control on a web page to the one an old saved step was pointing at.

    Answer with exactly one line and nothing else:
    PICK: <the number of the candidate that is the same control>
    or
    PICK: none

    Rules:
    - The number MUST come from the CANDIDATES list. Never any other number.
    - Same PURPOSE, not same wording. "Search" and "Find" are the same control. "Search" and "Search history" are not.
    - Answer none when you are not sure. Passing is always better than a wrong press.
    - No explanation, no second line.
    """

    static func prompt(intent: String, missingName: String, missingKind: String, candidates: [StepHealer.Candidate]) -> String {
        var lines = [
            "THE SAVED STEP: \(intent)",
            "IT POINTED AT: a \(missingKind) labelled “\(missingName)”, which is not on the page under that name now.",
            "",
            "CANDIDATES (the only valid answers):",
        ]
        lines.append(contentsOf: candidates.map { $0.line })
        lines.append("")
        lines.append("Answer with the one PICK line.")
        return lines.joined(separator: "\n")
    }

    /// Parses the answer and accepts it only when it names a candidate that is
    /// genuinely on the shortlist.
    static func parse(_ raw: String, allowed: [StepHealer.Candidate]) -> Int? {
        let line = raw
            .split(separator: "\n")
            .map { String($0).trimmed }
            .first { $0.lowercased().hasPrefix("pick:") }
        guard let line else { return nil }

        let value = String(line.dropFirst("pick:".count)).trimmed.lowercased()
        guard !value.isEmpty, value != "none" else { return nil }

        let digits = value.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        guard digits.count == 1, let number = Int(digits[0]) else { return nil }
        guard allowed.contains(where: { $0.id == number }) else { return nil }
        return number
    }
}
