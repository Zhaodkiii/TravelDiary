import AuthenticationServices
import SwiftUI

struct AccountProfileCard: View {
    let profile: AccountProfile
    private var displayName: String { AccountProfileDisplayName.resolve(profile.displayName) }

    var body: some View {
        HStack(spacing: 15) {
            ZStack {
                Circle().fill(DiaryLibraryStyle.accent.opacity(0.13)).frame(width: 58, height: 58)
                Image(systemName: profile.signInMethod == .device ? "person.crop.circle" : "person.fill")
                    .font(.system(size: 25, weight: .medium)).foregroundStyle(DiaryLibraryStyle.accent)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(displayName).font(.title3.weight(.semibold)).foregroundStyle(DiaryLibraryStyle.ink).lineLimit(1)
                Label(profile.signInMethodDescription, systemImage: "checkmark.shield")
                    .font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(DiaryLibraryStyle.line.opacity(0.65), lineWidth: 0.75))
    }
}

nonisolated enum AccountProfileDisplayName {
    static func resolve(_ value: String) -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = name.lowercased()
        guard !name.isEmpty,
              !lowered.hasPrefix("device_"),
              !lowered.hasPrefix("guest_"),
              !lowered.hasPrefix("auto_") else { return "我的账户" }
        return name
    }
}

struct AccountInfoRow: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            AccountSquareBadge(color: tint, icon: icon)
            Text(title).foregroundStyle(DiaryLibraryStyle.ink)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(DiaryLibraryStyle.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1).minimumScaleFactor(0.7)
                .font(.subheadline)
        }
        .padding(.horizontal, 16).padding(.vertical, 14).frame(minHeight: 68)
    }
}

struct AccountSquareBadge: View {
    let color: Color
    let icon: String

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color)
            .frame(width: 32, height: 32)
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

struct VerificationMethodCard: View {
    var title: String = L10n.text("account_management.verify.security_title")
    var message: String = L10n.text("account_management.verify.security_message")
    let channels: [AccountVerificationChannel]
    let maskedTarget: (AccountVerificationChannel) -> String
    let onSelect: (AccountVerificationChannel) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: "shield.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(Array(channels.enumerated()), id: \.offset) { _, channel in
                    Button {
                        onSelect(channel)
                    } label: {
                        HStack(spacing: 12) {
                            AccountSquareBadge(color: badgeColor(for: channel), icon: icon(for: channel))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(channel.title)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text(maskedTarget(channel))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Spacer()
                Button(L10n.text("common.cancel"), action: onCancel)
                    .buttonStyle(.bordered)
            }
        }
        .accountOverlayCard()
    }

    private func icon(for channel: AccountVerificationChannel) -> String {
        switch channel {
        case .apple:
            return "applelogo"
        case .phone:
            return "phone.fill"
        case .email:
            return "envelope.fill"
        }
    }

    private func badgeColor(for channel: AccountVerificationChannel) -> Color {
        switch channel {
        case .apple:
            return .black
        case .phone:
            return .green
        case .email:
            return .red
        }
    }
}

