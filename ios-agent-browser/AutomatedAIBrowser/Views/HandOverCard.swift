import SwiftUI

/// Your turn in the browser: what the agent needs you to do, and the two ways
/// out. The page above stays fully usable — do the part, then tap Done and the
/// agent carries on from wherever you leave it.
struct HandOverCard: View {
    @Environment(AgentViewModel.self) private var agent

    var body: some View {
        if let instruction = agent.pendingHandOver {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: AgentActionKind.handOver.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                    Text("YOUR TURN")
                        .techLabel(10)
                        .foregroundStyle(Theme.amber)
                    Spacer(minLength: 0)
                }

                Text(instruction)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Use the page above as you normally would. The agent is paused and will not touch it until you hand it back.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        agent.finishYourTurn(handBack: false)
                    } label: {
                        Text("Stop run")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Theme.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Theme.red.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .buttonStyle(PressableButtonStyle())

                    Button {
                        agent.finishYourTurn(handBack: true)
                    } label: {
                        Text("Done — carry on")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Theme.cyan, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(12)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Theme.amber.opacity(0.35), lineWidth: 1)
            )
        }
    }
}
