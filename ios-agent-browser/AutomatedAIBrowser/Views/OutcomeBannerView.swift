import SwiftUI

/// End-of-run result banner with the AI's summary or the failure reason.
struct OutcomeBannerView: View {
    @Environment(AgentViewModel.self) private var agent
    let banner: OutcomeBanner
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            summary
            // Offered here because this is the moment the user knows exactly what
            // the route that just worked was worth.
            if agent.canSaveRoutine {
                saveButton
            }
        }
        .padding(12)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(banner.outcome.color.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .sheet(isPresented: $isSaving) {
            SaveRoutineSheet()
        }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: banner.outcome.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(banner.outcome.color)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(banner.outcome.label)
                    .techLabel(10)
                    .foregroundStyle(banner.outcome.color)
                Text(banner.message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    agent.dismissBanner()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Theme.surface, in: Circle())
            }
            .buttonStyle(PressableButtonStyle())
        }
    }

    private var saveButton: some View {
        Button {
            Haptics.light()
            isSaving = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "bolt.badge.clock.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("SAVE AS ONE-TAP REPLAY")
                    .techLabel(9)
            }
            .foregroundStyle(Theme.cyan)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.cyan.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.cyan.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(PressableButtonStyle())
    }
}
