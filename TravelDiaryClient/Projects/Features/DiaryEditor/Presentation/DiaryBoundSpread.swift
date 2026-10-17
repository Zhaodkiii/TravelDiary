import SwiftUI

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
