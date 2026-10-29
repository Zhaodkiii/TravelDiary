import RevenueCatUI
import SwiftUI
import RevenueCat

struct DiamondWalletScreen: View {
    let owner: String
    @ObservedObject private var store = BillingStore.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        SupportCanvas {
            VStack(alignment: .leading, spacing: 16) {
                Text(store.wallet?.wallet_domain == "sandbox" ? "钻石余额 · 测试环境" : "钻石余额").font(.headline)
                Text(store.wallet?.balance.map(String.init) ?? "—").font(.system(size: 44, weight: .semibold, design: .rounded))
                if store.wallet?.balance_state != "fresh" { Text("余额待刷新").font(.caption) }
                MainNavigationLink { DiamondRechargeScreen(owner: owner) } label: { Label("充值钻石", systemImage: "diamond") }
                Text("可用于指定模板、贴纸和数字定制，已购钻石不过期。").font(.footnote).foregroundStyle(DiaryLibraryStyle.secondary)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).feedbackPaperCard()
            if let message = store.message { Text(message).font(.footnote).foregroundStyle(DiaryLibraryStyle.secondary) }
            if !store.pending.isEmpty {
                Text("待处理").font(.headline)
                ForEach(store.pending) { order in
                    MainNavigationLink { DiamondOrderScreen(owner: owner, orderID: order.id) } label: {
                        VStack(alignment: .leading) { Text(order.title); Text(order.statusText).font(.caption) }.frame(maxWidth: .infinity, alignment: .leading).padding().feedbackPaperCard()
                    }
                }
            }
            MainNavigationLink { DiamondEntriesScreen(owner: owner) } label: { SupportNavigationRow(title: "钻石明细", symbol: "list.bullet.rectangle") }.feedbackPaperCard()
            MainNavigationLink { DiamondOwnershipScreen(owner: owner) } label: { SupportNavigationRow(title: "我的解锁内容", symbol: "lock.open") }.feedbackPaperCard()
            Button("同步购买记录") { Task { await store.refresh(owner: owner) } }.frame(minHeight: 44)
            MainNavigationLink { HelpCenterScreen(owner: owner) } label: { SupportNavigationRow(title: "帮助与售后", symbol: "questionmark.circle") }.feedbackPaperCard()
        }.navigationTitle("我的钻石")
        .task(id: owner) { await store.refresh(owner: owner) }
        .onChange(of: scenePhase) { _, value in if value == .active { Task { await store.refresh(owner: owner) } } }
    }
}

