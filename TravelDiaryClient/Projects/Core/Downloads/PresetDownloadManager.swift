import Foundation
import Combine
import CryptoKit

nonisolated struct RemotePresetBook: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let series: String
    let version: Int
    let page_count: Int
    let cover_url: String
    var privateOwner: String? = nil
    var customizationID: String? = nil
    var content_page_count: Int? = nil
    var style_tags: [String]? = nil
    var usage_tags: [String]? = nil
}
nonisolated struct RemotePresetCatalog: Codable, Sendable {
    struct Series: Codable, Sendable { let slug: String; let title: String }
    let series: [Series]
    let books: [RemotePresetBook]
}
nonisolated struct RemotePresetPage: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let thumbnail_url: String
    let preview_url: String
}
/// Browsing never needs the import manifest or editable page documents.
nonisolated struct RemotePresetBrowse: Codable, Sendable {
    let title: String
    let page_size: PresetSize
    let cover_page_id: String
    let shell_page_id: String?
    let expires_at: TimeInterval
    let pages: [RemotePresetPage]
    var isFresh: Bool { expires_at > Date().timeIntervalSince1970 + 5 }
}

/// A ready local package or the metadata of one existing/new download job.
nonisolated struct PresetImportPreparation: Sendable {
    let package: DiaryPresetPackage
    let downloadID: UUID?
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
    var privateOwner: String? = nil
    var customizationID: String? = nil
    var downloadOnly: Bool? = nil
    var pinned = false
    var status = "queued"
    var bytes: Int64 = 0
    var total: Int64 = 0
    var error: String?
    var resultID: UUID?
}

/// A sheet subscribes to one job; unrelated downloads do not invalidate its view.
@MainActor
final class PresetDownloadObservation: ObservableObject {
    @Published private(set) var job: PresetDownloadJob?
    private var subscription: AnyCancellable?
    func bind(_ id: UUID, manager: PresetDownloadManager) {
        subscription = manager.$jobs.map { $0.first { $0.id == id } }
            .removeDuplicates()
            .sink { [weak self] in self?.job = $0 }
    }
}

/// Catalog views observe availability only, never byte-level progress.
@MainActor
final class PresetAvailabilityIndex: ObservableObject {
    @Published var pages: [String: Set<String>] = [:]
    func downloadedPageIDs(bookID: String, version: Int) -> Set<String> {
        pages["\(bookID):\(version)"] ?? []
    }
    func hasDownloadedPage(bookID: String, version: Int, pageID: String) -> Bool {
        downloadedPageIDs(bookID: bookID, version: version).contains(pageID)
    }
}

/// Application-wide jobs survive navigation. Completed 8 MiB ranges survive process termination.
@MainActor
final class PresetDownloadManager: ObservableObject {
    static let shared = PresetDownloadManager()
    @Published private(set) var jobs: [PresetDownloadJob] = []
    let availability = PresetAvailabilityIndex()
    private var packages: [UUID: DiaryPresetPackage] = [:]
    private var saveTask: Task<Void, Never>?
    private let saveQueue = DispatchQueue(label: "preset.download.persistence", qos: .utility)
    private var lastProgress: [UUID: Date] = [:]
    private var signedURLs: [String: (Date, [String: String])] = [:]
    private var restoreTask: Task<Void, Never>?
    private var engine: SupportNetworkEngine?
    private var running: [UUID: Task<Void, Never>] = [:]
    private var lockedHashes = Set<String>()
    private var catalogCache: (owner: String, date: Date, value: RemotePresetCatalog)?
    private var catalogRequest: Task<RemotePresetCatalog, Error>?
    private var catalogGeneration = UUID()
    private var browseRequestIDs: [String: UUID] = [:]
    private var browseCache: [String: RemotePresetBrowse] = [:]
    private var browseRequests: [String: Task<RemotePresetBrowse, Error>] = [:]
    private var owner: String?
    private let root: URL
    private var materialCacheClearing = false
    private let chunkSize = 8 * 1024 * 1024

