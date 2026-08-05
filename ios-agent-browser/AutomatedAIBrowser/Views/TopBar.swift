import SwiftUI

/// Custom app header: brand mark plus dossier, memory, history and settings
/// entry points.
struct TopBar: View {
    @Environment(AgentViewModel.self) private var agent
    @Environment(Dossier.self) private var dossier
    let onDossier: () -> Void
    let onMemory: () -> Void
    let onHistory: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.cyan)
                    .frame(width: 8, height: 8)
                    .shadow(color: Theme.cyan.opacity(0.8), radius: 5)
                Text("AGENT BROWSER")
                    .techLabel(12)
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            // Badged when your details are ready to be used, so the one piece of
            // setup that unlocks form filling is never invisible.
            headerButton(
                dossier.canHelpWithForms ? "person.text.rectangle.fill" : "person.text.rectangle",
                tint: dossier.canHelpWithForms ? Theme.cyan.opacity(0.9) : Theme.textSecondary,
                action: onDossier
            )
            headerButton("brain", action: onMemory)
            headerButton("clock.arrow.circlepath", action: onHistory)
            headerButton("gearshape.fill", action: onSettings)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func headerButton(
        _ systemName: String,
        tint: Color = Theme.textSecondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}
