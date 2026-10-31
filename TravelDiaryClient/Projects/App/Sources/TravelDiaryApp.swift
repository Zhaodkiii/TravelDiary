import SwiftUI

@main
struct TravelDiaryApp: App {
    @UIApplicationDelegateAdaptor(RemotePushAppDelegateBridge.self) private var pushDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var paymentProbe: PrintProbeLink?
    @State private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            ContentView(dependencies: container.contentDependencies)
                .environment(\.managedObjectContext, container.coreDataStack.viewContext)
                #if DEBUG
                .onOpenURL { url in
                    if let link = PrintProbeLink(url) { paymentProbe = link; return }
                    if !AlipayPrintPayment.shared.handle(url) { WeChatPrintPayment.shared.handle(url) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .printPaymentReturned)) { note in
                    let outcome = (note.userInfo?["outcome"] as? String).flatMap(PrintPaymentReturn.init(rawValue:)) ?? .returned
                    PrintOrderService.shared.paymentReturned(outcome)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        PrintOrderService.shared.resumePayments()
                        Task { await RegionRepository.shared.checkForUpdates() }
                    }
                }
                .sheet(item: $paymentProbe) { PrintProbeScreen(link: $0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { WeChatPrintPayment.shared.handle($0) }
                #endif
        }
    }
}
