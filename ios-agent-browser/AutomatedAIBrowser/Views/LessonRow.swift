import SwiftUI

/// One caution the agent has learned about a site, with how often it has held up.
struct LessonRow: View {
    let lesson: SiteLesson

    private var tint: Color {
        if lesson.isRetired { return Theme.textSecondary }
        return lesson.sightings > 1 ? Theme.amber : Theme.textSecondary
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: lesson.kind.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(lesson.kind.label)
                        .techLabel(8)
                        .foregroundStyle(tint)
                    Spacer(minLength: 0)
                    if lesson.isRetired {
                        Text("NO LONGER USED")
                            .techLabel(7)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.textSecondary.opacity(0.12), in: Capsule())
                    }
                }

                Text(lesson.caution)
                    .font(.system(size: 12.5))
                    .foregroundStyle(lesson.isRetired ? Theme.textSecondary : Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(lesson.recordLine.uppercased())
                    .techLabel(7)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 3)
    }
}
