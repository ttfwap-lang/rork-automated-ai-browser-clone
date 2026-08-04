import Foundation

/// A recipe the vault recognised for the goal at hand, and how confident the
/// match is. A weak or ambiguous match is never turned into one of these —
/// half-remembering is worse than reading the page fresh.
nonisolated struct RecipeMatch: Equatable, Sendable {
    let recipe: SiteRecipe
    /// 0-1, how well the goal matched the recipe's intent.
    let score: Double
    /// Plain reason, recorded in the run's history.
    let reason: String
}
