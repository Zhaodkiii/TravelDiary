import XCTest
@testable import SupplyChainClient

final class SupportAuthSessionInvalidationTests: XCTestCase {
    func test403DoesNotInvalidate() {
        XCTAssertFalse(
            SupportAuthSessionInvalidation.shouldInvalidate(
                statusCode: 403,
                backendCode: -1,
                message: "permission_denied"
            )
        )
    }

    func test401Invalidates() {
        XCTAssertTrue(
            SupportAuthSessionInvalidation.shouldInvalidate(
                statusCode: 401,
                backendCode: nil,
                message: ""
            )
        )
    }

    func testTokenNotValidMessageInvalidates() {
        XCTAssertTrue(
            SupportAuthSessionInvalidation.shouldInvalidate(
                statusCode: 200,
                backendCode: nil,
                message: "token_not_valid"
            )
        )
    }

    func testDeviceSessionReplacedMessageInvalidates() {
        XCTAssertTrue(
            SupportAuthSessionInvalidation.shouldInvalidate(
                statusCode: 200,
                backendCode: 40105,
                message: "device_session_replaced"
            )
        )
    }
}
