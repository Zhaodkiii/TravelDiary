import SwiftUI
import RevenueCat

/// Presentation data stays separate from transactions, so previews never contact the store.
struct ProSubscriptionPlan: Identifiable {
    let id: String
    let annual: Bool
    let price: String
    let monthlyEquivalent: String?
    let savings: Int?
    var title: String { annual ? "年度会员" : "月度会员" }
    var renewal: String { "\(price)/\(annual ? "年" : "月")，确认购买后由 Apple 账户扣款；自动续订，可在 Apple 账户中取消。" }

    static func savingPercent(annual: Decimal, monthly: Decimal, sameCurrency: Bool) -> Int? {
        guard sameCurrency, annual > 0, monthly > 0, annual < monthly * 12 else { return nil }
        let percentage = NSDecimalNumber(decimal: (1 - annual / (monthly * 12)) * 100).doubleValue
        guard percentage.isFinite else { return nil }
        let value = Int(percentage.rounded(.down))
        return value > 0 ? value : nil
    }

    static func make(packages: [RevenueCat.Package]) -> [Self] {
        let monthly = packages.first { $0.packageType == .monthly }?.storeProduct
        return packages.map { package in
            let product = package.storeProduct
            let annual = package.packageType == .annual
            return Self(id: package.identifier, annual: annual, price: product.localizedPriceString,
                        monthlyEquivalent: annual ? product.localizedPricePerMonth : nil,
                        savings: annual ? monthly.flatMap {
                            savingPercent(annual: product.price, monthly: $0.price,
                                          sameCurrency: product.currencyCode != nil && product.currencyCode == $0.currencyCode)
                        } : nil)
        }.sorted { $0.annual && !$1.annual }
    }
}

struct ProAnnualGift: Decodable {
    let id: Int?
    let title: String?
    let sku: String?
    let product: String?
    let percent: Int?
    let cap_fen: Int?
    let included_pages: Int?
    let valid_days: Int?
    let ends_at: String?
    var validityText: String? {
        guard let valid_days, valid_days > 0, let ends_at else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let end = iso.date(from: ends_at) ?? ISO8601DateFormatter().date(from: ends_at) else { return nil }
        let format = DateFormatter()
        format.locale = Locale(identifier: "zh_CN")
        format.timeZone = TimeZone(identifier: "Asia/Shanghai")
        format.dateFormat = "yyyy年M月d日 HH:mm"
        return "活动截至 \(format.string(from: end))（北京时间）。抵扣券有效期取到账后 \(valid_days) 天与活动截止时间中的较晚时间；名额用完即止。"
    }
    var reward: String { percent == 50 ? "标准装订半价抵扣券" : "标准装订抵扣券" }
    var detail: String {
        var text = "指定年费首次付费赠\(reward)，适用\(product ?? "活动指定规格")"
        if let pages = included_pages { text += "，覆盖 \(pages) 页" }
        text += "，最高抵扣 \(PrintText.money(cap_fen ?? 0))。超出部分与运费另计，需另行提交印制订单。"
        return text
    }
}

struct ProSubscriptionView: View {
    let plans: [ProSubscriptionPlan]
    @Binding var selectedID: String?
    let aiIncluded: Bool
    let contentIncluded: Bool
    let gift: ProAnnualGift?
    let busy: Bool
    let canPurchase: Bool
    let status: String?
    let retryTitle: String
    let purchase: () -> Void
    let restore: () -> Void
    let retry: () -> Void
    @State private var showDetails = false

