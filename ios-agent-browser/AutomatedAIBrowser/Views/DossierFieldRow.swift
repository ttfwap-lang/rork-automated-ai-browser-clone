import SwiftUI

/// One fact in the dossier editor.
///
/// The value is held locally while you type and written to the dossier when you
/// leave the field, so a long form does not hit the Keychain on every keystroke.
struct DossierFieldRow: View {
    let kind: DossierFieldKind
    let isUnlocked: Bool
    let storedValue: String
    let maskedValue: String
    let onCommit: (String) -> Void

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(kind.label.uppercased())
                    .techLabel(9)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                if !maskedValue.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.green)
                }
            }

            if isUnlocked {
                field
            } else {
                Text(maskedValue.isEmpty ? "not set" : maskedValue)
                    .font(.system(size: 14, design: maskedValue.isEmpty ? .default : .monospaced))
                    .foregroundStyle(maskedValue.isEmpty ? Theme.textSecondary.opacity(0.6) : Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 4)
        .onAppear { draft = storedValue }
        .onChange(of: isUnlocked) { _, unlocked in
            if unlocked { draft = storedValue }
        }
    }

    @ViewBuilder
    private var field: some View {
        if kind.isLongForm {
            TextField(kind.placeholder, text: $draft, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    if !focused { onCommit(draft) }
                }
                .onSubmit { onCommit(draft) }
        } else {
            TextField(kind.placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled(shouldDisableAutocorrect)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    if !focused { onCommit(draft) }
                }
                .onSubmit { onCommit(draft) }
        }
    }

    /// Lets iOS offer the right thing from its own autofill, so filling the
    /// dossier is itself quick.
    private var contentType: UITextContentType? {
        switch kind {
        case .fullName: .name
        case .firstName: .givenName
        case .lastName: .familyName
        case .email: .emailAddress
        case .phone: .telephoneNumber
        case .addressLine1: .streetAddressLine1
        case .addressLine2: .streetAddressLine2
        case .city: .addressCity
        case .region: .addressState
        case .postcode: .postalCode
        case .country: .countryName
        case .currentEmployer: .organizationName
        case .currentTitle: .jobTitle
        case .linkedIn, .portfolio, .github: .URL
        default: nil
        }
    }

    private var keyboard: UIKeyboardType {
        switch kind {
        case .email: .emailAddress
        case .phone: .phonePad
        case .linkedIn, .portfolio, .github: .URL
        case .yearsExperience, .graduationYear, .salaryExpectation: .numbersAndPunctuation
        default: .default
        }
    }

    private var autocapitalization: TextInputAutocapitalization {
        switch kind {
        case .email, .linkedIn, .portfolio, .github, .pronouns: .never
        default: .words
        }
    }

    private var shouldDisableAutocorrect: Bool {
        switch kind {
        case .email, .linkedIn, .portfolio, .github, .postcode: true
        default: false
        }
    }
}
