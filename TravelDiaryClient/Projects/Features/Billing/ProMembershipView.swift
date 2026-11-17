import StoreKit
import SwiftUI
import UIKit

struct ProMembershipView: View {
    let owner: String
    let member: MembershipStatus
    let busy: Bool
    let confirming: Bool
    let notice: String?
    let retryTitle: String
    let refresh: () async -> Void
    let restore: () async -> Void

    @ObservedObject private var production = DiaryProductionService.shared
    @State private var availableCoupons = 0
    @State private var openingSandboxManagement = false
    @State private var showsSandboxManagementError = false

    private let sandboxSettingsPath = "设置 → 开发者 → 沙盒 Apple 账户 → 管理"

    private var inGracePeriod: Bool { member.status == "in_grace_period" }
    private var quotaSummary: String {
        guard production.owner == owner, let quota = production.quota, quota.plan == "pro", !quota.windows.isEmpty else {
            return "查看剩余额度和恢复时间"
        }
        return quota.windows.map { window in
            let cycle = window.kind == "short" ? "5 小时" : "7 天"
            return "\(cycle)\(DiaryProductionQuotaSection.remainingText(window.remainingRatio))"
        }.joined(separator: " · ")
    }

    var body: some View {
        SupportCanvas {
            subscriptionCard
            if member.active { benefits }
            support
        }
        .refreshable {
            await refresh()
            await loadCoupons()
        }
        .task(id: member.active && member.wallet_domain == "production" ? owner : nil) { await loadCoupons() }
        .alert("暂时无法打开沙盒订阅管理", isPresented: $showsSandboxManagementError) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请在使用购买时同一沙盒 Apple 账户的设备上前往「\(sandboxSettingsPath)」。")
        }
    }

    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("寻寻仔 Pro", systemImage: "book.pages")
                .font(.title2.weight(.bold))
                .foregroundStyle(DiaryLibraryStyle.accent)

            VStack(alignment: .leading, spacing: 6) {
                Text(confirming ? "正在确认订阅状态" : member.active ? "会员已开通" : member.title)
                    .font(.title.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                if member.active {
                    Text("\(member.planName) · Apple App Store")
                        .font(.subheadline)
                        .foregroundStyle(DiaryLibraryStyle.secondary)
                }
            }

            if member.wallet_domain == "sandbox" {
                Label("沙盒测试订阅 · 续订周期已加速", systemImage: "testtube.2")
                    .font(.caption)
                    .foregroundStyle(DiaryLibraryStyle.secondary)
            }

            if !confirming && member.active {
                renewalDetails
            }

            if let notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(DiaryLibraryStyle.secondary)
            }

            if confirming {
                Button(retryTitle) { Task { await refresh() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy)
            }

            subscriptionManagement
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DiaryLibraryStyle.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(DiaryLibraryStyle.accent.opacity(0.25)))
    }

    @ViewBuilder private var subscriptionManagement: some View {
        switch member.wallet_domain {
        case "xcode":
            Text("本地测试订阅。制作额度与赠券仍由服务器管理。可在 Xcode 的 StoreKit 交易管理器中测试到期、退款与续订。")
                .font(.footnote).foregroundStyle(DiaryLibraryStyle.secondary)
        case "sandbox":
            Button {
                Task { await openSandboxManagement() }
            } label: {
                Label("管理沙盒订阅", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.bordered)
            .disabled(busy || openingSandboxManagement)

            DisclosureGroup("找不到测试订阅？") {
                Text("使用购买时的沙盒 Apple 账户，前往「\(sandboxSettingsPath)」。")
                    .padding(.top, 6)
            }
            .font(.footnote)
            .foregroundStyle(DiaryLibraryStyle.secondary)
        case "production":
            Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                Label("管理 Apple 订阅", systemImage: "arrow.up.right")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.bordered)
        default:
            EmptyView()
        }
    }

    private func openSandboxManagement() async {
        guard !busy, !openingSandboxManagement else { return }
        let foregroundScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        guard let scene = foregroundScenes.first(where: { $0.keyWindow != nil }) else {
            showsSandboxManagementError = true
            return
        }

        openingSandboxManagement = true
        defer { openingSandboxManagement = false }
        do {
            try await AppStore.showManageSubscriptions(in: scene)
            await refresh()
        } catch {
            showsSandboxManagementError = true
        }
    }

    private var renewalDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            if inGracePeriod {
                Label("付款待处理，会员仍可用", systemImage: "exclamationmark.circle")
                    .font(.subheadline.weight(.semibold))
                Text("请在 Apple 账户中更新付款方式。")
                    .font(.footnote)
                    .foregroundStyle(DiaryLibraryStyle.secondary)
            } else {
                let renewal = member.auto_renewal_status
                let description = switch renewal {
                case "will_renew": "自动续订已开启"
                case "will_not_renew": "已关闭自动续订"
                default: "请在 Apple 账户中查看续订设置"
                }
                Text(description).font(.subheadline.weight(.semibold))
            }
            if let details = member.subscriptionDate {
                Text(details.label)
                    .font(.footnote)
                    .foregroundStyle(DiaryLibraryStyle.secondary)
                Text(details.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline.monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var benefits: some View {
        if member.ai_production_included == true || member.member_content_count > 0 || availableCoupons > 0 {
            VStack(alignment: .leading, spacing: 10) {
                Text("我的权益").font(.headline).accessibilityAddTraits(.isHeader)
                if member.ai_production_included == true {
                    NavigationLink {
                        Form { DiaryProductionQuotaSection() }.navigationTitle("AI 制作额度")
                    } label: {
                        SupportNavigationRow(title: "AI 制作额度", symbol: "sparkles", detail: quotaSummary)
                    }
                    .buttonStyle(.plain).feedbackPaperCard()
                }
                if member.member_content_count > 0 {
                    NavigationLink {
                        DiaryPresetLibraryScreen(ownerID: owner)
                    } label: {
                        SupportNavigationRow(title: "会员模板与素材", symbol: "square.stack",
                            detail: "浏览模板与素材，查看会员可用内容")
                    }
                    .buttonStyle(.plain).feedbackPaperCard()
                }
                if availableCoupons > 0 {
                    NavigationLink {
                        PrintCouponWallet(owner: owner)
                    } label: {
                        SupportNavigationRow(title: "印制优惠券", symbol: "ticket", detail: "查看可用的印制优惠券",
                            badge: "\(availableCoupons) 张可用")
                    }
                    .buttonStyle(.plain).feedbackPaperCard()
                }
            }
        }
    }

    private var support: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("订阅帮助").font(.headline).accessibilityAddTraits(.isHeader)
            if !confirming {
                Button(retryTitle, systemImage: "arrow.clockwise") { Task { await refresh() } }
                    .frame(minHeight: 44)
            }
            Button("恢复购买", systemImage: "arrow.trianglehead.clockwise.rotate.90") { Task { await restore() } }
                .frame(minHeight: 44)
        }
        .font(.subheadline)
        .disabled(busy)
    }

    private func loadCoupons() async {
        guard member.active, member.wallet_domain == "production" else {
            availableCoupons = 0
            return
        }
        let items: [PrintCouponWallet.Item]? = try? await PrintOrderService.shared.request("coupons/mine/", owner: owner)
        guard !Task.isCancelled else { return }
        availableCoupons = items?.count(where: { $0.state == "可用" }) ?? 0
    }
}

#if DEBUG
struct ProMembershipPreview: View {
    var body: some View {
        let member = MembershipStatus(active: true, expires_at: "2026-11-17T05:27:40Z",
            period_ends_at: "2026-11-17T05:27:26Z", verified_at: nil, sync_state: "fresh",
            status: "active", auto_renewal_status: "will_renew",
            product_id: "cn.zhaodk.TravelDiary.member.monthly", wallet_domain: "sandbox",
            sales_enabled: true, member_content_count: 1, ai_production_included: true)
        NavigationStack {
            ProMembershipView(owner: "preview", member: member, busy: false, confirming: false,
                notice: nil, retryTitle: "同步会员状态", refresh: {}, restore: {})
                .navigationTitle("我的 Pro")
        }
    }
}

#Preview { ProMembershipPreview() }
#endif
