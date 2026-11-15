import Foundation
import Testing
@testable import TravelDiary

@MainActor
struct PhoneOTPDeviceCredentialRecoveryTests {
    private func failure(code: Int = 40162, message: String = "device_credential_not_registered", status: Int = 401) -> SupportNetworkError {
        .http(statusCode: status, backend: BackendError(code: code, msg: message, data: nil), data: Data())
    }

    @Test func unregisteredCredentialRetriesOnceWithoutSecret() async throws {
        var secrets: [String] = []
        let result = try await PhoneOTPDeviceCredentialRecovery.verify(deviceSecret: "saved", protectsGuestAccount: false) { secret in
            secrets.append(secret)
            if !secret.isEmpty { throw failure() }
            return 42
        }
        #expect(result == 42)
        #expect(secrets == ["saved", ""])
    }

    @Test func successfulGuestUpgradeKeepsCredential() async throws {
        var secrets: [String] = []
        let result = try await PhoneOTPDeviceCredentialRecovery.verify(deviceSecret: "saved", protectsGuestAccount: true) { secret in
            secrets.append(secret)
            return 17
        }
        #expect(result == 17)
        #expect(secrets == ["saved"])
    }

    @Test func guestUpgradeAndOtherFailuresNeverDowngrade() async {
        let cases: [(Bool, String, SupportNetworkError)] = [
            (true, "saved", failure()),
            (false, "", failure()),
            (false, "saved", failure(code: 40161, message: "device_credential_invalid")),
            (false, "saved", failure(code: 42361, message: "device_credential_locked", status: 423)),
            (false, "saved", failure(message: "apple identity not linked to current user")),
            (false, "saved", .timeout),
            (false, "saved", .cancelled)
        ]
        for (protectsGuest, secret, error) in cases {
            var attempts = 0
            do {
                let _: Int = try await PhoneOTPDeviceCredentialRecovery.verify(deviceSecret: secret, protectsGuestAccount: protectsGuest) { _ in
                    attempts += 1
                    throw error
                }
                Issue.record("Expected login failure")
            } catch {}
            #expect(attempts == 1)
        }
    }

    @Test func failedRetryIsPropagatedWithoutLoop() async {
        var attempts = 0
        do {
            let _: Int = try await PhoneOTPDeviceCredentialRecovery.verify(deviceSecret: "saved", protectsGuestAccount: false) { _ in
                attempts += 1
                throw failure()
            }
            Issue.record("Expected login failure")
        } catch {}
        #expect(attempts == 2)
    }

    @Test func cancelledTaskDoesNotStartRecoveryRequest() async {
        let task = Task { @MainActor in
            var attempts = 0
            do {
                let _: Int = try await PhoneOTPDeviceCredentialRecovery.verify(deviceSecret: "saved", protectsGuestAccount: false) { _ in
                    attempts += 1
                    withUnsafeCurrentTask { $0?.cancel() }
                    throw failure()
                }
                Issue.record("Expected cancellation")
            } catch {
                #expect(error is CancellationError)
            }
            #expect(attempts == 1)
        }
        await task.value
    }

    @Test func unregisteredCredentialHasUserFacingMessage() {
        let message = AuthUserFacingErrorMapper.message(for: failure(), scenario: .phoneOTPLogin)
        #expect(message == L10n.text("auth.device.credential_not_registered"))
        #expect(!message.contains("device_credential_not_registered"))
    }
}
