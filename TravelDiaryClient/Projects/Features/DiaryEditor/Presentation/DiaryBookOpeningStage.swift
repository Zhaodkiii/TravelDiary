import SwiftUI

/// 固定视口内插值尺寸与书脊位置；封面两面共用一根转轴，避免切换布局造成跳变。
struct DiaryBookOpeningStage<Pages: View>: View, Animatable {
    var progress: CGFloat
    let viewport: CGSize
    let paperRatio: CGFloat
    let cover: DiaryPageEntry?
    let firstPage: DiaryPageEntry?
    let store: DiaryDocumentStore
    @ViewBuilder let pages: () -> Pages

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let p = min(max(progress, 0), 1)
        let coverRatio = cover.map { max($0.size.width, 1) / max($0.size.height, 1) } ?? paperRatio
        let closedWidth = min(viewport.width * 0.80, viewport.height * 0.88 * coverRatio)
        let closedHeight = closedWidth / coverRatio
        // 外沿占单侧外壳宽度的 4.5%；内页宽高仍严格遵循内容页比例。
        let rimFraction: CGFloat = 0.045
        let openSize = DiaryBookStageLayout.openSize(viewport: viewport, paperRatio: paperRatio)
        let openWidth = openSize.width / 2
        let openHeight = openSize.height
        let width = closedWidth + (openWidth - closedWidth) * p
        let height = closedHeight + (openHeight - closedHeight) * p
        let rim = width * rimFraction
        let spine = viewport.width / 2 - width / 2 * (1 - p)
        ZStack(alignment: .topLeading) {
            // 后壳略大于纸张；合上时被原始封面完整遮住。
            ZStack(alignment: .topLeading) {
                if p >= 0.9999 {
                    Image("DiaryBookLeather").resizable()
                        .frame(width: width * 2, height: height)
                        .position(x: spine, y: viewport.height / 2)
                } else {
                    DiaryBookBackingHalf(left: false)
                        .frame(width: width, height: height)
                        .position(x: spine + width / 2, y: viewport.height / 2)
                }
                if p < 0.9999, let firstPage {
                    DiaryPagePreview(page: firstPage, store: store, large: true, undecorated: true)
                        .frame(width: (width - rim) * (1 - DiaryBookSpine.halfGapFraction), height: height - 2 * rim)
                        .clipped()
                        .position(x: spine + (width - rim) * (1 + DiaryBookSpine.halfGapFraction) / 2, y: viewport.height / 2)
                }
            }
            .frame(width: viewport.width, height: viewport.height)
            .mask {
                Rectangle()
                    .frame(width: width * 2, height: height)
                    .position(x: spine, y: viewport.height / 2)
            }
            // 闭合只显示原始封面，避免比例不同的内页从上下边缘露出。
            .opacity(min(p / 0.12, 1))
            LinearGradient(colors: [.black.opacity(0.12), .black.opacity(0.48), .black.opacity(0.12)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 2 * (width - rim) * DiaryBookSpine.halfGapFraction, height: height - 2 * rim)
                .position(x: spine, y: viewport.height / 2)
                .opacity(min(p / 0.12, 1))
                .allowsHitTesting(false)
            // 卷页控制器常驻并预载。纸张弯曲时必须能伸出静止纸面的边界，
            // 仅后壳保留 mask；这里裁剪会把卷页和阴影切在外皮内侧。
            pages()
                .frame(width: 2 * (width - rim), height: height - 2 * rim)
                .position(x: spine, y: viewport.height / 2)
                .opacity(p >= 0.9999 ? 1 : 0)
                .allowsHitTesting(p >= 0.9999)
            // 转过 90° 后显示内衬，背面预先翻转，避免文字/材质镜像。
            if p < 0.9999 {
                ZStack {
                    if p < 0.5 {
                        if let cover {
                            DiaryPagePreview(page: cover, store: store, large: true, undecorated: true)
                        }
                    } else {
                        DiaryBookBackingHalf(left: true)
                            .overlay { DiaryBookLining().padding(rim) }
                            .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    }
                }
                .frame(width: width, height: height)
                .shadow(color: .black.opacity(0.16 + 0.15 * sin(Double(p) * Double.pi)), radius: 10, x: 3, y: 5)
                .rotation3DEffect(.degrees(-180 * p), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.35)
                .offset(x: spine, y: (viewport.height - height) / 2)
            }
        }
        .frame(width: viewport.width, height: viewport.height)
    }
}

/// 开合动画从同一张完整底板取左右半面，书脊处不会出现额外圆角或缝线。
private struct DiaryBookBackingHalf: View {
    let left: Bool
    var body: some View {
        GeometryReader { geometry in
            Image("DiaryBookLeather").resizable()
                .frame(width: geometry.size.width * 2, height: geometry.size.height)
                .offset(x: left ? 0 : -geometry.size.width)
        }.clipped()
    }
}

/// 每张纸在书脊侧留出 1.8% 宽度，左右合成一条可见的装订缝。
nonisolated enum DiaryBookSpine {
    static let halfGapFraction: CGFloat = 0.018
    // 屏幕展示采用三组三孔：组内等距、组间等距，中心孔在 50%，上下镜像。
    // 不作为实体印刷打孔尺寸；不同装订器的九孔规格并不相同。
    static let ringPositions: [CGFloat] = [0.115, 0.190, 0.265, 0.425, 0.500, 0.575, 0.735, 0.810, 0.885]
}

/// Shared fitted bounds for rendering and the immersive background hit area.
nonisolated enum DiaryBookStageLayout {
    static let paperCornerRadius: CGFloat = 24

    /// Duo 横屏纯纸面：尺寸包含装订缝，扣除缝隙后每张纸保持内容比例。
    static func paperSize(viewport: CGSize, paperRatio: CGFloat) -> CGSize {
        let ratio = max(paperRatio, 0.01) * 2 / (1 - DiaryBookSpine.halfGapFraction)
        let width = min(max(viewport.width - 16, 1), max(viewport.height - 16, 1) * ratio)
        return CGSize(width: width, height: width / ratio)
    }

    static func openSize(viewport: CGSize, paperRatio: CGFloat) -> CGSize {
        let rimFraction: CGFloat = 0.045
        let heightPerHalfWidth = (1 - rimFraction) * (1 - DiaryBookSpine.halfGapFraction) / paperRatio + 2 * rimFraction
        let halfWidth = min(max(viewport.width - 24, 1) / 2,
                            max(viewport.height - 24, 1) / heightPerHalfWidth)
        return CGSize(width: halfWidth * 2, height: halfWidth * heightPerHalfWidth)
    }
}
