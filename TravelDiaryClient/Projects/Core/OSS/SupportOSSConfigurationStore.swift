import Foundation

enum SupportOSSConfigurationError: Error {
    /// STS 返回缺少 bucket/region/endpoint 或 AccessKey
    case incompleteSTSResponse
}

/// 登录后预拉取并缓存阿里云 OSS STS 与桶信息，供后续直传复用。
@MainActor
final class SupportOSSConfigurationStore {
    private(set) var snapshot: AliyunOSSRuntimeConfig?

    private let logger: Logger

    init(logger: Logger = ConsoleLogger()) {
        self.logger = logger
    }

    /// 冷启动 / 登录后由 `AppBootstrapper` 调用：尽力拉取，失败只打日志。
    func prefetchFromBackend(
        using api: SupportOSSAPI,
        ownerAccountID: Int64? = nil,
        phase: String = "bootstrapIfNeeded"
    ) async {
        do {
            let response = try await api.getSTSCredentials()
            guard let cfg = AliyunOSSRuntimeConfig(response: response) else {
                let diagnostics = AliyunOSSRuntimeConfig.incompleteFieldDiagnostics(for: response)
                logger.warning(
                    "OSS STS 预拉取：字段不完整，未缓存 ownerAccountID=\(ownerAccountID.map(String.init) ?? "-") phase=\(phase) \(diagnostics)",
                    module: .oss
                )
                return
            }
            snapshot = cfg
            logger.info(
                "OSS 配置已加载 bucket=\(cfg.bucketName) region=\(cfg.region)",
                module: .oss
            )
        } catch {
            if SupportCancellationClassifier.isCancellation(error) {
                let cancelReason = SupportCancellationClassifier.reason(for: error)
                logger.warning(
                    "OSS STS 预拉取取消 ownerAccountID=\(ownerAccountID.map(String.init) ?? "-") phase=\(phase) cancelledBy=\(cancelReason)",
                    module: .oss
                )
                return
            }
            logger.warning(
                "OSS STS 预拉取失败（后续上传前将重试） ownerAccountID=\(ownerAccountID.map(String.init) ?? "-") error=\(error.localizedDescription)",
                module: .oss
            )
        }
    }

    func clear() {
        snapshot = nil
        logger.debug("OSS STS 缓存已清理", module: .oss)
    }

    /// 上传前调用：优先用缓存；无缓存或临近过期则向服务端刷新。
    func configurationForUpload(using api: SupportOSSAPI) async throws -> AliyunOSSRuntimeConfig {
        if let s = snapshot, s.isFresh(thresholdSeconds: 300) {
            logger.debug(
                "OSS STS 缓存命中 bucket=\(s.bucketName) region=\(s.region)",
                module: .oss
            )
            return s
        }
        let response = try await api.getSTSCredentials()
        guard let cfg = AliyunOSSRuntimeConfig(response: response) else {
            throw SupportOSSConfigurationError.incompleteSTSResponse
        }
        snapshot = cfg
        logger.info(
            "OSS 配置已刷新 bucket=\(cfg.bucketName) region=\(cfg.region)",
            module: .oss
        )
        return cfg
    }
}
