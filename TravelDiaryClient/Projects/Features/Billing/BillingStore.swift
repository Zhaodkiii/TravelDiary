import Foundation
import Combine
import StoreKit
import RevenueCat

/// Account-bound billing. Every async response must still belong to this generation.
@MainActor
final class BillingStore: ObservableObject {
    static let shared = BillingStore()
    @Published private(set) var membershipPending = false
    @Published private(set) var membership: MembershipStatus?
    @Published private(set) var wallet: DiamondWallet?
    @Published private(set) var catalog: RechargeCatalog?
    @Published private(set) var packages: [String: RevenueCat.Package] = [:]
    @Published private(set) var pending: [DiamondOrder] = []
    @Published private(set) var bootstrapInfo: BillingBootstrap?
    @Published private(set) var busy = false
    @Published var message: String?
    private(set) var owner: String?
    private var formalAccount = false
    private var engine: SupportNetworkEngine?
    private var subscription: AnyCancellable?
    private var generation = UUID()
    private var identityTask: Task<Void, Error>?
    private var sdkTail: Task<Void, Never>?

    func configure(engine: SupportNetworkEngine, sessions: AppSessionStore) {
        self.engine = engine
        subscription = sessions.$state.sink { [weak self] state in
            guard let self else { return }
            let next: String?
            let formal: Bool
            if case let .signedIn(session) = state { next = String(session.accountID); formal = !session.isDeviceAccount }
            else { next = nil; formal = false }
            guard owner != next || formalAccount != formal else { return }
            generation = UUID(); identityTask?.cancel(); identityTask = nil
            owner = next; formalAccount = formal
            membershipPending = false; membership = nil; wallet = nil; catalog = nil; packages = [:]; pending = []; bootstrapInfo = nil; message = nil; busy = false
        }
    }
    private func validate(_ expected: String, stamp: UUID) throws {
        guard owner == expected, generation == stamp else { throw CancellationError() }
    }
    func request<T: Decodable>(_ path: String, owner expected: String, method: SupportHTTPMethod = .get, body: [String: Any]? = nil, key: String? = nil) async throws -> T {
        let stamp = generation
        try validate(expected, stamp: stamp)
        guard let engine else { throw BillingFailure("服务正在初始化") }
        var headers: [String: String] = [:]
        if let session = bootstrapInfo?.session_id { headers["X-Billing-Session"] = session }
        if let key { headers["Idempotency-Key"] = key }
        let components = URLComponents(string: path)
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) }
        let response = try await engine.sendRaw(SupportNetworkRequest(method: method, path: "/api/v1/billing/" + (components?.path ?? path), queryItems: components?.queryItems, headers: headers, body: data.map { .raw($0, contentType: "application/json") } ?? .none, strategy: NetworkStrategy(requiresAuth: true, allowETag: false)))
        try validate(expected, stamp: stamp)
        return try JSONDecoder().decode(T.self, from: response.data)
    }
    func ready(owner expected: String) async throws {
        guard owner == expected, formalAccount else { throw BillingFailure("请先绑定正式账号，再使用会员与钻石服务") }
        if let info = bootstrapInfo {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let expiry = formatter.date(from: info.expires_at) ?? ISO8601DateFormatter().date(from: info.expires_at)
            if let expiry, expiry.timeIntervalSinceNow > 60 { return }
            bootstrapInfo = nil
        }
        if let identityTask { return try await identityTask.value }
        let stamp = generation
        let task = Task { @MainActor in
            let proof = try await AppTransaction.shared
            guard case .verified = proof else { throw BillingFailure("无法验证 App Store 环境，请从 App Store 或 TestFlight 安装") }
            let info: BillingBootstrap = try await request("bootstrap/", owner: expected, method: .post, body: ["signed_app_transaction": proof.jwsRepresentation])
            try validate(expected, stamp: stamp)
            guard info.public_key.hasPrefix("appl_") else { throw BillingFailure("充值服务尚未配置") }
            // Login operations are serialized, including across account changes.
            let previous = sdkTail
            let login = Task { @MainActor in
                await previous?.value
                try validate(expected, stamp: stamp)
                if !Purchases.isConfigured {
                    Purchases.configure(withAPIKey: info.public_key, appUserID: info.rc_app_user_id)
                } else {
                    _ = try await Purchases.shared.logIn(info.rc_app_user_id)
                }
                try validate(expected, stamp: stamp)
                bootstrapInfo = info
                membershipPending = UserDefaults.standard.bool(forKey: "billing.membership.pending.\(info.rc_app_user_id)")
            }
            sdkTail = Task { _ = try? await login.value }
            try await login.value
        }
        identityTask = task
        do { try await task.value; if generation == stamp { identityTask = nil } }
        catch { if generation == stamp { identityTask = nil }; throw error }
    }
    /// Keep the RevenueCat identity fixed until StoreKit finishes the operation.
    private func serializedSDK<T: Sendable>(_ expected: String, stamp: UUID, operation: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = sdkTail
        let task = Task { @MainActor in
            await previous?.value
            try validate(expected, stamp: stamp)
            let result = try await operation()
            try validate(expected, stamp: stamp)
            return result
        }
        sdkTail = Task { _ = try? await task.value }
        return try await task.value
    }
    func refresh(owner expected: String) async {
        let stamp = generation
        do {
            try await ready(owner: expected)
            let fetched: DiamondWallet = try await request("wallet/", owner: expected)
            if wallet == nil || fetched.version >= (wallet?.version ?? 0) { wallet = fetched }
            let orders: BillingItems<DiamondOrder> = try await request("redemptions/?state=pending", owner: expected)
            pending = orders.items
            if Purchases.isConfigured { Purchases.shared.invalidateVirtualCurrenciesCache() }
            message = nil
        } catch { if generation == stamp { message = error.localizedDescription } }
    }
    func loadProducts(owner expected: String) async {
        let stamp = generation
        do {
            try await ready(owner: expected)
            let result: RechargeCatalog = try await request("recharge-products/", owner: expected)
            let offerings = try await Purchases.shared.offerings()
            try validate(expected, stamp: stamp)
            catalog = result
            let items = offerings.all[result.offering_id]?.availablePackages ?? []
            packages = Dictionary(uniqueKeysWithValues: items.map { ($0.identifier, $0) })
        } catch { if generation == stamp { message = error.localizedDescription } }
    }
    func package(for item: RechargeItem) -> RevenueCat.Package? {
        guard let package = packages[item.package_id], package.storeProduct.productIdentifier == item.apple_product_id else { return nil }
        return package
    }
    func purchase(_ item: RechargeItem, owner expected: String) async {
        guard !busy, catalog?.enabled == true, let package = package(for: item) else { return }
        let stamp = generation
        busy = true
        defer { if generation == stamp { busy = false } }
        do {
            try await ready(owner: expected)
            guard Purchases.shared.appUserID == bootstrapInfo?.rc_app_user_id else { throw BillingFailure("钱包身份正在同步") }
            let result = try await serializedSDK(expected, stamp: stamp) { try await Purchases.shared.purchase(package: package) }
            try validate(expected, stamp: stamp)
            if result.userCancelled { message = nil; return }
            let synced: DiamondWallet = try await request("wallet/sync/", owner: expected, method: .post, body: [:])
            wallet = synced
            // Purchase success alone does not prove the currency grant completed.
            message = "购买已记录，正在同步钻石余额，可在明细查看到账记录"
            Purchases.shared.invalidateVirtualCurrenciesCache()
        } catch { if generation == stamp { message = "购买状态待确认：\(error.localizedDescription)。请在钱包同步记录后再操作。" } }
    }
    func makeQuote(offerID: String, owner: String) async throws -> DiamondQuote {
        try await ready(owner: owner)
        return try await request("redemption-quotes/", owner: owner, method: .post, body: ["offer_id": offerID])
    }
    private func intentKey(_ owner: String, _ identity: String, _ offer: String) -> String { "billing.intent.\(owner).\(identity).\(offer)" }
    func redeem(_ quote: DiamondQuote, owner expected: String) async throws -> DiamondOrder {
        try await ready(owner: expected)
        guard let identity = bootstrapInfo?.rc_app_user_id else { throw BillingFailure("钱包身份尚未就绪") }
        let storageKey = intentKey(expected, identity, quote.offer_id)
        let saved = UserDefaults.standard.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(BillingIntent.self, from: $0) }
        let intent = saved ?? BillingIntent(owner: expected, identity: identity, quoteID: quote.quote_id, offerID: quote.offer_id, key: UUID().uuidString)
        UserDefaults.standard.set(try JSONEncoder().encode(intent), forKey: storageKey)
        let order: DiamondOrder
        do {
            order = try await request("redemptions/", owner: expected, method: .post, body: ["quote_id": intent.quoteID, "offer_id": intent.offerID], key: intent.key)
        } catch {
            // Only definite pre-debit rejections permit a fresh request key.
            if case let SupportNetworkError.http(_, _, data) = error,
               let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let code = (body["msg"] as? [String: Any])?["code"] as? String ?? body["code"] as? String,
               ["QUOTE_EXPIRED", "PRICE_CHANGED", "CONTENT_UNAVAILABLE", "ALREADY_OWNED", "SALES_DISABLED"].contains(code) {
                UserDefaults.standard.removeObject(forKey: storageKey)
            }
            throw error
        }
        if order.finished { UserDefaults.standard.removeObject(forKey: storageKey) }
        else {
            var updated = intent; updated.orderID = order.order_id
            UserDefaults.standard.set(try JSONEncoder().encode(updated), forKey: storageKey)
        }
        await refresh(owner: expected)
        return order
    }
}

