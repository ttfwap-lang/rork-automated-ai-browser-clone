import SwiftUI

/// One saved replay, as a tappable chip above the command bar.
struct RoutineChip: View {
    let routine: Routine
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: routine.isShaky ? "bolt.trianglebadge.exclamationmark.fill" : "bolt.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(routine.isShaky ? Theme.amber : Theme.cyan)

                VStack(alignment: .leading, spacing: 1) {
                    Text(routine.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(routine.needsInput ? "\(routine.host) · asks first" : routine.host)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                if routine.needsInput {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surface, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    (routine.isShaky ? Theme.amber : Theme.cyan).opacity(0.35),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(PressableButtonStyle())
    }
}
