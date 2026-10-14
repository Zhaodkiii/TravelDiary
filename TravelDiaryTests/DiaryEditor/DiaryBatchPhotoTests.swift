import Testing
import UIKit
@testable import TravelDiary

@MainActor
struct DiaryBatchPhotoTests {
    @Test func stableOrderSkipsProtectedGroupsAndPreservesGeometry() throws {
        var document = DiaryDocument()
        let asset = DiaryAsset(id: UUID(), path: "assets/old.png", pixelSize: CGSize(width: 100, height: 200))
        document.assets[asset.id] = asset
        var photo = DiaryLayer.photo(asset: asset, center: CGPoint(x: 200, y: 300))
        photo.transform.rotationDegrees = 30
        photo.transform.stretch = CGSize(width: 2, height: 0.8)
        document.appendObject(containing: photo)
        var second = photo; second.id = UUID()
        document.appendObject(containing: second)
        let targets = document.replaceablePhotos()
        #expect(targets.count == 2)
        let before = targets[0]
        let replacement = DiaryAsset(id: UUID(), path: "assets/new.png", pixelSize: CGSize(width: 600, height: 300))
        document.replacePhoto(before.id, with: replacement)
        let after = try #require(document.layer(before.id))
        #expect(after.size == before.size)
        #expect(after.transform == before.transform)
        #expect(after.photoFill == true)
        #expect(after.assetID == replacement.id)
        #expect(document.replaceablePhotos().map(\.id) == targets.map(\.id))
        let decoded = try JSONDecoder().decode(DiaryDocument.self, from: JSONEncoder().encode(document))
        #expect(decoded.layer(before.id)?.photoFill == true)
        document.update(photo.id) { $0.locked = true }
        #expect(document.replaceablePhotos().map(\.id) == [targets[1].id])
    }

    @Test func fillKeepsEntireSourceInsteadOfCoverCrop() {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let source = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: format).image { _ in
            UIColor.red.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 20, height: 100))
        }
        var document = DiaryDocument()
        let asset = DiaryAsset(id: UUID(), path: "assets/photo.png", pixelSize: source.size)
        document.assets[asset.id] = asset
        var layer = DiaryLayer(name: "照片", kind: .photo, transform: DiaryTransform(position: .zero, pivot: .zero), size: CGSize(width: 100, height: 100), assetID: asset.id)
        let point = CGPoint(x: 5, y: 50)
        #expect(!DiaryLayerHitTester.contains(point, layer: layer, document: document, siblings: [layer], images: [asset.id: source]))
        layer.photoFill = true
        #expect(DiaryLayerHitTester.contains(point, layer: layer, document: document, siblings: [layer], images: [asset.id: source]))
    }
    @Test func bookBatchPublishesAllPagesOrNone() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = DiaryDocumentStore(ownerID: "batch", baseDirectory: folder)
        let book = try await library.createBook(title: "批量替换", preset: .portrait)
        let store = DiaryDocumentStore(ownerID: "batch", baseDirectory: folder, bookID: book.id)
        var a = DiaryDocument(); a.bookID = book.id
        a.objects[a.rootContentID]?.referenceSize = book.defaultPageSize
        var b = DiaryDocument(); b.bookID = book.id
        b.objects[b.rootContentID]?.referenceSize = book.defaultPageSize
        try await store.save(a); try await store.save(b)
        let before = try await store.loadBook()
        a.objects[a.rootContentID]?.background = .pink
        b.objects[b.rootContentID]?.background = .yellow
        var invalid = b
        invalid.objects[invalid.rootContentID]?.referenceSize = .zero
        do {
            try await store.savePhotoReplacementBatch([a, invalid], expected: before)
            Issue.record("无效第二页不应发布第一页")
        } catch { }
        #expect(try await store.loadBook() == before)
        #expect(try await store.load(a.id).document.root.background == nil)
        try await store.savePhotoReplacementBatch([a, b], expected: before)
        #expect(try await store.load(a.id).document.root.background == .pink)
        #expect(try await store.load(b.id).document.root.background == .yellow)
        do {
            try await store.savePhotoReplacementBatch([a, b], expected: before)
            Issue.record("旧目录版本不应覆盖已提交修改")
        } catch DiaryEditorError.pageConflict { }
    }

}