struct OTPVerificationCard: View {
    let title: String
    let subtitle: String
    let target: String
    var footerHint: String? = nil
    var hasSentCode: Bool = true
    var isSendingCode: Bool = false
    @Binding var code: String
    let countdown: Int
    let onBack: () -> Void
    let onResend: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                }
                Spacer()
            }
            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.bold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if hasSentCode {
                    Text(
                        String(
                            format: L10n.text("account_management.deactivation.otp.sent_format"),
                            locale: Locale.current,
                            target
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(L10n.text("account_management.otp.tap_send_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            VerificationCodeField(code: $code, length: 6)
            if countdown > 0 {
                Text(
                    String(
                        format: L10n.text("account_management.otp.resend_countdown"),
                        locale: Locale.current,
                        countdown
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                Button(action: onResend) {
                    HStack(spacing: 8) {
                        if isSendingCode {
                            ProgressView()
                        }
                        Text(
                            hasSentCode
                                ? L10n.text("account_management.otp.resend")
                                : L10n.text("account_management.identity.target.send_otp")
                        )
                    }
                }
                    .buttonStyle(.bordered)
                    .disabled(isSendingCode)
            }
            if let footerHint, footerHint.isEmpty == false {
                Text(footerHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .accountOverlayCard()
    }
}

struct AppleReauthCard: View {
    var title: String = L10n.text("account_management.apple_reauth.title")
    var message: String = L10n.text("account_management.apple_reauth.message")
    let onCancel: () -> Void
    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: "applelogo")
                .font(.title3.weight(.bold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = []
            } onCompletion: { result in
                onCompletion(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 46)
            HStack {
                Spacer()
                Button(L10n.text("common.cancel"), action: onCancel)
                    .buttonStyle(.bordered)
            }
        }
        .accountOverlayCard()
    }
}

struct FinalDeleteConfirmationDialog: View {
    let phrase: String
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @State private var confirmText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("account_management.deactivation.final.title"))
                .font(.headline)
            Text(L10n.text("account_management.deactivation.final.intro"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                BulletLine(L10n.text("account_management.deactivation.final.bullet.chat"))
                BulletLine(L10n.text("account_management.deactivation.final.bullet.health"))
                BulletLine(L10n.text("account_management.deactivation.final.bullet.identity"))
                BulletLine(L10n.text("account_management.deactivation.final.bullet.irreversible"))
            }
            .font(.subheadline)
            Text(L10n.text("account_management.deactivation.final.warning"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    String(
                        format: L10n.text("account_management.deactivation.confirm_prompt"),
                        locale: Locale.current,
                        phrase
                    )
                )
                .font(.subheadline.weight(.medium))
                TextField(phrase, text: $confirmText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button(L10n.text("common.cancel"), action: onCancel)
                    .buttonStyle(.bordered)
                Button(L10n.text("account_management.deactivation.confirm_delete"), role: .destructive, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .disabled(confirmText != phrase)
                    .opacity(confirmText == phrase ? 1 : 0.6)
            }
        }
        .accountOverlayCard(maxWidth: 520)
    }
}

struct AccountFailureCard: View {
    let message: String
    let onBack: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L10n.text("account_management.failure.title"), systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(L10n.text("common.cancel"), action: onCancel)
                    .buttonStyle(.bordered)
                Button(L10n.text("account_management.failure.restart"), action: onBack)
                    .buttonStyle(.borderedProminent)
            }
        }
        .accountOverlayCard()
    }
}

struct AccountIdentityRow: View {
    let status: AccountIdentityStatus
    let onBind: () -> Void
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AccountSquareBadge(color: badgeColor, icon: status.provider.icon)
            VStack(alignment: .leading, spacing: 4) {
                Text(status.provider.title)
                    .font(.body.weight(.medium))
                Text(statusLabel)
                    .font(.footnote)
                    .foregroundStyle(DiaryLibraryStyle.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 12)
            actionButton
        }
        .padding(.horizontal, 16).padding(.vertical, 14).frame(minHeight: 72)
    }

    @ViewBuilder
    private var actionButton: some View {
        if status.bound {
            if status.modifiable {
                Button(L10n.text("account_management.identity.action.change"), action: onChange)
                    .font(.subheadline.weight(.medium))
            } else {
                Text(L10n.text("account_management.identity.status.bound"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else if status.bindable {
            Button(L10n.text("account_management.identity.action.bind"), action: onBind)
                .font(.subheadline.weight(.medium))
        } else {
            Text(L10n.text("account_management.identity.status.unbound"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var statusLabel: String {
        if status.bound {
            return status.maskedValue.isEmpty
                ? L10n.text("account_management.identity.status.bound")
                : status.maskedValue
        }
        return L10n.text("account_management.identity.status.unbound")
    }

    private var badgeColor: Color {
        switch status.provider {
        case .phone:
            return .green
        case .email:
            return .red
        case .apple:
            return .black
        }
    }
}

struct IdentityTargetInputCard: View {
    let provider: AccountIdentityProvider
    let isChange: Bool
    @Binding var target: String
    @Binding var phoneInput: PhoneNumberInputModel
    @Binding var emailInput: EmailAddressInputModel
    var isPhoneLocked: Bool = false
    var isEmailLocked: Bool = false
    var canSendOTP: Bool = false
    var isSendingOTP: Bool = false
    let onBack: () -> Void
    let onSendOTP: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                }
                Spacer()
            }
            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.bold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            switch provider {
            case .phone:
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("account_management.identity.target.phone.placeholder"))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    PhoneNumberInputView(model: $phoneInput, isLocked: isPhoneLocked)
                    if phoneInput.rawInput.isEmpty == false, phoneInput.isValid == false {
                        Text(L10n.text("account_management.identity.phone.invalid", fallback: "手机号格式不正确"))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            case .email:
                VStack(alignment: .leading, spacing: 8) {
                    Text(placeholder)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    EmailAddressInputView(model: $emailInput, isLocked: isEmailLocked)
                }
            case .apple:
                EmptyView()
            }
            
            Button(action: onSendOTP) {
                HStack(spacing: 8) {
                    if isSendingOTP {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(L10n.text("account_management.identity.target.send_otp"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(canSendOTP == false || isSendingOTP)
        }
        .accountOverlayCard()
    }

    private var title: String {
        switch provider {
        case .phone:
            return isChange
                ? L10n.text("account_management.identity.target.phone.change_title")
                : L10n.text("account_management.identity.target.phone.bind_title")
        case .email:
            return isChange
                ? L10n.text("account_management.identity.target.email.change_title")
                : L10n.text("account_management.identity.target.email.bind_title")
        case .apple:
            return L10n.text("account_management.identity.target.apple.bind_title")
        }
    }

    private var subtitle: String {
        switch provider {
        case .phone:
            return L10n.text("account_management.identity.target.phone.subtitle")
        case .email:
            return L10n.text("account_management.identity.target.email.subtitle")
        case .apple:
            return L10n.text("account_management.identity.target.apple.subtitle")
        }
    }

    private var placeholder: String {
        switch provider {
        case .phone:
            return L10n.text("account_management.identity.target.phone.placeholder")
        case .email:
            return L10n.text("account_management.identity.target.email.placeholder")
        case .apple:
            return ""
        }
    }
}

struct IdentityOperationResultCard: View {
    let operation: AccountIdentityOperation
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
            Button(L10n.text("common.ok"), action: onDismiss)
                .buttonStyle(.borderedProminent)
        }
        .accountOverlayCard()
    }

    private var message: String {
        switch operation {
        case .bind(let provider):
            return String(
                format: L10n.text("account_management.identity.completed.bind"),
                locale: Locale.current,
                provider.title
            )
        case .change(let provider):
            return String(
                format: L10n.text("account_management.identity.completed.change"),
                locale: Locale.current,
                provider.title
            )
        }
    }
}

private struct BulletLine: View {
    let text: String
    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(Color.secondary)
                .frame(width: 4, height: 4)
            Text(text)
        }
    }
}

private extension View {
    func accountOverlayCard(maxWidth: CGFloat = 420) -> some View {
        self
            .padding(18)
            .frame(maxWidth: maxWidth)
            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(.separator).opacity(0.4))
            }
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            .padding(.horizontal, 16)
    }
}
