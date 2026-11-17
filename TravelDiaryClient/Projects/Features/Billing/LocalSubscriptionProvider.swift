#if DEBUG
import Foundation
import StoreKit

@MainActor
final class LocalSubscriptionProvider: SubscriptionProvider {
    func products() async throws -> [ProSubscriptionPlan] { try await SubscriptionCatalog.products() }
    func status() async throws -> MembershipStatus {
        var latest: Transaction?
        for await result in Transaction.all {
            guard case .verified(let transaction) = result, transaction.environment == .xcode,
                  SubscriptionCatalog.ids.contains(transaction.productID), !transaction.isUpgraded else { continue }
            if latest == nil || transaction.purchaseDate > latest!.purchaseDate { latest = transaction }
        }
        let active = latest.map { $0.revocationDate == nil && ($0.expirationDate ?? .distantPast) > Date() } ?? false
        var renewal = "unknown"
        if let id = latest?.productID, let product = try await Product.products(for: [id]).first, let subscription = product.subscription {
            for state in try await subscription.status {
                if case .verified(let info) = state.renewalInfo { renewal = info.willAutoRenew ? "will_renew" : "will_not_renew" }
            }
        }
        let expiry = latest?.expirationDate.map { ISO8601DateFormatter().string(from: $0) }
        return MembershipStatus(active: active, expires_at: expiry, period_ends_at: expiry,
            verified_at: ISO8601DateFormatter().string(from: Date()), sync_state: "fresh",
            status: active ? "active" : latest?.revocationDate != nil ? "revoked" : latest == nil ? "inactive" : "expired",
            auto_renewal_status: renewal, product_id: latest?.productID ?? "", wallet_domain: "xcode",
            sales_enabled: true, member_content_count: 0, ai_production_included: true)
    }
    func purchase(_ id: String) async throws -> MembershipStatus? {
        guard SubscriptionCatalog.ids.contains(id), let product = try await Product.products(for: [id]).first else { throw BillingFailure("请重新加载套餐") }
        switch try await product.purchase() {
        case .success(.verified(let transaction)):
            guard transaction.environment == .xcode else { throw BillingFailure("测试环境不匹配") }
            await transaction.finish()
            return try await status()
        case .success(.unverified): throw BillingFailure("交易验证失败")
        case .pending: throw SubscriptionAwaitingApproval()
        case .userCancelled: return nil
        @unknown default: throw BillingFailure("未知购买结果，请恢复购买")
        }
    }
    func restore() async throws -> MembershipStatus { try await AppStore.sync(); return try await status() }
}
#endif
