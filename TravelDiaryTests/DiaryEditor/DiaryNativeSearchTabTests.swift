import Testing
import SwiftUI
@testable import TravelDiary

@MainActor
@Suite(.serialized)
struct DiaryNativeSearchTabTests {
    private final class Driver: ObservableObject {
        @Published var tab = 0
        @Published var query = ""
    }
    private struct Host: View {
        @ObservedObject var driver: Driver
        let catalog: RemotePresetCatalog
        var body: some View {
            Group {
                TabView(selection: $driver.tab) {
                    Tab("手帐", systemImage: "book.pages", value: 0) { NavigationStack { Text("我的手帐") } }
                    Tab("模板", systemImage: "books.vertical", value: 1) {
                        NavigationStack {
                            DiaryPresetLibraryScreen(ownerID: "native-search-test",
                                initialCatalog: catalog, catalogLoader: { catalog })
                        }
                    }
                    Tab("定制", systemImage: "sparkles", value: 2) { NavigationStack { Text("定制") } }
                    Tab("设置", systemImage: "gearshape", value: 3) { NavigationStack { Text("设置") } }
                    Tab(value: 4, role: .search) {
                        NavigationStack {
                            DiaryPresetSearchScreen(ownerID: "native-search-test", searchText: $driver.query,
                                initialCatalog: catalog, catalogLoader: { catalog })
                        }
                    }
                }
                .tabViewSearchActivation(.searchTabSelection)
            }
        }
    }
    @Test func templateLibraryShowsSearchModesBeforeTyping() async throws {
        let catalog = RemotePresetCatalog(series: [], books: [])
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let host = UIHostingController(rootView: NavigationStack {
            DiaryPresetLibraryScreen(ownerID: "library-search-test", initialCatalog: catalog, catalogLoader: { catalog })
        })
        window.rootViewController = host; window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        try await Task.sleep(for: .seconds(1))
        let search = try #require(findSearchController(in: host))
        #expect(findView(UISegmentedControl.self, in: window) == nil)
        search.isActive = true
        search.searchBar.searchTextField.becomeFirstResponder()
        try await Task.sleep(for: .seconds(1))
        try capture(window, name: "template-library-search-modes")
        let modes = try #require(findView(UISegmentedControl.self, in: window))
        #expect(modes.numberOfSegments == 2)
        #expect(modes.titleForSegment(at: 0) == "整本")
        #expect(modes.titleForSegment(at: 1) == "跨页")
        #expect(search.searchBar.text?.isEmpty != false)
    }

    @Test func createSheetKeepsNativeSearchHostWithoutCatalogContent() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let presenter = UIViewController()
        window.rootViewController = presenter
        window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
        let host = UIHostingController(rootView: DiaryCreateBookSheet(ownerID: "create-search-test",
            initialCatalog: RemotePresetCatalog(series: [], books: [])) { _ in })
        defer { window.isHidden = true; previous?.makeKey() }
        presenter.present(host, animated: false)
        try await Task.sleep(for: .milliseconds(500))

        #expect(findView(UISegmentedControl.self, in: window) != nil)
        // 搜索宿主必须在紧凑面板和空目录中就存在，不能等待展开列表才创建。
        let search = try #require(findSearchController(in: host))
        let navigation = try #require(findController(UINavigationController.self, in: host))
        navigation.setNavigationBarHidden(false, animated: false)
        for _ in 0..<3 {
            host.sheetPresentationController?.animateChanges {
                host.sheetPresentationController?.selectedDetentIdentifier = .large
            }
            try await Task.sleep(for: .milliseconds(400))
            #expect(findSearchController(in: host) === search)
            search.isActive = true
            search.searchBar.searchTextField.becomeFirstResponder()
            try await Task.sleep(for: .milliseconds(400))
            #expect(search.isActive)
            #expect(findView(UISearchTextField.self, in: window) != nil)
            #expect(findView(UISegmentedControl.self, in: window) == nil)
            // 走原生取消按钮的 delegate 路径，让 SwiftUI 同步 isPresented。
            search.searchBar.delegate?.searchBarCancelButtonClicked?(search.searchBar)
            try await Task.sleep(for: .milliseconds(400))
            #expect(!search.isActive)
            #expect(findView(UISegmentedControl.self, in: window) != nil)
        }
        presenter.dismiss(animated: false)
    }

    private func findSearchController(in controller: UIViewController) -> UISearchController? {
        controller.navigationItem.searchController
            ?? controller.children.lazy.compactMap { findSearchController(in: $0) }.first
    }
    @Test func nativeSearchTabOwnsSystemSearchFieldAndKeepsResultsVertical() async throws {
        let catalog = RemotePresetCatalog(series: [.init(slug: "city", title: "城市漫游")], books: [])
        let driver = Driver()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let host = UIHostingController(rootView: Host(driver: driver, catalog: catalog))
        window.rootViewController = host; window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        try await Task.sleep(for: .seconds(1))
        let tabs = try #require(findController(UITabBarController.self, in: host))
        #expect(tabs.viewControllers?.count == 5)
        #expect(tabs.tabBar.items?.last?.image != nil)
        try capture(window, name: "native-search-entry")
        driver.tab = 4
        driver.query = "苏州"
        try await Task.sleep(for: .seconds(1))
        #expect(tabs.selectedIndex == 4)
        #expect(findView(UISearchTextField.self, in: window)?.text == "苏州")
        #expect(findView(UIScrollView.self, in: window) != nil)
        try capture(window, name: "native-search-active")
        driver.query = ""
        driver.tab = 1
        try await Task.sleep(for: .milliseconds(300))
        #expect(tabs.selectedIndex == 1)
    }
    private func findController<T: UIViewController>(_ type: T.Type, in controller: UIViewController) -> T? {
        if let found = controller as? T { return found }
        return controller.children.lazy.compactMap { findController(type, in: $0) }.first
    }
    private func findView<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let found = view as? T { return found }
        return view.subviews.lazy.compactMap { findView(type, in: $0) }.first
    }
    private func capture(_ window: UIWindow, name: String) throws {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("NativeSearchQA")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let file = folder.appendingPathComponent(name + ".png")
        try #require(image.pngData()).write(to: file)
        print("NATIVE_SEARCH_QA \(file.path)")
    }
}
