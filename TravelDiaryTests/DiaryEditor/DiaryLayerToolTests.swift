import Testing
import UIKit
import SwiftUI
@testable import TravelDiary

@MainActor
struct DiaryLayerToolTests {
    private func session() -> DiaryEditorSession {
        var document = DiaryDocument()
        for name in ["A", "B", "C"] {
            document.objects[document.rootContentID]?.layers.append(DiaryLayer(name: name, kind: .text,
                transform: DiaryTransform(position: .zero, pivot: .zero), size: CGSize(width: 100, height: 100), text: name))
        }
        return DiaryEditorSession(document: document, images: [:], store: DiaryDocumentStore(ownerID: "layer-tool-tests",
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
    }

    @Test func railTracksCanvasSelectionAndCentersEndItems() async throws {
        let session = session()
        let host = UIHostingController(rootView: DiaryLayerThumbnailRail(session: session).frame(height: 90))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        func rail(in view: UIView) -> UICollectionView? {
            if let rail = view as? UICollectionView { return rail }
            return view.subviews.lazy.compactMap { rail(in: $0) }.first
        }
        try await Task.sleep(for: .milliseconds(100))
        let collection = try #require(rail(in: host.view))
        for index in [0, 2, 1] {
            session.select(session.scopeLayers[index].id)
            try await Task.sleep(for: .milliseconds(100))
            collection.layoutIfNeeded()
            let path = IndexPath(item: index, section: 0)
            let cell = try #require(collection.cellForItem(at: path))
            #expect(cell.accessibilityTraits.contains(.selected))
            let attributes = try #require(collection.layoutAttributesForItem(at: path))
            #expect(abs(attributes.center.x - collection.contentOffset.x - collection.bounds.width / 2) < 1)
            for other in collection.visibleCells where other !== cell {
                #expect(!other.accessibilityTraits.contains(.selected))
            }
        }
    }

    @Test func opacityGestureIsOneUndoAndSelectionFinishesIt() throws {
        let session = session()
        let id = session.scopeLayers[0].id
        session.select(id)
        session.previewOpacity(0.8)
        session.previewOpacity(0.3)
        #expect(session.undoStack.isEmpty)
        session.select(session.scopeLayers[1].id)
        #expect(session.undoStack.count == 1)
        #expect(session.document.layer(id)?.effectiveOpacity == 0.3)
        session.undo()
        #expect(session.document.layer(id)?.effectiveOpacity == 1)
        session.redo()
        #expect(session.document.layer(id)?.effectiveOpacity == 0.3)
        let decoded = try JSONDecoder().decode(DiaryDocument.self, from: JSONEncoder().encode(session.document))
        #expect(decoded.layer(id)?.effectiveOpacity == 0.3)
    }

    @Test func reorderDeleteAndLocksKeepStableIdentity() {
        let session = session()
        session.layerMode = true
        let id = session.scopeLayers[0].id
        session.select(id)
        session.moveLayer(id, to: 2)
        #expect(session.scopeLayers.map(\.name) == ["B", "C", "A"])
        #expect(session.selectedID == id)
        #expect(!session.canMoveSelected(forward: true))
        session.toggleVisibility(id)
        #expect(session.selectedID == id)
        session.toggleLock(id)
        let before = session.document
        session.moveLayer(id, to: 0)
        session.removeSelected()
        session.previewOpacity(0.2)
        #expect(session.document == before)
        session.toggleLock(id)
        session.removeSelected()
        #expect(session.selected?.name == "C")
        session.undo()
        #expect(session.scopeLayers.map(\.name) == ["B", "C", "A"])
    }

    @Test func reorderPreviewCanCancelOrCommitAsOneUndo() {
        let session = session()
        let id = session.scopeLayers[0].id
        session.select(id)
        session.previewLayerOrder(id, to: 1)
        session.previewLayerOrder(id, to: 2)
        #expect(session.undoStack.isEmpty)
        #expect(session.scopeLayers.map(\.name) == ["B", "C", "A"])
        session.cancelInteraction()
        #expect(session.scopeLayers.map(\.name) == ["A", "B", "C"])
        session.previewLayerOrder(id, to: 2)
        session.finishInteraction()
        #expect(session.undoStack.count == 1)
        session.undo()
        #expect(session.scopeLayers.map(\.name) == ["A", "B", "C"])
    }

    @Test func legacyLayerDefaultsToOpaque() throws {
        let layer = session().scopeLayers[0]
        let data = try JSONEncoder().encode(layer)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["opacity"] == nil)
        #expect(try JSONDecoder().decode(DiaryLayer.self, from: data).effectiveOpacity == 1)
    }

    @Test func objectOpacityCompositesOnceAndReusesRaster() throws {
        var document = DiaryDocument()
        let child = DiaryObjectContent(role: .sticker, referenceSize: CGSize(width: 10, height: 10), background: .white, layers: [])
        document.objects[child.id] = child
        let layer = DiaryLayer(name: "Group", kind: .object, transform: DiaryTransform(position: .zero, pivot: .zero),
            size: child.referenceSize, contentID: child.id, opacity: 0.5)
        document.objects[document.rootContentID]?.layers = [layer]
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let image = UIGraphicsImageRenderer(size: child.referenceSize, format: format).image { renderer in
            DiaryPageRenderer.draw(document, images: [:], in: renderer.cgContext,
                viewport: CGRect(origin: .zero, size: child.referenceSize), cacheObjects: false)
        }
        let cg = try #require(image.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        #expect(abs(Int(pixel[3]) - 128) <= 1)
        let cache = DiaryCanvasRenderCache()
        cache.synchronize(document: document, images: [:], contentID: document.rootContentID)
        cache.prepareResolution(pointsToPixels: 1)
        let entry = try #require(cache.ordered.first)
        cache.rasterize(entry)
        let raster = entry.image
        let version = cache.visualVersion
        document.update(layer.id) { $0.opacity = 0.2 }
        cache.synchronize(document: document, images: [:], contentID: document.rootContentID)
        #expect(cache.ordered[0].image === raster)
        #expect(cache.visualVersion != version)
    }
}
