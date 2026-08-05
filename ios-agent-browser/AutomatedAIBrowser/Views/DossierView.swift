import SwiftUI

/// Your details, and the plain truth about what happens to them.
///
/// Sealed until Face ID, Touch ID or your passcode passes. While sealed you can
/// still see WHICH facts are on file — that is what the agent knows too — but not
/// what they say.
struct DossierView: View {
    @Environment(Dossier.self) private var dossier
    @Environment(AppSettings.self) private var settings
    @Environment(OnDeviceModel.self) private var onDevice
    @Environment(\.dismiss) private var dismiss
    @State private var confirmWipe = false
    @State private var isUnlocking = false

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                if !dossier.isUnlocked {
                    lockSection
                }
                ForEach(DossierCategory.allCases) { category in
                    section(for: category)
                }
                privacySection
                dangerSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Your Dossier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            .confirmationDialog("Delete every detail you've saved?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Delete Everything", role: .destructive) {
                    dossier.wipe()
                    Haptics.warning()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your details from this iPhone. Nothing was ever stored anywhere else, so there is no copy to delete.")
            }
            .onDisappear {
                // Re-sealed the moment you leave, not just on relaunch.
                dossier.seal()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        @Bindable var settings = settings
        return Section {
            HStack(spacing: 14) {
                ring
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(dossier.filledCount) of \(DossierFieldKind.allCases.count) filled in")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(dossier.canHelpWithForms
                         ? "Enough to start filling forms."
                         : "Add at least three to start filling forms.")
                        .font(.system(size: 12))
                        .foregroundStyle(dossier.canHelpWithForms ? Theme.green : Theme.amber)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)

            Toggle("Offer these to forms", isOn: $settings.dossierEnabled)
        } header: {
            Text("Your Details")
        } footer: {
            Text(settings.dossierEnabled
                 ? "When the agent meets a form, it fills what it can from here in one move. It is told which details exist — never what they say — and the values go straight from this iPhone into the page."
                 : "Switched off. The agent isn't even offered the move, so it can't ask for your details.")
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Theme.line, lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(dossier.completion, 0.02))
                .stroke(
                    dossier.canHelpWithForms ? Theme.cyan : Theme.amber,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: dossier.completion)
            Image(systemName: dossier.isUnlocked ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(dossier.isUnlocked ? Theme.cyan : Theme.textSecondary)
        }
        .frame(width: 46, height: 46)
    }

    // MARK: - The lock

    private var lockSection: some View {
        Section {
            Button {
                Haptics.light()
                isUnlocking = true
                Task {
                    await dossier.unlock()
                    isUnlocking = false
                    if dossier.isUnlocked { Haptics.success() }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "faceid")
                        .font(.system(size: 14, weight: .semibold))
                    Text(isUnlocking ? "Waiting for you…" : "Unlock with \(DossierGuard.methodName())")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.cyan)
            }
            .disabled(isUnlocking)

            if let note = dossier.lockNote {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.amber)
            }
        } header: {
            Text("Locked")
        } footer: {
            Text("Your details are hidden until you prove it's you. The agent can still use them — this lock is here so that someone holding your unlocked iPhone can't simply read your address and your salary expectation off the screen.")
        }
    }

    // MARK: - The facts

    private func section(for category: DossierCategory) -> some View {
        let kinds = DossierFieldKind.allCases.filter { $0.category == category }
        return Section {
            ForEach(kinds) { kind in
                DossierFieldRow(
                    kind: kind,
                    isUnlocked: dossier.isUnlocked,
                    storedValue: dossier.editableValue(for: kind),
                    maskedValue: dossier.masked(kind)
                ) { value in
                    dossier.set(value, for: kind)
                }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 9, weight: .bold))
                Text(category.title)
            }
        } footer: {
            Text(category.caption)
        }
    }

    // MARK: - The promises

    private var privacySection: some View {
        Section {
            promise("lock.shield.fill", "Never sent to any AI", "The agent is handed the NAMES of your details, never the values. A value's only destination is the field it belongs in.")
            promise("nosign", "Secrets can't be stored here", "There is no box for a password, a card number or a security code — so nothing can talk the agent into typing one. Those are always yours to type.")
            promise("iphone.gen3", "Stays on this iPhone", dossier.usesFileFallback
                    ? "Held in this app's private, encrypted storage. Not backed up to anyone's server."
                    : "Held in this iPhone's keychain, readable only while your phone is unlocked, and never backed up off the device.")
            promise("pencil.slash", "Nothing is invented", "A field the dossier has nothing for is left blank and reported as blank. The agent is never allowed to make up a fact about you.")
            if onDevice.isReady {
                promise("bolt.fill", "Matching costs nothing", "Fields are matched by what the page declares, then by their own labels, then by your iPhone's own model. None of it is a paid call.")
            }
        } header: {
            Text("What Happens To These")
        } footer: {
            if let note = dossier.storageNote {
                Text(note)
            }
        }
    }

    private func promise(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.cyan)
                .frame(width: 20)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                confirmWipe = true
            } label: {
                Text("Delete all my details")
            }
            .disabled(dossier.isEmpty)
        } footer: {
            Text("Honest limits: date pickers, checkboxes and yes/no choices are left to the agent's normal moves for now, and any field that submits, buys or sends always waits for you.")
        }
    }
}
