import Foundation

/// Turns a whole-page reading into the part worth sending to the model.
///
/// A reading used to be the first 9,000 characters, so on a long page the one
/// section that answered the question was often past the cut. Two ways out,
/// both free and on the device:
///
/// - **With a question**, the page is split into sections (each heading starts
///   one; long runs are cut into ~700-character pieces) and every section is
///   ranked by BM25 against the question — the same ranking search engines and
///   Crawl4AI's content filter use. The best sections that fit the budget are
///   kept, shown in page order so the reading still makes sense.
/// - **Without one**, the reading continues from `startFrom`, so a long page
///   can be read in pages instead of being cut off.
nonisolated enum PageDigest {

    nonisolated struct Section: Equatable {
        /// Where the section starts in the full reading, in characters.
        let offset: Int
        let text: String
    }

    /// Characters handed to the model per reading.
    static let budget = 9_000
    /// Longest a section may run before it is cut.
    static let sectionLength = 700

    // BM25's usual constants.
    private static let k1 = 1.2
    private static let b = 0.75

    // MARK: - Sections

    /// Splits a reading into sections at headings (`#` lines) and every
    /// `sectionLength` characters, at line boundaries.
    static func sections(of text: String, maxLength: Int = sectionLength) -> [Section] {
        var sections: [Section] = []
        var current = ""
        var currentStart = 0
        var offset = 0

        func close() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { sections.append(Section(offset: currentStart, text: trimmed)) }
            current = ""
        }

        for line in text.components(separatedBy: "\n") {
            let isHeading = line.hasPrefix("#")
            if isHeading || current.count + line.count > maxLength {
                close()
                currentStart = offset
            }
            // A single line longer than a section is cut on its own.
            if line.count > maxLength {
                var rest = Substring(line)
                var pieceStart = offset
                while !rest.isEmpty {
                    let piece = rest.prefix(maxLength)
                    sections.append(Section(offset: pieceStart, text: String(piece)))
                    pieceStart += piece.count
                    rest = rest.dropFirst(piece.count)
                }
                currentStart = offset + line.count + 1
            } else {
                current += current.isEmpty ? line : "\n" + line
            }
            offset += line.count + 1
        }
        close()
        return sections
    }

    // MARK: - Ranking

    /// Meaningful words of a question, lightly normalised so "prices" finds "price".
    static func terms(_ text: String) -> [String] {
        Wording.words(text)
            .filter { $0.count > 1 && !RecipeMatcher.stopWords.contains($0) }
            .map(normalise)
    }

    private static func normalise(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") else { return word }
        return String(word.dropLast())
    }

    /// BM25 score of every section against the query terms.
    static func scores(_ sections: [Section], terms queryTerms: [String]) -> [Double] {
        let query = Array(Set(queryTerms))
        guard !sections.isEmpty, !query.isEmpty else { return sections.map { _ in 0 } }
        let docs = sections.map { Wording.words($0.text).map(normalise) }
        let averageLength = max(1, Double(docs.map(\.count).reduce(0, +)) / Double(docs.count))
        let total = Double(docs.count)

        var documentFrequency: [String: Double] = [:]
        for term in query {
            documentFrequency[term] = Double(docs.filter { $0.contains(term) }.count)
        }

        return docs.map { words in
            let length = Double(words.count)
            var frequency: [String: Double] = [:]
            for word in words where documentFrequency[word] != nil {
                frequency[word, default: 0] += 1
            }
            var score = 0.0
            for term in query {
                guard let tf = frequency[term], tf > 0 else { continue }
                let df = documentFrequency[term] ?? 0
                let idf = log(1 + (total - df + 0.5) / (df + 0.5))
                score += idf * (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * length / averageLength))
            }
            return score
        }
    }

    // MARK: - The reading handed to the model

    /// The part of `full` worth reading for `query`, or the page from
    /// `startFrom` when there is no question.
    static func digest(_ full: String, query: String?, startFrom: Int = 0, budget: Int = budget) -> String {
        let text = full.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return full }

        let queryTerms = terms(query ?? "")
        if !queryTerms.isEmpty {
            if let focused = focusedDigest(text, query: query ?? "", terms: queryTerms, budget: budget) {
                return focused
            }
            let top = sequentialDigest(text, startFrom: 0, budget: budget)
            return "(Nothing on this page mentions “\(String((query ?? "").prefix(60)))” — showing the page from the top.)\n\n\(top)"
        }
        return sequentialDigest(text, startFrom: startFrom, budget: budget)
    }

    private static func focusedDigest(_ text: String, query: String, terms queryTerms: [String], budget: Int) -> String? {
        let all = sections(of: text)
        let ranked = zip(all.indices, scores(all, terms: queryTerms))
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        guard !ranked.isEmpty else { return nil }

        var chosen: [Int] = []
        var used = 0
        for (index, _) in ranked {
            let cost = all[index].text.count + 2
            guard used + cost <= budget || chosen.isEmpty else { continue }
            chosen.append(index)
            used += cost
        }
        chosen.sort()

        var pieces: [String] = []
        var previous: Int?
        for index in chosen {
            if let previous, index != previous + 1 { pieces.append("…") }
            pieces.append(String(all[index].text.prefix(budget)))
            previous = index
        }
        let header = "(Reading focused on “\(String(query.prefix(60)))”: the \(chosen.count) of \(all.count) sections of this page that match it best, in page order. Read without a query, or with start_from, for the rest.)"
        return header + "\n\n" + pieces.joined(separator: "\n\n")
    }

    private static func sequentialDigest(_ text: String, startFrom: Int, budget: Int) -> String {
        let start = min(max(startFrom, 0), text.count)
        let tail = text.dropFirst(start)
        guard tail.count > budget else {
            let prefix = start > 0 ? "(Continuing from character \(start).)\n\n" : ""
            return prefix + String(tail)
        }
        var slice = String(tail.prefix(budget))
        // End on a line break when one is reasonably close, so no line is cut.
        if let lastBreak = slice.lastIndex(of: "\n"), slice.distance(from: slice.startIndex, to: lastBreak) > budget / 2 {
            slice = String(slice[..<lastBreak])
        }
        let next = start + slice.count
        let prefix = start > 0 ? "(Continuing from character \(start).)\n\n" : ""
        return prefix + slice + "\n…(the page continues — \(text.count - next) more characters; call extract with start_from=\(next) to read on, or with a query to jump to what matters)"
    }
}
