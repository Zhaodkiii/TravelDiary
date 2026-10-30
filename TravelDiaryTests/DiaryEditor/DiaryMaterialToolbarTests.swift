import Testing
import SwiftUI
@testable import TravelDiary

@MainActor
@Suite(.serialized)
struct DiaryMaterialToolbarTests {
    @Test func filterRequestsReachOnlyTheirCatalogAndAreConsumedOnce() {
        let state = DiaryMaterialToolbarState()
        state.category = .albums
        state.requestFilters()
        #expect(!state.consumeFilterRequest(contentKind: "journal"))
        #expect(state.consumeFilterRequest(contentKind: "album"))
        #expect(!state.consumeFilterRequest(contentKind: "album"))

        state.category = .stickers
        state.requestFilters()
        #expect(state.filterRequest == nil)
    }

    @Test func filterIndicatorFollowsTheSelectedCatalog() {
        let state = DiaryMaterialToolbarState()
        state.setFiltersActive(true, contentKind: "journal")
        #expect(state.hasActiveFilters)
        state.category = .albums
        #expect(!state.hasActiveFilters)
        state.setFiltersActive(true, contentKind: "album")
        #expect(state.hasActiveFilters)
        state.setFiltersActive(false, contentKind: "album")
        state.category = .templates
        #expect(state.hasActiveFilters)
    }

    @Test(arguments: [DiaryMaterialToolbarState.Category.templates, .albums])
    func rootFilterActionPresentsTheSelectedCatalogSheet(category: DiaryMaterialToolbarState.Category) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.keyWindow
        let state = DiaryMaterialToolbarState()
        state.category = category
        let catalog = RemotePresetCatalog(series: [], books: [])
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let host = UIHostingController(rootView: NavigationStack {
            DiaryPresetLibraryScreen(ownerID: "toolbar-test", initialCatalog: catalog,
                toolbarState: state, catalogLoader: { catalog })
        })
        window.rootViewController = host
        window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }

        // This is the same command sent by the root toolbar, including when a
        // page has not yet been created by the nested paged TabView.
        state.requestFilters()
        let deadline = Date().addingTimeInterval(5)
        let expectedTitle = "筛选" + category.rawValue
        while Date() < deadline {
            if let presented = host.presentedViewController,
               containsNavigationTitle(expectedTitle, in: presented.view) { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Root filter action did not present \(expectedTitle)")
    }

    private func containsNavigationTitle(_ title: String, in view: UIView) -> Bool {
        if let bar = view as? UINavigationBar, bar.topItem?.title == title { return true }
        return view.subviews.contains { containsNavigationTitle(title, in: $0) }
    }
}
