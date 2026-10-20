import SwiftUI

@main
struct TravelDiaryApp: App {
    @UIApplicationDelegateAdaptor(RemotePushAppDelegateBridge.self) private var pushDelegate
    @State private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            ContentView(dependencies: container.contentDependencies)
                .environment(\.managedObjectContext, container.coreDataStack.viewContext)
                .onOpenURL { WeChatPrintPayment.shared.handle($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { WeChatPrintPayment.shared.handle($0) }
        }
    }
}
