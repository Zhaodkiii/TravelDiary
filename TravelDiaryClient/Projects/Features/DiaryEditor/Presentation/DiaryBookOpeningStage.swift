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
        let openHeightPerWidth = (1 - rimFraction) / paperRatio + 2 * rimFraction
        let openWidth = min(max(viewport.width - 24, 1) / 2,
                            max(viewport.height - 24, 1) / openHeightPerWidth)
        let openHeight = openWidth * openHeightPerWidth
        let width = closedWidth + (openWidth - closedWidth) * p
        let height = closedHeight + (openHeight - closedHeight) * p
        let rim = width * rimFraction
        let spine = viewport.width / 2 - width / 2 * (1 - p)
        ZStack(alignment: .topLeading) {
            // 后壳略大于纸张；合上时被原始封面完整遮住。
            ZStack(alignment: .topLeading) {
                Image("DiaryBookLeather").resizable()
                    .frame(width: width, height: height)
                    .position(x: spine + width / 2, y: viewport.height / 2)
                if p >= 0.9999 {
                    Image("DiaryBookLeather").resizable()
                        .frame(width: width, height: height)
                        .position(x: spine - width / 2, y: viewport.height / 2)
                } else if let firstPage {
                    DiaryPagePreview(page: firstPage, store: store, large: true, undecorated: true)
                        .frame(width: width - rim, height: height - 2 * rim)
                        .position(x: spine + (width - rim) / 2, y: viewport.height / 2)
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
            // 卷页控制器常驻并预载，避免动画完成时重新创建造成闪屏。
            pages()
                .frame(width: 2 * (width - rim), height: height - 2 * rim)
                .clipped()
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
                        Image("DiaryBookLeather").resizable()
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
