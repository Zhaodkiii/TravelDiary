import Testing
import Foundation
import CoreGraphics
import SwiftUI
import UIKit
@testable import TravelDiary

@Suite(.serialized)
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

    @Test func bundledOnboardingSpreadsAreAvailable() {
        for index in 0..<3 {
            let image = UIImage(named: "OnboardingSpread" + String(index))
            #expect(image != nil)
            #expect((image?.size.width ?? 0) > (image?.size.height ?? 0))
        }
    }
    @Test func interruptedGuideRemainsEligibleAfterBackgroundGuestLoginStarts() {
        let name = "DiaryOnboardingTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let policy = DiaryOnboardingPolicy(defaults: defaults)
        policy.begin()
        #expect(InitialGuestEntryPolicy(defaults: defaults).consumeAutomaticEntryIfNeeded())
        #expect(DiaryOnboardingPolicy(defaults: defaults).shouldPresent)
        policy.finish()
        #expect(!DiaryOnboardingPolicy(defaults: defaults).shouldPresent)
    }

    @Test func preparedHomeWaitsForUserToFinishGuide() {
        var handoff = DiaryOnboardingHandoff()
        handoff.updateReadiness(true)
        #expect(!handoff.canDismiss)
        handoff.requestFinish()
        #expect(handoff.canDismiss)
    }

    @Test func earlyFinishKeepsGuideUntilPreparationCompletes() {
        var handoff = DiaryOnboardingHandoff()
        handoff.requestFinish()
        #expect(!handoff.canDismiss)
        handoff.updateReadiness(true)
        #expect(handoff.canDismiss)
    }

    @Test func ReadinessCanBeRevokedBeforeFinish() {
        var handoff = DiaryOnboardingHandoff()
        handoff.updateReadiness(true)
        handoff.updateReadiness(false)
        handoff.requestFinish()
        #expect(!handoff.canDismiss)
        // Offline / sign-in / preparation-error routes also report readiness,
        // giving the user their existing retry controls instead of hanging.
        handoff.updateReadiness(true)
        #expect(handoff.canDismiss)
    }

    @Test func defaultCaptureTabFinishesHandoffBehindGuideWithoutOpeningShelf() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let container = AppContainer.live(environment: .debug)
        let session = UserSession(accountID: Int64.random(in: 8_000_000...9_000_000),
                                  email: "", displayName: "Onboarding test", signedInAt: Date(),
                                  signInMethod: .device, isDeviceAccount: true)
        var handoff = DiaryOnboardingHandoff()
        handoff.requestFinish()
        let host = UIHostingController(rootView: ZStack {
            // Mount the real main coordinator with its real initial tab. A test
            // of just the handoff booleans cannot catch a missing tab callback.
            SupportMainCoordinatorView(session: session, dependencies: container.contentDependencies.coordinator,
                                       onHomeReady: { handoff.updateReadiness(true) })
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Color.white
        })
        window.rootViewController = host
        window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !handoff.canDismiss && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(handoff.canDismiss, "Default 随记 tab must signal readiness without loading the 手帐 tab")
        let tabBar = try #require(findTabBar(in: host.view))
        #expect(tabBar.selectedItem?.title == "随记")
    }

    private func findTabBar(in view: UIView) -> UITabBar? {
        if let tabBar = view as? UITabBar { return tabBar }
        return view.subviews.lazy.compactMap { findTabBar(in: $0) }.first
    }

}
