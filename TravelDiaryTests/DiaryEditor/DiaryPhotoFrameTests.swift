import Testing
import UIKit
@testable import TravelDiary

@MainActor
struct DiaryPhotoFrameTests {
    @Test func bundledFramesHaveValidTransparentOpenings() throws {
        #expect(DiaryPhotoFrameCatalog.items.count == 55)
        for item in DiaryPhotoFrameCatalog.items {
            let image = try #require(item.image)
            #expect(image.size.width > 0 && image.size.height > 0)
            #expect(item.opening.width > 0 && item.opening.height > 0)
            #expect(CGRect(x: 0, y: 0, width: 1, height: 1).contains(item.opening))
        }
    }

    @Test func openingTracksPhotoSizeAndTransform() {
        let asset = DiaryAsset(id: UUID(), path: "frame.png", pixelSize: CGSize(width: 400, height: 600))
        var photo = DiaryLayer.photo(asset: asset, center: CGPoint(x: 300, y: 400))
        let item = DiaryPhotoFrameCatalog.Item(id: "fixture", title: "相框", opening: CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.7))
        let frame = DiaryEditorSession.photoFrame(item, asset: asset, photo: photo)
        for size in [CGSize(width: 200, height: 600), CGSize(width: 800, height: 300)] {
            photo.size = size
            photo.transform.rotationDegrees = 32
            photo.transform.scale = 0.7
            let bounds = DiaryPageRenderer.bounds(frame, siblings: [photo, frame])
            #expect(abs(bounds.minX + bounds.width * item.opening.minX) < 0.001)
            #expect(abs(bounds.minY + bounds.height * item.opening.minY) < 0.001)
            #expect(abs(bounds.width * item.opening.width - size.width) < 0.001)
            #expect(abs(bounds.height * item.opening.height - size.height) < 0.001)
            #expect(DiaryPageRenderer.matrix(frame, siblings: [photo, frame]) == photo.transform.matrix)
        }
    }

    @Test func framedPhotosSaveReopenAndKeepResourcesThroughFrameChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryDocumentStore(ownerID: "photo-frame-persistence", baseDirectory: root)
        let session = DiaryEditorSession(document: DiaryDocument(), images: [:], store: store)
        let data = try #require(UIGraphicsImageRenderer(size: CGSize(width: 120, height: 200)).image { c in
            UIColor.blue.setFill(); c.fill(CGRect(x: 0, y: 0, width: 120, height: 200))
        }.pngData())
        #expect(await session.importPhoto(data))
        let photo = try #require(session.managedPhotos.first)
        func verifySaved() async throws {
            try await session.save()
            #expect(session.saveStatus == "已保存")
            let loaded = try await store.load(session.document.id)
            #expect(loaded.document == session.document)
            for content in loaded.document.objects.values {
                for layer in content.layers where layer.kind == .photo || layer.kind == .frame {
                    if let assetID = layer.assetID { #expect(loaded.images[assetID] != nil) }
                }
            }
            let exported = try await store.exportImages(for: loaded.document)
            #expect(!exported.isEmpty)
        }
        try await verifySaved()
        #expect(await session.applyPhotoFrame(DiaryPhotoFrameCatalog.items[1], to: photo.id))
        try await verifySaved()
        try await store.saveDraft(session.document, contentID: photo.ownerID, baseRevision: 1)
        let loadedDraft = try await store.loadDraft(contentID: photo.ownerID, documentID: session.document.id)
        let draft = try #require(loadedDraft)
        #expect(draft.loaded.document == session.document)
        #expect(await session.applyPhotoFrame(nil, to: photo.id))
        try await verifySaved()
        session.undo()
        try await verifySaved()
        #expect(await session.close())
    }

    @Test func validatesBothFrameFormatsAndRejectsBrokenStickerMetadata() throws {
        let asset = DiaryAsset(id: UUID(), path: "fixture.png", pixelSize: CGSize(width: 120, height: 200))
        var document = DiaryDocument()
        document.assets[asset.id] = asset
        let photo = DiaryLayer.photo(asset: asset, center: .zero)
        let frame = DiaryEditorSession.photoFrame(DiaryPhotoFrameCatalog.defaultFrame, asset: asset, photo: photo)
        document.objects[document.rootContentID]?.layers = [photo, frame]
        #expect(throws: Never.self) { try DiaryDocumentStore.validate(document) }
        func rejects(_ mutate: (inout DiaryLayer) -> Void, error: DiaryEditorError) {
            var invalid = document
            mutate(&invalid.objects[invalid.rootContentID]!.layers[1])
            #expect(throws: error) { try DiaryDocumentStore.validate(invalid) }
        }
        rejects({ $0.assetID = UUID() }, error: .missingResource)
        rejects({ $0.assetID = nil }, error: .missingResource)
        rejects({ $0.frameOpening = nil }, error: .invalidDocument)
        rejects({ $0.frameOpening = CGRect(x: 0, y: 0, width: 0, height: 1) }, error: .invalidDocument)
        rejects({ $0.frameOpening = CGRect(x: -0.1, y: 0, width: 1, height: 1) }, error: .invalidDocument)
        rejects({ $0.frameTargetID = UUID() }, error: .invalidDocument)
        document.objects[document.rootContentID]?.layers[1] = DiaryLayer(name: "旧版相框", kind: .frame,
            transform: photo.transform, size: photo.size, frameTargetID: photo.id, frameColor: .white, frameWidth: 20)
        #expect(throws: Never.self) { try DiaryDocumentStore.validate(document) }
        rejects({ $0.frameWidth = nil }, error: .invalidDocument)
    }

    @Test func importedPhotoAndStickerFrameAreOneUndoableObject() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = DiaryEditorSession(document: DiaryDocument(), images: [:],
            store: DiaryDocumentStore(ownerID: "photo-frame-tests", baseDirectory: root))
        let data = try #require(UIGraphicsImageRenderer(size: CGSize(width: 100, height: 200)).image { c in
            UIColor.blue.setFill(); c.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
        }.pngData())
        #expect(await session.importPhoto(data))
        #expect(session.scopeLayers.count == 1)
        let contentID = try #require(session.scopeLayers.first?.contentID)
        let object = try #require(session.document.objects[contentID])
        #expect(object.layers.count == 2)
        let photo = try #require(object.layers.first { $0.isContentPhoto })
        let frame = try #require(object.layers.first { $0.isPhotoFrame })
        #expect(frame.assetID != nil)
        #expect(frame.kind == .photo)
        #expect(frame.subcategory == "frame")
        #expect(frame.renderType == "image")
        #expect(session.managedPhotos.count == 1)
        #expect(session.selectedPhotos.count == 1)
        #expect(session.document.replaceablePhotos().count == 1)
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(frame)) as? [String: Any])
        #expect(encoded["kind"] as? String == "photo")
        #expect(encoded["subcategory"] as? String == "frame")
        #expect(encoded["renderType"] as? String == "image")
        #expect(frame.frameTargetID == photo.id)
        #expect(session.undoStack.count == 1)
        #expect(session.selectedEditingKind == .photo)
        #expect(session.contextActions.contains(.frame))
        #expect(session.contextActions.contains(.crop))
        #expect(await session.applyPhotoFrame(DiaryPhotoFrameCatalog.items[1], to: photo.id))
        #expect(session.document.objects[object.id]?.layers.count == 2)
        session.undo()
        #expect(session.document.objects[object.id]?.layers.last == frame)
        #expect(await session.applyPhotoFrame(nil, to: photo.id))
        #expect(session.document.objects[object.id]?.layers.count == 1)
        session.undo()
        #expect(session.document.objects[object.id]?.layers.last == frame)
        let roundTrip = try JSONDecoder().decode(DiaryDocument.self, from: JSONEncoder().encode(session.document))
        #expect(roundTrip == session.document)
        session.undo()
        #expect(session.scopeLayers.isEmpty)
    }
}
