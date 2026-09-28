import Foundation

actor AppBootstrapper {
    private let aiConfigCenter: AIConfigCenter
    private let ossConfigurationStore: SupportOSSConfigurationStore
    private let ossAPI: SupportOSSAPI
    private let logger: Logger
    private var launched = false
    private var bootstrappedAccountIDs = Set<Int64>()

    init(
        aiConfigCenter: AIConfigCenter,
        ossConfigurationStore: SupportOSSConfigurationStore,
        ossAPI: SupportOSSAPI,
        logger: Logger
    ) {
        self.aiConfigCenter = aiConfigCenter
        self.ossConfigurationStore = ossConfigurationStore
        self.ossAPI = ossAPI
        self.logger = logger
    }

    func resetLaunchBootstrap() {
        launched = false
        bootstrappedAccountIDs.removeAll()
        logger.debug("AppBootstrapper：启动引导状态已重置", module: .lifecycle)
    }

    func bootstrapAppLaunchIfNeeded() async {
        guard !launched else {
            logger.debug("AppBootstrapper：应用级引导已完成，跳过", module: .lifecycle)
            return
        }
        launched = true
        logger.info("AppBootstrapper：应用级引导完成", module: .lifecycle)
    }

    func bootstrapAccountIfNeeded(accountID: Int64) async {
        guard !bootstrappedAccountIDs.contains(accountID) else {
            logger.debug(
                "AppBootstrapper：账号引导已完成，跳过 accountID=\(accountID)",
                module: .lifecycle
            )
            return
        }

        logger.debug("会话流程：准备步骤 AI prewarm 开始 accountID=\(accountID)", module: .aiConfig)
        await aiConfigCenter.prewarm(ownerAccountID: accountID)

        logger.debug("会话流程：准备步骤 remote AI config 开始 accountID=\(accountID)", module: .aiConfig)
        await aiConfigCenter.refreshRemoteConfig(ownerAccountID: accountID)

        logger.debug(
            "会话流程：准备步骤 OSS STS prefetch 开始 accountID=\(accountID) phase=bootstrapIfNeeded",
            module: .oss
        )
        await ossConfigurationStore.prefetchFromBackend(
            using: ossAPI,
            ownerAccountID: accountID,
            phase: "bootstrapIfNeeded"
        )

        bootstrappedAccountIDs.insert(accountID)
        logger.info("Account \(accountID) bootstrap complete", module: .aiConfig)
    }
}
