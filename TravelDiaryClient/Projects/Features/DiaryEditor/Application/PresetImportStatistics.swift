import Foundation
import Combine
import Network

nonisolated struct PresetImportStatisticsContext: Sendable {
    let templateID: String
    let version: Int
    let wholeBook: Bool
}

nonisolated struct PresetImportEvent: Codable, Sendable, Equatable {
    nonisolated struct Page: Codable, Sendable, Equatable {
        let source_page_id: String
        let target_page_id: UUID
    }
    let operation_id: UUID
    let template_id: String
    let version: Int
    let mode: String
    let target_book_id: UUID
    let completed_at: String
    var pages: [Page]? // nil omits the key for book events.
}

nonisolated struct PresetImportOutboxRecord: Codable, Sendable {
    let event: PresetImportEvent
    var attempts = 0
    var nextAttempt = Date.distantPast
    var acknowledged = false
    var rejectedReason: String? = nil
}

/// Runs only for the authenticated account. Durable records live outside books and downloads.
@MainActor
final class PresetImportStatisticsReporter {
    static let shared = PresetImportStatisticsReporter()
    private var engine: SupportNetworkEngine?
    private var owner: String?
    private var subscription: AnyCancellable?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private let monitor = NWPathMonitor()

    func configure(engine: SupportNetworkEngine, sessions: AppSessionStore) {
        self.engine = engine
        subscription = sessions.$state.sink { [weak self] state in
            let id: String?
            if case let .signedIn(session) = state { id = String(session.accountID) } else { id = nil }
            self?.activate(id)
        }
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied { Task { @MainActor in self?.wake() } }
        }
        monitor.start(queue: DispatchQueue(label: "TravelDiary.PresetStatistics.Network"))
    }

    private func activate(_ id: String?) {
        generation = UUID(); task?.cancel(); task = nil; owner = id
        wake()
    }

    func wake() {
        guard task == nil, let owner, let engine else { return }
        let generation = generation
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == generation { self.task = nil } }
            let store = DiaryDocumentStore(ownerID: owner)
            while !Task.isCancelled && self.generation == generation {
                do {
                    let records = try await store.pendingImportStatistics()
                    for var record in records where record.rejectedReason == nil && record.nextAttempt <= Date() {
                        guard !Task.isCancelled, self.owner == owner, self.generation == generation else { return }
                        do {
                            let response = try await engine.sendRaw(SupportNetworkRequest(method: .post,
                                path: "/api/v1/diary-presets/import-events/",
                                headers: ["X-Preset-Import-Owner": owner],
                                body: .raw(try JSONEncoder().encode(record.event), contentType: "application/json"),
                                strategy: NetworkStrategy(requiresAuth: true)))
                            struct Ack: Decodable { let operation_id: UUID; let duplicate: Bool }
                            let ack = try JSONDecoder().decode(Ack.self, from: response.data)
                            guard ack.operation_id == record.event.operation_id else { throw SupportNetworkError.invalidResponse }
                            guard !Task.isCancelled, self.generation == generation else { return }
                            try await store.acknowledgeImportStatistics(record.event.operation_id)
                        } catch {
                            guard !Task.isCancelled, self.generation == generation else { return }
                            record.attempts += 1
                            record.nextAttempt = Date().addingTimeInterval(min(3600, pow(2, Double(min(record.attempts, 10))) * 5))
                            if case let SupportNetworkError.http(code, _, _) = error, [400, 404, 409, 422].contains(code) {
                                record.rejectedReason = "HTTP \(code)"
                            }
                            try await store.saveImportStatisticsAttempt(record)
                        }
                    }
                } catch {
                    SupportLogger.log(level: .error, module: .diaryEditor, message: "preset_statistics_queue_failed \(error.localizedDescription)")
                }
                // Periodic wake also catches imports committed while this loop is sleeping.
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }
}
