import Foundation

/// 账号运行时：统一管理账号级内存状态和缓存失效。
///
/// Support 裁剪版：不含 Member / Knowledge / 医疗导入。
@MainActor
final class AccountSessionRuntime {
    private enum Mode: Equatable {
        case guest
        case account(Int64)
    }

    private let routeCoordinator: RouteCoordinator
    private let storageRegistry: StorageRegistry
    private let aiConfigCenter: AIConfigCenter
    private let logger: Logger
    private let clearSessionScopedViewModels: () -> Void
    private var mode: Mode?
    private(set) var isAccountSwitchInProgress = false
    private var suspendedAccountIDForSwitch: Int64?

    init(
        routeCoordinator: RouteCoordinator,
        storageRegistry: StorageRegistry,
        aiConfigCenter: AIConfigCenter,
        logger: Logger,
        clearSessionScopedViewModels: @escaping () -> Void
    ) {
        self.routeCoordinator = routeCoordinator
        self.storageRegistry = storageRegistry
        self.aiConfigCenter = aiConfigCenter
        self.logger = logger
        self.clearSessionScopedViewModels = clearSessionScopedViewModels
    }

    /// 同设备账号切换登录前：标记切换中（Support 无实时 Chat 同步可暂停）。
    func beginAccountSwitch(suspendedAccountID: Int64?) async {
        guard isAccountSwitchInProgress == false else { return }
        isAccountSwitchInProgress = true
        suspendedAccountIDForSwitch = suspendedAccountID
        logger.info(
            "账号运行时：账号切换登录开始 accountID=\(suspendedAccountID.map(String.init) ?? "-")",
            module: .auth
        )
    }

    /// 登录流程结束：commit=true 表示已切到新账号。
    func endAccountSwitch(commit: Bool, currentSignedInAccountID: Int64?) async {
        defer {
            isAccountSwitchInProgress = false
            suspendedAccountIDForSwitch = nil
        }
        if commit {
            logger.info(
                "账号运行时：账号切换登录提交 current=\(currentSignedInAccountID.map(String.init) ?? "-")",
                module: .auth
            )
        } else {
            logger.info("账号运行时：账号切换登录取消/失败", module: .auth)
        }
    }

    func activateUser(accountID: Int64) async {
        if mode == .account(accountID) {
            logger.debug("账号运行时：账号未变化，跳过重复初始化 accountID=\(accountID)", module: .auth)
            return
        }

        let previousAccountID = currentAccountID
        logger.info("账号运行时：开始切换到账号 accountID=\(accountID)", module: .auth)
        await storageRegistry.prepareForAccountSwitch(from: previousAccountID, to: accountID)
        await aiConfigCenter.resetRuntimeCaches()
        routeCoordinator.resetRouteGraphForAccountRuntime(reason: "accountSwitch(\(accountID))")
        clearSessionScopedViewModels()
        mode = .account(accountID)
        logger.info("账号运行时：账号切换完成 accountID=\(accountID)", module: .auth)
    }

    func activateGuest() async {
        if mode == .guest {
            logger.debug("账号运行时：已处于未登录运行时，跳过重复清理", module: .auth)
            return
        }

        let previousAccountID = currentAccountID
        logger.info("账号运行时：切换到访客/未登录运行时", module: .auth)
        await storageRegistry.prepareForSignOut(from: previousAccountID)
        await aiConfigCenter.resetRuntimeCaches()
        routeCoordinator.resetRouteGraphForAccountRuntime(reason: "signOut")
        clearSessionScopedViewModels()
        mode = .guest
    }

    private var currentAccountID: Int64? {
        if case .account(let accountID) = mode {
            return accountID
        }
        return nil
    }
}

extension AccountSessionRuntime: LoginAccountSwitchHandling {
    func beginLoginAccountSwitch(suspendedAccountID: Int64?) async {
        await beginAccountSwitch(suspendedAccountID: suspendedAccountID)
    }

    func endLoginAccountSwitch(commit: Bool, currentSignedInAccountID: Int64?) async {
        await endAccountSwitch(commit: commit, currentSignedInAccountID: currentSignedInAccountID)
    }
}
