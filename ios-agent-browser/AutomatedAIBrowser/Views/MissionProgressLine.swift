import SwiftUI

/// Always-visible plan awareness above the run telemetry: the current task and
/// the same progress bar as the plan card. Tap to open the full mission log.
struct MissionProgressLine: View {
    @Environment(AgentViewModel.self) private var agent

    var body: some View {
        if let plan = agent.plan {
            Button {
                Haptics.light()
                agent.isFeedPresented = true
            } label: {
                VStack(spacing: 5) {
                    HStack(spacing: 7) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.cyan)
                        Text(currentTitle(plan))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(plan.settledCount)/\(plan.tasks.count)")
                            .techLabel(9)
                            .foregroundStyle(Theme.cyan)
                            .contentTransition(.numericText())
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.line)
                            Capsule()
                                .fill(Theme.cyan)
                                .frame(width: max(plan.progress > 0 ? 4 : 0, geo.size.width * plan.progress))
                        }
                    }
                    .frame(height: 3)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Theme.surface.opacity(0.55))
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: plan.progress)
        }
    }

    private func currentTitle(_ plan: MissionPlan) -> String {
        if let current = plan.currentTask {
            return "\(current.number). \(current.title)"
        }
        return plan.settledCount == plan.tasks.count ? "All tasks settled — wrapping up" : "Working the plan"
    }
}
