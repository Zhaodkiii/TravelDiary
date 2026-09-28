import Foundation

/// 领域装配器：每个 Assembly 只暴露本领域 facade，避免 AppContainer 向 UI 泄露完整系统地图。
protocol FeatureAssembly {
    associatedtype Facade
    var scope: DependencyScope { get }
    func makeFacade() -> Facade
}

struct AuthFeatureDependencies {
    let sessionStore: AppSessionStore
    let makeLoginViewModel: @MainActor () -> LoginViewModel
}

struct AIConfigFacade {
    let configCenter: AIConfigCenter
    let runtimeStore: AIRuntimeStore
    let makeSettingsViewModel: @MainActor (_ ownerAccountID: Int64) -> AISettingsViewModel
}

struct NotificationFeatureDependencies {
    let notificationStore: NotificationStore
    let notificationClient: any NotificationClient
    let routeCoordinator: RouteCoordinator
}

@MainActor
struct AuthAssemblyFacade: FeatureAssembly {
    let scope: DependencyScope = .accountScoped
    let dependencies: AuthFeatureDependencies

    func makeFacade() -> AuthFeatureDependencies {
        dependencies
    }
}

@MainActor
struct AIAssemblyFacade: FeatureAssembly {
    let scope: DependencyScope = .accountScoped
    let facade: AIConfigFacade

    func makeFacade() -> AIConfigFacade {
        facade
    }
}

@MainActor
struct NotificationAssemblyFacade: FeatureAssembly {
    let scope: DependencyScope = .appSingleton
    let dependencies: NotificationFeatureDependencies

    func makeFacade() -> NotificationFeatureDependencies {
        dependencies
    }
}
