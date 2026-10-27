import Foundation

/// 统一存储策略注册表：记录存储归属，也提供账号切换/登出时的可执行清理入口。
struct StorageRegistry {
    enum Backend: String, Sendable {
        case coreData
        case userDefaults
        case keychain
        case fileSystem
        case memory
        case remote
    }

    enum ResetReason: Sendable {
        case accountSwitch(fromAccountID: Int64?, toAccountID: Int64)
        case signOut(fromAccountID: Int64?)

        var logValue: String {
            switch self {
            case .accountSwitch(let fromAccountID, let toAccountID):
                return "accountSwitch(from=\(fromAccountID.map(String.init) ?? "-"), to=\(toAccountID))"
            case .signOut(let fromAccountID):
                return "signOut(from=\(fromAccountID.map(String.init) ?? "-"))"
            }
        }
    }

    struct Entry: Identifiable {
        let id: String
        let backend: Backend
        let scope: DependencyScope
        let accountIsolated: Bool
        let owner: String
        let resetPolicy: String
        let reset: @MainActor (_ reason: ResetReason) async -> Void
    }

    let entries: [Entry]
    private let logger: Logger

    init(entries: [Entry], logger: Logger = ConsoleLogger()) {
        self.entries = entries
        self.logger = logger
    }

    /// 统一 key 命名：`support.<domain>.<name>[.account.<id>]`。
    func key(domain: String, name: String, accountID: Int64? = nil) -> String {
        let normalizedDomain = normalize(domain)
        let normalizedName = normalize(name)
        if let accountID {
            return "support.\(normalizedDomain).\(normalizedName).account.\(accountID)"
        }
        return "support.\(normalizedDomain).\(normalizedName)"
    }

    @MainActor
    func prepareForAccountSwitch(from fromAccountID: Int64?, to accountID: Int64) async {
        await executeReset(reason: .accountSwitch(fromAccountID: fromAccountID, toAccountID: accountID))
    }

    @MainActor
    func prepareForSignOut(from fromAccountID: Int64?) async {
        await executeReset(reason: .signOut(fromAccountID: fromAccountID))
    }

    @MainActor
    private func executeReset(reason: ResetReason) async {
        logger.info("存储策略：开始执行统一清理 reason=\(reason.logValue)", module: .general)
        for entry in entries {
            await entry.reset(reason)
        }
        logger.info("存储策略：统一清理完成 reason=\(reason.logValue)", module: .general)
    }

    private func normalize(_ raw: String) -> String {
        raw.lowercased()
            .split { character in
                character == "." || character == "_" || character == "-" || character == " "
            }
            .joined(separator: ".")
    }

    static func live(
        storageService: StorageService,
        fileCacheManager: FileCacheManager,
        fileTransferService: FileTransferService,
        logger: Logger
    ) -> StorageRegistry {
        return StorageRegistry(entries: [
            Entry(id: "storage.resourceCatalog", backend: .fileSystem, scope: .accountScoped,
                  accountIsolated: true, owner: "StorageService", resetPolicy: "Invalidate scoped plans before session changes.", reset: { reason in
                switch reason {
                case .accountSwitch(_, let accountID):
                    PreviewImagePipeline.shared.activate(owner: String(accountID))
                    PresetPreviewRepository.shared.reset()
                    await storageService.activate(owner: String(accountID))
                case .signOut:
                    PreviewImagePipeline.shared.activate(owner: nil)
                    PresetPreviewRepository.shared.reset()
                    await storageService.activate(owner: nil)
                }
            }),
            Entry(
                id: "coreData.supportClient",
                backend: .coreData,
                scope: .appSingleton,
                accountIsolated: true,
                owner: "CoreDataStack",
                resetPolicy: "Persistent rows are filtered by account where applicable; not deleted on sign-out.",
                reset: { _ in }
            ),
            Entry(
                id: "userDefaults.aiPreferences",
                backend: .userDefaults,
                scope: .accountScoped,
                accountIsolated: true,
                owner: "DefaultAISettingsRepository",
                resetPolicy: "Keyed by owner account ID; preserved across sign-out for the same account.",
                reset: { _ in }
            ),
            Entry(
                id: "keychain.deviceAndTokens",
                backend: .keychain,
                scope: .appSingleton,
                accountIsolated: false,
                owner: "SparkKeychain / AuthTokenProvider",
                resetPolicy: "Device ID survives sign-out; auth tokens are cleared by sign-out use case.",
                reset: { _ in }
            ),
            Entry(
                id: "fileCache.attachments",
                backend: .fileSystem,
                scope: .accountScoped,
                accountIsolated: true,
                owner: "FileCacheManager",
                resetPolicy: "Account context is switched before user runtime activation; sign-out moves cache back to guest namespace.",
                reset: { reason in
                    switch reason {
                    case .accountSwitch(_, let toAccountID):
                        await fileCacheManager.activateAccountContext(toAccountID)
                    case .signOut:
                        await fileCacheManager.activateGuestContext()
                    }
                }
            ),
            Entry(
                id: "oss.runtimeCredentials",
                backend: .memory,
                scope: .accountScoped,
                accountIsolated: true,
                owner: "SupportOSSConfigurationStore / OSSManager",
                resetPolicy: "STS snapshot and runtime OSS credentials are cleared on sign-out or account switch.",
                reset: { _ in
                    await fileTransferService.resetRuntimeCredentials()
                }
            ),
            Entry(
                id: "memory.accountRuntime",
                backend: .memory,
                scope: .accountScoped,
                accountIsolated: true,
                owner: "AccountSessionRuntime",
                resetPolicy: "Reset on sign-out and before a new account session is activated.",
                reset: { _ in }
            ),
        ], logger: logger)
    }
}
