import SwiftUI

/// Past runs saved on this device.
struct HistoryView: View {
    @Environment(HistoryStore.self) private var history
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Group {
                if history.runs.isEmpty {
                    emptyState
                } else {
                    runList
                }
            }
            .background(Theme.bg)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !history.runs.isEmpty {
                        Button("Clear", role: .destructive) {
                            confirmClear = true
                        }
                        .foregroundStyle(Theme.red)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .navigationDestination(for: AgentRun.self) { run in
                RunDetailView(run: run)
            }
            .confirmationDialog("Delete all saved runs?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) {
                    history.clearAll()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var runList: some View {
        List {
            ForEach(history.runs) { run in
                NavigationLink(value: run) {
                    HistoryRow(run: run)
                }
                .listRowBackground(Theme.surface)
                .listRowSeparatorTint(Theme.line)
            }
            .onDelete { offsets in
                history.delete(at: offsets)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 34))
                .foregroundStyle(Theme.textSecondary)
            Text("No runs yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Finished missions land here with every step, snapshot, and outcome.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
