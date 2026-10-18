import Combine
import Foundation

@MainActor
final class AppLifecycleCoordinator: ObservableObject {
    @Published private(set) var sessionState: AppSessionState = .loading
    @Published private(set) var preparedAccountID: Int64?
    @Published private(set) var preparationFailed = false

    private let sessionStore: AppSessionStore
    private let appBootstrapper: AppBootstrapper
    private let deviceRegistration: DeviceRegistrationCoordinator
    private let accountSessionRuntime: AccountSessionRuntime
    private let logger: Logger
    private var cancellables = Set<AnyCancellable>()
    private var didRunSignedOutTask = false
    private var isColdLaunchBootstrapInProgress = false
    private var isHandlingServerAuthInvalidation = false
    private var lastObservedSessionState: AppSessionState = .loading
    private let signedInPreparationRegistry = SignedInSessionPreparationRegistry()

    init(
        sessionStore: AppSessionStore,
        appBootstrapper: AppBootstrapper,
        deviceRegistration: DeviceRegistrationCoordinator,
        accountSessionRuntime: AccountSessionRuntime,
        logger: Logger
    ) {
        self.sessionStore = sessionStore
        self.appBootstrapper = appBootstrapper
        self.deviceRegistration = deviceRegistration
        self.accountSessionRuntime = accountSessionRuntime
        self.logger = logger
        self.sessionState = sessionStore.state
        self.lastObservedSessionState = sessionStore.state
        self.preparedAccountID = signedInPreparationRegistry.preparedAccountID

        sessionStore.$state
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                let previous = self.lastObservedSessionState
                self.lastObservedSessionState = state
                self.sessionState = state
                self.logger.debug("根生命周期：会话状态已同步到根视图 state=\(state.logValue)", module: .lifecycle)
                Task { await self.handleSessionStateTransition(from: previous, to: state) }
            }
            .store(in: &cancellables)
        logger.info("AppLifecycleCoordinator 已初始化", module: .lifecycle)
    }

    func bootstrapLaunchAfterNetworkEvaluation(networkHasEvaluated: Bool, networkSatisfied: Bool) async {
        guard networkHasEvaluated else { return }
        guard networkSatisfied else {
            logger.info("启动流程：网络路径已评估但当前不可用，等待网络恢复后再执行引导与会话恢复", module: .lifecycle)
            return
        }
        logger.info("启动流程：网络路径已评估且可用，开始会话恢复与应用级引导", module: .lifecycle)

        isColdLaunchBootstrapInProgress = true
        defer { isColdLaunchBootstrapInProgress = false }

        await sessionStore.restoreIfNeeded()
        await appBootstrapper.bootstrapAppLaunchIfNeeded()

        switch sessionStore.state {
        case .signedIn(let session):
            await enqueueSignedInPreparation(session: session, reason: .signedInColdLaunch)
        case .signedOut:
            await deviceRegistration.registerGuestDevice(reason: .guestColdLaunch)
        case .loading:
            break
        }
    }

    func handleSignedOutTask() async {
        guard !didRunSignedOutTask else {
            logger.debug("会话流程：已处理未登录态，跳过重复清理", module: .auth)
            return
        }
        didRunSignedOutTask = true
        logger.info("会话流程：进入未登录态，清理账号运行时", module: .auth)
        signedInPreparationRegistry.reset()
        preparedAccountID = nil
        deviceRegistration.reset()
        await appBootstrapper.resetLaunchBootstrap()
        await accountSessionRuntime.activateGuest()
        await deviceRegistration.registerGuestDevice(reason: .guestColdLaunch)
        logger.info("Signed-out session cleanup complete", module: .auth)
    }

    func handleServerAuthInvalidationIfNeeded(invalidationMessage: String = "") async {
        guard isHandlingServerAuthInvalidation == false else { return }

        switch sessionStore.state {
        case .signedOut:
            return
        case .loading, .signedIn:
            break
        }

        logger.warning(
            "认证流程：收到服务端鉴权失效通知，准备强制回到登录态 message=\(invalidationMessage)",
            module: .auth
        )
        isHandlingServerAuthInvalidation = true
        deviceRegistration.suspendPendingSubmissions()
        signedInPreparationRegistry.reset()
        preparedAccountID = nil
        defer { isHandlingServerAuthInvalidation = false }

        await sessionStore.signOut()
        await appBootstrapper.resetLaunchBootstrap()
        await accountSessionRuntime.activateGuest()
        deviceRegistration.reset()
        logger.info("认证流程：服务端鉴权失效处理完成，已回到未登录态", module: .auth)
    }

    /// 兼容旧调用点；正式路径由会话状态迁移统一调度，避免 SwiftUI `.task` 取消。
    func prepareSignedInSession(_ session: UserSession, reason: DeviceRegistrationReason) async {
        await enqueueSignedInPreparation(session: session, reason: reason)
    }

    // MARK: - 已登录准备（单一入口，不经过 SwiftUI .task）

    private func handleSessionStateTransition(
        from previous: AppSessionState,
        to current: AppSessionState
    ) async {
        guard case .signedIn(let session) = current else { return }
        guard isColdLaunchBootstrapInProgress == false else { return }
        guard isHandlingServerAuthInvalidation == false else { return }

        switch previous {
        case .signedOut:
            await enqueueSignedInPreparation(session: session, reason: .signedInColdLaunch)
        case .signedIn(let previousSession) where previousSession.accountID != session.accountID:
            await enqueueSignedInPreparation(session: session, reason: .signedInColdLaunch)
        case .loading:
            break
        default:
            break
        }
    }

    func retrySignedInPreparation() async {
        guard case .signedIn(let session) = sessionStore.state else { return }
        await enqueueSignedInPreparation(session: session, reason: .signedInColdLaunch)
    }

    private func enqueueSignedInPreparation(
        session: UserSession,
        reason: DeviceRegistrationReason
    ) async {
        preparationFailed = false
        await signedInPreparationRegistry.runPreparationIfNeeded(accountID: session.accountID) {
            await self.runSignedInPreparation(session: session, reason: reason)
        }
        guard case .signedIn(let current) = sessionStore.state, current.accountID == session.accountID else { return }
        preparedAccountID = signedInPreparationRegistry.preparedAccountID
        preparationFailed = preparedAccountID != session.accountID && !isHandlingServerAuthInvalidation
    }

    private func runSignedInPreparation(
        session: UserSession,
        reason: DeviceRegistrationReason
    ) async {
        logger.info("会话流程：准备账号运行时 accountID=\(session.accountID)", module: .auth)
        didRunSignedOutTask = false

        logger.debug(
            "会话流程：准备步骤 activateUser 开始 accountID=\(session.accountID)",
            module: .auth
        )
        await accountSessionRuntime.activateUser(accountID: session.accountID)

        logger.debug(
            "会话流程：准备步骤 signedInDeviceRegistration 开始 accountID=\(session.accountID) reason=\(reason.rawValue)",
            module: .auth
        )
        let registrationOutcome = await deviceRegistration.requestRegisterWithLimitedRetry(
            reason: reason,
            session: session
        )
        switch registrationOutcome {
        case .authSessionInvalidated:
            logger.warning(
                "会话流程：设备登记鉴权失效，中止账号级引导 accountID=\(session.accountID)",
                module: .auth
            )
            signedInPreparationRegistry.rollbackPreparingIfNeeded(accountID: session.accountID)
            return
        case .failedRetryable:
            logger.warning(
                "会话流程：设备登记失败且重试已用尽，中止账号级引导 accountID=\(session.accountID)",
                module: .auth
            )
            signedInPreparationRegistry.rollbackPreparingIfNeeded(accountID: session.accountID)
            return
        case .submitted, .skippedSameLaunchSubmission:
            break
        }

        guard registrationOutcome.allowsAccountBootstrap else {
            signedInPreparationRegistry.rollbackPreparingIfNeeded(accountID: session.accountID)
            return
        }

        guard case .signedIn = sessionStore.state, isHandlingServerAuthInvalidation == false else {
            logger.warning(
                "会话流程：设备登记后鉴权失效，跳过后续账号级引导 accountID=\(session.accountID)",
                module: .auth
            )
            signedInPreparationRegistry.rollbackPreparingIfNeeded(accountID: session.accountID)
            return
        }

        logger.debug(
            "会话流程：准备步骤 bootstrapIfNeeded 开始 accountID=\(session.accountID)",
            module: .auth
        )
        await appBootstrapper.bootstrapAccountIfNeeded(accountID: session.accountID)

        guard case .signedIn = sessionStore.state, isHandlingServerAuthInvalidation == false else {
            logger.warning(
                "会话流程：账号引导后鉴权失效，跳过标记 prepared accountID=\(session.accountID)",
                module: .auth
            )
            signedInPreparationRegistry.rollbackPreparingIfNeeded(accountID: session.accountID)
            return
        }

        signedInPreparationRegistry.markPrepared(accountID: session.accountID)
        preparedAccountID = session.accountID
        logger.info("Prepared signed-in account \(session.accountID)", module: .auth)
        logger.info("会话流程：账号运行时准备完成 accountID=\(session.accountID)", module: .auth)
    }
}

extension AppSessionState {
    var logValue: String {
        switch self {
        case .loading: return "loading"
        case .signedOut: return "signedOut"
        case .signedIn(let session): return "signedIn(\(session.accountID))"
        }
    }
}
