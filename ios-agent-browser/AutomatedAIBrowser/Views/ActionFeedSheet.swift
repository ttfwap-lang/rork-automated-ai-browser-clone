import SwiftUI

/// Resizable mission log: live step cards, thinking indicator, and supervised approvals.
struct ActionFeedSheet: View {
    @Environment(AgentViewModel.self) private var agent
    @State private var visionStep: AgentStep?

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if let plan = agent.plan {
                            MissionPlanCard(plan: plan, note: agent.planNote, isRunning: agent.isRunning)
                        }
                        if !agent.bookmarks.isEmpty {
                            BookmarkStrip()
                        }
                        if agent.steps.isEmpty && !agent.isRunning {
                            emptyHint
                        }
                        ForEach(agent.steps) { step in
                            StepCardView(step: step, onInspect: { visionStep = step })
                                .id(step.id)
                        }
                        if agent.isRunning && agent.isScanningVisual {
                            thinkingCard
                                .id("thinking")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: agent.steps.count) { _, _ in
                    guard let lastID = agent.steps.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.3)) {
                        scrollProxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if agent.pendingStep != nil {
                ApprovalControls(showReasoning: false)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .sheet(item: $visionStep) { step in
            AgentVisionView(step: step)
        }
        .presentationDetents([.height(300), .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .height(300)))
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.surface)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("MISSION LOG")
                .techLabel(11)
                .foregroundStyle(Theme.textPrimary)
            if agent.isRunning {
                PulsingDot(color: agent.phase.color)
            }
            Spacer()
            if let goal = agent.activeGoal {
                Text(goal)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: 180, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.and.magnifyingglass")
                .font(.system(size: 26))
                .foregroundStyle(Theme.textSecondary)
            Text("No steps yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Type a goal below and hit Run — every move the agent makes lands here with its reasoning and the snapshot it saw.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
    }

    private var thinkingCard: some View {
        HStack(spacing: 10) {
            PulsingDot(color: agent.phase.color)
            Text(agent.phase.activityLine)
                .techLabel(10)
                .foregroundStyle(agent.phase.color)
            Spacer()
        }
        .padding(14)
        .background(Theme.elevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(agent.phase.color.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }
}
