import Foundation

@MainActor
protocol NotificationClient: AnyObject {
    func publish(_ intent: NotificationIntent)
    func success(_ message: String, title: String?, source: String)
    func error(_ message: String, title: String?, source: String)
    func warning(_ message: String, title: String?, source: String)
    func info(_ message: String, title: String?, source: String)
}

@MainActor
extension NotificationClient {
    func success(_ message: String, title: String? = nil, source: String = "app") {
        success(message, title: title, source: source)
    }

    func error(_ message: String, title: String? = nil, source: String = "app") {
        error(message, title: title, source: source)
    }

    func warning(_ message: String, title: String? = nil, source: String = "app") {
        warning(message, title: title, source: source)
    }

    func info(_ message: String, title: String? = nil, source: String = "app") {
        info(message, title: title, source: source)
    }
}

@MainActor
final class DefaultNotificationClient: NotificationClient {
    private let publishUseCase: PublishNotificationUseCase

    init(publishUseCase: PublishNotificationUseCase) {
        self.publishUseCase = publishUseCase
    }

    func publish(_ intent: NotificationIntent) {
        Task {
            await publishUseCase.execute(intent)
        }
    }

    func success(_ message: String, title: String? = nil, source: String = "app") {
        publish(NotificationIntent(title: title, message: message, level: .success, presentation: .toast, source: source))
    }

    func error(_ message: String, title: String? = nil, source: String = "app") {
        publish(NotificationIntent(title: title, message: message, level: .error, presentation: .banner, source: source))
    }

    func warning(_ message: String, title: String? = nil, source: String = "app") {
        publish(NotificationIntent(title: title, message: message, level: .warning, presentation: .banner, source: source))
    }

    func info(_ message: String, title: String? = nil, source: String = "app") {
        publish(NotificationIntent(title: title, message: message, level: .info, presentation: .toast, source: source))
    }
}
