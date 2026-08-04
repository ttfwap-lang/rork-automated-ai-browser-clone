import Foundation

/// Matches the vault against the goal at hand — by site AND by what the user is
/// actually trying to do.
///
/// Matching on the domain alone is the failure mode that makes remembered routes
/// dangerous: a "find the cheapest flight" recipe must never be used for a
/// "cancel my booking" goal on the same site.
nonisolated enum RecipeMatcher {

    /// Below this overlap the memory is not used at all.
    static let minimumScore = 0.34
    /// Two candidates this close together are genuinely ambiguous.
    static let ambiguityMargin = 0.06

    /// Words that carry no intent and would inflate every match.
    static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "to", "for", "of", "on", "in", "at", "my",
        "me", "i", "is", "it", "this", "that", "with", "from", "by", "as", "be",
        "get", "please", "can", "you", "your", "then", "some", "any", "do", "go",
        "www", "com", "http", "https", "find", "show",
    ]

    /// Verbs that change a goal's meaning completely. If one side has a strong
    /// verb the other lacks, the recipe is the wrong recipe no matter how many
    /// other words overlap.
    static let decisiveVerbs: Set<String> = [
        "cancel", "delete", "remove", "refund", "return", "unsubscribe", "close",
        "buy", "purchase", "order", "pay", "checkout", "book", "reserve",
        "sell", "post", "publish", "send", "apply", "download", "upload",
    ]

    /// The strongest usable match, or nil when nothing is trustworthy enough.
    static func best(for goal: String, urlString: String, in recipes: [SiteRecipe]) -> RecipeMatch? {
        let hosts = candidateHosts(goal: goal, urlString: urlString, in: recipes)
        guard !hosts.isEmpty else { return nil }
        return best(for: goal, hosts: hosts, in: recipes)
    }

    static func best(for goal: String, host: String, in recipes: [SiteRecipe]) -> RecipeMatch? {
        best(for: goal, hosts: [host], in: recipes)
    }

    static func best(for goal: String, hosts: Set<String>, in recipes: [SiteRecipe]) -> RecipeMatch? {
        let goalWords = significantWords(goal)
        guard !goalWords.isEmpty else { return nil }

        let candidates = recipes
            .filter { !$0.isRetired && hosts.contains($0.host) && !$0.moves.isEmpty }
            .compactMap { recipe -> (SiteRecipe, Double)? in
                let intentWords = significantWords(recipe.intent)
                guard !intentWords.isEmpty else { return nil }
                guard !conflicts(goalWords, intentWords) else { return nil }
                let overlap = similarity(goalWords, intentWords)
                guard overlap >= minimumScore else { return nil }
                return (recipe, overlap)
            }
            .sorted { left, right in
                if abs(left.1 - right.1) > 0.001 { return left.1 > right.1 }
                return left.0.confidence > right.0.confidence
            }

        guard let winner = candidates.first else { return nil }

        // A near-tie between two different intents is genuine ambiguity. There
        // should only ever be one recipe per intent per site, so this means the
        // goal sits between two of them.
        if candidates.count > 1, winner.1 - candidates[1].1 < ambiguityMargin {
            return nil
        }

        return RecipeMatch(
            recipe: winner.0,
            score: winner.1,
            reason: "recognised “\(winner.0.title)” on \(winner.0.host)"
        )
    }

    /// Which sites are worth searching: the one the browser is on, plus any site
    /// the goal itself names.
    ///
    /// Matching on the current page alone would make memory almost useless in
    /// practice — a repeat mission usually starts from a search page or a blank
    /// tab, not from the site it is about.
    static func candidateHosts(goal: String, urlString: String, in recipes: [SiteRecipe]) -> Set<String> {
        var hosts: Set<String> = []
        let current = normalizedHost(urlString)
        if !current.isEmpty { hosts.insert(current) }

        let goalWords = significantWords(goal)
        for recipe in recipes {
            let label = primaryLabel(recipe.host)
            if !label.isEmpty, goalWords.contains(label) {
                hosts.insert(recipe.host)
            }
        }
        return hosts
    }

    /// `amazon` from `amazon.co.uk`, `example` from `shop.example.com` — the part
    /// a person would actually type into a goal.
    static func primaryLabel(_ host: String) -> String {
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return host.lowercased() }
        let secondLast = parts[parts.count - 2]
        // Handle two-part suffixes like .co.uk, where the meaningful label sits
        // one place further left.
        if secondLast.count <= 3, parts.count >= 3 {
            return parts[parts.count - 3].lowercased()
        }
        return secondLast.lowercased()
    }

    /// Overlap of meaningful words, measured against the shorter side so a
    /// verbose goal is not penalised for saying more.
    static func similarity(_ left: Set<String>, _ right: Set<String>) -> Double {
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let shared = left.intersection(right).count
        return Double(shared) / Double(min(left.count, right.count))
    }

    /// True when one side carries a decisive verb the other does not.
    static func conflicts(_ left: Set<String>, _ right: Set<String>) -> Bool {
        let leftVerbs = left.intersection(decisiveVerbs)
        let rightVerbs = right.intersection(decisiveVerbs)
        if leftVerbs.isEmpty && rightVerbs.isEmpty { return false }
        return leftVerbs != rightVerbs
    }

    /// Lowercased words worth matching on, stripped of punctuation and noise.
    static func significantWords(_ text: String) -> Set<String> {
        let pieces = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
        return Set(pieces)
    }

    /// `shop.example.com` from a full address, without a `www.` prefix.
    static func normalizedHost(_ urlString: String) -> String {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
