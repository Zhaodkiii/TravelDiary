import Combine
import Foundation

@MainActor
final class AccountManagementViewModel: ObservableObject {
    @Published private(set) var profile: AccountProfile?
    @Published private(set) var identityList: AccountIdentityList?
    @Published private(set) var flowState: AccountDeactivationFlowState = .idle
    @Published private(set) var identityFlowState: AccountIdentityFlowState = .idle
    @Published private(set) var isLoadingProfile = false
    @Published private(set) var isLoadingIdentities = false
    @Published private(set) var isSigningOut = false
    @Published private(set) var isRequestingIdentityReauthOTP = false
    @Published private(set) var isRequestingIdentityTargetOTP = false
    @Published private(set) var errorMessage: String?
    @Published var options = AccountDeactivationOptions()
    @Published var otpCode = ""
    @Published var identityReauthOTPCode = ""
    @Published var identityTargetInput = ""
    @Published var identityTargetPhoneInput = PhoneNumberInputModel()
    @Published var identityTargetEmailInput = EmailAddressInputModel()
    @Published private(set) var lockedIdentityTargetPhone: LockedPhoneTarget?
    @Published private(set) var lockedIdentityTargetEmail: LockedEmailTarget?
    @Published var identityTargetOTPCode = ""
    @Published private(set) var resendCountdown = 0
    @Published private(set) var identityResendCountdown = 0

    var canRequestIdentityTargetOTP: Bool {
        guard isRequestingIdentityTargetOTP == false else { return false }
        guard case .enteringTarget(let operation, _) = identityFlowState else { return false }
        switch operation.targetProvider {
        case .phone:
            return identityTargetPhoneInput.isValid && identityTargetPhoneInput.e164.isEmpty == false
        case .email:
            return identityTargetEmailInput.isValid && identityTargetEmailInput.normalizedEmail.isEmpty == false
        case .apple:
            return false
        }
    }

    var identityTargetOTPDisplayValue: String {
        guard case .targetOTP(_, _, _, let target) = identityFlowState else {
            if identityTargetEmailInput.normalizedEmail.isEmpty == false {
                return identityTargetEmailInput.normalizedEmail
            }
            return identityTargetInput
        }
        return target.displayValue
    }

    var requiredConfirmationPhrase: String {
        L10n.text("account_management.deactivation.confirm_phrase", fallback: "删除我的账户")
    }

    private let loadAccountProfileUseCase: LoadAccountProfileUseCase
    private let loadAccountIdentitiesUseCase: LoadAccountIdentitiesUseCase
    private let requestAccountVerificationUseCase: RequestAccountVerificationUseCase
    private let requestIdentityVerificationUseCase: RequestIdentityVerificationUseCase
    private let verifyIdentityVerificationUseCase: VerifyIdentityVerificationUseCase
    private let bindAccountIdentityUseCase: BindAccountIdentityUseCase
    private let changeAccountIdentityUseCase: ChangeAccountIdentityUseCase
    private let submitAccountDeactivationUseCase: SubmitAccountDeactivationUseCase
    private let accountManagementRepository: any AccountManagementRepository
    private let signOutUseCase: SignOutUseCase
    private let sessionStore: AppSessionStore
    private var countdownTask: Task<Void, Never>?
    private var identityCountdownTask: Task<Void, Never>?

