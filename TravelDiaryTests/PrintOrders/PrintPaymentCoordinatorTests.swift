import Foundation
import Testing
@testable import TravelDiary

@MainActor
private final class PaymentClientStub: PrintPaymentClient {
    var order: PrintOrder
    var refreshCount = 0
    var requests: [(String, UUID)] = []
    var launches = 0
    var attemptID = "attempt-1"
    var expiresAt = "2099-01-01T00:00:00Z"
    var createError: Error?
    var onRefresh: (() async throws -> PrintOrder)?
    var onCreate: (() async throws -> Void)?
    var onLaunch: (() async throws -> Void)?
    init(_ order: PrintOrder) { self.order = order }
    func refreshPayment(_ id: String, owner: String) async throws -> PrintOrder {
        refreshCount += 1
        return try await onRefresh?() ?? order
    }
    func checkPaymentAvailability(_ channel: String) throws { }
    func createPayment(_ id: String, owner: String, channel: String, key: UUID) async throws -> PrintPaymentLaunch {
        requests.append((channel, key))
        try await onCreate?()
        if let createError { throw createError }
        return try JSONDecoder().decode(PrintPaymentLaunch.self, from: Data("""
        {"attempt_id":"\(attemptID)","channel":"\(channel)","expires_at":"\(expiresAt)","parameters":{"order_string":"test-only"}}
        """.utf8))
    }
    func launchPayment(_ launch: PrintPaymentLaunch, owner: String) async throws {
        launches += 1; try await onLaunch?()
    }
}