    init(directory: URL? = nil) {
        root = directory ?? StoragePaths.system.downloads
        let directory = root
        restoreTask = Task {
            let restored = await Task.detached(priority: .utility) {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var url = directory
                var values = URLResourceValues(); values.isExcludedFromBackup = true
                try? url.setResourceValues(values)
                let data = try? Data(contentsOf: directory.appendingPathComponent("jobs.json"))
                var saved = data.flatMap { try? JSONDecoder().decode([PresetDownloadJob].self, from: $0) } ?? []
                var packages: [UUID: DiaryPresetPackage] = [:]
                for i in saved.indices {
                    if ["ready", "completed"].contains(saved[i].status),
                       let manifest = try? JSONDecoder().decode(PresetManifest.self, from: saved[i].manifestData) {
                        let root = directory.appendingPathComponent(saved[i].id.uuidString)
                        if manifest.files.allSatisfy({ (try? root.appendingPathComponent($0.path).resourceValues(forKeys: [.fileSizeKey]).fileSize) == $0.byteCount }) {
                            packages[saved[i].id] = DiaryPresetPackage(root: root, manifest: manifest)
                        } else { saved[i].status = "paused" }
                    } else if saved[i].status != "cancelled" { saved[i].status = "paused" }
                }
                return (saved, packages)
            }.value
            jobs = restored.0; packages = restored.1; rebuildAvailability()
        }
    }
    private func rebuildAvailability() {
        var pages: [String: Set<String>] = [:]
        for (id, package) in packages where canUsePackage(id) {
            let manifest = package.manifest
            pages["\(manifest.templateBookID):\(manifest.packageVersion)", default: []].formUnion(manifest.pages.map(\.id))
        }
        if availability.pages != pages { availability.pages = pages }
    }

