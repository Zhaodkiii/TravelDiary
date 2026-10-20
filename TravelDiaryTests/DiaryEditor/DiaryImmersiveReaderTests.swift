import Testing
import SwiftUI
import UIKit
@testable import TravelDiary

@MainActor
struct DiaryImmersiveReaderTests {
    private final class Paper: UIViewController, DiaryIndexedPaper {
        let index: Int
        let canSelect: () -> Bool
        init(index: Int, canSelect: @escaping () -> Bool) {
            self.index = index
            self.canSelect = canSelect
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError() }
    }

    @Test func fullSpreadFitsPortraitAndLandscapeWithoutCropping() {
        for viewport in [CGSize(width: 390, height: 600), CGSize(width: 750, height: 350)] {
            for ratio in [CGFloat(0.5), 0.75, 1.0, 1.5] {
                let size = DiaryBookStageLayout.openSize(viewport: viewport, paperRatio: ratio)
                #expect(size.width <= viewport.width - 24 + 0.001)
                #expect(size.height <= viewport.height - 24 + 0.001)
                #expect(abs(size.width - (viewport.width - 24)) < 0.001 ||
                        abs(size.height - (viewport.height - 24)) < 0.001)
            }
        }
    }

    @Test func cachedPageActionsUseCurrentReadingMode() throws {
        let reader = DiaryPageCurlReader(spreadCount: 3, spread: .constant(1), reduceMotion: false) {
            Paper(index: $0, canSelect: $1)
        }
        let coordinator = reader.makeCoordinator()
        let paper = try #require(coordinator.page(2) as? Paper)
        #expect(paper.canSelect())
        coordinator.parent.allowsPageActions = false
        #expect(!paper.canSelect())
        coordinator.parent.allowsPageActions = true
        #expect(paper.canSelect())
    }

    @Test func immersiveReaderStopsBeforeSyntheticAddSpread() {
        let reader = DiaryPageCurlReader(spreadCount: 3, spread: .constant(2), reduceMotion: false,
                                        allowsPageActions: false) {
            Paper(index: $0, canSelect: $1)
        }
        let coordinator = reader.makeCoordinator()
        #expect(coordinator.page(5) != nil)
        #expect(coordinator.page(6) == nil)
        #expect(coordinator.page(-1) == nil)
    }

    @Test func readOnlyModePreservesNativePanAndDisablesEditing() async throws {
        let reader = DiaryPageCurlReader(spreadCount: 3, spread: .constant(1), reduceMotion: false,
                                        allowsPageActions: false) {
            Paper(index: $0, canSelect: $1)
        }
        let coordinator = reader.makeCoordinator()
        let controller = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal,
            options: [.spineLocation: UIPageViewController.SpineLocation.mid.rawValue])
        controller.isDoubleSided = true
        coordinator.installRings(in: controller)
        coordinator.show(1, in: controller, animated: false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.dataSource === coordinator)
        let pans = controller.gestureRecognizers.compactMap { $0 as? UIPanGestureRecognizer }
        #expect(!pans.isEmpty)
        #expect(pans.allSatisfy { $0.isEnabled && $0.maximumNumberOfTouches == 1 })
        let paper = try #require(coordinator.page(2) as? Paper)
        #expect(!paper.canSelect())
        #expect(coordinator.pageViewController(controller, viewControllerBefore: paper) != nil)
        #expect(coordinator.pageViewController(controller, viewControllerAfter: paper) != nil)
    }

    @Test func readOnlyReaderRestoresInteractiveNavigationAfterEachTurn() async throws {
        final class Position { var spread = 0 }
        let position = Position()
        let reader = DiaryPageCurlReader(spreadCount: 3,
            spread: Binding(get: { position.spread }, set: { position.spread = $0 }),
            reduceMotion: false, allowsPageActions: false) {
                Paper(index: $0, canSelect: $1)
            }
        let coordinator = reader.makeCoordinator()
        let controller = DiaryCurlPageViewController(transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: UIPageViewController.SpineLocation.mid.rawValue])
        controller.isDoubleSided = true
        controller.delegate = coordinator
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        coordinator.installRings(in: controller)
        coordinator.show(0, in: controller, animated: false)
        try await Task.sleep(for: .milliseconds(100))
        for spread in [1, 2, 1, 0] {
            position.spread = spread
            coordinator.show(spread, in: controller, animated: true)
            try await Task.sleep(for: .milliseconds(700))
            let indices = controller.viewControllers?.compactMap { ($0 as? Paper)?.index }
            #expect(indices == [spread * 2, spread * 2 + 1])
            #expect(controller.dataSource === coordinator)
        }
    }

}
