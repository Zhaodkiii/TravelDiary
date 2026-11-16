import Foundation
import Testing
@testable import TravelDiary

@MainActor
struct ProSubscriptionTests {
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
