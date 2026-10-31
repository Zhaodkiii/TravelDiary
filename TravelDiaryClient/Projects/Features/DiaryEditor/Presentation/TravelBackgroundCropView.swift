import SwiftUI
import UIKit

/// 预览页内直接取景，坐标以输出画布归一化，旋转设备后仍保留相同裁剪。
struct TravelBackgroundCropView: View {
    let image: UIImage
    @Binding var zoom: CGFloat
    @Binding var offset: CGSize
    @GestureState private var drag = CGSize.zero
    @GestureState private var magnification: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            let viewport = geometry.size
            let scale = max(viewport.width / image.size.width, viewport.height / image.size.height)
            let currentZoom = min(8, max(1, zoom * magnification))
            let proposed = CGSize(width: offset.width + drag.width / viewport.width,
                                  height: offset.height + drag.height / viewport.height)
            let position = TravelBackgroundCrop.clamp(proposed, image: image.size, viewport: viewport, zoom: currentZoom)
            ZStack {
                Color.black
                Image(uiImage: image).resizable()
                    .frame(width: image.size.width * scale * currentZoom, height: image.size.height * scale * currentZoom)
                    .offset(x: position.width * viewport.width, y: position.height * viewport.height)
                Path { path in
                    for value in [CGFloat(1)/3, CGFloat(2)/3] {
                        path.move(to: CGPoint(x: viewport.width * value, y: 0)); path.addLine(to: CGPoint(x: viewport.width * value, y: viewport.height))
                        path.move(to: CGPoint(x: 0, y: viewport.height * value)); path.addLine(to: CGPoint(x: viewport.width, y: viewport.height * value))
                    }
                }.stroke(.white.opacity(0.45), lineWidth: 0.5).allowsHitTesting(false)
            }.frame(width: viewport.width, height: viewport.height).clipped().contentShape(Rectangle())
                .gesture(DragGesture().updating($drag) { value, state, _ in state = value.translation }.onEnded { value in
                    offset = TravelBackgroundCrop.clamp(CGSize(width: offset.width + value.translation.width / viewport.width,
                        height: offset.height + value.translation.height / viewport.height), image: image.size, viewport: viewport, zoom: zoom)
                }.simultaneously(with: MagnificationGesture().updating($magnification) { value, state, _ in state = value }.onEnded { value in
                    zoom = min(8, max(1, zoom * value))
                    offset = TravelBackgroundCrop.clamp(offset, image: image.size, viewport: viewport, zoom: zoom)
                }))
        }.aspectRatio(4370.0 / 3130, contentMode: .fit)
        .accessibilityLabel("背景取景区域，可拖动和双指缩放，也可使用下方取景控件")
    }
}

@MainActor
enum TravelBackgroundCrop {
    static let output = CGSize(width: 4370, height: 3130)
    static func clamp(_ offset: CGSize, image: CGSize, viewport: CGSize, zoom: CGFloat) -> CGSize {
        let scale = max(viewport.width / max(1, image.width), viewport.height / max(1, image.height)) * max(1, zoom)
        let x = max(0, (image.width * scale - viewport.width) / (2 * viewport.width))
        let y = max(0, (image.height * scale - viewport.height) / (2 * viewport.height))
        return CGSize(width: min(x, max(-x, offset.width)), height: min(y, max(-y, offset.height)))
    }
    static func render(_ image: UIImage, zoom: CGFloat, offset: CGSize) -> UIImage {
        let scale = max(output.width / image.size.width, output.height / image.size.height) * max(1, zoom)
        let position = clamp(offset, image: image.size, viewport: output, zoom: zoom)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: output, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: output))
            image.draw(in: CGRect(x: (output.width-size.width)/2 + position.width*output.width,
                                  y: (output.height-size.height)/2 + position.height*output.height,
                                  width: size.width, height: size.height))
        }
    }
}
