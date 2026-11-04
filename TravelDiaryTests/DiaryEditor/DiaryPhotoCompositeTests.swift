import Testing
import UIKit
@testable import TravelDiary

@MainActor struct DiaryPhotoCompositeTests {
    @Test func persistedCompositeSurvivesReloadAndInvalidatesOnlyForLocalEdits() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryDocumentStore(ownerID: "composite-test", baseDirectory: root)
        let session = DiaryEditorSession(document: DiaryDocument(), images: [:], store: store)
        let data = try #require(UIGraphicsImageRenderer(size: CGSize(width: 120, height: 180)).image { c in
            UIColor.blue.setFill(); c.fill(CGRect(x: 0, y: 0, width: 120, height: 180))
        }.pngData())
        #expect(await session.importPhoto(data))
        let photo = try #require(session.managedPhotos.first)
        #expect(await session.applyPhotoFrame(DiaryPhotoFrameCatalog.generated(), to: photo.id))
        try await session.save()
        let original = try await store.load(session.document.id)
        #expect(original.document == session.document)
        func files() -> [URL] {
            (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
                .filter { $0.path.contains("photo-composites/") && $0.pathExtension == "png" }
        }
        #expect(files().isEmpty)
        let prepared = await DiaryPhotoComposite.prepare(original, store: store)
        #expect(files().count == 1)
        let cached = try #require(files().first)
        let bytes = try Data(contentsOf: cached)
        #expect(prepared.document.layer(photo.id)?.kind == .sticker)
        #expect(prepared.document.objects[photo.ownerID]?.layers.contains { $0.frameTargetID == photo.id } == false)
        #expect(try Data(contentsOf: cached) == bytes)
        var moved = original.document
        moved.update(photo.id) { $0.transform.position.x += 50; $0.transform.rotationDegrees = 20 }
        _ = await DiaryPhotoComposite.prepare(.init(document: moved, images: original.images), store: store)
        #expect(files().count == 1)
        var changed = original.document
        changed.update(photo.id) { $0.opacity = 0.4 }
        _ = await DiaryPhotoComposite.prepare(.init(document: changed, images: original.images), store: store)
        #expect(files().count == 2)
        // 损坏的派生资源允许恢复，原始文档不受影响。
        try Data("broken".utf8).write(to: cached)
        _ = await DiaryPhotoComposite.prepare(original, store: store)
        #expect(UIImage(contentsOfFile: cached.path) != nil)
        #expect(try await store.load(session.document.id).document == original.document)
    }
}
