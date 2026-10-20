import Testing
import UIKit
import SwiftUI
@testable import TravelDiary

@MainActor
struct DiaryReaderPhotoTests {
    private func photo(_ color: UIColor) throws -> Data {
        try #require(UIGraphicsImageRenderer(size: CGSize(width: 160, height: 200)).image { ctx in
            color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 160, height: 200))
        }.pngData())
    }

    @Test func readerAddReplaceDeletePersistsWithoutTouchingOtherPage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryDocumentStore(ownerID: "reader-photo-tests", baseDirectory: root)
        let other = DiaryDocument()
        try await store.save(other)
        let initial = DiaryEditorSession(document: DiaryDocument(), images: [:], store: store)
        #expect(await initial.importPhotos(try [photo(.blue), photo(.green)]))
        #expect(initial.managedPhotos.count == 2)
        for layer in initial.scopeLayers {
            let bounds = DiaryPageRenderer.bounds(layer, document: initial.document, siblings: initial.scopeLayers)
                .applying(layer.transform.matrix)
            #expect(CGRect(origin: .zero, size: initial.content.referenceSize).contains(bounds))
        }
        #expect(await initial.close())
        let first = try await store.load(initial.document.id)
        let replacing = DiaryEditorSession(document: first.document, images: first.images, store: store)
        let target = try #require(replacing.managedPhotos.first)
        let wrapper = try #require(replacing.scopeLayers.first)
        let frame = try #require(replacing.document.objects[target.ownerID]?.layers.first { $0.isPhotoFrame })
        #expect(await replacing.importPhoto(try photo(.red), replacing: target.id))
        #expect(replacing.scopeLayers.first?.transform == wrapper.transform)
        #expect(replacing.document.layer(frame.id) == frame)
        #expect(await replacing.close())
        let second = try await store.load(initial.document.id)
        let deleting = DiaryEditorSession(document: second.document, images: second.images, store: store)
        deleting.removePhoto(target.id)
        #expect(deleting.managedPhotos.count == 1)
        #expect(deleting.scopeLayers.count == 1)
        #expect(await deleting.close())
        let final = try await store.load(initial.document.id)
        #expect(final.document.layer(target.id) == nil)
        #expect(final.document.layer(frame.id) == nil)
        let untouched = try await store.load(other.id)
        #expect(untouched.document == other)
    }

    @Test func photoShortcutStripRendersBelowPage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryDocumentStore(ownerID: "reader-strip-preview", baseDirectory: root)
        let session = DiaryEditorSession(document: DiaryDocument(), images: [:], store: store)
        #expect(await session.importPhotos(try [photo(.systemTeal), photo(.systemOrange)]))
        #expect(await session.close())
        let entry = DiaryPageEntry(id: session.document.id, title: "", revisionID: UUID(), size: session.content.referenceSize)
        let host = UIHostingController(rootView: HStack(spacing: 16) {
            DiaryReaderPhotoStrip(page: entry, store: store, title: "左页照片", readerBusy: .constant(false), onSaved: {})
            DiaryReaderPhotoStrip(page: entry, store: store, title: "右页照片", readerBusy: .constant(false), onSaved: {})
        }.padding(12).frame(width: 390, height: 100).background(Color(uiColor: .systemGroupedBackground)))
        host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 100))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(700))
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        Attachment.record(Array(try #require(image.pngData())), named: "reader-photo-shortcuts.png")
    }

    @Test func deletingPrimaryPhotoPreservesDecorationsAndValidObject() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryDocumentStore(ownerID: "reader-decoration-tests", baseDirectory: root)
        let session = DiaryEditorSession(document: DiaryDocument(), images: [:], store: store)
        #expect(await session.importPhotos(try [photo(.blue)]))
        let target = try #require(session.managedPhotos.first)
        let caption = DiaryLayer(name: "保留文字", kind: .text,
            transform: DiaryTransform(position: .zero, pivot: .zero), size: CGSize(width: 200, height: 80), text: "旅行")
        var decorated = session.document
        decorated.objects[target.ownerID]?.layers.append(caption)
        #expect(await session.close())
        let editing = DiaryEditorSession(document: decorated, images: session.images, store: store)
        editing.removePhoto(target.id)
        #expect(editing.document.layer(caption.id) != nil)
        #expect(editing.document.objects[target.ownerID]?.role == .canvas)
        #expect(await editing.close())
        let loaded = try await store.load(editing.document.id)
        #expect(loaded.document.layer(caption.id) != nil)
    }
}
