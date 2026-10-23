import SwiftUI

/// 模板替换和自由相册共用添加区域、网格和移除按钮，容量由各自流程决定。
struct DiaryPhotoSelectionGrid<Picker: View, Thumbnail: View>: View {
    let count: Int
    let emptyPrompt: String
    @ViewBuilder let picker: (Bool) -> Picker
    @ViewBuilder let thumbnail: (Int) -> Thumbnail
    let remove: (Int) -> Void
    var body: some View {
        ScrollView {
            if count == 0 {
                picker(true)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72, maximum: 100), spacing: 10)], spacing: 10) {
                    picker(false)
                    ForEach(0..<count, id: \.self) { index in
                        thumbnail(index).frame(height: 86).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .bottomLeading) {
                                Text("\(index + 1)").font(.caption2.weight(.semibold)).padding(.horizontal, 5).padding(.vertical, 2)
                                    .foregroundStyle(.white).background(.black.opacity(0.5), in: Capsule()).padding(3)
                            }
                            .overlay(alignment: .topTrailing) {
                                Button { remove(index) } label: {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 18))
                                        .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.6))
                                        .frame(width: 36, height: 36)
                                }.accessibilityLabel("移除第 \(index + 1) 张照片")
                            }
                    }
                }
            }
        }.frame(maxHeight: .infinity)
    }
}
struct DiaryPhotoAddLabel: View {
    var expanded: Bool
    var prompt = "点这里添加照片，自动排入相册"
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus").font(.system(size: 26, weight: .light))
            if expanded { Text(prompt).font(.caption).multilineTextAlignment(.center) }
        }
        .foregroundStyle(DiaryLibraryStyle.accent)
        .frame(maxWidth: .infinity).frame(height: expanded ? 110 : 86)
        .background {
            RoundedRectangle(cornerRadius: 14).strokeBorder(DiaryLibraryStyle.line, style: StrokeStyle(lineWidth: 1.5, dash: [6]))
        }
        .accessibilityLabel("添加照片")
    }
}
