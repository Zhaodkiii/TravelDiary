import Foundation

/// 统一网络门面（对齐 Spark `Backend`，不含医疗业务 API）。
final class SupportBackend {
    let baseURL: URL
    let configuration: SupportBackendConfiguration
    let engine: SupportNetworkEngine
    let deviceCache: DeviceCache

    let auth: SupportAuthAPI
    let otp: SupportOTPAPI
    let device: SupportDeviceAPI
    let files: SupportFileAPI
    let oss: SupportOSSAPI
    let ocr: SupportOCRAPI
    let aiConfig: SupportAIConfigAPI
    let deactivation: SupportDeactivationAPI
    let accountIdentity: SupportAccountIdentityAPI

    init(
        baseURL: URL,
        transport: SupportNetworkTransport? = nil,
        gate: SerialRequestGate = SerialRequestGate(),
        deviceCache: DeviceCache = DeviceCache(),
        retryPolicy: RetryPolicy = RetryPolicy(),
        authProvider: AuthTokenProvider? = nil,
        logger: Logger = ConsoleLogger()
    ) {
        self.baseURL = baseURL
        if let level = deviceCache.persistedLogLevel {
            SupportLogger.logLevel = level
        }

        let transport = transport ?? URLSessionNetworkTransport(logger: logger)
        let etagInterceptor = ETagHTTPInterceptor(store: deviceCache, logger: logger)
        let engine = SupportNetworkEngine(
            baseURL: baseURL,
            transport: transport,
            gate: gate,
            etagInterceptor: etagInterceptor,
            retryPolicy: retryPolicy,
            authProvider: authProvider,
            deviceCache: deviceCache,
            logger: logger
        )
        let configuration = SupportBackendConfiguration(
            engine: engine,
            deviceCache: deviceCache,
            logger: logger
        )
        self.engine = engine
        self.configuration = configuration
        self.deviceCache = deviceCache
        self.auth = SupportAuthAPI(configuration: configuration)
        self.otp = SupportOTPAPI(configuration: configuration)
        self.device = SupportDeviceAPI(configuration: configuration)
        self.files = SupportFileAPI(configuration: configuration)
        self.oss = SupportOSSAPI(configuration: configuration)
        self.ocr = SupportOCRAPI(configuration: configuration)
        self.aiConfig = SupportAIConfigAPI(configuration: configuration)
        self.deactivation = SupportDeactivationAPI(configuration: configuration)
        self.accountIdentity = SupportAccountIdentityAPI(configuration: configuration)
        logger.info(SupportNetworkingStrings.Backend.initialized, module: .network)
    }

    /// 测试与自定义 engine 注入入口。
    init(engine: SupportNetworkEngine, deviceCache: DeviceCache = DeviceCache(), logger: Logger? = nil) {
        let logger = logger ?? engine.networkLogger
        self.baseURL = engine.serviceBaseURL
        let configuration = SupportBackendConfiguration(
            engine: engine,
            deviceCache: deviceCache,
            logger: logger
        )
        self.engine = engine
        self.configuration = configuration
        self.deviceCache = deviceCache
        self.auth = SupportAuthAPI(configuration: configuration)
        self.otp = SupportOTPAPI(configuration: configuration)
        self.device = SupportDeviceAPI(configuration: configuration)
        self.files = SupportFileAPI(configuration: configuration)
        self.oss = SupportOSSAPI(configuration: configuration)
        self.ocr = SupportOCRAPI(configuration: configuration)
        self.aiConfig = SupportAIConfigAPI(configuration: configuration)
        self.deactivation = SupportDeactivationAPI(configuration: configuration)
        self.accountIdentity = SupportAccountIdentityAPI(configuration: configuration)
        logger.info(SupportNetworkingStrings.Backend.initialized, module: .network)
    }

    func tokenProvider() -> AuthTokenProvider { engine.tokenProvider() }
}
