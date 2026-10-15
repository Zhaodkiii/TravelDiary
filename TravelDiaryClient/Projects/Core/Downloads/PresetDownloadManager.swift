import Foundation
import Combine
import CryptoKit

nonisolated struct RemotePresetBook: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let series: String
    let version: Int
    let page_count: Int
    let cover_url: String
}
nonisolated struct RemotePresetCatalog: Decodable, Sendable {
    struct Series: Decodable, Sendable { let slug: String; let title: String }
    let series: [Series]
    let books: [RemotePresetBook]
}
nonisolated struct RemotePresetPage: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let thumbnail_url: String
    let preview_url: String
}
nonisolated struct PresetDownloadJob: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let owner: String
    let planID: String
    let title: String
    let manifestData: Data
    let wholeBook: Bool
    let targetID: UUID?
    let afterPageID: UUID?
    let expectedRevision: UUID?
    var downloadOnly: Bool? = nil
    var status = "queued"
    var bytes: Int64 = 0
    var total: Int64 = 0
    var error: String?
    var resultID: UUID?
}

/// Application-wide jobs survive navigation. Completed 8 MiB ranges survive process termination.
@MainActor
final class PresetDownloadManager: ObservableObject {
    static let shared = PresetDownloadManager()
    @Published private(set) var jobs: [PresetDownloadJob] = []
    private var engine: SupportNetworkEngine?
    private var running: [UUID: Task<Void, Never>] = [:]
    private var lockedHashes = Set<String>()
    private var owner: String?
    private let root: URL
    private let chunkSize = 8 * 1024 * 1024

