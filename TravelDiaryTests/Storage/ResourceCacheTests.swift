import Testing
import Foundation
import UIKit
@testable import TravelDiary

@MainActor
struct ResourceCacheTests {
    private struct Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var paths: StoragePaths { StoragePaths(support: root.appendingPathComponent("Support"), caches: root.appendingPathComponent("Caches"), temporary: root.appendingPathComponent("Tmp")) }
        func key(_ id: String, owner: String = "a") -> ResourceCacheKey { .account(owner, category: "test", identity: id) }
        func remove() { try? FileManager.default.removeItem(at: root) }
        func write(_ data: Data, to url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
    }
    @Test func evictionUsesLastReadAndSurvivesRestart() throws {
        let f = Fixture(); defer { f.remove() }
        var cache: ResourceCache? = ResourceCache(paths: f.paths, limit: 100)
        cache?.store(Data(repeating: 1, count: 30), for: f.key("1"))
        cache?.store(Data(repeating: 2, count: 30), for: f.key("2"))
        cache?.store(Data(repeating: 3, count: 30), for: f.key("3"))
        #expect(cache?.data(for: f.key("1"))?.count == 30)
        cache?.flushAccesses(); cache = nil
        let restored = ResourceCache(paths: f.paths, limit: 100)
        restored.store(Data(repeating: 4, count: 40), for: f.key("4"))
        #expect(restored.data(for: f.key("1")) != nil)
        #expect(restored.data(for: f.key("2")) == nil)
        #expect(restored.data(for: f.key("3")) == nil)
        #expect(restored.totalBytes == 70)
    }
    @Test func shrinkingCapacitySkipsReadersAndRetriesAfterRelease() throws {
        let f = Fixture(); defer { f.remove() }
        let activity = StorageActivity(), cache = ResourceCache(paths: f.paths, activity: activity, limit: 100)
        let url = try #require(cache.store(Data(repeating: 1, count: 80), for: f.key("1")))
        var lease: StorageActivity.Lease? = activity.acquire(url)
        cache.setCapacity(10)
        #expect(FileManager.default.fileExists(atPath: url.path))
        withExtendedLifetime(lease) {}; lease = nil
        cache.maintain()
        #expect(cache.totalBytes == 0)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
    @Test func oversizedObjectsAndProtectedBudgetDoNotDestroyUsefulData() throws {
        let f = Fixture(); defer { f.remove() }
        let activity = StorageActivity(), cache = ResourceCache(paths: f.paths, activity: activity, limit: 100)
        let url = try #require(cache.store(Data(repeating: 1, count: 80), for: f.key("1")))
        let lease = activity.acquire(url)
        #expect(cache.store(Data(repeating: 1, count: 101), for: f.key("oversized")) == nil)
        #expect(cache.store(Data(repeating: 1, count: 40), for: f.key("full")) == nil)
        #expect(cache.data(for: f.key("1"))?.count == 80)
        withExtendedLifetime(lease) {}
    }
    @Test func sessionAndClearRejectLateWritesAndKeepAccountsSeparate() {
        let f = Fixture(); defer { f.remove() }
        let cache = ResourceCache(paths: f.paths)
        let a = f.key("image"), b = f.key("image", owner: "b")
        let generation = cache.generation(for: a)
        cache.store(Data([1]), for: a); cache.store(Data([2]), for: b)
        cache.invalidateSession(scope: a.scope)
        #expect(cache.store(Data([3]), for: a, expectedGeneration: generation) == nil)
        cache.clear(scope: a.scope)
        #expect(cache.data(for: a) == nil)
        #expect(cache.data(for: b) == Data([2]))
    }
    @Test func externalRegistrationRejectsOriginalsAndSymlinks() throws {
        let f = Fixture(); defer { f.remove() }
        let cache = ResourceCache(paths: f.paths)
        let original = f.paths.books("a").appendingPathComponent("original.png")
        try f.write(Data([1]), to: original)
        cache.register(original, for: f.key("original"))
        let link = f.paths.cacheRoot.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: f.paths.cacheRoot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        cache.register(link, for: f.key("link")); cache.clear()
        #expect(cache.entries().isEmpty)
        #expect(FileManager.default.fileExists(atPath: original.path))
    }
    @Test func manualCleanupChecksReplacedFileAndScopesMetadata() async throws {
        let f = Fixture(); defer { f.remove() }
        let cache = ResourceCache(paths: f.paths)
        let url = try #require(cache.store(Data([1]), for: f.key("image")))
        cache.store(Data(repeating: 2, count: 200), for: f.key("private", owner: "b"))
        let service = StorageService(paths: f.paths, cache: cache)
        await service.activate(owner: "a")
        let snapshot = try await service.scan(owner: "a")
        #expect(snapshot.items.count == 1)
        #expect(snapshot.totals[.otherAccounts] == 200)
        try f.write(Data([3, 4]), to: url)
        let result = try await service.clean(snapshot: snapshot, ids: Set(snapshot.items.map(\.id)))
        #expect(result.removed == 0 && result.skipped == 1)
        #expect(try Data(contentsOf: url) == Data([3, 4]))
    }
    @Test func missingObjectsAreReconciledAndExpiredEntriesAreNotServed() throws {
        let f = Fixture(); defer { f.remove() }
        let cache = ResourceCache(paths: f.paths)
        let url = try #require(cache.store(Data([1]), for: f.key("missing")))
        cache.store(Data([2]), for: f.key("expired"), expiresAt: .distantPast)
        try FileManager.default.removeItem(at: url)
        cache.maintain()
        #expect(cache.data(for: f.key("missing")) == nil)
        #expect(cache.data(for: f.key("expired")) == nil)
    }
    @Test func attachmentStagingIsProtectedUntilTheServerAcknowledgesIt() async throws {
        let f = Fixture(); defer { f.remove() }
        let resourceCache = ResourceCache(paths: f.paths, limit: 100)
        let files = FileCacheManager(baseDirectory: f.paths.cacheAccounts, resourceCache: resourceCache)
        await files.activateAccountContext(1)
        let namespace = await files.accountContext()
        let staging = try await files.save(data: Data([1, 2]), fileUUID: "upload", fileName: "photo.png")
        let downloaded = try await files.save(data: Data([3, 4]), fileUUID: "download", fileName: "photo.png", automaticallyEvictable: true)
        resourceCache.setCapacity(0)
        #expect(FileManager.default.fileExists(atPath: staging.path))
        #expect(!FileManager.default.fileExists(atPath: downloaded.path))
        await files.markRebuildable(fileUUID: "upload", fileName: "photo.png", namespace: namespace)
        resourceCache.maintain()
        #expect(!FileManager.default.fileExists(atPath: staging.path))
    }
    @Test func legacyMigrationAdoptsOnlyKnownRebuildableFiles() throws {
        let f = Fixture(); defer { f.remove() }
        let cache = ResourceCache(paths: f.paths, limit: 100)
        let catalog = f.paths.catalog("a"), original = f.paths.books("a").appendingPathComponent("original.png")
        let unknown = f.paths.cacheAccount("a").appendingPathComponent("Attachments/unknown/file")
        try f.write(Data([1]), to: catalog); try f.write(Data([2]), to: original); try f.write(Data([3]), to: unknown)
        LegacyCacheMigration.run(cache: cache)
        #expect(cache.entries().count == 1)
        cache.clear()
        #expect(!FileManager.default.fileExists(atPath: catalog.path))
        #expect(FileManager.default.fileExists(atPath: original.path))
        #expect(FileManager.default.fileExists(atPath: unknown.path))
    }
    @Test func corruptIndexRecoversWithoutTouchingUserData() throws {
        let f = Fixture(); defer { f.remove() }
        let original = f.paths.books("a").appendingPathComponent("original")
        try f.write(Data([9]), to: original)
        try f.write(Data("corrupt sqlite".utf8), to: f.paths.cache("Resources").appendingPathComponent("index.sqlite"))
        let cache = ResourceCache(paths: f.paths)
        #expect(cache.store(Data([1]), for: f.key("recovered")) != nil)
        #expect(cache.data(for: f.key("recovered")) == Data([1]))
        #expect(try Data(contentsOf: original) == Data([9]))
    }
    @Test func conditionalResponseUsesRetainedBodyEvenAfterEviction() throws {
        let url = try #require(URL(string: "https://example.test/catalog"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: 304, httpVersion: "HTTP/1.1", headerFields: [:]))
        let interceptor = ETagHTTPInterceptor(store: EmptyResourceETagStore())
        let body = Data("cached body".utf8)
        let result = interceptor.intercept(transportResponse: SupportTransportResponse(data: Data(), httpResponse: response),
            cacheKey: "evicted", request: SupportNetworkRequest(method: .get, path: "/catalog"), conditionalBody: body)
        #expect(result.didMerge304)
        #expect(result.data == body)
    }
    private func png() throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 10), format: format).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        }
        return try #require(image.pngData())
    }
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CacheImageURLProtocol.self]
        return URLSession(configuration: configuration)
    }
    @Test func signedURLChangesAndNewPipelineReuseDiskWithoutNetwork() async throws {
        let f = Fixture(); defer { f.remove() }
        let cache = ResourceCache(paths: f.paths), session = session()
        let host = UUID().uuidString.lowercased() + ".test"
        CacheImageURLProtocol.install(host: host, data: try png()); defer { CacheImageURLProtocol.remove(host: host) }
        let first = PreviewImageRequest(key: f.key("same-version-page"), url: URL(string: "https://\(host)/image?Signature=first"))
        let pipeline = PreviewImagePipeline(cache: cache, session: session)
        _ = try await pipeline.load(first)
        var second = first; second.url = URL(string: "https://\(host)/image?Signature=second")
        let reopened = PreviewImagePipeline(cache: cache, session: session)
        let image = try await reopened.load(second)
        #expect(image.size.width == 20)
        #expect(CacheImageURLProtocol.count(host: host) == 1)
        #expect(reopened.diskHits == 1)
        var newVersion = second
        newVersion = PreviewImageRequest(key: f.key("new-version-page"), url: newVersion.url)
        _ = try await reopened.load(newVersion)
        #expect(CacheImageURLProtocol.count(host: host) == 2)
    }
    @Test func concurrentConsumersShareDownloadAndCancellationDoesNotBreakOtherConsumer() async throws {
        let f = Fixture(); defer { f.remove() }
        let host = UUID().uuidString.lowercased() + ".test"
        CacheImageURLProtocol.install(host: host, data: try png(), delay: 0.1); defer { CacheImageURLProtocol.remove(host: host) }
        let pipeline = PreviewImagePipeline(cache: ResourceCache(paths: f.paths), session: session())
        let request = PreviewImageRequest(key: f.key("image"), url: URL(string: "https://\(host)/image"))
        let first = Task { try await pipeline.load(request) }
        var larger = request; larger.maxPixelSize = 2048
        let secondRequest = larger
        let second = Task { try await pipeline.load(secondRequest) }
        first.cancel()
        _ = try await second.value
        #expect(CacheImageURLProtocol.count(host: host) == 1)
    }
    @Test func localResolverUsesDownloadedPageAndDoesNotDuplicateDiskBytes() async throws {
        let f = Fixture(); defer { f.remove() }
        let local = f.paths.downloads.appendingPathComponent("partial/page.png")
        try f.write(png(), to: local)
        let cache = ResourceCache(paths: f.paths)
        let pipeline = PreviewImagePipeline(cache: cache, session: session())
        let request = PreviewImageRequest(key: f.key("page"), url: URL(string: "https://unreachable.test/image"), resolveLocalURL: { local })
        _ = try await pipeline.load(request)
        #expect(pipeline.localHits == 1)
        #expect(pipeline.networkBytes == 0)
        #expect(cache.totalBytes == 0)
    }
    @Test func invalidNetworkImagesAreNeverPersisted() async throws {
        let f = Fixture(); defer { f.remove() }
        let host = UUID().uuidString.lowercased() + ".test"
        CacheImageURLProtocol.install(host: host, data: Data("not an image".utf8)); defer { CacheImageURLProtocol.remove(host: host) }
        let cache = ResourceCache(paths: f.paths), pipeline = PreviewImagePipeline(cache: cache, session: session())
        let request = PreviewImageRequest(key: f.key("image"), url: URL(string: "https://\(host)/image"))
        await #expect(throws: (any Error).self) { try await pipeline.load(request) }
        #expect(cache.data(for: request.key) == nil)
    }
    @Test func clearingWhileDownloadingCannotRepopulateTheCache() async throws {
        let f = Fixture(); defer { f.remove() }
        let host = UUID().uuidString.lowercased() + ".test"
        CacheImageURLProtocol.install(host: host, data: try png(), delay: 0.15); defer { CacheImageURLProtocol.remove(host: host) }
        let cache = ResourceCache(paths: f.paths), pipeline = PreviewImagePipeline(cache: cache, session: session())
        let request = PreviewImageRequest(key: f.key("image"), url: URL(string: "https://\(host)/image"))
        let task = Task { try await pipeline.load(request) }
        while CacheImageURLProtocol.count(host: host) == 0 { await Task.yield() }
        cache.clear()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(cache.totalBytes == 0)
        #expect(pipeline.cached(request) == nil)
    }
}

