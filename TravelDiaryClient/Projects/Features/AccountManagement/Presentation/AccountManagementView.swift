import AuthenticationServices
import SwiftUI

struct AccountManagementView: View {
    @ObservedObject var viewModel: AccountManagementViewModel
    let session: UserSession
    @State private var showSignOutConfirm = false
    @State private var showAdvancedOptions = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let profile = viewModel.profile {
                        AccountProfileCard(profile: profile)
                        accountInfoSection(profile)
                    } else if viewModel.isLoadingProfile {
                        ProgressView()
                            .padding(.top, 48)
                    }

                    if let identityList = viewModel.identityList {
                        identitySection(identityList)
                    } else if viewModel.isLoadingIdentities {
                        ProgressView(L10n.text("account_management.identity.loading"))
                            .padding(.top, 8)
                    }

                    sessionSection
                    dangerSection
                }
                .padding(16)
                .padding(.bottom, 48)
            }
            .background(Color(.systemGroupedBackground))

            if viewModel.flowState.isOverlayPresented {
                deactivationOverlay
            }

            if viewModel.identityFlowState.isOverlayPresented {
                identityOverlay
            }
        }
        .navigationTitle(L10n.text("settings.account_management"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load(session: session)
        }
        .alert(L10n.text("common.operation_failed"), isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { presented in
                if presented == false {
                    viewModel.clearError()
                }
            }
        )) {
            Button(L10n.text("common.ok")) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert(L10n.text("account_management.sign_out.confirm.title"), isPresented: $showSignOutConfirm) {
            Button(L10n.text("settings.sign_out"), role: .destructive) {
                Task { await viewModel.signOut() }
            }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("account_management.sign_out.confirm.message"))
        }
        .onChange(of: viewModel.otpCode) { _ in
            viewModel.completeOTPIfReady()
        }
        .onChange(of: viewModel.identityReauthOTPCode) { _ in
            viewModel.verifyIdentityReauthOTPIfReady()
        }
        .onChange(of: viewModel.identityTargetOTPCode) { _ in
            viewModel.submitIdentityTargetOTPIfReady()
        }
    }

    private func accountInfoSection(_ profile: AccountProfile) -> some View {
        AccountSection(title: L10n.text("account_management.section.account_info")) {
            AccountInfoRow(
                icon: "person.text.rectangle",
                tint: .blue,
                title: L10n.text("account_management.field.account_id"),
                value: "\(profile.accountID)"
            )
            Divider()
            AccountInfoRow(
                icon: profile.signInMethod == .phone ? "phone.fill" : "envelope.fill",
                tint: .green,
                title: profile.signInMethod == .phone
                    ? L10n.text("account_management.field.phone")
                    : L10n.text("settings.email"),
                value: profile.contact
            )
            Divider()
            AccountInfoRow(
                icon: "checkmark.shield.fill",
                tint: .purple,
                title: L10n.text("settings.sign_in_method"),
                value: profile.signInMethodDescription
            )
            Divider()
            AccountInfoRow(
                icon: "clock.fill",
                tint: .orange,
                title: L10n.text("settings.sign_in_time"),
                value: profile.signedInAt.formatted(date: .abbreviated, time: .shortened)
            )
        }
    }

    private func identitySection(_ identities: AccountIdentityList) -> some View {
        AccountSection(title: L10n.text("account_management.identity.section.title")) {
            ForEach(Array(identities.identities.enumerated()), id: \.offset) { index, status in
                if index > 0 {
                    Divider()
                }
                AccountIdentityRow(
                    status: status,
                    onBind: { viewModel.beginBind(status.provider) },
                    onChange: { viewModel.beginChange(status.provider) }
                )
            }
        }
    }

    private var sessionSection: some View {
        AccountSection(title: L10n.text("account_management.section.session")) {
            Button {
                showSignOutConfirm = true
            } label: {
                HStack(spacing: 12) {
                    AccountSquareBadge(color: .orange, icon: "rectangle.portrait.and.arrow.right")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("settings.sign_out"))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.red)
                        Text(L10n.text("account_management.sign_out.subtitle"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if viewModel.isSigningOut {
                        ProgressView()
                    }
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var dangerSection: some View {
        AccountSection(title: L10n.text("account_management.section.danger")) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.text("account_management.deactivation.intro"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showAdvancedOptions.toggle()
                    }
                } label: {
                    HStack {
                        Text(
                            showAdvancedOptions
                                ? L10n.text("account_management.advanced.hide")
                                : L10n.text("account_management.advanced.show")
                        )
                        Image(systemName: showAdvancedOptions ? "chevron.up" : "chevron.down")
                    }
                    .font(.footnote.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                if showAdvancedOptions {
                    VStack(spacing: 12) {
                        Toggle(L10n.text("account_management.deactivation.immediate"), isOn: $viewModel.options.immediateDeactivation)
                        if viewModel.options.immediateDeactivation == false {
                            Stepper(value: $viewModel.options.countdownHours, in: 1...168) {
                                HStack {
                                    Text(L10n.text("account_management.deactivation.countdown_label"))
                                    Spacer()
                                    Text(
                                        String(
                                            format: L10n.text("account_management.deactivation.countdown_hours"),
                                            locale: Locale.current,
                                            viewModel.options.countdownHours
                                        )
                                    )
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Toggle(L10n.text("account_management.deactivation.anonymize"), isOn: $viewModel.options.anonymizePersonalData)
                        Toggle(L10n.text("account_management.deactivation.delete_related"), isOn: $viewModel.options.deleteRelatedData)
                        Stepper(value: $viewModel.options.dataRetentionDays, in: 0...365) {
                            HStack {
                                Text(L10n.text("account_management.deactivation.retention_label"))
                                Spacer()
                                Text(
                                    String(
                                        format: L10n.text("account_management.deactivation.retention_days"),
                                        locale: Locale.current,
                                        viewModel.options.dataRetentionDays
                                    )
                                )
                                .foregroundStyle(.secondary)
                            }
                        }
                        TextField(L10n.text("account_management.deactivation.reason_placeholder"), text: $viewModel.options.reason)
                            .textFieldStyle(.roundedBorder)
                    }
                    .font(.subheadline)
                }
            }
            .padding(16)

            Divider()

            Button(role: .destructive) {
                viewModel.beginDeactivation()
            } label: {
                HStack(spacing: 12) {
                    AccountSquareBadge(color: .red, icon: "trash.fill")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("account_management.deactivation.request_title"))
                            .font(.body.weight(.semibold))
                        Text(L10n.text("account_management.deactivation.request_subtitle"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var deactivationOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    if case .chooseVerification = viewModel.flowState {
                        viewModel.cancelFlow()
                    }
                }

            switch viewModel.flowState {
            case .chooseVerification:
                VerificationMethodCard(
                    channels: viewModel.availableVerificationChannels,
                    maskedTarget: { viewModel.maskedTarget(for: $0) },
                    onSelect: { channel in
                        Task { await viewModel.requestVerification(channel) }
                    },
                    onCancel: viewModel.cancelFlow
                )
            case .enteringOTP(let channel, _):
                OTPVerificationCard(
                    title: L10n.text("account_management.deactivation.otp.title"),
                    subtitle: L10n.text("account_management.deactivation.otp.subtitle"),
                    target: viewModel.maskedTarget(for: channel),
                    code: $viewModel.otpCode,
                    countdown: viewModel.resendCountdown,
                    onBack: {
                        viewModel.beginDeactivation()
                    },
                    onResend: {
                        Task { await viewModel.requestVerification(channel) }
                    }
                )
            case .appleReauth:
                AppleReauthCard(
                    onCancel: viewModel.cancelFlow,
                    onCompletion: handleDeactivationAppleReauthResult
                )
            case .finalConfirmation:
                FinalDeleteConfirmationDialog(
                    phrase: viewModel.requiredConfirmationPhrase,
                    onCancel: viewModel.cancelFlow,
                    onConfirm: {
                        Task { await viewModel.submitFinalDeactivation() }
                    }
                )
            case .submitting:
                VStack(spacing: 14) {
                    ProgressView()
                    Text(L10n.text("account_management.deactivation.submitting"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            case .failed(let message):
                AccountFailureCard(message: message, onBack: viewModel.beginDeactivation, onCancel: viewModel.cancelFlow)
            case .idle, .completed:
                EmptyView()
            }
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.2), value: viewModel.flowState)
    }

    @ViewBuilder
    private var identityOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    if case .choosingReauth = viewModel.identityFlowState {
                        viewModel.cancelIdentityFlow()
                    }
                }

            switch viewModel.identityFlowState {
            case .choosingReauth:
                VerificationMethodCard(
                    title: L10n.text("account_management.verify.security_title"),
                    message: L10n.text("account_management.identity.reauth.message"),
                    channels: viewModel.availableIdentityVerificationChannels,
                    maskedTarget: { viewModel.maskedTarget(for: $0) },
                    onSelect: { channel in
                        Task { await viewModel.requestIdentityReauth(channel) }
                    },
                    onCancel: viewModel.cancelIdentityFlow
                )
            case .reauthOTP(_, let channel, let otpID):
                OTPVerificationCard(
                    title: L10n.text("account_management.identity.reauth.otp.title"),
                    subtitle: L10n.text("account_management.identity.reauth.otp.subtitle"),
                    target: viewModel.maskedTarget(for: channel),
                    hasSentCode: otpID != nil,
                    isSendingCode: viewModel.isRequestingIdentityReauthOTP,
                    code: $viewModel.identityReauthOTPCode,
                    countdown: viewModel.identityResendCountdown,
                    onBack: {
                        viewModel.restartIdentityFlow()
                    },
                    onResend: {
                        Task { await viewModel.requestIdentityReauthOTP(channel) }
                    }
                )
            case .reauthApple:
                AppleReauthCard(
                    onCancel: viewModel.handleIdentityAppleReauthCancelled,
                    onCompletion: handleIdentityAppleReauthResult
                )
            case .enteringTarget(let operation, _):
                if case .bind(.apple) = operation {
                    AppleReauthCard(
                        title: L10n.text("account_management.identity.target.apple.bind_title"),
                        message: L10n.text("account_management.identity.target.apple.subtitle"),
                        onCancel: viewModel.handleIdentityAppleBindCancelled,
                        onCompletion: handleIdentityAppleBindResult
                    )
                } else {
                    IdentityTargetInputCard(
                        provider: operation.targetProvider,
                        isChange: {
                            if case .change = operation { return true }
                            return false
                        }(),
                        target: $viewModel.identityTargetInput,
                        phoneInput: $viewModel.identityTargetPhoneInput,
                        emailInput: $viewModel.identityTargetEmailInput,
                        isPhoneLocked: viewModel.lockedIdentityTargetPhone != nil,
                        isEmailLocked: viewModel.lockedIdentityTargetEmail != nil,
                        canSendOTP: viewModel.canRequestIdentityTargetOTP,
                        isSendingOTP: viewModel.isRequestingIdentityTargetOTP,
                        onBack: viewModel.restartIdentityFlow,
                        onSendOTP: {
                            Task { await viewModel.requestTargetOTP() }
                        }
                    )
                }
            case .targetOTP(let operation, _, _, _):
                OTPVerificationCard(
                    title: L10n.text("account_management.identity.target.otp.title"),
                    subtitle: L10n.text("account_management.identity.target.otp.subtitle"),
                    target: viewModel.identityTargetOTPDisplayValue,
                    footerHint: operation.targetProvider == .phone
                        ? L10n.text(
                            "account_management.identity.phone.change_to_edit",
                            fallback: "如需修改手机号，请返回上一步"
                        )
                        : operation.targetProvider == .email
                            ? L10n.text(
                                "account_management.identity.email.change_to_edit",
                                fallback: "如需修改邮箱，请返回上一步"
                            )
                            : nil,
                    code: $viewModel.identityTargetOTPCode,
                    countdown: viewModel.identityResendCountdown,
                    onBack: viewModel.backToIdentityTargetInput,
                    onResend: {
                        Task { await viewModel.requestTargetOTP() }
                    }
                )
            case .submitting:
                VStack(spacing: 14) {
                    ProgressView()
                    Text(L10n.text("account_management.identity.submitting"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            case .completed(let operation):
                IdentityOperationResultCard(operation: operation, onDismiss: viewModel.dismissIdentityCompletion)
            case .failed(let message):
                AccountFailureCard(
                    message: message,
                    onBack: viewModel.restartIdentityFlow,
                    onCancel: viewModel.cancelIdentityFlow
                )
            case .idle:
                EmptyView()
            }
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.2), value: viewModel.identityFlowState)
    }

    private func handleDeactivationAppleReauthResult(_ result: Result<ASAuthorization, Error>) {
        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8),
                  identityToken.isEmpty == false
            else {
                throw AccountManagementError.invalidAppleCredential
            }
            let authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            viewModel.completeAppleReauth(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                userIdentifier: credential.user
            )
        } catch {
            viewModel.failAppleReauth(error)
        }
    }

    private func handleIdentityAppleReauthResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            do {
                let credential = try appleCredential(from: authorization)
                viewModel.completeIdentityAppleReauth(
                    identityToken: credential.identityToken,
                    authorizationCode: credential.authorizationCode,
                    userIdentifier: credential.userIdentifier
                )
            } catch {
                if AuthUserFacingErrorMapper.isAppleSignInCancelled(error) {
                    viewModel.handleIdentityAppleReauthCancelled()
                } else {
                    viewModel.failIdentityFlow(error.localizedDescription)
                }
            }
        case .failure(let error):
            if AuthUserFacingErrorMapper.isAppleSignInCancelled(error) {
                viewModel.handleIdentityAppleReauthCancelled()
            } else {
                viewModel.failIdentityFlow(error.localizedDescription)
            }
        }
    }

    private func handleIdentityAppleBindResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            do {
                let credential = try appleCredential(from: authorization)
                viewModel.completeIdentityAppleBind(
                    identityToken: credential.identityToken,
                    authorizationCode: credential.authorizationCode,
                    userIdentifier: credential.userIdentifier
                )
            } catch {
                if AuthUserFacingErrorMapper.isAppleSignInCancelled(error) {
                    viewModel.handleIdentityAppleBindCancelled()
                } else {
                    viewModel.failIdentityFlow(error.localizedDescription)
                }
            }
        case .failure(let error):
            if AuthUserFacingErrorMapper.isAppleSignInCancelled(error) {
                viewModel.handleIdentityAppleBindCancelled()
            } else {
                viewModel.failIdentityFlow(error.localizedDescription)
            }
        }
    }

    private func appleCredential(from authorization: ASAuthorization) throws -> (
        identityToken: String,
        authorizationCode: String?,
        userIdentifier: String
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8),
              identityToken.isEmpty == false
        else {
            throw AccountManagementError.invalidAppleCredential
        }
        let authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        return (identityToken, authorizationCode, credential.user)
    }
}

private struct AccountSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(.separator).opacity(0.35))
            }
        }
    }
}
