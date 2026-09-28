import SwiftUI

@main
struct TravelDiaryApp: App {
    @State private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            ContentView(dependencies: container.contentDependencies)
                .environment(\.managedObjectContext, container.coreDataStack.viewContext)
        }
    }
}
