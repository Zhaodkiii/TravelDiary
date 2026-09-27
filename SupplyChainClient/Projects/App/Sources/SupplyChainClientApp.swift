import SwiftUI

@main
struct SupplyChainClientApp: App {
    @State private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            ContentView(dependencies: container.contentDependencies)
                .environment(\.managedObjectContext, container.coreDataStack.viewContext)
        }
    }
}
