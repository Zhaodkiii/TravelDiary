import Testing
import SwiftUI
import UIKit
import SafariServices
@testable import TravelDiary

@MainActor
struct LoginPresentationTests {
    @Test func legalDocumentIdentityIsStableAndSafariCloseFinishesPresentation() throws {
        let url = try #require(URL(string: "https://example.com/terms"))
        #expect(IdentifiableURL(url: url).id == IdentifiableURL(url: url).id)
        var presented: IdentifiableURL? = IdentifiableURL(url: url)
        let coordinator = SafariWebViewSheet.Coordinator(onFinish: { presented = nil })
        let controller = SFSafariViewController(url: url)
        coordinator.safariViewControllerDidFinish(controller)
        #expect(presented == nil)
        // 关闭后只有再次主动选择才创建下一次展示。
        presented = IdentifiableURL(url: url)
        #expect(presented?.url == url)
    }

    @Test func journalPreparationCanRetryAfterFailure() async {
        let registry = SignedInSessionPreparationRegistry()
        var attempts = 0
        await registry.runPreparationIfNeeded(accountID: 42) {
            attempts += 1
            registry.rollbackPreparingIfNeeded(accountID: 42)
        }
        #expect(registry.preparedAccountID == nil)
        await registry.runPreparationIfNeeded(accountID: 42) {
            attempts += 1
            registry.markPrepared(accountID: 42)
        }
        #expect(registry.preparedAccountID == 42)
        await registry.runPreparationIfNeeded(accountID: 42) { attempts += 1 }
        #expect(attempts == 2)
    }

    @Test func openingBookAnimatesAndReducedMotionIsStatic() throws {
        func render(_ time: Double, settled: Bool) throws -> Data {
            let renderer = ImageRenderer(content: DiaryLaunchBook(elapsed: time, settled: settled)
                .padding(24).background(DiaryLibraryStyle.background))
            return try #require(renderer.uiImage?.pngData())
        }
        #expect(try render(0, settled: false) != render(1.4, settled: false))
        #expect(try render(0, settled: true) == render(1.4, settled: true))

    }

    @Test func consentRequiresCurrentNoticeAndCanBeRevoked() throws {
        let suite = "LoginConsentTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "auth.login.initial_legal_prompt_accepted")
        let store = LoginConsentStore(defaults: defaults)
        #expect(!store.isAccepted)
        defaults.set("older-travel-notice", forKey: "auth.login.legal.accepted_version")
        #expect(!store.isAccepted)
        store.accept(at: Date(timeIntervalSince1970: 1234))
        #expect(store.isAccepted)
        #expect(defaults.double(forKey: "auth.login.legal.accepted_at") == 1234)
        store.revoke()
        #expect(!store.isAccepted)
        #expect(defaults.object(forKey: "auth.login.initial_legal_prompt_accepted") == nil)
    }

    @Test func legalAndArtworkRenderInSmallAndAccessibleLayouts() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("LoginDesignVerification")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, size, scheme, type) in [
            ("legal-light", CGSize(width: 375, height: 667), ColorScheme.light, DynamicTypeSize.large),
            ("legal-dark-large", CGSize(width: 375, height: 812), ColorScheme.dark, DynamicTypeSize.accessibility3)
        ] {
            let content = LoginAgreementSheet(onDecline: {}, onAgree: {})
                .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, type)
            let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height))
            renderer.scale = 2
            let image = try #require(renderer.uiImage)
            #expect(image.size == size)
            let data = try #require(image.pngData())
            try data.write(to: output.appendingPathComponent(name + ".png"))
        }
        let artwork = ImageRenderer(content: LoginTravelArtwork().frame(width: 330, height: 220).background(DiaryLibraryStyle.background))
        #expect(artwork.uiImage != nil)
        print("Login visual artifacts: \(output.path)")
    }
}
