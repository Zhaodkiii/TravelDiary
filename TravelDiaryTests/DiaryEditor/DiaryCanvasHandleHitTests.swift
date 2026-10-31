import Testing
import CoreGraphics
import UIKit
@testable import TravelDiary

struct DiaryCanvasHandleHitTests {
    @Test func circularControlsDoNotCaptureNeighboringText() {
        #expect(DiaryCanvasHandleHitRegion.contains(.zero))
        #expect(DiaryCanvasHandleHitRegion.contains(CGPoint(x: 10, y: 0)))
        #expect(!DiaryCanvasHandleHitRegion.contains(CGPoint(x: 18, y: 0)))
        #expect(!DiaryCanvasHandleHitRegion.contains(CGPoint(x: 12, y: 12)))
    }
    @Test func slimEdgeHandlesFollowRotationWithoutLargeCircularHalo() {
        #expect(DiaryCanvasHandleHitRegion.contains(CGPoint(x: 11, y: 0), edgeAngle: 0))
        #expect(!DiaryCanvasHandleHitRegion.contains(CGPoint(x: 0, y: 12), edgeAngle: 0))
        #expect(DiaryCanvasHandleHitRegion.contains(CGPoint(x: 0, y: 11), edgeAngle: .pi / 2))
        #expect(!DiaryCanvasHandleHitRegion.contains(CGPoint(x: 12, y: 0), edgeAngle: .pi / 2))
    }
    @Test func exteriorExpansionRestoresComfortableTargetsWithoutCoveringInteriorText() {
        #expect(DiaryCanvasHandleHitRegion.contains(CGPoint(x: 20, y: 0), allowsExpansion: true))
        #expect(!DiaryCanvasHandleHitRegion.contains(CGPoint(x: 20, y: 0), allowsExpansion: false))
        for angle in [CGFloat.zero, .pi / 2, .pi, -.pi / 2] {
            let offset = CGPoint(x: -sin(angle) * 16, y: cos(angle) * 16)
            #expect(DiaryCanvasHandleHitRegion.contains(offset, edgeAngle: angle, allowsExpansion: true))
            #expect(!DiaryCanvasHandleHitRegion.contains(offset, edgeAngle: angle, allowsExpansion: false))
        }
    }
    @MainActor private final class Tap: UITapGestureRecognizer {
        var point = CGPoint.zero
        override func location(in view: UIView?) -> CGPoint { point }
    }
    @MainActor private final class Pan: UIPanGestureRecognizer {
        var point = CGPoint.zero
        var offset = CGPoint.zero
        var phase: UIGestureRecognizer.State = .began
        override var state: UIGestureRecognizer.State {
            get { phase }
            set { phase = newValue }
        }
        override func location(in view: UIView?) -> CGPoint { point }
        override func translation(in view: UIView?) -> CGPoint { offset }
    }
    @Test @MainActor func actualCanvasEditMoveAndDeleteControlsWorkNearTheirVisibleEdges() throws {
        var document = DiaryDocument()
        document.objects[document.rootContentID]?.referenceSize = CGSize(width: 200, height: 200)
        var text = DiaryLayer(name: "文字", kind: .text,
            transform: DiaryTransform(position: CGPoint(x: 50, y: 50), pivot: .zero), size: CGSize(width: 100, height: 40))
        text.text = "旅行记录"; text.fontSize = 20
        let id = document.appendObject(containing: text)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = DiaryEditorSession(document: document, images: [:], store: DiaryDocumentStore(ownerID: "handle-test", baseDirectory: folder))
        let surface = DiaryCanvasSurface(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        surface.session = session; session.select(id); surface.refresh(force: true)
        let rect = try #require(surface.renderCache.entries[id]?.rect).insetBy(dx: -3, dy: -3)
        let transform = try #require(session.selected).transform
        let fit = (400 - 2 * DiaryCanvasSurface.controlMargin) / 200
        func screen(_ point: CGPoint) -> CGPoint {
            let value = transform.projection.point(point)
            return CGPoint(x: value.x * fit + DiaryCanvasSurface.controlMargin, y: value.y * fit + DiaryCanvasSurface.controlMargin)
        }
        func tap(_ point: CGPoint) {
            let gesture = Tap(); gesture.point = point
            _ = surface.perform(NSSelectorFromString("tapped:"), with: gesture)
        }
        var edited = false
        surface.onEdit = { edited = true }
        let edit = screen(CGPoint(x: rect.maxX, y: rect.minY))
        tap(CGPoint(x: edit.x + 17, y: edit.y - 2))
        #expect(edited)
        let move = screen(CGPoint(x: rect.minX, y: rect.maxY))
        let origin = CGPoint(x: move.x - 17, y: move.y + 2)
        tap(origin)
        #expect(session.scopeLayers.count == 1)
        #expect(session.selectedID == id)
        let pan = Pan()
        pan.point = origin
        _ = surface.perform(NSSelectorFromString("panned:"), with: pan)
        pan.phase = .changed
        pan.offset = CGPoint(x: 20 * fit, y: 15 * fit)
        pan.point = CGPoint(x: origin.x + pan.offset.x, y: origin.y + pan.offset.y)
        _ = surface.perform(NSSelectorFromString("panned:"), with: pan)
        pan.phase = .ended
        _ = surface.perform(NSSelectorFromString("panned:"), with: pan)
        let moved = try #require(session.selected)
        #expect(abs(moved.transform.position.x - transform.position.x - 20) < 0.001)
        #expect(abs(moved.transform.position.y - transform.position.y - 15) < 0.001)
        #expect(moved.transform.scale == transform.scale)
        #expect(session.scopeLayers.count == 1)
        session.undo()
        session.select(id); surface.refresh(force: true)
        let delete = screen(CGPoint(x: rect.minX, y: rect.minY))
        tap(CGPoint(x: delete.x - 17, y: delete.y - 2))
        #expect(session.document.layer(id) == nil)
    }

}
