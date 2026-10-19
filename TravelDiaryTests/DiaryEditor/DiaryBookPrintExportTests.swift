import Testing
import UIKit
import PDFKit
@testable import TravelDiary

@MainActor
struct DiaryBookPrintExportTests {
    private var product: PrintProduct {
        PrintProduct(id: "test", title: "A5", revision: 1, width_mm: 148, height_mm: 210, paper: "测试", binding: "测试",
                     description: "", cover_mode: "separate_front_back", duplex: true, min_pages: 2, max_pages: 200,
                     max_quantity: 10, base_fen: 1000, page_fen: 10, shipping_fen: 0, regions: ["上海"], lead_time: "", terms: "测试")
    }
    private func page(_ book: DiaryBook, text: String) -> DiaryDocument {
        var d = DiaryDocument(); d.bookID = book.id
        d.appendObject(containing: DiaryLayer(name: text, kind: .text,
            transform: DiaryTransform(position: CGPoint(x: 80, y: 80), pivot: .zero), size: CGSize(width: 600, height: 120), text: text))
        return d
    }
    @Test func separatesCoverExcludesShellPadsAndPreservesConfirmedBytes() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = DiaryDocumentStore(ownerID: "print-test", baseDirectory: folder)
        let book = try await library.createBook(title: "印刷", preset: .a5)
        let store = DiaryDocumentStore(ownerID: "print-test", baseDirectory: folder, bookID: book.id)
        let front = page(book, text: "FRONT"), inside = page(book, text: "INSIDE"), back = page(book, text: "BACK"), shell = page(book, text: "SHELL")
        for d in [front, inside, back, shell] { try await store.save(d) }
        try await store.setShell(shell.id)
        let snapshot = try await store.loadBook()
        let output = folder.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let result = try await DiaryBookPrintExporter.prepare(book: snapshot, store: store, product: product, front: front.id, back: back.id, directory: output) { _,_ in }
        let cover = try #require(PDFDocument(url: output.appendingPathComponent("cover.pdf")))
        let inner = try #require(PDFDocument(url: output.appendingPathComponent("interior.pdf")))
        #expect(cover.pageCount == 2)
        #expect(cover.page(at: 0)?.string?.contains("FRONT") == true)
        #expect(cover.page(at: 1)?.string?.contains("BACK") == true)
        #expect(inner.pageCount == 2)
        #expect(inner.page(at: 0)?.string?.contains("INSIDE") == true)
        #expect(inner.string?.contains("SHELL") != true)
        #expect(inner.string?.contains("FRONT") != true)
        #expect(result.snapshot.pages.count == 3)
        #expect(result.warnings.contains { $0.contains("空白") })
        let size = try #require(inner.page(at: 0)).bounds(for: .trimBox).size
        #expect(abs(size.width * 25.4 / 72 - 148) < 0.1)
        try await library.deleteBook(book.id)
        for f in result.files { #expect(try DiaryBookPrintExporter.hashFile(output.appendingPathComponent(f.role + ".pdf")) == f.sha256) }
    }
    @Test func rejectsDuplicateCoverAndUnsupportedDimensions() throws {
        var book = DiaryBook(title: "test")
        book.pages = (0..<3).map { _ in DiaryPageEntry(id: UUID(), title: "", revisionID: UUID(), size: DiaryPagePreset.a5.size) }
        #expect(throws: PrintFailure.self) { try DiaryBookPrintExporter.mapping(book: book, front: book.pages[0].id, back: book.pages[0].id, product: product) }
        book.pages[1].size = CGSize(width: 1000, height: 1000)
        #expect(throws: PrintFailure.self) { try DiaryBookPrintExporter.mapping(book: book, front: book.pages[0].id, back: book.pages[2].id, product: product) }
    }
    @Test func changedCatalogCannotBeSilentlyFrozen() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = DiaryDocumentStore(ownerID: "print", baseDirectory: folder)
        let book = try await library.createBook(title: "test", preset: .a5)
        let store = DiaryDocumentStore(ownerID: "print", baseDirectory: folder, bookID: book.id)
        try await store.save(page(book, text: "NEW"))
        await #expect(throws: DiaryEditorError.self) { try await store.freezeForPrinting(book, at: folder.appendingPathComponent("frozen")) }
    }
}

