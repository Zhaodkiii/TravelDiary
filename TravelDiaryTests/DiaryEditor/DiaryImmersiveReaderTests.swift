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

    @Test func doubleTapFocusesSelectedPageAndClampsVerticalEdges() throws {
        let viewport = CGSize(width: 900, height: 650)
        let spread = DiaryBookStageLayout.openSize(viewport: viewport, paperRatio: 0.7)
        let left = try #require(DiaryBookFocusLayout.rect(viewport: viewport, spread: spread,
            point: CGPoint(x: 250, y: 30)))
        let right = try #require(DiaryBookFocusLayout.rect(viewport: viewport, spread: spread,
            point: CGPoint(x: 650, y: 620)))
        #expect(left.midX < viewport.width / 2)
        #expect(right.midX > viewport.width / 2)
        #expect(left.minY >= (viewport.height - spread.height) / 2)
        #expect(right.maxY <= (viewport.height + spread.height) / 2)
        #expect(abs(left.width / left.height - viewport.width / viewport.height) < 0.001)
        #expect(DiaryBookFocusLayout.rect(viewport: viewport, spread: spread, point: .zero) == nil)
        #expect(DiaryBookFocusLayout.rect(viewport: .zero, spread: .zero, point: .zero) == nil)
    }

    @Test func onlyDuoUsesTheShelllessDeviceStyle() {
        #expect(AppleDeviceInfo.isDuo(modelIdentifier: "iPhone19,4"))
        for identifier in ["iPhone19,2", "iPhone17,2", "iPad16,6", "", "iPhone Duo"] {
            #expect(!AppleDeviceInfo.isDuo(modelIdentifier: identifier))
        }
    }

    @Test func plainPaperFillsViewportWithoutCroppingOrChangingPageRatio() {
        for viewport in [CGSize(width: 900, height: 650), CGSize(width: 844, height: 390)] {
            for ratio in [CGFloat(0.5), 0.7, 1, 1.5] {
                let size = DiaryBookStageLayout.paperSize(viewport: viewport, paperRatio: ratio)
                #expect(size.width <= viewport.width - 16 + 0.001)
                #expect(size.height <= viewport.height - 16 + 0.001)
                #expect(abs(size.width * (1 - DiaryBookSpine.halfGapFraction) / size.height - 2 * ratio) < 0.001)
                #expect(abs(size.width - viewport.width + 16) < 0.001 ||
                        abs(size.height - viewport.height + 16) < 0.001)
            }
        }
    }

    @Test func bindingVisibilityFollowsReaderStyle() throws {
        let reader = DiaryPageCurlReader(spreadCount: 2, spread: .constant(0),
            reduceMotion: true, showsBinding: false) { Paper(index: $0, canSelect: $1) }
        let coordinator = reader.makeCoordinator()
        let controller = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal)
        coordinator.installRings(in: controller)
        let rings = try #require(controller.children.first)
        #expect(rings.view.alpha == 0)
        coordinator.parent.showsBinding = true
        coordinator.updateBindingVisibility()
        #expect(rings.view.alpha == 1)
        coordinator.parent.showsBinding = false
        coordinator.updateBindingVisibility()
        #expect(rings.view.alpha == 0)
    }

    @Test func nineBindingHolesAreSymmetricInThreeEqualGroups() {
        let holes = DiaryBookSpine.ringPositions
        #expect(holes.count == 9)
        #expect(holes[4] == 0.5)
        for index in 0..<9 {
            #expect(abs(holes[index] + holes[8 - index] - 1) < 0.0001)
        }
        for start in [0, 3, 6] {
            #expect(abs(holes[start + 1] - holes[start] - 0.075) < 0.0001)
            #expect(abs(holes[start + 2] - holes[start + 1] - 0.075) < 0.0001)
        }
        #expect(DiaryBookStageLayout.paperCornerRadius == 24)
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

    @Test func suspensionKeepsBothLeavesAndDataSourceAvailable() async throws {
        let reader = DiaryPageCurlReader(spreadCount: 3, spread: .constant(1), reduceMotion: false) {
            Paper(index: $0, canSelect: $1)
        }
        let coordinator = reader.makeCoordinator()
        let controller = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal,
            options: [.spineLocation: UIPageViewController.SpineLocation.mid.rawValue])
        controller.isDoubleSided = true
        coordinator.installRings(in: controller)
        coordinator.show(1, in: controller, animated: false)
        try await Task.sleep(for: .milliseconds(100))
        let pan = try #require(controller.gestureRecognizers.first { $0 is UIPanGestureRecognizer })
        let gate = try #require(pan.delegate)

        coordinator.setZoomSuspended(true, in: controller)
        #expect(controller.dataSource === coordinator)
        #expect(gate.gestureRecognizerShouldBegin?(pan) == false)
        #expect(controller.viewControllers?.count == 2)
        let paper = try #require(controller.viewControllers?.first)
        #expect(controller.dataSource?.pageViewController(controller, viewControllerAfter: paper) != nil)

        coordinator.setZoomSuspended(false, in: controller)
        coordinator.parent = DiaryPageCurlReader(spreadCount: 3, spread: .constant(1), reduceMotion: true) {
            Paper(index: $0, canSelect: $1)
        }
        coordinator.updateMotionPolicy(in: controller)
        #expect(controller.dataSource === coordinator)
        #expect(gate.gestureRecognizerShouldBegin?(pan) == false)

        coordinator.pageViewController(controller, willTransitionTo: [])
        coordinator.parent = DiaryPageCurlReader(spreadCount: 1, spread: .constant(0), reduceMotion: false) {
            Paper(index: $0, canSelect: $1)
        }
        coordinator.show(0, in: controller, animated: false)
        #expect(controller.viewControllers?.compactMap { ($0 as? Paper)?.index } == [2, 3])
        #expect(coordinator.page(5) != nil)
        #expect(gate.gestureRecognizerShouldBegin?(pan) == false)

        coordinator.pageViewController(controller, didFinishAnimating: true,
            previousViewControllers: [], transitionCompleted: false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.viewControllers?.compactMap { ($0 as? Paper)?.index } == [0, 1])
        #expect(controller.dataSource === coordinator)
        #expect(coordinator.page(5) == nil)
    }

}
