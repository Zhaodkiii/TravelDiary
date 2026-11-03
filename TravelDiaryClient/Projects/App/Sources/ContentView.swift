import SwiftUI

struct ContentView: View {
    let dependencies: AppContentDependencies

    @State private var showsOnboarding = DiaryOnboardingPolicy.initialPresentation

    @State private var handoff = DiaryOnboardingHandoff()

    var body: some View {
        ZStack {
            // Keep this subtree mounted: restore, guest login, account preparation
            // and the first shelf read all run while the demonstration is visible.
            appContent
                .allowsHitTesting(!showsOnboarding)
                .accessibilityHidden(showsOnboarding)
            if showsOnboarding {
                DiaryOnboardingView(isPreparingHome: handoff.finishRequested) {
                    handoff.requestFinish()
                }
                .zIndex(1)
            }
        }
        .onChange(of: handoff.canDismiss) { _, canDismiss in
            guard showsOnboarding, canDismiss else { return }
            DiaryOnboardingPolicy().finish()
            showsOnboarding = false
        }
    }

    private var appContent: some View {
        NotificationHostView(store: dependencies.notificationStore) {
            AppCoordinatorView(dependencies: dependencies.coordinator,
                               onEntryReady: { handoff.updateReadiness($0) })
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
