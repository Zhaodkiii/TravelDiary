import SwiftUI
import UIKit

/// 从当前编辑快照绘制整跨页，再按中线分成两半，复用阅读器外壳。
struct DiaryEditorSpreadPreview: View {
    @ObservedObject var session: DiaryEditorSession
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                Group {
                    if let image {
                        let rim: CGFloat = 0.0225
                        let gap = DiaryBookSpine.halfGapFraction
                        let ratio = session.document.root.referenceSize.width / session.document.root.referenceSize.height
                        let outerRatio = (ratio * (1 - 2 * rim) + 2 * rim) / (1 - (1 - 2 * rim) * gap)
                        DiaryBoundSpread {
                            half(image, left: true)
                        } right: {
                            half(image, left: false)
                        }
                        .aspectRatio(outerRatio, contentMode: .fit)
                        .padding(16)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    } else if let error {
                        ContentUnavailableView("预览生成失败", systemImage: "exclamationmark.triangle", description: Text(error))
                    } else { ProgressView("正在生成跨页预览…").frame(maxWidth: .infinity, maxHeight: .infinity) }
                }
            }
            .background(DiaryLibraryStyle.background)
            .navigationTitle("完整跨页预览").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("返回编辑") { dismiss() } } }
            .task {
                do {
                    // 捕获同一文档快照；不保存、不加载其他页，也不改变原会话版本基线。
                    let document = session.document
                    let images = try await session.store.exportImages(for: document)
                    let size = document.root.referenceSize
                    let format = UIGraphicsImageRendererFormat(); format.scale = 1800 / max(size.width, size.height)
                    image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                        DiaryPageRenderer.draw(document, images: images, in: context.cgContext, cacheObjects: false)
                    }
                } catch { self.error = error.localizedDescription }
            }
        }
    }
    private func half(_ image: UIImage, left: Bool) -> some View {
        GeometryReader { geometry in
            Image(uiImage: image).resizable()
                .frame(width: geometry.size.width * 2, height: geometry.size.height)
                .offset(x: left ? 0 : -geometry.size.width)
        }.clipped().accessibilityLabel(left ? "跨页左半页" : "跨页右半页")
    }
}
