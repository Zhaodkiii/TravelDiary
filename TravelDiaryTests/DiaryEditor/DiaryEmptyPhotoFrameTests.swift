import Testing
import UIKit
@testable import TravelDiary

@MainActor struct DiaryEmptyPhotoFrameTests {
    private func photoData() throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return try #require(UIGraphicsImageRenderer(size: CGSize(width: 160, height: 220), format: format).image { renderer in
            UIColor.red.setFill(); renderer.fill(CGRect(x: 0,y: 0,width: 160,height: 220))
        }.pngData())
    }
    private func fixture(root: URL, standalone: Bool = false) async throws -> (DiaryEditorSession, UUID) {
        let store = DiaryDocumentStore(ownerID: "empty-frame-tests", baseDirectory: root)
        var doc = DiaryDocument()
        let item = try #require(DiaryPhotoFrameCatalog.items.first { $0.title == "梧桐街道_双胶带" })
        let (asset,image) = try await store.importImage(try #require(item.image?.pngData()), documentID: doc.id)
        doc.assets[asset.id] = asset
        var frame = DiaryLayer(name: "相框_梧桐街道_双胶带", kind: .sticker,
            transform: DiaryTransform(position: CGPoint(x: 320,y: 420),pivot: CGPoint(x: 80,y: 90),scale: 0.7,rotationDegrees: 12),
            size: image.size, semanticKind: .photo, subcategory: "frame", renderType: "image", assetID: asset.id)
        frame.transform.stretch = CGSize(width: 0.9,height: 1.2)
        if standalone { doc.objects[doc.rootContentID]?.layers = [frame] }
        else { doc.appendObject(containing: frame) }
        let session = DiaryEditorSession(document: doc,images: [asset.id:image],store: store)
        session.select(frame.id)
        return (session,frame.id)
    }

    @Test func emptySmartFrameAddsBoundPhotoAndSupportsHistoryAndReopening() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (session,id) = try await fixture(root: root)
        let before = session.document, outer = try #require(session.selected)
        #expect(session.contextActions.first == .addPhotoToFrame)
        #expect(!session.contextActions.contains(.replaceMaterial))
        let target = try #require(session.selectedEmptyPhotoFrameTarget)
        #expect(await session.addPhotoToEmptyFrame(try photoData(),target: target))
        #expect(session.document.layer(id)?.transform == outer.transform)
        #expect(session.document.layer(id)?.contentID == outer.contentID)
        let object = try #require(session.document.objects[target.ownerID])
        let photo = try #require(object.layers.first { $0.isContentPhoto })
        let frame = try #require(object.layers.first { $0.id == target.frameID })
        #expect(frame.frameTargetID == photo.id)
        #expect(frame.frameOpening == CGRect(x: 0,y: 0,width: 1,height: 1))
        #expect(object.layers.first?.id == photo.id)
        #expect(session.selectedPhotos.count == 1)
        #expect(session.contextActions.contains(.replacePhoto))
        #expect(!session.contextActions.contains(.addPhotoToFrame))
        #expect(session.undoStack.count == 1)
        try DiaryDocumentStore.validate(session.document)
        session.undo()
        #expect(session.document.layer(id)?.transform == before.layer(id)?.transform)
        #expect(session.contextActions.contains(.addPhotoToFrame))
        #expect(session.document.objects[target.ownerID]?.layers.count == 1)
        session.redo()
        try await session.store.save(session.document)
        let reopened = try await session.store.load(session.document.id)
        #expect(reopened.document == session.document)
        #expect(reopened.images[photo.assetID!] != nil)
        #expect(reopened.images[frame.assetID!] != nil)
        let export = try await session.store.exportImages(for: reopened.document)
        #expect(export.count == 2)
        // 已固定的空框目标不能在再次提交时添加第二张照片。
        let filled = session.document
        #expect(!(await session.addPhotoToEmptyFrame(try photoData(),target: target)))
        #expect(session.document == filled)
    }

    @Test func standaloneFrameBecomesOneSmartObjectWithoutMovingIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (session,id) = try await fixture(root: root,standalone: true)
        let original = try #require(session.selected)
        let target = try #require(session.selectedEmptyPhotoFrameTarget)
        #expect(await session.addPhotoToEmptyFrame(try photoData(),target: target))
        let wrapper = try #require(session.document.layer(id))
        #expect(wrapper.kind == .object)
        #expect(wrapper.transform == original.transform)
        #expect(wrapper.size == original.size)
        let content = try #require(wrapper.contentID.flatMap { session.document.objects[$0] })
        #expect(content.layers.count == 2)
        #expect(content.layers.allSatisfy { $0.transform.matrix == .identity })
        #expect(content.layers[1].frameTargetID == content.layers[0].id)
        #expect(session.undoStack.count == 1)
        session.undo()
        #expect(session.document.layer(id) == original)
    }

    @Test func lockedExistingAndAmbiguousContentDoNotOfferAdd() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (session,id) = try await fixture(root: root)
        let target = try #require(session.selectedEmptyPhotoFrameTarget)
        var document = session.document
        document.update(id) { $0.locked = true }
        let locked = DiaryEditorSession(document: document,images: session.images,store: session.store)
        locked.select(id)
        #expect(locked.selectedEmptyPhotoFrameTarget == nil)
        document = session.document
        var copy = try #require(document.layer(target.frameID)); copy.id = UUID()
        document.objects[target.ownerID]?.layers.append(copy)
        let ambiguous = DiaryEditorSession(document: document,images: session.images,store: session.store)
        ambiguous.select(id)
        #expect(ambiguous.selectedEmptyPhotoFrameTarget == nil)
        document = session.document
        document.update(target.frameID) { $0.semanticKind = nil; $0.subcategory = nil }
        let ordinary = DiaryEditorSession(document: document,images: session.images,store: session.store)
        ordinary.select(id)
        #expect(ordinary.selectedEmptyPhotoFrameTarget == nil)
    }

    @Test func addingInsideSmartObjectCommitsOneParentUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (parent,id) = try await fixture(root: root)
        let original = try #require(parent.selected)
        let child = try #require(parent.openObject())
        let frame = try #require(child.scopeLayers.first)
        child.select(frame.id)
        let target = try #require(child.selectedEmptyPhotoFrameTarget)
        #expect(await child.addPhotoToEmptyFrame(try photoData(),target: target))
        #expect(child.selected?.isContentPhoto == true)
        #expect(await child.commitToParent())
        #expect(parent.document.layer(id)?.transform == original.transform)
        #expect(parent.selectedPhotos.count == 1)
        #expect(parent.undoStack.count == 1)
        parent.undo()
        #expect(parent.selectedEmptyPhotoFrameTarget != nil)
    }

    @Test func croppingAddedPhotoKeepsFrameGeometry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (session,_) = try await fixture(root: root)
        let target = try #require(session.selectedEmptyPhotoFrameTarget)
        #expect(await session.addPhotoToEmptyFrame(try photoData(),target: target))
        let photo = try #require(session.selectedPhotos.first)
        let frame = try #require(session.document.layer(target.frameID))
        let before = DiaryPageRenderer.bounds(frame,siblings: [photo,frame])
        let image = try #require(UIImage(data: photoData()))
        let parameters = ImageCropParameters(outputSize: image.size,translation: .zero,rotation: 0,scale: 1,flipped: false)
        #expect(await session.commitPhotoCrop(layerID: photo.id,image: image,parameters: parameters))
        let cropped = try #require(session.document.layer(photo.id))
        #expect(cropped.size == photo.size)
        #expect(cropped.transform == photo.transform)
        #expect(DiaryPageRenderer.bounds(frame,siblings: [cropped,frame]) == before)
        #expect(cropped.photoFrameIsManual == true)
    }

    @Test func framesWithoutOpeningMetadataFindOffsetAndDecoratedHoles() throws {
        for index in [0, 4, 16] {
            let item = DiaryPhotoFrameCatalog.items[index]
            let image = try #require(item.image)
            let aperture = try #require(DiaryPhotoFrameAperture.detect(image,opening: CGRect(x: 0,y: 0,width: 1,height: 1)))
            #expect(aperture.slot.isValid)
        }
    }

    @Test func failedImportDoesNotMutateFrameOrHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let (session,_) = try await fixture(root: root)
        let target = try #require(session.selectedEmptyPhotoFrameTarget)
        let before = session.document
        #expect(!(await session.addPhotoToEmptyFrame(Data("invalid".utf8),target: target)))
        #expect(session.document == before)
        #expect(session.undoStack.isEmpty)
    }
}
