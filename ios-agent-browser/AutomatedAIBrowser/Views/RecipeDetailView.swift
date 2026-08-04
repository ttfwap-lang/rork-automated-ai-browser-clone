import SwiftUI

/// One learned route in plain language: the route, the traps, the checks — plus
/// rename and delete. Nothing here is jargon, because a memory the user cannot
/// read is a memory they cannot trust.
struct RecipeDetailView: View {
    @Environment(RecipeVault.self) private var vault
    @Environment(\.dismiss) private var dismiss
    let recipe: SiteRecipe

    @State private var draftTitle = ""
    @State private var isRenaming = false
    @State private var confirmDelete = false

    /// Read back from the vault so edits show immediately.
    private var live: SiteRecipe {
        vault.recipes.first { $0.id == recipe.id } ?? recipe
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerCard
                routeCard
                if !live.traps.isEmpty {
                    listCard(
                        title: "WHAT GETS IN THE WAY",
                        icon: "exclamationmark.triangle.fill",
                        tint: Theme.amber,
                        lines: live.traps
                    )
                }
                if !live.checks.isEmpty {
                    listCard(
                        title: "HOW IT WAS PROVEN",
                        icon: "checkmark.shield.fill",
                        tint: Theme.green,
                        lines: live.checks
                    )
                }
                privacyNote
                deleteButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.bg)
        .navigationTitle("Learned Route")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Rename") {
                    draftTitle = live.title
                    isRenaming = true
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.cyan)
            }
        }
        .alert("Rename this route", isPresented: $isRenaming) {
            TextField("Name", text: $draftTitle)
            Button("Save") {
                vault.rename(live.id, to: draftTitle)
                Haptics.success()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Call it whatever you think of it as.")
        }
        .confirmationDialog("Delete this route?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                vault.delete(live.id)
                Haptics.warning()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: live.isRetired ? "xmark.seal.fill" : "brain")
                    .font(.system(size: 11, weight: .bold))
                Text(live.isRetired ? "RETIRED" : "LEARNED ROUTE")
                    .techLabel(10)
                Spacer()
                Text(live.host)
                    .techLabel(9)
                    .foregroundStyle(Theme.textSecondary)
            }
            .foregroundStyle(live.isRetired ? Theme.red : Theme.cyan)

            Text(live.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Used when you want to: \(live.intent)")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(live.recordLine.uppercased())
                .techLabel(8)
                .foregroundStyle(Theme.textSecondary)

            if live.isRetired {
                Text("This route stopped matching the site twice, so it is no longer used. The site has probably been redesigned — the next confirmed success here will write a fresh one.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.red.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder((live.isRetired ? Theme.red : Theme.cyan).opacity(0.3), lineWidth: 1)
        )
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 10, weight: .semibold))
                Text("THE ROUTE THAT WORKED")
                    .techLabel(9)
            }
            .foregroundStyle(Theme.cyan)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(live.moves.enumerated()), id: \.element.id) { offset, move in
                    HStack(alignment: .top, spacing: 8) {
                        Text(String(format: "%02d", offset + 1))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(move.plainLine)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            if offset < HeadStart.maxMoves, move.isSafeToReplay {
                                Text("REPLAYED WITHOUT ASKING THE AI")
                                    .techLabel(7)
                                    .foregroundStyle(Theme.amber.opacity(0.9))
                            } else if move.isCommitting {
                                Text("NEVER REPLAYED — THIS ONE COMMITS")
                                    .techLabel(7)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
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

    private func listCard(title: String, icon: String, tint: Color, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .techLabel(9)
            }
            .foregroundStyle(tint)

            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .foregroundStyle(tint.opacity(0.7))
                    Text(line)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.green)
                .padding(.top, 1)
            Text("This route remembers which field to use, never what you typed into it. It was written on your iPhone and never left it.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            confirmDelete = true
        } label: {
            Text("Delete this route")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Theme.red)
        }
        .buttonStyle(PressableButtonStyle())
    }
}