@MainActor
struct PrintPaymentCoordinatorTests {
    private func order(payment: String = "unpaid", state: String = "draft", attempts: [[String: Any]] = [], actions: [String] = ["pay"]) throws -> PrintOrder {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/print-workflow-contract.json")
        var json = try #require((JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [[String: Any]])?.first)
        json["payment_state"] = payment; json["state"] = state; json["allowed_actions"] = actions
        json["payments"] = attempts; json["total_fen"] = 15900; json["file_state"] = "ready"
        return try JSONDecoder().decode(PrintOrder.self, from: JSONSerialization.data(withJSONObject: json))
    }
    private func url() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("payment.json") }
    private func coordinator(_ client: PaymentClientStub, _ path: URL) -> PrintPaymentCoordinator {
        PrintPaymentCoordinator(id: client.order.id, owner: "test-owner", client: client, storageURL: path, delays: [.zero])
    }
    private func settle(_ value: PrintPaymentCoordinator) async throws {
        for _ in 0..<1000 {
            if !value.phase.isBusy { await Task.yield(); return }
            await Task.yield()
        }
        Issue.record("Payment worker did not settle")
    }
    @Test func transportFailureSurvivesReopeningAndReusesOriginalKey() async throws {
        let path = url(); defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let client = PaymentClientStub(try order()); client.createError = URLError(.timedOut)
        let first = coordinator(client, path)
        await first.refresh(); #expect(first.canPay)
        first.pay(channel: "alipay"); first.pay(channel: "alipay")
        try await settle(first)
        #expect(client.requests.count == 1)
        #expect(first.phase == .unresolved); #expect(!first.canPay)
        let key = try #require(first.context?.key)
        first.invalidate()
        let reopened = coordinator(client, path)
        await reopened.refresh()
        #expect(reopened.context?.key == key)
        client.createError = nil
        reopened.resumeOriginalPayment(); try await settle(reopened)
        #expect(client.requests.count == 2)
        #expect(client.requests.allSatisfy { $0.1 == key && $0.0 == "alipay" })
        #expect(client.launches == 1)
        #expect(reopened.phase == .unresolved)
    }
    @Test func callbackWhileLaunchingIsNotLostAndSuccessClearsDisk() async throws {
        let path = url(); defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let client = PaymentClientStub(try order()); let value = coordinator(client, path)
        await value.refresh()
        let paid = try order(payment: "paid")
        client.onLaunch = {
            value.returned(.returned)
            client.order = paid
        }
        value.pay(channel: "wechat"); try await settle(value)
        #expect(value.phase == .succeeded)
        #expect(client.refreshCount >= 2)
        #expect(value.context == nil)
        #expect(!FileManager.default.fileExists(atPath: path.path))
        #expect(!value.canPay)
    }
    @Test func busyRefreshCoalescesCallbacksAndRunsOneFollowup() async throws {
        let path = url(); defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let client = PaymentClientStub(try order()); let value = coordinator(client, path)
        var release: CheckedContinuation<Void, Never>?
        client.onRefresh = {
            if client.refreshCount == 1 { await withCheckedContinuation { release = $0 } }
            return client.order
        }
        value.requestRefresh()
        for _ in 0..<1000 { if release != nil { break }; await Task.yield() }
        #expect(release != nil)
        value.requestRefresh(); value.requestRefresh(); value.requestRefresh()
        release?.resume()
        try await settle(value)
        #expect(client.refreshCount == 2)
    }
    @Test func closedAttemptAllowsNewChannelButUnknownAttemptDoesNot() async throws {
        let path = url(); defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let client = PaymentClientStub(try order()); let value = coordinator(client, path)
        await value.refresh(); value.pay(channel: "alipay"); try await settle(value)
        let oldKey = try #require(value.context?.key)
        #expect(!value.canPay)
        value.pay(channel: "wechat"); #expect(client.requests.count == 1)
        client.order = try order(attempts: [["id":"attempt-1", "channel":"alipay", "amount":15900, "state":"closed"]])
        await value.refresh(); #expect(value.canPay)
        value.pay(channel: "wechat"); try await settle(value)
        #expect(client.requests.count == 2)
        #expect(client.requests.last?.0 == "wechat")
        #expect(client.requests.last?.1 != oldKey)
    }
    @Test func refundAndCancelledOrdersNeverBecomePaymentSuccess() async throws {
        for (payment, state, expected) in [("refund_pending", "cancelled", PrintPaymentCoordinator.Phase.refunding), ("refunded", "cancelled", .refunded), ("unpaid", "cancelled", .closed), ("not_required", "awaiting_review", .free), ("paid", "cancelled", .closed), ("not_required", "cancelled", .closed)] {
            let client = PaymentClientStub(try order(payment: payment, state: state))
            let value = coordinator(client, url())
            await value.refresh(); #expect(value.phase == expected); #expect(!value.canPay)
        }
    }
    @Test func accountInvalidationPreventsDelayedSDKLaunch() async throws {
        let path = url(); defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let client = PaymentClientStub(try order()); let value = coordinator(client, path)
        await value.refresh()
        var release: CheckedContinuation<Void, Never>?
        client.onCreate = { await withCheckedContinuation { release = $0 } }
        value.pay(channel: "alipay")
        for _ in 0..<1000 { if release != nil { break }; await Task.yield() }
        #expect(release != nil)
        value.invalidate(); release?.resume()
        for _ in 0..<20 { await Task.yield() }
        #expect(client.launches == 0); #expect(value.order == nil); #expect(!value.canPay)
    }
    @Test func corruptPersistenceBlocksNewPaymentsAndMissingBreakdownIsCompatible() async throws {
        let path = url(); defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: path)
        let client = PaymentClientStub(try order()); let value = coordinator(client, path)
        await value.refresh()
        #expect(value.phase == .unresolved); #expect(!value.canPay); #expect(!value.canResumeOriginal)
        #expect(client.order.production_fen == nil); #expect(client.order.shipping_fen == nil)
    }
    @Test func storageFailureNeverSendsPaymentRequest() async throws {
        let path = url(); defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try Data("parent-is-file".utf8).write(to: path.deletingLastPathComponent())
        let client = PaymentClientStub(try order()); let value = coordinator(client, path)
        await value.refresh(); value.pay(channel: "alipay")
        #expect(client.requests.isEmpty); #expect(value.context == nil)
        #expect(value.error?.contains("无法保存支付记录") == true)
    }
    @Test func expiredAuthorizationNeverLaunchesAndRecoveryRefusesDifferentAttempt() async throws {
        let path = url(); defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let client = PaymentClientStub(try order()); let value = coordinator(client, path)
        await value.refresh(); value.pay(channel: "alipay"); try await settle(value)
        #expect(client.launches == 1)
        client.attemptID = "unexpected-new-attempt"
        value.resumeOriginalPayment(); try await settle(value)
        #expect(client.launches == 1)
        #expect(value.context?.attemptID == "attempt-1")
        client.attemptID = "attempt-1"; client.expiresAt = "2000-01-01T00:00:00Z"
        value.resumeOriginalPayment(); try await settle(value)
        #expect(client.launches == 1); #expect(value.phase == .unresolved)
    }

}
