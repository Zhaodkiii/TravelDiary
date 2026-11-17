import SwiftUI
import XCTest
@testable import TravelDiary

/// Renders the shipping SwiftUI views with deterministic fixtures, without StoreKit transactions.
nonisolated final class ProSubscriptionScreenshotTests: XCTestCase {
    @MainActor func testSubscriptionScreenshots() async throws {
        for annual in [true, false] {
            try await capture(PaywallFixture(annual: annual), name: annual ? "annual-paywall" : "monthly-paywall")
        }
        try await capture(ProMembershipPreview(), name: "active-membership")
    }

    @MainActor private func capture<V: View>(_ view: V, name: String) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 414, height: 896)
        let host = UIHostingController(rootView: view.environment(\.locale, Locale(identifier: "zh_Hans_CN")).environment(\.colorScheme, .light))
        window.rootViewController = host
        window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(for: .seconds(1))
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        let result = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let cg = try XCTUnwrap(result.cgImage)
        XCTAssertEqual(cg.width, 1242)
        XCTAssertEqual(cg.height, 2688)
        let bytes = try XCTUnwrap(cg.dataProvider?.data)
        let pointer = try XCTUnwrap(CFDataGetBytePtr(bytes))
        let samples = stride(from: 0, to: CFDataGetLength(bytes), by: 127).map { pointer[$0] }
        XCTAssertGreaterThan(Set(samples).count, 8, "The screenshot must contain rendered UI.")
        let attachment = XCTAttachment(image: result)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let directory = URL.documentsDirectory.appendingPathComponent("SubscriptionReviewScreenshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(result.pngData()).write(to: directory.appendingPathComponent(name + ".png"))
    }
}

private struct PaywallFixture: View {
    let annual: Bool
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ProSubscriptionView(plans: [
                    .init(id: "annual", annual: true, price: "¥128.00", monthlyEquivalent: "¥10.67", savings: 40),
                    .init(id: "monthly", annual: false, price: "¥18.00", monthlyEquivalent: nil, savings: nil)
                ], selectedID: .constant(annual ? "annual" : "monthly"), aiIncluded: true, contentIncluded: true,
                    gift: nil, busy: false, canPurchase: true,
                    status: "自动化界面测试 · 测试数据，不执行交易", retryTitle: "同步会员状态",
                    purchase: {}, restore: {}, retry: {})
                    .navigationTitle("寻寻仔 Pro").navigationBarTitleDisplayMode(.inline)
                    .task {
                        try? await Task.sleep(for: .milliseconds(150))
                        proxy.scrollTo("pro-plans", anchor: .top)
                    }
            }
        }
    }
}
