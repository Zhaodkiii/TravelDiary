import PencilKit
import Testing
import UIKit
@testable import TravelDiary

@MainActor
struct TelegramPhotoEditorRendererTests {
    @Test
    func squareCropProducesSquareImage() throws {
        let source = makeImage(size: CGSize(width: 1200, height: 800))
        let rendered = try #require(
            TelegramPhotoEditorRenderer.render(
                sourceImage: source,
                adjustments: .neutral,
                curves: .neutral,
                cropPreset: .square,
                quarterTurns: 0,
                straightenDegrees: 0,
                isFlippedHorizontally: false,
                blur: .off,
                drawing: PKDrawing(),
                drawingCanvasSize: CGSize(width: 300, height: 300),
                textOverlays: [],
                stickerOverlays: []
            )
        )

        #expect(abs(rendered.size.width - rendered.size.height) < 1)
    }

    @Test
    func quarterTurnSwapsImageDimensions() throws {
        let source = makeImage(size: CGSize(width: 1200, height: 800))
        let rendered = try #require(
            TelegramPhotoEditorRenderer.render(
                sourceImage: source,
                adjustments: .neutral,
                curves: .neutral,
                cropPreset: .original,
                quarterTurns: 1,
                straightenDegrees: 0,
                isFlippedHorizontally: false,
                blur: .off,
                drawing: PKDrawing(),
                drawingCanvasSize: CGSize(width: 200, height: 300),
                textOverlays: [],
                stickerOverlays: []
            )
        )

        #expect(rendered.size.height > rendered.size.width)
        #expect(abs(rendered.size.width - 800) < 1)
        #expect(abs(rendered.size.height - 1200) < 1)
    }

    private func makeImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
