import Foundation
import Observation

/// The vault of proven routes, written to the device and kept small on purpose.
///
/// Every use is scored. A recipe that leads the agent astray twice is retired
/// automatically, so a site redesign cannot keep costing the user missions, and a
/// recipe that keeps working gains confidence and is preferred over newer,
/// less-proven ones.
@Observable
final class RecipeVault {
    private(set) var recipes: [SiteRecipe] = []

    private let fileURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("site_recipes.json")
        load()
    }

    /// Sites the agent has learned, newest activity first, with their recipes.
    var sites: [(host: String, recipes: [SiteRecipe])] {
        Dictionary(grouping: recipes, by: { $0.host })
            .map { (host: $0.key, recipes: $0.value.sorted { left, right in
                (left.lastHelpedAt ?? left.createdAt) > (right.lastHelpedAt ?? right.createdAt)
            }) }
            .sorted { left, right in
                let leftDate = left.recipes.first.map { $0.lastHelpedAt ?? $0.createdAt } ?? .distantPast
                let rightDate = right.recipes.first.map { $0.lastHelpedAt ?? $0.createdAt } ?? .distantPast
                return leftDate > rightDate
            }
    }

    var isEmpty: Bool { recipes.isEmpty }

    /// Recipes that are still trusted.
    var liveRecipes: [SiteRecipe] { recipes.filter { !$0.isRetired } }

    /// Stores a freshly distilled recipe, replacing the existing one for the same
    /// kind of mission on the same site. One recipe per intent per site — a
    /// vault of near-duplicates is what makes matching ambiguous.
    func upsert(_ recipe: SiteRecipe) {
        let intentWords = RecipeMatcher.significantWords(recipe.intent)
        let existingIndex = recipes.firstIndex { candidate in
            guard candidate.host == recipe.host else { return false }
            let candidateWords = RecipeMatcher.significantWords(candidate.intent)
            guard !RecipeMatcher.conflicts(intentWords, candidateWords) else { return false }
            return RecipeMatcher.similarity(intentWords, candidateWords) >= 0.6
        }

        if let existingIndex {
            // Keep the record of what this route has already proven; replace the
            // route itself with the one that just worked.
            let existing = recipes[existingIndex]
            let merged = SiteRecipe(
                id: existing.id,
                host: recipe.host,
                intent: recipe.intent,
                title: existing.title == existing.intent ? recipe.title : existing.title,
                moves: recipe.moves,
                checks: recipe.checks,
                traps: recipe.traps.isEmpty ? existing.traps : recipe.traps,
                stepCount: recipe.stepCount,
                useCount: existing.useCount,
                helpedCount: existing.helpedCount,
                // A fresh proof clears the stale count: this route just worked.
                strayCount: 0,
                createdAt: existing.createdAt,
                lastUsedAt: existing.lastUsedAt,
                lastHelpedAt: existing.lastHelpedAt
            )
            recipes[existingIndex] = merged
        } else {
            recipes.append(recipe)
        }

        enforceCapacity()
        save()
    }

    /// Notes that a recipe was recalled for a run.
    func recordUse(_ id: UUID) {
        guard let index = recipes.firstIndex(where: { $0.id == id }) else { return }
        recipes[index].useCount += 1
        recipes[index].lastUsedAt = Date()
        save()
    }

    /// Notes that a recipe's route actually held up.
    func recordHelped(_ id: UUID) {
        guard let index = recipes.firstIndex(where: { $0.id == id }) else { return }
        recipes[index].helpedCount += 1
        recipes[index].lastHelpedAt = Date()
        save()
    }

    /// Notes that a recipe led the agent somewhere that no longer exists. Two of
    /// these retires it.
    func recordStray(_ id: UUID) {
        guard let index = recipes.firstIndex(where: { $0.id == id }) else { return }
        recipes[index].strayCount += 1
        save()
    }

    func rename(_ id: UUID, to title: String) {
        guard let index = recipes.firstIndex(where: { $0.id == id }) else { return }
        let clean = title.trimmed
        guard !clean.isEmpty else { return }
        recipes[index].title = String(clean.prefix(60))
        save()
    }

    func delete(_ id: UUID) {
        recipes.removeAll { $0.id == id }
        save()
    }

    func forget(host: String) {
        recipes.removeAll { $0.host == host }
        save()
    }

    func wipe() {
        recipes = []
        save()
    }

    /// Keeps the vault small: when it overflows, the least-proven and least-recently
    /// useful recipes go first.
    private func enforceCapacity() {
        guard recipes.count > SiteRecipe.capacity else { return }
        let ranked = recipes.sorted { left, right in
            if left.isRetired != right.isRetired { return !left.isRetired }
            if abs(left.confidence - right.confidence) > 0.001 { return left.confidence > right.confidence }
            return (left.lastHelpedAt ?? left.createdAt) > (right.lastHelpedAt ?? right.createdAt)
        }
        recipes = Array(ranked.prefix(SiteRecipe.capacity))
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        recipes = (try? JSONDecoder().decode([SiteRecipe].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(recipes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
