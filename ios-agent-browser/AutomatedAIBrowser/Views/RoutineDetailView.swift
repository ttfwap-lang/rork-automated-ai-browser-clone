import SwiftUI

/// One saved replay in plain language: what it does, what it asks for, how it has
/// held up, and how many times it has had to repair itself.
struct RoutineDetailView: View {
    @Environment(AgentViewModel.self) private var agent
    @Environment(RoutineStore.self) private var routines
    @Environment(\.dismiss) private var dismiss
    let routine: Routine

    @State private var draftTitle = ""
    @State private var isRenaming = false
    @State private var confirmDelete = false
    @State private var isLaunching = false

    /// Read back from the store so repairs and renames show immediately.
    private var live: Routine {
        routines.routine(routine.id) ?? routine
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerCard
                routeCard
                if !live.blanks.isEmpty {
                    asksCard
                }
                if live.healCount > 0 {
                    healCard
                }
                privacyNote
                runButton
                deleteButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.bg)
        .navigationTitle("One-Tap Replay")
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
        .alert("Rename this replay", isPresented: $isRenaming) {
            TextField("Name", text: $draftTitle)
            Button("Save") {
                routines.rename(live.id, to: draftTitle)
                Haptics.success()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Call it whatever you think of it as.")
        }
        .confirmationDialog("Delete this replay?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                routines.delete(live.id)
                Haptics.warning()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $isLaunching) {
            RoutineLaunchSheet(routine: live)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.badge.clock.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("SAVED REPLAY")
                    .techLabel(10)
                Spacer()
                Text(live.host)
                    .techLabel(9)
                    .foregroundStyle(Theme.textSecondary)
            }
            .foregroundStyle(live.isShaky ? Theme.amber : Theme.cyan)

            Text(live.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(live.goalTemplate)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(live.recordLine.uppercased())
                .techLabel(8)
                .foregroundStyle(Theme.textSecondary)

            if live.isShaky {
                Text("The last attempt did not end confirmed. It is still here because a site having a bad day is not a reason to throw a route away — but read the last run before you trust it.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.amber.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder((live.isShaky ? Theme.amber : Theme.cyan).opacity(0.3), lineWidth: 1)
        )
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 10, weight: .semibold))
                Text("WHAT IT DOES")
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
                            Text(line(for: move, at: offset))
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            if move.isCommitting {
                                Text("STOPS AND ASKS YOU FIRST")
                                    .techLabel(7)
                                    .foregroundStyle(Theme.amber.opacity(0.9))
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

    private var asksCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 10, weight: .semibold))
                Text("WHAT IT ASKS YOU FOR")
                    .techLabel(9)
            }
            .foregroundStyle(Theme.violet)

            ForEach(live.blanks) { blank in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .foregroundStyle(Theme.violet.opacity(0.7))
                    Text(blank.label)
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

    private var healCard: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "bandage.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.green)
                .padding(.top, 1)
            Text("This replay has repaired itself \(live.healCount) time\(live.healCount == 1 ? "" : "s"). When the site moved a control, the step was matched to where it went and the route was updated — so the run after it was clean again.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.green)
                .padding(.top, 1)
            Text("This replay remembers which field to use, never what you typed into it. That is why it asks each time.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var runButton: some View {
        Button {
            Haptics.medium()
            if live.needsInput {
                isLaunching = true
            } else {
                agent.startRoutine(live, values: [:])
                dismiss()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13, weight: .bold))
                Text(live.needsInput ? "Fill in and run" : "Run it now")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Theme.cyan, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(Color.black)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(agent.isRunning)
        .opacity(agent.isRunning ? 0.4 : 1)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            confirmDelete = true
        } label: {
            Text("Delete this replay")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Theme.red)
        }
        .buttonStyle(PressableButtonStyle())
    }

    /// The move in plain words, with its blank shown as a blank.
    private func line(for move: RecipeMove, at index: Int) -> String {
        guard let blank = live.blanks.first(where: { $0.moveIndex == index }) else {
            return move.plainLine
        }
        return move.plainLine.replacingOccurrences(of: blank.label, with: blank.token)
    }
}
