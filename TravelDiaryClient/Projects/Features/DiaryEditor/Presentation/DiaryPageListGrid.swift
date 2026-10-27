import SwiftUI

/// 封面独占首个跨页的右侧，正文按原始页序成对展示，末尾单页仍保留。
struct DiaryPresetOverviewSpread<Page: Identifiable>: Identifiable {
    let left: Page?
    let right: Page?
    var pages: [Page] { [left, right].compactMap { $0 } }
    var id: [Page.ID] { pages.map(\.id) }

    static func group(pages: [Page], shellID: Page.ID?, coverID: Page.ID?) -> [Self] {
        let cover = pages.first { $0.id == coverID } ?? pages.first { $0.id != shellID }
        guard let cover else { return [] }
        let content = pages.filter { $0.id != shellID && $0.id != cover.id }
        var result = [Self(left: nil, right: cover)]
        for index in stride(from: 0, to: content.count, by: 2) {
            result.append(Self(left: content[index], right: index + 1 < content.count ? content[index + 1] : nil))
        }
        return result
    }
}

struct DiaryPresetOverviewGrid<Page: Identifiable, Cell: View>: View {
    let spreads: [DiaryPresetOverviewSpread<Page>]
    @ViewBuilder let cell: (DiaryPresetOverviewSpread<Page>) -> Cell

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)],
                  alignment: .leading, spacing: 20) {
            ForEach(spreads) { spread in cell(spread) }
        }
    }
}

struct DiaryPresetOverviewThumbnail<Page: Identifiable, Paper: View>: View {
    let spread: DiaryPresetOverviewSpread<Page>
    let pageSize: CGSize
    @ViewBuilder let paper: (Page) -> Paper

    private var ratio: CGFloat { max(pageSize.width, 1) / max(pageSize.height, 1) }
    var body: some View {
        DiaryBoundSpread {
            leaf(spread.left, lining: spread.left == nil)
        } right: {
            leaf(spread.right, lining: false)
        }
        .aspectRatio(2 / (0.955 * (1 - DiaryBookSpine.halfGapFraction) / ratio + 0.09), contentMode: .fit)
        .shadow(color: .black.opacity(0.10), radius: 3, y: 2)
    }

    @ViewBuilder private func leaf(_ page: Page?, lining: Bool) -> some View {
        if let page { paper(page) }
        else if lining { DiaryBookLining() }
        else { Color(red: 0.96, green: 0.92, blue: 0.82) }
    }
}

/// 外壳、封面固定在首行，正文另起网格；同一页同时承担两个角色时只显示一次。
struct DiaryPageListGrid<Page: Identifiable, Cell: View>: View {
    let pages: [Page]
    let shellID: Page.ID?
    let coverID: Page.ID?
    @ViewBuilder let cell: (Page) -> Cell

    private var frontPages: [Page] {
        var result: [Page] = []
        for id in [shellID, coverID].compactMap({ $0 }) {
            if !result.contains(where: { $0.id == id }), let page = pages.first(where: { $0.id == id }) {
                result.append(page)
            }
        }
        return result
    }

    var body: some View {
        let front = frontPages
        let remaining = pages.filter { page in !front.contains { $0.id == page.id } }
        VStack(alignment: .leading, spacing: 20) {
            if !front.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 20) {
                    ForEach(front) { page in cell(page) }
                }
            }
            if !remaining.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .top)], spacing: 20) {
                    ForEach(remaining) { page in cell(page) }
                }
            }
        }
    }
}
