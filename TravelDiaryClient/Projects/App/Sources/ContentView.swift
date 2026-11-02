import SwiftUI

struct ContentView: View {
    let dependencies: AppContentDependencies

    @State private var showsOnboarding = DiaryOnboardingPolicy.initialPresentation

    var body: some View {
        Group {
            if showsOnboarding {
                DiaryOnboardingView {
                    DiaryOnboardingPolicy().finish()
                    showsOnboarding = false
                }
            } else {
                appContent
            }
        }
    }

    private var appContent: some View {
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
