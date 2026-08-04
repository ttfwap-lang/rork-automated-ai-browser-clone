import SwiftUI

/// One saved run in the History list.
struct HistoryRow: View {
    let run: AgentRun

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(run.goal)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: run.outcome.icon)
                        .font(.system(size: 8, weight: .bold))
                    Text(run.outcome.label)
                        .techLabel(8)
                }
                .foregroundStyle(run.outcome.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(run.outcome.color.opacity(0.12), in: Capsule())

                Text("\(run.steps.count) STEPS")
                    .techLabel(8)
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                Text(run.date, format: .relative(presentation: .named))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}
