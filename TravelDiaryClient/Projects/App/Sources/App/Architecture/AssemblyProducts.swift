import Foundation

/// App 级基础设施装配产物。
struct AppInfrastructureAssemblyProduct {
    let storageService: StorageService
    let storageRegistry: StorageRegistry
    let fileCacheManager: FileCacheManager
    let ossConfigurationStore: SupportOSSConfigurationStore
    let fileTransferService: FileTransferService
    let ocrOrchestrator: OCROrchestrator
}

/// 认证领域装配产物。
struct AuthAssemblyProduct {
    let sessionSnapshotStore: SessionSnapshotStore
    let authRepository: any AuthRepository
    let restoreSessionUseCase: RestoreSessionUseCase
    let accountManagementRepository: AccountManagementRepository
    let signOutUseCase: SignOutUseCase
    let deviceRegistrationCoordinator: DeviceRegistrationCoordinator
}

/// AI 领域装配产物。
struct AIAssemblyProduct {
    let aiSettingsRepository: any AISettingsRepository
    let aiRuntimeStore: AIRuntimeStore
    let aiRuntimeConfigStore: AIRuntimeConfigStore
    let aiConfigCenter: AIConfigCenter
    let localModelService: LocalModelService
}

/// 通知领域装配产物。
struct NotificationAssemblyProduct {
    let routeCoordinator: RouteCoordinator
    let notificationStore: NotificationStore
    let notificationMetricsStore: NotificationMetricsStore
    let notificationInboxStore: NotificationInboxStore
    let notificationQueue: NotificationQueue
    let notificationDeliveryCoordinator: NotificationDeliveryCoordinator
    let publishNotificationUseCase: PublishNotificationUseCase
    let notificationClient: any NotificationClient
}

enum AppAssembly {
    static func makeInfrastructure(
        environment: SupportAppEnvironment,
        backend: SupportBackend,
        logger: Logger
    ) -> AppInfrastructureAssemblyProduct {
        logger.info("AppAssembly 装配基础设施", module: .app)

        let ossConfigurationStore = SupportOSSConfigurationStore(logger: logger)
        let ossManager = OSSManager.shared
        let ossClient = OSSClientWrapper(manager: ossManager)
        ossManager.credentialsProvider = { [weak ossConfigurationStore, backend] in
            guard let store = ossConfigurationStore else {
                throw SupportOSSConfigurationError.incompleteSTSResponse
            }
            let config = try await store.configurationForUpload(using: backend.oss)
            return OSSCredentials(
                accessKeyId: config.accessKeyId,
                accessKeySecret: config.accessKeySecret,
                securityToken: config.securityToken,
                expiration: config.credentialExpiresAt
            )
        }

        let fileCacheManager = FileCacheManager(logger: logger)
        let fileTransferService = FileTransferService(
            api: backend.files,
            ossAPI: backend.oss,
            ossClient: ossClient,
            ossRuntimeConfigurator: ossManager,
            ossConfigurationStore: ossConfigurationStore,
            cacheManager: fileCacheManager,
            logger: logger
        )

        let ocrConfiguration = environment.ocrConfiguration
        let aliyunEngine: OCRTextEngine? = ocrConfiguration.enableAliyunOCR
            ? AliyunOCREngine(credentialsProvider: BackendOCRCredentialsProvider(api: backend.ocr))
            : nil
        let localServerEngine: OCRTextEngine? = {
            guard ocrConfiguration.enableLocalServerOCR,
                  !ocrConfiguration.localServerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return LocalServerOCREngine(
                baseURL: ocrConfiguration.localServerBaseURL,
                timeoutMs: ocrConfiguration.localServerTimeoutMs,
                authToken: ocrConfiguration.localServerAuthToken
            )
        }()
        let ocrOrchestrator = OCROrchestrator(
            config: ocrConfiguration,
            aliyunEngine: aliyunEngine,
            localServerEngine: localServerEngine,
            logger: logger
        )

        Task.detached(priority: .utility) { LegacyCacheMigration.run(cache: .shared) }
        let storageService = StorageService()
        let storageRegistry = StorageRegistry.live(
            storageService: storageService,
            fileCacheManager: fileCacheManager,
            fileTransferService: fileTransferService,
            logger: logger
        )

        return AppInfrastructureAssemblyProduct(
            storageService: storageService,
            storageRegistry: storageRegistry,
            fileCacheManager: fileCacheManager,
            ossConfigurationStore: ossConfigurationStore,
            fileTransferService: fileTransferService,
            ocrOrchestrator: ocrOrchestrator
        )
    }
}

