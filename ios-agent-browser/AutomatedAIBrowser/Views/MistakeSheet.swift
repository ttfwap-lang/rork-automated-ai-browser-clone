import SwiftUI

/// You saw the agent go wrong. This is where you say so.
///
/// Deliberately one line and one tap: an objection that takes a paragraph to
/// file will not be filed while the agent is already moving. A flag with nothing
/// written on it is still worth far more than saying nothing, so the note is
/// optional and the button never disables.
struct MistakeSheet: View {
    @Environment(AgentViewModel.self) private var agent
    @Environment(\.dismiss) private var dismiss

    @State private var note = ""
    @State private var rewindTarget: PageBookmark?
    @FocusState private var noteFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let move = agent.flaggableMoveText {
                        rejectedMove(move)
                    }
                    noteField
                    if !agent.rewindableBookmarks.isEmpty {
                        rewindPicker
                    }
                    consequences
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Theme.bg)
            .navigationTitle("That Was a Mistake")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Flag It") {
                        agent.flagMistake(note: note, rewindTo: rewindTarget)
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.red)
                }
            }
            .onAppear { noteFocused = true }
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
    }

    private func rejectedMove(_ move: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("THE MOVE YOU'RE REJECTING")
                .techLabel(9)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 7) {
                Image(systemName: "hand.raised.slash.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.red)
                Text(move)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.red.opacity(0.35), lineWidth: 1)
            )
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WHAT WAS WRONG? (OPTIONAL)")
                .techLabel(9)
                .foregroundStyle(Theme.textSecondary)
            TextField("e.g. that's the sponsored result, not the real one", text: $note, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1...3)
                .focused($noteFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(noteFocused ? Theme.red.opacity(0.5) : Theme.line, lineWidth: 1)
                )
        }
    }

    /// Offered only when there is somewhere real to go back to.
    private var rewindPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GO BACK FIRST? (OPTIONAL)")
                .techLabel(9)
                .foregroundStyle(Theme.textSecondary)
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(agent.rewindableBookmarks) { bookmark in
                        Button {
                            Haptics.light()
                            rewindTarget = rewindTarget?.number == bookmark.number ? nil : bookmark
                        } label: {
                            let isPicked = rewindTarget?.number == bookmark.number
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 8, weight: .bold))
                                Text("\(bookmark.number). \(bookmark.label)")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(isPicked ? Theme.bg : Theme.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(isPicked ? Theme.amber : Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(isPicked ? .clear : Theme.line, lineWidth: 1))
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: 34)
        }
    }

    /// Exactly what flagging does, including what it costs — which is nothing.
    private var consequences: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(
                icon: "nosign",
                tint: Theme.red,
                text: "That move is barred for the rest of this run. Not discouraged — refused."
            )
            row(
                icon: "arrow.triangle.2.circlepath",
                tint: Theme.violet,
                text: "The agent has to rewrite the rest of its route before it can touch the page again, and your words are handed over exactly as you wrote them."
            )
            row(
                icon: "creditcard",
                tint: Theme.green,
                text: "It costs nothing extra. The rewrite rides along with the next step's thinking, and it never spends the agent's own rewind allowance."
            )
            row(
                icon: "sparkles",
                tint: Theme.cyan,
                text: "The next decision goes to the strongest model — this is the worst moment for a cheap guess."
            )
            if let status = agent.mistakeStatus {
                row(icon: "info.circle", tint: Theme.amber, text: "Already flagged this run — \(status).")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elevated.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    private func row(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 14)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
