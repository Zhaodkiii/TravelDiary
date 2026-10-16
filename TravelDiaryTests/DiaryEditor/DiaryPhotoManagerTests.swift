import Testing
import UIKit
@testable import TravelDiary

@MainActor
struct DiaryPhotoManagerTests {
    @Test func managesNestedPhotosAndUndoPreservesDecoration() throws {
        var document = DiaryDocument()
        let asset = DiaryAsset(id: UUID(), path: "assets/photo.png", pixelSize: CGSize(width: 100, height: 200))
        document.assets[asset.id] = asset
        let wrapperID = document.appendObject(containing: .photo(asset: asset, center: .zero))
        let ownerID = try #require(document.layer(wrapperID)?.contentID)
        let photoID = try #require(document.objects[ownerID]?.primaryLayerID)
        let decoration = DiaryLayer(name: "装饰", kind: .sticker, transform: DiaryTransform(position: .zero, pivot: .zero), size: CGSize(width: 20, height: 20), assetID: asset.id)
        document.objects[ownerID]?.layers.append(decoration)
        document.update(wrapperID) { $0.visible = false }
        let store = DiaryDocumentStore(ownerID: "photo-manager", baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let session = DiaryEditorSession(document: document, images: [:], store: store)
        #expect(session.managedPhotos.map(\.id) == [photoID])
        #expect(session.managedPhotos.first?.visible == false)
        session.removePhoto(photoID)
        #expect(session.managedPhotos.isEmpty)
        #expect(session.document.layer(decoration.id) != nil)
        #expect(session.document.objects[ownerID]?.primaryLayerID == nil)
        session.undo()
        #expect(session.document == document)
    }

    @Test func lockedAncestorProtectsNestedPhoto() throws {
        var document = DiaryDocument()
        let asset = DiaryAsset(id: UUID(), path: "assets/photo.png", pixelSize: CGSize(width: 100, height: 200))
        document.assets[asset.id] = asset
        let wrapperID = document.appendObject(containing: .photo(asset: asset, center: .zero))
        document.update(wrapperID) { $0.locked = true }
        let store = DiaryDocumentStore(ownerID: "photo-manager", baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let session = DiaryEditorSession(document: document, images: [:], store: store)
        let photo = try #require(session.managedPhotos.first)
        #expect(photo.locked)
        session.removePhoto(photo.id)
        #expect(session.document == document)
        #expect(session.undoStack.isEmpty)
    }
}
