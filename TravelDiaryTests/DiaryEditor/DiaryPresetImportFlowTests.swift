import Testing
import UIKit
@testable import TravelDiary

@MainActor
struct DiaryPresetImportFlowTests {
    @Test func deselectedPagesAreOmittedAndReplacementOrderMatchesSelection() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let package = try fixture(in: base)
        let first = try imageFile(in: base, name: "first", size: CGSize(width: 32, height: 48), color: .red)
        let second = try imageFile(in: base, name: "second", size: CGSize(width: 40, height: 20), color: .blue)
        let library = DiaryDocumentStore(ownerID: "flow-test", baseDirectory: base)
        let operation = UUID()
        let book = try await library.importPreset(package, pageIDs: ["page-3", "page-1"], title: "所选两页",
            operationID: operation, replacementPhotos: [first, second], hiddenCategories: [.background])
        #expect(book.pages.map { $0.presetSource?.pageID } == ["page-3", "page-1"])
        let store = DiaryDocumentStore(ownerID: "flow-test", baseDirectory: base, bookID: book.id)
        for (index, entry) in book.pages.enumerated() {
            let loaded = try await store.load(entry.id)
            let photo = try #require(loaded.document.replaceablePhotos().first)
            let asset = try #require(photo.assetID.flatMap { loaded.document.assets[$0] })
            #expect(asset.pixelSize == (index == 0 ? CGSize(width: 32, height: 48) : CGSize(width: 40, height: 20)))
            #expect(loaded.document.root.background == nil)
            #expect(loaded.document.objects.values.flatMap(\.layers).allSatisfy { $0.contentID != nil || $0.semanticKind != .background })
            // 背景组合内独立标注为文字的子层仍可编辑。
            #expect(loaded.document.objects.values.flatMap(\.layers).contains { $0.name == "组合内文字" })
            try DiaryDocumentStore.validate(loaded.document)
        }
        let retry = try await library.importPreset(package, pageIDs: ["page-3", "page-1"], title: "所选两页",
            operationID: operation, replacementPhotos: [first, second], hiddenCategories: [.background])
        #expect(retry.id == book.id)
        #expect(try await library.listBooks().count == 1)
    }

    @Test func creatingWithPartialPhotosKeepsRemainingPresetPhotos() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let package = try fixture(in: base)
        let replacement = try imageFile(in: base, name: "replacement", size: CGSize(width: 32, height: 48), color: .red)
        let library = DiaryDocumentStore(ownerID: "partial-creation", baseDirectory: base)
        let book = try await library.importPreset(package, pageIDs: ["page-1", "page-2", "page-3"],
            title: "部分替换", operationID: UUID(), replacementPhotos: [replacement])
        let store = DiaryDocumentStore(ownerID: "partial-creation", baseDirectory: base, bookID: book.id)
        #expect(book.pages.count == 3)
        for (index, page) in book.pages.enumerated() {
            let loaded = try await store.load(page.id)
            let photo = try #require(loaded.document.replaceablePhotos().first)
            let asset = try #require(photo.assetID.flatMap { loaded.document.assets[$0] })
            #expect(asset.pixelSize == (index == 0 ? CGSize(width: 32, height: 48) : CGSize(width: 20, height: 20)))
            try DiaryDocumentStore.validate(loaded.document)
        }
    }

    @Test func disabledCategoriesAreExcludedFromSavedCopyAndSourceStaysIntact() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let package = try fixture(in: base)
        let source = try package.instantiate(package.pages[0], bookID: UUID(), targetSize: package.manifest.pageSize.cg,
            assetIDs: Dictionary(uniqueKeysWithValues: package.manifest.assetTable.keys.map { ($0, UUID()) }))
        let switches: Set<DiaryLayerSemanticKind> = [.background, .photo, .paper, .text, .illustration]
        let book = try await DiaryDocumentStore(ownerID: "flow-test", baseDirectory: base).importPreset(package,
            pageIDs: ["page-2"], title: "仅保留品牌", operationID: UUID(), hiddenCategories: switches)
        let local = DiaryDocumentStore(ownerID: "flow-test", baseDirectory: base, bookID: book.id)
        let loaded = try await local.load(book.pages[0].id)
        let remaining = loaded.document.objects.values.flatMap(\.layers)
        #expect(remaining.count == 1 && remaining.first?.semanticKind == .branding)
        #expect(loaded.document.replaceablePhotos().isEmpty)
        #expect(loaded.document.objects.count == 1)
        #expect(loaded.document.assets.count == 1)
        #expect(source.replaceablePhotos().count == 1)
        #expect(source.root.background != nil)
        try FileManager.default.removeItem(at: package.root)
        #expect(try await local.load(book.pages[0].id).document == loaded.document)
    }

    @Test func photoSwitchSkipsSlotsAndRemovesFramesBeforePublishing() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let package = try fixture(in: base)
        let book = try await DiaryDocumentStore(ownerID: "flow-test", baseDirectory: base).importPreset(package,
            pageIDs: ["page-1", "page-2"], title: "不要照片", operationID: UUID(), hiddenCategories: [.photo])
        let local = DiaryDocumentStore(ownerID: "flow-test", baseDirectory: base, bookID: book.id)
        for page in book.pages {
            let loaded = try await local.load(page.id)
            #expect(loaded.document.replaceablePhotos().isEmpty)
            #expect(loaded.document.objects.values.flatMap(\.layers).allSatisfy { $0.kind != .frame && $0.kind != .photo })
            try DiaryDocumentStore.validate(loaded.document)
        }
        // 旧的照片映射不能悄悄应用到新开关，失败时不发布半本。
        let photo = try imageFile(in: base, name: "stale", size: CGSize(width: 20, height: 20), color: .red)
        let library = DiaryDocumentStore(ownerID: "other-flow-test", baseDirectory: base)
        await #expect(throws: (any Error).self) {
            try await library.importPreset(package, pageIDs: ["page-1"], title: "过期照片映射", operationID: UUID(),
                replacementPhotos: [photo], hiddenCategories: [.photo])
        }
        #expect(try await library.listBooks().isEmpty)
    }

    @Test func mixedPrimaryGroupsRemainValidAndLegacyKindsAreFiltered() throws {
        var document = DiaryDocument()
        let asset = DiaryAsset(id: UUID(), path: "test.image", pixelSize: CGSize(width: 100, height: 100))
        document.assets[asset.id] = asset
        let photo = DiaryLayer.photo(asset: asset, center: .zero)
        let text = DiaryLayer(name: "文字", kind: .text, transform: DiaryTransform(position: .zero, pivot: .zero), size: CGSize(width: 100, height: 30))
        let child = DiaryObjectContent(role: .photo, primaryLayerID: photo.id, referenceSize: CGSize(width: 100, height: 100), layers: [photo, text])
        document.objects[child.id] = child
        let group = DiaryLayer(name: "混合组合", kind: .object, transform: DiaryTransform(position: .zero, pivot: .zero), size: child.referenceSize, contentID: child.id)
        document.objects[document.rootContentID]?.layers = [group]
        let filtered = document.excludingPresetCategories([.photo])
        #expect(filtered.objects[child.id]?.role == .canvas)
        #expect(filtered.objects[child.id]?.primaryLayerID == nil)
        #expect(filtered.objects[child.id]?.layers.map(\.id) == [text.id])
        #expect(filtered.assets.isEmpty)
        try DiaryDocumentStore.validate(filtered)
        #expect(document.objects[child.id]?.primaryLayerID == photo.id)
        #expect(document.excludingPresetCategories([]) == document)
    }

    @Test func layerSwitchesRoundTripAndOldImportIntentsStillDecode() throws {
        let intent = DiaryPresetImportIntent(id: UUID(), templateID: "fixture", version: 1, pageIDs: ["page-2"],
            wholeBook: true, targetID: nil, afterPageID: nil, title: "恢复", hiddenCategories: [.photo, .text])
        let data = try JSONEncoder().encode(intent)
        let restored = try JSONDecoder().decode(DiaryPresetImportIntent.self, from: data)
        #expect(restored.hiddenCategories == [.photo, .text])
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "hiddenCategories")
        let old = try JSONDecoder().decode(DiaryPresetImportIntent.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(old.hiddenCategories == nil)
        #expect(old.pageIDs == ["page-2"] && old.wholeBook)
    }

    private func imageFile(in base: URL, name: String, size: CGSize, color: UIColor) throws -> URL {
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let image = UIGraphicsImageRenderer(size: size, format: {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; return format
        }()).image { context in color.setFill(); context.fill(CGRect(origin: .zero, size: size)) }
        let file = base.appendingPathComponent(name + ".png")
        try #require(image.pngData()).write(to: file)
        return file
    }

    private func fixture(in base: URL) throws -> DiaryPresetPackage {
        let root = base.appendingPathComponent("fixture.diarypreset")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let image = try imageFile(in: root, name: "asset", size: CGSize(width: 20, height: 20), color: .brown)
        let imageData = try Data(contentsOf: image)
        let size: [String: Any] = ["width": 100, "height": 140]
        var files: [[String: Any]] = [["path": "asset.png", "byteCount": imageData.count, "sha256": DiaryPresetPackage.hash(imageData)]]
        func write(_ path: String, _ value: [String: Any]) throws {
            let bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            try bytes.write(to: root.appendingPathComponent(path))
            files.append(["path": path, "byteCount": bytes.count, "sha256": DiaryPresetPackage.hash(bytes)])
        }
        func node(_ id: String, _ kind: String, _ subcategory: String, render: String = "image", name: String? = nil) -> [String: Any] {
            var value: [String: Any] = ["id": id, "name": name ?? id, "kind": kind, "subcategory": subcategory,
                "renderType": render, "size": size, "visible": true, "locked": false,
                "transform": ["position": ["x": 0, "y": 0], "pivot": ["x": 0, "y": 0], "scale": 1, "rotationDegrees": 0]]
            if render == "image" { value["assetID"] = "asset" }
            if render == "native_text" { value["text"] = "可编辑文字"; value["fontSize"] = 20 }
            return value
        }
        var group = node("background-group", "background", "page", render: "group")
        group["contentID"] = "mixed"
        try write("mixed.json", ["id": "mixed", "role": "canvas", "referenceSize": size,
            "layers": [node("background", "background", "page"), node("nested-text", "text", "caption", render: "native_text", name: "组合内文字")]])
        var frame = node("frame", "photo", "frame", render: "frame")
        frame["frameTargetID"] = "photo"; frame["frameWidth"] = 2
        try write("root.json", ["id": "root", "role": "canvas", "referenceSize": size,
            "background": ["red": 1, "green": 1, "blue": 1, "alpha": 1],
            "layers": [group, node("photo", "photo", "slot"), frame, node("paper", "paper", "note"),
                node("text", "text", "title", render: "native_text"), node("decoration", "illustration", "tape"), node("brand", "branding", "logo")]])
        var pages: [[String: Any]] = []
        for index in 1...3 {
            let id = "page-\(index)", path = "page-\(index).json", title = "第 \(index) 页"
            try write(path, ["id": id, "title": title, "size": size, "rootContentID": "root",
                "preview": ["thumbnailPath": "asset.png", "largePath": "asset.png"]])
            pages.append(["id": id, "title": title, "path": path])
        }
        let manifest: [String: Any] = ["format": "TravelDiary.PresetBook", "schemaVersion": 1, "layerSchemaVersion": 2,
            "templateBookID": "fixture", "packageVersion": 1, "title": "流程验证", "seriesID": "test", "pageSize": size,
            "coverPageID": "page-1", "pages": pages, "objectTable": ["root": "root.json", "mixed": "mixed.json"],
            "assetTable": ["asset": ["id": "asset", "path": "asset.png", "pixelSize": ["width": 20, "height": 20],
                "sha256": DiaryPresetPackage.hash(imageData), "byteCount": imageData.count]],
            "requiredCapabilities": ["image", "object", "text", "frame"], "files": files]
        let data = try JSONSerialization.data(withJSONObject: manifest)
        try data.write(to: root.appendingPathComponent("package.json"))
        return DiaryPresetPackage(root: root, manifest: try JSONDecoder().decode(PresetManifest.self, from: data))
    }
}
