import Foundation

/// Word-level matching shared by every heuristic that reads a label or a result
/// line. Substring matching is the failure mode it exists to prevent: "ok" is
/// inside "Book", "send" is inside "Sender", and a button called "Report an
/// error" must never make a tap read as a failed one.
nonisolated enum Wording {

    /// Endings a phrase's last word may carry and still count as that word, so
    /// "pay" matches "payment" and "order" matches "orders" — but "pay" never
    /// matches "PayPal" and "send" never matches "Sender".
    static let inflections = ["s", "es", "ed", "d", "ing", "ment", "ments"]

    /// Lowercased alphanumeric words, in order.
    static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// True when `phrase` appears in `text` as whole words, in order.
    static func containsPhrase(_ text: String, _ phrase: String, allowInflection: Bool = false) -> Bool {
        let haystack = words(text)
        let needle = words(phrase)
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }

        for start in 0...(haystack.count - needle.count) {
            var hit = true
            for offset in 0..<needle.count {
                let word = haystack[start + offset]
                let wanted = needle[offset]
                if word == wanted { continue }
                let isLast = offset == needle.count - 1
                if allowInflection, isLast, word.hasPrefix(wanted),
                   inflections.contains(String(word.dropFirst(wanted.count))) {
                    continue
                }
                hit = false
                break
            }
            if hit { return true }
        }
        return false
    }

    /// True when any of `phrases` appears in `text` as whole words.
    static func containsAny(_ text: String, _ phrases: [String], allowInflection: Bool = false) -> Bool {
        phrases.contains { containsPhrase(text, $0, allowInflection: allowInflection) }
    }

    /// The part of a result line the app itself wrote.
    ///
    /// Result lines echo page content — element names, typed text, dialog
    /// messages, addresses — and all of it arrives quoted or as a bare address.
    /// Stripping those leaves only the app's own verdict wording, which is the
    /// only thing a success/failure reading may key off.
    static func appAuthored(_ result: String) -> String {
        var text = result
        // Straight and curly double-quoted spans: descriptors, typed text, dialogs.
        for pattern in [#""[^"]*""#, "\u{201C}[^\u{201D}]*\u{201D}"] {
            text = text.replacingOccurrences(of: pattern, with: "\"\"", options: .regularExpression)
        }
        // Address-like tokens: "landed on shop.test/error-404".
        text = text.replacingOccurrences(of: #"\S*\w[./]\w\S*"#, with: "<address>", options: .regularExpression)
        return text
    }
}
