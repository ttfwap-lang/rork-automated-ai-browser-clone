import SwiftUI

/// One learned route in the Memory list: what it learned, how often it has
/// helped, and whether it has gone stale.
struct MemorySiteRow: View {
    let recipe: SiteRecipe

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(recipe.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if recipe.isRetired {
                    Text("RETIRED")
                        .techLabel(8)
                        .foregroundStyle(Theme.red)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.red.opacity(0.12), in: Capsule())
                } else if recipe.helpedCount > 0 {
                    Text("HELPED \(recipe.helpedCount)×")
                        .techLabel(8)
                        .foregroundStyle(Theme.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.green.opacity(0.12), in: Capsule())
                }
            }

            Text(recipe.intent)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text("\(recipe.moves.count) MOVE\(recipe.moves.count == 1 ? "" : "S")")
                    .techLabel(8)
                    .foregroundStyle(Theme.cyan.opacity(0.8))
                if let last = recipe.lastHelpedAt ?? recipe.lastUsedAt {
                    Text("·")
                        .foregroundStyle(Theme.textSecondary)
                    Text(last, format: .relative(presentation: .named))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.vertical, 3)
    }
}
