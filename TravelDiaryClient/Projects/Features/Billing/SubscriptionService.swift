import Foundation
import Combine
import StoreKit
import RevenueCat

@MainActor
protocol SubscriptionProvider: AnyObject {
    func products() async throws -> [ProSubscriptionPlan]
    func status() async throws -> MembershipStatus
    func purchase(_ id: String) async throws -> MembershipStatus?
    func restore() async throws -> MembershipStatus
}

enum SubscriptionOperation { case idle, loading, purchasing, restoring, awaitingApproval }
enum SubscriptionSync { case local, idle, syncing, ready, failed }

@MainActor
final class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()
    @Published private(set) var plans: [ProSubscriptionPlan] = []
    @Published private(set) var gift: ProAnnualGift?
    @Published private(set) var member: MembershipStatus?
    @Published private(set) var serverMember: MembershipStatus?
    @Published private(set) var operation: SubscriptionOperation = .idle
    @Published private(set) var serverSync: SubscriptionSync = .idle
    @Published private(set) var error: String?
    private(set) var owner: String?
    private var provider: (any SubscriptionProvider)?
    private var sessions: AnyCancellable?
    private var updates: Task<Void, Never>?
    private var reconciliation: Task<Void, Never>?
    private var generation = UUID()
    init() {}
    // Inject the same provider contract for deterministic purchase-state tests.
    init(owner: String, provider: any SubscriptionProvider) {
        self.owner = owner
        self.provider = provider
        self.serverSync = .local
    }
    var busy: Bool { [.loading, .purchasing, .restoring].contains(operation) }
    var notice: String? {
        if let error { return error }
        if operation == .awaitingApproval { return "购买等待批准，批准后会自动更新" }
        if serverSync == .local { return "本地购买测试 · 服务端额度与赠券不受影响" }
        if member?.active == true && serverSync == .syncing { return "已订阅，制作服务正在同步" }
        if serverSync == .failed { return "服务器权益暂未同步，请重试" }
        return nil
    }

    func configure(sessions store: AppSessionStore) {
        sessions = store.$state.sink { [weak self] state in
            guard let self else { return }
            let next: String?
            if case .signedIn(let session) = state { next = String(session.accountID) } else { next = nil }
            guard next != owner else { return }
            generation = UUID(); updates?.cancel(); reconciliation?.cancel()
            updates = nil; reconciliation = nil
            owner = next; provider = nil; plans = []; member = nil; serverMember = nil; gift = nil; error = nil
            operation = .idle; serverSync = .idle
        }
    }

    private func prepared(_ expected: String) async throws -> any SubscriptionProvider {
        guard owner == expected else { throw CancellationError() }
        if let provider { return provider }
        let stamp = generation
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--local-storekit") {
            let adapter = LocalSubscriptionProvider()
            provider = adapter; serverSync = .local
            updates = Task { [weak self] in
                for await result in Transaction.updates {
                    guard !Task.isCancelled, let self, generation == stamp else { return }
                    if case .verified(let transaction) = result, transaction.environment == .xcode,
                       SubscriptionCatalog.ids.contains(transaction.productID) {
                        await transaction.finish()
                        if let value = try? await adapter.status(), generation == stamp { member = value; if value.active && operation == .awaitingApproval { operation = .idle } }
                    }
                }
            }
            return adapter
        }
        #endif
        try await BillingStore.shared.ready(owner: expected)
        guard generation == stamp else { throw CancellationError() }
        let adapter = RevenueCatSubscriptionProvider(owner: expected)
        provider = adapter
        updates = Task { [weak self] in
            for await _ in Purchases.shared.customerInfoStream {
                guard !Task.isCancelled, let self, generation == stamp else { return }
                guard Purchases.shared.appUserID == BillingStore.shared.bootstrapInfo?.rc_app_user_id else { continue }
                // Stream events can be buffered across logIn. Re-read within the identity queue
                // instead of trusting an event's originalAppUserId (which can be an alias).
                guard let current = try? await adapter.status(), generation == stamp else { continue }
                member = current
                if member?.active == true && operation == .awaitingApproval { operation = .idle }
                reconcile(expected)
            }
        }
        return adapter
    }

    func refresh(owner expected: String) async {
        guard !busy else { return }
        let stamp = generation
        let waitingForApproval = operation == .awaitingApproval
        operation = .loading; error = nil
        defer {
            if generation == stamp && operation == .loading {
                operation = waitingForApproval && member?.active != true ? .awaitingApproval : .idle
            }
        }
        do {
            // StoreKit catalog loading does not depend on our server or RevenueCat identity.
            do { let value = try await SubscriptionCatalog.products(); if generation == stamp { plans = value } }
            catch { if generation == stamp { self.error = error.localizedDescription } }
            let adapter = try await prepared(expected)
            do { let value = try await adapter.status(); if generation == stamp { member = value } }
            catch { if generation == stamp { self.error = error.localizedDescription } }
            guard generation == stamp else { return }
            if serverSync != .local {
                reconcile(expected)
                let offer: ProAnnualGift? = try? await PrintOrderService.shared.request("campaign/annual/", owner: expected)
                if generation == stamp { gift = member?.wallet_domain == "production" && offer?.validityText != nil ? offer : nil }
            }
        } catch is CancellationError {} catch { if generation == stamp { self.error = error.localizedDescription } }
    }

    func purchase(_ id: String, owner expected: String) async {
        guard !busy, operation != .awaitingApproval else { return }
        let stamp = generation
        operation = .purchasing; error = nil
        defer { if generation == stamp && operation == .purchasing { operation = .idle } }
        do {
            let adapter = try await prepared(expected)
            var promised: ProAnnualGift?
            if let gift, let giftID = gift.id, let sku = gift.sku, plans.first(where: { $0.id == id })?.annual == true {
                let body = try PrintOrderService.shared.json(["plan_id": giftID, "sku": sku])
                let _: GiftReservation = try await PrintOrderService.shared.request("campaign/annual/", owner: expected, body: body)
                promised = gift
            }
            let value: MembershipStatus?
            do { value = try await adapter.purchase(id) }
            catch {
                // Unknown payment results retain the reservation for webhook reconciliation.
                if isRevenueCat(error, .purchaseCancelledError) { await releaseGift(promised, owner: expected) }
                throw error
            }
            if value == nil { await releaseGift(promised, owner: expected) }
            guard generation == stamp else { return }
            if let value { member = value; if serverSync != .local { reconcile(expected) } }
        } catch {
            guard generation == stamp else { return }
            if isRevenueCat(error, .paymentPendingError) || error is SubscriptionAwaitingApproval {
                operation = .awaitingApproval
            } else if !isRevenueCat(error, .purchaseCancelledError) {
                self.error = error.localizedDescription
            }
        }
    }

    func restore(owner expected: String) async {
        guard !busy else { return }
        let stamp = generation
        operation = .restoring; error = nil
        defer { if generation == stamp { operation = .idle } }
        do {
            let value = try await prepared(expected).restore()
            guard generation == stamp else { return }
            member = value
            if !value.active { error = "未找到有效订阅，请确认使用购买时的 Apple 账户" }
            if serverSync != .local { reconcile(expected) }
        } catch { if generation == stamp { self.error = error.localizedDescription } }
    }

    private func isRevenueCat(_ error: Error, _ code: RevenueCat.ErrorCode) -> Bool {
        let value = error as NSError
        return value.domain == RevenueCat.ErrorCode.errorDomain && value.code == code.rawValue
    }
    private struct GiftReservation: Decodable { let message: String }
    private func releaseGift(_ gift: ProAnnualGift?, owner: String) async {
        guard let id = gift?.id, let sku = gift?.sku else { return }
        if let body = try? PrintOrderService.shared.json(["plan_id": id, "sku": sku, "cancelled": true]) {
            let _: GiftReservation? = try? await PrintOrderService.shared.request("campaign/annual/", owner: owner, body: body)
        }
    }

    private func reconcile(_ expected: String) {
        guard reconciliation == nil else { return }
        let stamp = generation
        serverSync = .syncing
        reconciliation = Task { [weak self] in
            guard let self else { return }
            defer { if generation == stamp { reconciliation = nil } }
            for delay in [0, 2, 5] {
                do {
                    if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
                    try Task.checkCancellation()
                    try await BillingStore.shared.ready(owner: expected)
                    let value: MembershipStatus = try await BillingStore.shared.request("membership/", owner: expected, method: .post, body: [:])
                    guard generation == stamp else { return }
                    serverMember = value
                    if value.sync_state == "fresh", value.active == (member?.active == true) {
                        serverSync = .ready
                        await DiaryProductionService.shared.refreshQuota()
                        return
                    }
                } catch is CancellationError { return } catch { }
            }
            if generation == stamp { serverSync = .failed }
        }
    }
}

