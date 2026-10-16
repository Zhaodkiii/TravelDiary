import Testing
import Foundation
@testable import TravelDiary

@MainActor
struct PresetBrowseTests {
    private actor Transport: SupportNetworkTransport {
        var requests: [URLRequest] = []
        let expiredFirst: Bool
        init(expiredFirst: Bool = false) { self.expiredFirst = expiredFirst }
        func send(_ request: URLRequest) async throws -> SupportTransportResponse {
            requests.append(request)
            try await Task.sleep(for: .milliseconds(20))
            let expired = expiredFirst && requests.count == 1
            let conditional = request.value(forHTTPHeaderField: "If-None-Match") == "\"browse\""
            let data = Data("""
            {"title":"Browse","page_size":{"width":100,"height":150},"cover_page_id":"a",
            "expires_at":\(Date().timeIntervalSince1970 + (expired ? -10 : 240)),
            "pages":[{"id":"a","title":"A","thumbnail_url":"https://example.test/thumb",
            "preview_url":"https://example.test/large"}]}
            """.utf8)
            return SupportTransportResponse(data: conditional ? Data() : data,
                httpResponse: HTTPURLResponse(url: request.url!, statusCode: conditional ? 304 : 200,
                    httpVersion: "HTTP/1.1", headerFields: ["ETag": "\"browse\"",
                        "Cache-Control": "private, max-age=\(expired ? 0 : 240)"])!)
        }
    }

    private let book = RemotePresetBook(id: "book", title: "Browse", series: "series", version: 1,
                                        page_count: 1, cover_url: "https://example.test/thumb")

    @Test func largeImagesStayWithinCurrentAndAdjacentSpreads() {
        let urls = (0..<61).map { URL(string: "https://example.test/large/\($0)")! }
        #expect(PresetPreviewWindow.urls(content: urls, spread: 0) == Array(urls[0...2]))
        #expect(PresetPreviewWindow.urls(content: urls, spread: 26) == Array(urls[49...54]))
        #expect(PresetPreviewWindow.urls(content: urls, spread: 30) == Array(urls[57...60]))
        #expect(PresetPreviewWindow.urls(content: [], spread: 0).isEmpty)
    }

    @Test func concurrentBrowseSharesRequestAndRecreatedManagerUsesETag() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = Transport()
        let baseURL = URL(string: "https://example.test")!
        let auth = AuthTokenProvider(transport: transport, baseURL: baseURL, keychainService: UUID().uuidString)
        await auth.setTokens(AuthTokens(accessToken: "test", refreshToken: "test",
            expiresAt: Date().addingTimeInterval(3600), tokenType: "Bearer"))
        let engine = SupportNetworkEngine(baseURL: baseURL, transport: transport,
            etagInterceptor: ETagHTTPInterceptor(store: FileETagStore(baseDirectory: root.appendingPathComponent("etag"))),
            authProvider: auth)
        let manager = PresetDownloadManager(directory: root.appendingPathComponent("jobs"))
        await manager.waitUntilRestored()
        manager.configure(engine: engine)
        async let first = manager.browse(book, ownerID: "owner")
        async let second = manager.browse(book, ownerID: "owner")
        let values = try await (first, second)
        #expect(values.0.pages.first?.thumbnail_url == values.1.pages.first?.thumbnail_url)
        _ = try await manager.browse(book, ownerID: "owner")
        #expect(await transport.requests.count == 1)
        let reopened = PresetDownloadManager(directory: root.appendingPathComponent("jobs2"))
        await reopened.waitUntilRestored()
        reopened.configure(engine: engine)
        let cached = try await reopened.browse(book, ownerID: "owner")
        #expect(cached.title == "Browse")
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.last?.url?.path == "/api/v1/diary-presets/templates/book/1/browse")
        #expect(requests.last?.value(forHTTPHeaderField: "If-None-Match") == "\"browse\"")
        #expect(requests.last?.value(forHTTPHeaderField: "X-Cache-Max-Age") == "300")
        await auth.clearTokens()
    }

    @Test func expiredSignedURLsAreNotReused() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = Transport(expiredFirst: true)
        let baseURL = URL(string: "https://example.test")!
        let auth = AuthTokenProvider(transport: transport, baseURL: baseURL, keychainService: UUID().uuidString)
        await auth.setTokens(AuthTokens(accessToken: "test", refreshToken: "test",
            expiresAt: Date().addingTimeInterval(3600), tokenType: "Bearer"))
        let manager = PresetDownloadManager(directory: root.appendingPathComponent("jobs"))
        await manager.waitUntilRestored()
        manager.configure(engine: SupportNetworkEngine(baseURL: baseURL, transport: transport,
            etagInterceptor: ETagHTTPInterceptor(store: FileETagStore(baseDirectory: root.appendingPathComponent("etag"))),
            authProvider: auth))
        let old = try await manager.browse(book, ownerID: "owner")
        #expect(!old.isFresh)
        let refreshed = try await manager.browse(book, ownerID: "owner")
        #expect(refreshed.isFresh)
        #expect(await transport.requests.count == 2)
        #expect(await transport.requests.last?.value(forHTTPHeaderField: "If-None-Match") == nil)
        await auth.clearTokens()
    }
}
