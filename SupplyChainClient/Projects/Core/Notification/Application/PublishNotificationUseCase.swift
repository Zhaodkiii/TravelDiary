import Foundation

struct PublishNotificationUseCase {
    private let queue: NotificationQueue
    private let deliveryCoordinator: NotificationDeliveryCoordinator
    private let logger: Logger

    init(
        queue: NotificationQueue,
        deliveryCoordinator: NotificationDeliveryCoordinator,
        logger: Logger = ConsoleLogger()
    ) {
        self.queue = queue
        self.deliveryCoordinator = deliveryCoordinator
        self.logger = logger
    }

    func execute(_ intent: NotificationIntent) async {
        let result = await queue.enqueue(intent)
        switch result {
        case .enqueued(let message):
            logger.debug("Notification enqueued: \(message.id)", module: .notification)
            await MainActor.run {
                deliveryCoordinator.startIfNeeded()
            }
        case .dropped(let message, let reason):
            logger.info("Notification dropped: \(reason.rawValue) id=\(message.id)", module: .notification)
            await deliveryCoordinator.refreshDashboard()
        }
    }
}
