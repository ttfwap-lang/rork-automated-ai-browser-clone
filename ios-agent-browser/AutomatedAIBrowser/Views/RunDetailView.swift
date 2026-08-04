import SwiftUI

/// Full review of one saved run: goal, outcome, and every step.
struct RunDetailView: View {
    let run: AgentRun

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                summaryCard

                if let plan = run.plan {
                    planCard(plan)
                }

                ForEach(run.steps) { step in
                    PersistedStepCard(step: step)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.bg)
        .navigationTitle("Run Review")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: run.outcome.icon)
                    .font(.system(size: 11, weight: .bold))
                Text(run.outcome.label)
                    .techLabel(10)
                Spacer()
                Text("\(run.browserStepCount) STEPS")
                    .techLabel(9)
                    .foregroundStyle(Theme.textSecondary)
            }
            .foregroundStyle(run.outcome.color)

            if let verdict = run.verdict {
                HStack(spacing: 5) {
                    Image(systemName: verdict.icon)
                        .font(.system(size: 8, weight: .bold))
                    Text("CHECK: \(verdict.label)")
                        .techLabel(8)
                }
                .foregroundStyle(verdict.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(verdict.color.opacity(0.12), in: Capsule())
            }

            Text(run.goal)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(run.summary)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !statLines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(statLines, id: \.self) { line in
                        Text(line)
                            .techLabel(8)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            Text(run.date, format: .dateTime.day().month().year().hour().minute())
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(run.outcome.color.opacity(0.3), lineWidth: 1)
        )
    }

    /// Honest accounting: how the steps split between models, and what judgment cost.
    private var statLines: [String] {
        var lines: [String] = []
        if let split = run.routingSplit {
            lines.append(split.uppercased())
        }
        if let breakdown = run.callBreakdown {
            lines.append(breakdown.uppercased())
        }
        if let rewinds = run.rewinds, rewinds > 0 {
            lines.append("\(rewinds) REWIND\(rewinds == 1 ? "" : "S")")
        }
        if let weighed = run.weighedMoves, weighed > 0 {
            lines.append("\(weighed) MOVES WEIGHED")
        }
        if let memory = run.memoryLine {
            lines.append("MEMORY: \(memory.uppercased())")
        }
        if let routine = run.routineLine {
            lines.append("REPLAY: \(routine.uppercased())")
        }
        if let cautions = run.cautionLine {
            lines.append(cautions.uppercased())
        }
        return lines
    }

    /// The checklist as it stood when the run ended — what was planned, done, and skipped.
    private func planCard(_ plan: MissionPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle.portrait.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("MISSION PLAN — \(plan.settledCount) OF \(plan.tasks.count) SETTLED")
                    .techLabel(9)
            }
            .foregroundStyle(Theme.cyan)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(plan.tasks) { task in
                    MissionTaskRow(task: task)
                }
            }

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
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elevated.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }
}
