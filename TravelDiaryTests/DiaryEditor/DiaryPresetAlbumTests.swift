import Testing
import Foundation
import UIKit
@testable import TravelDiary

@MainActor
struct DiaryPresetAlbumTests {
    nonisolated private static var delivery: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PSD转换工具/output/人生的三个春天-相册-v1/人生的三个春天.diarypreset")
    }

    @Test func legacyCatalogDefaultsToJournalAndAlbumSurvivesCacheEncoding() throws {
        let legacy = Data(#"{"id":"legacy","title":"手帐","series":"romance","version":1,"page_count":1,"cover_url":""}"#.utf8)
        let book = try JSONDecoder().decode(RemotePresetBook.self, from: legacy)
        #expect(book.contentKind == "journal")
        var album = book
        album.content_kind = "album"
        let restored = try JSONDecoder().decode(RemotePresetBook.self, from: JSONEncoder().encode(album))
        #expect(restored.contentKind == "album")
    }

    // Workstation acceptance test: CI without the private PSD delivery skips this case.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: Self.delivery.path)))
    func springAlbumUsesExistingImportAndWorksAfterRemovingDownload() async throws {
        let source = Self.delivery
        let manifest = try JSONDecoder().decode(PresetManifest.self, from: Data(contentsOf: source.appendingPathComponent("package.json")))
        #expect(manifest.contentKind == "album")
        #expect(manifest.pages.count == 21)
        #expect(manifest.readingUnits?.filter { $0.kind == "spread" && $0.searchEnabled }.count == 10)
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let copied = base.appendingPathComponent("download.diarypreset")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: copied)
        let package = DiaryPresetPackage(root: copied, manifest: manifest)
        try package.validate()
        let store = DiaryDocumentStore(ownerID: "album-acceptance", baseDirectory: base.appendingPathComponent("works"))
        let replacement = base.appendingPathComponent("replacement.png")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let replacementImage = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 60), format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        }
        try #require(replacementImage.pngData()).write(to: replacement)
        let book = try await store.importPreset(package, pageIDs: manifest.pages.map(\.id), title: manifest.title,
            operationID: UUID(), replacementPhotos: Array(repeating: replacement, count: 33))
        #expect(book.pages.count == 21)
        try FileManager.default.removeItem(at: copied)
        let local = DiaryDocumentStore(ownerID: "album-acceptance", baseDirectory: base.appendingPathComponent("works"), bookID: book.id)
        var photos = 0, texts = 0
        for page in book.pages {
            let loaded = try await local.load(page.id)
            for object in loaded.document.objects.values {
                for layer in object.layers {
                    if layer.kind == .photo {
                        photos += 1
                        let assetID = try #require(layer.assetID)
                        #expect(loaded.document.assets[assetID]?.pixelSize == CGSize(width: 80, height: 60))
                    }
                    if layer.kind == .text {
                        texts += 1
                        #expect(!layer.text.isEmpty)
                        #expect(layer.textColor != nil)
                        #expect(layer.textAlignment == .left)
                    }
                }
            }
        }
        #expect(photos == 33)
        #expect(texts == 35)
    }
}
