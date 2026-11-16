import Foundation
import Testing
@testable import TravelDiary

@MainActor
struct ProSubscriptionTests {
    @Test func membershipDatesFollowRenewalAndGracePeriod() {
        func member(renewal: String, status: String = "active", sync: String = "fresh",
                    period: String? = "2026-11-17T05:27:26Z") -> MembershipStatus {
            MembershipStatus(active: true, expires_at: "2026-11-19T05:27:26Z", period_ends_at: period,
                verified_at: nil, sync_state: sync, status: status, auto_renewal_status: renewal,
                product_id: "cn.zhaodk.TravelDiary.member.monthly", wallet_domain: "sandbox",
                sales_enabled: true, member_content_count: 0, ai_production_included: false)
        }

        let renewing = member(renewal: "will_renew").subscriptionDate
        let stopped = member(renewal: "will_not_renew").subscriptionDate
        let grace = member(renewal: "will_renew", status: "in_grace_period").subscriptionDate
        #expect(renewing?.label == "预计续费时间")
        #expect(stopped?.label == "本期权益可用至")
        #expect(grace?.label == "当前权益可用至")
        #expect(renewing?.date.addingTimeInterval(2 * 86400) == stopped?.date)
        #expect(grace?.date == stopped?.date)
        #expect(member(renewal: "will_renew", sync: "stale").subscriptionDate == nil)
        #expect(member(renewal: "will_renew", period: nil).subscriptionDate?.label == "本期权益可用至")
    }

    @Test func savingsUseActualAnnualChargeAndRoundDown() {
        #expect(ProSubscriptionPlan.savingPercent(annual: Decimal(string: "69.99")!, monthly: Decimal(string: "9.99")!, sameCurrency: true) == 41)
        #expect(ProSubscriptionPlan.savingPercent(annual: 198, monthly: 30, sameCurrency: true) == 45)
    }

    @Test func incomparableOrInvalidPricesNeverAdvertiseSavings() {
        #expect(ProSubscriptionPlan.savingPercent(annual: 100, monthly: 10, sameCurrency: false) == nil)
        #expect(ProSubscriptionPlan.savingPercent(annual: 120, monthly: 10, sameCurrency: true) == nil)
        #expect(ProSubscriptionPlan.savingPercent(annual: 150, monthly: 10, sameCurrency: true) == nil)
        #expect(ProSubscriptionPlan.savingPercent(annual: 100, monthly: 0, sameCurrency: true) == nil)
    }

    @Test func giftDoesNotPromiseFreePrintingWhenOnlyCapIsKnown() throws {
        let data = Data(#"{"id":3,"percent":100,"cap_fen":8800,"product":"不限印制规格"}"#.utf8)
        let gift = try JSONDecoder().decode(ProAnnualGift.self, from: data)
        #expect(gift.reward == "标准装订抵扣券")
        #expect(!gift.detail.contains("免费"))
        #expect(gift.detail.contains("运费另计"))
        #expect(gift.included_pages == nil)
    }
}
