import XCTest
@testable import TravelDiary

final class OSSCredentialsBucketNameDecodeTests: XCTestCase {
    /// 与生产路径一致：全局 `convertFromSnakeCase`。
    private let decoder = JSONDecoder.supportDefault

    func testOSSCredentialsResponse_decodesSnakeCaseBucketNameViaGlobalStrategy() throws {
        let json = """
        {
          "access_key_id": "STS.xxx",
          "access_key_secret": "secret",
          "security_token": "token",
          "expiration": 1783616825,
          "bucket_name": "zhaodkdream",
          "region": "cn-shanghai",
          "endpoint": "https://oss-cn-beijing.aliyuncs.com"
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(OSSCredentialsResponse.self, from: json)
        let config = try XCTUnwrap(AliyunOSSRuntimeConfig(response: response))

        XCTAssertEqual(response.bucket, "zhaodkdream")
        XCTAssertEqual(config.bucketName, "zhaodkdream")
        XCTAssertEqual(config.region, "cn-shanghai")
        XCTAssertEqual(config.endpointURL, "https://oss-cn-beijing.aliyuncs.com")
    }

    func testOSSCredentialsResponse_decodesCamelCaseBucketName() throws {
        let json = """
        {
          "accessKeyId": "STS.xxx",
          "accessKeySecret": "secret",
          "securityToken": "token",
          "expiration": "1783616825",
          "bucketName": "zhaodkdream",
          "region": "cn-shanghai",
          "endpoint": "https://oss-cn-beijing.aliyuncs.com"
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(OSSCredentialsResponse.self, from: json)
        let config = try XCTUnwrap(AliyunOSSRuntimeConfig(response: response))

        XCTAssertEqual(response.bucket, "zhaodkdream")
        XCTAssertEqual(config.bucketName, "zhaodkdream")
    }

    func testOSSCredentialsResponse_decodesLegacyBucket() throws {
        let json = """
        {
          "accessKeyId": "STS.xxx",
          "accessKeySecret": "secret",
          "securityToken": "token",
          "expiration": "1783616825",
          "bucket": "zhaodkdream",
          "region": "cn-shanghai",
          "endpoint": "https://oss-cn-beijing.aliyuncs.com"
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(OSSCredentialsResponse.self, from: json)
        let config = try XCTUnwrap(AliyunOSSRuntimeConfig(response: response))

        XCTAssertEqual(response.bucket, "zhaodkdream")
        XCTAssertEqual(config.bucketName, "zhaodkdream")
    }

    func testOCRSTSCredentialsResponse_decodesSnakeCaseBucketNameViaGlobalStrategy() throws {
        let json = """
        {
          "access_key_id": "STS.xxx",
          "access_key_secret": "secret",
          "security_token": "token",
          "expiration": 1783616825,
          "bucket_name": "zhaodkdream",
          "region": "cn-shanghai",
          "endpoint": "https://oss-cn-beijing.aliyuncs.com"
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(OCRSTSCredentialsResponse.self, from: json)
        let config = try XCTUnwrap(AliyunOSSRuntimeConfig(response: response))

        XCTAssertEqual(response.bucketName, "zhaodkdream")
        XCTAssertEqual(config.bucketName, "zhaodkdream")
    }

    func testUserSession_decodesSnakeCaseAndRoundTripsWithoutTokens() throws {
        let json = """
        {
          "account_id": 810,
          "user_id": 42,
          "access_token": "access",
          "refresh_token": "refresh",
          "token_type": "Bearer",
          "is_pro": true,
          "display_name": "Hua",
          "email": "a@b.com",
          "sign_in_method": "apple"
        }
        """.data(using: .utf8)!

        let session = try decoder.decode(UserSession.self, from: json)
        XCTAssertEqual(session.accountID, 810)
        XCTAssertEqual(session.userID, 42)
        XCTAssertEqual(session.displayName, "Hua")
        XCTAssertEqual(session.isPro, true)
        XCTAssertEqual(session.signInMethod, "apple")

        let encoded = try JSONEncoder.supportDefault.encode(session)
        let roundTrip = try decoder.decode(UserSession.self, from: encoded)
        XCTAssertEqual(roundTrip, session)

        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        XCTAssertEqual(object?["account_id"] as? Int, 810)
        XCTAssertNil(object?["access_token"])
        XCTAssertNil(object?["refresh_token"])
        XCTAssertNil(object?["token_type"])
    }

    func testIncompleteFieldDiagnostics_reportsMissingBucketWithoutSecrets() throws {
        let json = """
        {
          "access_key_id": "STS.xxx",
          "access_key_secret": "super-secret",
          "security_token": "super-token",
          "expiration": 1783616825,
          "region": "cn-shanghai",
          "endpoint": "https://oss-cn-beijing.aliyuncs.com"
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(OSSCredentialsResponse.self, from: json)
        XCTAssertNil(AliyunOSSRuntimeConfig(response: response))

        let diagnostics = AliyunOSSRuntimeConfig.incompleteFieldDiagnostics(for: response)
        XCTAssertTrue(diagnostics.contains("missing=[bucket]"))
        XCTAssertTrue(diagnostics.contains("hasAccessKey=true"))
        XCTAssertTrue(diagnostics.contains("hasEndpoint=true"))
        XCTAssertTrue(diagnostics.contains("hasRegion=true"))
        XCTAssertFalse(diagnostics.contains("super-secret"))
        XCTAssertFalse(diagnostics.contains("super-token"))
    }
}