enum AuthAssembly {
    static func makeCore(
        backend: SupportBackend,
        logger: Logger
    ) -> AuthAssemblyProduct {
        logger.info("AuthAssembly 装配认证核心", module: .app)
        let snapshotStore = SessionSnapshotStore(logger: logger)
        let authRepository = DefaultAuthRepository(
            backend: backend,
            snapshotStore: snapshotStore,
            logger: logger
        )
        return AuthAssemblyProduct(
            sessionSnapshotStore: snapshotStore,
            authRepository: authRepository,
            restoreSessionUseCase: RestoreSessionUseCase(authRepository: authRepository),
            accountManagementRepository: DefaultAccountManagementRepository(backend: backend),
            signOutUseCase: SignOutUseCase(authRepository: authRepository),
            deviceRegistrationCoordinator: DeviceRegistrationCoordinator(backend: backend, logger: logger)
        )
    }
}

enum AIAssembly {
    static func makeCore(
        coreDataStack: CoreDataStack,
        backend: SupportBackend,
        sessionSnapshotStore: SessionSnapshotStore,
        logger: Logger
    ) -> AIAssemblyProduct {
        logger.info("AIAssembly 装配 AI 配置与运行时", module: .app)
        let aiRuntimeStore = AIRuntimeStore()
        let aiRuntimeConfigStore = AIRuntimeConfigStore()
        let aiSettingsRepository = DefaultAISettingsRepository(
            coreDataStack: coreDataStack,
            snapshotStore: sessionSnapshotStore,
            logger: logger
        )
        let remoteConfigProvider = BackendAIRemoteConfigProvider(api: backend.aiConfig)
        let aiConfigCenter = AIConfigCenter(
            repository: aiSettingsRepository,
            remoteProvider: remoteConfigProvider,
            runtimeStore: aiRuntimeStore,
            runtimeConfigStore: aiRuntimeConfigStore,
            sessionSnapshotStore: sessionSnapshotStore,
            logger: logger
        )
        return AIAssemblyProduct(
            aiSettingsRepository: aiSettingsRepository,
            aiRuntimeStore: aiRuntimeStore,
            aiRuntimeConfigStore: aiRuntimeConfigStore,
            aiConfigCenter: aiConfigCenter,
            localModelService: LocalModelService()
        )
    }
}

enum NotificationAssembly {
    static func makeCore(logger: Logger) -> NotificationAssemblyProduct {
        logger.info("NotificationAssembly 装配通知核心", module: .app)
        let notificationStore = NotificationStore()
        let notificationMetricsStore = NotificationMetricsStore()
        let notificationInboxStore = NotificationInboxStore()
        let notificationQueue = NotificationQueue(
            metricsStore: notificationMetricsStore,
            inboxStore: notificationInboxStore,
            logger: logger
        )
        let notificationDelivery = NotificationDeliveryCoordinator(
            queue: notificationQueue,
            store: notificationStore,
            inboxStore: notificationInboxStore,
            metricsStore: notificationMetricsStore
        )
        let publishNotificationUseCase = PublishNotificationUseCase(
            queue: notificationQueue,
            deliveryCoordinator: notificationDelivery,
            logger: logger
        )
        let notificationClient = DefaultNotificationClient(publishUseCase: publishNotificationUseCase)
        notificationDelivery.startIfNeeded()
        let routeCoordinator = RouteCoordinator(logger: logger)
        return NotificationAssemblyProduct(
            routeCoordinator: routeCoordinator,
            notificationStore: notificationStore,
            notificationMetricsStore: notificationMetricsStore,
            notificationInboxStore: notificationInboxStore,
            notificationQueue: notificationQueue,
            notificationDeliveryCoordinator: notificationDelivery,
            publishNotificationUseCase: publishNotificationUseCase,
            notificationClient: notificationClient
        )
    }
}