struct DiamondRechargeScreen: View {
    let owner: String
    @ObservedObject private var store = BillingStore.shared
    @State private var selected: String?
    var body: some View {
        SupportCanvas {
            Text(store.bootstrapInfo?.wallet_domain == "sandbox" ? "测试环境" : "钻石充值").font(.headline)
            Text("当前余额 ◇ \(store.wallet?.balance.map(String.init) ?? "—")")
            ForEach(store.catalog?.items ?? []) { item in
                Button { selected = item.id } label: {
                    HStack {
                        Text("\(item.units) 钻石").font(.headline)
                        Spacer()
                        Text(store.package(for: item)?.storeProduct.localizedPriceString ?? "暂不可售")
                        if selected == item.id { Image(systemName: "checkmark.circle.fill") }
                    }.padding(20).frame(minHeight: 64).feedbackPaperCard()
                }.buttonStyle(.plain).disabled(store.package(for: item) == nil || store.busy)
            }
            if store.catalog?.items.isEmpty != false { Text("充值档位暂不可用，请稍后重试。") }
            if store.catalog?.enabled != true { Text("充值正在准备中，暂未开放销售。").font(.footnote) }
            if let item = store.catalog?.items.first(where: { $0.id == selected }), let package = store.package(for: item) {
                Text("本次获得 \(item.units) 钻石，实际支付 \(package.storeProduct.localizedPriceString)")
                Button { Task { await store.purchase(item, owner: owner) } } label: {
                    HStack { if store.busy { ProgressView() }; Text("确认充值") }.frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(.borderedProminent).disabled(store.busy || store.catalog?.enabled != true)
            }
            if let message = store.message { Text(message).font(.footnote) }
            Text("钻石用于 App 内指定数字内容，不支持转让或提现。已购钻石不过期，充值后仍需确认兑换内容。").font(.footnote).foregroundStyle(DiaryLibraryStyle.secondary)
            Link("隐私政策", destination: AppEnvironment.current.privacyPolicyURL)
            Link("用户协议", destination: AppEnvironment.current.termsOfServiceURL)
            Button("重新加载") { Task { await store.loadProducts(owner: owner); await store.refresh(owner: owner) } }
        }.navigationTitle("充值钻石")
        .task(id: owner) { await store.refresh(owner: owner); await store.loadProducts(owner: owner) }
    }
}

struct DiamondPurchaseSheet: View {
    let owner: String
    let offerID: String
    let onUnlocked: () -> Void
    @State private var quote: DiamondQuote?
    @State private var order: DiamondOrder?
    @State private var error: String?
    @State private var submitting = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            SupportCanvas {
                if let quote {
                    Text(quote.title).font(.title2.bold())
                    Text("本人账号永久解锁，可反复用于自己的作品，换机登录后可恢复。")
                    LabeledContent("本次扣除", value: "◇ \(quote.diamond_price)")
                    LabeledContent("当前余额", value: quote.balance.map { "◇ \($0)" } ?? "待刷新")
                    if let balance = quote.balance, balance >= quote.diamond_price {
                        LabeledContent("预计剩余", value: "◇ \(balance - quote.diamond_price)")
                        Button("确认解锁 · \(quote.diamond_price) 钻") { Task { await redeem(quote) } }.buttonStyle(.borderedProminent).disabled(submitting || order?.finished == false)
                    } else {
                        if let balance = quote.balance { Text("还差 \(max(0, quote.diamond_price - balance)) 钻") }
                        NavigationLink("充值钻石") { DiamondRechargeScreen(owner: owner) }
                    }
                    Button("刷新报价与余额") { Task { await load() } }.disabled(submitting || order?.finished == false)
                } else if error == nil { ProgressView("正在读取报价") }
                if let order {
                    Text(order.statusText)
                    if !order.finished { NavigationLink("查看进度") { DiamondOrderScreen(owner: owner, orderID: order.id) } }
                }
                if let error { Text(error).font(.footnote) }
            }.navigationTitle("永久解锁").toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
                .task { await load() }
        }
    }
    private func load() async {
        do { quote = try await BillingStore.shared.makeQuote(offerID: offerID, owner: owner); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func redeem(_ quote: DiamondQuote) async {
        submitting = true; defer { submitting = false }
        do {
            let value = try await BillingStore.shared.redeem(quote, owner: owner); order = value
            if value.status == "fulfilled" { onUnlocked(); dismiss() }
        } catch { self.error = "正在确认操作结果：\(error.localizedDescription)。可返回钱包查看进度。" }
    }
}

struct DiamondOrderScreen: View {
    let owner: String
    let orderID: String
    @State private var order: DiamondOrder?
    @State private var error: String?
    var body: some View {
        SupportCanvas {
            Text(order?.title ?? "交易进度").font(.headline)
            Text(order?.statusText ?? "正在查询")
            Text("订单号：\(orderID)").font(.caption).textSelection(.enabled)
            if let error { Text(error) }
            Button("刷新") { Task { await load() } }
        }.navigationTitle("交易进度").task {
            for delay in [0, 2, 4, 8, 15, 15] {
                if delay > 0 { do { try await Task.sleep(for: .seconds(delay)) } catch { return } }
                await load()
                if order?.finished == true { return }
            }
        }
    }
    private func load() async {
        do { try await BillingStore.shared.ready(owner: owner); order = try await BillingStore.shared.request("redemptions/\(orderID)/", owner: owner); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct DiamondEntriesScreen: View {
    let owner: String
    @State private var entries: [DiamondEntry] = []
    @State private var next: String?
    @State private var error: String?
    var body: some View {
        SupportCanvas {
            ForEach(entries) { entry in
                HStack { VStack(alignment: .leading) { Text(entry.title); Text(entry.created_at).font(.caption) }; Spacer(); Text(entry.delta.map { $0 > 0 ? "+\($0)" : "\($0)" } ?? "—") }.padding().feedbackPaperCard()
            }
            if entries.isEmpty { Text("暂无记录") }
            if let error { Text(error) }
            if next != nil { Button("加载更多") { Task { await load(more: true) } } }
        }.navigationTitle("钻石明细").task { await load(more: false) }
    }
    private func load(more: Bool) async {
        do {
            try await BillingStore.shared.ready(owner: owner)
            let page: DiamondEntries = try await BillingStore.shared.request("wallet/entries/" + (more ? "?cursor=\(next ?? "")" : ""), owner: owner)
            entries = more ? entries + page.items : page.items; next = page.next_cursor; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct DiamondOwnershipScreen: View {
    let owner: String
    @State private var items: [DiamondOwnership] = []
    @State private var error: String?
    var body: some View {
        SupportCanvas {
            ForEach(items) { item in
                VStack(alignment: .leading) { Text(item.target_kind == "template" ? "已解锁手帐模板" : item.target_kind == "font" ? "已解锁字体" : "已解锁贴纸包"); Text(item.target_id).font(.caption).textSelection(.enabled) }.padding().feedbackPaperCard()
            }
            if items.isEmpty { Text("暂无永久解锁内容") }
            if let error { Text(error) }
        }.navigationTitle("我的解锁内容").task {
            do { try await BillingStore.shared.ready(owner: owner); let result: BillingItems<DiamondOwnership> = try await BillingStore.shared.request("content-ownerships/", owner: owner); items = result.items }
            catch { self.error = error.localizedDescription }
        }
    }
}

/// Reusable access control at content details; checkout always needs explicit confirmation.
struct BillingContentAction: View {
    let owner: String
    let kind: String
    let targetID: String
    let title: String
    let onUse: () -> Void
    @State private var access: ContentAccess?
    @State private var purchase = false
    @State private var membership = false
    @State private var error: String?
    @State private var revision = 0
    @State private var checking = false
    var body: some View {
        VStack(spacing: 8) {
            if let access {
                if access.access.can_use {
                    Button(access.access.permanently_owned ? "已解锁 · \(title)" : title) {
                        Task {
                            guard !checking else { return }
                            checking = true
                            defer { checking = false }
                            do {
                                let latest = try await BillingStore.shared.contentAccess(kind: kind, targetID: targetID, owner: owner)
                                self.access = latest; error = nil
                                if latest.access.can_use { onUse() }
                            } catch { self.error = error.localizedDescription }
                        }
                    }.buttonStyle(.borderedProminent).disabled(checking)
                }
                if access.access.can_redeem, let price = access.commerce?.diamond_price {
                    Button("\(price) 钻永久解锁") { purchase = true }.buttonStyle(.bordered)
                }
                if !access.access.can_use, ["pro_only", "pro_or_diamond"].contains(access.commerce?.access_mode ?? "") {
                    Button("开通 Pro 使用") { membership = true }
                }
            } else if error == nil { ProgressView() }
            if let error { Text(error).font(.caption); Button("重新检查") { revision += 1 } }
        }.frame(minHeight: 44)
        .task(id: "\(owner):\(targetID):\(revision)") {
            do { access = try await BillingStore.shared.contentAccess(kind: kind, targetID: targetID, owner: owner); error = nil }
            catch { self.error = error.localizedDescription }
        }
        .sheet(isPresented: $purchase, onDismiss: { revision += 1 }) {
            if let offerID = access?.commerce?.offer_id { DiamondPurchaseSheet(owner: owner, offerID: offerID) { revision += 1 } }
        }
        .sheet(isPresented: $membership, onDismiss: { revision += 1 }) { NavigationStack { MembershipPurchaseScreen(owner: owner) } }
    }
}

struct MembershipPurchaseScreen: View {
    let owner: String
    @ObservedObject private var store = BillingStore.shared
    @State private var offering: RevenueCat.Offering?
    @State private var error: String?
    @State private var loading = false
    @State private var showPaywall = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
                SupportCanvas {
                    if loading { ProgressView("正在加载会员页面") }
                    if let member = store.membership {
                        Text(member.title).font(.title2.bold())
                        if let expiry = member.expiryText { Text("权益有效期至 \(expiry)") }
                        if member.wallet_domain == "sandbox" { Text("沙盒测试订阅").font(.caption) }
                        if member.status == "in_grace_period" { Text("请检查 Apple 付款信息，宽限期内仍可使用会员内容。") }
                        Link("管理或取消 Apple 订阅", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    }
                    if store.membership?.active != true {
                        Button("开通会员") { showPaywall = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(offering == nil || loading || store.busy)
                    }
                    Button("同步会员状态") { Task { await load() } }.disabled(loading || store.busy)
                    Button("恢复购买") { Task { await restore() } }.disabled(loading || store.busy)
                }
        .navigationTitle("会员服务")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("同步状态") { Task { await load() } }.disabled(loading || store.busy)
            }
        }
        .sheet(isPresented: $showPaywall, onDismiss: { Task { await load() } }) {
            if let offering {
                subscriptionPaywall(offering)
                    .interactiveDismissDisabled(store.busy)
                    .alert("会员服务", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                        Button("同步状态") { Task { await load() } }
                        Button("关闭", role: .cancel) { error = nil }
                    } message: { Text(error ?? "") }
            }
        }
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !store.busy { Task { await load() } }
        }
        .alert("会员服务", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("同步状态") { Task { await load() } }
            Button("关闭", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
    private func subscriptionPaywall(_ offering: RevenueCat.Offering) -> some View {
                PaywallView(offering: offering, displayCloseButton: true)
                    // Keep account switching and all SDK mutations on the existing serialized lane.
                    // The interception handles the transaction; never resume a second SDK purchase.
                    .onPurchaseInitiated { package, resume in
                        Task { @MainActor in
                            defer { resume(shouldProceed: false) }
                            do {
                                guard store.membership?.member_content_count ?? 0 > 0 else { throw BillingFailure("会员内容正在准备中") }
                                let purchased = try await store.purchaseMembership(package, owner: owner)
                                if purchased && store.membership?.active == true { showPaywall = false }
                                else if purchased { error = "购买已记录，请同步会员状态，勿重复付款。" }
                            } catch {
                                let nsError = error as NSError
                                if nsError.code != RevenueCat.ErrorCode.purchaseCancelledError.rawValue {
                                    self.error = nsError.code == RevenueCat.ErrorCode.paymentPendingError.rawValue
                                        ? "购买等待批准，批准后请同步会员状态。" : error.localizedDescription
                                }
                            }
                        }
                    }
                    .onRestoreInitiated { resume in
                        Task { @MainActor in
                            defer { resume(shouldProceed: false) }
                            await restore()
                        }
                    }
    }
    private func load() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        do {
            try await store.refreshMembership(owner: owner)
            if store.membership?.active != true { offering = try await store.membershipOffering(owner: owner) }
        } catch { self.error = error.localizedDescription }
    }
    private func restore() async {
        do {
            try await store.restoreMembership(owner: owner)
            if store.membership?.active == true { showPaywall = false }
            if store.membership?.active != true { error = "未发现有效会员，请确认登录原购买账号。" }
        } catch { self.error = error.localizedDescription }
    }
}

struct CustomizationDiamondPaymentScreen: View {
    let owner: String
    let requestID: String
    @ObservedObject private var store = BillingStore.shared
    @State private var payment: CustomDiamondPayment?
    @State private var funding: CustomDiamondFunding?
    @State private var error: String?
    @State private var paying = false
    var body: some View {
        SupportCanvas {
            if let quote = payment?.quote {
                Text("确认数字定制报价").font(.title2.bold())
                Text("含 \(quote.scope.included_pages) 内页、最多 \(quote.scope.max_photos) 张照片、\(quote.scope.revision_rounds) 轮修改，初稿预计 \(quote.scope.lead_workdays) 个工作日。")
                LabeledContent("基础价", value: "\(quote.standard_diamonds) 钻")
                if quote.pricing_reason == "pro" { LabeledContent("Pro 优惠", value: "−\(quote.standard_diamonds - quote.total_diamonds) 钻") }
                LabeledContent("合计", value: "\(quote.total_diamonds) 钻")
                Text("报价有效期至 \(quote.expires_at)").font(.footnote)
                Text("会员优惠在付款时核验。数字定制不包含实体印制。")
                if let funding = funding ?? payment?.funding {
                    Text(funding.status == "funded" ? "已付款，等待制作" : funding.status == "refunded" ? "已退钻" : "付款状态：\(funding.status)")
                    Text("付款单号：\(funding.id)").font(.caption).textSelection(.enabled)
                } else if let balance = store.wallet?.balance, balance >= quote.total_diamonds {
                    Button("确认支付 · \(quote.total_diamonds) 钻") { Task { await pay(quote) } }.buttonStyle(.borderedProminent).disabled(paying || payment?.enabled != true)
                } else { NavigationLink("充值后支付") { DiamondRechargeScreen(owner: owner) } }
            } else { Text("暂无待确认报价") }
            if let error { Text(error).font(.footnote) }
            Button("刷新报价和付款进度") { Task { await load() } }.disabled(paying)
        }.navigationTitle("定制付款").task { await load() }
    }
    private func load() async {
        do { try await store.ready(owner: owner); payment = try await store.request("customizations/\(requestID)/", owner: owner); await store.refresh(owner: owner); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func pay(_ quote: CustomDiamondQuote) async {
        paying = true; defer { paying = false }
        let cacheKey = "billing.custom.\(owner).\(store.bootstrapInfo?.rc_app_user_id ?? "").\(requestID).\(quote.quote_id)"
        let key = UserDefaults.standard.string(forKey: cacheKey) ?? UUID().uuidString
        UserDefaults.standard.set(key, forKey: cacheKey)
        do {
            funding = try await store.request("customizations/\(requestID)/", owner: owner, method: .post, body: ["quote_id":quote.quote_id,"quote_revision":quote.quote_revision,"expected_request_revision":quote.expected_request_revision,"expected_total":quote.total_diamonds], key: key)
            await store.refresh(owner: owner)
        } catch { self.error = "付款结果待确认，请刷新原订单进度。\(error.localizedDescription)" }
    }
}
