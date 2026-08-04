import SwiftUI

/// Supervised-mode approve/reject card for the AI's proposed action.
struct ApprovalControls: View {
    @Environment(AgentViewModel.self) private var agent
    var showReasoning = true

    var body: some View {
        if let step = agent.pendingStep {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: step.action.kind.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                    Text("PROPOSED: \(step.action.kind.label)")
                        .techLabel(10)
                        .foregroundStyle(Theme.amber)
                    Text(step.action.detailText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                if showReasoning && !step.reasoning.isEmpty {
                    Text(step.reasoning)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    Button {
                        agent.rejectPendingAction()
                    } label: {
                        Text("Reject")
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
                        agent.approvePendingAction()
                    } label: {
                        Text("Approve")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Theme.cyan, in: RoundedRectangle(cornerRadius: 12))
                            .shadow(color: Theme.cyan.opacity(0.4), radius: 8, y: 2)
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
