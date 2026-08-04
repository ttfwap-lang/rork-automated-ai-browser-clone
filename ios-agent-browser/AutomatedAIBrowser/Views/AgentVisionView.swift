import SwiftUI

/// Agent Vision: the audit view showing exactly what the AI received for one
/// step — the badged screenshot and the written element map.
struct AgentVisionView: View {
    let step: AgentStep
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    actionSummary
                    if let verification = step.verification {
                        verdictSection(verification)
                    }
                    if let snapshot = step.snapshot {
                        Image(uiImage: snapshot)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Theme.line, lineWidth: 1)
                            )
                    }
                    if step.pageMap != nil {
                        legend
                    }
                    if step.overviewImage != nil {
                        overviewSection
                    }
                    if !step.isCheckEntry {
                        mapSection
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle(step.isCheckEntry ? "Independent Check — Step \(step.index)" : "Agent Vision — Step \(step.index)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.cyan)
                }
            }
        }
        .presentationBackground(Theme.bg)
        .preferredColorScheme(.dark)
    }

    private var actionSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: step.action.kind.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(step.action.kind.label)
                    .techLabel(11)
                Spacer()
                Text(step.isCheckEntry ? "WHAT THE CHECK SAW" : "WHAT THE AI SAW")
                    .techLabel(8)
                    .foregroundStyle(Theme.textSecondary)
            }
            .foregroundStyle(step.verification?.verdict.color ?? Theme.cyan)

            if !step.action.detailText.isEmpty {
                Text(step.action.detailText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
            }
            if !step.reasoning.isEmpty {
                Text(step.reasoning)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    /// The independent check's ruling, openable like any other step so the
    /// checker itself can be audited.
    private func verdictSection(_ verification: VerificationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: verification.verdict.icon)
                    .font(.system(size: 11, weight: .bold))
                Text(verification.verdict.label)
                    .techLabel(10)
                Spacer()
                if let by = verification.checkedBy, !by.isEmpty {
                    Text(by)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .foregroundStyle(verification.verdict.color)

            labelled("EVIDENCE", verification.evidence)
            if let objection = verification.objection, !objection.isEmpty {
                labelled("OBJECTION", objection)
            }
            if let corrected = verification.correctedAnswer, !corrected.isEmpty {
                labelled("CORRECTED ANSWER", corrected)
            }

            Text("This check never saw the agent's own reasoning — only the goal, the success statement, the page, and a bare list of moves.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(verification.verdict.color.opacity(0.3), lineWidth: 1)
        )
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .techLabel(8)
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendDot(color: Theme.cyan, label: "BTN")
            legendDot(color: Color(red: 0.36, green: 0.64, blue: 1.0), label: "LINK")
            legendDot(color: Theme.amber, label: "FIELD")
            legendDot(color: Color(red: 1.0, green: 0.42, blue: 0.71), label: "TOGGLE")
            legendDot(color: Theme.green, label: "DROP")
            legendDot(color: Color(red: 0.73, green: 0.77, blue: 0.82), label: "OTHER")
            Spacer(minLength: 0)
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .techLabel(7)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.expand.vertical")
                    .font(.system(size: 10, weight: .semibold))
                Text("WHOLE-PAGE OVERVIEW — ALSO SEEN THIS STEP")
                    .techLabel(9)
            }
            .foregroundStyle(Theme.green)

            if let note = step.overviewNote, !note.isEmpty {
                Text("\(note) · orientation only — no badges")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            if let overview = step.overviewImage {
                Image(uiImage: overview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Theme.green.opacity(0.25), lineWidth: 1)
                    )
            }
        }
    }

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ELEMENT MAP")
                .techLabel(10)
                .foregroundStyle(Theme.textSecondary)
            Text(step.pageMap ?? "Page scan was unavailable for this step — the agent worked from the raw screenshot alone (no badges, coordinate taps only).")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(step.pageMap == nil ? Theme.amber : Theme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
        }
    }
}
