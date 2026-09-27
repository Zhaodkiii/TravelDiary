import XCTest
@testable import SupplyChainClient

final class SupportNetworkEngineAuthTests: XCTestCase {
    private struct StubHTTPResponse {
        var statusCode: Int
        var headers: [String: String]
        var body: Data
    }

    private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var requestHandler: ((URLRequest) -> StubHTTPResponse)?
        private static let requestCountLock = NSLock()
        nonisolated(unsafe) static var requestCount: Int = 0
        nonisolated(unsafe) static var refreshCount: Int = 0

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.requestCountLock.lock()
            Self.requestCount += 1
            if request.url?.path.contains("/auth/token/refresh") == true {
                Self.refreshCount += 1
            }
            Self.requestCountLock.unlock()

            guard let handler = Self.requestHandler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }

            let stub = handler(request)
            let url = request.url ?? URL(string: "http://localhost")!
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
            )!

            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        static func reset() {
            requestHandler = nil
            requestCountLock.lock()
            requestCount = 0
            refreshCount = 0
            requestCountLock.unlock()
        }
    }

    private func makeFakeJWT(expDate: Date, sub: String = "user") -> String {
        func base64URLEncode(_ data: Data) -> String {
            var str = data.base64EncodedString()
            str = str.replacingOccurrences(of: "+", with: "-")
            str = str.replacingOccurrences(of: "/", with: "_")
            str = str.replacingOccurrences(of: "=", with: "")
            return str
        }

        let header: [String: String] = ["alg": "none", "typ": "JWT"]
        let payload: [String: Any] = [
            "exp": Int(expDate.timeIntervalSince1970),
            "sub": sub
        ]
        let headerData = try! JSONSerialization.data(withJSONObject: header, options: [])
        let payloadData = try! JSONSerialization.data(withJSONObject: payload, options: [])
        return "\(base64URLEncode(headerData)).\(base64URLEncode(payloadData)).sig"
    }

    private func makeEngine() -> SupportNetworkEngine {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: config)
        let transport = URLSessionNetworkTransport(session: session, logger: ConsoleLogger())
        return SupportNetworkEngine(
            baseURL: URL(string: "http://localhost")!,
            transport: transport,
            logger: ConsoleLogger()
        )
    }

    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    func testRefresh401PostsAuthInvalidationNotification() async throws {
        URLProtocolStub.reset()
        let accessJWT = makeFakeJWT(expDate: Date().addingTimeInterval(3600))
        let refreshJWT = makeFakeJWT(expDate: Date().addingTimeInterval(86400), sub: "refresh")

        URLProtocolStub.requestHandler = { req in
            let path = req.url?.path ?? ""
            if path.contains("/auth/token/refresh") {
                let body = Data(#"{"code":40102,"msg":"token_not_valid","data":{"request_id":"test"}}"#.utf8)
                return StubHTTPResponse(statusCode: 401, headers: ["Content-Type": "application/json"], body: body)
            }
            let body = Data(#"{"code":40102,"msg":"token_not_valid","data":{"request_id":"test"}}"#.utf8)
            return StubHTTPResponse(statusCode: 401, headers: ["Content-Type": "application/json"], body: body)
        }

        let engine = makeEngine()
        await engine.tokenStore().setTokens(
            AuthTokens(
                accessToken: accessJWT,
                refreshToken: refreshJWT,
                expiresAt: Date().addingTimeInterval(3600),
                tokenType: "Bearer"
            )
        )

        let invalidation = expectation(forNotification: SupportAuthSessionInvalidation.notificationName, object: nil) { notification in
            (notification.userInfo?["source"] as? String)?.contains("refresh") == true
                || notification.userInfo?["message"] as? String == "token_not_valid"
        }

        do {
            let _: EmptyResponse = try await engine.send(
                .init(method: .get, path: "/api/v1/test/protected/", strategy: .init(requiresAuth: true))
            )
            XCTFail("Expected refresh failure")
        } catch SupportNetworkError.refreshFailed {
            // Expected.
        } catch {
            XCTFail("Expected SupportNetworkError.refreshFailed, got \(error)")
        }

        await fulfillment(of: [invalidation], timeout: 2.0)
        let tokens = await engine.tokenStore().currentTokens()
        XCTAssertNil(tokens)
    }

    func testConcurrent401TriggersSingleRefresh() async throws {
        URLProtocolStub.reset()
        let accessJWT = makeFakeJWT(expDate: Date().addingTimeInterval(3600))
        let refreshJWT = makeFakeJWT(expDate: Date().addingTimeInterval(86400), sub: "refresh")
        let lock = NSLock()
        var protectedHits = 0

        URLProtocolStub.requestHandler = { req in
            let path = req.url?.path ?? ""
            if path.contains("/auth/token/refresh") {
                // Temporary failure: keep tokens.
                return StubHTTPResponse(statusCode: 500, headers: [:], body: Data("oops".utf8))
            }
            lock.lock()
            protectedHits += 1
            lock.unlock()
            let body = Data(#"{"code":40102,"msg":"token_not_valid","data":{}}"#.utf8)
            return StubHTTPResponse(statusCode: 401, headers: ["Content-Type": "application/json"], body: body)
        }

        let engine = makeEngine()
        await engine.tokenStore().setTokens(
            AuthTokens(
                accessToken: accessJWT,
                refreshToken: refreshJWT,
                expiresAt: Date().addingTimeInterval(3600),
                tokenType: "Bearer"
            )
        )

        async let first: Void = {
            do {
                let _: EmptyResponse = try await engine.send(
                    .init(method: .get, path: "/api/v1/test/a/", strategy: .init(requiresAuth: true))
                )
            } catch {
                // expected
            }
        }()
        async let second: Void = {
            do {
                let _: EmptyResponse = try await engine.send(
                    .init(method: .get, path: "/api/v1/test/b/", strategy: .init(requiresAuth: true))
                )
            } catch {
                // expected
            }
        }()
        _ = await (first, second)

        XCTAssertEqual(URLProtocolStub.refreshCount, 1)
        let tokens = await engine.tokenStore().currentTokens()
        XCTAssertNotNil(tokens)
    }

    func testRefreshTemporaryFailureDoesNotClearTokens() async throws {
        URLProtocolStub.reset()
        let accessJWT = makeFakeJWT(expDate: Date().addingTimeInterval(3600))
        let refreshJWT = makeFakeJWT(expDate: Date().addingTimeInterval(86400), sub: "refresh")

        URLProtocolStub.requestHandler = { req in
            let path = req.url?.path ?? ""
            if path.contains("/auth/token/refresh") {
                return StubHTTPResponse(statusCode: 500, headers: [:], body: Data("<html>bad gateway</html>".utf8))
            }
            let body = Data(#"{"code":40102,"msg":"token_not_valid","data":{}}"#.utf8)
            return StubHTTPResponse(statusCode: 401, headers: ["Content-Type": "application/json"], body: body)
        }

        let engine = makeEngine()
        await engine.tokenStore().setTokens(
            AuthTokens(
                accessToken: accessJWT,
                refreshToken: refreshJWT,
                expiresAt: Date().addingTimeInterval(3600),
                tokenType: "Bearer"
            )
        )

        do {
            let _: EmptyResponse = try await engine.send(
                .init(method: .get, path: "/api/v1/test/protected/", strategy: .init(requiresAuth: true))
            )
            XCTFail("Expected temporary refresh failure")
        } catch SupportNetworkError.refreshTemporarilyUnavailable {
            // Expected.
        } catch {
            XCTFail("Expected refreshTemporarilyUnavailable, got \(error)")
        }

        let tokens = await engine.tokenStore().currentTokens()
        XCTAssertNotNil(tokens)
        XCTAssertEqual(tokens?.refreshToken, refreshJWT)
    }
}

@MainActor
final class DeviceRegistrationBootstrapGateTests: XCTestCase {
    func testAuthInvalidatedOutcomeStopsBootstrap() {
        let outcome = DeviceRegistrationRequestOutcome.authSessionInvalidated
        XCTAssertFalse(outcome.allowsAccountBootstrap)
    }

    func testRetryableFailureStopsBootstrapWithoutLogoutSemantics() {
        let outcome = DeviceRegistrationRequestOutcome.failedRetryable
        XCTAssertFalse(outcome.allowsAccountBootstrap)
    }

    func testSubmittedAllowsBootstrap() {
        XCTAssertTrue(DeviceRegistrationRequestOutcome.submitted.allowsAccountBootstrap)
        XCTAssertTrue(DeviceRegistrationRequestOutcome.skippedSameLaunchSubmission.allowsAccountBootstrap)
    }
}
