import Testing
import Foundation
import UIKit
import CryptoKit
@testable import TravelDiary

@MainActor
struct MaterialLibraryTests {
    @Test func queryParametersStayOutOfURLPath() throws {
        let request = try MaterialCatalogRepository.networkRequest("libraries/?type=sticker&template=21a8759e-e59f-58a0-b92e-86d41d88848a&template_version=2")
        #expect(request.path == "/api/v1/materials/libraries/")
        #expect(request.queryItems?.first(where: { $0.name == "type" })?.value == "sticker")
        #expect(request.queryItems?.first(where: { $0.name == "template_version" })?.value == "2")
        let search = try MaterialCatalogRepository.networkRequest("items/?q=%E8%8A%B1%E8%8D%89%20%26%20%E8%83%B6%E5%B8%A6")
        #expect(search.path == "/api/v1/materials/items/")
        #expect(search.queryItems?.first?.value == "花草 & 胶带")
    }
    @Test func downloadAuthorizationUsesPostWithoutBody() throws {
        let request = try MaterialCatalogRepository.networkRequest("revisions/36/download/", method: .post)
        #expect(request.method == .post)
        #expect(request.path == "/api/v1/materials/revisions/36/download/")
    }
    @Test func cachedOriginalWorksWithoutNetworkConfiguration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try png(.red)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let blobs = root.appendingPathComponent("blobs")
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        try data.write(to: blobs.appendingPathComponent(hash))
        let item = CloudMaterial(id: "cached", revision: 36, name: "cached", keywords: [], aliases: [],
            kind: "illustration", subcategory: "object", thumbnail_sha256: String(repeating: "0", count: 64),
            thumbnail_url: "https://example.invalid/thumb", sha256: hash, byte_size: data.count,
            favorite_count: 0, is_favorited: false)
        let manager = PresetDownloadManager(directory: root)
        let result = try await manager.materialData(item) { _ in }
        #expect(result == data)
        #expect(await MaterialThumbnailCache.shared.cachedOriginal(item) == nil)
    }
    @Test func independentPackDecodesWithoutTemplateAndRoutesEscapeQueries() throws {
        let json = #"{"id":"pack","template_id":null,"title":"出游","type":"sticker","series":"","version":1,"count":2,"favorite_count":0,"is_favorited":false,"availability":"published","previews":[]}"#
        let pack = try JSONDecoder().decode(CloudMaterialLibrary.self,from:Data(json.utf8))
        #expect(pack.template_id == nil)
        let path = MaterialRoutes.path("items/",["schema":"2","q":"花草 & 胶带","scope":"my"])
        let request = try MaterialCatalogRepository.networkRequest(path)
        #expect(request.path == "/api/v1/materials/items/")
        #expect(request.queryItems?.first(where:{$0.name=="q"})?.value == "花草 & 胶带")
    }
    @Test func recentItemsAreAccountScopedAndDedupeByIdentity() {
        let owner = "recent-test-" + UUID().uuidString
        defer { UserDefaults.standard.removeObject(forKey:"material.recent.\(owner)") }
        let item = CloudMaterial(id:"flower",revision:1,name:"花",keywords:[],aliases:[],kind:"illustration",subcategory:"botanical",thumbnail_sha256:String(repeating:"a",count:64),thumbnail_url:"",sha256:String(repeating:"a",count:64),byte_size:1,favorite_count:0,is_favorited:false)
        MaterialRecentStore.record(item,owner:owner)
        MaterialRecentStore.record(item,owner:owner)
        #expect(MaterialRecentStore.items(owner:owner).count == 1)
        #expect(MaterialRecentStore.items(owner:owner + "-other").isEmpty)
    }
    @Test func cancelledMaterialCommitDoesNotAddLayer() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let session=DiaryEditorSession(document:DiaryDocument(),images:[:],store:DiaryDocumentStore(ownerID:"intent-test",baseDirectory:root))
        #expect(await session.importPhoto(try png(.red),asSticker:true,canCommit:{false}) == false)
        #expect(session.content.layers.isEmpty)
        #expect(session.undoStack.isEmpty)
    }
    @Test func materialSourceSurvivesSaveAndReopen() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=DiaryDocumentStore(ownerID:"source-test",baseDirectory:root)
        let session=DiaryEditorSession(document:DiaryDocument(),images:[:],store:store)
        let source=DiaryMaterialSource(materialID:"flower",revision:8,libraryID:"spring",libraryVersion:2)
        #expect(await session.importPhoto(try png(.red),asSticker:true,materialSource:source))
        #expect(session.document.objects.values.flatMap(\.layers).contains(where:{$0.materialSource==source}))
        try await session.save()
        let loaded=try await store.load(session.document.id)
        #expect(loaded.document.objects.values.flatMap(\.layers).contains(where:{$0.materialSource==source}))
    }

    private func png(_ color: UIColor) throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60)).image { context in
            color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }
        return try #require(image.pngData())
    }
    @Test func repeatedStickerReusesAssetButCreatesIndependentLayers() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryDocumentStore(ownerID: "materials-test", baseDirectory: root)
        let session = DiaryEditorSession(document: DiaryDocument(), images: [:], store: store)
        let data = try png(.red)
        #expect(await session.importPhoto(data, asSticker: true))
        #expect(await session.importPhoto(data, asSticker: true))
        #expect(session.document.assets.count == 1)
        #expect(session.content.layers.count == 2)
        #expect(session.content.layers[0].id != session.content.layers[1].id)
    }
    @Test func solidBackgroundRemovesNestedBackgroundsAndUndoRestoresThem() throws {
        var document = DiaryDocument()
        let background = DiaryLayer(name: "原背景", kind: .sticker,
            transform: DiaryTransform(position: .zero, pivot: .zero), size: CGSize(width: 100, height: 100),
            semanticKind: .background)
        let decoration = DiaryLayer(name: "装饰", kind: .sticker,
            transform: background.transform, size: background.size, semanticKind: .illustration)
        let child = DiaryObjectContent(role: .object, referenceSize: background.size, layers: [background, decoration])
        document.objects[child.id] = child
        let group = DiaryLayer(name: "组合", kind: .object, transform: background.transform,
            size: background.size, contentID: child.id)
        document.objects[document.rootContentID]?.layers = [group]
        document.objects[document.rootContentID]?.background = .mint
        let session = DiaryEditorSession(document: document, images: [:],
            store: DiaryDocumentStore(ownerID: "background-replacement-tests",
                baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        session.previewBackground(.mint)
        #expect(session.document.layer(background.id) == nil)
        #expect(session.document.layer(decoration.id) == decoration)
        #expect(session.content.background == .mint)
        session.finishInteraction()
        #expect(session.undoStack.count == 1)
        session.undo()
        #expect(session.content.layers == document.root.layers)
        #expect(session.content.background == document.root.background)
        #expect(session.document.objects[child.id] == child)
        #expect(session.document.assets == document.assets)
        session.redo()
        #expect(session.document.layer(background.id) == nil)
        #expect(session.document.layer(decoration.id) == decoration)
    }

    @Test func backgroundReplacementIsEditableFitsCanvasAndPreservesOtherLayers() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryDocumentStore(ownerID: "materials-test", baseDirectory: root)
        let session = DiaryEditorSession(document: DiaryDocument(), images: [:], store: store)
        #expect(await session.importPhoto(try png(.red), asSticker: true))
        #expect(await session.importMaterialBackground(try png(.blue)))
        let before = session.document
        #expect(await session.importMaterialBackground(try png(.green), name: "新背景"))
        #expect(session.content.layers.filter { $0.isLibraryBackground == true }.count == 1)
        #expect(session.content.layers.count == 2)
        let layer = try #require(session.content.layers.first)
        #expect(layer.locked == false)
        #expect(layer.name == "新背景")
        #expect(session.selectedID == layer.id)
        #expect(layer.size.width <= session.content.referenceSize.width)
        #expect(layer.size.height <= session.content.referenceSize.height)
        #expect(abs(layer.size.width / layer.size.height - 40.0 / 60.0) < 0.001)
        #expect(Array(session.content.layers.dropFirst()) == Array(before.root.layers.dropFirst()))
        #expect(session.content.background == nil)
        session.undo()
        #expect(session.content.layers == before.root.layers)
        #expect(session.document.assets == before.assets)
    }
}