    init(
        loadAccountProfileUseCase: LoadAccountProfileUseCase,
        loadAccountIdentitiesUseCase: LoadAccountIdentitiesUseCase,
        requestAccountVerificationUseCase: RequestAccountVerificationUseCase,
        requestIdentityVerificationUseCase: RequestIdentityVerificationUseCase,
        verifyIdentityVerificationUseCase: VerifyIdentityVerificationUseCase,
        bindAccountIdentityUseCase: BindAccountIdentityUseCase,
        changeAccountIdentityUseCase: ChangeAccountIdentityUseCase,
        submitAccountDeactivationUseCase: SubmitAccountDeactivationUseCase,
        accountManagementRepository: any AccountManagementRepository,
        signOutUseCase: SignOutUseCase,
        sessionStore: AppSessionStore
    ) {
        self.loadAccountProfileUseCase = loadAccountProfileUseCase
        self.loadAccountIdentitiesUseCase = loadAccountIdentitiesUseCase
        self.requestAccountVerificationUseCase = requestAccountVerificationUseCase
        self.requestIdentityVerificationUseCase = requestIdentityVerificationUseCase
        self.verifyIdentityVerificationUseCase = verifyIdentityVerificationUseCase
        self.bindAccountIdentityUseCase = bindAccountIdentityUseCase
        self.changeAccountIdentityUseCase = changeAccountIdentityUseCase
        self.submitAccountDeactivationUseCase = submitAccountDeactivationUseCase
        self.accountManagementRepository = accountManagementRepository
        self.signOutUseCase = signOutUseCase
        self.sessionStore = sessionStore
    }

    var availableVerificationChannels: [AccountVerificationChannel] {
        guard let profile else { return [] }
        switch profile.signInMethod {
        case .apple:
            if let email = profile.email {
                return [.apple, .email(email)]
            }
            return [.apple]
        case .phone:
            if let phone = profile.phoneNumber {
                return [.phone(phone)]
            }
            return []
        case .email:
            if let email = profile.email {
                return [.email(email)]
            }
            return []
        case .device, .google:
            return []
        }
    }

    var availableIdentityVerificationChannels: [AccountVerificationChannel] {
        guard let identityList else { return [] }
        return identityList.identities.compactMap { status in
            guard status.bound else { return nil }
            switch status.provider {
            case .apple:
                return .apple
            case .phone:
                return .phone(status.maskedValue)
            case .email:
                return .email(status.maskedValue)
            }
        }
    }

    func load(session: UserSession) async {
        isLoadingProfile = true
        isLoadingIdentities = true
        defer {
            isLoadingProfile = false
            isLoadingIdentities = false
        }
        async let profileTask = loadAccountProfileUseCase.execute(session: session)
        async let identitiesTask = loadAccountIdentitiesUseCase.execute(session: session)
        do {
            profile = try await profileTask
            identityList = try await identitiesTask
            errorMessage = nil
        } catch {
            errorMessage = localizedErrorMessage(for: error)
        }
    }

    func beginDeactivation() {
        otpCode = ""
        errorMessage = nil
        flowState = .chooseVerification
    }

    func cancelFlow() {
        stopCountdown()
        otpCode = ""
        flowState = .idle
    }

    func beginBind(_ provider: AccountIdentityProvider) {
        clearIdentityFlowInputs()
        identityFlowState = .choosingReauth(.bind(provider))
    }

    func beginChange(_ provider: AccountIdentityProvider) {
        clearIdentityFlowInputs()
        identityFlowState = .choosingReauth(.change(provider))
    }

    func cancelIdentityFlow() {
        stopIdentityCountdown()
        clearIdentityFlowInputs()
        identityFlowState = .idle
    }

    func restartIdentityFlow() {
        guard let operation = identityFlowState.operation else {
            cancelIdentityFlow()
            return
        }
        clearIdentityFlowInputs()
        identityFlowState = .choosingReauth(operation)
    }

    func requestVerification(_ channel: AccountVerificationChannel) async {
        errorMessage = nil
        otpCode = ""
        switch channel {
        case .apple:
            flowState = .appleReauth
        case .phone, .email:
            do {
                let context = try await requestAccountVerificationUseCase.execute(
                    channel: channel,
                    session: currentSession
                )
                flowState = .enteringOTP(channel, otpID: context.otpID)
                startCountdown(seconds: min(max(context.expiresIn, 30), 120))
            } catch {
                flowState = .failed(localizedErrorMessage(for: error))
            }
        }
    }

