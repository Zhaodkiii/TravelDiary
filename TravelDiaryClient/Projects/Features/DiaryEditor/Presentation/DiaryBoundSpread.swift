import SwiftUI

/// 手帐展示的统一代码配置；修改后重新编译生效。
nonisolated enum DiaryBookAppearance {
    /// true：显示九枚装订环；false：隐藏。覆盖所有共用预览、跨页图片及视频导出。
    /// 仅控制装订环，保留皮革外沿、书脊间距和纸张布局。
    static let showsBindingRings = false
}

/// 静态跨页共用阅读器的皮革外沿、书脊与九枚装订环；列表和导出保持同一结构。
struct DiaryBoundSpread<Left: View, Right: View>: View {
    @ViewBuilder let left: () -> Left
    @ViewBuilder let right: () -> Right

    var body: some View {
        GeometryReader { geometry in
            let rim = geometry.size.width * 0.0225
            let innerWidth = geometry.size.width - rim * 2
            let gap = innerWidth * DiaryBookSpine.halfGapFraction
            ZStack {
                Image("DiaryBookLeather").resizable()
                LinearGradient(colors: [.black.opacity(0.12), .black.opacity(0.48), .black.opacity(0.12)],
                    startPoint: .leading, endPoint: .trailing)
                    .frame(width: gap).padding(.vertical, rim)
                HStack(spacing: gap) {
                    left().frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                    right().frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                }.padding(rim)
                DiaryBindingRings().padding(rim).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}