    private init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PresetDownloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var url = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        if let data = try? Data(contentsOf: root.appendingPathComponent("jobs.json")),
           let saved = try? JSONDecoder().decode([PresetDownloadJob].self, from: data) {
            jobs = saved.map { value in var value = value; if !["completed", "ready", "cancelled"].contains(value.status) { value.status = "paused" }; return value }
        }
    }
    func configure(engine: SupportNetworkEngine) { self.engine = engine }
    func activate(owner: String) {
        if self.owner != owner {
            for job in jobs where running[job.id] != nil { pause(job.id) }
            self.owner = owner
        }
    }
    func request(_ path: String, body: [String: [String]]? = nil) async throws -> Data {
        guard let engine else { throw URLError(.userAuthenticationRequired) }
        let response = try await engine.sendRaw(SupportNetworkRequest(method: body == nil ? .get : .post,
            path: "/api/v1/diary-presets/" + path,
            body: body.map { .json(AnyEncodable($0)) } ?? .none,
            strategy: NetworkStrategy(requiresAuth: true)))
        return response.data
    }
    func catalog() async throws -> RemotePresetCatalog {
        try JSONDecoder().decode(RemotePresetCatalog.self, from: await request("catalog/"))
    }
    func pages(_ book: RemotePresetBook) async throws -> [RemotePresetPage] {
        struct Result: Decodable { let pages: [RemotePresetPage] }
        return try JSONDecoder().decode(Result.self, from: await request("templates/\(book.id)/\(book.version)/")).pages
    }
    @discardableResult
    func enqueue(book: RemotePresetBook, pageIDs: [String]?, owner: String, target: DiaryBook?, after: UUID?, downloadOnly: Bool = false) async throws -> UUID {
        activate(owner: owner)
        if downloadOnly, let existing = jobs.last(where: { job in
            guard job.owner == owner, job.downloadOnly == true, job.status != "cancelled",
                  let manifest = try? JSONDecoder().decode(PresetManifest.self, from: job.manifestData),
                  manifest.templateBookID == book.id, manifest.packageVersion == book.version else { return false }
            return pageIDs.map { Set($0).isSubset(of: Set(manifest.pages.map(\.id))) } ?? job.wholeBook
        }) { return existing.id }
        let data = try await request("templates/\(book.id)/\(book.version)/", body: pageIDs.map { ["page_ids": $0] } ?? [:])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plan = json["id"] as? String, let manifest = json["manifest"] else { throw DiaryEditorError.invalidDocument }
        let bytes = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        let package = try JSONDecoder().decode(PresetManifest.self, from: bytes)
        let jobID = UUID()
        jobs.append(PresetDownloadJob(id: jobID, owner: owner, planID: plan, title: book.title,
            manifestData: bytes, wholeBook: pageIDs == nil, targetID: pageIDs == nil ? nil : target?.id,
            afterPageID: after, expectedRevision: target?.catalogRevision,
            downloadOnly: downloadOnly, total: Int64(package.files.reduce(0) { $0 + $1.byteCount })))
        persist(); schedule()
        return jobID
    }
    func cachedPackage(bookID: String, version: Int, pageIDs: [String]) -> DiaryPresetPackage? {
        for job in jobs.reversed() where ["ready", "completed"].contains(job.status) {
            guard let manifest = try? JSONDecoder().decode(PresetManifest.self, from: job.manifestData),
                  manifest.templateBookID == bookID, manifest.packageVersion == version,
                  Set(pageIDs).isSubset(of: Set(manifest.pages.map(\.id))) else { continue }
            let directory = root.appendingPathComponent(job.id.uuidString)
            guard manifest.files.allSatisfy({ FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.path).path) }) else { continue }
            return DiaryPresetPackage(root: directory, manifest: manifest)
        }
        return nil
    }
    /// Count unique, locally available pages for this exact template version.
    func downloadedPageIDs(bookID: String, version: Int) -> Set<String> {
        var result = Set<String>()
        for job in jobs where ["ready", "completed"].contains(job.status) {
            guard let manifest = try? JSONDecoder().decode(PresetManifest.self, from: job.manifestData),
                  manifest.templateBookID == bookID, manifest.packageVersion == version else { continue }
            let directory = root.appendingPathComponent(job.id.uuidString)
            guard manifest.files.allSatisfy({ record in
                let url = directory.appendingPathComponent(record.path)
                return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) == record.byteCount
            }) else { continue }
            result.formUnion(manifest.pages.map(\.id))
        }
        return result
    }
    func hasDownloadedPage(bookID: String, version: Int, pageID: String) -> Bool {
        downloadedPageIDs(bookID: bookID, version: version).contains(pageID)
    }
    func preparedPackage(_ id: UUID) -> DiaryPresetPackage? {
        guard let job = jobs.first(where: { $0.id == id }), ["ready", "completed"].contains(job.status),
              let manifest = try? JSONDecoder().decode(PresetManifest.self, from: job.manifestData) else { return nil }
        return cachedPackage(bookID: manifest.templateBookID, version: manifest.packageVersion, pageIDs: manifest.pages.map(\.id))
    }
    func pause(_ id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }), !["completed", "ready", "importing"].contains(jobs[i].status) else { return }
        jobs[i].status = "paused"; running[id]?.cancel(); persist()
    }
    func resume(_ id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].owner == owner,
              ["paused", "failed"].contains(jobs[i].status) else { return }
        jobs[i].status = "queued"; jobs[i].error = nil; persist(); schedule()
    }
    func cancel(_ id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }), !["importing", "completed"].contains(jobs[i].status) else { return }
        jobs[i].status = "cancelled"; running[id]?.cancel(); persist()
    }
    /// 仅删除停止运行的下载资源；手帐使用独立副本，不受影响。
    func removeDownloads(_ ids: Set<UUID>, ownerID: String) throws {
        let removable = jobs.filter {
            ids.contains($0.id) && $0.owner == ownerID && running[$0.id] == nil
                && ["ready", "completed", "cancelled", "paused", "failed"].contains($0.status)
        }
        let removedIDs = Set(removable.map(\.id))
        guard removedIDs == ids else { throw DiaryEditorError.staleObject }
        let remaining = jobs.filter { !removedIDs.contains($0.id) }
        // Decode before deleting anything; retain blobs referenced by any account or task.
        let retained = try Set(remaining.flatMap {
            try JSONDecoder().decode(PresetManifest.self, from: $0.manifestData).files.map(\.sha256)
        })
        let candidates = try Set(removable.flatMap {
            try JSONDecoder().decode(PresetManifest.self, from: $0.manifestData).files.map(\.sha256)
        })
        let fm = FileManager.default
        for job in removable {
            let directory = root.appendingPathComponent(job.id.uuidString)
            if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
        }
        for hash in candidates.subtracting(retained) where !lockedHashes.contains(hash) {
            guard hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else { continue }
            for name in [hash, hash + ".parts"] {
                let url = root.appendingPathComponent("blobs").appendingPathComponent(name)
                if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            }
        }
        jobs = remaining
        persist()
    }

    private func persist() {
        do { try JSONEncoder().encode(jobs).write(to: root.appendingPathComponent("jobs.json"), options: .atomic) }
        catch { /* Existing jobs remain in memory; surface persistence failure. */
            for i in jobs.indices where jobs[i].status == "queued" { jobs[i].error = "下载状态保存失败：\(error.localizedDescription)" }
        }
    }
    private func schedule() {
        for job in jobs where running.count < 3 && job.owner == owner && job.status == "queued" && running[job.id] == nil {
            running[job.id] = Task { await execute(job.id); running[job.id] = nil; schedule() }
        }
    }
    private func update(_ id: UUID, _ action: (inout PresetDownloadJob) -> Void) {
        if let i = jobs.firstIndex(where: { $0.id == id }) { action(&jobs[i]); persist() }
    }
    private func execute(_ id: UUID) async {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        do {
            let manifest = try JSONDecoder().decode(PresetManifest.self, from: job.manifestData)
            let directory = root.appendingPathComponent(id.uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let package = DiaryPresetPackage(root: directory, manifest: manifest)
            update(id) { $0.status = "downloading"; $0.bytes = 0 }
            var complete: Int64 = 0
            for file in manifest.files {
                try Task.checkCancellation()
                let destination = try package.url(file.path)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                let cached = try await download(file, plan: job.planID) { bytes in
                    self.update(id) { $0.bytes = complete + Int64(bytes) }
                }
                if !FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.copyItem(at: cached, to: destination)
                }
                complete += Int64(file.byteCount)
                update(id) { $0.bytes = complete }
            }
            try Task.checkCancellation()
            update(id) { $0.status = "verifying" }
            try await Task.detached { try package.validate() }.value
            try Task.checkCancellation()
            if job.downloadOnly == true {
                update(id) { $0.status = "ready" }
                return
            }
            guard owner == job.owner else { throw CancellationError() }
            update(id) { $0.status = "importing" }
            let result = try await DiaryDocumentStore(ownerID: job.owner, bookID: job.targetID).importPreset(package,
                pageIDs: manifest.pages.map(\.id), title: job.title, operationID: id,
                afterPageID: job.targetID == nil ? nil : job.afterPageID, expectedRevision: job.expectedRevision)
            update(id) { $0.status = "completed"; $0.resultID = result.id }
        } catch {
            update(id) { value in
                if !["paused", "cancelled"].contains(value.status) { value.status = "failed"; value.error = error.localizedDescription }
            }
        }
    }
    private func download(_ file: PresetManifest.FileRecord, plan: String, progress: (Int) -> Void) async throws -> URL {
        guard file.sha256.count == 64, file.sha256.allSatisfy({ $0.isHexDigit }), file.byteCount >= 0, file.byteCount <= 100_000_000 else { throw DiaryEditorError.invalidDocument }
        while lockedHashes.contains(file.sha256) { try await Task.sleep(for: .milliseconds(150)) }
        try Task.checkCancellation()
        lockedHashes.insert(file.sha256)
        defer { lockedHashes.remove(file.sha256) }
        let cache = root.appendingPathComponent("blobs")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let final = cache.appendingPathComponent(file.sha256)
        if FileManager.default.fileExists(atPath: final.path) { progress(file.byteCount); return final }
        let parts = cache.appendingPathComponent(file.sha256 + ".parts")
        try FileManager.default.createDirectory(at: parts, withIntermediateDirectories: true)
        var offset = 0
        while offset < file.byteCount {
            try Task.checkCancellation()
            let length = min(chunkSize, file.byteCount - offset)
            let part = parts.appendingPathComponent(String(offset))
            let existing = (try? part.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
            if existing != length {
                var lastError: Error = URLError(.cannotLoadFromNetwork)
                var success = false
                for attempt in 0..<3 {
                    do {
                        try Task.checkCancellation()
                        let urls = try JSONDecoder().decode([String: String].self, from: await request("plans/\(plan)/urls/", body: ["paths": [file.path]]))
                        guard let raw = urls[file.path], let url = URL(string: raw), url.scheme == "https",
                              url.host?.hasSuffix(".aliyuncs.com") == true else { throw URLError(.badURL) }
                        var request = URLRequest(url: url); request.timeoutInterval = 120
                        request.setValue("bytes=\(offset)-\(offset + length - 1)", forHTTPHeaderField: "Range")
                        let (tmp, response) = try await URLSession.shared.download(for: request)
                        defer { try? FileManager.default.removeItem(at: tmp) }
                        guard let http = response as? HTTPURLResponse,
                              http.statusCode == 206,
                              http.value(forHTTPHeaderField: "Content-Range") == "bytes \(offset)-\(offset + length - 1)/\(file.byteCount)",
                              (try tmp.resourceValues(forKeys: [.fileSizeKey])).fileSize == length else { throw URLError(.badServerResponse) }
                        try Task.checkCancellation()
                        if FileManager.default.fileExists(atPath: part.path) { try FileManager.default.removeItem(at: part) }
                        try FileManager.default.moveItem(at: tmp, to: part)
                        success = true; break
                    } catch {
                        try Task.checkCancellation(); lastError = error
                        if attempt < 2 { try await Task.sleep(for: .seconds(attempt + 1)) }
                    }
                }
                if !success { throw lastError }
            }
            offset += length; progress(offset)
        }
        let size = file.byteCount, hash = file.sha256, chunk = chunkSize
        try await Task.detached {
            let assembling = parts.appendingPathComponent("assembled")
            FileManager.default.createFile(atPath: assembling.path, contents: nil)
            let out = try FileHandle(forWritingTo: assembling)
            defer { try? out.close() }
            var hasher = SHA256(), offset = 0
            while offset < size {
                let data = try Data(contentsOf: parts.appendingPathComponent(String(offset)), options: .mappedIfSafe)
                try out.write(contentsOf: data); hasher.update(data: data); offset += min(chunk, size - offset)
            }
            let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard actual == hash else {
                try? FileManager.default.removeItem(at: parts)
                throw DiaryEditorError.invalidDocument
            }
            try out.synchronize()
            try FileManager.default.moveItem(at: assembling, to: final)
            try? FileManager.default.removeItem(at: parts)
        }.value
        return final
    }
}
