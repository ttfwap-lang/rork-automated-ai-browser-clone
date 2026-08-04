import SwiftUI

/// The saved one-tap replays, sitting where you reach for them: just above the
/// place you would otherwise type the whole mission out again.
struct RoutineStrip: View {
    @Environment(AgentViewModel.self) private var agent
    @Environment(RoutineStore.self) private var routines
    /// Set when a replay needs its blanks filled in before it can run.
    @State private var launching: Routine?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "bolt.badge.clock.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("ONE-TAP REPLAYS")
                    .techLabel(9)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(routines.ordered) { routine in
                        RoutineChip(routine: routine) {
                            launch(routine)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 16, for: .scrollContent)
        }
        .sheet(item: $launching) { routine in
            RoutineLaunchSheet(routine: routine)
        }
    }

    /// A replay with no blanks runs on the tap. One with blanks asks first —
    /// which is the whole point of keeping the question instead of the answer.
    private func launch(_ routine: Routine) {
        Haptics.medium()
        if routine.needsInput {
            launching = routine
        } else {
            agent.startRoutine(routine, values: [:])
        }
    }
}
