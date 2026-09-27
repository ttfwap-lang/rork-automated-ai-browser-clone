import SwiftUI

/// The agent's question to you, with its suggested answers and room for your
/// own. The run waits here; skipping lets the agent carry on with its best
/// judgement.
struct QuestionCard: View {
    @Environment(AgentViewModel.self) private var agent
    @State private var draft = ""
    @FocusState private var isTyping: Bool

    var body: some View {
        if let question = agent.pendingQuestion {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: AgentActionKind.askUser.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                    Text("THE AGENT ASKS")
                        .techLabel(10)
                        .foregroundStyle(Theme.amber)
                    Spacer(minLength: 0)
                }

                Text(question.text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if !question.choices.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(question.choices, id: \.self) { choice in
                                Button {
                                    agent.answerQuestion(choice)
                                } label: {
                                    Text(choice)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.cyan)
                                        .padding(.horizontal, 12)
                                        .frame(height: 34)
                                        .background(Theme.cyan.opacity(0.12), in: Capsule())
                                        .overlay(Capsule().strokeBorder(Theme.cyan.opacity(0.4), lineWidth: 1))
                                }
                                .buttonStyle(PressableButtonStyle())
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField("Your answer", text: $draft)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textPrimary)
                        .focused($isTyping)
                        .submitLabel(.send)
                        .onSubmit(send)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))

                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(draft.trimmed.isEmpty ? Theme.textSecondary : Theme.cyan)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(draft.trimmed.isEmpty)
                }

                Button {
                    agent.answerQuestion(nil)
                } label: {
                    Text("SKIP — USE YOUR BEST JUDGEMENT")
                        .techLabel(9)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(12)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Theme.amber.opacity(0.35), lineWidth: 1)
            )
            .onChange(of: question.id) { _, _ in
                draft = ""
            }
        }
    }

    private func send() {
        let answer = draft.trimmed
        guard !answer.isEmpty else { return }
        isTyping = false
        draft = ""
        agent.answerQuestion(answer)
    }
}
