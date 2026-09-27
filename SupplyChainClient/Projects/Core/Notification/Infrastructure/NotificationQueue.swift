import Foundation

actor NotificationQueue {
    enum EnqueueResult: Sendable {
        case enqueued(NotificationMessage)
        case dropped(NotificationMessage, NotificationDropReason)
    }

    private let dedupeWindow: TimeInterval
    private let maxQueueDepth: Int
    private let metricsStore: NotificationMetricsStore
    private let inboxStore: NotificationInboxStore
    private let logger: Logger

    private var queue: [NotificationMessage] = []
    private var lastSeenByKey: [String: Date] = [:]
    /// Tap actions stored side-channel so NotificationMessage stays Codable.
    private var pendingTapActions: [UUID: @MainActor @Sendable () -> Void] = [:]

    init(
        dedupeWindow: TimeInterval = 2.0,
        maxQueueDepth: Int = 128,
        metricsStore: NotificationMetricsStore,
        inboxStore: NotificationInboxStore,
        logger: Logger = ConsoleLogger()
    ) {
        self.dedupeWindow = dedupeWindow
        self.maxQueueDepth = maxQueueDepth
        self.metricsStore = metricsStore
        self.inboxStore = inboxStore
        self.logger = logger
    }

    func enqueue(_ intent: NotificationIntent) async -> EnqueueResult {
        let message = NotificationMessage.from(intent: intent)
        let onTap = intent.onTap
        let now = Date()

        if let previous = lastSeenByKey[message.dedupeKey], now.timeIntervalSince(previous) < dedupeWindow {
            await metricsStore.recordDropped(.duplicate)
            await inboxStore.markDropped(message, reason: .duplicate, at: now)
            logger.debug("Notification dropped as duplicate: \(message.dedupeKey)", module: .notification)
            return .dropped(message, .duplicate)
        }

        if queue.count >= maxQueueDepth {
            await metricsStore.recordDropped(.queueOverflow)
            await inboxStore.markDropped(message, reason: .queueOverflow, at: now)
            logger.warning("Notification dropped due to queue overflow: \(message.id)", module: .notification)
            return .dropped(message, .queueOverflow)
        }

        queue.append(message)
        if let onTap {
            pendingTapActions[message.id] = onTap
        }
        lastSeenByKey[message.dedupeKey] = now
        await metricsStore.recordEnqueued()
        await inboxStore.appendQueued(message)
        return .enqueued(message)
    }

    func dequeue() -> NotificationMessage? {
        guard queue.isEmpty == false else { return nil }
        return queue.removeFirst()
    }

    func consumeTapAction(for id: UUID) -> (@MainActor @Sendable () -> Void)? {
        pendingTapActions.removeValue(forKey: id)
    }
}
