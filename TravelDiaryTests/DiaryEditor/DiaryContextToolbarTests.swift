import Testing
import UIKit
import SwiftUI
@testable import TravelDiary

@MainActor
struct DiaryContextToolbarTests {
    private func makeSession(_ layers: [DiaryLayer], wrapped: Bool = true) -> DiaryEditorSession {
        var document = DiaryDocument()
        for layer in layers {
            if wrapped { document.appendObject(containing: layer) }
            else { document.objects[document.rootContentID]?.layers.append(layer) }
        }
        return DiaryEditorSession(document: document, images: [:], store: DiaryDocumentStore(ownerID: "context-toolbar-tests",
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
    }
    private func layer(_ kind: DiaryLayer.Kind, semantic: DiaryLayerSemanticKind? = nil) -> DiaryLayer {
        DiaryLayer(name: "内容", kind: kind, transform: DiaryTransform(position: CGPoint(x: 200, y: 200), pivot: .zero),
                   size: CGSize(width: 100, height: 100), semanticKind: semantic, text: "旅行日记")
    }

    @Test func resolvesWrappedContentAndKeepsExactToolOrder() throws {
        let session = makeSession([layer(.photo), layer(.text), layer(.sticker), layer(.sticker, semantic: .paper), layer(.sticker, semantic: .text)])
        #expect(session.contextActions == [.background, .layers])
        let expected: [[DiaryContextAction]] = [
            [.replacePhoto, .crop, .frame, .opacity, .arrange],
            [.editText, .font, .fontSize, .textColor, .typography],
            [.replaceMaterial, .flip, .opacity, .arrange],
            [.replaceMaterial, .opacity, .arrange],
            [.replaceMaterial, .opacity, .arrange]
        ]
        for (index, actions) in expected.enumerated() {
            session.select(session.scopeLayers[index].id)
            #expect(session.contextActions == actions)
        }
        #expect(session.selectedEditingKind == .textImage)
        let target = try #require(session.selectedEditingLayer)
        #expect(!session.applyTextEdit(targetID: target.id, text: "错误", fontSize: 20, font: nil))
    }

    @Test func backgroundFrameAndLockedStates() throws {
        let session = makeSession([layer(.sticker, semantic: .background), layer(.frame)], wrapped: false)
        let background = session.scopeLayers[0].id
        session.select(background)
        #expect(session.contextActions == [.replaceBackground, .placement, .opacity, .lock])
        session.toggleLock(background)
        #expect(session.contextActions == [.unlock, .layers])
        let before = session.document
        session.setLayerOpacity(background, value: 0.2)
        session.flipSelected(horizontal: true)
        #expect(session.document == before)
        session.select(session.scopeLayers[1].id)
        #expect(session.contextActions == [.frameColor, .frameWidth, .opacity])
    }

    @Test func mixedGroupOffersOnlyUnlockedPhotoTargets() throws {
        var document = DiaryDocument()
        let photo = layer(.photo)
        var locked = layer(.photo); locked.locked = true
        let content = DiaryObjectContent(role: .object, referenceSize: CGSize(width: 200, height: 200), layers: [photo, locked, layer(.text)])
        document.objects[content.id] = content
        let group = DiaryLayer(name: "组合", kind: .object, transform: DiaryTransform(position: .zero, pivot: .zero), size: content.referenceSize, contentID: content.id)
        document.objects[document.rootContentID]?.layers = [group]
        let session = DiaryEditorSession(document: document, images: [:], store: DiaryDocumentStore(ownerID: "group-test"))
        session.select(group.id)
        #expect(session.contextActions == [.editContent, .replacePhoto, .opacity, .arrange])
        #expect(session.selectedPhotos.map(\.id) == [photo.id])
        #expect(session.editableLayer(locked.id) == nil)
    }

    @Test func nestedTextStylesUndoAndSerializeWithoutMovingObject() throws {
        let session = makeSession([layer(.text)])
        session.select(session.scopeLayers[0].id)
        let outer = try #require(session.selected)
        let text = try #require(session.selectedEditingLayer)
        #expect(session.applyTextEdit(targetID: text.id, text: "杭州旅行", fontSize: 48, font: nil, color: .pink,
                                      alignment: .left, lineHeight: 1.8, letterSpacing: 3))
        #expect(session.selected?.transform == outer.transform)
        #expect(session.undoStack.count == 1)
        let decoded = try JSONDecoder().decode(DiaryDocument.self, from: JSONEncoder().encode(session.document))
        let edited = try #require(decoded.layer(text.id))
        #expect(edited.textColor == .pink && edited.textAlignment == .left)
        #expect(edited.textLineHeight == 1.8 && edited.textLetterSpacing == 3)
        let style = DiaryPageRenderer.textStyle(edited)
        #expect((style[.paragraphStyle] as? NSParagraphStyle)?.alignment == .left)
        #expect(style[.kern] as? Double == 3)
        session.undo()
        #expect(session.document.layer(text.id)?.text == "旅行日记")
        session.redo()
        #expect(session.document.layer(text.id)?.text == "杭州旅行")
    }

