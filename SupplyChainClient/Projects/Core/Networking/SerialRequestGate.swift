import Foundation

actor SerialRequestGate {
    enum Priority: Int, Sendable {
        case retry = 0
        case veryHigh = 1
        case high = 2
        case normal = 3
        case low = 4
    }

    private struct QueuedJob {
        let priority: Priority
        let sequence: UInt64
        let job: @Sendable () async -> Void
    }

    private struct QueueState {
        var isRunning: Bool = false
        var queue: [QueuedJob] = []
    }

    private var states: [String: QueueState] = [:]
    private var nextSequence: UInt64 = 0

    func enqueue<T>(
        serialKey: String,
        priority: Priority = .normal,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            // Each job resumes its own continuation; job closure stays in actor isolation.
            let job: @Sendable () async -> Void = {
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                do {
                    let result = try await operation()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            var state = states[serialKey] ?? QueueState()
            let queued = QueuedJob(priority: priority, sequence: nextSequence, job: job)
            nextSequence += 1
            state.queue.append(queued)
            states[serialKey] = state

            if state.isRunning == false {
                states[serialKey]?.isRunning = true
                Task { [serialKey] in
                    await self.runQueue(serialKey: serialKey)
                }
            }
        }
    }

    private func runQueue(serialKey: String) async {
        while true {
            guard var state = states[serialKey] else { return }
            guard !state.queue.isEmpty else {
                state.isRunning = false
                states[serialKey] = state
                return
            }

            let nextIndex = state.queue.enumerated().min { lhs, rhs in
                if lhs.element.priority.rawValue != rhs.element.priority.rawValue {
                    return lhs.element.priority.rawValue < rhs.element.priority.rawValue
                }
                return lhs.element.sequence < rhs.element.sequence
            }!.offset

            let job = state.queue.remove(at: nextIndex)
            states[serialKey] = state

            await job.job()
            // next iteration picks next head
        }
    }
}
