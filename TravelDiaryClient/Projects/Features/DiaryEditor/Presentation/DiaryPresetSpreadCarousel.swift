import SwiftUI

/// 每一页独立参与原生滚动吸附；视口完整显示任意相邻两页。
struct DiaryPresetSpreadCarousel<Content: View>: View {
    let count: Int
    @Binding var position: Int?
    @ViewBuilder let content: (Int) -> Content
    @State private var scrollPosition = ScrollPosition(edge: .leading)
    @State private var visibleIndex = 0

    var body: some View {
        GeometryReader { geometry in
            // 两页之外每侧预留 20pt：8pt 间距 + 12pt 邻页；首尾裁到真实内容边界。
            let reveal: CGFloat = count > 2 ? 20 : 0
            let width = max(1, count == 1 ? geometry.size.width : (geometry.size.width - reveal * 2 - 8) / 2)
            let stride = width + 8
            let lastFirstIndex = max(0, count - 2)
            let maximumOffset = max(0, CGFloat(count) * stride - 8 - geometry.size.width)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 8) {
                    ForEach(0..<count, id: \.self) { index in
                        content(index)
                            .frame(width: width, height: geometry.size.height, alignment: .top)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(DiaryPresetPageSnapBehavior(reveal: reveal, stride: stride, lastFirstIndex: lastFirstIndex))
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: Int.self) { value in
                min(max(0, Int(((value.contentOffset.x + reveal) / stride).rounded())), lastFirstIndex)
            } action: { _, index in
                visibleIndex = index
                if position != index { position = index }
            }
            .onChange(of: position) { _, index in
                guard let index, index != visibleIndex else { return }
                // 箭头每次移动一页，与手势使用相同的相邻两页位置。
                scrollPosition.scrollTo(x: min(max(0, CGFloat(index) * stride - reveal), maximumOffset))
            }
            .onAppear {
                if let index = position, index > 0 {
                    scrollPosition.scrollTo(x: min(max(0, CGFloat(index) * stride - reveal), maximumOffset))
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .environment(\.layoutDirection, .leftToRight)
        }
    }
}

/// 系统按独立页面选择吸附目标，再将该页及其下一页作为可见区域居中。
private struct DiaryPresetPageSnapBehavior: ScrollTargetBehavior {
    let reveal: CGFloat
    let stride: CGFloat
    let lastFirstIndex: Int
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        ViewAlignedScrollTargetBehavior(limitBehavior: .alwaysByOne).updateTarget(&target, context: context)
        let page = min(max(0, (target.rect.minX / stride).rounded()), CGFloat(lastFirstIndex))
        target.rect.origin.x = min(max(0, page * stride - reveal),
                                  max(0, context.contentSize.width - context.containerSize.width))
        target.anchor = .topLeading
    }
}
