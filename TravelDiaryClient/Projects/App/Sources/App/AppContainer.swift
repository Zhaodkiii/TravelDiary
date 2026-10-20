import Combine
import Foundation

@MainActor
struct AppContentDependencies {
    let notificationStore: NotificationStore
    let notificationClient: any NotificationClient
    let routeCoordinator: RouteCoordinator
    let notificationDeliveryCoordinator: NotificationDeliveryCoordinator
    let coordinator: AppCoordinatorDependencies
}

@MainActor
struct AppCoordinatorDependencies {
    let storageService: StorageService
    let sessionStore: AppSessionStore
    let lifecycle: AppLifecycleCoordinator
    let authRepository: AuthRepository
    let accountManagementRepository: AccountManagementRepository
    let makeAISettingsViewModel: (Int64) -> AISettingsViewModel
    let makeLoginViewModel: () -> LoginViewModel
    let makeAccountManagementViewModel: () -> AccountManagementViewModel
    let notificationStore: NotificationStore
}

@MainActor
final class AppContainer {
    let environment: SupportAppEnvironment
    let backend: SupportBackend
    let coreDataStack: CoreDataStack
    let contentDependencies: AppContentDependencies
    let aiSettingsRepository: any AISettingsRepository
    let aiRuntimeStore: AIRuntimeConfigStore
    let aiConfigCenter: AIConfigCenter
    let ossConfigurationStore: SupportOSSConfigurationStore
    let fileCacheManager: FileCacheManager
    let fileTransferService: FileTransferService
    let ocrOrchestrator: OCROrchestrator
    let accountSessionRuntime: AccountSessionRuntime

    private let logger: ConsoleLogger
    private var aiSettingsViewModelCache = AccountScopedCache<AISettingsViewModel>()

    private init(
        environment: SupportAppEnvironment,
        backend: SupportBackend,
        coreDataStack: CoreDataStack,
        contentDependencies: AppContentDependencies,
        aiSettingsRepository: any AISettingsRepository,
        aiRuntimeStore: AIRuntimeConfigStore,
        aiConfigCenter: AIConfigCenter,
        ossConfigurationStore: SupportOSSConfigurationStore,
        fileCacheManager: FileCacheManager,
        fileTransferService: FileTransferService,
        ocrOrchestrator: OCROrchestrator,
        accountSessionRuntime: AccountSessionRuntime,
        logger: ConsoleLogger
    ) {
        self.environment = environment
        self.backend = backend
        PresetDownloadManager.shared.configure(engine: backend.engine)
        PrintOrderService.shared.configure(engine: backend.engine, sessions: contentDependencies.coordinator.sessionStore)
        CustomizationService.shared.configure(engine: backend.engine, sessions: contentDependencies.coordinator.sessionStore)
        self.coreDataStack = coreDataStack
        self.contentDependencies = contentDependencies
        self.aiSettingsRepository = aiSettingsRepository
        self.aiRuntimeStore = aiRuntimeStore
        self.aiConfigCenter = aiConfigCenter
        self.ossConfigurationStore = ossConfigurationStore
        self.fileCacheManager = fileCacheManager
        self.fileTransferService = fileTransferService
        self.ocrOrchestrator = ocrOrchestrator
        self.accountSessionRuntime = accountSessionRuntime
        self.logger = logger
    }

    static func live() -> AppContainer {
        live(environment: SupportAppEnvironment.current)
    }

