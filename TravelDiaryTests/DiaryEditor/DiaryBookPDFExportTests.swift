import Testing
import UIKit
import PDFKit
@testable import TravelDiary

@MainActor
struct DiaryBookPDFExportTests {
    private func page(_ book: DiaryBook, title: String) -> DiaryDocument {
        var document = DiaryDocument()
        document.bookID = book.id
        document.objects[document.rootContentID]?.referenceSize = book.defaultPageSize
        document.appendObject(containing: DiaryLayer(name: title, kind: .text,
            transform: DiaryTransform(position: CGPoint(x: 20, y: 20), pivot: .zero),
            size: CGSize(width: 500, height: 100), text: title, fontSize: 36))
        return document
    }

    @Test func exportsSavedPageOrderIncludingShellAndExcludingTrash() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = DiaryDocumentStore(ownerID: "pdf-tests", baseDirectory: folder)
        let original = try await library.createBook(title: "旅行/PDF:测试", preset: .square)
        let store = DiaryDocumentStore(ownerID: "pdf-tests", baseDirectory: folder, bookID: original.id)
        var first = page(original, title: "FIRST")
        let second = page(original, title: "SECOND"), removed = page(original, title: "REMOVED")
        try await store.save(first); try await store.save(second); try await store.save(removed)
        try await store.trashPage(removed.id)
        try await store.setShell(first.id)
        let before = try await store.loadBook()
        try await store.reorderPages([second.id, first.id], expectedRevision: before.catalogRevision)
        let snapshot = try await store.loadBook()
        // 导出旧目录时必须读取旧版本，不能混入后来保存的内容。
        let child = try #require(first.root.layers[0].contentID)
        first.objects[child]?.layers[0].text = "NEW VERSION"
        try await store.save(first)
        var progress: [Int] = []
        let result = try await DiaryBookPDFExporter.export(book: snapshot, store: store,
            outputDirectory: folder.appendingPathComponent("exports")) { done, total in
                progress.append(done); #expect(total == 2)
            }
        let pdf = try #require(PDFDocument(url: result.url))
        #expect(pdf.pageCount == 2)
        #expect(pdf.page(at: 0)?.string?.contains("SECOND") == true)
        #expect(pdf.page(at: 1)?.string?.contains("FIRST") == true)
        #expect(pdf.string?.contains("NEW VERSION") == false)
        #expect(pdf.string?.contains("REMOVED") == false)
        #expect(progress == [0, 1, 2])
        #expect(result.url.lastPathComponent == "旅行PDF测试.pdf")
        #expect(pdf.page(at: 0)?.bounds(for: .mediaBox).size == CGSize(width: 240, height: 240))
        DiaryBookPDFExporter.discard(result)
        #expect(!FileManager.default.fileExists(atPath: result.url.path))
    }

    @Test func a5SizeAndImageTopOriginArePreserved() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = DiaryDocumentStore(ownerID: "pdf-tests", baseDirectory: folder)
        let original = try await library.createBook(title: "A5", preset: .a5)
        let store = DiaryDocumentStore(ownerID: "pdf-tests", baseDirectory: folder, bookID: original.id)
        var document = DiaryDocument(); document.bookID = original.id
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format).image { _ in
            UIColor.red.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 100, height: 50))
            UIColor.blue.setFill(); UIRectFill(CGRect(x: 0, y: 50, width: 100, height: 50))
        }
        let (asset, _) = try await store.importImage(try #require(image.pngData()), documentID: document.id)
        document.assets[asset.id] = asset
        document.appendObject(containing: DiaryLayer(name: "orientation", kind: .sticker,
            transform: DiaryTransform(position: .zero, pivot: .zero), size: original.defaultPageSize, assetID: asset.id))
        try await store.save(document)
        let result = try await DiaryBookPDFExporter.export(book: store.loadBook(), store: store,
            outputDirectory: folder.appendingPathComponent("exports"))
        let pdf = try #require(PDFDocument(url: result.url)), page = try #require(pdf.page(at: 0))
        let size = page.bounds(for: .mediaBox).size
        #expect(abs(size.width - 148 / 25.4 * 72) < 0.01)
        #expect(abs(size.height - 210 / 25.4 * 72) < 0.01)
        let thumbnail = page.thumbnail(of: CGSize(width: 100, height: 140), for: .mediaBox)
        let cg = try #require(thumbnail.cgImage)
        var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8,
                bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        let top = ((cg.height / 4) * cg.width + cg.width / 2) * 4
        let bottom = ((cg.height * 3 / 4) * cg.width + cg.width / 2) * 4
        #expect(pixels[top] > 200 && pixels[top + 2] < 30)
        #expect(pixels[bottom + 2] > 200 && pixels[bottom] < 30)
    }

    @Test func cancellationAfterFirstPageRemovesPartialFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = DiaryDocumentStore(ownerID: "pdf-tests", baseDirectory: folder)
        let original = try await library.createBook(title: "cancel", preset: .square)
        let store = DiaryDocumentStore(ownerID: "pdf-tests", baseDirectory: folder, bookID: original.id)
        try await store.save(page(original, title: "ONE")); try await store.save(page(original, title: "TWO"))
        let book = try await store.loadBook(), output = folder.appendingPathComponent("exports")
        let task = Task {
            try await DiaryBookPDFExporter.export(book: book, store: store, outputDirectory: output) { done, _ in
                if done == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
    }

    @Test func missingPageAndEmptyBookDoNotProducePDF() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = DiaryDocumentStore(ownerID: "pdf-tests", baseDirectory: folder)
        var book = try await library.createBook(title: "empty")
        let store = DiaryDocumentStore(ownerID: "pdf-tests", baseDirectory: folder, bookID: book.id)
        let output = folder.appendingPathComponent("exports")
        do { _ = try await DiaryBookPDFExporter.export(book: book, store: store, outputDirectory: output); Issue.record("Expected empty-book failure") }
        catch { #expect(error is DiaryBookPDFExporter.ExportError) }
        book.pages = [DiaryPageEntry(id: UUID(), title: "missing", revisionID: UUID(), size: book.defaultPageSize)]
        do { _ = try await DiaryBookPDFExporter.export(book: book, store: store, outputDirectory: output); Issue.record("Expected missing-page failure") }
        catch { #expect(error.localizedDescription.contains("第 1 页")) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
    }
}