    @Test func frameOpacityAndFlipRemainIndependentAndUndoable() throws {
        let session = makeSession([layer(.photo)])
        session.select(session.scopeLayers[0].id)
        session.addFrame()
        let object = try #require(session.selected?.contentID)
        let frame = try #require(session.document.objects[object]?.layers.first { $0.kind == .frame })
        session.updateFrame(frame.id, color: .pink, width: 35)
        #expect(session.document.layer(frame.id)?.frameWidth == 35)
        #expect(session.document.layer(frame.id)?.frameColor == .pink)
        let selectedID = try #require(session.selectedID)
        session.setLayerOpacity(selectedID, value: 0.4)
        #expect(session.selected?.effectiveOpacity == 0.4)
        session.flipSelected(horizontal: true)
        #expect(session.selected?.transform.flippedHorizontally == true)
        session.undo()
        #expect(session.selected?.transform.flippedHorizontally != true)
        #expect(session.selected?.effectiveOpacity == 0.4)
    }
    @Test func materialReplacementPreservesIdentityAndSemanticTools() async throws {
        let session = makeSession([])
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20), format: format).image { _ in
            UIColor.red.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        let data = try #require(image.pngData())
        #expect(await session.importPhoto(data, asSticker: true, stickerName: "文字素材", semanticKind: .text))
        let selected = try #require(session.selected)
        let leaf = try #require(session.selectedMaterialLayer)
        #expect(session.selectedEditingKind == .textImage)
        #expect(await session.importPhoto(data, replacing: leaf.id))
        #expect(session.selectedID == selected.id)
        #expect(session.selected?.transform == selected.transform)
        #expect(session.selectedEditingKind == .textImage)
        #expect(session.document.layer(leaf.id)?.assetID != leaf.assetID)
        session.undo()
        #expect(session.document.layer(leaf.id)?.assetID == leaf.assetID)
        session.toggleLock(selected.id)
        #expect(!(await session.importPhoto(data, replacing: leaf.id)))
    }

    @Test func compactToolbarVisualVerification() async throws {
        let photo = makeSession([layer(.photo)])
        let text = makeSession([layer(.text)])
        let textImage = makeSession([layer(.sticker, semantic: .text)])
        let background = makeSession([layer(.sticker, semantic: .background)])
        for session in [photo, text, textImage, background] { session.select(session.scopeLayers[0].id) }
        let host = UIHostingController(rootView: VStack(spacing: 20) {
            ForEach(Array([photo, text, textImage, background].enumerated()), id: \.offset) { _, session in
                DiaryContextToolbar(session: session, onPhotos: {}, onCamera: {}, onDrawing: {}, onLayers: {}, onStickers: {}, onOpenObject: {})
            }
        }.frame(width: 390).padding(.vertical).background(Color(uiColor: .systemGroupedBackground)))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("diary-context-toolbar-qa.png")
        try #require(image.pngData()).write(to: destination)
        print("Toolbar visual QA: \(destination.path)")
    }

}
