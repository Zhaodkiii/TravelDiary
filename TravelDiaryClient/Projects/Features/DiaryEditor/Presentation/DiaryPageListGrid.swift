import SwiftUI

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
