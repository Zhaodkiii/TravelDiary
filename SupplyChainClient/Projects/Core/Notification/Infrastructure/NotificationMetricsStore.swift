import Foundation

actor NotificationMetricsStore {
    private var enqueuedCount = 0
    private var displayedCount = 0
    private var droppedDuplicateCount = 0
    private var droppedOverflowCount = 0
    private var accumulatedDisplayLatencyMs: Double = 0

    func recordEnqueued() {
        enqueuedCount += 1
    }

    func recordDropped(_ reason: NotificationDropReason) {
        switch reason {
        case .duplicate:
            droppedDuplicateCount += 1
        case .queueOverflow:
            droppedOverflowCount += 1
        }
    }

    func recordDisplayed(latencyMs: Double) {
        displayedCount += 1
        accumulatedDisplayLatencyMs += max(0, latencyMs)
    }

    func snapshot() -> NotificationMetricsSnapshot {
        let averageLatency: Double
        if displayedCount == 0 {
            averageLatency = 0
        } else {
            averageLatency = accumulatedDisplayLatencyMs / Double(displayedCount)
        }

        return NotificationMetricsSnapshot(
            enqueuedCount: enqueuedCount,
            displayedCount: displayedCount,
            droppedDuplicateCount: droppedDuplicateCount,
            droppedOverflowCount: droppedOverflowCount,
            averageDisplayLatencyMs: averageLatency
        )
    }
}
