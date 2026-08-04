import SwiftUI

/// The checkpoint strip: up to five points the mission can go back to, the
/// current one highlighted. Tap one to send the agent back there yourself while
/// a run is paused for approval, or to take the browser back when it is idle.
struct BookmarkStrip: View {
    @Environment(AgentViewModel.self) private var agent
    @State private var pendingTarget: PageBookmark?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text("CHECKPOINTS")
                    .techLabel(9)
                Spacer()
                if agent.rewindCount > 0 {
                    Text("\(agent.rewindCount) REWOUND")
                        .techLabel(8)
                        .foregroundStyle(Theme.violet)
                }
            }
            .foregroundStyle(Theme.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(agent.bookmarks) { bookmark in
                        Button {
                            guard agent.canRewindByHand else { return }
                            Haptics.light()
                            pendingTarget = bookmark
                        } label: {
                            BookmarkChip(
                                bookmark: bookmark,
                                isCurrent: agent.isCurrentBookmark(bookmark),
                                isTappable: agent.canRewindByHand
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!agent.canRewindByHand)
                    }
                }
            }
            .contentMargins(.horizontal, 0, for: .scrollContent)

            if !agent.canRewindByHand {
                Text("Tap a checkpoint to go back — available while the run is paused for approval or finished.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
        .confirmationDialog(
            pendingTarget.map { "Go back to checkpoint \($0.number)?" } ?? "Go back?",
            isPresented: Binding(
                get: { pendingTarget != nil },
                set: { if !$0 { pendingTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let target = pendingTarget {
                Button("Rewind to \(target.label)") {
                    agent.userRewind(to: target)
                    pendingTarget = nil
                }
                Button("Cancel", role: .cancel) { pendingTarget = nil }
            }
        } message: {
            if let target = pendingTarget {
                Text(target.tried.isEmpty
                     ? "The browser goes back to this page. Typed form text is not restored."
                     : "Already tried from there: \(target.triedLine)")
            }
        }
    }
}
