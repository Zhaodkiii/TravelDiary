import Testing
import Foundation
import UIKit
@testable import TravelDiary

@MainActor
struct DiaryPresetTests {
    private func package() throws -> DiaryPresetPackage {
        let catalog = try BundleDiaryPresetProvider().catalog()
        #expect(catalog.issues.isEmpty)
        return try #require(catalog.books.first { $0.id == "hiking-yubeng" })
    }
    /// 真实应用资源目录必须保持包结构；真实雨崩各层均可独立打开。
    @Test func bundleDiscoveryAndObjectEditing() async throws {
        let p = try package(); try p.validate()
        let page = try #require(p.pages.first)
        let ids = Dictionary(uniqueKeysWithValues: p.manifest.assetTable.keys.map { ($0, UUID()) })
        let doc = try p.instantiate(page, bookID: UUID(), targetSize: page.size.cg, assetIDs: ids)
        #expect(doc.root.layers.count == 15)
        #expect(doc.root.layers.allSatisfy { $0.kind == .object && $0.contentID != nil })
        let session = DiaryEditorSession(document: doc, images: [:], store: DiaryDocumentStore(ownerID: "test", bookID: doc.bookID))
        #expect(session.openObject() != nil)
    }
    /// 两页共享模板源对象，导入必须分别生成可变对象；同次请求重试不会重复。
    @Test func wholeBookTransactionAndIdempotency() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let p = try twoPageFixture(in: base)
        let store = DiaryDocumentStore(ownerID: "owner", baseDirectory: base)
        let operation = UUID()
        let book = try await store.importPreset(p, pageIDs: p.manifest.pages.map(\.id), title: "两页验证", operationID: operation)
        #expect(book.pages.count == 2)
        let retry = try await store.importPreset(p, pageIDs: p.manifest.pages.map(\.id), title: "两页验证", operationID: operation)
        #expect(retry.id == book.id)
        #expect(try await store.listBooks().count == 1)
        let local = DiaryDocumentStore(ownerID: "owner", baseDirectory: base, bookID: book.id)
        let a = try await local.load(book.pages[0].id)
        let b = try await local.load(book.pages[1].id)
        #expect(Set(a.document.objects.keys).isDisjoint(with: b.document.objects.keys))
        #expect(Set(a.document.assets.keys) == Set(b.document.assets.keys))
        var changed = a.document
        changed.objects[changed.rootContentID]?.background = .pink
        try await local.save(changed)
        #expect(try await local.load(book.pages[1].id).document == b.document)
        // 模板移除后已导入用户资源仍可独立打开。
        try FileManager.default.removeItem(at: p.root)
        #expect(try await local.load(book.pages[0].id).document == changed)
    }
    @Test func appendFitsAndPreservesCover() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let p = try package()
        let store = DiaryDocumentStore(ownerID: "owner", baseDirectory: base)
        let book = try await store.createBook(title: "正方形", preset: .square)
        let local = DiaryDocumentStore(ownerID: "owner", baseDirectory: base, bookID: book.id)
        var original = DiaryDocument(); original.bookID = book.id
        original.objects[original.rootContentID]?.referenceSize = book.defaultPageSize
        try await local.save(original)
        try await local.setCover(original.id)
        let current = try await local.loadBook()
        let updated = try await local.importPreset(p, pageIDs: [p.manifest.pages[0].id], title: "unused", operationID: UUID(),
                                    afterPageID: original.id, expectedRevision: current.catalogRevision)
        #expect(updated.pages.count == 2 && updated.coverPageID == original.id)
        let loaded = try await local.load(updated.pages[1].id)
        #expect(loaded.document.root.referenceSize == book.defaultPageSize)
        let wrapper = try #require(loaded.document.root.layers.first)
        #expect(wrapper.transform.position.x > 0 && wrapper.transform.position.y == 0)
        let session = DiaryEditorSession(document: loaded.document, images: loaded.images, store: local)
        #expect(session.openObject()?.content.role == .canvas)
    }
    @Test func invalidAssetsAndCancellationPublishNothing() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let p = try twoPageFixture(in: base)
        let store = DiaryDocumentStore(ownerID: "owner", baseDirectory: base)
        let cancel = DiaryPresetCancellation(); cancel.cancel()
        do {
            _ = try await store.importPreset(p, pageIDs: p.manifest.pages.map(\.id), title: "取消", operationID: UUID(), cancellation: cancel)
            Issue.record("取消不应发布")
        } catch is CancellationError { }
        let file = try #require(p.manifest.assetTable.values.first)
        try Data("broken".utf8).write(to: p.url(file.path))
        do {
            _ = try await store.importPreset(p, pageIDs: p.manifest.pages.map(\.id), title: "损坏", operationID: UUID())
            Issue.record("损坏包不应发布")
        } catch { }
        #expect(try await store.listBooks().isEmpty)
    }
    /// 预览参考来自转换后 JSON，客户端渲染不能出现层序或原点错位。
    @Test func nativeRenderMatchesConvertedPreview() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let p = try package(); let page = try #require(p.pages.first)
        let library = DiaryDocumentStore(ownerID: "owner", baseDirectory: base)
        let book = try await library.importPreset(p, pageIDs: [page.id], title: "视觉验证", operationID: UUID())
        let local = DiaryDocumentStore(ownerID: "owner", baseDirectory: base, bookID: book.id)
        let loaded = try await local.load(book.pages[0].id)
        let reference = try #require(UIImage(data: Data(contentsOf: p.url(page.preview.thumbnailPath))))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: reference.size, format: format).image { renderer in
            renderer.cgContext.scaleBy(x: reference.size.width / page.size.width, y: reference.size.height / page.size.height)
            DiaryPageRenderer.draw(loaded.document, images: loaded.images, in: renderer.cgContext, cacheObjects: false)
        }
        func pixels(_ image: UIImage) throws -> [UInt8] {
            var data = [UInt8](repeating: 0, count: Int(reference.size.width * reference.size.height) * 4)
            let context = try #require(CGContext(data: &data, width: Int(reference.size.width), height: Int(reference.size.height), bitsPerComponent: 8, bytesPerRow: Int(reference.size.width) * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(try #require(image.cgImage), in: CGRect(origin: .zero, size: reference.size)); return data
        }
        let a = try pixels(reference), b = try pixels(rendered)
        let error = zip(a,b).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(a.count) / 255
        #expect(error < 0.035, "平均像素误差 \(error)")
    }
    @Test func creationReplacesOnlySelectedPhotosAndRetriesWithoutDuplication() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let p = try twoPageFixture(in: base)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 48)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 48))
        }
        let photo = base.appendingPathComponent("selected.png")
        try #require(image.pngData()).write(to: photo)
        let store = DiaryDocumentStore(ownerID: "owner", baseDirectory: base)
        let operation = UUID()
        let book = try await store.importPreset(p, pageIDs: p.manifest.pages.map(\.id), title: "选图创建",
                                               operationID: operation, replacementPhotos: [photo])
        let local = DiaryDocumentStore(ownerID: "owner", baseDirectory: base, bookID: book.id)
        let first = try await local.load(book.pages[0].id)
        let second = try await local.load(book.pages[1].id)
        let replaced = try #require(first.document.replaceablePhotos().first)
        let retained = try #require(second.document.replaceablePhotos().first)
        let replacedAssetID = try #require(replaced.assetID)
        let asset = try #require(first.document.assets[replacedAssetID])
        #expect(asset.pixelSize == CGSize(width: 32, height: 48))
        #expect(replaced.assetID != retained.assetID)
        #expect(first.document.replaceablePhotos().count == second.document.replaceablePhotos().count)
        let retry = try await store.importPreset(p, pageIDs: p.manifest.pages.map(\.id), title: "选图创建",
                                                operationID: operation, replacementPhotos: [photo])
        #expect(retry.id == book.id)
        #expect(try await store.listBooks().count == 1)
    }

    @Test func invalidCreationPhotoDoesNotPublishBook() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let p = try twoPageFixture(in: base)
        let photo = base.appendingPathComponent("invalid.image")
        try Data("invalid image".utf8).write(to: photo)
        let store = DiaryDocumentStore(ownerID: "owner", baseDirectory: base)
        do {
            _ = try await store.importPreset(p, pageIDs: p.manifest.pages.map(\.id), title: "失败创建",
                                             operationID: UUID(), replacementPhotos: [photo])
            Issue.record("无效照片不应创建成功")
        } catch { }
        #expect(try await store.listBooks().isEmpty)
    }

    private func twoPageFixture(in base: URL) throws -> DiaryPresetPackage {
        let source = try package()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let root = base.appendingPathComponent("fixture.diarypreset")
        try FileManager.default.copyItem(at: source.root, to: root)
        var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("package.json"))) as? [String: Any])
        let ref = source.manifest.pages[0]
        var page = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(ref.path))) as? [String: Any])
        page["id"] = "test-page-two"; page["title"] = "第二页验证"
        let path = "pages/test-page-two.json"
        let data = try JSONSerialization.data(withJSONObject: page, options: [.sortedKeys])
        try data.write(to: root.appendingPathComponent(path))
        var pages = manifest["pages"] as! [[String: Any]]
        pages.append(["id": "test-page-two", "title": "第二页验证", "path": path]); manifest["pages"] = pages
        var files = manifest["files"] as! [[String: Any]]
        files.append(["path": path, "byteCount": data.count, "sha256": DiaryPresetPackage.hash(data)]); manifest["files"] = files
        let bytes = try JSONSerialization.data(withJSONObject: manifest)
        try bytes.write(to: root.appendingPathComponent("package.json"))
        return DiaryPresetPackage(root: root, manifest: try JSONDecoder().decode(PresetManifest.self, from: bytes))
    }
}