    static func live(environment: SupportAppEnvironment) -> AppContainer {
        SupportLogger.configure(level: environment.logLevel, subsystem: environment.subsystem)
        let logger = ConsoleLogger()
        logger.info("AppContainer 开始组合各领域 Assembly", module: .app)

        let backend = SupportBackend(baseURL: environment.apiBaseURL, logger: logger)
        let coreDataStack = CoreDataStack.shared

        let infrastructure = AppAssembly.makeInfrastructure(
            environment: environment,
            backend: backend,
            logger: logger
        )
        let auth = AuthAssembly.makeCore(backend: backend, logger: logger)
        let notification = NotificationAssembly.makeCore(logger: logger)
        let ai = AIAssembly.makeCore(
            coreDataStack: coreDataStack,
            backend: backend,
            sessionSnapshotStore: auth.sessionSnapshotStore,
            logger: logger
        )

        let tokenProvider = backend.tokenProvider()
        let sessionStore = AppSessionStore(
            snapshotStore: auth.sessionSnapshotStore,
            tokenProvider: tokenProvider,
            logger: logger
        )
        sessionStore.bindRestoreSessionUseCase(auth.restoreSessionUseCase)

        logger.info("AppAssembly 装配启动协调器", module: .app)
        let bootstrapper = AppBootstrapper(
            aiConfigCenter: ai.aiConfigCenter,
            ossConfigurationStore: infrastructure.ossConfigurationStore,
            ossAPI: backend.oss,
            logger: logger
        )

        var container: AppContainer!
        let accountSessionRuntime = AccountSessionRuntime(
            routeCoordinator: notification.routeCoordinator,
            storageRegistry: infrastructure.storageRegistry,
            aiConfigCenter: ai.aiConfigCenter,
            logger: logger,
            clearSessionScopedViewModels: { container.clearSessionCaches() }
        )
        let lifecycle = AppLifecycleCoordinator(
            sessionStore: sessionStore,
            appBootstrapper: bootstrapper,
            deviceRegistration: auth.deviceRegistrationCoordinator,
            accountSessionRuntime: accountSessionRuntime,
            logger: logger
        )
        notification.routeCoordinator.bind(lifecycle: lifecycle)
        PushAdapter.shared.configure(sessions: sessionStore, devices: auth.deviceRegistrationCoordinator, client: notification.notificationClient)

        container = AppContainer(
            environment: environment,
            backend: backend,
            coreDataStack: coreDataStack,
            contentDependencies: AppContentDependencies(
                notificationStore: notification.notificationStore,
                notificationClient: notification.notificationClient,
                routeCoordinator: notification.routeCoordinator,
                notificationDeliveryCoordinator: notification.notificationDeliveryCoordinator,
                coordinator: AppCoordinatorDependencies(
                    storageService: infrastructure.storageService,
                    sessionStore: sessionStore,
                    lifecycle: lifecycle,
                    authRepository: auth.authRepository,
                    accountManagementRepository: auth.accountManagementRepository,
                    makeAISettingsViewModel: { ownerAccountID in
                        container.makeAISettingsViewModel(ownerAccountID: ownerAccountID)
                    },
                    makeLoginViewModel: {
                        LoginViewModel(
                            signInWithAppleUseCase: SignInWithAppleUseCase(authRepository: auth.authRepository),
                            signInWithDeviceUseCase: SignInWithDeviceUseCase(authRepository: auth.authRepository),
                            requestPhoneOTPUseCase: RequestPhoneOTPUseCase(authRepository: auth.authRepository),
                            signInWithPhoneOTPUseCase: SignInWithPhoneOTPUseCase(authRepository: auth.authRepository),
                            sessionStore: sessionStore,
                            notificationClient: notification.notificationClient,
                            accountSwitchHandler: accountSessionRuntime
                        )
                    },
                    makeAccountManagementViewModel: {
                        AccountManagementViewModel(
                            loadAccountProfileUseCase: LoadAccountProfileUseCase(
                                repository: auth.accountManagementRepository
                            ),
                            loadAccountIdentitiesUseCase: LoadAccountIdentitiesUseCase(
                                repository: auth.accountManagementRepository
                            ),
                            requestAccountVerificationUseCase: RequestAccountVerificationUseCase(
                                repository: auth.accountManagementRepository
                            ),
                            requestIdentityVerificationUseCase: RequestIdentityVerificationUseCase(
                                repository: auth.accountManagementRepository
                            ),
                            verifyIdentityVerificationUseCase: VerifyIdentityVerificationUseCase(
                                repository: auth.accountManagementRepository
                            ),
                            bindAccountIdentityUseCase: BindAccountIdentityUseCase(
                                repository: auth.accountManagementRepository
                            ),
                            changeAccountIdentityUseCase: ChangeAccountIdentityUseCase(
                                repository: auth.accountManagementRepository
                            ),
                            submitAccountDeactivationUseCase: SubmitAccountDeactivationUseCase(
                                repository: auth.accountManagementRepository
                            ),
                            accountManagementRepository: auth.accountManagementRepository,
                            signOutUseCase: auth.signOutUseCase,
                            sessionStore: sessionStore
                        )
                    },
                    notificationStore: notification.notificationStore
                )
            ),
            aiSettingsRepository: ai.aiSettingsRepository,
            aiRuntimeStore: ai.aiRuntimeConfigStore,
            aiConfigCenter: ai.aiConfigCenter,
            ossConfigurationStore: infrastructure.ossConfigurationStore,
            fileCacheManager: infrastructure.fileCacheManager,
            fileTransferService: infrastructure.fileTransferService,
            ocrOrchestrator: infrastructure.ocrOrchestrator,
            accountSessionRuntime: accountSessionRuntime,
            logger: logger
        )
        logger.info("AppContainer 组合完成：容器仅持有 Assembly facade 与共享运行时", module: .app)
        return container
    }

    func clearSessionCaches() {
        aiSettingsViewModelCache.clear()
        logger.info("账号级 ViewModel 与主 Tab 依赖缓存已清理", module: .auth)
    }

    func makeAISettingsViewModel(ownerAccountID: Int64) -> AISettingsViewModel {
        if aiSettingsViewModelCache.matches(ownerAccountID),
           let cached = aiSettingsViewModelCache.value {
            return cached
        }
        let created = AISettingsViewModel(
            loadUseCase: LoadAISettingsUseCase(repository: aiSettingsRepository),
            saveUseCase: SaveAISettingsUseCase(repository: aiSettingsRepository),
            localModelService: LocalModelService(),
            ownerAccountIDForLoad: ownerAccountID,
            coreDataStack: coreDataStack,
            aiConfigAPI: backend.aiConfig,
            aiConfigCenter: aiConfigCenter,
            promptTooling: DefaultAISettingsPromptTooling(ocrOrchestrator: ocrOrchestrator)
        )
        aiSettingsViewModelCache.store(created, ownerAccountID: ownerAccountID)
        return created
    }
}
