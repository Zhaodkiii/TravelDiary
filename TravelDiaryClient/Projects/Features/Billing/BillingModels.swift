import Foundation

struct BillingBootstrap: Decodable {
    let session_id: String
    let expires_at: String
    let rc_app_user_id: String
    let wallet_domain: String
    let public_key: String
    let flags: BillingFlags
}
struct BillingFlags: Decodable {
    let diamond_recharge_enabled: Bool
    let diamond_redemption_enabled: Bool
    let diamond_customization_enabled: Bool
    let membership_sales_enabled: Bool
}
struct DiamondWallet: Decodable {
    let balance: Int?
    let balance_state: String
    let wallet_domain: String
    let can_redeem: Bool
    let version: Int
    let pending_order_id: String?
}
struct RechargeCatalog: Decodable {
    let offering_id: String
    let enabled: Bool
    let items: [RechargeItem]
}
struct RechargeItem: Decodable, Identifiable {
    let id: String
    let apple_product_id: String
    let package_id: String
    let units: Int
}
struct DiamondQuote: Decodable, Identifiable {
    var id: String { quote_id }
    let quote_id: String
    let offer_id: String
    let title: String
    let diamond_price: Int
    let balance: Int?
    let expires_at: String
    let member_access: Bool
}
struct DiamondOrder: Decodable, Identifiable {
    var id: String { order_id }
    let order_id: String
    let offer_id: String
    let title: String
    let status: String
    let amount: Int
    let last_error_code: String
    var finished: Bool { ["fulfilled", "rejected", "compensated"].contains(status) }
    var statusText: String {
        switch status {
        case "fulfilled": return "已解锁"
        case "rejected": return "未完成解锁"
        case "compensated": return "已退钻"
        case "compensating", "refund_unknown": return "正在处理退钻"
        default: return "正在确认，请勿重复操作"
        }
    }
}
struct DiamondEntry: Decodable, Identifiable {
    let id: String
    let delta: Int?
    let title: String
    let entry_kind: String
    let created_at: String
}
struct DiamondEntries: Decodable {
    let items: [DiamondEntry]
    let next_cursor: String?
}
struct BillingItems<T: Decodable>: Decodable { let items: [T] }
struct DiamondOwnership: Decodable, Identifiable {
    let id: String
    let target_kind: String
    let target_id: String
    let source_kind: String
}
struct BillingIntent: Codable {
    let owner: String
    let identity: String
    let quoteID: String
    let offerID: String
    let key: String
    var orderID: String?
}
struct BillingFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

nonisolated struct ContentCommerce: Codable {
    let offer_id: String
    let policy_revision: Int
    let access_mode: String?
    let diamond_price: Int?
}
nonisolated struct ContentAccess: Codable {
    struct Access: Codable {
        let can_use: Bool
        let reason: String
        let permanently_owned: Bool
        let can_redeem: Bool
        let can_preview: Bool
    }
    let commerce: ContentCommerce?
    let access: Access
}

nonisolated struct CustomDiamondQuote: Decodable {
    struct Scope: Decodable { let included_pages: Int; let max_photos: Int; let revision_rounds: Int; let lead_workdays: Int; let terms_version: String }
    let quote_id: String
    let quote_revision: Int
    let expected_request_revision: Int
    let total_diamonds: Int
    let standard_diamonds: Int
    let pricing_reason: String
    let scope: Scope
    let expires_at: String
}
nonisolated struct CustomDiamondFunding: Decodable { let id: String; let status: String; let amount: Int }
nonisolated struct CustomDiamondPayment: Decodable {
    let quote: CustomDiamondQuote?
    let funding: CustomDiamondFunding?
    let enabled: Bool?
}

struct MembershipStatus: Decodable {
    let active: Bool
    let expires_at: String?
    let period_ends_at: String?
    let verified_at: String?
    let sync_state: String
    let status: String
    let auto_renewal_status: String
    let product_id: String
    let wallet_domain: String
    let sales_enabled: Bool
    let member_content_count: Int
    var title: String {
        if sync_state != "fresh" { return "会员状态待同步" }
        if active {
            if status == "in_grace_period" { return "宽限期内，会员仍可用" }
            if auto_renewal_status == "will_not_renew" { return "已关闭续订，会员仍有效" }
            return "会员有效"
        }
        return status == "expired" || expires_at != nil ? "会员已到期" : "尚未开通会员"
    }
    var expiryText: String? {
        guard let raw = expires_at else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
