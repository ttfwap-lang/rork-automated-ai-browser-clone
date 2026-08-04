import SwiftUI

/// Live run telemetry: phase, step counter, and mode.
struct StatusStrip: View {
    @Environment(AgentViewModel.self) private var agent

    var body: some View {
        HStack(spacing: 10) {
            PulsingDot(color: agent.phase.color)
            Text(agent.phase.label)
                .techLabel(10)
                .foregroundStyle(agent.phase.color)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: agent.phase)

            Rectangle()
                .fill(Theme.line)
                .frame(width: 1, height: 12)

            Text("STEP \(agent.currentStepIndex)/\(agent.maxStepsThisRun)")
                .techLabel(10)
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.numericText())
                .animation(.snappy, value: agent.currentStepIndex)

            Rectangle()
                .fill(Theme.line)
                .frame(width: 1, height: 12)

            HStack(spacing: 4) {
                Image(systemName: agent.mode.icon)
                    .font(.system(size: 8, weight: .bold))
                Text(agent.mode.label)
                    .techLabel(9)
            }
            .foregroundStyle(Theme.textSecondary)

            if let tally = agent.routingTally {
                Rectangle()
                    .fill(Theme.line)
                    .frame(width: 1, height: 12)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 8, weight: .bold))
                    Text(tally)
                        .techLabel(9)
                        .contentTransition(.numericText())
                }
                .foregroundStyle(Theme.violet)
            }

            // Steps a saved replay had to repair to keep working.
            if let healed = agent.healTally {
                HStack(spacing: 4) {
                    Image(systemName: "bandage.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text(healed)
                        .techLabel(9)
                        .contentTransition(.numericText())
                }
                .foregroundStyle(Theme.green)
            }

            // Free work is shown apart from the paid tally, because it is free.
            if let free = agent.freeTally {
                HStack(spacing: 4) {
                    Image(systemName: "iphone")
                        .font(.system(size: 8, weight: .bold))
                    Text(free)
                        .techLabel(9)
                        .contentTransition(.numericText())
                }
                .foregroundStyle(Theme.cyan)
            }

            Spacer()

            if let goal = agent.activeGoal {
                Text(goal)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Theme.surface.opacity(0.7))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }
}