extension BillingStore {
    func contentAccess(kind: String, targetID: String, owner: String) async throws -> ContentAccess {
        let path = "content-access/\(kind)/\(targetID)/"
        let initial: ContentAccess = try await request(path, owner: owner)
        if initial.access.can_use { return initial }
        try await ready(owner: owner)
        return try await request(path, owner: owner)
    }
    func requireContent(kind: String, targetID: String, owner: String) async throws {
        let access = try await contentAccess(kind: kind, targetID: targetID, owner: owner)
        guard access.access.can_use else { throw BillingFailure("请先在内容详情开通会员或永久解锁") }
    }
}

extension BillingStore {
    func membershipOffering(owner expected: String) async throws -> RevenueCat.Offering {
        let stamp = generation
        try await ready(owner: expected)
        let offerings = try await Purchases.shared.offerings()
        try validate(expected, stamp: stamp)
        guard let offering = offerings.all["membership"], offering.hasPaywall else {
            throw BillingFailure("会员订阅页面暂不可用，请稍后重试")
        }
        return offering
    }
    func membershipPackages(owner expected: String) async throws -> [RevenueCat.Package] {
        let stamp = generation
        try await ready(owner: expected)
        let offerings = try await Purchases.shared.offerings()
        try validate(expected, stamp: stamp)
        let allowed = ["cn.zhaodk.TravelDiary.member.monthly", "cn.zhaodk.TravelDiary.member.yearly"]
        return (offerings.all["membership"]?.availablePackages ?? []).filter {
            allowed.contains($0.storeProduct.productIdentifier) && $0.storeProduct.subscriptionPeriod != nil
        }
    }
    func refreshMembership(owner expected: String) async throws {
        try await ready(owner: expected)
        let value: MembershipStatus = try await request("membership/", owner: expected, method: .post, body: [:])
        membership = value
        if value.active && value.sync_state == "fresh" { setMembershipPending(false) }
    }
    private func setMembershipPending(_ value: Bool) {
        membershipPending = value
        if let identity = bootstrapInfo?.rc_app_user_id {
            UserDefaults.standard.set(value, forKey: "billing.membership.pending.\(identity)")
        }
    }
    func purchaseMembership(_ package: RevenueCat.Package, owner expected: String) async throws -> Bool {
        let stamp = generation
        try await ready(owner: expected)
        guard bootstrapInfo?.flags.membership_sales_enabled == true, !busy else { throw BillingFailure("会员购买暂未开放") }
        busy = true; defer { if generation == stamp { busy = false } }
        try await refreshMembership(owner: expected)
        guard ["cn.zhaodk.TravelDiary.member.monthly", "cn.zhaodk.TravelDiary.member.yearly"].contains(package.storeProduct.productIdentifier), package.storeProduct.subscriptionPeriod != nil else {
            throw BillingFailure("此套餐不属于当前会员订阅")
        }
        guard membership?.sales_enabled == true, (membership?.member_content_count ?? 0) > 0 else { throw BillingFailure("会员服务暂未开放") }
        guard membership?.active != true else { throw BillingFailure("已有有效会员，请通过管理订阅调整套餐") }
        guard !membershipPending, membership?.sync_state == "fresh" else { throw BillingFailure("请先同步或恢复上次购买记录") }
        setMembershipPending(true)
        do {
            let result = try await serializedSDK(expected, stamp: stamp) { try await Purchases.shared.purchase(package: package) }
            try validate(expected, stamp: stamp)
            if result.userCancelled { setMembershipPending(false); return false }
            try await refreshMembership(owner: expected)
            return true
        } catch {
            if generation == stamp && (error as NSError).code == RevenueCat.ErrorCode.purchaseCancelledError.rawValue { setMembershipPending(false) }
            throw error
        }
    }
    func restoreMembership(owner expected: String) async throws {
        let stamp = generation
        try await ready(owner: expected)
        guard !busy else { throw BillingFailure("购买正在处理中，请稍后") }
        busy = true; defer { if generation == stamp { busy = false } }
        _ = try await serializedSDK(expected, stamp: stamp) { try await Purchases.shared.restorePurchases() }
        try validate(expected, stamp: stamp)
        try await refreshMembership(owner: expected)
        if membership?.sync_state == "fresh" { setMembershipPending(false) }
    }
}
