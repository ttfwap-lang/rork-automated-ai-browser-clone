import SwiftUI

/// Cockpit bottom bar: goal input, run/stop button, mode toggle, and mission log access.
struct CommandBar: View {
    @Environment(AgentViewModel.self) private var agent
    @FocusState private var goalFocused: Bool

    var body: some View {
        @Bindable var agent = agent
        VStack(spacing: 10) {
            if !agent.isRunning && agent.goalText.isEmpty {
                SuggestionChips { goal in
                    agent.goalText = goal
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundStyle(agent.isRunning ? Theme.cyan : Theme.textSecondary)
                    TextField("Tell the agent what to do…", text: $agent.goalText, axis: .vertical)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1...3)
                        .focused($goalFocused)
                        .submitLabel(.go)
                        .onSubmit { startRun() }
                        .disabled(agent.isRunning)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .hudGlass(.rect(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(goalFocused ? Theme.cyan.opacity(0.5) : Theme.line, lineWidth: 1)
                )

                runStopButton
            }

            HStack {
                ModeToggle(mode: $agent.mode, locked: agent.isRunning)
                Spacer()
                Button {
                    agent.isFeedPresented = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.rectangle.fill")
                            .font(.system(size: 10))
                        Text("LOG")
                            .techLabel(10)
                        if !agent.steps.isEmpty {
                            Text("\(agent.steps.count)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.cyan, in: Capsule())
                        }
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                }
                .buttonStyle(PressableButtonStyle())
                .controlGlass(.capsule)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: agent.goalText.isEmpty)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: agent.isRunning)
    }

    private var runStopButton: some View {
        Button {
            if agent.isRunning {
                agent.stopRun()
            } else {
                startRun()
            }
        } label: {
            Image(systemName: agent.isRunning ? "stop.fill" : "arrow.up")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(agent.isRunning ? Theme.red : Color.black)
                .frame(width: 52, height: 46)
                .shadow(color: agent.isRunning ? .clear : Theme.cyan.opacity(0.45), radius: 10, y: 2)
        }
        .buttonStyle(PressableButtonStyle())
        // The one tinted control in the cockpit: the thing that starts and stops
        // the agent. Everything else stays untinted so this reads as primary.
        .controlGlass(
            .rect(cornerRadius: 16),
            tint: agent.isRunning ? Theme.red : Theme.cyan
        )
        .disabled(!agent.isRunning && agent.goalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(!agent.isRunning && agent.goalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
    }

    private func startRun() {
        goalFocused = false
        agent.startRun()
    }
}
