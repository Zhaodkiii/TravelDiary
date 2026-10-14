import CoreImage
import CoreImage.CIFilterBuiltins
import PencilKit
import UIKit

@MainActor
enum TelegramPhotoEditorRenderer {
    private static let context = CIContext(options: [.cacheIntermediates: true])

    static func render(
        sourceImage: UIImage,
        adjustments: TelegramPhotoAdjustments,
        curves: TelegramPhotoCurves,
        cropPreset: TelegramPhotoCropPreset,
        quarterTurns: Int,
        straightenDegrees: Double,
        isFlippedHorizontally: Bool,
        blur: TelegramPhotoBlur,
        drawing: PKDrawing,
        drawingCanvasSize: CGSize,
        textOverlays: [TelegramPhotoTextOverlay],
        stickerOverlays: [TelegramPhotoStickerOverlay]
    ) -> UIImage? {
        guard var image = normalized(sourceImage) else { return nil }
        image = transformed(
            image,
            quarterTurns: quarterTurns,
            straightenDegrees: straightenDegrees,
            flipped: isFlippedHorizontally
        )
        image = adjusted(image, values: adjustments, curves: curves) ?? image
        image = cropped(image, preset: cropPreset)
        image = blurred(image, value: blur) ?? image
        return composited(
            image,
            drawing: drawing,
            drawingCanvasSize: drawingCanvasSize,
            textOverlays: textOverlays,
            stickerOverlays: stickerOverlays
        )
    }

    static func preview(
        sourceImage: UIImage,
        adjustments: TelegramPhotoAdjustments,
        curves: TelegramPhotoCurves,
        cropPreset: TelegramPhotoCropPreset,
        quarterTurns: Int,
        straightenDegrees: Double,
        isFlippedHorizontally: Bool,
        blur: TelegramPhotoBlur,
        maximumDimension: CGFloat = 1200
    ) -> UIImage? {
        let image = downsampled(sourceImage, maximumDimension: maximumDimension)
        return render(
            sourceImage: image,
            adjustments: adjustments,
            curves: curves,
            cropPreset: cropPreset,
            quarterTurns: quarterTurns,
            straightenDegrees: straightenDegrees,
            isFlippedHorizontally: isFlippedHorizontally,
            blur: blur,
            drawing: PKDrawing(),
            drawingCanvasSize: .zero,
            textOverlays: [],
            stickerOverlays: []
        )
    }

