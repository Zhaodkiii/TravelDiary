import UIKit
import Vision
import CoreImage

nonisolated struct StickerSubject: Identifiable, @unchecked Sendable {
    let id: Int
    let image: UIImage
    let bounds: CGRect
}
nonisolated enum StickerImageProcessor {
    static func subjects(_ image: UIImage) throws -> [StickerSubject] {
        // Normalize camera EXIF orientation before passing pixels to Vision.
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let ratio = min(1, 2048 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let cg = normalized.cgImage else { return [] }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg)
        try handler.perform([request])
        guard let observation = request.results?.first else { return [] }
        let context = CIContext()
        return try observation.allInstances.map { instance in
            let buffer = try observation.generateMaskedImage(ofInstances: IndexSet(integer: instance), from: handler, croppedToInstancesExtent: false)
            let ci = CIImage(cvPixelBuffer: buffer)
            guard let result = context.createCGImage(ci, from: ci.extent) else { throw URLError(.cannotDecodeContentData) }
            let width = result.width, height = result.height
            var rgba = [UInt8](repeating: 0, count: width * height * 4)
            let box: CGRect = rgba.withUnsafeMutableBytes { bytes in
                guard let drawing = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .zero }
                drawing.draw(result, in: CGRect(x: 0, y: 0, width: width, height: height))
                let pixels = bytes.bindMemory(to: UInt8.self)
                var minX = width, minY = height, maxX = 0, maxY = 0
                for y in 0..<height {
                    for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 32 {
                        minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
                    }
                }
                guard maxX >= minX, maxY >= minY else { return .zero }
                return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
            }
            guard !box.isEmpty, let cropped = result.cropping(to: box) else { throw URLError(.cannotDecodeContentData) }
            return StickerSubject(id: instance, image: UIImage(cgImage: cropped),
                bounds: CGRect(x: box.minX / CGFloat(width), y: box.minY / CGFloat(height), width: box.width / CGFloat(width), height: box.height / CGFloat(height)))
        }
    }
    static func thumbnail(_ image: UIImage) -> UIImage {
        let factor = min(1, 96 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
    static func render(_ image: UIImage, style: String, color: UIColor, thickness: Int) -> UIImage {
        let edge = max(2, min(36, min(image.size.width, image.size.height) * CGFloat(thickness) / 100))
        let padding = ceil(edge * 2 + 4)
        let size = CGSize(width: image.size.width + padding * 2, height: image.size.height + padding * 2)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let rect = CGRect(origin: CGPoint(x: padding, y: padding), size: image.size)
            if style != "原样", let input = CIImage(image: image) {
                let expanded = input.applyingFilter("CIMorphologyMaximum", parameters: ["inputRadius": edge])
                let tinted = expanded.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: CIColor(color: color).red, y: CIColor(color: color).green, z: CIColor(color: color).blue, w: 0)])
                if let cg = CIContext().createCGImage(tinted, from: input.extent.insetBy(dx: -edge, dy: -edge)) {
                    let borderRect = rect.insetBy(dx: -edge, dy: -edge)
                    if style == "虚线" {
                        let alpha = expanded.applyingFilter("CIColorMatrix", parameters: [
                            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
                        if let mask = CIContext().createCGImage(alpha, from: input.extent.insetBy(dx: -edge, dy: -edge)) {
                            let request = VNDetectContoursRequest(); request.detectsDarkOnLight = false
                            try? VNImageRequestHandler(cgImage: mask).perform([request])
                            if let contours = request.results?.first {
                                var transform = CGAffineTransform(a: borderRect.width, b: 0, c: 0, d: -borderRect.height, tx: borderRect.minX, ty: borderRect.maxY)
                                if let path = contours.normalizedPath.copy(using: &transform) {
                                    let context = renderer.cgContext
                                    context.saveGState(); context.addPath(path); context.setStrokeColor(color.cgColor)
                                    context.setLineWidth(max(2, edge * 0.6)); context.setLineCap(.round)
                                    context.setLineDash(phase: 0, lengths: [edge * 1.5, edge * 1.2]); context.strokePath(); context.restoreGState()
                                }
                            }
                        }
                    } else { UIImage(cgImage: cg).draw(in: borderRect) }
                }
            }
            image.draw(in: rect)
        }
    }
}
