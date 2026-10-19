import SwiftUI

/// 模板卡片沿用原生滚动、惰性加载和视图吸附；首张贴左，后续卡片露出前后邻项。
struct DiaryPresetTemplateCarousel<Content: View>: View {
    let count: Int
    var position: Binding<Int?>? = nil
    var maximumCardWidth: CGFloat = 290
    @ViewBuilder let content: (Int) -> Content
    @State private var current: Int? = 0

    nonisolated static func cardWidth(in width: CGFloat) -> CGFloat { max(1, min(290, width * 0.72)) }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(0..<count, id: \.self) { index in
                    content(index)
                        .containerRelativeFrame(.horizontal) { width, _ in min(maximumCardWidth, Self.cardWidth(in: width)) }
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(DiaryPresetTemplateSnapBehavior(maximumCardWidth: maximumCardWidth))
        .scrollPosition(id: position ?? $current, anchor: .leading)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .environment(\.layoutDirection, .leftToRight)
    }
}

private struct DiaryPresetTemplateSnapBehavior: ScrollTargetBehavior {
    let maximumCardWidth: CGFloat
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        ViewAlignedScrollTargetBehavior(limitBehavior: .alwaysByOne).updateTarget(&target, context: context)
        let width = max(1, min(maximumCardWidth, min(290, context.containerSize.width * 0.72)))
        let stride = width + 12
        let index = max(0, (target.rect.minX / stride).rounded())
        // 中间项左侧保留 12pt 上一张卡片和 12pt 间距；首尾不制造额外空白。
        target.rect.origin.x = min(max(0, index * stride - 24),
                                  max(0, context.contentSize.width - context.containerSize.width))
        target.anchor = .topLeading
    }
}

struct DiaryPresetTemplateCard: View {
    let item: PresetLibraryItem
    let ownerID: String
    var downloadedCount = 0
    var expanded = false
    var seriesTitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 12 : 10) {
            DiaryPresetMagazinePreview(item: item, ownerID: ownerID)
            HStack(spacing: 6){
                Text(item.title)
                    .font(expanded ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                    .lineLimit(2, reservesSpace: !expanded)
                Spacer(minLength: 0)
                if let remote = item.remote {
                    PresetBookAvailabilityBadge(downloadedCount: min(remote.page_count, downloadedCount), totalCount: remote.page_count)
                }

            }

//            HStack(spacing: 6) {
//                Text(expanded ? [seriesTitle, item.pageLabel].compactMap { $0 }.joined(separator: " · ") : item.pageLabel)
//                    .font(expanded ? .caption : .caption2).foregroundStyle(DiaryLibraryStyle.secondary)
//                Spacer(minLength: 0)
//                if item.local != nil {
//                    if expanded {
//                        Label("内置可用", systemImage: "checkmark.circle").font(.caption)
//                    } else {
//                        Image(systemName: "checkmark.circle").font(.caption2).accessibilityLabel("内置可用")
//                    }
//                } else if let remote = item.remote {
//                    PresetBookAvailabilityBadge(downloadedCount: min(remote.page_count, downloadedCount), totalCount: remote.page_count)
//                }
//                if !expanded { Image(systemName: "arrow.up.right").font(.caption2.weight(.medium)) }
//            }.foregroundStyle(DiaryLibraryStyle.secondary)
            if expanded {
                HStack(spacing: 8) { Text("翻看这本模板"); Image(systemName: "arrow.right") }
                    .font(.subheadline.weight(.medium)).foregroundStyle(DiaryLibraryStyle.accent)
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(DiaryLibraryStyle.ink)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