    func requestIdentityReauth(_ channel: AccountVerificationChannel) async {
        guard let operation = identityFlowState.operation else { return }
        identityReauthOTPCode = ""
        errorMessage = nil

        switch channel {
        case .apple:
            identityFlowState = .reauthApple(operation)
        case .phone, .email:
            stopIdentityCountdown()
            identityFlowState = .reauthOTP(operation, channel, otpID: nil)
        }
    }

    func requestIdentityReauthOTP(_ channel: AccountVerificationChannel) async {
        guard isRequestingIdentityReauthOTP == false else { return }
        guard case .reauthOTP(let operation, _, _) = identityFlowState else { return }
        isRequestingIdentityReauthOTP = true
        defer { isRequestingIdentityReauthOTP = false }

        identityReauthOTPCode = ""
        errorMessage = nil

        let provider = identityProvider(for: channel)
        do {
            let result = try await requestIdentityVerificationUseCase.execute(
                provider: provider,
                purpose: operation.purpose,
                session: currentSession
            )
            switch result {
            case .otp(let otpID, let expiresIn):
                identityFlowState = .reauthOTP(operation, channel, otpID: otpID)
                startIdentityCountdown(seconds: min(max(expiresIn, 30), 120))
            case .appleReady:
                identityFlowState = .reauthApple(operation)
            }
        } catch {
            identityFlowState = .reauthOTP(operation, channel, otpID: nil)
            errorMessage = localizedErrorMessage(for: error)
        }
    }

    func verifyIdentityReauthOTPIfReady() {
        guard identityReauthOTPCode.count == 6 else { return }
        guard case .reauthOTP(let operation, let channel, let otpID) = identityFlowState else { return }
        guard let otpID else { return }
        Task { await verifyIdentityReauth(operation: operation, channel: channel, otpID: otpID) }
    }

    func completeIdentityAppleReauth(identityToken: String, authorizationCode: String?, userIdentifier: String) {
        guard case .reauthApple(let operation) = identityFlowState else { return }
        Task {
            await verifyIdentityReauth(
                operation: operation,
                channel: .apple,
                otpID: "",
                appleCredentials: (identityToken, authorizationCode, userIdentifier)
            )
        }
    }

    func handleIdentityAppleReauthCancelled() {
        guard case .reauthApple(let operation) = identityFlowState else { return }
        identityFlowState = .choosingReauth(operation)
    }

    func completeIdentityAppleBind(identityToken: String, authorizationCode: String?, userIdentifier: String) {
        guard case .enteringTarget(let operation, let ticket) = identityFlowState else { return }
        guard case .bind = operation else { return }
        Task {
            await submitBindOrChange(
                operation: operation,
                ticket: ticket,
                bindProof: .apple(
                    identityToken: identityToken,
                    authorizationCode: authorizationCode,
                    userIdentifier: userIdentifier
                )
            )
        }
    }

    func handleIdentityAppleBindCancelled() {
        guard case .enteringTarget(let operation, let ticket) = identityFlowState else { return }
        identityFlowState = .enteringTarget(operation, ticket: ticket)
    }

    func requestTargetOTP() async {
        guard isRequestingIdentityTargetOTP == false else { return }
        isRequestingIdentityTargetOTP = true
        defer { isRequestingIdentityTargetOTP = false }

        identityTargetOTPCode = ""
        errorMessage = nil

        switch identityFlowState {
        case .enteringTarget(let operation, let ticket):
            await requestTargetOTPFromInput(operation: operation, ticket: ticket)
        case .targetOTP(let operation, let ticket, let otpID, let target):
            await resendTargetOTP(operation: operation, ticket: ticket, currentOtpID: otpID, target: target)
        default:
            return
        }
    }

