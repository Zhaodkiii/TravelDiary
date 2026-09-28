import Foundation

nonisolated enum NotificationLevel: String, Codable, Sendable {
    case success
    case error
    case warning
    case info
}

nonisolated enum NotificationPresentation: String, Codable, Sendable {
    case toast
    case banner
    case alert
}

nonisolated enum NotificationDropReason: String, Codable, Sendable {
    case duplicate
    case queueOverflow
}

nonisolated struct NotificationIntent: Sendable {
    var title: String?
    var message: String
    var level: NotificationLevel
    var presentation: NotificationPresentation
    var dedupeKey: String?
    var source: String
    var autoDismissAfter: TimeInterval?
    /// Optional tap handler. When set, the banner becomes tappable and invokes this closure on tap.
    var onTap: (@MainActor @Sendable () -> Void)?

    init(
        title: String? = nil,
        message: String,
        level: NotificationLevel,
        presentation: NotificationPresentation = .toast,
        dedupeKey: String? = nil,
        source: String = "app",
        autoDismissAfter: TimeInterval? = nil,
        onTap: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.level = level
        self.presentation = presentation
        self.dedupeKey = dedupeKey
        self.source = source
        self.autoDismissAfter = autoDismissAfter
        self.onTap = onTap
    }
}

nonisolated struct NotificationMessage: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let title: String?
    let message: String
    let level: NotificationLevel
    let presentation: NotificationPresentation
    let source: String
    let dedupeKey: String
    let enqueuedAt: Date
    let autoDismissAfter: TimeInterval?

    init(
        id: UUID = UUID(),
        title: String?,
        message: String,
        level: NotificationLevel,
        presentation: NotificationPresentation,
        source: String,
        dedupeKey: String,
        enqueuedAt: Date = Date(),
        autoDismissAfter: TimeInterval?
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.level = level
        self.presentation = presentation
        self.source = source
        self.dedupeKey = dedupeKey
        self.enqueuedAt = enqueuedAt
        self.autoDismissAfter = autoDismissAfter
    }

    nonisolated static func from(intent: NotificationIntent) -> NotificationMessage {
        let normalizedKey = intent.dedupeKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackKey = "\(intent.level.rawValue)|\(intent.presentation.rawValue)|\(intent.message.lowercased())"
        return NotificationMessage(
            title: intent.title,
            message: intent.message,
            level: intent.level,
            presentation: intent.presentation,
            source: intent.source,
            dedupeKey: (normalizedKey?.isEmpty == false ? normalizedKey! : fallbackKey),
            autoDismissAfter: intent.autoDismissAfter
        )
    }
}

nonisolated struct NotificationInboxItem: Identifiable, Codable, Sendable {
    let id: UUID
    let title: String?
    let message: String
    let level: NotificationLevel
    let presentation: NotificationPresentation
    let source: String
    let createdAt: Date
    var presentedAt: Date?
    var dismissedAt: Date?
    var droppedReason: NotificationDropReason?
}

nonisolated struct NotificationMetricsSnapshot: Codable, Sendable, Equatable {
    var enqueuedCount: Int
    var displayedCount: Int
    var droppedDuplicateCount: Int
    var droppedOverflowCount: Int
    var averageDisplayLatencyMs: Double

    static let zero = NotificationMetricsSnapshot(
        enqueuedCount: 0,
        displayedCount: 0,
        droppedDuplicateCount: 0,
        droppedOverflowCount: 0,
        averageDisplayLatencyMs: 0
    )
}
