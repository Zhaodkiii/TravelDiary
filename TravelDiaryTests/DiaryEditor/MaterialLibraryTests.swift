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
    @Test func backgroundReplacementIsSingleUndoAndPreservesContent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryDocumentStore(ownerID: "materials-test", baseDirectory: root)
        let session = DiaryEditorSession(document: DiaryDocument(), images: [:], store: store)
        #expect(await session.importPhoto(try png(.red), asSticker: true))
        #expect(await session.importMaterialBackground(try png(.blue)))
        let before = session.document
        #expect(await session.importMaterialBackground(try png(.green), fit: true))
        #expect(session.content.layers.filter { $0.isLibraryBackground == true }.count == 1)
        #expect(session.content.layers.count == 2)
        #expect(session.content.layers.first?.locked == true)
        session.undo()
        #expect(session.content.layers == before.root.layers)
        #expect(session.document.assets == before.assets)
    }
}
