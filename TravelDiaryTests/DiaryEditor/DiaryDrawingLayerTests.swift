import Testing
import UIKit
import PencilKit
@testable import TravelDiary

@MainActor
struct DiaryDrawingLayerTests {
    private func session() -> DiaryEditorSession {
        DiaryEditorSession(document: DiaryDocument(), images: [:],
            store: DiaryDocumentStore(ownerID: "drawing-layer-tests",
                baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
    }

    private func drawing() -> PKDrawing {
        let points = [CGPoint(x: 100, y: 200), CGPoint(x: 160, y: 260)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                size: CGSize(width: 12, height: 12), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue),
            path: PKStrokePath(controlPoints: points, creationDate: Date()))])
    }

    @Test func eachDraftCreatesAnIndependentUndoableLayer() throws {
        let session = session()
        let ink = drawing()
        let first = try #require(session.addDrawingLayer(ink))
        let second = try #require(session.addDrawingLayer(ink))
        #expect(first != second)
        #expect(session.scopeLayers.map(\.id) == [first, second])
        #expect(session.scopeLayers[0].contentID != session.scopeLayers[1].contentID)
        #expect(session.selectedID == second)
        #expect(session.drawing.strokes.isEmpty)
        #expect(session.undoStack.count == 2)
        session.undo()
        #expect(session.scopeLayers.map(\.id) == [first])
        session.redo()
        #expect(session.scopeLayers.map(\.id) == [first, second])
        let before = session.document
        #expect(session.addDrawingLayer(PKDrawing()) == nil)
        #expect(session.document == before)
        #expect(session.undoStack.count == 2)
    }

    @Test func tightBoundsPreservePositionAndUseCommonRenderingAndHitTesting() throws {
        let session = session()
        let ink = drawing()
        let id = try #require(session.addDrawingLayer(ink))
        let layer = try #require(session.document.layer(id))
        let contentID = try #require(layer.contentID)
        let child = try #require(session.document.objects[contentID])
        let localInk = try PKDrawing(data: child.drawing)
        let localBounds = DiaryPageRenderer.bounds(layer, document: session.document, siblings: session.scopeLayers)
        let placed = localInk.transformed(using: layer.transform.matrix)
        #expect(abs(placed.bounds.minX - ink.bounds.minX) < 0.01)
        #expect(abs(placed.bounds.minY - ink.bounds.minY) < 0.01)
        #expect(layer.size == ink.bounds.integral.size)
        let cache = DiaryCanvasRenderCache()
        cache.synchronize(document: session.document, images: [:], contentID: session.contentID)
        let entry = try #require(cache.entries[id])
        cache.rasterize(entry)
        #expect(entry.image != nil)
        let hit = CGPoint(x: 130 - ink.bounds.integral.minX, y: 230 - ink.bounds.integral.minY)
        #expect(localBounds.contains(hit))
        #expect(DiaryLayerHitTester.contains(hit, layer: layer, document: session.document,
            siblings: session.scopeLayers, images: [:]))
        session.previewOpacity(0.4)
        session.finishInteraction()
        #expect(session.selected?.effectiveOpacity == 0.4)
        session.toggleVisibility(id)
        #expect(session.selected?.visible == false)
        session.toggleLock(id)
        let locked = session.document
        session.removeSelected()
        #expect(session.document == locked)
    }

    @Test func saveReloadRetainsSeparateDrawingAndLegacyInk() async throws {
        let session = session()
        let ink = drawing()
        session.beginInteraction()
        session.previewDrawing(ink)
        session.finishInteraction()
        let legacy = session.content.drawing
        let id = try #require(session.addDrawingLayer(ink))
        try await session.save()
        let loaded = try await session.store.load(session.document.id)
        #expect(loaded.document.root.drawing == legacy)
        let layer = try #require(loaded.document.layer(id))
        let contentID = try #require(layer.contentID)
        let child = try #require(loaded.document.objects[contentID])
        #expect(try PKDrawing(data: child.drawing).strokes.count == 1)
        session.removeSelected()
        #expect(session.document.layer(id) == nil)
        #expect(session.content.drawing == legacy)
        session.undo()
        #expect(session.document.layer(id) != nil)
    }

    @Test func drawingSupportsReorderDuplicationAndTransform() throws {
        let session = session()
        let first = try #require(session.addDrawingLayer(drawing()))
        let second = try #require(session.addDrawingLayer(drawing()))
        session.moveLayer(first, to: 1)
        #expect(session.scopeLayers.map(\.id) == [second, first])
        session.select(first)
        #expect(session.canTransformSelection)
        session.updatePlacement(first, position: CGPoint(x: 300, y: 400), scale: 2, angle: 45)
        #expect(session.selected?.transform.position == CGPoint(x: 300, y: 400))
        #expect(session.selected?.transform.scale == 2)
        #expect(session.selected?.transform.rotationDegrees == 45)
        session.duplicateSelected()
        let copy = try #require(session.selected)
        #expect(copy.id != first)
        #expect(copy.contentID != session.document.layer(first)?.contentID)
        let copyContentID = try #require(copy.contentID)
        let copyContent = try #require(session.document.objects[copyContentID])
        #expect(try PKDrawing(data: copyContent.drawing).strokes.count == 1)
    }

    @Test func reopenSavedDrawingUpdatesSameLayerAndPreservesPlacement() async throws {
        let original = session()
        let id = try #require(original.addDrawingLayer(drawing()))
        original.updatePlacement(id, position: CGPoint(x: 350, y: 460), scale: 1.8, angle: 37)
        original.previewOpacity(0.45)
        original.finishInteraction()
        _ = original.addDrawingLayer(drawing())
        try await original.save()
        let loaded = try await original.store.load(original.document.id)
        let session = DiaryEditorSession(document: loaded.document, images: loaded.images, store: original.store)
        session.select(id)
        #expect(session.selectedEditingKind == .drawing)
        #expect(session.contextActions.contains(.editDrawing))
        let layer = try #require(session.selected)
        let order = session.scopeLayers.map(\.id)
        let child = try #require(session.openObject())
        let initial = child.drawing
        #expect(initial.strokes.count == 1)
        let edited = PKDrawing(strokes: initial.strokes + initial.strokes)
        let committed = await child.saveDrawingEdits(edited)
        #expect(committed)
        #expect(session.selected == layer)
        #expect(session.scopeLayers.map(\.id) == order)
        #expect(session.undoStack.count == 1)
        let contentID = try #require(layer.contentID)
        let content = try #require(session.document.objects[contentID])
        #expect(try PKDrawing(data: content.drawing).strokes.count == 2)
        session.undo()
        let undone = try #require(session.document.objects[contentID])
        #expect(try PKDrawing(data: undone.drawing).strokes.count == 1)
        session.redo()
        try await session.save()
        let reopened = try await session.store.load(session.document.id)
        let saved = try #require(reopened.document.objects[contentID])
        #expect(try PKDrawing(data: saved.drawing).strokes.count == 2)
    }

    @Test func cancelDrawingEditLeavesOriginalUntouched() async throws {
        let session = session()
        let id = try #require(session.addDrawingLayer(drawing()))
        let before = session.document
        let historyCount = session.undoStack.count
        let child = try #require(session.openObject())
        child.beginInteraction()
        child.previewDrawing(PKDrawing())
        child.finishInteraction()
        #expect(session.document == before)
        await child.cancelEditor()
        #expect(session.document == before)
        #expect(session.selectedID == id)
        #expect(session.undoStack.count == historyCount)
        // Cancelling also releases the parent so this same layer can be reopened.
        let reopened = try #require(session.openObject())
        #expect(reopened.drawing.strokes.count == 1)
        await reopened.cancelEditor()
    }

    @Test func clearDrawingCanBeReeditedAndDoesNotChangeDuplicate() async throws {
        let session = session()
        let originalID = try #require(session.addDrawingLayer(drawing()))
        session.duplicateSelected()
        let copy = try #require(session.selected)
        let child = try #require(session.openObject())
        let cleared = await child.saveDrawingEdits(PKDrawing())
        #expect(cleared)
        #expect(session.selected?.id == copy.id)
        #expect(session.selectedEditingKind == .drawing)
        let originalLayer = try #require(session.document.layer(originalID))
        let originalContentID = try #require(originalLayer.contentID)
        let original = try #require(session.document.objects[originalContentID])
        #expect(try PKDrawing(data: original.drawing).strokes.count == 1)
        let reopened = try #require(session.openObject())
        #expect(reopened.drawing.strokes.isEmpty)
        await reopened.cancelEditor()
        session.toggleLock(copy.id)
        #expect(!session.contextActions.contains(.editDrawing))
        #expect(session.openObject() == nil)
    }

    @Test func groupContainingDrawingKeepsGroupEditor() throws {
        let original = session()
        _ = original.addDrawingLayer(drawing())
        let drawingLayer = try #require(original.selected)
        var document = original.document
        let group = DiaryObjectContent(role: .canvas, referenceSize: drawingLayer.size, layers: [drawingLayer])
        document.objects[group.id] = group
        let wrapper = DiaryLayer(name: "组合", kind: .object,
            transform: DiaryTransform(position: .zero, pivot: .zero), size: drawingLayer.size, contentID: group.id)
        document.objects[document.rootContentID]?.layers = [wrapper]
        let session = DiaryEditorSession(document: document, images: [:], store: original.store)
        session.select(wrapper.id)
        #expect(session.selectedEditingKind == .group)
        #expect(session.contextActions.contains(.editContent))
        #expect(!session.contextActions.contains(.editDrawing))
    }
}
