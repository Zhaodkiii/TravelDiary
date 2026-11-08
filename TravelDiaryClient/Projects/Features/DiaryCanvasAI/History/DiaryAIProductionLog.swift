import Foundation
import ZIPFoundation

/// Diagnostic evidence lives under the account's storage tree, independent of recoverable work documents.
@MainActor final class DiaryAIProductionLog {
    private(set) var directory: URL
    private var sequence = 0
    private let writer = DiaryAILogWriter()
    private var knownAttachments: Set<String> = []
    private var secrets: Set<String> = []
    func registerSecret(_ value: String) { if !value.isEmpty { secrets.insert(value) } }
    private(set) var failure: String?
    init(owner: String, page: UUID, root: URL = StoragePaths.system.support) {
        let paths = StoragePaths(support: root, caches: StoragePaths.system.caches, temporary: StoragePaths.system.temporary)
        directory = paths.account(owner).appendingPathComponent("AIProductionLogs/\(page)/\(UUID().uuidString)")
        record("session", ["page": page.uuidString, "schema": 2, "notice": "包含完整制作输入和输出；认证信息已脱敏。"])
    }
    func resume(_ name: String) {
        guard UUID(uuidString: name) != nil else { return }
        let previous = directory.deletingLastPathComponent().appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: previous.path) else { return }
        writer.flushSynchronously()
        directory = previous
        knownAttachments = []
        sequence = (try? FileManager.default.contentsOfDirectory(at: previous, includingPropertiesForKeys: nil).compactMap { Int($0.lastPathComponent.prefix(6)) }.max()) ?? 0
        if let bytes = try? Data(contentsOf: previous.appendingPathComponent("events.jsonl")),
           let last = bytes.split(separator: 10).last,
           let row = try? JSONSerialization.jsonObject(with: Data(last)) as? [String: Any] {
            sequence = max(sequence, row["sequence"] as? Int ?? 0)
        }
        record("resume", ["message": "继续上次制作日志"])
    }
    @discardableResult func attachment(_ data: Data, ext: String) -> String {
        let name = "attachments/\(DiaryEditorAIBridge.hash(data)).\(ext)"
        if knownAttachments.insert(name).inserted {
            writer.save(data, to: directory.appendingPathComponent(name))
        }
        return name
    }
    func record(_ kind: String, _ value: Any) {
        do { data(kind, try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])) }
        catch { failure = error.localizedDescription }
    }
    func data(_ kind: String, _ data: Data) {
        sequence += 1
        // Keep sequence/time assignment synchronous; parse, redact and encode on the ordered writer.
        writer.record(kind, data: data, sequence: sequence, date: Date(), directory: directory, keys: Array(secrets))
    }
    func flush() async throws { try await writer.flush() }
    func export() async throws -> URL {
        try await writer.flush()
        if let failure { throw DiaryAIError.invalid("日志记录不完整：\(failure)") }
        let source = directory.deletingLastPathComponent().appendingPathComponent("snapshot-" + UUID().uuidString)
        try await writer.snapshot(from: directory, to: source)
        let target = directory.deletingLastPathComponent().appendingPathComponent("AI制作日志-\(UUID().uuidString).zip")
        return try await Task.detached {
            defer { try? FileManager.default.removeItem(at: source) }
            // Compact legacy one-file-per-event archives in the export snapshot only.
            let legacy = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" && Int($0.lastPathComponent.prefix(6)) != nil }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            if !legacy.isEmpty {
                let stream = source.appendingPathComponent("events.jsonl")
                let newer = (try? Data(contentsOf: stream)) ?? Data()
                var compact = Data()
                for file in legacy {
                    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
                    compact.append(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
                    compact.append(10)
                }
                compact.append(newer)
                try compact.write(to: stream, options: .atomic)
                for file in legacy { try FileManager.default.removeItem(at: file) }
            }
            try FileManager.default.zipItem(at: source, to: target)
            return target
        }.value
    }
}

/// Ordered I/O and bounded-time batching; no file writes on the UI thread.
private nonisolated final class DiaryAILogWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "diary.ai.production-log", qos: .utility)
    private var pending: [URL: Data] = [:]
    private var scheduled = false
    private var failure: Error?
    private let formatter = ISO8601DateFormatter()

    func record(_ kind: String, data: Data, sequence: Int, date: Date, directory: URL, keys: [String]) {
        queue.async {
            autoreleasepool {
                do {
                    let value = try (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed))
                        ?? ["file": try self.attachment(data, ext: "txt", directory: directory)]
                    let body: [String: Any] = ["sequence": sequence, "time": self.formatter.string(from: date),
                        "kind": kind, "payload": try self.sanitize(value, directory: directory, keys: keys)]
                    var bytes = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .fragmentsAllowed])
                    bytes.append(10)
                    self.appendOnQueue(bytes, to: directory.appendingPathComponent("events.jsonl"))
                } catch { self.failure = error }
            }
        }
    }
    private func sanitize(_ value: Any, directory: URL, keys: [String]) throws -> Any {
        if let dict = value as? [String: Any] {
            return try dict.filter { !["authorization", "proxy-authorization", "api_key", "apikey", "secret", "access_token", "refresh_token", "credentials"].contains($0.key.lowercased()) }
                .mapValues { try sanitize($0, directory: directory, keys: keys) }
        }
        if let array = value as? [Any] { return try array.map { try sanitize($0, directory: directory, keys: keys) } }
        if let text = value as? String {
            if text.hasPrefix("data:image/"), let comma = text.firstIndex(of: ","), let data = Data(base64Encoded: String(text[text.index(after: comma)...])) {
                return ["attachment": try attachment(data, ext: text.hasPrefix("data:image/png") ? "png" : "jpg", directory: directory), "bytes": data.count] as [String: Any]
            }
            var clean = text
            for key in keys { clean = clean.replacingOccurrences(of: key, with: "[REDACTED]") }
            return clean.replacingOccurrences(of: #"(?i)Bearer\s+[^\s\"<>]+"#, with: "Bearer [REDACTED]", options: .regularExpression)
        }
        return value
    }
    private func attachment(_ data: Data, ext: String, directory: URL) throws -> String {
        let name = "attachments/\(DiaryEditorAIBridge.hash(data)).\(ext)"
        let url = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
        return name
    }
    private func appendOnQueue(_ data: Data, to url: URL) {
        pending[url, default: Data()].append(data)
        if pending[url]!.count >= 64 * 1024 { drain() }
        if !scheduled {
            scheduled = true
            queue.asyncAfter(deadline: .now() + 0.2) { self.scheduled = false; self.drain() }
        }
    }
    func save(_ data: Data, to url: URL) {
        queue.async {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
            } catch { self.failure = error }
        }
    }
    private func drain() {
        for (url, data) in pending {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd(); try handle.write(contentsOf: data)
            } catch { failure = error }
        }
        pending.removeAll(keepingCapacity: true)
    }
    func flushSynchronously() { queue.sync { drain() } }
    func flush() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { self.drain(); if let error = self.failure { continuation.resume(throwing: error) } else { continuation.resume() } }
        }
    }
    func snapshot(from source: URL, to target: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do { self.drain(); if let error = self.failure { throw error }; try FileManager.default.copyItem(at: source, to: target); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}