    func waitUntilRestored() async { await restoreTask?.value }
    func configure(engine: SupportNetworkEngine) {
        catalogGeneration = UUID(); catalogCache = nil; catalogRequest?.cancel(); catalogRequest = nil
        for task in browseRequests.values { task.cancel() }; browseRequests.removeAll(); browseRequestIDs.removeAll()
        browseCache.removeAll()
        self.engine = engine
        MaterialCatalogRepository.shared.engine = engine
    }
    func deactivate() {
        catalogGeneration = UUID(); catalogCache = nil; catalogRequest?.cancel(); catalogRequest = nil
        for task in browseRequests.values { task.cancel() }; browseRequests.removeAll(); browseRequestIDs.removeAll()
        for job in jobs where running[job.id] != nil { pause(job.id) }
        MaterialCatalogRepository.shared.activate("")
        PreviewImagePipeline.shared.activate(owner: nil)
        PresetPreviewRepository.shared.reset()
        owner = nil; signedURLs.removeAll(); browseCache.removeAll(); rebuildAvailability()
    }
    func activate(owner: String) {
        PreviewImagePipeline.shared.activate(owner: owner)
        MaterialCatalogRepository.shared.activate(owner)
        if self.owner != owner {
            catalogGeneration = UUID(); catalogCache = nil; catalogRequest?.cancel(); catalogRequest = nil
            PresetPreviewRepository.shared.reset()
            for task in browseRequests.values { task.cancel() }; browseRequests.removeAll(); browseRequestIDs.removeAll()
            for job in jobs where running[job.id] != nil { pause(job.id) }
            self.owner = owner
            signedURLs.removeAll(); browseCache.removeAll(); rebuildAvailability()
        }
    }
    func request(_ path: String, body: [String: [String]]? = nil, allowETag: Bool = false, queryItems: [URLQueryItem]? = nil) async throws -> Data {
        guard let engine else { throw URLError(.userAuthenticationRequired) }
        let response = try await engine.sendRaw(SupportNetworkRequest(method: body == nil ? .get : .post,
            path: "/api/v1/diary-presets/" + path,
            queryItems: queryItems,
            body: body.map { .json(AnyEncodable($0)) } ?? .none,
            strategy: NetworkStrategy(requiresAuth: true, allowETag: allowETag, etagTTL: allowETag ? 300 : nil)))
        return response.data
    }
    func importStatisticsContext(for package: DiaryPresetPackage, wholeBook: Bool) -> PresetImportStatisticsContext? {
        guard UUID(uuidString: package.id) != nil, jobs.contains(where: { job in
            guard job.owner == owner, let manifest = try? JSONDecoder().decode(PresetManifest.self, from: job.manifestData) else { return false }
            return manifest.templateBookID == package.id && manifest.packageVersion == package.manifest.packageVersion
        }) else { return nil }
        return PresetImportStatisticsContext(templateID: package.id, version: package.manifest.packageVersion, wholeBook: wholeBook)
    }
    func invalidateCatalog() { catalogCache = nil }
    func catalog() async throws -> RemotePresetCatalog {
        let context = owner ?? "signed-out"
        if let catalogCache, catalogCache.owner == context, Date().timeIntervalSince(catalogCache.date) < 300 { return catalogCache.value }
        if let catalogRequest { return try await catalogRequest.value }
        let generation = catalogGeneration
        let task = Task {
            try JSONDecoder().decode(RemotePresetCatalog.self, from: await request("catalog/", queryItems: [URLQueryItem(name: "schema_max", value: "2")]))
        }
        catalogRequest = task
        defer { if generation == catalogGeneration { catalogRequest = nil } }
        let value = try await task.value
        guard generation == catalogGeneration, (owner ?? "signed-out") == context else { throw CancellationError() }
        catalogCache = (context, Date(), value)
        return value
    }
    func browse(_ book: RemotePresetBook, ownerID: String, forceRefresh: Bool = false) async throws -> RemotePresetBrowse {
        let key = "\(ownerID):\(book.id):\(book.version)"
        if !forceRefresh, let value = browseCache[key], value.isFresh { return value }
        if let pending = browseRequests[key] { return try await pending.value }
        let task = Task {
            try JSONDecoder().decode(RemotePresetBrowse.self,
                from: await request("templates/\(book.id)/\(book.version)/browse/", allowETag: true))
        }
        let requestID = UUID()
        browseRequests[key] = task; browseRequestIDs[key] = requestID
        defer { if browseRequestIDs[key] == requestID { browseRequests[key] = nil; browseRequestIDs[key] = nil } }
        let value = try await task.value
        guard browseRequestIDs[key] == requestID else { throw CancellationError() }
        browseCache[key] = value
        PresetPreviewRepository.shared.remember(value, book: book, ownerID: ownerID)
        return value
    }
    func pages(_ book: RemotePresetBook) async throws -> [RemotePresetPage] {
        try await browse(book, ownerID: owner ?? "").pages
    }
    @discardableResult
    func enqueue(book: RemotePresetBook, pageIDs: [String]?, owner: String, target: DiaryBook?, after: UUID?, downloadOnly: Bool = false, minimumLayerSchema: Int? = nil, unitID: String? = nil) async throws -> UUID {
        await restoreTask?.value
        activate(owner: owner)
        if downloadOnly, let existing = jobs.last(where: { job in
            guard job.owner == owner, job.downloadOnly == true, job.status != "cancelled",
                  let manifest = try? JSONDecoder().decode(PresetManifest.self, from: job.manifestData),
                  manifest.templateBookID == book.id, manifest.packageVersion == book.version else { return false }
            return pageIDs.map { Set($0).isSubset(of: Set(manifest.pages.map(\.id))) } ?? job.wholeBook
        }) {
            if let minimumLayerSchema,
               let manifest = try? JSONDecoder().decode(PresetManifest.self, from: existing.manifestData),
               manifest.layerSchemaVersion < minimumLayerSchema {
                throw NSError(domain: "PresetCategoryPreview", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "此云端模板尚未提供组件分类，请发布带分类信息的新版本后使用。"])
            }
            return existing.id
        }
        let data: Data
        if let unitID {
            guard let engine else { throw URLError(.userAuthenticationRequired) }
            let payload = PresetSpreadPlanRequest(selection: .init(kind: "spread", unit_id: unitID))
            data = try await engine.sendRaw(SupportNetworkRequest(method: .post,
                path: "/api/v1/diary-presets/templates/\(book.id)/\(book.version)/",
                body: .json(AnyEncodable(payload)), strategy: NetworkStrategy(requiresAuth: true))).data
        } else {
            data = try await request("templates/\(book.id)/\(book.version)/", body: pageIDs.map { ["page_ids": $0] } ?? [:])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plan = json["id"] as? String, let manifest = json["manifest"] else { throw DiaryEditorError.invalidDocument }
        try Task.checkCancellation()
        guard self.owner == owner else { throw CancellationError() }
        let bytes = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        let package = try JSONDecoder().decode(PresetManifest.self, from: bytes)
        if let minimumLayerSchema, package.layerSchemaVersion < minimumLayerSchema {
            throw NSError(domain: "PresetCategoryPreview", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "此云端模板尚未提供组件分类，请发布带分类信息的新版本后使用。"])
        }
        let jobID = UUID()
        jobs.append(PresetDownloadJob(id: jobID, owner: owner, planID: plan, title: book.title,
            manifestData: bytes, wholeBook: pageIDs == nil, targetID: pageIDs == nil ? nil : target?.id,
            afterPageID: after, expectedRevision: target?.catalogRevision,
            privateOwner: book.privateOwner, customizationID: book.customizationID, downloadOnly: downloadOnly, total: Int64(package.files.reduce(0) { $0 + $1.byteCount })))
        persist(); schedule()
        return jobID
    }
    func prepareImport(book: RemotePresetBook, pageIDs: [String], wholeBook: Bool,
                       ownerID: String, unitID: String? = nil) async throws -> PresetImportPreparation {
        await restoreTask?.value
        try Task.checkCancellation()
        activate(owner: ownerID)
        if let cached = cachedPackage(bookID: book.id, version: book.version, pageIDs: pageIDs) {
            return PresetImportPreparation(package: cached, downloadID: nil)
        }
        let id = try await enqueue(book: book, pageIDs: wholeBook ? nil : pageIDs,
                                   owner: ownerID, target: nil, after: nil, downloadOnly: true, unitID: unitID)
        if let ready = preparedPackage(id) {
            return PresetImportPreparation(package: ready, downloadID: nil)
        }
        guard let job = jobs.first(where: { $0.id == id }) else { throw DiaryEditorError.missingResource }
        let manifest = try JSONDecoder().decode(PresetManifest.self, from: job.manifestData)
        let package = DiaryPresetPackage(root: root.appendingPathComponent(id.uuidString), manifest: manifest)
        return PresetImportPreparation(package: package, downloadID: id)
    }
    /// 浏览过滤只下载指定页面，不创建用户手帐；首次仅请求轻量清单检查分类能力。
    func prepareCategoryPreview(book: RemotePresetBook, pageIDs: [String], ownerID: String) async throws -> PresetImportPreparation {
        await restoreTask?.value
        try Task.checkCancellation()
        activate(owner: ownerID)
        if let cached = cachedPackage(bookID: book.id, version: book.version, pageIDs: pageIDs), cached.manifest.layerSchemaVersion >= 2 {
            return PresetImportPreparation(package: cached, downloadID: nil)
        }
        let id = try await enqueue(book: book, pageIDs: pageIDs, owner: ownerID, target: nil, after: nil,
                                   downloadOnly: true, minimumLayerSchema: 2)
        if let ready = preparedPackage(id) { return PresetImportPreparation(package: ready, downloadID: nil) }
        guard let job = jobs.first(where: { $0.id == id }) else { throw DiaryEditorError.missingResource }
        let manifest = try JSONDecoder().decode(PresetManifest.self, from: job.manifestData)
        return PresetImportPreparation(package: DiaryPresetPackage(root: root.appendingPathComponent(id.uuidString), manifest: manifest), downloadID: id)
    }

    private func canUsePackage(_ id: UUID) -> Bool {
        guard let job = jobs.first(where: { $0.id == id }) else { return false }
        return job.privateOwner == nil || (job.privateOwner == owner && job.owner == owner)
    }
    func cachedPackage(bookID: String, version: Int, pageIDs: [String]) -> DiaryPresetPackage? {
        packages.filter { id, _ in canUsePackage(id) }.map(\.value).first {
            $0.manifest.templateBookID == bookID && $0.manifest.packageVersion == version
                && Set(pageIDs).isSubset(of: Set($0.manifest.pages.map(\.id)))
        }
    }
    /// Partial downloads may already contain a requested preview; completeness is irrelevant here.
    func previewPackages(book: RemotePresetBook, ownerID: String) -> [DiaryPresetPackage] {
        guard owner == ownerID else { return [] }
        return packages.filter { canUsePackage($0.key) }.map(\.value).filter {
            $0.manifest.templateBookID == book.id && $0.manifest.packageVersion == book.version
        }
    }
    func completeCachedPackage(for book: RemotePresetBook) -> DiaryPresetPackage? {
        packages.filter { id, _ in canUsePackage(id) }.map(\.value).first {
            $0.id == book.id && $0.manifest.packageVersion == book.version
                && book.page_count > 0 && $0.manifest.pages.count == book.page_count
        }
    }
    func preparedPackage(_ id: UUID) -> DiaryPresetPackage? {
        guard canUsePackage(id) else { return nil }
        return packages[id]
    }
    func isRunning(_ id: UUID) -> Bool { running[id] != nil }
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
    func setPinned(_ value: Bool, id: UUID, ownerID: String) throws {
        guard owner == ownerID, let i = jobs.firstIndex(where: { $0.id == id && $0.owner == ownerID }) else { throw StorageFailure.accountChanged }
        jobs[i].pinned = value; persist()
    }
    /// 仅删除停止运行的下载资源；手帐使用独立副本，不受影响。
    func removeDownloads(_ ids: Set<UUID>, ownerID: String) throws {
        guard owner == ownerID else { throw StorageFailure.accountChanged }
        for id in ids where StorageActivity.shared.isInUse(root.appendingPathComponent(id.uuidString)) { throw StorageFailure.inUse }
        let removable = jobs.filter {
            ids.contains($0.id) && $0.owner == ownerID && !$0.pinned && running[$0.id] == nil
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
        for scope in Set(removable.compactMap(\.privateOwner)) {
            let removedHashes = Set(removable.filter { $0.privateOwner == scope }.flatMap { job in
                (try? JSONDecoder().decode(PresetManifest.self, from: job.manifestData).files.map(\.sha256)) ?? []
            })
            let liveHashes = Set(remaining.filter { $0.privateOwner == scope }.flatMap { job in
                (try? JSONDecoder().decode(PresetManifest.self, from: job.manifestData).files.map(\.sha256)) ?? []
            })
            let name = "private-" + SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
            for hash in removedHashes.subtracting(liveHashes) where hash.count == 64 && hash.allSatisfy({ $0.isHexDigit }) && !lockedHashes.contains(hash) {
                for suffix in ["", ".parts"] { try? fm.removeItem(at: root.appendingPathComponent(name).appendingPathComponent(hash + suffix)) }
            }
        }
        jobs = remaining
        for id in removedIDs { packages.removeValue(forKey: id) }
        rebuildAvailability()
        persist()
    }

    private func persist(immediate: Bool = true) {
        if !immediate, saveTask != nil { return }
        saveTask?.cancel()
        saveTask = Task {
            if !immediate {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            let snapshot = jobs, url = root.appendingPathComponent("jobs.json")
            saveTask = nil
            // A serial queue prevents older snapshots overwriting newer snapshots.
            saveQueue.async {
                do { try JSONEncoder().encode(snapshot).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen]) }
                catch { NSLog("Preset download state persistence failed: %@", error.localizedDescription) }
            }
        }
    }
    private func progress(_ id: UUID, bytes: Int64) {
        guard Date().timeIntervalSince(lastProgress[id] ?? .distantPast) >= 0.25,
              let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].status == "downloading" else { return }
        lastProgress[id] = Date()
        jobs[i].bytes = min(jobs[i].total, max(jobs[i].bytes, bytes))
        persist(immediate: false)
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
        let lease = StorageActivity.shared.acquire(root.appendingPathComponent(id.uuidString))
        defer { withExtendedLifetime(lease) {} }
        do {
            let manifest = try await Task.detached(priority: .utility) { try JSONDecoder().decode(PresetManifest.self, from: job.manifestData) }.value
            let directory = root.appendingPathComponent(id.uuidString)
            try await Task.detached(priority: .utility) { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path) }.value
            let package = DiaryPresetPackage(root: directory, manifest: manifest)
            update(id) { $0.status = "downloading"; $0.bytes = 0 }
            var complete: Int64 = 0
            for (fileIndex, file) in manifest.files.enumerated() {
                try Task.checkCancellation()
                guard owner == job.owner else { throw CancellationError() }
                let destination = try await Task.detached(priority: .utility) { try package.url(file.path) }.value
                let completedBytes = complete
                let cached = try await download(file, plan: job.planID, paths: Array(manifest.files.dropFirst(fileIndex).prefix(50).map(\.path))) { bytes in
                    self.progress(id, bytes: completedBytes + Int64(bytes))
                }
                try await Task.detached(priority: .utility) {
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if !FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.copyItem(at: cached, to: destination)
                    }
                }.value
                complete += Int64(file.byteCount)
                progress(id, bytes: complete)
            }
            try Task.checkCancellation()
            update(id) { $0.status = "verifying"; $0.bytes = complete }
            try await Task.detached(priority: .utility) { try package.validate() }.value
            try Task.checkCancellation()
            guard owner == job.owner else { throw CancellationError() }
            packages[id] = package; rebuildAvailability()
            if job.downloadOnly == true {
                update(id) { $0.status = "ready" }
                return
            }
            guard owner == job.owner else { throw CancellationError() }
            update(id) { $0.status = "importing" }
            let result = try await DiaryDocumentStore(ownerID: job.owner, bookID: job.targetID).importPreset(package,
                pageIDs: manifest.pages.map(\.id), title: job.title, operationID: id,
                statistics: PresetImportStatisticsContext(templateID: manifest.templateBookID, version: manifest.packageVersion, wholeBook: job.wholeBook),
                afterPageID: job.targetID == nil ? nil : job.afterPageID, expectedRevision: job.expectedRevision)
            update(id) { $0.status = "completed"; $0.resultID = result.id }
        } catch {
            if Task.isCancelled { return } // A quick resume must not be overwritten by the cancelled run.
            update(id) { value in
                if !["paused", "cancelled"].contains(value.status) { value.status = "failed"; value.error = error.localizedDescription }
            }
        }
    }
    func materialCacheFiles() -> [URL] {
        let registry = root.appendingPathComponent("material-hashes.json")
        let hashes = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: registry))) ?? []
        let protected = Set(jobs.flatMap { job in
            (try? JSONDecoder().decode(PresetManifest.self, from: job.manifestData).files.map(\.sha256)) ?? []
        }).union(lockedHashes)
        return hashes.filter { $0.count == 64 && $0.allSatisfy(\.isHexDigit) && !protected.contains($0) }
            .flatMap { hash in [root.appendingPathComponent("blobs/" + hash), root.appendingPathComponent("blobs/" + hash + ".parts")] }
    }
    func clearMaterialCache() async throws {
        materialCacheClearing = true; defer { materialCacheClearing = false }
        let files = materialCacheFiles()
        try await Task.detached(priority: .utility) {
            for file in files where FileManager.default.fileExists(atPath:file.path) { try FileManager.default.removeItem(at:file) }
        }.value
    }

    /// Material and preset imports share hash locks, cached bytes, range resume and URL refresh.
    func materialData(_ item: CloudMaterial, progress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> Data {
        guard !materialCacheClearing, item.availability != "unavailable" else { throw URLError(.resourceUnavailable) }
        let registry = root.appendingPathComponent("material-hashes.json")
        var hashes = Set((try? JSONDecoder().decode([String].self, from: Data(contentsOf: registry))) ?? [])
        hashes.insert(item.sha256)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? JSONEncoder().encode(Array(hashes)).write(to: registry, options: .atomic)
        let materialKey = "material-\(item.revision)"
        if item.library_id != nil {
            do {
                let plan = try await MaterialCatalogRepository.shared.downloadPlan(item)
                guard plan.sha256 == item.sha256, plan.byte_size == item.byte_size else { throw DiaryEditorError.invalidDocument }
                signedURLs[materialKey] = (Date(), [item.sha256: plan.url])
            } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost].contains(error.code) {
                // Only complete, hash-verified cached bytes can be used offline.
                let path = root.appendingPathComponent("blobs").appendingPathComponent(item.sha256)
                if let data = try? Data(contentsOf: path), data.count == item.byte_size,
                   SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == item.sha256 { progress(1); return data }
                throw error
            }
        }
        if let data = await MaterialThumbnailCache.shared.cachedOriginal(item) {
            try Task.checkCancellation()
            progress(1)
            return data
        }
        let key = "material-\(item.revision)"
        let file = PresetManifest.FileRecord(path: item.sha256, byteCount: item.byte_size, sha256: item.sha256)
        let url = try await download(file, plan: key, paths: [], materialRevision: item.revision, material: item) { count in
            progress(Double(count) / Double(max(1, item.byte_size)))
        }
        return try await Task.detached(priority: .utility) { try Data(contentsOf: url) }.value
    }

    private func download(_ file: PresetManifest.FileRecord, plan: String, paths: [String], materialRevision: Int? = nil, material: CloudMaterial? = nil, progress: @escaping @MainActor @Sendable (Int) -> Void) async throws -> URL {
        guard file.sha256.count == 64, file.sha256.allSatisfy({ $0.isHexDigit }), file.byteCount >= 0, file.byteCount <= 100_000_000 else { throw DiaryEditorError.invalidDocument }
        while lockedHashes.contains(file.sha256) { try await Task.sleep(for: .milliseconds(150)) }
        try Task.checkCancellation()
        lockedHashes.insert(file.sha256)
        defer { lockedHashes.remove(file.sha256) }
        let cacheOwner = jobs.first(where: { $0.planID == plan })?.privateOwner
        let cacheName = cacheOwner.map { "private-" + SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() } ?? "blobs"
        let cache = root.appendingPathComponent(cacheName)
        let final = cache.appendingPathComponent(file.sha256)
        let parts = cache.appendingPathComponent(file.sha256 + ".parts")
        let hit = try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(at: parts, withIntermediateDirectories: true)
            guard let data = try? Data(contentsOf: final, options: .mappedIfSafe) else { return false }
            if data.count == file.byteCount,
               SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == file.sha256 { return true }
            try FileManager.default.removeItem(at: final)
            return false
        }.value
        if let cacheOwner, cacheOwner != owner { throw CancellationError() }
        if hit { progress(file.byteCount); return final }
        var offset = 0
        while offset < file.byteCount {
            try Task.checkCancellation()
            let length = min(chunkSize, file.byteCount - offset)
            let part = parts.appendingPathComponent(String(offset))
            let existing = await Task.detached(priority: .utility) { (try? part.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1 }.value
            if existing != length {
                var lastError: Error = URLError(.cannotLoadFromNetwork)
                var success = false
                for attempt in 0..<3 {
                    do {
                        try Task.checkCancellation()
                        if signedURLs[plan].map({ Date().timeIntervalSince($0.0) < 600 && $0.1[file.path] != nil }) != true {
                            let urls: [String: String]
                            if let materialRevision {
                                let result: MaterialDownload
                                if let material, material.library_id != nil { result = try await MaterialCatalogRepository.shared.downloadPlan(material) }
                                else { result = try await MaterialCatalogRepository.shared.request("revisions/\(materialRevision)/download/", method: .post) }
                                guard result.sha256 == file.sha256, result.byte_size == file.byteCount else { throw DiaryEditorError.invalidDocument }
                                urls = [file.path: result.url]
                            } else {
                                urls = try JSONDecoder().decode([String: String].self, from: await request("plans/\(plan)/urls/", body: ["paths": paths]))
                            }
                            signedURLs[plan] = (Date(), urls)
                        }
                        let urls = signedURLs[plan]?.1 ?? [:]
                        guard let raw = urls[file.path], let url = URL(string: raw), url.scheme == "https",
                              url.host?.hasSuffix(".aliyuncs.com") == true else { throw URLError(.badURL) }
                        var request = URLRequest(url: url); request.timeoutInterval = 120
                        request.setValue("bytes=\(offset)-\(offset + length - 1)", forHTTPHeaderField: "Range")
                        let partOffset = offset
                        let transfer = PresetTransferProgress { count in
                            Task { @MainActor in progress(partOffset + min(length, Int(count))) }
                        }
                        let (tmp, response) = try await URLSession.shared.download(for: request, delegate: transfer)
                        guard let http = response as? HTTPURLResponse, http.statusCode == 206,
                              http.value(forHTTPHeaderField: "Content-Range") == "bytes \(offset)-\(offset + length - 1)/\(file.byteCount)" else {
                            signedURLs.removeValue(forKey: plan)
                            await Task.detached { try? FileManager.default.removeItem(at: tmp) }.value
                            throw URLError(.badServerResponse)
                        }
                        try await Task.detached(priority: .utility) {
                            defer { try? FileManager.default.removeItem(at: tmp) }
                            guard (try tmp.resourceValues(forKeys: [.fileSizeKey])).fileSize == length else { throw URLError(.badServerResponse) }
                            if FileManager.default.fileExists(atPath: part.path) { try FileManager.default.removeItem(at: part) }
                            try FileManager.default.moveItem(at: tmp, to: part)
                        }.value
                        try Task.checkCancellation()
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
        try await Task.detached(priority: .utility) {
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

/// 提供区间内部的实时进度；已完成区间仍由下载管理器持久化。
private nonisolated final class PresetTransferProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let report: @Sendable (Int64) -> Void
    init(report: @escaping @Sendable (Int64) -> Void) { self.report = report }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        report(totalBytesWritten)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) { }
}
