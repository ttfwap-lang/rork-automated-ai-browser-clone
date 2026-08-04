import SwiftUI

/// Offered the moment a run is confirmed: turn what just worked into something
/// you can run again with one tap.
///
/// It is deliberately offered here rather than buried in a menu, because this is
/// the one moment the user knows exactly what the route was worth.
struct SaveRoutineSheet: View {
    @Environment(AgentViewModel.self) private var agent
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    nameField
                    explanation
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Theme.bg)
            .navigationTitle("Save as One-Tap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        agent.saveRoutine(title: title)
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(title.trimmed.isEmpty ? Theme.textSecondary : Theme.cyan)
                    .disabled(title.trimmed.isEmpty)
                }
            }
            .onAppear {
                if title.isEmpty { title = agent.suggestedRoutineTitle }
                titleFocused = true
            }
        }
        .presentationDetents([.medium])
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What do you call this?")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            TextField("Name", text: $title)
                .font(.system(size: 16))
                .foregroundStyle(Theme.textPrimary)
                .focused($titleFocused)
                .submitLabel(.done)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(titleFocused ? Theme.cyan.opacity(0.5) : Theme.line, lineWidth: 1)
                )
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(
                icon: "bolt.fill",
                tint: Theme.cyan,
                text: "The moves that just worked are saved in order, so next time this is one tap from the home screen."
            )
            row(
                icon: "text.cursor",
                tint: Theme.violet,
                text: "Anything you typed becomes a blank it asks you for — the value itself is never saved."
            )
            row(
                icon: "bandage.fill",
                tint: Theme.green,
                text: "If the site moves a control later, the replay repairs that step and remembers the fix."
            )
            row(
                icon: "hand.raised.fill",
                tint: Theme.amber,
                text: "Any step that submits, buys, sends or deletes always stops and asks you first."
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elevated.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    private func row(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 14)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
