import Testing
import SwiftUI
@testable import TravelDiary

/// 验证实际原生滚动布局：任意相邻两页吸附，页码不受奇偶配对限制。
@MainActor
struct DiaryPresetSpreadCarouselTests {
    private final class Driver: ObservableObject {
        @Published var position: Int? = 0
        var viewport: CGRect = .zero
        var pages: [Int: CGRect] = [:]
    }
    private struct Probe: View {
        @ObservedObject var driver: Driver
        let count: Int
        var body: some View {
            DiaryPresetSpreadCarousel(count: count, position: $driver.position) { index in
                Rectangle().fill(index.isMultiple(of: 2) ? Color.orange : Color.blue)
                    .overlay { Text("\(index + 1)").font(.largeTitle) }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("carousel-test")) } action: {
                        driver.pages[index] = $0
                    }
            }
            .frame(height: 320)
            .background { GeometryReader { geometry in
                Color.clear.onAppear { driver.viewport = CGRect(origin: .zero, size: geometry.size) }
            } }
            .coordinateSpace(name: "carousel-test")
            .padding(16)
        }
    }

    @Test func adjacentPairsAdvanceByOnePageAndOddLastPageHasNoEmptyPartner() async throws {
        let driver = Driver()
        let window = try makeWindow(driver: driver, count: 7)
        defer { window.isHidden = true }
        try await settle { driver.viewport.width > 0 && driver.pages[2] != nil }
        let width = driver.viewport.width
        #expect(abs(try #require(driver.pages[0]).minX) < 1)
        try expectCompletePair(startingAt: 0, driver: driver)
        #expect(try #require(driver.pages[2]).minX < width)

        // 逐页前进：1–2 → 2–3 → 3–4 → … → 6–7，最后不产生单页空白组。
        for first in 1...5 {
            driver.position = first
            try await settle {
                guard let left = driver.pages[first], let right = driver.pages[first + 1] else { return false }
                return first == 5 ? abs(right.maxX - width) < 1 : abs((left.minX + right.maxX) / 2 - width / 2) < 1
            }
            #expect(driver.position == first)
            try expectCompletePair(startingAt: first, driver: driver)
            let left = try #require(driver.pages[first])
            let previous = try #require(driver.pages[first - 1])
            #expect(previous.maxX > 0 && previous.maxX < left.minX)
            if first < 5 {
                let right = try #require(driver.pages[first + 1]), next = try #require(driver.pages[first + 2])
                #expect(next.minX < width && next.minX > right.maxX)
            }
        }
        #expect(abs(try #require(driver.pages[6]).maxX - width) < 1)

        // 向后也可以回到偶数起始页的组合。
        driver.position = 4
        try await settle { abs((driver.pages[4]?.minX ?? -1000) - 20) < 1 }
        try expectCompletePair(startingAt: 4, driver: driver)
    }

    @Test(arguments: [1, 2]) func oneOrTwoPagesUseFullWidthWithoutNeighborSpace(count: Int) async throws {
        let driver = Driver()
        let window = try makeWindow(driver: driver, count: count)
        defer { window.isHidden = true }
        try await settle { driver.viewport.width > 0 && driver.pages[count - 1] != nil }
        #expect(abs(try #require(driver.pages[0]).minX) < 1)
        #expect(abs(try #require(driver.pages[count - 1]).maxX - driver.viewport.width) < 1)
        #expect(driver.position == 0)
    }

    private func makeWindow(driver: Driver, count: Int) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: Probe(driver: driver, count: count))
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        return window
    }
    private func expectCompletePair(startingAt first: Int, driver: Driver) throws {
        for index in first...(first + 1) {
            let page = try #require(driver.pages[index])
            #expect(page.minX >= -1 && page.maxX <= driver.viewport.width + 1)
            #expect(page.width > 100)
        }
    }
    private func settle(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("原生滚动未在预期位置吸附")
    }
}
