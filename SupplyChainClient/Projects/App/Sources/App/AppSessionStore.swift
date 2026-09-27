import Foundation
import Combine

enum AppSessionState: Equatable, Sendable {
    case loading
    case signedOut
    case signedIn(UserSession)
}

@MainActor
final class AppSessionStore: ObservableObject {
    @Published private(set) var state: AppSessionState = .loading

    private var restoreSessionUseCase: RestoreSessionUseCase?
    private let snapshotStore: SessionSnapshotStore
    private let tokenProvider: AuthTokenProvider
    private let logger: Logger
    private var didRestore = false

    init(
        snapshotStore: SessionSnapshotStore,
        tokenProvider: AuthTokenProvider,
        restoreSessionUseCase: RestoreSessionUseCase? = nil,
        logger: Logger = ConsoleLogger()
    ) {
        self.snapshotStore = snapshotStore
        self.tokenProvider = tokenProvider
        self.restoreSessionUseCase = restoreSessionUseCase
        self.logger = logger
    }

    /// 解决与 `DefaultAuthRepository` 的循环依赖：先构造 sessionStore，再注入 restore use case。
    func bindRestoreSessionUseCase(_ useCase: RestoreSessionUseCase) {
        restoreSessionUseCase = useCase
    }

    /// App 冷启动仅恢复一次；恢复逻辑由仓储负责校验 token 与合并远端 session。
    func restoreIfNeeded() async {
        guard !didRestore else { return }
        didRestore = true

        guard let restoreSessionUseCase else {
            logger.error("AppSessionStore：restoreSessionUseCase 未绑定，进入 signedOut", module: .auth)
            state = .signedOut
            return
        }

        if let session = await restoreSessionUseCase.execute() {
            state = .signedIn(session)
            await verifyPersistedSnapshotMatchesMemory(session, context: "restoreIfNeeded")
            logger.info(
                "AppSessionStore：冷启动会话已恢复 accountID=\(session.accountID) isPro=\(session.isPro)",
                module: .auth
            )
        } else {
            logger.info("AppSessionStore：冷启动无可用会话，进入 signedOut", module: .auth)
            state = .signedOut
        }
    }

    /// 登录成功后仅切换 UI 状态。快照与 Keychain token 已由认证仓储写入。
    func setAuthenticated(_ session: UserSession) {
        state = .signedIn(session)
        logger.info(
            "AppSessionStore：设置已登录状态 accountID=\(session.accountID) isPro=\(session.isPro)",
            module: .auth
        )
        Task { await verifyPersistedSnapshotMatchesMemory(session, context: "setAuthenticated") }
    }

    /// 完整登出清理（鉴权失效等路径）：清 snapshot + token + UI 状态。
    func signOut() async {
        await snapshotStore.clear()
        await tokenProvider.clearTokens()
        state = .signedOut
        logger.info("AppSessionStore：已登出并清理本地会话", module: .auth)
    }

    /// 仓储已清理 token/snapshot 后，仅切换内存 UI 为未登录。
    func setSignedOut() {
        state = .signedOut
        logger.info("AppSessionStore：设置未登录状态", module: .auth)
    }

    /// 检测「内存 signedIn」与 SessionSnapshotStore 是否一致。
    private func verifyPersistedSnapshotMatchesMemory(_ session: UserSession, context: String) async {
        guard let persisted = await snapshotStore.load() else {
            logger.warning(
                "AppSessionStore：\(context) 后内存为 signedIn(accountID=\(session.accountID))，但 SessionSnapshotStore.load()=nil（快照缺失或解码失败）",
                module: .auth
            )
            return
        }
        guard persisted.accountID == session.accountID else {
            logger.warning(
                "AppSessionStore：\(context) 后内存 accountID=\(session.accountID) 与快照 accountID=\(persisted.accountID) 不一致",
                module: .auth
            )
            return
        }
        logger.debug(
            "AppSessionStore：\(context) 后内存与快照一致 accountID=\(session.accountID)",
            module: .auth
        )
    }
}
