import SwiftUI

/// AUTO / SUPERVISED pill switch. Locked while a run is active.
struct ModeToggle: View {
    @Binding var mode: AgentMode
    let locked: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AgentMode.allCases) { candidate in
                Button {
                    guard !locked, mode != candidate else { return }
                    Haptics.light()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        mode = candidate
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: candidate.icon)
                            .font(.system(size: 9, weight: .bold))
                        Text(candidate.label)
                            .techLabel(9)
                    }
                    .foregroundStyle(mode == candidate ? Color.black : Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(mode == candidate ? Theme.cyan : Color.clear)
                    )
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(3)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        .opacity(locked ? 0.5 : 1)
    }
}
