import SwiftUI

/// One checklist task in the mission plan card. Finished tasks dim back, the
/// current task glows with a pulsing dot, skipped tasks are struck through with
/// their reason — the log never claims work that did not happen.
struct MissionTaskRow: View {
    let task: MissionTask

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            marker
                .frame(width: 14, height: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 12.5, weight: task.state == .current ? .semibold : .regular))
                    .foregroundStyle(titleColor)
                    .strikethrough(task.state == .skipped, color: Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if task.state == .current, !task.doneWhen.isEmpty {
                    Text("done when \(task.doneWhen)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.cyan.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if task.state == .skipped, let reason = task.skipReason, !reason.isEmpty {
                    Text(reason)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textSecondary.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            Text("\(task.number)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
        }
        .opacity(task.state == .pending ? 0.55 : 1)
    }

    private var titleColor: Color {
        switch task.state {
        case .current: Theme.textPrimary
        case .done: Theme.textSecondary
        case .pending: Theme.textPrimary
        case .skipped: Theme.textSecondary
        }
    }

    @ViewBuilder
    private var marker: some View {
        switch task.state {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.green)
                .transition(.scale.combined(with: .opacity))
        case .current:
            PulsingDot(color: Theme.cyan)
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary.opacity(0.5))
        case .skipped:
            Image(systemName: "minus.circle")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary.opacity(0.7))
        }
    }
}
