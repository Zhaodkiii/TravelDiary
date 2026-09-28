import SwiftUI

struct ContentView: View {
    let dependencies: AppContentDependencies

    var body: some View {
        NotificationHostView(store: dependencies.notificationStore) {
            AppCoordinatorView(dependencies: dependencies.coordinator)
        }
        .task {
            dependencies.routeCoordinator.startSystemEventRouting()
            await dependencies.notificationDeliveryCoordinator.refreshDashboard()
        }
        .onOpenURL { url in
            dependencies.notificationClient.info(url.absoluteString, source: "deeplink")
        }
    }
}

#Preview {
    ContentView(dependencies: AppContainer.live(environment: .debug).contentDependencies)
}