@MainActor
struct PrintWorkflowContractTests {
    @Test func decodesActualServerWorkflowResponses() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/print-workflow-contract.json")
        let orders = try JSONDecoder().decode([PrintOrder].self, from: Data(contentsOf: fixture))
        #expect(orders.count == 3)
        #expect(orders[0].statusText == "待修改重提")
        #expect(orders[0].allowed_actions.contains("revise"))
        #expect(UUID(uuidString: orders[0].source_book_id) != nil)
        #expect(!orders[0].exception_reason.isEmpty)
        #expect(orders[1].statusText == "制作暂停")
        #expect(orders[2].after_sale_state == "resolved")
        #expect(orders[2].after_sale_resolution == "已补寄")
        #expect(orders[2].shipments.count == 2)
        #expect(orders[2].shipments.last?.kind == "reship")
    }
}

@MainActor
struct PrintMultipartHTTPTests {
    @Test func sendsExplicitSignedContentType() throws {
        let url = try #require(URL(string: "https://example.test/part?Signature=not-real"))
        let request = try PrintUploadHTTP.request(url: url, headers: ["Content-Type":"application/octet-stream"])
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
        #expect(throws: PrintFailure.self) { try PrintUploadHTTP.request(url: url, headers: ["Content-Type":"application/pdf"]) }
    }
    @Test func reportsSafeOSSErrorWithoutLeakingSignature() throws {
        let url = try #require(URL(string: "https://example.test/part?Signature=private-secret"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil))
        let body = Data("<Error><Code>SignatureDoesNotMatch</Code><StringToSign>private-secret</StringToSign></Error>".utf8)
        do { try PrintUploadHTTP.validate(response: response, body: body); Issue.record("403 must fail") }
        catch {
            #expect(error.localizedDescription.contains("SignatureDoesNotMatch"))
            #expect(error.localizedDescription.contains("403"))
            #expect(!error.localizedDescription.contains("private-secret"))
        }
        let ok = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        try PrintUploadHTTP.validate(response: ok, body: Data())
    }
}

@MainActor
struct PrintDirectOSSXMLTests {
    @Test func readsInitAndResumeParts() throws {
        let initResult = try PrintOSSXML.read(Data("<InitiateMultipartUploadResult><UploadId>ABC123</UploadId></InitiateMultipartUploadResult>".utf8))
        #expect(initResult.uploadID == "ABC123")
        let parts = try PrintOSSXML.read(Data("<ListPartsResult><Part><PartNumber>1</PartNumber><ETag>&quot;abc&quot;</ETag><Size>5242880</Size></Part><Part><PartNumber>2</PartNumber><ETag>&quot;def&quot;</ETag><Size>123</Size></Part></ListPartsResult>".utf8))
        #expect(parts.parts.count == 2)
        #expect(parts.parts[1]?.size == 5242880)
        #expect(parts.parts[2]?.etag == "\"def\"")
    }
    @Test func completesInPartOrderAndEscapesETags() throws {
        let xml = PrintOSSXML.completion([2: "b&c", 1: "a<d>"])
        #expect(xml.contains("a&lt;d&gt;"))
        #expect(xml.contains("b&amp;c"))
        let first = try #require(xml.range(of: "<PartNumber>1</PartNumber>"))
        let second = try #require(xml.range(of: "<PartNumber>2</PartNumber>"))
        #expect(first.lowerBound < second.lowerBound)
        #expect(try PrintOSSXML.read(Data(xml.utf8)).root == "CompleteMultipartUpload")
        #expect(throws: PrintFailure.self) { try PrintOSSXML.read(Data("<broken>".utf8)) }
        #expect(throws: PrintFailure.self) { try PrintOSSXML.read(Data(repeating: 0, count: 1024*1024+1)) }
        #expect(try PrintOSSXML.read(Data("<Error><Code>InvalidPart</Code></Error>".utf8)).root != "CompleteMultipartUploadResult")
    }
}
