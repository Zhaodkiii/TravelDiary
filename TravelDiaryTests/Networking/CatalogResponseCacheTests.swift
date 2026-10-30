import XCTest
import Testing
@testable import TravelDiary

@MainActor
final class CatalogResponseCacheTests {
    private var root: URL!
    private var disk: ResourceCache!
    private var cache: CatalogResponseCache!
    private var clock = Date(timeIntervalSince1970: 1_000)
    init() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        disk = ResourceCache(paths: StoragePaths(support: root.appendingPathComponent("Support"),
            caches: root.appendingPathComponent("Caches"), temporary: root.appendingPathComponent("Tmp")))
        cache = CatalogResponseCache(cache: disk, now: { [unowned self] in clock })
    }


    @Test func testFreshSnapshotSurvivesRestartAndNormalizesQueryOrder() async throws {
        _ = try await cache.load(owner: "a", domain: "fonts", path: "/list?sort=new&page=1") { Data([1]) }
        let restored = CatalogResponseCache(cache: disk, now: { self.clock })
        let result = try await restored.load(owner: "a", domain: "fonts", path: "/list?page=1&sort=new") {
            XCTFail("fresh persisted catalog must not request the server"); return Data([2])
        }
        XCTAssertEqual(result, Data([1]))
    }
    @Test func testStaleIsDeliveredBeforeRefreshAndForceBypassesTTL() async throws {
        _ = try await cache.load(owner: "a", domain: "fonts", path: "/list") { Data([1]) }
        clock.addTimeInterval(301)
        var events: [String] = []
        let result = try await cache.load(owner: "a", domain: "fonts", path: "/list", onCached: { data in
            XCTAssertEqual(data, Data([1])); events.append("cached")
        }) { events.append("network"); return Data([2]) }
        XCTAssertEqual(events, ["cached", "network"])
        XCTAssertEqual(result, Data([2]))
        let forced = try await cache.load(owner: "a", domain: "fonts", path: "/list", forceRefresh: true) { Data([3]) }
        XCTAssertEqual(forced, Data([3]))
    }
    @Test func testAccountPageAndFilterIsolation() async throws {
        _ = try await cache.load(owner: "a", domain: "fonts", path: "/list?page=1") { Data([1]) }
        for (owner, path) in [("b", "/list?page=1"), ("a", "/list?page=2"), ("a", "/list?page=1&q=other")] {
            let result = try await cache.load(owner: owner, domain: "fonts", path: path) { Data([2]) }
            XCTAssertEqual(result, Data([2]))
        }
    }
    @Test func testConcurrentRequestsShareOneFetch() async throws {
        var calls = 0
        let fetch: @MainActor () async throws -> Data = {
            calls += 1
            try await Task.sleep(for: .milliseconds(50))
            return Data([1])
        }
        let a = Task { try await cache.load(owner: "a", domain: "fonts", path: "/list", fetch: fetch) }
        let b = Task { try await cache.load(owner: "a", domain: "fonts", path: "/list", fetch: fetch) }
        let first = try await a.value; let second = try await b.value
        XCTAssertEqual(first, second); XCTAssertEqual(calls, 1)
    }
    @Test func testMutationRejectsLateResponseAndDoesNotClearOtherDomains() async throws {
        _ = try await cache.load(owner: "a", domain: "help", path: "/list") { Data([9]) }
        do {
            _ = try await cache.load(owner: "a", domain: "fonts", path: "/list") {
                self.cache.invalidate(owner: "a", domain: "fonts")
                return Data([1])
            }
            XCTFail("invalidated request must not return or repopulate cache")
        } catch is CancellationError { }
        let value = try await cache.load(owner: "a", domain: "fonts", path: "/list") { Data([2]) }
        XCTAssertEqual(value, Data([2]))
        let other = try await cache.load(owner: "a", domain: "help", path: "/list") { XCTFail(); return Data() }
        XCTAssertEqual(other, Data([9]))
    }
    @Test func testOfflineFallbackButNeverAuthorizationFallback() async throws {
        _ = try await cache.load(owner: "a", domain: "fonts", path: "/list") { Data([1]) }
        clock.addTimeInterval(301)
        let offline = try await cache.load(owner: "a", domain: "fonts", path: "/list") {
            throw SupportNetworkError.transport(URLError(.notConnectedToInternet))
        }
        XCTAssertEqual(offline, Data([1]))
        do {
            _ = try await cache.load(owner: "a", domain: "fonts", path: "/list") {
                throw SupportNetworkError.http(statusCode: 403, backend: nil, data: Data())
            }
            XCTFail("403 must not be hidden by stale data")
        } catch let error as SupportNetworkError {
            guard case .http(statusCode: 403, backend: _, data: _) = error else { return XCTFail() }
        }
    }
    @Test func testClearDuringFetchRejectsWrite() async throws {
        do {
            _ = try await cache.load(owner: "a", domain: "fonts", path: "/list") {
                self.disk.clear(); return Data([1])
            }
            XCTFail()
        } catch is CancellationError { }
        XCTAssertTrue(disk.entries().isEmpty)
    }
    @Test func testExpiredETagStillRevalidatesAndBillingSessionIsIsolated() throws {
        let store = FileETagStore(baseDirectory: root.appendingPathComponent("ETags"))
        let interceptor = ETagHTTPInterceptor(store: store)
        let url = URL(string: "https://example.com/catalog")!
        var request = URLRequest(url: url)
        request.setValue("session-a", forHTTPHeaderField: "X-Billing-Session")
        let key = interceptor.cacheKey(for: request)
        try store.store(etag: "old", body: Data("{}".utf8), forKey: key, expirationDate: Date().addingTimeInterval(-1))
        let applied = interceptor.applyIfNoneMatch(to: request, cacheKey: key,
            request: SupportNetworkRequest(method: .get, path: "/catalog", strategy: .init(allowETag: true)))
        XCTAssertEqual(applied.value(forHTTPHeaderField: "If-None-Match"), "old")
        request.setValue("session-b", forHTTPHeaderField: "X-Billing-Session")
        XCTAssertNotEqual(key, interceptor.cacheKey(for: request))
        store.removeCache(forKey: key)
        let missing = interceptor.applyIfNoneMatch(to: request, cacheKey: key,
            request: SupportNetworkRequest(method: .get, path: "/catalog", strategy: .init(allowETag: true)))
        XCTAssertNil(missing.value(forHTTPHeaderField: "If-None-Match"))
    }


    @Test func cancellationIsControlFlowAcrossNetworkLayers() {
        XCTAssertTrue(CatalogLoadError.isCancellation(CancellationError()))
        XCTAssertTrue(CatalogLoadError.isCancellation(URLError(.cancelled)))
        XCTAssertTrue(CatalogLoadError.isCancellation(SupportNetworkError.cancelled))
        XCTAssertTrue(CatalogLoadError.isCancellation(SupportNetworkError.transport(URLError(.cancelled))))
        XCTAssertFalse(CatalogLoadError.isCancellation(URLError(.timedOut)))
        XCTAssertFalse(CatalogLoadError.isCancellation(SupportNetworkError.http(statusCode: 403, backend: nil, data: Data())))
    }

    @Test func partialPackageCannotSubstituteInteriorPageForBookCover() {
        XCTAssertNil(PresetPreviewRepository.previewPageID(requested: nil, canonicalCoverID: nil,
            packageCoverID: "autumn-interior", isComplete: false))
        XCTAssertEqual(PresetPreviewRepository.previewPageID(requested: nil, canonicalCoverID: "jiuzhaigou-cover",
            packageCoverID: "autumn-interior", isComplete: false), "jiuzhaigou-cover")
        XCTAssertEqual(PresetPreviewRepository.previewPageID(requested: nil, canonicalCoverID: nil,
            packageCoverID: "jiuzhaigou-cover", isComplete: true), "jiuzhaigou-cover")
        XCTAssertEqual(PresetPreviewRepository.previewPageID(requested: "interior", canonicalCoverID: "cover",
            packageCoverID: "other", isComplete: false), "interior")
    }

    @Test func paginationExpiryAndRecoveryAreDistinctFromContentTakedown() {
        let issued = Date(timeIntervalSince1970: 1793295766)
        let cursor = "payload:1xMU9G:signature"
        XCTAssertFalse(MaterialPaginationPolicy.expired(cursor, now: issued.addingTimeInterval(423)))
        XCTAssertTrue(MaterialPaginationPolicy.expired(cursor, now: issued.addingTimeInterval(1500)))
        XCTAssertTrue(MaterialPaginationPolicy.expired("invalid", now: issued))
        for code in ["CURSOR_EXPIRED", "SNAPSHOT_MISSING", "CONTENT_UNAVAILABLE"] {
            let data = Data("{\"msg\":{\"code\":\"\(code)\"}}".utf8)
            let error = SupportNetworkError.http(statusCode: 410, backend: nil, data: data)
            XCTAssertEqual(MaterialPaginationPolicy.shouldRestart(error), code != "CONTENT_UNAVAILABLE")
        }
        XCTAssertTrue(MaterialPaginationPolicy.shouldRestart(MaterialPaginationPolicy.Expired()))
        XCTAssertFalse(MaterialPaginationPolicy.shouldRestart(URLError(.timedOut)))
    }

}
