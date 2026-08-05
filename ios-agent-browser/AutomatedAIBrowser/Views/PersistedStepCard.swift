import SwiftUI

/// Step card for reviewing a saved run, with its stored thumbnail.
struct PersistedStepCard: View {
    @Environment(HistoryStore.self) private var history
    let step: PersistedStep

    private var statusColor: Color {
        // Your own objection reads as yours at a glance, whatever its status.
        if step.kind == .mistake { return Theme.red }
        if let verdict = step.verdict { return verdict.color }
        switch step.status {
        case .proposed: return Theme.amber
        case .rejected: return Theme.red
        case .executed:
            if step.kind == .revisePlan { return Theme.violet }
            if step.kind == .headStart || step.kind == .replay { return Theme.amber }
            return Theme.cyan
        case .terminal: return step.kind == .fail ? Theme.red : Theme.green
        }
    }

    private var numberColor: Color {
        if step.kind == .verify { return Theme.violet }
        if step.kind == .mistake { return Theme.red }
        if step.kind == .headStart || step.kind == .replay { return Theme.amber }
        return Theme.textSecondary
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(step.displayNumber)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(numberColor)
                    Image(systemName: step.kind.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(statusColor)
                    Text(step.kind.label)
                        .techLabel(11)
                        .foregroundStyle(statusColor)
                    Spacer(minLength: 0)
                    Text(step.status.label)
                        .techLabel(8)
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.12), in: Capsule())
                }

                HStack(spacing: 6) {
                    if let model = step.model {
                        Text(model.shortLabel)
                            .techLabel(8)
                            .foregroundStyle(model.color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(model.color.opacity(0.12), in: Capsule())
                    } else if step.wasReplayed == true, step.kind != .headStart, step.kind != .replay {
                        Text("REPLAYED")
                            .techLabel(8)
                            .foregroundStyle(Theme.amber)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.amber.opacity(0.12), in: Capsule())
                    }
                    if step.wasHealed == true {
                        HStack(spacing: 3) {
                            Image(systemName: "bandage.fill")
                                .font(.system(size: 8, weight: .bold))
                            Text("HEALED")
                                .techLabel(8)
                        }
                        .foregroundStyle(Theme.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.green.opacity(0.12), in: Capsule())
                    }
                }

                if let title = step.taskTitle, let number = step.taskNumber, step.kind != .verify {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 7, weight: .bold))
                        Text("TASK \(number) · \(title)")
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Theme.textSecondary)
                }

                if !step.actionDetail.isEmpty {
                    Text(step.actionDetail)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                }

                if !step.reasoning.isEmpty {
                    Text(step.reasoning)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(4)
                }

                if let result = step.result, !result.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.top, 2)
                        Text(result)
                            .lineLimit(2)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.cyan.opacity(0.85))
                }
            }

            if let file = step.thumbnailFile, let image = history.thumbnail(named: file) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 52, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Theme.line, lineWidth: 1)
                    )
            }
        }
        .padding(12)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }
}
