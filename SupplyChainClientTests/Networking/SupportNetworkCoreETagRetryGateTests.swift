import CryptoKit
import XCTest
@testable import SupplyChainClient

final class SupportNetworkCoreETagRetryGateTests: XCTestCase {

    // MARK: - ETag store

    func testFileETagStoreWriteAndRead() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SupportETagTests-\(UUID().uuidString)", isDirectory: true)
        let store = FileETagStore(baseDirectory: dir)
        let key = "test-key-1"
        let body = Data(#"{"ok":true}"#.utf8)
        try store.store(etag: "\"abc\"", body: body, forKey: key, expirationDate: Date().addingTimeInterval(60))

        XCTAssertEqual(store.etag(forKey: key), "\"abc\"")
        XCTAssertEqual(store.cachedBody(forKey: key), body)
        XCTAssertEqual(store.record(forKey: key)?.etag, "\"abc\"")
        XCTAssertFalse(store.record(forKey: key)?.isExpired() ?? true)
    }

    func testETagCacheKeyIncludesAuthorizationFingerprint() {
        let store = InMemoryETagStore()
        let interceptor = ETagHTTPInterceptor(store: store)
        var requestA = URLRequest(url: URL(string: "https://example.com/api/v1/items")!)
        requestA.setValue("Bearer token-a", forHTTPHeaderField: "Authorization")
        var requestB = URLRequest(url: URL(string: "https://example.com/api/v1/items")!)
        requestB.setValue("Bearer token-b", forHTTPHeaderField: "Authorization")

        let keyA = interceptor.cacheKey(for: requestA)
        let keyB = interceptor.cacheKey(for: requestB)
        XCTAssertNotEqual(keyA, keyB)
        XCTAssertEqual(keyA.count, 64)
    }

    func testETagInterceptorMerges304WithCachedBody() async throws {
        let store = InMemoryETagStore()
        let interceptor = ETagHTTPInterceptor(store: store)
        let url = URL(string: "https://example.com/api/v1/config")!
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("Bearer user-1", forHTTPHeaderField: "Authorization")
        let key = interceptor.cacheKey(for: urlRequest)
        let cached = Data(#"{"code":0,"msg":"ok","data":{"v":1}}"#.utf8)
        try store.store(etag: "\"etag-1\"", body: cached, forKey: key)

        let http304 = HTTPURLResponse(url: url, statusCode: 304, httpVersion: "HTTP/1.1", headerFields: nil)!
        let transport = SupportTransportResponse(data: Data(), httpResponse: http304)
        let networkRequest = SupportNetworkRequest(
            method: .get,
            path: "/api/v1/config",
            strategy: .init(requiresAuth: true, allowETag: true, etagTTL: 120)
        )
        let merged = interceptor.intercept(
            transportResponse: transport,
            cacheKey: key,
            request: networkRequest
        )
        XCTAssertTrue(merged.didMerge304)
        XCTAssertEqual(merged.data, cached)
        XCTAssertEqual(merged.httpResponse.statusCode, 304)
    }

    func testETagInterceptorDoesNotMerge304WithoutBody() {
        let store = InMemoryETagStore()
        let interceptor = ETagHTTPInterceptor(store: store)
        let url = URL(string: "https://example.com/api/v1/config")!
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("Bearer user-1", forHTTPHeaderField: "Authorization")
        let key = interceptor.cacheKey(for: urlRequest)

        let http304 = HTTPURLResponse(url: url, statusCode: 304, httpVersion: "HTTP/1.1", headerFields: nil)!
        let transport = SupportTransportResponse(data: Data(), httpResponse: http304)
        let networkRequest = SupportNetworkRequest(
            method: .get,
            path: "/api/v1/config",
            strategy: .init(allowETag: true)
        )
        let response = interceptor.intercept(
            transportResponse: transport,
            cacheKey: key,
            request: networkRequest
        )
        XCTAssertFalse(response.didMerge304)
        XCTAssertEqual(response.httpResponse.statusCode, 304)
        XCTAssertTrue(response.data.isEmpty)
    }

    func testETagRecordExpiresWithTTL() throws {
        let store = InMemoryETagStore()
        let key = "expired"
        try store.store(
            etag: "\"x\"",
            body: Data("{}".utf8),
            forKey: key,
            expirationDate: Date().addingTimeInterval(-1)
        )
        XCTAssertTrue(store.record(forKey: key)?.isExpired() ?? false)
    }

    // MARK: - Retry

    func testRetryAfterParserDeltaSeconds() {
        XCTAssertEqual(RetryAfterParser.parseSeconds(from: "3"), 3)
        XCTAssertEqual(RetryAfterParser.parseSeconds(from: "0"), 0)
        XCTAssertNil(RetryAfterParser.parseSeconds(from: nil))
        XCTAssertNil(RetryAfterParser.parseSeconds(from: "not-a-date"))
    }

    func testRetryPolicyGETDefaultCanRetryStatus() {
        let policy = RetryPolicy()
        XCTAssertTrue(policy.shouldRetry(statusCode: 503, error: nil))
        XCTAssertTrue(policy.shouldRetry(statusCode: 429, error: nil))
        XCTAssertFalse(policy.shouldRetry(statusCode: 400, error: nil))
        XCTAssertTrue(policy.shouldRetry(statusCode: nil, error: URLError(.timedOut)))
    }

    func testNetworkStrategyNonGETDefaultNotIdempotent() {
        let post = NetworkStrategy(requiresAuth: true)
        XCTAssertFalse(post.isIdempotent)
        XCTAssertFalse(post.allowETag)
        let getIdempotent = NetworkStrategy(requiresAuth: true, allowETag: true, isIdempotent: true)
        XCTAssertTrue(getIdempotent.isIdempotent)
        XCTAssertTrue(getIdempotent.allowETag)
    }

    // MARK: - Serial gate

    func testSerialRequestGateSameKeyRunsSerially() async throws {
        let gate = SerialRequestGate()
        let lock = NSLock()
        var concurrent = 0
        var maxConcurrent = 0
        var finished: [Int] = []

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<5 {
                group.addTask {
                    _ = try? await gate.enqueue(serialKey: "same", priority: .normal) {
                        lock.lock()
                        concurrent += 1
                        maxConcurrent = max(maxConcurrent, concurrent)
                        lock.unlock()
                        try await Task.sleep(nanoseconds: 30_000_000)
                        lock.lock()
                        concurrent -= 1
                        finished.append(index)
                        lock.unlock()
                        return index
                    }
                }
            }
        }

        XCTAssertEqual(maxConcurrent, 1)
        XCTAssertEqual(finished.count, 5)
    }
}

// MARK: - In-memory ETag store for tests

private final class InMemoryETagStore: ETagStore, @unchecked Sendable {
    private var records: [String: ETagCacheRecord] = [:]
    private var bodies: [String: Data] = [:]
    private let lock = NSLock()

    func record(forKey key: String) -> ETagCacheRecord? {
        lock.lock(); defer { lock.unlock() }
        return records[key]
    }

    func cachedBody(forKey key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return bodies[key]
    }

    func store(record: ETagCacheRecord, body: Data, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        records[key] = record
        bodies[key] = body
    }

    func removeCache(forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        records[key] = nil
        bodies[key] = nil
    }
}
