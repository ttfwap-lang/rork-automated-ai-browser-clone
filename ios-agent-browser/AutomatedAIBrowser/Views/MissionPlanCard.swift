import SwiftUI

/// The pinned mission plan at the top of the log: goal progress, the current
/// task, and — expanded — the whole checklist ticking off live.
struct MissionPlanCard: View {
    let plan: MissionPlan
    let note: String?
    let isRunning: Bool
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            progressBar

            if let current = plan.currentTask, !isExpanded {
                HStack(alignment: .top, spacing: 8) {
                    PulsingDot(color: Theme.cyan)
                        .padding(.top, 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(current.number). \(current.title)")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                        if !current.doneWhen.isEmpty {
                            Text("done when \(current.doneWhen)")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.cyan.opacity(0.75))
                                .lineLimit(2)
                        }
                    }
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(plan.tasks) { task in
                        MissionTaskRow(task: task)
                    }
                }
                .padding(.top, 2)

                if !plan.successStatement.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SUCCESS MEANS")
                            .techLabel(8)
                            .foregroundStyle(Theme.textSecondary)
                        Text(plan.successStatement)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
            }

            if let note, !note.isEmpty {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.top, 2)
                    Text(note)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.amber)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elevated.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.cyan.opacity(isRunning ? 0.22 : 0.1), lineWidth: 1)
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: isExpanded)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: plan)
    }

    private var header: some View {
        Button {
            Haptics.light()
            isExpanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle.portrait.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.cyan)
                Text("MISSION PLAN")
                    .techLabel(10)
                    .foregroundStyle(Theme.textPrimary)

                Spacer(minLength: 0)

                Text("\(plan.settledCount) OF \(plan.tasks.count)")
                    .techLabel(9)
                    .foregroundStyle(Theme.cyan)
                    .contentTransition(.numericText())

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.line)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Theme.cyan, Theme.green],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(plan.progress > 0 ? 6 : 0, geo.size.width * plan.progress))
            }
        }
        .frame(height: 4)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: plan.progress)
    }
}
