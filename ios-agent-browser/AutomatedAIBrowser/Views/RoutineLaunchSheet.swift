import SwiftUI

/// Fills in the blanks a saved replay left behind, then runs it.
///
/// This sheet is the visible half of the privacy guarantee: the route knows
/// which field to use and what kind of thing goes in it, and asks you for the
/// value every time because it never kept the last one.
struct RoutineLaunchSheet: View {
    @Environment(AgentViewModel.self) private var agent
    @Environment(\.dismiss) private var dismiss
    let routine: Routine

    @State private var values: [UUID: String] = [:]
    @FocusState private var focused: UUID?

    private var isReady: Bool { routine.isReadyToRun(with: values) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    fields
                    preview
                    privacyNote
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Theme.bg)
            .navigationTitle("Run Replay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Run") { run() }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isReady ? Theme.cyan : Theme.textSecondary)
                        .disabled(!isReady)
                }
            }
            .onAppear {
                focused = routine.blanks.first?.id
            }
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("SAVED REPLAY")
                    .techLabel(10)
                Spacer()
                Text(routine.host)
                    .techLabel(9)
                    .foregroundStyle(Theme.textSecondary)
            }
            .foregroundStyle(Theme.cyan)

            Text(routine.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(routine.subtitle)
                .techLabel(8)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.cyan.opacity(0.3), lineWidth: 1)
        )
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(routine.blanks) { blank in
                VStack(alignment: .leading, spacing: 5) {
                    Text(blank.question)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    TextField(blank.label, text: binding(for: blank))
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textPrimary)
                        .textInputAutocapitalization(.never)
                        .focused($focused, equals: blank.id)
                        .submitLabel(.done)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(focused == blank.id ? Theme.cyan.opacity(0.5) : Theme.line, lineWidth: 1)
                        )
                }
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 10, weight: .semibold))
                Text("WHAT IT WILL DO")
                    .techLabel(9)
            }
            .foregroundStyle(Theme.textSecondary)

            Text(routine.goal(filling: values))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(routine.routeLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if routine.hasCommittingMove {
                Text("One of these steps commits, so it will stop and ask you before it runs — whatever mode you are in.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
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

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.green)
                .padding(.top, 1)
            Text("This replay asks every time because it never kept what you typed last time. What you enter here is used for this run and then dropped.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private func binding(for blank: RoutineBlank) -> Binding<String> {
        Binding(
            get: { values[blank.id] ?? "" },
            set: { values[blank.id] = $0 }
        )
    }

    private func run() {
        guard isReady else { return }
        let filled = values
        dismiss()
        agent.startRoutine(routine, values: filled)
    }
}