struct SubscriptionAwaitingApproval: Error {}
enum SubscriptionCatalog {
    static func products() async throws -> [ProSubscriptionPlan] {
        let products = try await Product.products(for: ids)
        let monthly = products.first { $0.id.hasSuffix(".monthly") }
        return products.map { product in
            let annual = product.id.hasSuffix(".yearly")
            return ProSubscriptionPlan(id: product.id, annual: annual, price: product.displayPrice,
                monthlyEquivalent: annual ? (product.price / 12).formatted(product.priceFormatStyle) : nil,
                savings: annual ? monthly.flatMap { ProSubscriptionPlan.savingPercent(annual: product.price, monthly: $0.price,
                    sameCurrency: product.priceFormatStyle.currencyCode == $0.priceFormatStyle.currencyCode) } : nil)
        }.sorted { $0.annual && !$1.annual }
    }
    static let ids = ["cn.zhaodk.TravelDiary.member.monthly", "cn.zhaodk.TravelDiary.member.yearly"]
}

@MainActor
final class RevenueCatSubscriptionProvider: SubscriptionProvider {
    let owner: String
    init(owner: String) { self.owner = owner }
    func products() async throws -> [ProSubscriptionPlan] { try await SubscriptionCatalog.products() }
    func map(_ info: CustomerInfo) -> MembershipStatus {
        let entitlement = info.entitlements.all["member"]
        let expiry = entitlement?.expirationDate.map { ISO8601DateFormatter().string(from: $0) }
        return MembershipStatus(active: entitlement?.isActive == true, expires_at: expiry, period_ends_at: expiry,
            verified_at: ISO8601DateFormatter().string(from: Date()), sync_state: "fresh",
            status: entitlement?.isActive == true ? "active" : entitlement == nil ? "inactive" : "expired",
            auto_renewal_status: entitlement.map { $0.willRenew ? "will_renew" : "will_not_renew" } ?? "unknown",
            product_id: entitlement?.productIdentifier ?? "", wallet_domain: entitlement.map { $0.isSandbox ? "sandbox" : "production" } ?? BillingStore.shared.bootstrapInfo?.wallet_domain ?? "unknown",
            sales_enabled: BillingStore.shared.bootstrapInfo?.flags.membership_sales_enabled == true,
            member_content_count: 0, ai_production_included: true)
    }
    func status() async throws -> MembershipStatus {
        let store = BillingStore.shared
        return map(try await store.serializedSDK(owner, stamp: store.generation) { try await Purchases.shared.customerInfo() })
    }
    func purchase(_ id: String) async throws -> MembershipStatus? {
        guard SubscriptionCatalog.ids.contains(id), let product = try await Purchases.shared.products([id]).first else { throw BillingFailure("套餐已变化，请重新加载") }
        let store = BillingStore.shared
        let result = try await store.serializedSDK(owner, stamp: store.generation) { try await Purchases.shared.purchase(product: product) }
        return result.userCancelled ? nil : map(result.customerInfo)
    }
    func restore() async throws -> MembershipStatus {
        let store = BillingStore.shared
        return map(try await store.serializedSDK(owner, stamp: store.generation) { try await Purchases.shared.restorePurchases() })
    }
}
