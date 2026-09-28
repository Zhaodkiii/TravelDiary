import Foundation

@MainActor
final class NotificationDeliveryCoordinator {
    private let queue: NotificationQueue
    private let store: NotificationStore
    private let inboxStore: NotificationInboxStore
    private let metricsStore: NotificationMetricsStore

    private var isConsuming = false

    init(
        queue: NotificationQueue,
        store: NotificationStore,
        inboxStore: NotificationInboxStore,
        metricsStore: NotificationMetricsStore
    ) {
        self.queue = queue
        self.store = store
        self.inboxStore = inboxStore
        self.metricsStore = metricsStore
    }

    func startIfNeeded() {
        guard isConsuming == false else { return }
        isConsuming = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.consumeLoop()
        }
    }

    func refreshDashboard() async {
        let inbox = await inboxStore.allItems()
        let metrics = await metricsStore.snapshot()
        store.replaceInboxItems(inbox)
        store.replaceMetrics(metrics)
    }

    private func consumeLoop() async {
        defer { isConsuming = false }

        while let message = await queue.dequeue() {
            let presentedAt = Date()
            await inboxStore.markPresented(id: message.id, at: presentedAt)
            let latencyMs = presentedAt.timeIntervalSince(message.enqueuedAt) * 1000
            await metricsStore.recordDisplayed(latencyMs: latencyMs)
            await refreshDashboard()

            // Register tap action (if any) before presenting so the view can pick it up.
            if let tapAction = await queue.consumeTapAction(for: message.id) {
                store.registerTapAction(for: message.id, action: tapAction)
            }
            store.present(message)

            switch message.presentation {
            case .toast:
                await autoDismissToast(message)
            case .banner:
                await autoDismissBanner(message)
            case .alert:
                await store.waitForAlertDismissal(id: message.id)
            }

            await inboxStore.markDismissed(id: message.id, at: Date())
            await refreshDashboard()
        }
    }

    private func autoDismissToast(_ message: NotificationMessage) async {
        let duration = message.autoDismissAfter ?? 2.0
        try? await Task.sleep(nanoseconds: UInt64(max(0.4, duration) * 1_000_000_000))
        store.dismissToast(id: message.id)
    }

    private func autoDismissBanner(_ message: NotificationMessage) async {
        let duration = message.autoDismissAfter ?? 2.8
        try? await Task.sleep(nanoseconds: UInt64(max(0.6, duration) * 1_000_000_000))
        store.dismissBanner(id: message.id)
    }
}