    private static func downsampled(_ image: UIImage, maximumDimension: CGFloat) -> UIImage {
        let largest = max(image.size.width, image.size.height)
        guard largest > maximumDimension else { return image }
        let ratio = maximumDimension / largest
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    private static func normalized(_ image: UIImage) -> UIImage? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func transformed(
        _ image: UIImage,
        quarterTurns: Int,
        straightenDegrees: Double,
        flipped: Bool
    ) -> UIImage {
        let turns = ((quarterTurns % 4) + 4) % 4
        let outputSize = turns.isMultiple(of: 2) ? image.size : CGSize(width: image.size.height, height: image.size.width)
        let angle = CGFloat(turns) * .pi / 2 + CGFloat(straightenDegrees) * .pi / 180
        guard angle != 0 || flipped else { return image }

        let absCos = abs(cos(CGFloat(straightenDegrees) * .pi / 180))
        let absSin = abs(sin(CGFloat(straightenDegrees) * .pi / 180))
        let coverScale = max(
            (outputSize.width * absCos + outputSize.height * absSin) / max(outputSize.width, 1),
            (outputSize.width * absSin + outputSize.height * absCos) / max(outputSize.height, 1)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false

        return UIGraphicsImageRenderer(size: outputSize, format: format).image { rendererContext in
            let context = rendererContext.cgContext
            context.translateBy(x: outputSize.width / 2, y: outputSize.height / 2)
            context.rotate(by: angle)
            context.scaleBy(x: flipped ? -coverScale : coverScale, y: coverScale)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        }
    }

    private static func adjusted(
        _ image: UIImage,
        values: TelegramPhotoAdjustments,
        curves: TelegramPhotoCurves
    ) -> UIImage? {
        guard var output = CIImage(image: image) else { return nil }

        if values.enhance > 0.001 {
            let vibrance = CIFilter.vibrance()
            vibrance.inputImage = output
            vibrance.amount = Float(values.enhance * 0.8)
            output = vibrance.outputImage ?? output

            let exposure = CIFilter.exposureAdjust()
            exposure.inputImage = output
            exposure.ev = Float(values.enhance * 0.18)
            output = exposure.outputImage ?? output
        }

        let controls = CIFilter.colorControls()
        controls.inputImage = output
        controls.brightness = Float(values.brightness)
        controls.contrast = Float(values.contrast)
        controls.saturation = Float(values.saturation)
        output = controls.outputImage ?? output

        if abs(values.warmth) > 0.001 {
            let temperature = CIFilter.temperatureAndTint()
            temperature.inputImage = output
            temperature.neutral = CIVector(x: 6500, y: 0)
            temperature.targetNeutral = CIVector(x: 6500 - values.warmth * 2200, y: 0)
            output = temperature.outputImage ?? output
        }

        if abs(values.shadows) > 0.001 || abs(values.highlights) > 0.001 {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = output
            filter.shadowAmount = Float(max(0, 1 + values.shadows))
            filter.highlightAmount = Float(max(0, 1 - values.highlights * 0.8))
            output = filter.outputImage ?? output
        }

        if values.fade > 0.001 {
            let fade = CIFilter.colorMatrix()
            let scale = 1 - values.fade * 0.34
            let bias = values.fade * 0.17
            fade.inputImage = output
            fade.rVector = CIVector(x: scale, y: 0, z: 0, w: 0)
            fade.gVector = CIVector(x: 0, y: scale, z: 0, w: 0)
            fade.bVector = CIVector(x: 0, y: 0, z: scale, w: 0)
            fade.biasVector = CIVector(x: bias, y: bias, z: bias, w: 0)
            output = fade.outputImage ?? output
        }

        output = applyCurves(output, curves: curves)

        if values.sharpen > 0.001 {
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = output
            sharpen.sharpness = Float(values.sharpen * 1.4)
            output = sharpen.outputImage ?? output
        }

        if values.vignette > 0.001 {
            let vignette = CIFilter.vignette()
            vignette.inputImage = output
            vignette.intensity = Float(values.vignette * 2)
            vignette.radius = Float(min(output.extent.width, output.extent.height) * 0.75)
            output = vignette.outputImage ?? output
        }

        if values.grain > 0.001, let random = CIFilter(name: "CIRandomGenerator")?.outputImage {
            let monochrome = random.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            let alpha = monochrome.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.16, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.16, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.16, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: values.grain * 0.35),
            ]).cropped(to: output.extent)
            output = alpha.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: output]).cropped(to: output.extent)
        }

        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    private static func applyCurves(_ image: CIImage, curves: TelegramPhotoCurves) -> CIImage {
        var output = image
        if curves.all != .neutral {
            let tone = CIFilter.toneCurve()
            tone.inputImage = output
            let points = curves.all.values
            tone.point0 = CGPoint(x: 0, y: points[0])
            tone.point1 = CGPoint(x: 0.25, y: points[1])
            tone.point2 = CGPoint(x: 0.5, y: points[2])
            tone.point3 = CGPoint(x: 0.75, y: points[3])
            tone.point4 = CGPoint(x: 1, y: points[4])
            output = tone.outputImage ?? output
        }
        guard curves.red != .neutral || curves.green != .neutral || curves.blue != .neutral else { return output }

        let dimension = 32
        var cube = [Float](repeating: 0, count: dimension * dimension * dimension * 4)
        var offset = 0
        for blue in 0..<dimension {
            for green in 0..<dimension {
                for red in 0..<dimension {
                    cube[offset] = Float(curveValue(Double(red) / Double(dimension - 1), curve: curves.red))
                    cube[offset + 1] = Float(curveValue(Double(green) / Double(dimension - 1), curve: curves.green))
                    cube[offset + 2] = Float(curveValue(Double(blue) / Double(dimension - 1), curve: curves.blue))
                    cube[offset + 3] = 1
                    offset += 4
                }
            }
        }
        let data = cube.withUnsafeBufferPointer { Data(buffer: $0) }
        return output.applyingFilter("CIColorCube", parameters: ["inputCubeDimension": dimension, "inputCubeData": data])
    }

    private static func curveValue(_ input: Double, curve: TelegramPhotoCurve) -> Double {
        let values = curve.values
        let position = min(max(input, 0), 1) * 4
        let lower = min(Int(position), 3)
        let fraction = position - Double(lower)
        return values[lower] + (values[lower + 1] - values[lower]) * fraction
    }

    private static func cropped(_ image: UIImage, preset: TelegramPhotoCropPreset) -> UIImage {
        guard preset != .original, let cgImage = image.cgImage else { return image }
        let targetRatio = preset.aspectRatio(for: image.size, quarterTurns: 0)
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let currentRatio = width / max(height, 1)
        let cropRect: CGRect
        if currentRatio > targetRatio {
            let cropWidth = height * targetRatio
            cropRect = CGRect(x: (width - cropWidth) / 2, y: 0, width: cropWidth, height: height)
        } else {
            let cropHeight = width / targetRatio
            cropRect = CGRect(x: 0, y: (height - cropHeight) / 2, width: width, height: cropHeight)
        }
        guard let cropped = cgImage.cropping(to: cropRect.integral) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }

    private static func blurred(_ image: UIImage, value: TelegramPhotoBlur) -> UIImage? {
        guard value.mode != .off, let input = CIImage(image: image) else { return image }
        let radius = max(input.extent.width, input.extent.height) * value.intensity * 0.035
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: input.extent)
        let center = CGPoint(
            x: input.extent.minX + input.extent.width * value.position.x,
            y: input.extent.minY + input.extent.height * (1 - value.position.y)
        )
        let base = min(input.extent.width, input.extent.height)
        let inner = base * value.size
        let outer = inner + base * value.falloff
        let mask: CIImage

        switch value.mode {
        case .off:
            return image
        case .radial, .portrait:
            let gradient = CIFilter.radialGradient()
            gradient.center = center
            gradient.radius0 = Float(inner)
            gradient.radius1 = Float(max(outer, inner + 1))
            gradient.color0 = CIColor.black
            gradient.color1 = CIColor.white
            mask = (gradient.outputImage ?? CIImage.empty()).cropped(to: input.extent)
        case .linear:
            let angle = CGFloat(value.rotation)
            let normal = CGVector(dx: -sin(angle), dy: cos(angle))
            let p0 = CGPoint(x: center.x + normal.dx * inner, y: center.y + normal.dy * inner)
            let p1 = CGPoint(x: center.x + normal.dx * outer, y: center.y + normal.dy * outer)
            let p2 = CGPoint(x: center.x - normal.dx * inner, y: center.y - normal.dy * inner)
            let p3 = CGPoint(x: center.x - normal.dx * outer, y: center.y - normal.dy * outer)
            let first = CIFilter.smoothLinearGradient()
            first.point0 = p0
            first.point1 = p1
            first.color0 = CIColor.black
            first.color1 = CIColor.white
            let second = CIFilter.smoothLinearGradient()
            second.point0 = p2
            second.point1 = p3
            second.color0 = CIColor.black
            second.color1 = CIColor.white
            mask = (first.outputImage ?? CIImage.empty())
                .applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: second.outputImage ?? CIImage.empty()])
                .cropped(to: input.extent)
        }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = blurred
        blend.backgroundImage = input
        blend.maskImage = mask
        guard let output = blend.outputImage, let cgImage = context.createCGImage(output, from: input.extent) else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    private static func composited(
        _ image: UIImage,
        drawing: PKDrawing,
        drawingCanvasSize: CGSize,
        textOverlays: [TelegramPhotoTextOverlay],
        stickerOverlays: [TelegramPhotoStickerOverlay]
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let outputRect = CGRect(origin: .zero, size: image.size)

        return UIGraphicsImageRenderer(size: image.size, format: format).image { renderer in
            image.draw(in: outputRect)

            if !drawing.strokes.isEmpty, drawingCanvasSize.width > 0, drawingCanvasSize.height > 0 {
                let drawingImage = drawing.image(from: CGRect(origin: .zero, size: drawingCanvasSize), scale: image.size.width / drawingCanvasSize.width)
                drawingImage.draw(in: outputRect)
            }

            for overlay in textOverlays where !overlay.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                drawText(overlay, in: outputRect, context: renderer.cgContext)
            }
            for sticker in stickerOverlays {
                drawSticker(sticker, in: outputRect, context: renderer.cgContext)
            }
        }
    }

    private static func drawText(_ overlay: TelegramPhotoTextOverlay, in rect: CGRect, context: CGContext) {
        let fontSize = max(22, rect.width * 0.065 * overlay.scale)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        var attributes: [NSAttributedString.Key: Any] = [
            .font: overlay.font.font(size: fontSize),
            .foregroundColor: overlay.style == .filled ? UIColor.black : overlay.color.uiColor,
            .paragraphStyle: paragraph,
        ]
        if overlay.style == .outline {
            attributes[.strokeColor] = UIColor.black
            attributes[.strokeWidth] = -max(2, fontSize * 0.07)
        } else if overlay.style == .regular {
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.7)
            shadow.shadowBlurRadius = max(2, fontSize * 0.06)
            shadow.shadowOffset = CGSize(width: 0, height: 1)
            attributes[.shadow] = shadow
        }
        let attributed = NSAttributedString(string: overlay.text, attributes: attributes)
        let maxWidth = rect.width * 0.86
        var measured = attributed.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).integral
        measured.size.width = min(maxWidth, max(measured.width, fontSize))
        let center = CGPoint(x: rect.width * overlay.normalizedPosition.x, y: rect.height * overlay.normalizedPosition.y)

        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: CGFloat(overlay.rotation))
        let drawRect = CGRect(x: -measured.width / 2, y: -measured.height / 2, width: measured.width, height: measured.height)
        if overlay.style == .filled {
            let background = UIBezierPath(roundedRect: drawRect.insetBy(dx: -fontSize * 0.22, dy: -fontSize * 0.12), cornerRadius: fontSize * 0.22)
            overlay.color.uiColor.setFill()
            background.fill()
        }
        attributed.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        context.restoreGState()
    }

    private static func drawSticker(_ sticker: TelegramPhotoStickerOverlay, in rect: CGRect, context: CGContext) {
        let fontSize = max(44, rect.width * 0.14 * sticker.scale)
        let attributed = NSAttributedString(string: sticker.content, attributes: [.font: UIFont.systemFont(ofSize: fontSize)])
        let size = attributed.size()
        let center = CGPoint(x: rect.width * sticker.normalizedPosition.x, y: rect.height * sticker.normalizedPosition.y)
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: CGFloat(sticker.rotation))
        attributed.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
        context.restoreGState()
    }
}
