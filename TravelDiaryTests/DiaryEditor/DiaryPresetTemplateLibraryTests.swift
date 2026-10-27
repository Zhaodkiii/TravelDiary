import Testing
import SwiftUI
@testable import TravelDiary

@MainActor
struct DiaryPresetTemplateLibraryTests {
    private func book(_ id: String, series: String) -> RemotePresetBook {
        RemotePresetBook(id: id, title: id, series: series, version: 1, page_count: 4, cover_url: "https://example.test/cover.png")
    }

    @Test func sectionsUseCatalogNamesAndOrderAndKeepEveryBookOnce() {
        let items = PresetLibraryItem.merge(local: [], remote: [book("city-a", series: "city"), book("hike-a", series: "hike"),
            book("city-b", series: "city"), book("other", series: "new")])
        let sections = PresetLibrarySection.group(items, series: [.init(slug: "hike", title: "山野自然"),
            .init(slug: "empty", title: "空系列"), .init(slug: "city", title: "城市漫游"), .init(slug: "city", title: "重复系列")])
        #expect(sections.map(\.id) == ["hike", "city", "new"])
        #expect(sections.map(\.title) == ["山野自然", "城市漫游", "更多模板"])
        #expect(sections[1].items.map(\.id) == ["city-a", "city-b"])
        #expect(sections.flatMap(\.items).count == items.count)
    }

    @Test func categoryScopeKeepsAllItsTemplatesAndCannotLeakOtherSeries() {
        let items = PresetLibraryItem.merge(local: [], remote: [book("上海", series: "city"), book("苏州", series: "city"), book("雨崩", series: "hike")])
        let rootSearch = items.filter { $0.matches(search: "上海", series: "", styles: [], usages: []) }
        #expect(rootSearch.map(\.id) == ["上海"])
        // 分类页从完整目录重新筛选，而非沿用首页的搜索结果。
        let category = PresetLibrarySection.scoped(items, seriesID: "city")
        #expect(category.map(\.id) == ["上海", "苏州"])
        let search = items.filter { $0.matches(search: "雨崩", series: "city", styles: [], usages: []) }
        #expect(search.isEmpty)
        let missingSeries = PresetLibraryItem.merge(local: [], remote: [book("未分类", series: "")])
        #expect(PresetLibrarySection.scoped(items + missingSeries, seriesID: "").map(\.id) == ["未分类"])
        #expect(PresetLibrarySection.scoped(items + missingSeries, seriesID: nil).count == 4)
    }

    private final class Driver: ObservableObject {
        @Published var position: Int? = 0
        var viewport = CGRect.zero
        var cards: [Int: CGRect] = [:]
    }
    private struct Probe: View {
        @ObservedObject var driver: Driver
        let count: Int
        var body: some View {
            DiaryPresetTemplateCarousel(count: count, position: $driver.position) { index in
                Rectangle().fill(index.isMultiple(of: 2) ? Color.orange : Color.blue)
                    .overlay { Text("\(index + 1)") }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("template-test")) } action: {
                        driver.cards[index] = $0
                    }
            }
            .frame(height: 360)
            .background { GeometryReader { geometry in
                Color.clear.onAppear { driver.viewport = CGRect(origin: .zero, size: geometry.size) }
            } }
            .coordinateSpace(name: "template-test")
            .padding(20)
        }
    }

    @Test func nativeCardsShowOneCompleteCardWithNeighborHintsAtEachStop() async throws {
        let driver = Driver()
        let window = try makeWindow(driver: driver, count: 4)
        defer { window.isHidden = true }
        try await settle { driver.viewport.width > 0 && driver.cards[1] != nil }
        let width = driver.viewport.width
        let first = try #require(driver.cards[0]), next = try #require(driver.cards[1])
        #expect(abs(first.minX) < 1)
        #expect(first.maxX < width && next.minX < width && next.maxX > width)

        for index in 1...2 {
            driver.position = index
            try await settle { abs((driver.cards[index]?.minX ?? -1000) - 24) < 1 }
            let card = try #require(driver.cards[index]), previous = try #require(driver.cards[index - 1])
            #expect(card.minX >= 0 && card.maxX < width)
            #expect(previous.maxX > 0 && previous.maxX < card.minX)
            #expect(try #require(driver.cards[index + 1]).minX < width)
        }
        driver.position = 3
        try await settle { abs((driver.cards[3]?.maxX ?? -1000) - width) < 1 }
        #expect(abs(try #require(driver.cards[3]).maxX - width) < 1)
    }

    @Test func onlyCardStartsAtLeadingEdgeWithoutReservedPreviousSlot() async throws {
        let driver = Driver()
        let window = try makeWindow(driver: driver, count: 1)
        defer { window.isHidden = true }
        try await settle { driver.cards[0] != nil }
        #expect(abs(try #require(driver.cards[0]).minX) < 1)
    }

    @Test func actualTemplateCardsRenderInsideThePagedLibraryAndLazyCarousels() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let books = (0..<4).map { index in
            RemotePresetBook(id: "render-fixture-\(index)", title: "模板 \(index)", series: "city", version: 1,
                             page_count: 5, cover_url: "file:///missing/preview.png")
        }
        let catalog = RemotePresetCatalog(series: [.init(slug: "city", title: "城市漫游")], books: books)
        let controller = UIHostingController(rootView: NavigationStack {
            DiaryPresetLibraryScreen(ownerID: "render-fixture", initialCatalog: catalog, catalogLoader: { catalog })
        })
        window.rootViewController = controller
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        controller.view.layoutIfNeeded()
        #expect(controller.view.bounds.width > 0)
        #expect(controller.view.bounds.height > 0)
    }

    private func makeWindow(driver: Driver, count: Int) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: Probe(driver: driver, count: count))
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        return window
    }
    private func settle(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("模板卡片未在预期位置吸附")
    }
}