    func submitIdentityTargetOTPIfReady() {
        guard identityTargetOTPCode.count == 6 else { return }
        guard case .targetOTP(let operation, let ticket, let otpID, let target) = identityFlowState else { return }

        Task {
            switch operation {
            case .bind(let provider):
                switch (provider, target) {
                case (.phone, .phone(let phone)):
                    let proof = AccountIdentityBindProof.phone(
                        target: phone.e164,
                        otpID: otpID,
                        code: identityTargetOTPCode
                    )
                    await submitBindOrChange(
                        operation: operation,
                        ticket: ticket,
                        bindProof: proof,
                        restoreTargetOTP: (otpID, target)
                    )
                case (.email, .email(let email)):
                    let proof = AccountIdentityBindProof.email(
                        target: email.email,
                        otpID: otpID,
                        code: identityTargetOTPCode
                    )
                    await submitBindOrChange(
                        operation: operation,
                        ticket: ticket,
                        bindProof: proof,
                        restoreTargetOTP: (otpID, target)
                    )
                default:
                    return
                }
            case .change(let provider):
                switch (provider, target) {
                case (.phone, .phone(let phone)):
                    await submitBindOrChange(
                        operation: operation,
                        ticket: ticket,
                        changeTarget: phone.e164,
                        changeOtpID: otpID,
                        changeCode: identityTargetOTPCode,
                        provider: .phone,
                        restoreTargetOTP: (otpID, target)
                    )
                case (.email, .email(let email)):
                    await submitBindOrChange(
                        operation: operation,
                        ticket: ticket,
                        changeTarget: email.email,
                        changeOtpID: otpID,
                        changeCode: identityTargetOTPCode,
                        provider: .email,
                        restoreTargetOTP: (otpID, target)
                    )
                default:
                    return
                }
            }
        }
    }

    func completeOTPIfReady() {
        guard otpCode.count == 6 else { return }
        guard case .enteringOTP(let channel, let otpID) = flowState else { return }
        switch channel {
        case .phone:
            stopCountdown()
            flowState = .finalConfirmation(.phone(otpID: otpID, code: otpCode))
        case .email:
            stopCountdown()
            flowState = .finalConfirmation(.email(otpID: otpID, code: otpCode))
        case .apple:
            break
        }
    }

    func completeAppleReauth(identityToken: String, authorizationCode: String?, userIdentifier: String) {
        flowState = .finalConfirmation(
            .apple(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                userIdentifier: userIdentifier
            )
        )
    }

    func failAppleReauth(_ error: Error) {
        flowState = .failed(error.localizedDescription)
    }

    func submitFinalDeactivation() async {
        guard case .finalConfirmation(let verification) = flowState else {
            flowState = .failed(AccountManagementError.missingVerificationProof.localizedDescription)
            return
        }
        flowState = .submitting
        do {
            let result = try await submitAccountDeactivationUseCase.execute(options: options, verification: verification)
            flowState = .completed(result)
            try await signOutUseCase.execute()
            sessionStore.setSignedOut()
        } catch {
            flowState = .failed(localizedErrorMessage(for: error))
        }
    }

