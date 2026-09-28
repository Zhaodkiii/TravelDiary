import XCTest
@testable import TravelDiary

final class SupportAuthSessionPersistenceTests: XCTestCase {
    private struct StubHTTPResponse {
        var statusCode: Int
        var headers: [String: String] = [:]
        var body: Data
    }

    private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var requestHandler: ((URLRequest) -> StubHTTPResponse)?
        private static let requestCountLock = NSLock()
        nonisolated(unsafe) static var refreshCount: Int = 0
        nonisolated(unsafe) static var sessionCount: Int = 0

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.requestCountLock.lock()
            if request.url?.path.contains("/auth/token/refresh") == true {
                Self.refreshCount += 1
            }
            if request.url?.path.contains("/auth/session") == true {
                Self.sessionCount += 1
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
            refreshCount = 0
            sessionCount = 0
            requestCountLock.unlock()
        }
    }

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "support.auth.session.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        URLProtocolStub.reset()
        clearAuthKeychain()
    }

    override func tearDown() {
        URLProtocolStub.reset()
        clearAuthKeychain()
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        super.tearDown()
    }

    func testRestoreSession_returnsNilWhenSnapshotExistsButKeychainMissing() async {
        let engine = makeEngine()
        let tokenProvider = engine.tokenStore()
        let snapshotStore = SessionSnapshotStore(
            defaults: defaults,
            logger: ConsoleLogger()
        )
        await snapshotStore.save(
            UserSession(accountID: 11, userID: 11, isPro: false, displayName: "A", email: "a@b.com", signInMethod: "apple", signedInAt: Date())
        )

        let repository = DefaultAuthRepository(
            backend: SupportBackend(engine: engine),
            snapshotStore: snapshotStore,
            sessionStore: await makeSessionStore(snapshotStore: snapshotStore, tokenProvider: tokenProvider),
            logger: ConsoleLogger()
        )
        let restored = await repository.restoreSession()
        XCTAssertNil(restored)
        let loadedAfterRestore = await snapshotStore.load()
        let tokensAfterRestore = await tokenProvider.currentTokens()
        XCTAssertNil(loadedAfterRestore)
        XCTAssertNil(tokensAfterRestore)
    }

    func testRestoreSession_keepsCachedSessionOnTemporaryRefreshFailure() async throws {
        let nearExpiryAccess = makeFakeJWT(expDate: Date().addingTimeInterval(10))
        let refresh = makeFakeJWT(expDate: Date().addingTimeInterval(86400), sub: "refresh")
        let engine = makeEngine()
        let tokenProvider = engine.tokenStore()
        await tokenProvider.setTokens(
            AuthTokens(accessToken: nearExpiryAccess, refreshToken: refresh, tokenType: "Bearer")
        )

        URLProtocolStub.requestHandler = { req in
            if req.url?.path.contains("/auth/token/refresh") == true {
                return StubHTTPResponse(
                    statusCode: 500,
                    body: Data(#"{"code":500,"msg":"temporary"}"#.utf8)
                )
            }
            return StubHTTPResponse(statusCode: 500, body: Data())
        }

        let snapshotStore = SessionSnapshotStore(
            defaults: defaults,
            logger: ConsoleLogger()
        )
        let cached = UserSession(
            accountID: 99,
            userID: 99,
            isPro: true,
            displayName: "Cached",
            email: "c@d.com",
            signInMethod: "apple",
            signedInAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        await snapshotStore.save(cached)

        let repository = DefaultAuthRepository(
            backend: SupportBackend(engine: engine),
            snapshotStore: snapshotStore,
            sessionStore: await makeSessionStore(snapshotStore: snapshotStore, tokenProvider: tokenProvider),
            logger: ConsoleLogger()
        )
        let restored = await repository.restoreSession()
        XCTAssertEqual(restored, cached)
        let tokensAfterRestore = await tokenProvider.currentTokens()
        let loadedAfterRestore = await snapshotStore.load()
        XCTAssertNotNil(tokensAfterRestore)
        XCTAssertEqual(loadedAfterRestore?.accountID, 99)
        XCTAssertGreaterThan(URLProtocolStub.refreshCount, 0)
    }

    func testRestoreSession_clearsStateOnDefinitiveRefreshFailure() async throws {
        let nearExpiryAccess = makeFakeJWT(expDate: Date().addingTimeInterval(10))
        let refresh = makeFakeJWT(expDate: Date().addingTimeInterval(86400), sub: "refresh")
        let engine = makeEngine()
        let tokenProvider = engine.tokenStore()
        await tokenProvider.setTokens(
            AuthTokens(accessToken: nearExpiryAccess, refreshToken: refresh, tokenType: "Bearer")
        )

        let expectation = expectation(description: "auth invalidation")
        let observer = NotificationCenter.default.addObserver(
            forName: SupportAuthSessionInvalidation.notificationName,
            object: nil,
            queue: nil
        ) { _ in
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        URLProtocolStub.requestHandler = { req in
            if req.url?.path.contains("/auth/token/refresh") == true {
                return StubHTTPResponse(
                    statusCode: 401,
                    body: Data(#"{"code":401,"msg":"token_not_valid"}"#.utf8)
                )
            }
            return StubHTTPResponse(statusCode: 500, body: Data())
        }

        let snapshotStore = SessionSnapshotStore(
            defaults: defaults,
            logger: ConsoleLogger()
        )
        await snapshotStore.save(
            UserSession(accountID: 55, userID: 55, isPro: false, displayName: "X", email: nil, signInMethod: "phone", signedInAt: Date())
        )

        let repository = DefaultAuthRepository(
            backend: SupportBackend(engine: engine),
            snapshotStore: snapshotStore,
            sessionStore: await makeSessionStore(snapshotStore: snapshotStore, tokenProvider: tokenProvider),
            logger: ConsoleLogger()
        )
        let restored = await repository.restoreSession()
        XCTAssertNil(restored)
        let loadedAfterRestore = await snapshotStore.load()
        let tokensAfterRestore = await tokenProvider.currentTokens()
        XCTAssertNil(loadedAfterRestore)
        XCTAssertNil(tokensAfterRestore)
        await fulfillment(of: [expectation], timeout: 2)
    }

    func testRestoreSession_fetchesCurrentSessionAndMergesWhenTokenValid() async throws {
        let access = makeFakeJWT(expDate: Date().addingTimeInterval(3600))
        let refresh = makeFakeJWT(expDate: Date().addingTimeInterval(86400), sub: "refresh")
        let engine = makeEngine()
        let tokenProvider = engine.tokenStore()
        await tokenProvider.setTokens(
            AuthTokens(accessToken: access, refreshToken: refresh, tokenType: "Bearer")
        )

        URLProtocolStub.requestHandler = { req in
            if req.url?.path.contains("/auth/session") == true {
                let body = Data("""
                {"code":0,"msg":"ok","data":{"user_id":88,"email":"new@e.com","display_name":"Remote","is_pro":true,"sign_in_method":"apple"}}
                """.utf8)
                return StubHTTPResponse(statusCode: 200, body: body)
            }
            return StubHTTPResponse(statusCode: 500, body: Data())
        }

        let snapshotStore = SessionSnapshotStore(
            defaults: defaults,
            logger: ConsoleLogger()
        )
        let cached = UserSession(
            accountID: 88,
            userID: 88,
            isPro: false,
            displayName: "Local",
            email: "old@e.com",
            signInMethod: "apple",
            signedInAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        await snapshotStore.save(cached)

        let repository = DefaultAuthRepository(
            backend: SupportBackend(engine: engine),
            snapshotStore: snapshotStore,
            sessionStore: await makeSessionStore(snapshotStore: snapshotStore, tokenProvider: tokenProvider),
            logger: ConsoleLogger()
        )
        let maybeRestored = await repository.restoreSession()
        let restored = try XCTUnwrap(maybeRestored)
        XCTAssertEqual(restored.accountID, 88)
        XCTAssertEqual(restored.isPro, true)
        XCTAssertEqual(restored.displayName, "Remote")
        XCTAssertEqual(restored.email, "new@e.com")
        XCTAssertEqual(restored.signedInAt, cached.signedInAt)
        XCTAssertEqual(URLProtocolStub.sessionCount, 1)
    }

    func testLoginResult_buildsTokensAndProfileWithoutEmbeddingTokensInSession() throws {
        let json = """
        {
          "user_id": 12,
          "access_token": "\(makeFakeJWT(expDate: Date().addingTimeInterval(3600)))",
          "refresh_token": "refresh-token",
          "expires_in": 7200,
          "token_type": "Bearer"
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder.supportDefault.decode(SupportAuthAPI.LoginResult.self, from: json)
        let tokens = AuthTokens(
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(result.expiresIn)),
            tokenType: result.tokenType
        )
        XCTAssertEqual(tokens.refreshToken, "refresh-token")
        XCTAssertEqual(tokens.tokenType, "Bearer")
        XCTAssertGreaterThan(tokens.expiresAt.timeIntervalSinceNow, 7000)

        let session = UserSession(
            accountID: result.userId,
            userID: result.userId,
            isPro: false,
            displayName: "User",
            email: "u@e.com",
            signInMethod: "password",
            signedInAt: Date(),
            isNewUser: false
        )
        let encoded = try JSONEncoder.supportDefault.encode(session)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["access_token"])
        XCTAssertNil(object["refresh_token"])
        XCTAssertEqual(object["account_id"] as? Int, 12)
        XCTAssertEqual(object["user_id"] as? Int, 12)
    }

    func testSnapshotSave_neverPersistsTokenFields() async throws {
        let snapshotStore = SessionSnapshotStore(defaults: defaults, logger: ConsoleLogger())
        await snapshotStore.save(
            UserSession(
                accountID: 1,
                userID: 2,
                isPro: false,
                displayName: "N",
                email: "e@e.com",
                signInMethod: "apple",
                signedInAt: Date()
            )
        )
        let data = try XCTUnwrap(defaults.data(forKey: "support.session.snapshot.v1"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["access_token"])
        XCTAssertNil(object["refresh_token"])
        XCTAssertNil(object["token_type"])
        XCTAssertEqual(object["account_id"] as? Int, 1)
    }

    @MainActor
    func testLogout_clearsLocalStateAndSetsSignedOutEvenWhenServerLogoutFails() async throws {
        let engine = makeEngine()
        let tokenProvider = engine.tokenStore()
        await tokenProvider.setTokens(
            AuthTokens(
                accessToken: makeFakeJWT(expDate: Date().addingTimeInterval(3600)),
                refreshToken: makeFakeJWT(expDate: Date().addingTimeInterval(86400), sub: "refresh"),
                tokenType: "Bearer"
            )
        )

        URLProtocolStub.requestHandler = { _ in
            StubHTTPResponse(statusCode: 500, body: Data(#"{"code":500,"msg":"logout failed"}"#.utf8))
        }

        let snapshotStore = SessionSnapshotStore(
            defaults: defaults,
            logger: ConsoleLogger()
        )
        let session = UserSession(
            accountID: 77,
            userID: 77,
            isPro: false,
            displayName: "Logout",
            email: "l@e.com",
            signInMethod: "apple",
            signedInAt: Date()
        )
        await snapshotStore.save(session)

        let sessionStore = await makeSessionStore(snapshotStore: snapshotStore, tokenProvider: tokenProvider)
        await MainActor.run {
            sessionStore.setAuthenticated(session)
        }
        let stateBeforeLogout = await MainActor.run { sessionStore.state }
        XCTAssertEqual(stateBeforeLogout, .signedIn(session))

        let repository = DefaultAuthRepository(
            backend: SupportBackend(engine: engine),
            snapshotStore: snapshotStore,
            sessionStore: sessionStore,
            logger: ConsoleLogger()
        )
        try await repository.logout()

        let stateAfterLogout = await MainActor.run { sessionStore.state }
        XCTAssertEqual(stateAfterLogout, .signedOut)
        let loaded = await snapshotStore.load()
        let tokens = await tokenProvider.currentTokens()
        XCTAssertNil(loaded)
        XCTAssertNil(tokens)
    }

    // MARK: - Helpers

    private func makeSessionStore(
        snapshotStore: SessionSnapshotStore,
        tokenProvider: AuthTokenProvider
    ) async -> AppSessionStore {
        await MainActor.run {
            AppSessionStore(
                snapshotStore: snapshotStore,
                tokenProvider: tokenProvider,
                logger: ConsoleLogger()
            )
        }
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

    private func clearAuthKeychain() {
        SupportKeychain.delete(account: "accessToken")
        SupportKeychain.delete(account: "refreshToken")
        SupportKeychain.delete(account: "tokenType")
        SupportKeychain.delete(account: "expiresAt")
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
}