    private var selected: ProSubscriptionPlan? { plans.first { $0.id == selectedID } }
    private let ink = DiaryLibraryStyle.ink
    private let accent = DiaryLibraryStyle.accent

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero
                benefits.padding(.horizontal, 24)
                VStack(spacing: 10) {
                    ForEach(plans) { plan in planRow(plan) }
                    if plans.isEmpty {
                        Text(status ?? "正在获取 App Store 套餐…")
                            .font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
                            .frame(maxWidth: .infinity).padding(20)
                    }
                }.padding(.horizontal, 24).id("pro-plans")
                if let gift { giftCard(gift).padding(.horizontal, 24) }
                DisclosureGroup("订阅前，你可能想了解", isExpanded: $showDetails) {
                    VStack(alignment: .leading, spacing: 12) {
                        if aiIncluded {
                            Text("AI 制作按用量消耗额度，5 小时与 7 天额度分别按周期恢复；失败或取消的制作也可能消耗额度。可在制作额度中查看剩余比例与恢复时间。")
                        }
                        if contentIncluded { Text("会员内容在订阅有效期内可用，具体范围以内容页的会员标记为准。") }
                        Text("月付与年付享有相同的 Pro 数字权益。实体印制单独下单，年费赠礼以当前展示的活动规则为准。")
                        Text("无需注册即可订阅，购买由 Apple 安全处理。恢复购买请使用原购买时的 Apple 账户。")
                    }.font(.footnote).foregroundStyle(DiaryLibraryStyle.secondary)
                        .padding(.top, 12).fixedSize(horizontal: false, vertical: true)
                }.font(.subheadline).tint(ink).padding(.horizontal, 24)
                footer.padding(.bottom, 20)
            }.frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .background(DiaryLibraryStyle.background)
        .foregroundStyle(ink)
        .safeAreaInset(edge: .bottom, spacing: 0) { purchaseBar }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "book.pages")
                Text("寻寻仔").fontWeight(.semibold)
                Text("PRO").font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.5).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(accent.opacity(0.1), in: Capsule())
            }.font(.subheadline).foregroundStyle(accent)
            Text("把旅途，\n认真收藏。")
                .font(.system(.largeTitle, design: .serif, weight: .bold))
                .multilineTextAlignment(.center).lineSpacing(3)
            Text("从相册里的瞬间，到值得翻阅的每一页。")
                .font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 20)
            Image("ProSubscriptionHero").resizable().scaledToFit()
                .frame(maxHeight: 230)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 16)
                .accessibilityLabel("咖啡旅行手账成品展示，照片、文字和贴纸编排成跨页")
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("让照片有故事，让回忆有形状")
            }.font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
        }.padding(.top, 12)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("给每段旅途，多一点创作空间")
                .font(.headline)
            if aiIncluded {
                benefit("sparkles", "更多 AI 制作额度", "免费版使用 7 天基础额度；Pro 使用会员额度，同时受 5 小时和 7 天周期限制。按实际 AI 用量扣减，不是无限制作。")
            }
            if contentIncluded {
                benefit("square.stack.3d.up", "精选会员模板与素材", "使用已开放的会员内容，找到适合这段旅途的表达。")
            }
            if !aiIncluded && !contentIncluded {
                benefit("checkmark.shield", "权益以账号实时信息为准", "正在确认可用权益，确认后即可选择订阅。")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func benefit(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol).font(.system(size: 19, weight: .medium))
                .foregroundStyle(accent).frame(width: 38, height: 38)
                .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(DiaryLibraryStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.accessibilityElement(children: .combine)
    }

    private func giftCard(_ gift: ProAnnualGift) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("年费开通礼", systemImage: "gift").font(.caption.weight(.semibold))
                Spacer()
                Text("首次付费专享").font(.caption2)
            }.foregroundStyle(accent)
            Text("这一段旅途，\n也可以捧在手里。")
                .font(.system(.title3, design: .serif, weight: .semibold))
            Image("ProPrintedBook").resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("真实装订样书照片，实际内容由你的作品决定")
            Text("装订实拍 · 你的作品，也有纸上的模样")
                .font(.caption2).foregroundStyle(DiaryLibraryStyle.secondary)
            Text("赠\(gift.reward)").font(.subheadline.weight(.semibold))
            Text(gift.detail).font(.footnote).foregroundStyle(DiaryLibraryStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(gift.validityText ?? "赠礼规则正在更新，请刷新后查看完整有效期。")
                .font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(accent.opacity(0.2)))
    }

    private func planRow(_ plan: ProSubscriptionPlan) -> some View {
        let selected = selectedID == plan.id
        return Button { selectedID = plan.id } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? accent : DiaryLibraryStyle.secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 5) {
                    ViewThatFits(in: .horizontal) {
                        HStack { Text(plan.title).font(.headline); savingBadge(plan) }
                        VStack(alignment: .leading) { Text(plan.title).font(.headline); savingBadge(plan) }
                    }
                    if plan.annual, let monthly = plan.monthlyEquivalent {
                        Text("折合 \(monthly)/月 · 按年付费").font(.caption)
                            .foregroundStyle(DiaryLibraryStyle.secondary)
                        if let gift {
                            Text("首购赠装订抵扣券 · 最高 \(PrintText.money(gift.cap_fen ?? 0))")
                                .font(.caption).foregroundStyle(accent)
                        }
                    } else {
                        Text("按月付费").font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                    }
                }
                Spacer(minLength: 0)
                Text("\(plan.price)/\(plan.annual ? "年" : "月")")
                    .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? accent.opacity(0.06) : DiaryLibraryStyle.surface,
                            in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? accent : DiaryLibraryStyle.line, lineWidth: selected ? 1.5 : 1))
        }.buttonStyle(.plain).disabled(busy)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private func savingBadge(_ plan: ProSubscriptionPlan) -> some View {
        if let savings = plan.savings {
            Text("省 \(savings)%").font(.caption2.weight(.semibold))
                .foregroundStyle(accent).padding(.horizontal, 7).padding(.vertical, 3)
                .background(accent.opacity(0.1), in: Capsule())
                .accessibilityLabel("较连续月付十二个月节省百分之\(savings)")
        }
    }

    private var purchaseBar: some View {
        VStack(spacing: 9) {
            if let status, !plans.isEmpty {
                Text(status).font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: purchase) {
                HStack(spacing: 9) {
                    if busy { ProgressView().tint(.white) }
                    Text(busy ? "正在处理…" : "订阅\(selected?.title ?? " Pro")")
                        .font(.headline)
                    if !busy { Image(systemName: "arrow.right").font(.subheadline.weight(.semibold)) }
                }.frame(maxWidth: .infinity).frame(minHeight: 52)
                    .foregroundStyle(.white)
                    .background(Color(red: 156 / 255, green: 79 / 255, blue: 52 / 255), in: Capsule())
            }.buttonStyle(.plain).disabled(!canPurchase || selected == nil || busy)
                .opacity(canPurchase && selected != nil ? 1 : 0.5)
            Text(selected?.renewal ?? "价格与可售方案以 App Store 为准")
                .font(.caption2).foregroundStyle(DiaryLibraryStyle.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 10)
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
            .background(DiaryLibraryStyle.background)
            .overlay(alignment: .top) { Divider().overlay(DiaryLibraryStyle.line.opacity(0.4)) }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Button(retryTitle, action: retry).disabled(busy)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) { legalLinks }
                VStack(spacing: 0) { legalLinks }
            }
        }.font(.caption).tint(DiaryLibraryStyle.secondary)
    }

    @ViewBuilder private var legalLinks: some View {
        Button("恢复购买", action: restore).disabled(busy).frame(minHeight: 44)
        Link("使用条款", destination: AppEnvironment.current.termsOfServiceURL).frame(minHeight: 44)
        Link("隐私政策", destination: AppEnvironment.current.privacyPolicyURL).frame(minHeight: 44)
    }
}

