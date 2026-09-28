import Foundation

actor NotificationInboxStore {
    private let fileURL: URL
    private let maxItems: Int
    private var items: [NotificationInboxItem]

    init(fileURL: URL? = nil, maxItems: Int = 500) {
        let defaultURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TravelDiary", isDirectory: true)
            .appendingPathComponent("notification_inbox.json")
        self.fileURL = fileURL ?? defaultURL ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notification_inbox.json")
        self.maxItems = maxItems
        self.items = NotificationInboxStore.loadItems(from: self.fileURL)
    }

    func appendQueued(_ message: NotificationMessage) {
        let item = NotificationInboxItem(
            id: message.id,
            title: message.title,
            message: message.message,
            level: message.level,
            presentation: message.presentation,
            source: message.source,
            createdAt: message.enqueuedAt,
            presentedAt: nil,
            dismissedAt: nil,
            droppedReason: nil
        )
        items.insert(item, at: 0)
        trimIfNeeded()
        persist()
    }

    func markDropped(_ message: NotificationMessage, reason: NotificationDropReason, at date: Date = Date()) {
        if let index = items.firstIndex(where: { $0.id == message.id }) {
            items[index].droppedReason = reason
            items[index].dismissedAt = date
        } else {
            var item = NotificationInboxItem(
                id: message.id,
                title: message.title,
                message: message.message,
                level: message.level,
                presentation: message.presentation,
                source: message.source,
                createdAt: message.enqueuedAt,
                presentedAt: nil,
                dismissedAt: date,
                droppedReason: reason
            )
            item.dismissedAt = date
            items.insert(item, at: 0)
            trimIfNeeded()
        }
        persist()
    }

    func markPresented(id: UUID, at date: Date = Date()) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].presentedAt = date
        persist()
    }

    func markDismissed(id: UUID, at date: Date = Date()) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].dismissedAt = date
        persist()
    }

    func allItems() -> [NotificationInboxItem] {
        items
    }

    private func trimIfNeeded() {
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder.default.encode(items)
            try AtomicFileWriter.write(data, to: fileURL)
        } catch {
            SupportLogger.log(
                level: .warning,
                module: .notification,
                message: "Inbox persistence failed: \(error.localizedDescription)"
            )
        }
    }

    private static func loadItems(from url: URL) -> [NotificationInboxItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder.default.decode([NotificationInboxItem].self, from: data)) ?? []
    }
}
