import Foundation

/// One fact the agent wrote down while reading a page, with the exact words it
/// read it from.
///
/// Page readings only live for one turn, so without this a mission that
/// gathers facts across several pages ("compare the price on three sites")
/// forgets the first page by the time it reaches the third — and the
/// independent check, which only sees the page the run ended on, can never
/// confirm it. The app checks each quote against the live page before the fact
/// is kept, so a noted fact is evidence, not a claim.
nonisolated struct NotedFact: Codable, Equatable, Sendable {
    /// The fact in the agent's words, e.g. "Store B sells it for $348".
    let fact: String
    /// Words copied exactly from the page that support it.
    let quote: String
    /// Where it was read — set by the app, never by the model.
    var urlString: String?

    static let maxFactLength = 200
    static let maxQuoteLength = 240

    /// Trimmed and bounded, or nil when either half is empty.
    static func make(fact: String?, quote: String?) -> NotedFact? {
        let cleanFact = String((fact ?? "").trimmed.prefix(maxFactLength))
        let cleanQuote = String((quote ?? "").trimmed.prefix(maxQuoteLength))
        guard !cleanFact.isEmpty, !cleanQuote.isEmpty else { return nil }
        return NotedFact(fact: cleanFact, quote: cleanQuote, urlString: nil)
    }

    /// `Store B sells it for $348 — “$348.00” (shop-b.test/item/9)`
    var ledgerLine: String {
        let source = urlString.map { RecipeMove.shortAddress($0) } ?? "unknown page"
        return "\(fact) — \u{201C}\(quote)\u{201D} (\(source))"
    }
}
