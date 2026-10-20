import Testing
import SwiftUI
@testable import TravelDiary

@MainActor
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
                            DiaryPresetLibraryScreen(ownerID: "native-search-test", showsInlineSearch: false,
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