    func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }
        do {
            try await signOutUseCase.execute()
            sessionStore.setSignedOut()
        } catch {
            errorMessage = localizedErrorMessage(for: error)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func dismissIdentityCompletion() {
        identityFlowState = .idle
        clearIdentityFlowInputs()
    }

    func backToIdentityTargetInput() {
        guard case .targetOTP(let operation, let ticket, _, _) = identityFlowState else { return }
        stopIdentityCountdown()
        identityTargetOTPCode = ""
        lockedIdentityTargetPhone = nil
        lockedIdentityTargetEmail = nil
        identityFlowState = .enteringTarget(operation, ticket: ticket)
    }

    func failIdentityFlow(_ message: String) {
        identityFlowState = .failed(message)
    }

    func maskedTarget(for channel: AccountVerificationChannel) -> String {
        switch channel {
        case .apple:
            return L10n.text("account_management.target.apple_id", fallback: "Apple ID")
        case .phone(let value):
            let compact = value.replacingOccurrences(of: " ", with: "")
            guard compact.count >= 7 else { return value }
            if compact.contains("*") { return value }
            return "\(compact.prefix(3))****\(compact.suffix(2))"
        case .email(let value):
            if value.contains("*") { return value }
            guard let at = value.firstIndex(of: "@") else { return value }
            let name = value[..<at]
            let domain = value[at...]
            if name.count <= 3 {
                return "\(name.prefix(1))***\(domain)"
            }
            return "\(name.prefix(2))***\(name.suffix(1))\(domain)"
        }
    }

    private func verifyIdentityReauth(
        operation: AccountIdentityOperation,
        channel: AccountVerificationChannel,
        otpID: String,
        appleCredentials: (String, String?, String)? = nil
    ) async {
        let provider = identityProvider(for: channel)
        let proof: AccountIdentityReauthProof
        switch channel {
        case .phone:
            proof = .phone(otpID: otpID, code: identityReauthOTPCode)
        case .email:
            proof = .email(otpID: otpID, code: identityReauthOTPCode)
        case .apple:
            guard let appleCredentials else { return }
            proof = .apple(
                identityToken: appleCredentials.0,
                authorizationCode: appleCredentials.1,
                userIdentifier: appleCredentials.2
            )
        }

        do {
            let ticket = try await verifyIdentityVerificationUseCase.execute(
                provider: provider,
                purpose: operation.purpose,
                proof: proof,
                session: currentSession
            )
            stopIdentityCountdown()
            identityReauthOTPCode = ""
            identityTargetInput = ""
            identityTargetPhoneInput = PhoneNumberInputModel()
            identityTargetEmailInput = EmailAddressInputModel()
            lockedIdentityTargetPhone = nil
            lockedIdentityTargetEmail = nil
            identityTargetOTPCode = ""
            identityFlowState = .enteringTarget(operation, ticket: ticket.ticket)
        } catch {
            if shouldStayOnReauthOTP(for: error) {
                identityReauthOTPCode = ""
                identityFlowState = .reauthOTP(operation, channel, otpID: otpID)
                errorMessage = localizedErrorMessage(for: error)
                return
            }
            handleIdentityOperationError(error, operation: operation, ticket: nil)
        }
    }

    private func submitBindOrChange(
        operation: AccountIdentityOperation,
        ticket: String,
        bindProof: AccountIdentityBindProof? = nil,
        changeTarget: String? = nil,
        changeOtpID: String? = nil,
        changeCode: String? = nil,
        provider: AccountIdentityProvider? = nil,
        restoreTargetOTP: (otpID: String, target: AccountIdentityTargetSnapshot)? = nil
    ) async {
        identityFlowState = .submitting
        do {
            let updatedList: AccountIdentityList
            switch operation {
            case .bind(let targetProvider):
                guard let bindProof else {
                    throw AccountManagementError.missingVerificationProof
                }
                updatedList = try await bindAccountIdentityUseCase.execute(
                    provider: targetProvider,
                    verificationTicket: ticket,
                    proof: bindProof,
                    session: currentSession
                )
            case .change(let targetProvider):
                guard
                    let changeTarget,
                    let changeOtpID,
                    let changeCode
                else {
                    throw AccountManagementError.missingVerificationProof
                }
                updatedList = try await changeAccountIdentityUseCase.execute(
                    provider: provider ?? targetProvider,
                    verificationTicket: ticket,
                    newTarget: changeTarget,
                    newOtpID: changeOtpID,
                    newCode: changeCode,
                    session: currentSession
                )
            }
            identityList = updatedList
            if let session = currentSession {
                profile = try? await loadAccountProfileUseCase.execute(session: session)
            }
            stopIdentityCountdown()
            clearIdentityFlowInputs(keepTarget: false)
            identityFlowState = .completed(operation)
        } catch {
            handleIdentityOperationError(
                error,
                operation: operation,
                ticket: ticket,
                restoreTargetOTP: restoreTargetOTP
            )
        }
    }

    private func requestTargetOTPFromInput(operation: AccountIdentityOperation, ticket: String) async {
        switch operation.targetProvider {
        case .phone:
            let phone = identityTargetPhoneInput
            guard phone.isValid, phone.e164.isEmpty == false else { return }

            let locked = LockedPhoneTarget(
                countryCode: phone.countryCode,
                nationalNumber: phone.nationalNumber,
                e164: phone.e164
            )
            do {
                let context = try await requestTargetOTP(
                    provider: .phone,
                    target: locked.e164,
                    operation: operation
                )
                lockedIdentityTargetPhone = locked
                identityTargetPhoneInput = PhoneNumberInputModel(
                    rawInput: locked.nationalNumber,
                    countryCode: locked.countryCode,
                    nationalNumber: locked.nationalNumber,
                    e164: locked.e164,
                    isValid: true
                )
                identityFlowState = .targetOTP(
                    operation,
                    ticket: ticket,
                    otpID: context.otpID,
                    target: .phone(locked)
                )
                startIdentityCountdown(seconds: min(max(context.expiresIn, 30), 120))
            } catch {
                lockedIdentityTargetPhone = nil
                handleIdentityOperationError(error, operation: operation, ticket: ticket)
            }

        case .email:
            let target = identityTargetEmailInput.normalizedEmail
            guard identityTargetEmailInput.isValid, target.isEmpty == false else { return }
            do {
                let context = try await requestTargetOTP(
                    provider: .email,
                    target: target,
                    operation: operation
                )
                let locked = LockedEmailTarget(email: target)
                lockedIdentityTargetEmail = locked
                identityFlowState = .targetOTP(
                    operation,
                    ticket: ticket,
                    otpID: context.otpID,
                    target: .email(locked)
                )
                startIdentityCountdown(seconds: min(max(context.expiresIn, 30), 120))
            } catch {
                lockedIdentityTargetEmail = nil
                handleIdentityOperationError(error, operation: operation, ticket: ticket)
            }

        case .apple:
            return
        }
    }

    private func resendTargetOTP(
        operation: AccountIdentityOperation,
        ticket: String,
        currentOtpID: String,
        target: AccountIdentityTargetSnapshot
    ) async {
        do {
            let context = try await requestTargetOTP(
                provider: operation.targetProvider,
                target: target.rawTarget,
                operation: operation
            )
            identityFlowState = .targetOTP(
                operation,
                ticket: ticket,
                otpID: context.otpID,
                target: target
            )
            startIdentityCountdown(seconds: min(max(context.expiresIn, 30), 120))
        } catch {
            // 重发失败：保留原 otpID 与冻结目标，留在验证码页。
            identityFlowState = .targetOTP(
                operation,
                ticket: ticket,
                otpID: currentOtpID,
                target: target
            )
            errorMessage = localizedErrorMessage(for: error)
        }
    }

    private func requestTargetOTP(
        provider: AccountIdentityProvider,
        target: String,
        operation: AccountIdentityOperation
    ) async throws -> AccountVerificationRequestContext {
        try await accountManagementRepository.requestTargetOTP(
            provider: provider,
            target: target,
            operation: operation,
            session: currentSession
        )
    }

    private func handleIdentityOperationError(
        _ error: Error,
        operation: AccountIdentityOperation,
        ticket: String?,
        restoreTargetOTP: (otpID: String, target: AccountIdentityTargetSnapshot)? = nil
    ) {
        let message = localizedErrorMessage(for: error)
        if shouldRestartIdentityReauth(for: error) {
            clearIdentityFlowInputs()
            identityFlowState = .choosingReauth(operation)
            errorMessage = message
            return
        }
        if shouldStayOnTargetOTP(for: error),
           let ticket,
           let restoreTargetOTP {
            identityTargetOTPCode = ""
            identityFlowState = .targetOTP(
                operation,
                ticket: ticket,
                otpID: restoreTargetOTP.otpID,
                target: restoreTargetOTP.target
            )
            errorMessage = message
            return
        }
        if shouldStayOnTargetInput(for: error), let ticket {
            identityTargetOTPCode = ""
            lockedIdentityTargetPhone = nil
            lockedIdentityTargetEmail = nil
            identityFlowState = .enteringTarget(operation, ticket: ticket)
            errorMessage = message
            return
        }
        identityFlowState = .failed(message)
    }

    private func shouldRestartIdentityReauth(for error: Error) -> Bool {
        guard case .http(_, let backend, _) = error as? SupportNetworkError else {
            return false
        }
        let ticketErrors: Set<String> = [
            "verification_ticket_expired",
            "verification_ticket_used",
            "verification_ticket_invalid"
        ]
        return ticketErrors.contains(backend?.msg ?? "")
    }

    private func shouldStayOnTargetOTP(for error: Error) -> Bool {
        guard case .http(_, let backend, _) = error as? SupportNetworkError else {
            return false
        }
        let stayErrors: Set<String> = [
            "target_otp_invalid",
            "target_otp_expired",
            "invalid_otp"
        ]
        return stayErrors.contains(backend?.msg ?? "")
    }

    private func shouldStayOnReauthOTP(for error: Error) -> Bool {
        guard case .http(_, let backend, _) = error as? SupportNetworkError else {
            return false
        }
        let stayErrors: Set<String> = [
            "otp_otp_invalid",
            "invalid_otp"
        ]
        return stayErrors.contains(backend?.msg ?? "")
    }

    private func shouldStayOnTargetInput(for error: Error) -> Bool {
        guard case .http(_, let backend, _) = error as? SupportNetworkError else {
            return false
        }
        let stayErrors: Set<String> = [
            "identity_already_bound_to_active_user"
        ]
        return stayErrors.contains(backend?.msg ?? "")
    }

    private func localizedErrorMessage(for error: Error) -> String {
        if let networkError = error as? SupportNetworkError {
            switch networkError {
            case .http(let statusCode, let backend, _):
                return BackendErrorLocalizer.message(for: backend, statusCode: statusCode)
            default:
                break
            }
        }
        return error.localizedDescription
    }

    private func identityProvider(for channel: AccountVerificationChannel) -> AccountIdentityProvider {
        switch channel {
        case .apple:
            return .apple
        case .phone:
            return .phone
        case .email:
            return .email
        }
    }

    private var currentSession: UserSession? {
        if case .signedIn(let currentSession) = sessionStore.state {
            return currentSession
        }
        return nil
    }

    private func clearIdentityFlowInputs(keepTarget: Bool = false) {
        identityReauthOTPCode = ""
        identityTargetOTPCode = ""
        lockedIdentityTargetPhone = nil
        lockedIdentityTargetEmail = nil
        if keepTarget == false {
            identityTargetInput = ""
            identityTargetPhoneInput = PhoneNumberInputModel()
            identityTargetEmailInput = EmailAddressInputModel()
        }
    }

    private func startCountdown(seconds: Int) {
        stopCountdown()
        resendCountdown = seconds
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    guard let self else { return }
                    if self.resendCountdown > 0 {
                        self.resendCountdown -= 1
                    }
                    if self.resendCountdown == 0 {
                        self.stopCountdown()
                    }
                }
            }
        }
    }

    private func stopCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        resendCountdown = 0
    }

    private func startIdentityCountdown(seconds: Int) {
        stopIdentityCountdown()
        identityResendCountdown = seconds
        identityCountdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    guard let self else { return }
                    if self.identityResendCountdown > 0 {
                        self.identityResendCountdown -= 1
                    }
                    if self.identityResendCountdown == 0 {
                        self.stopIdentityCountdown()
                    }
                }
            }
        }
    }

    private func stopIdentityCountdown() {
        identityCountdownTask?.cancel()
        identityCountdownTask = nil
        identityResendCountdown = 0
    }

    deinit {
        countdownTask?.cancel()
        identityCountdownTask?.cancel()
    }
}
