import SwiftUI

/// The agent's thinking, live, over the page it is working on.
///
/// The point of this panel is that watching the browser and understanding WHY it
/// is doing something should not be two different screens. Everything on it is
/// something the agent actually said or did — the reasoning is its own words, the
/// result is what the page really replied. Nothing here is a synthesised inner
/// monologue, because a plausible-sounding narration of a wrong move is worse
/// than no narration at all.
struct LiveThinkingPanel: View {
    @Environment(AgentViewModel.self) private var agent
    @State private var isExpanded = true
    @State private var isFlagging = false
    /// Bumped when you flag a mistake, to pulse the panel red once.
    @State private var flashCount = 0

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expanded
            } else {
                collapsedPill
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isExpanded)
        .sheet(isPresented: $isFlagging) {
            MistakeSheet()
        }
    }

    // MARK: - Expanded

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            if let plan = agent.plan, !plan.tasks.isEmpty {
                taskRail(plan)
            }
            thought
            if let result = agent.liveResult {
                resultLine(result)
            }
            badges
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .background(Theme.bg.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(edgeColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Amber while the agent is waiting on you, red for a beat after you flag a
    /// mistake, cyan otherwise.
    private var edgeColor: Color {
        if flashCount > 0 { return Theme.red.opacity(0.75) }
        if agent.phase == .awaitingApproval { return Theme.amber.opacity(0.55) }
        return Theme.cyan.opacity(0.32)
    }

    private var header: some View {
        HStack(spacing: 8) {
            PulsingDot(color: agent.phase.color)
            Text(agent.phase.label)
                .techLabel(9.5)
                .foregroundStyle(agent.phase.color)
                .contentTransition(.opacity)

            if agent.awaitingReplan {
                statusChip("RETHINKING", icon: "arrow.triangle.2.circlepath", tint: Theme.red)
            }

            Spacer(minLength: 0)

            Text("STEP \(agent.currentStepIndex)/\(agent.maxStepsThisRun)")
                .techLabel(9)
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.numericText())

            Button {
                Haptics.light()
                isExpanded = false
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Theme.surface.opacity(0.8), in: Circle())
            }
            .buttonStyle(PressableButtonStyle())
        }
        .animation(.easeInOut(duration: 0.2), value: agent.phase)
    }

    /// The plan as a rail of pills — the mission at a glance, ticking over.
    private func taskRail(_ plan: MissionPlan) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                ForEach(plan.tasks) { task in
                    HStack(spacing: 3) {
                        Image(systemName: task.state.icon)
                            .font(.system(size: 7, weight: .bold))
                        Text("\(task.number)")
                            .techLabel(8)
                    }
                    .foregroundStyle(task.state.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(task.state.color.opacity(task.state == .current ? 0.18 : 0.09), in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(
                            task.state == .current ? task.state.color.opacity(0.5) : .clear,
                            lineWidth: 1
                        )
                    )
                    .scaleEffect(task.state == .current ? 1.06 : 1)
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(height: 20)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: plan.settledCount)
    }

    /// The agent's own words, then the move in plain language. When the agent said
    /// nothing, this shows the phase's own activity line rather than inventing a
    /// thought for it.
    private var thought: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let thought = agent.liveThought {
                TypewriterText(text: thought)
            } else {
                Text(agent.phase.activityLine)
                    .techLabel(10)
                    .foregroundStyle(Theme.textSecondary)
            }

            if let move = agent.liveMove {
                HStack(spacing: 6) {
                    Image(systemName: agent.liveMoveIsYours ? "hand.raised.slash.fill" : "arrow.turn.down.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(agent.liveMoveIsYours ? Theme.red : Theme.cyan)
                    Text(move)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(agent.liveMoveIsYours ? Theme.red : Theme.textPrimary)
                        .lineLimit(1)
                    if agent.liveMoveWasHealed {
                        Image(systemName: "bandage.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.green)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// What the page actually did, coloured honestly rather than optimistically.
    private func resultLine(_ result: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 7, weight: .bold))
                .padding(.top, 2)
            Text(result)
                .lineLimit(2)
        }
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundStyle(Self.resultColor(result))
    }

    /// Green when the page reacted, amber when it ran but nothing moved, red when
    /// it failed. "Nothing moved" is checked first because it is a specific case
    /// of failure, and calling it red would overstate what went wrong.
    static func resultColor(_ result: String) -> Color {
        if ReactionWatch.readsAsNoReaction(result) { return Theme.amber }
        if ReactionWatch.readsAsFailure(result) { return Theme.red }
        return Theme.green
    }

    /// Only ever shows what is actually true of this run.
    private var badges: some View {
        HStack(spacing: 6) {
            if let title = agent.activeRoutineTitle {
                chip(title, icon: "bolt.badge.clock.fill", tint: Theme.amber)
            }
            if let healed = agent.healTally {
                chip(healed, icon: "bandage.fill", tint: Theme.green)
            }
            if let free = agent.freeTally {
                chip(free, icon: "iphone", tint: Theme.cyan)
            }
            if let cautions = agent.cautionTally {
                chip(cautions, icon: "exclamationmark.triangle.fill", tint: Theme.violet)
            }
            if agent.totalCallCount > 0 {
                chip("\(agent.totalCallCount) PAID", icon: "creditcard.fill", tint: Theme.textSecondary)
            }

            Spacer(minLength: 0)

            if agent.canFlagMistake {
                mistakeButton
            }
        }
    }

    private var mistakeButton: some View {
        Button {
            Haptics.warning()
            isFlagging = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "hand.raised.slash.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("MISTAKE")
                    .techLabel(9)
            }
            .foregroundStyle(Theme.red)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(Theme.red.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.red.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func chip(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 7.5, weight: .bold))
            Text(text.uppercased())
                .techLabel(8)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private func statusChip(_ text: String, icon: String, tint: Color) -> some View {
        chip(text, icon: icon, tint: tint)
    }

    // MARK: - Collapsed

    private var collapsedPill: some View {
        HStack {
            Spacer()
            Button {
                Haptics.light()
                isExpanded = true
            } label: {
                HStack(spacing: 6) {
                    PulsingDot(color: agent.phase.color)
                    Text(agent.phase.label)
                        .techLabel(9)
                        .foregroundStyle(agent.phase.color)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background(.ultraThinMaterial, in: Capsule())
                .background(Theme.bg.opacity(0.55), in: Capsule())
                .overlay(Capsule().strokeBorder(edgeColor, lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
            }
            .buttonStyle(PressableButtonStyle())
            Spacer()
        }
        .padding(.top, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
