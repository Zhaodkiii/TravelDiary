import Testing
import Foundation
import CoreGraphics
@testable import TravelDiary

@MainActor
struct DiaryOnboardingTests {
    @Test func testNewInstallationAndInterruptedGuideRemainEligible() {
        let name = "DiaryOnboardingTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(DiaryOnboardingPolicy(defaults: defaults).shouldPresent)
        // Merely displaying the guide must not consume first-launch eligibility.
        #expect(DiaryOnboardingPolicy(defaults: defaults).shouldPresent)
    }

    @Test func testFinishOrSkipPersistsAcrossPolicyInstances() {
        let name = "DiaryOnboardingTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        DiaryOnboardingPolicy(defaults: defaults).finish()
        #expect(!(DiaryOnboardingPolicy(defaults: defaults).shouldPresent))
        #expect(InitialGuestEntryPolicy(defaults: defaults).canAttemptAutomaticEntry)
    }

    @Test func testExistingUsersAreNotForcedThroughNewGuide() {
        let name = "DiaryOnboardingTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        InitialGuestEntryPolicy(defaults: defaults).markExistingSession()
        #expect(!(DiaryOnboardingPolicy(defaults: defaults).shouldPresent))
    }

    @Test func testBundledSampleRendersAllConstructionStages() async throws {
        let artwork = try await DiaryOnboardingArtwork.load()
        #expect(artwork.size == CGSize(width: 4370, height: 3130))
        #expect(artwork.pieces.filter { $0.stage == 1 }.count == 1)
        #expect(artwork.pieces.filter { $0.stage == 2 }.count == 6)
        #expect(artwork.pieces.filter { $0.stage == 3 }.count == 6)
        #expect(artwork.pieces.filter { $0.stage == 4 }.count == 10)
        #expect(artwork.pieces.allSatisfy { $0.image.size.width > 0 && $0.image.size.height > 0 })
    }
}
