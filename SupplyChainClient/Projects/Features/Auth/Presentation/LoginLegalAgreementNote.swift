import SwiftUI

/// Checkbox + links for Terms of Service and Privacy Policy on the login screen.
struct LoginLegalAgreementNote: View {
    let hasAgreed: Bool
    var shakeTrigger: Int
    var showsValidationHighlight: Bool
    let onOpenAgreementPrompt: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                onOpenAgreementPrompt()
            } label: {
                Image(systemName: hasAgreed ? "checkmark.square.fill" : "square")
                    .font(.body)
                    .foregroundStyle(hasAgreed ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("auth.login.legal.toggle_accessibility"))

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("auth.login.legal.checkbox_lead"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 2) {
                    Text(L10n.text("auth.login.legal.terms"))
                        .font(.caption2)
                        .foregroundStyle(.blue)

                    Text(L10n.text("auth.login.legal.conjunction"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(L10n.text("auth.login.legal.privacy"))
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenAgreementPrompt()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(showsValidationHighlight ? Color.red.opacity(0.06) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    showsValidationHighlight ? Color.red.opacity(0.45) : Color.clear,
                    lineWidth: 1
                )
        )
        .shakeOnTrigger(shakeTrigger)
        .padding(.top, 4)
    }
}
