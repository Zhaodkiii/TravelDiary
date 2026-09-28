import Combine
import Foundation

/// 统一路由协调器：鉴权失效等系统事件先进入这里，再交给生命周期协调器。
@MainActor
final class RouteCoordinator {
    private let logger: Logger
    private weak var lifecycle: AppLifecycleCoordinator?
    private var cancellables = Set<AnyCancellable>()
    private var didStartSystemRouting = false

    init(logger: Logger = ConsoleLogger()) {
        self.logger = logger
        logger.info("RouteCoordinator 已初始化：系统事件统一进入路由协调", module: .routing)
    }

    func bind(lifecycle: AppLifecycleCoordinator) {
        self.lifecycle = lifecycle
    }

    func startSystemEventRouting() {
        guard didStartSystemRouting == false else { return }
        didStartSystemRouting = true

        NotificationCenter.default.publisher(for: SupportAuthSessionInvalidation.notificationName)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                let message = notification.userInfo?["message"] as? String ?? ""
                let source = notification.userInfo?["source"] as? String ?? "-"
                Task { @MainActor in
                    self?.logger.warning(
                        "路由流程：收到服务端鉴权失效事件 source=\(source) message=\(message)",
                        module: .auth
                    )
                    await self?.lifecycle?.handleServerAuthInvalidationIfNeeded(invalidationMessage: message)
                }
            }
            .store(in: &cancellables)

        logger.info("RouteCoordinator 已接管系统事件：鉴权失效", module: .routing)
    }

    func resetRouteGraphForAccountRuntime(reason: String) {
        logger.info("路由流程：账号运行时变更 reason=\(reason)（Support 无 typed route graph）", module: .routing)
    }
}

typealias AppRouteCoordinator = RouteCoordinator