#if DEBUG
struct ProSubscriptionPreview: View {
    @State private var selected: String? = "annual"
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ProSubscriptionView(plans: [
                .init(id: "annual", annual: true, price: "¥198.00", monthlyEquivalent: "¥16.50", savings: 45),
                .init(id: "monthly", annual: false, price: "¥30.00", monthlyEquivalent: nil, savings: nil)
            ], selectedID: $selected, aiIncluded: true, contentIncluded: true,
               gift: .init(id: 0, title: "年费开通礼", sku: nil, product: "活动指定规格", percent: 100,
                           cap_fen: 8800, included_pages: 20, valid_days: 30, ends_at: nil),
               busy: false, canPurchase: true, status: "设计预览 · 示例价格与赠礼，不可交易", retryTitle: "刷新方案",
               purchase: {}, restore: {}, retry: {})
                .navigationTitle("寻寻仔 Pro").navigationBarTitleDisplayMode(.inline)
                .task {
                    if ProcessInfo.processInfo.arguments.contains("--preview-pro-monthly") { selected = "monthly" }
                    if ProcessInfo.processInfo.arguments.contains("--preview-pro-plans") { proxy.scrollTo("pro-plans", anchor: .top) }
                }
            }
        }
    }
}
#Preview { ProSubscriptionPreview() }
#endif
