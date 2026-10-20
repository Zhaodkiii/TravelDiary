import Testing
import Foundation
import SwiftUI
import UIKit
@testable import TravelDiary

@MainActor
struct DiaryLibraryTests {
    @Test func emptyCurlStillProvidesOneCompleteSpread() {
        let reader = DiaryPageCurlReader(spreadCount: 0, spread: .constant(0), reduceMotion: false) { _, _ in UIViewController() }
        let coordinator = reader.makeCoordinator()
        #expect(coordinator.page(0) != nil)
        #expect(coordinator.page(1) != nil)
        #expect(coordinator.page(-1) == nil)
        #expect(coordinator.page(2) == nil)
    }

    @Test func curlMotionPolicyLetsUIKitManageNavigation() {
        let reader = DiaryPageCurlReader(spreadCount: 2, spread: .constant(0), reduceMotion: false) { _, _ in UIViewController() }
        let coordinator = reader.makeCoordinator()
        let controller = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal,
            options: [.spineLocation: UIPageViewController.SpineLocation.mid.rawValue])
        controller.isDoubleSided = true
        controller.dataSource = coordinator
        controller.setViewControllers([UIViewController(), UIViewController()], direction: .forward, animated: false)
        let gestures = controller.gestureRecognizers
        #expect(!gestures.isEmpty)
        gestures.forEach { $0.isEnabled = false }
        coordinator.updateMotionPolicy(in: controller)
        #expect(gestures.allSatisfy { !$0.isEnabled })
        coordinator.parent = DiaryPageCurlReader(spreadCount: 2, spread: .constant(0), reduceMotion: true) { _, _ in UIViewController() }
        coordinator.updateMotionPolicy(in: controller)
        #expect(controller.dataSource == nil)
        coordinator.parent = reader
        coordinator.updateMotionPolicy(in: controller)
        #expect(controller.dataSource === coordinator)
        #expect(controller.gestureRecognizers.compactMap { $0 as? UITapGestureRecognizer }.allSatisfy { !$0.isEnabled })
    }

    private final class CurlTestPaper: UIViewController, DiaryIndexedPaper {
        let index: Int
        init(index: Int) {
            self.index = index
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("Not supported") }
    }

    private func curlController(_ coordinator: DiaryPageCurlReader.Coordinator) -> UIPageViewController {
        let controller = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal,
            options: [.spineLocation: UIPageViewController.SpineLocation.mid.rawValue])
        controller.isDoubleSided = true
        controller.delegate = coordinator
        return controller
    }

    private func finishCurlCallbacks() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test func curlClampsInvalidTargetsAndKeepsCompleteSpreads() async throws {
        let reader = DiaryPageCurlReader(spreadCount: 2, spread: .constant(99), reduceMotion: false) { index, _ in CurlTestPaper(index: index) }
        let coordinator = reader.makeCoordinator()
        let controller = curlController(coordinator)
        coordinator.show(99, in: controller, animated: false)
        await finishCurlCallbacks()
        #expect(controller.viewControllers?.compactMap { ($0 as? CurlTestPaper)?.index } == [2, 3])
        #expect(coordinator.pageViewController(controller, viewControllerAfter: try #require(coordinator.page(3))) == nil)
        #expect(coordinator.pageViewController(controller, viewControllerBefore: try #require(coordinator.page(0))) == nil)
        #expect(coordinator.page(2) === coordinator.page(2))
    }

    @Test func curlFreezesPagesDuringTransitionThenAppliesLatestTarget() async {
        var target = 0
        let selection = Binding(get: { target }, set: { target = $0 })
        let reader = DiaryPageCurlReader(spreadCount: 3, spread: selection, reduceMotion: false) { index, _ in CurlTestPaper(index: index) }
        let coordinator = reader.makeCoordinator()
        let controller = curlController(coordinator)
        coordinator.show(0, in: controller, animated: false)
        #expect(controller.dataSource == nil)
        target = 1
        coordinator.parent = DiaryPageCurlReader(spreadCount: 2, spread: selection, reduceMotion: true) { index, _ in CurlTestPaper(index: index) }
        coordinator.show(1, in: controller, animated: false)
        #expect(coordinator.page(5) != nil)
        await finishCurlCallbacks()
        await finishCurlCallbacks()
        #expect(coordinator.page(5) == nil)
        #expect(controller.viewControllers?.compactMap { ($0 as? CurlTestPaper)?.index } == [2, 3])
        #expect(controller.dataSource == nil)
        coordinator.parent = DiaryPageCurlReader(spreadCount: 2, spread: selection, reduceMotion: false) { index, _ in CurlTestPaper(index: index) }
        coordinator.updateMotionPolicy(in: controller)
        #expect(controller.dataSource === coordinator)
        coordinator.setZoomSuspended(true, in: controller)
        #expect(controller.dataSource == nil)
        coordinator.setZoomSuspended(false, in: controller)
        #expect(controller.dataSource === coordinator)
    }

    @Test func curlDefersNavigationPolicyUntilInteractiveTurnFinishes() async {
        let reader = DiaryPageCurlReader(spreadCount: 2, spread: .constant(0), reduceMotion: false) { index, _ in CurlTestPaper(index: index) }
        let coordinator = reader.makeCoordinator()
        let controller = curlController(coordinator)
        coordinator.show(0, in: controller, animated: false)
        await finishCurlCallbacks()
        coordinator.pageViewController(controller, willTransitionTo: [])
        coordinator.setZoomSuspended(true, in: controller)
        #expect(controller.dataSource === coordinator)
        coordinator.pageViewController(controller, didFinishAnimating: true, previousViewControllers: [], transitionCompleted: false)
        #expect(controller.dataSource === coordinator)
        await finishCurlCallbacks()
        #expect(controller.dataSource == nil)
        #expect(controller.viewControllers?.compactMap { ($0 as? CurlTestPaper)?.index } == [0, 1])
    }

    @Test func libraryColorsResolveOffMainActorInBothAppearances() async {
        // 在主线程创建 SwiftUI/UIKit 桥接颜色，再在后台解析，复现 AsyncRenderer 的调用边界。
        let colors = [DiaryLibraryStyle.background, DiaryLibraryStyle.surface,
                      DiaryLibraryStyle.ink, DiaryLibraryStyle.secondary,
                      DiaryLibraryStyle.accent, DiaryLibraryStyle.line].map { UIColor($0) }
        let resolved = await Task.detached { @Sendable in Self.resolveColors(colors) }.value
        #expect(resolved.0)
        #expect(resolved.1 == [0xF7F5F0, 0xFFFEFB, 0x292622, 0x706A62, 0x9C4F34, 0xDDD7CE,
                               0x1C1B19, 0x282622, 0xF2EEE7, 0xBDB6AC, 0xE9AA8E, 0x49433B])
    }

    private nonisolated static func resolveColors(_ colors: [UIColor]) -> (Bool, [UInt32]) {
        let isBackground = !Thread.isMainThread
        let values = [UIUserInterfaceStyle.light, .dark].flatMap { style in
            colors.map { color -> UInt32 in
                let value = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                guard value.getRed(&r, green: &g, blue: &b, alpha: &a) else { return UInt32.max }
                return (UInt32((r * 255).rounded()) << 16)
                    | (UInt32((g * 255).rounded()) << 8) | UInt32((b * 255).rounded())
            }
        }
        return (isBackground, values)
    }

    @Test func magazinePreviewKeepsReaderPairingAndSkipsCoverAndShell() {
        #expect(DiaryMagazineSpreadSelection.select(pageIDs: ["shell", "cover", "a", "b", "c", "d", "e"], shellID: "shell", coverID: "cover") == [["a", "b"], ["c", "d"]])
        // 不先过滤封面再重排，否则所有左右页都会错位。
        #expect(DiaryMagazineSpreadSelection.select(pageIDs: ["first", "cover", "a", "b", "c"], shellID: nil, coverID: "cover") == [["b", "c"]])
        #expect(DiaryMagazineSpreadSelection.select(pageIDs: ["cover", "a", "b", "c"], shellID: nil, coverID: "cover") == [["a", "b"], ["c"]])
        #expect(DiaryMagazineSpreadSelection.select(pageIDs: ["shell", "cover"], shellID: "shell", coverID: "cover").isEmpty)
        #expect(DiaryMagazineSpreadSelection.select(pageIDs: [], shellID: nil, coverID: nil).isEmpty)
    }

    @Test func accessRecordsAreIsolatedAndResumeByIdentity() throws {
        let suite = "DiaryLibraryTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = DiaryBookAccessStore(ownerID: "first", defaults: defaults)
        let second = DiaryBookAccessStore(ownerID: "second", defaults: defaults)
        var book = DiaryBook(title: "旅途")
        let shell = DiaryPageEntry(id: UUID(), title: "外壳", revisionID: UUID(), size: book.defaultPageSize)
        let a = DiaryPageEntry(id: UUID(), title: "第一页", revisionID: UUID(), size: book.defaultPageSize)
        let b = DiaryPageEntry(id: UUID(), title: "第二页", revisionID: UUID(), size: book.defaultPageSize)
        book.pages = [shell, a, b]; book.shellPageID = shell.id
        let timestamp = book.updatedAt
        first.record(bookID: book.id, pageID: b.id)
        #expect(second.records.isEmpty)
        #expect(book.updatedAt == timestamp)
        #expect(first.latest(in: [book])?.pageID == b.id)
        book.pages = [shell, b, a]
        #expect(DiaryBookAccessStore.resumePage(in: book, preferred: b.id)?.id == b.id)
        book.pages = [shell, a]
        #expect(DiaryBookAccessStore.resumePage(in: book, preferred: b.id)?.id == a.id)
        book.pages = [shell]
        #expect(DiaryBookAccessStore.resumePage(in: book, preferred: b.id) == nil)
        first.remove(book.id)
        #expect(first.records.isEmpty)
    }

    @Test func openingEditorRecordsAccessWithoutOpeningAnyTool() async throws {
        let owner = "editor-lifecycle-\(UUID())"
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = DiaryDocumentStore(ownerID: owner, baseDirectory: folder)
        let book = try await library.createBook(title: "访问记录")
        let store = DiaryDocumentStore(ownerID: owner, baseDirectory: folder, bookID: book.id)
        var document = DiaryDocument(); document.bookID = book.id
        try await store.save(document)
        let loaded = try await store.load(document.id)
        let session = DiaryEditorSession(document: loaded.document, images: loaded.images, store: store)
        let access = DiaryBookAccessStore(ownerID: owner)
        defer { access.remove(book.id) }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: DiaryEditorScreen(session: session))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        for _ in 0..<20 {
            if access.records.first?.pageID == document.id { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(access.records.first?.bookID == book.id)
        #expect(access.records.first?.pageID == document.id)
    }

    @Test func shelfSortFiltersWhitespaceAndKeepsStableTies() {
        let date = Date(timeIntervalSince1970: 10)
        var a = DiaryBook(title: "苏州春日"), b = DiaryBook(title: "海岛")
        a.updatedAt = date; b.updatedAt = date
        #expect(DiaryShelfSort.updated.apply(to: [a, b], search: "  苏州  ").map(\.id) == [a.id])
        #expect(DiaryShelfSort.updated.apply(to: [a, b], search: "").map(\.id) == DiaryShelfSort.updated.apply(to: [b, a], search: "").map(\.id))
    }

    @Test func oldCatalogDecodesAndFiltersCompose() throws {
        let raw = #"{"series":[],"books":[{"id":"one","title":"海岛旅行","series":"island","version":2,"page_count":3,"cover_url":"https://example.com/cover.jpg"}]}"#
        let catalog = try JSONDecoder().decode(RemotePresetCatalog.self, from: Data(raw.utf8))
        #expect(catalog.books[0].content_page_count == nil)
        var remote = catalog.books[0]
        remote.style_tags = ["拼贴", "复古"]; remote.usage_tags = ["照片墙"]
        let item = try #require(PresetLibraryItem.merge(local: [], remote: [remote, remote]).first)
        #expect(PresetLibraryItem.merge(local: [], remote: [remote, remote]).count == 1)
        #expect(item.matches(search: " 海岛 ", series: "island", styles: ["拼贴", "极简"], usages: ["照片墙"]))
        #expect(!item.matches(search: "海岛", series: "island", styles: ["拼贴"], usages: ["路线"]))
        #expect(!item.matches(search: "苏州", series: "", styles: [], usages: []))
        let roundtrip = try JSONDecoder().decode(RemotePresetCatalog.self, from: JSONEncoder().encode(catalog))
        #expect(roundtrip.books[0].version == 2)
    }

    @Test func remoteVersionDoesNotDisappearBehindBundledVersion() throws {
        let packages = try BundleDiaryPresetProvider(root: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/DiaryPresets.bundle")).catalog().books
        let local = try #require(packages.first)
        let new = RemotePresetBook(id: local.id, title: "新版", series: local.manifest.seriesID,
                                   version: local.manifest.packageVersion + 1, page_count: 10, cover_url: "https://example.com/cover")
        let items = PresetLibraryItem.merge(local: [local], remote: [new])
        #expect(items.count == 1)
        #expect(items[0].version == new.version)
        #expect(items[0].local == nil)
        #expect(items[0].title == "新版")
        let offline = PresetLibraryItem.merge(local: [local], remote: [new], preferLocal: true)
        #expect(offline[0].version == local.manifest.packageVersion)
        #expect(offline[0].remote == nil)
        let same = RemotePresetBook(id: local.id, title: "相同版", series: local.manifest.seriesID,
                                    version: local.manifest.packageVersion, page_count: local.manifest.pages.count, cover_url: "https://example.com/cover")
        #expect(PresetLibraryItem.merge(local: [local], remote: [same])[0].local != nil)
    }

    @Test func shelfRecoversHealthyBooksWithoutDeletingCorruptBook() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = DiaryDocumentStore(ownerID: "shelf-test", baseDirectory: folder)
        let healthy = try await store.createBook(title: "有效作品")
        let brokenID = UUID()
        let broken = StoragePaths(support: folder, caches: folder.appendingPathComponent("Caches"), temporary: folder.appendingPathComponent("Temporary")).books("shelf-test").appendingPathComponent(brokenID.uuidString)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: broken.appendingPathComponent("book.json"))
        let result = try await store.loadShelf()
        #expect(result.books.map(\.id) == [healthy.id])
        #expect(result.unreadableIDs == [brokenID])
        #expect(FileManager.default.fileExists(atPath: broken.path))
    }
}
