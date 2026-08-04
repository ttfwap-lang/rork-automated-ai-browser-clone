import SwiftUI

/// One move from a hard step's shortlist, with the score the app gave it and why
/// it won or lost — the agent's road not taken, in the open.
struct CandidateRow: View {
    let candidate: MoveCandidate
    let isWinner: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isWinner ? "play.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundStyle(isWinner ? Theme.green : Theme.textSecondary.opacity(0.6))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.moveText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isWinner ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(2)

                if !candidate.rationale.isEmpty {
                    Text(candidate.rationale)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }

                if !candidate.note.isEmpty {
                    Text(candidate.note)
                        .font(.system(size: 10))
                        .foregroundStyle(isWinner ? Theme.green.opacity(0.85) : Theme.amber.opacity(0.85))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Text("\(candidate.scorePercent)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(isWinner ? Theme.green : Theme.textSecondary)
        }
    }
}
