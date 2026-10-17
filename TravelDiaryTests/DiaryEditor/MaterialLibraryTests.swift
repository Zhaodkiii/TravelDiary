import Testing
import Foundation
import UIKit
@testable import TravelDiary

@MainActor
struct MaterialLibraryTests {
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
