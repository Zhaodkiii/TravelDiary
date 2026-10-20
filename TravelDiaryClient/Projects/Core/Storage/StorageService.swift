import Foundation

nonisolated enum StorageCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case diaries, downloads, previews, exports, camera, printOrders, business, otherAccounts, unknown
    var id: String { rawValue }
    var title: String {
        switch self {
        case .diaries: "手帐作品与恢复资料"
        case .downloads: "模板、素材与本地模型"
        case .previews: "预览与浏览缓存"
        case .exports: "导出文件"
        case .camera: "相机临时资料"
        case .printOrders: "印制资料"
        case .business: "其他业务数据"
        case .otherAccounts: "其他账号数据"
        case .unknown: "待识别与管理数据"
        }
    }
    var symbol: String {
        switch self {
        case .diaries: "book.closed"
        case .downloads: "arrow.down.circle"
        case .previews: "photo.on.rectangle"
        case .exports: "square.and.arrow.up"
        case .camera: "camera"
        case .printOrders: "shippingbox"
        case .business: "externaldrive"
        case .otherAccounts: "person.2"
        case .unknown: "folder.badge.questionmark"
        }
    }
    var explanation: String {
        switch self {
        case .diaries: "原图、页面、草稿、历史和最近删除均保留。清理预览不会删除作品。"
        case .downloads: "主动下载不参加安全清理。移除模板下载不影响已完整导入的手帐；再次下载需要联网。模型与未知归属素材暂只统计。"
        case .previews: "可清理项仅包括当前账号已登记的手帐预览和模板目录缓存。重新打开会生成预览或重新联网加载。"
        case .exports: "只管理带任务记录且已完成的本地导出副本。系统相册和“文件”中的副本不受影响。"
        case .camera: "未保存媒体可能是唯一副本，当前保守保留。请在相机内完成保存或放弃编辑。"
        case .printOrders: "上传断点和生产文件受保护。请在订单中继续处理；清理缓存不取消订单。"
        case .business: "包含数据库、设置、知识库和其他业务资料，清缓存不会重置登录或删除记录。"
        case .otherAccounts: "仅显示汇总占用。请切换对应账号后管理，不展示其他账号的作品或文件。"
        case .unknown: "包含管理索引、旧版临时产物及尚未登记归属的文件。未确认用途前保留原文件。"
        }
    }
}

nonisolated struct StorageItem: Identifiable, Sendable {
    let id: String
    let category: StorageCategory
    let bytes: Int64
    let modified: Date
    let title: String
    let canRemove: Bool
    let automatic: Bool
    let reason: String
}
nonisolated struct StorageSnapshot: Sendable {
    let id: UUID
    let owner: String
    let generation: UUID
    let generatedAt: Date
    let totals: [StorageCategory: Int64]
    let items: [StorageItem]
    let unreadableCount: Int
    let available: Int64?
    var total: Int64 { totals.values.reduce(0, +) }
    var safeBytes: Int64 { items.filter { $0.automatic }.reduce(0) { $0 + $1.bytes } }
}
nonisolated struct StorageCleanupResult: Codable, Sendable {
    var removed = 0
    var skipped = 0
    var failed = 0
    var stopped = false
    var bytes: Int64 = 0
    var completedAt = Date()
}

