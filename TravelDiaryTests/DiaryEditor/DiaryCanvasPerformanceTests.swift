import Testing
import UIKit
import PencilKit
import SwiftUI
@testable import TravelDiary

@MainActor
struct DiaryCanvasPerformanceTests {
    private func fixture(count: Int = 1) -> (DiaryDocument, [UUID: UIImage]) {
        var document = DiaryDocument()
        document.objects[document.rootContentID]?.referenceSize = CGSize(width: 200, height: 200)
        document.objects[document.rootContentID]?.background = .white
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format).image { _ in
            UIColor.red.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 100, height: 10))
        }
        let asset = DiaryAsset(id: UUID(), path: "assets/test.png", pixelSize: image.size)
        document.assets[asset.id] = asset
        for i in 0..<count {
            let layer = DiaryLayer(name: "layer \(i)", kind: .sticker,
                transform: DiaryTransform(position: CGPoint(x: i, y: i), pivot: .zero), size: image.size, assetID: asset.id)
            document.appendObject(containing: layer)
        }
        return (document, [asset.id: image])
    }
    private func cache(_ document: DiaryDocument, _ images: [UUID: UIImage]) -> DiaryCanvasRenderCache {
        let cache = DiaryCanvasRenderCache()
        cache.synchronize(document: document, images: images, contentID: document.rootContentID)
        cache.prepareResolution(pointsToPixels: 1)
        for entry in cache.ordered { cache.rasterize(entry) }
        cache.rasterizeInk()
        return cache
    }
    private func session(_ document: DiaryDocument, _ images: [UUID: UIImage]) -> DiaryEditorSession {
        DiaryEditorSession(document: document, images: images,
            store: DiaryDocumentStore(ownerID: "canvas-tests", baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
    }

    @Test func selectionAndToolsDoNotSynchronizeArtwork() {
        let (document, images) = fixture(count: 50)
        let session = session(document, images)
        let surface = DiaryCanvasSurface(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        surface.session = session; surface.refresh()
        let syncs = surface.renderCache.synchronizationCount
        let version = surface.renderCache.visualVersion
        for i in 0..<50 {
            session.select(i % 2 == 0 ? document.root.layers[i].id : nil)
            session.inkMode.toggle(); session.eraser.toggle()
            surface.refresh()
        }
        #expect(surface.renderCache.synchronizationCount == syncs)
        #expect(surface.renderCache.visualVersion == version)
    }

    @Test func selectionKeepsToolbarHeightAndViewport() {
        let (document, images) = fixture()
        let session = session(document, images)
        func toolbarHeight() -> CGFloat {
            let host = UIHostingController(rootView: DiaryContextToolbar(session: session,
                onPhotos: {}, onCamera: {}, onDrawing: {}, onLayers: {}, onStickers: {}, onOpenObject: {}))
            return host.sizeThatFits(in: CGSize(width: 390, height: 1000)).height
        }
        let height = toolbarHeight()
        session.select(document.root.layers[0].id)
        #expect(abs(toolbarHeight() - height) < 0.01)
        session.select(nil)
        #expect(abs(toolbarHeight() - height) < 0.01)
    }

    @Test func resourceRefreshKeepsPreviousImageUntilReplacementIsReady() throws {
        let (document, images) = fixture()
        let cache = cache(document, images)
        let oldImage = try #require(cache.ordered[0].image)
        let assetID = try #require(images.keys.first)
        var loaded = images
        loaded[assetID] = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200)).image { _ in
            UIColor.blue.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        cache.synchronize(document: document, images: loaded, contentID: document.rootContentID)
        let replacement = cache.ordered[0]
        #expect(replacement.image === oldImage)
        #expect(replacement.needsRaster)
        cache.prepareResolution(pointsToPixels: 2)
        #expect(cache.rasterize(replacement))
        #expect(replacement.image != nil)
        #expect(replacement.image !== oldImage)
        #expect(!replacement.needsRaster)
    }

    @Test func resizingReusesDisplayedPixelsUntilNewResolutionIsReady() throws {
        let (document, images) = fixture()
        var resized = document
        let cache = cache(document, images)
        let entry = cache.ordered[0]
        let oldImage = try #require(entry.image)
        resized.objects[document.rootContentID]?.layers[0].transform.scale = 2
        cache.synchronize(document: resized, images: images, contentID: document.rootContentID)
        cache.prepareResolution(pointsToPixels: 1)
        #expect(cache.ordered[0] === entry)
        #expect(entry.image === oldImage)
        #expect(entry.needsRaster)
        #expect(cache.rasterize(entry))
        #expect(entry.image !== oldImage)
        #expect(!entry.needsRaster)
    }

    @Test func transformsReusePixelsAndCommitOneUndo() throws {
        let (document, images) = fixture()
        let session = session(document, images)
        session.select(document.root.layers[0].id)
        let cache = cache(document, images)
        let first = try #require(cache.ordered.first)
        let image = first.image
        var layer = try #require(session.selected)
        layer.transform.position = CGPoint(x: 42, y: 13)
        layer.transform.rotationDegrees = 35
        session.commitTransform(layer)
        #expect(session.undoStack.count == 1)
        cache.synchronize(document: session.document, images: images, contentID: document.rootContentID)
        #expect(cache.ordered[0] === first)
        #expect(cache.ordered[0].image === image)
        #expect(!cache.ordered[0].needsRaster)
        session.commitTransform(layer)
        #expect(session.undoStack.count == 1)
        session.undo()
        #expect(session.document.root.layers[0].transform == document.root.layers[0].transform)
    }

    @Test func nestedChangesUndoAndBranchInvalidateOnlyAffectedObject() throws {
        var (document, images) = fixture(count: 2)
        let original = document
        let cache = cache(document, images)
        let id = try #require(document.root.layers[0].contentID)
        let before = cache.ordered[0].version
        let other = cache.ordered[1]
        document.objects[id]?.layers[0].crop.zoom = 2
        cache.synchronize(document: document, images: images, contentID: document.rootContentID)
        let changed = cache.ordered[0].version
        #expect(changed != before)
        #expect(cache.ordered[1] === other)
        cache.synchronize(document: original, images: images, contentID: document.rootContentID)
        #expect(cache.ordered[0].version != changed)
        document = original
        document.objects[id]?.layers[0].crop.zoom = 3
        cache.synchronize(document: document, images: images, contentID: document.rootContentID)
        #expect(cache.ordered[0].version != before)
        #expect(cache.ordered[1] === other)
    }

    @Test func locksDoNotChangeVisualVersionButVisibilityDoes() {
        var (document, images) = fixture()
        let cache = cache(document, images)
        let entry = cache.ordered[0], version = cache.visualVersion
        document.objects[document.rootContentID]?.layers[0].locked = true
        cache.synchronize(document: document, images: images, contentID: document.rootContentID)
        #expect(cache.visualVersion == version)
        #expect(cache.ordered[0] === entry)
        document.objects[document.rootContentID]?.layers[0].visible = false
        cache.synchronize(document: document, images: images, contentID: document.rootContentID)
        #expect(cache.visualVersion != version)
        #expect(cache.ordered[0].image == nil)
    }

    @Test func cachedAlphaPreservesTopOriginAndTransparentHole() throws {
        let (document, images) = fixture()
        let cache = cache(document, images)
        let entry = try #require(cache.ordered.first)
        #expect(cache.contains(CGPoint(x: 50, y: 5), entry: entry))
        #expect(!cache.contains(CGPoint(x: 50, y: 95), entry: entry))
        #expect(!cache.contains(CGPoint(x: 50, y: 50), entry: entry))
        let rasters = cache.rasterCount
        for _ in 0..<100 { _ = cache.contains(CGPoint(x: 50, y: 5), entry: entry) }
        #expect(cache.rasterCount == rasters)
    }

    @Test func replacementInvalidatesPixelsButUnrelatedImageDoesNot() throws {
        let (document, images) = fixture()
        let cache = cache(document, images)
        let entry = cache.ordered[0]
        var changed = images
        changed[UUID()] = UIImage()
        cache.synchronize(document: document, images: changed, contentID: document.rootContentID)
        #expect(cache.ordered[0] === entry)
        let assetID = try #require(images.keys.first)
        changed[assetID] = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { _ in
            UIColor.blue.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        cache.synchronize(document: document, images: changed, contentID: document.rootContentID)
        #expect(cache.ordered[0] !== entry)
        cache.prepareResolution(pointsToPixels: 1)
        #expect(cache.contains(CGPoint(x: 50, y: 50), entry: cache.ordered[0]))
    }

    @Test func manyLayersSharePixelBudget() {
        let (document, images) = fixture(count: 100)
        let cache = cache(document, images)
        cache.prepareResolution(pointsToPixels: 20)
        let pixels = cache.ordered.reduce(CGFloat.zero) { $0 + $1.rect.width * $1.rect.height * $1.requestedScale * $1.requestedScale }
        #expect(pixels <= DiaryCanvasRenderCache.pixelBudget + 1)
    }

    @Test func mixedCompositionMatchesExistingRenderer() throws {
        for blend in [DiaryBlendMode.normal, .multiply, .darken, .linearBurn, .lighten] {
            var (document, images) = fixture(count: 2)
            document.objects[document.rootContentID]?.layers[1].blendMode = blend
            document.objects[document.rootContentID]?.layers[1].transform.position = CGPoint(x: 20, y: 5)
            let cache = cache(document, images)
            let view = DiaryCanvasArtworkView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
            view.cache = cache; view.composited = true; view.contentScaleFactor = 1
            view.setNeedsDisplay(); view.layer.displayIfNeeded()
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false; format.preferredRange = .standard
            let actual = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { r in view.layer.render(in: r.cgContext) }
            let expected = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { r in
                DiaryPageRenderer.draw(document, images: images, in: r.cgContext)
            }
            let a = try #require(actual.cgImage?.dataProvider?.data) as Data
            let e = try #require(expected.cgImage?.dataProvider?.data) as Data
            if a != e {
                let folder = FileManager.default.temporaryDirectory
                try actual.pngData()?.write(to: folder.appendingPathComponent("canvas-actual-\(blend.rawValue).png"))
                try expected.pngData()?.write(to: folder.appendingPathComponent("canvas-expected-\(blend.rawValue).png"))
                let deltas = zip(a, e).map { abs(Int($0) - Int($1)) }
                print("CANVAS-DIFF \(blend) mean=\(Double(deltas.reduce(0,+))/Double(deltas.count)) max=\(deltas.max() ?? 0) count=\(deltas.filter { $0 > 0 }.count) files=\(folder.path)")
            }
            #expect(a == e, "blend: \(blend)")
        }
    }

    @Test func retainedLayerPlacementAndLinkedFrameFollowTransform() throws {
        var (document, images) = fixture()
        let child = try #require(document.root.layers[0].contentID)
        document.objects[child]?.layers[0].transform.position = CGPoint(x: 10, y: 20)
        document.objects[document.rootContentID]?.layers[0].transform.position = CGPoint(x: 150, y: 50)
        document.objects[document.rootContentID]?.layers[0].transform.rotationDegrees = 90
        let source = document.root.layers[0]
        let frame = DiaryLayer(name: "frame", kind: .frame, transform: source.transform, size: source.size,
            frameTargetID: source.id, frameColor: .white, frameWidth: 5)
        document.objects[document.rootContentID]?.layers.append(frame)
        let session = session(document, images)
        let surface = DiaryCanvasSurface(frame: CGRect(x: 0, y: 0, width: 312, height: 312))
        surface.session = session; surface.refresh()
        for entry in surface.renderCache.ordered { surface.renderCache.rasterize(entry) }
        surface.refresh(force: true)
        let artwork = try #require(surface.subviews.first)
        let retained = try #require(artwork.layer.sublayers?.first { $0.name == source.id.uuidString })
        let cachedImage = surface.renderCache.entries[source.id]?.image
        #expect(abs(retained.position.x - 130) < 0.001)
        #expect(abs(retained.position.y - 60) < 0.001)
        session.select(source.id)
        var moved = source
        moved.transform.position.x += 30
        session.commitTransform(moved)
        surface.refresh()
        let linked = try #require(artwork.layer.sublayers?.first { $0.name == frame.id.uuidString })
        let frameRect = try #require(surface.renderCache.entries[frame.id]?.rect)
        let expected = frameRect.origin.applying(moved.transform.matrix)
        #expect(abs(linked.position.x - expected.x) < 0.001)
        #expect(abs(linked.position.y - expected.y) < 0.001)
        #expect(surface.renderCache.entries[source.id]?.image === cachedImage)
    }

    @Test func decodedImagePlanHonorsBudgetAndHiddenLayerResolution() {
        var document = DiaryDocument()
        for i in 0..<100 {
            let asset = DiaryAsset(id: UUID(), path: "assets/\(i).png", pixelSize: CGSize(width: 4000, height: 4000))
            document.assets[asset.id] = asset
            document.objects[document.rootContentID]?.layers.append(DiaryLayer(name: "photo", kind: .sticker,
                transform: DiaryTransform(position: .zero, pivot: .zero), size: CGSize(width: 1500, height: 1500),
                assetID: asset.id, visible: i != 0))
        }
        let plan = DiaryEditorImageSizing.plan(document, contentID: document.rootContentID, longestEdge: 4000)
        let pixels = plan.values.reduce(0) { $0 + $1 * $1 }
        #expect(pixels <= 40 * 1024 * 1024 / 4)
        #expect((plan[document.root.layers[0].assetID!] ?? 10000) <= 96)
    }

    @Test func drawingFlushRunsBeforeHistoryCommit() {
        let (document, images) = fixture()
        let session = session(document, images)
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 30)].map {
            PKStrokePoint(location: $0, timeOffset: 0, size: CGSize(width: 5, height: 5), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))])
        session.beginInteraction()
        session.flushDrawingInteraction = { [weak session] in session?.previewDrawing(drawing) }
        session.finishInteraction()
        session.flushDrawingInteraction = nil
        #expect(session.undoStack.count == 1)
        #expect(session.drawing.strokes.count == 1)
        session.undo()
        #expect(session.drawing.strokes.isEmpty)
    }
}
