import Foundation

nonisolated struct StoragePolicy: Codable, Equatable, Sendable {
    var automaticallyManageSafeFiles = false
    var previewLimit: Int64 = 1_000_000_000
}

/// Reserve estimated peak bytes across concurrent exports. This never replaces write-error handling.
nonisolated final class StorageSpaceBudget: @unchecked Sendable {
    static let shared = StorageSpaceBudget()
    private let lock = NSLock()
    private var reservations: [UUID: Int64] = [:]
    func reserve(at directory: URL, estimatedPeak: Int64) throws -> Reservation {
        lock.lock(); defer { lock.unlock() }
        let available = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        let peak = max(0, estimatedPeak)
        let budget = peak + max(200_000_000, peak / 5)
        if let available, available - reservations.values.reduce(0, +) < budget { throw StorageFailure.insufficientSpace }
        let id = UUID(); reservations[id] = budget
        return Reservation(id: id, budget: self)
    }
    private func release(_ id: UUID) { lock.lock(); defer { lock.unlock() }; reservations.removeValue(forKey: id) }
    final class Reservation: @unchecked Sendable {
        private let id: UUID
        private let budget: StorageSpaceBudget
        fileprivate init(id: UUID, budget: StorageSpaceBudget) { self.id = id; self.budget = budget }
        deinit { budget.release(id) }
    }
}
