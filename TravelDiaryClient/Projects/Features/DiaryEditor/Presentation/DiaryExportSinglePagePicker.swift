import SwiftUI

struct DiaryExportSinglePagePicker: View {
    let book: DiaryBook
    let store: DiaryDocumentStore
    @Binding var selected: Set<UUID>
    private let ink = Color(red: 0.23, green: 0.36, blue: 0.31)

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("已选 \(selected.count) / \(book.pages.count) 页").font(.subheadline)
                Spacer()
                Button("全选") { selected = Set(book.pages.map(\.id)) }
                Button("清空") { selected.removeAll() }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 94))], spacing: 14) {
                ForEach(Array(book.pages.enumerated()), id: \.element.id) { index, page in
                    Button {
                        if selected.contains(page.id) { selected.remove(page.id) } else { selected.insert(page.id) }
                    } label: {
                        VStack(spacing: 8) {
                            DiaryPagePreview(page: page, store: store).frame(height: 120)
                            HStack {
                                Text("第 \(index + 1) 页").font(.caption)
                                Spacer()
                                Image(systemName: selected.contains(page.id) ? "checkmark.circle.fill" : "circle")
                            }
                        }.padding(10).background(.background, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected.contains(page.id) ? ink : .clear, lineWidth: 2))
                    }.buttonStyle(.plain).accessibilityAddTraits(selected.contains(page.id) ? .isSelected : [])
                }
            }
        }
    }
}