/// A scoped catalog/cleanup provider for rebuildable previews and registered export workspaces.
/// Unregistered resources are counted but never treated as deletion candidates.
actor StorageService {
    let paths: StoragePaths
    private let activity: StorageActivity
    private var owner: String?
    private var generation = UUID()
    private var files: [String: Candidate] = [:]
    private var latestID: UUID?
    private struct Candidate {
        let url: URL
        let root: URL
        let item: StorageItem
        let fileNumber: UInt64?
        let workspace: URL?
    }

    init(paths: StoragePaths = .system, activity: StorageActivity = .shared) { self.paths = paths; self.activity = activity }
    func activate(owner value: String?) {
        guard value != owner else { return }
        owner = value; generation = UUID(); latestID = nil; files = [:]
    }
    private func validate(_ expected: String, generation expectedGeneration: UUID? = nil) throws {
        guard owner == expected, expectedGeneration == nil || expectedGeneration == generation else { throw StorageFailure.accountChanged }
    }

    func scan(owner expected: String) async throws -> StorageSnapshot {
        try validate(expected)
        let session = generation
        var totals: [StorageCategory: Int64] = [:], items: [StorageItem] = []
        var catalog: [String: Candidate] = [:], failures = 0, visited = Set<String>(), identities = Set<String>()
        let fm = FileManager.default
        let privatePrint = paths.printOrders(expected)
        let privateCache = paths.cacheAccount(expected)
        var fileIndex = 0
        // The catalog covers disk data; scope is decided before publishing any item metadata.
        for root in [paths.support, paths.caches, paths.temporary] {
            guard fm.fileExists(atPath: root.path) else { continue }
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
                options: [], errorHandler: { _, _ in failures += 1; return true }) else { failures += 1; continue }
            while let url = enumerator.nextObject() as? URL {
                fileIndex += 1
                if fileIndex.isMultiple(of: 128) { await Task.yield(); try Task.checkCancellation(); try validate(expected, generation: session) }
                guard visited.insert(url.standardizedFileURL.path).inserted else { continue }
                let values: URLResourceValues
                do { values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]) }
                catch { failures += 1; enumerator.skipDescendants(); continue }
                if values.isSymbolicLink == true { enumerator.skipDescendants(); failures += 1; continue }
                guard values.isRegularFile == true else { continue }
                let attributes = try? fm.attributesOfItem(atPath: url.path)
                let fileNumber = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
                if let fileNumber, let volume = (attributes?[.systemNumber] as? NSNumber)?.uint64Value {
                    guard identities.insert("\(volume):\(fileNumber)").inserted else { continue }
                }
                let bytes = Int64(values.fileSize ?? 0), modified = values.contentModificationDate ?? .distantPast
                var category: StorageCategory = .unknown
                var removable = false, automatic = false, reason = "资料受保护或尚未确认用途", title = ""
                var workspace: URL?
                let relative = String(url.path.dropFirst(root.path.count + 1))
                if StoragePaths.contains(url, in: paths.accounts), !StoragePaths.contains(url, in: paths.account(expected)) {
                    category = .otherAccounts
                } else if StoragePaths.contains(url, in: paths.cacheAccounts), !StoragePaths.contains(url, in: privateCache) {
                    category = .otherAccounts
                } else if StoragePaths.contains(url, in: paths.diaryOwner(expected)) || StoragePaths.contains(url, in: paths.trash(expected)) {
                    category = .diaries
                } else if StoragePaths.contains(url, in: paths.previews(expected)) {
                    category = .previews
                    removable = url.pathExtension == "png" && canRebuildPreview(url, owner: expected)
                    automatic = removable; title = "手帐预览"
                } else if url.standardizedFileURL == paths.catalog(expected).standardizedFileURL {
                    category = .previews; removable = true; automatic = true; title = "模板目录缓存"
                } else if StoragePaths.contains(url, in: paths.downloads) || StoragePaths.contains(url, in: paths.persistent("LocalModels")) {
                    category = .downloads
                } else if StoragePaths.contains(url, in: privatePrint) { category = .printOrders
                } else if StoragePaths.contains(url, in: paths.account(expected)) || StoragePaths.contains(url, in: privateCache) {
                    category = .business
                } else if StoragePaths.contains(url, in: paths.camera) || StoragePaths.contains(url, in: paths.persistent("CameraEditor")) { category = .camera
                } else if StoragePaths.contains(url, in: paths.workspaces) {
                    let remainder = String(url.path.dropFirst(paths.workspaces.path.count + 1))
                    if let folder = remainder.split(separator: "/").first {
                        let dir = paths.workspaces.appendingPathComponent(String(folder))
                        if let data = try? Data(contentsOf: dir.appendingPathComponent(StorageWorkspace.manifestName)),
                           let record = try? JSONDecoder().decode(StorageWorkspace.self, from: data) {
                            category = record.owner == expected ? .exports : .otherAccounts
                            if category == .exports, let completed = record.completedAt,
                               sourceBookExists(record.bookID, owner: expected),
                               url.lastPathComponent != StorageWorkspace.manifestName {
                                title = url.lastPathComponent
                                removable = true; automatic = completed < Date().addingTimeInterval(-7 * 86400); workspace = dir
                            }
                        }
                    }
                } else if StoragePaths.contains(url, in: paths.caches) {
                    category = .previews // Unattributed caches are counted, but cannot be cleared.
                } else if StoragePaths.contains(url, in: paths.persistentRoot) {
                    category = .business
                }
                totals[category, default: 0] += bytes
                guard removable else { continue }
                if (attributes?[.referenceCount] as? NSNumber)?.intValue ?? 1 > 1 { removable = false; automatic = false; reason = "共享物理文件，已保留" }
                else if activity.isInUse(url) { removable = false; automatic = false; reason = "资料正在使用，已保留" }
                else { reason = category == .exports ? "删除 App 内导出副本，原手帐保留" : "再次打开时重建或联网加载" }
                let id = StoragePaths.digest(root.path + "/" + relative)
                let item = StorageItem(id: id, category: category, bytes: bytes, modified: modified, title: title,
                                       canRemove: removable, automatic: automatic, reason: reason)
                items.append(item)
                catalog[id] = Candidate(url: url, root: root, item: item, fileNumber: fileNumber, workspace: workspace)
            }
        }
        try Task.checkCancellation(); try validate(expected, generation: session)
        let id = UUID(); latestID = id; files = catalog
        let available = try? paths.support.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        return StorageSnapshot(id: id, owner: expected, generation: session, generatedAt: Date(), totals: totals,
                               items: items.sorted { $0.bytes > $1.bytes }, unreadableCount: failures, available: available)
    }

    private func sourceBookExists(_ id: UUID, owner: String) -> Bool {
        let root = paths.books(owner).appendingPathComponent(id.uuidString)
        guard let data = try? Data(contentsOf: root.appendingPathComponent("book.json")),
              let book = try? JSONDecoder().decode(DiaryBook.self, from: data),
              book.id == id, book.format == "TravelDiary.Book", book.schemaVersion == 1 else { return false }
        return book.pages.allSatisfy { completeManifest(root: root, pageID: $0.id, revision: $0.revisionID.uuidString) }
    }

    private func canRebuildPreview(_ url: URL, owner: String) -> Bool {
        let relative = String(url.path.dropFirst(paths.previews(owner).path.count + 1)).split(separator: "/").map(String.init)
        guard relative.count == 4, let bookID = UUID(uuidString: relative[0]), let pageID = UUID(uuidString: relative[1]),
              UUID(uuidString: relative[2]) != nil else { return false }
        let root = paths.books(owner).appendingPathComponent(bookID.uuidString)
        guard let data = try? Data(contentsOf: root.appendingPathComponent("book.json")),
              let book = try? JSONDecoder().decode(DiaryBook.self, from: data), book.id == bookID,
              book.pages.contains(where: { $0.id == pageID }) || book.trashedPages.contains(where: { $0.id == pageID }) else { return false }
        return completeManifest(root: root, pageID: pageID, revision: relative[2])
    }

    private func completeManifest(root: URL, pageID: UUID, revision: String) -> Bool {
        guard let pageRoot = try? StoragePaths.resolve("pages/" + pageID.uuidString, within: root),
              let manifestURL = try? StoragePaths.resolve("revisions/" + revision + "/manifest.json", within: pageRoot),
              let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              manifest["format"] as? String == "TravelDiary.SmartCanvas", manifest["documentID"] as? String == pageID.uuidString,
              let assets = manifest["assets"] as? [String: [String: Any]],
              let objects = manifest["objects"] as? [[String: Any]], !objects.isEmpty else { return false }
        for asset in assets.values {
            guard let path = asset["path"] as? String, let target = try? StoragePaths.resolve(path, within: root),
                  FileManager.default.fileExists(atPath: target.path) else { return false }
        }
        for object in objects {
            for key in ["path", "drawingPath"] {
                guard let path = object[key] as? String, let target = try? StoragePaths.resolve(path, within: pageRoot),
                      FileManager.default.fileExists(atPath: target.path) else { return false }
            }
        }
        return true
    }

    func policy() -> StoragePolicy {
        guard let data = try? Data(contentsOf: paths.control.appendingPathComponent("policy.json")),
              let value = try? JSONDecoder().decode(StoragePolicy.self, from: data) else { return StoragePolicy() }
        return value
    }
    func savePolicy(_ value: StoragePolicy, owner expected: String) throws {
        try validate(expected)
        guard [500_000_000, 1_000_000_000, 2_000_000_000].contains(value.previewLimit) else { throw StorageFailure.stalePlan }
        try FileManager.default.createDirectory(at: paths.control, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: paths.control.appendingPathComponent("policy.json"), options: .atomic)
    }
    /// Runs only when the storage page refreshes and the user has explicitly enabled the policy.
    func maintain(snapshot: StorageSnapshot) async throws -> StorageCleanupResult? {
        try validate(snapshot.owner, generation: snapshot.generation)
        let settings = policy()
        guard settings.automaticallyManageSafeFiles else { return nil }
        var ids = Set(snapshot.items.filter { $0.automatic && $0.category == .exports }.map(\.id))
        var remaining = snapshot.totals[.previews, default: 0]
        for item in snapshot.items.filter({ $0.automatic && $0.category == .previews }).sorted(by: { $0.modified < $1.modified }) where remaining > settings.previewLimit {
            ids.insert(item.id); remaining -= item.bytes
        }
        guard !ids.isEmpty else { return nil }
        return try await clean(snapshot: snapshot, ids: ids)
    }

    func checkOwner(_ expected: String) throws { try validate(expected) }

    func bookSizes(owner expected: String) async throws -> [UUID: Int64] {
        try validate(expected)
        let session = generation
        let fm = FileManager.default
        guard fm.fileExists(atPath: paths.books(expected).path) else { return [:] }
        var result: [UUID: Int64] = [:]
        for directory in try fm.contentsOfDirectory(at: paths.books(expected), includingPropertiesForKeys: nil) {
            guard let id = UUID(uuidString: directory.lastPathComponent),
                  StoragePaths.contains(directory.resolvingSymlinksInPath(), in: paths.books(expected)) else { continue }
            if let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]) {
                var count = 0
                while let url = enumerator.nextObject() as? URL {
                    count += 1
                    if count.isMultiple(of: 128) { await Task.yield(); try validate(expected, generation: session); try Task.checkCancellation() }
                    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                    if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                    if values.isRegularFile == true { result[id, default: 0] += Int64(values.fileSize ?? 0) }
                }
            }
        }
        return result
    }

    nonisolated struct ExportAccess: Identifiable, Sendable {
        let id = UUID()
        let url: URL
        let lease: StorageActivity.Lease
    }
    func exportAccess(snapshot: StorageSnapshot, id: String) throws -> ExportAccess {
        try validate(snapshot.owner, generation: snapshot.generation)
        guard latestID == snapshot.id, let candidate = files[id], candidate.item.category == .exports,
              FileManager.default.fileExists(atPath: candidate.url.path),
              StoragePaths.contains(candidate.url.resolvingSymlinksInPath(), in: paths.workspaces) else { throw StorageFailure.stalePlan }
        let lease = activity.acquire(candidate.url)
        return ExportAccess(url: candidate.url, lease: lease)
    }

    /// Snapshot and individual file versions are checked again. No API accepts arbitrary filesystem paths.
    func clean(snapshot: StorageSnapshot, ids: Set<String>) async throws -> StorageCleanupResult {
        try validate(snapshot.owner, generation: snapshot.generation)
        guard latestID == snapshot.id, Date().timeIntervalSince(snapshot.generatedAt) < 600 else { throw StorageFailure.stalePlan }
        let candidates = try ids.map { id -> Candidate in
            guard let value = files[id], value.item.canRemove else { throw StorageFailure.stalePlan }; return value
        }
        var result = StorageCleanupResult()
        for candidate in candidates {
            if Task.isCancelled { result.stopped = true; break }
            try validate(snapshot.owner, generation: snapshot.generation)
            do {
                try activity.exclusively(candidate.url) {
                    if candidate.item.category == .previews, candidate.url.pathExtension == "png", !canRebuildPreview(candidate.url, owner: snapshot.owner) { throw StorageFailure.stalePlan }
                    if let workspace = candidate.workspace {
                        let record = try JSONDecoder().decode(StorageWorkspace.self, from: Data(contentsOf: workspace.appendingPathComponent(StorageWorkspace.manifestName)))
                        guard record.owner == snapshot.owner, record.completedAt != nil,
                              sourceBookExists(record.bookID, owner: snapshot.owner) else { throw StorageFailure.stalePlan }
                    }
                    guard StoragePaths.contains(candidate.url.resolvingSymlinksInPath(), in: candidate.root.standardizedFileURL),
                          (try candidate.url.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw StorageFailure.unsafePath }
                    let attr = try FileManager.default.attributesOfItem(atPath: candidate.url.path)
                    guard (attr[.size] as? NSNumber)?.int64Value == candidate.item.bytes,
                          attr[.modificationDate] as? Date == candidate.item.modified,
                          (attr[.systemFileNumber] as? NSNumber)?.uint64Value == candidate.fileNumber else { throw StorageFailure.stalePlan }
                    try FileManager.default.removeItem(at: candidate.url)
                }
                result.removed += 1; result.bytes += candidate.item.bytes
            } catch StorageFailure.inUse { result.skipped += 1
            } catch StorageFailure.stalePlan { result.skipped += 1
            } catch { result.failed += 1 }
            await Task.yield()
        }
        latestID = nil; files = [:]; result.completedAt = Date()
        // Metadata only; no account identifiers, paths or titles in the result journal.
        try? FileManager.default.createDirectory(at: paths.control, withIntermediateDirectories: true)
        try? JSONEncoder().encode(result).write(to: paths.control.appendingPathComponent("last-cleanup.json"), options: .atomic)
        return result
    }
}