nonisolated private final class CacheImageURLProtocol: URLProtocol, @unchecked Sendable {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var responses: [String: (Data, TimeInterval)] = [:]
        var counts: [String: Int] = [:]
    }
    private static let state = State()
    static func install(host: String, data: Data, delay: TimeInterval = 0) {
        state.lock.lock(); defer { state.lock.unlock() }; state.responses[host] = (data, delay); state.counts[host] = 0
    }
    static func remove(host: String) {
        state.lock.lock(); defer { state.lock.unlock() }; state.responses[host] = nil; state.counts[host] = nil
    }
    static func count(host: String) -> Int {
        state.lock.lock(); defer { state.lock.unlock() }; return state.counts[host, default: 0]
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let host = request.url?.host ?? ""
        Self.state.lock.lock()
        let value = Self.state.responses[host]
        Self.state.counts[host, default: 0] += 1
        Self.state.lock.unlock()
        guard let value, let url = request.url else { client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost)); return }
        DispatchQueue.global().asyncAfter(deadline: .now() + value.1) { [self] in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: value.0)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

nonisolated private struct EmptyResourceETagStore: ETagStore {
    func record(forKey key: String) -> ETagCacheRecord? { nil }
    func cachedBody(forKey key: String) -> Data? { nil }
    func store(record: ETagCacheRecord, body: Data, forKey key: String) throws {}
    func removeCache(forKey key: String) {}
}
