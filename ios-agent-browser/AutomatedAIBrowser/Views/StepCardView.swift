import SwiftUI

/// One entry of the live mission log: action, reasoning, result, and the snapshot the AI saw.
/// Tapping the snapshot opens Agent Vision — the badged screenshot + element map audit.
struct StepCardView: View {
    let step: AgentStep
    var onInspect: (() -> Void)? = nil
    @State private var isShowingCandidates = false

    private var statusColor: Color {
        if let verdict = step.verification?.verdict { return verdict.color }
        switch step.status {
        case .proposed: return Theme.amber
        case .rejected: return Theme.red
        case .executed:
            if step.action.kind == .revisePlan { return Theme.violet }
            if step.isHeadStartEntry || step.isReplayEntry { return Theme.amber }
            return Theme.cyan
        case .terminal: return step.action.kind == .fail ? Theme.red : Theme.green
        }
    }

    private var borderColor: Color {
        if let verdict = step.verification?.verdict { return verdict.color.opacity(0.35) }
        if step.status == .proposed { return Theme.amber.opacity(0.3) }
        if step.isHeadStartEntry || step.isReplayEntry { return Theme.amber.opacity(0.3) }
        return Theme.line
    }

    private var numberColor: Color {
        if step.isCheckEntry { return Theme.violet }
        if step.isHeadStartEntry || step.isReplayEntry { return Theme.amber }
        return Theme.textSecondary
    }

    /// Which model decided this step, and how hard the app judged the moment.
    private var metaRow: some View {
        HStack(spacing: 6) {
            if let model = step.modelChoice {
                Text(model.shortLabel)
                    .techLabel(8)
                    .foregroundStyle(model.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(model.color.opacity(0.12), in: Capsule())
            } else if step.isReplayed, !step.isHeadStartEntry, !step.isReplayEntry {
                Text("REPLAYED")
                    .techLabel(8)
                    .foregroundStyle(Theme.amber)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.amber.opacity(0.12), in: Capsule())
            }
            // A repaired step says so on its face: a replay that quietly healed
            // itself is a replay you cannot audit.
            if step.wasHealed {
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
            if let difficulty = step.difficulty {
                HStack(spacing: 3) {
                    Image(systemName: difficulty.icon)
                        .font(.system(size: 8, weight: .bold))
                    Text(difficulty.label)
                        .techLabel(8)
                }
                .foregroundStyle(Theme.textSecondary)
            }
            if let reason = step.routingReason, !reason.isEmpty {
                Text(reason)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textSecondary.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    /// The road not taken: every move weighed on a hard step, with its score.
    private var shortlist: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                Haptics.light()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isShowingCandidates.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "scale.3d")
                        .font(.system(size: 8, weight: .bold))
                    Text("WEIGHED \(step.candidates.count) MOVES")
                        .techLabel(8)
                    Image(systemName: isShowingCandidates ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.violet)
            }
            .buttonStyle(.plain)

            if isShowingCandidates {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(step.candidates.enumerated()), id: \.element.id) { offset, candidate in
                        CandidateRow(candidate: candidate, isWinner: offset == 0)
                    }
                }
                .padding(9)
                .background(Theme.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.top, 2)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(step.displayNumber)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(numberColor)
                    Image(systemName: step.action.kind.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(statusColor)
                    Text(step.action.kind.label)
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

                if step.modelChoice != nil || step.difficulty != nil || step.isReplayed || step.wasHealed {
                    metaRow
                }

                if let title = step.taskTitle, let number = step.taskNumber, !step.isCheckEntry {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 7, weight: .bold))
                        Text("TASK \(number) · \(title)")
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Theme.textSecondary)
                }

                if !step.action.detailText.isEmpty {
                    Text(step.action.detailText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                }

                if !step.reasoning.isEmpty {
                    Text(step.reasoning)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(3)
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

                if step.candidates.count > 1 {
                    shortlist
                }
            }

            if let snapshot = step.displaySnapshot {
                Button {
                    onInspect?()
                } label: {
                    Image(uiImage: snapshot)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 52, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Theme.line, lineWidth: 1)
                        )
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Theme.cyan)
                                .padding(3)
                                .background(Theme.bg.opacity(0.85), in: Circle())
                                .padding(2)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(step.isCheckEntry ? Theme.elevated.opacity(0.85) : Theme.elevated, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }
}
