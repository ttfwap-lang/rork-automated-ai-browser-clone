import SwiftUI

/// Quick-start goal suggestions shown when the command bar is idle and empty.
struct SuggestionChips: View {
    let onPick: (String) -> Void

    private static let suggestions: [(label: String, goal: String)] = [
        ("Vintage cameras", "Search DuckDuckGo for vintage film cameras and open the first result"),
        ("Top HN story", "Go to news.ycombinator.com and tell me today's top story"),
        ("Tallest building", "Look up the tallest building in the world on Wikipedia and give me its height"),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.suggestions, id: \.label) { suggestion in
                    Button {
                        Haptics.light()
                        onPick(suggestion.goal)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 9))
                            Text(suggestion.label)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Theme.cyan.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.cyan.opacity(0.08), in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.cyan.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }
}
