import Testing
import UIKit
import PDFKit
@testable import TravelDiary

@MainActor
struct DiaryBookPrintExportTests {
    private var product: PrintProduct {
        PrintProduct(id: "test", title: "A5", revision: 1, width_mm: 148, height_mm: 210, paper: "测试", binding: "测试",
                     description: "", cover_mode: "optional_shell", duplex: true, min_pages: 2, max_pages: 200,
                     max_quantity: 10, base_fen: 1000, page_fen: 10, shipping_fen: 0, regions: ["上海"], lead_time: "", terms: "测试")
    }
    private func page(_ book: DiaryBook, text: String) -> DiaryDocument {
        var d = DiaryDocument(); d.bookID = book.id
        d.appendObject(containing: DiaryLayer(name: text, kind: .text,
            transform: DiaryTransform(position: CGPoint(x: 80, y: 80), pivot: .zero), size: CGSize(width: 600, height: 120), text: text))
        return d
    }
    @Test func printsOptionalShellThenAllContentWithoutExtractingLastPage() async throws {
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
        var published: [UUID: URL] = [:]
        var completionCounts: [Int] = []
        let result = try await DiaryBookPrintExporter.prepare(book: snapshot, store: store, product: product, directory: output, onPageReady: { id, url in
            #expect(UIImage(contentsOfFile: url.path) != nil)
            let readyPDF = output.appendingPathComponent("page-\(id).pdf")
            #expect(PDFDocument(url: readyPDF)?.pageCount == 1)
            #expect(published[id] == nil)
            #expect(completionCounts.count == published.count)
            published[id] = url
        }) { done, total in
            #expect(total == 4)
            #expect(published.count == done)
            completionCounts.append(done)
        }
        #expect(completionCounts == [1, 2, 3, 4])
        #expect(Set(published.keys) == Set(snapshot.pages.map(\.id)))
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).filter { $0.hasPrefix("page-") }.count == 4)
        let cover = try #require(PDFDocument(url: output.appendingPathComponent("cover.pdf")))
        let inner = try #require(PDFDocument(url: output.appendingPathComponent("interior.pdf")))
        #expect(cover.pageCount == 1)
        #expect(cover.page(at: 0)?.string?.contains("SHELL") == true)
        #expect(inner.pageCount == 4)
        #expect(inner.page(at: 0)?.string?.contains("FRONT") == true)
        #expect(inner.page(at: 1)?.string?.contains("INSIDE") == true)
        #expect(inner.page(at: 2)?.string?.contains("BACK") == true)
        #expect(inner.string?.contains("SHELL") != true)
        #expect(result.snapshot.pages.map(\.role) == ["shell", "interior", "interior", "interior"])
        #expect(result.snapshot.pages.count == 4)
        #expect(result.warnings.contains { $0.contains("空白") })
        let size = try #require(inner.page(at: 0)).bounds(for: .trimBox).size
        #expect(abs(size.width * 25.4 / 72 - 148) < 0.1)
        try await library.deleteBook(book.id)
        for f in result.files { #expect(try DiaryBookPrintExporter.hashFile(output.appendingPathComponent(f.role + ".pdf")) == f.sha256) }
    }
    @Test func automaticallyMapsSortedContentAndEnforcesProportionThreshold() throws {
        var book = DiaryBook(title: "test")
        book.pages = (0..<6).map { _ in DiaryPageEntry(id: UUID(), title: "", revisionID: UUID(), size: DiaryPagePreset.a5.size) }
        book.shellPageID = book.pages[0].id
        let map = try DiaryBookPrintExporter.mapping(book: book, product: product)
        #expect(map.cover.map(\.id) == [book.pages[0].id])
        #expect(map.inner.map(\.id) == Array(book.pages[1...5]).map(\.id))
        #expect(map.count == 6)
        let ratio = CGFloat(product.width_mm) / CGFloat(product.height_mm)
        book.pages[2].size = CGSize(width: ratio * 1.15 * 1000, height: 1000)
        #expect(try DiaryBookPrintExporter.mapping(book: book, product: product).count == 6)
        book.pages[3].size = CGSize(width: ratio / 1.15 * 1000, height: 1000)
        #expect(DiaryBookPrintExporter.incompatiblePages(book: book, product: product).isEmpty)
        book.pages[2].size.width += 0.1
        #expect(DiaryBookPrintExporter.incompatiblePages(book: book, product: product) == [2])
        #expect(throws: PrintFailure.self) { try DiaryBookPrintExporter.mapping(book: book, product: product) }
        book.pages = Array(book.pages.prefix(1))
        #expect(throws: PrintFailure.self) { try DiaryBookPrintExporter.mapping(book: book, product: product) }
    }
    @Test func singleContentPageNeedsNoCoverOrBack() throws {
        var book = DiaryBook(title: "one")
        let entry = DiaryPageEntry(id: UUID(), title: "", revisionID: UUID(), size: DiaryPagePreset.a5.size)
        book.pages = [entry]
        let map = try DiaryBookPrintExporter.mapping(book: book, product: product)
        #expect(map.cover.isEmpty)
        #expect(map.inner.map(\.id) == [entry.id])
        #expect(map.count == 2)
        #expect(DiaryBookImageExporter.spreadPages(book).count == 1)
        #expect(DiaryBookImageExporter.spreadPages(book)[0][0] == nil)
        #expect(DiaryBookImageExporter.spreadPages(book)[0][1]?.id == entry.id)
    }
    @Test func cooperativePrintDrawingMatchesNormalRendererAndLetsUIRun() async throws {
        var document = page(DiaryBook(title: "responsive"), text: "SAME CONTENT")
        document.appendObject(containing: DiaryLayer(name: "second", kind: .text,
            transform: DiaryTransform(position: CGPoint(x: 120, y: 260), pivot: .zero), size: CGSize(width: 600, height: 120), text: "SECOND"))
        func context() throws -> CGContext {
            let ctx = try #require(CGContext(data: nil, width: 400, height: 600, bitsPerComponent: 8, bytesPerRow: 1600,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.scaleBy(x: 400 / document.root.referenceSize.width, y: 600 / document.root.referenceSize.height)
            return ctx
        }
        let normal = try context(), cooperative = try context()
        UIGraphicsPushContext(normal)
        DiaryPageRenderer.draw(document, images: [:], in: normal, cacheObjects: false)
        UIGraphicsPopContext()
        var uiRan = false
        let uiTask = Task { @MainActor in uiRan = true }
        try await DiaryPageRenderer.drawForPrinting(document, images: [:], in: cooperative)
        #expect(uiRan)
        await uiTask.value
        let first = try #require(normal.data), second = try #require(cooperative.data)
        #expect(Data(bytes: first, count: 1600 * 600) == Data(bytes: second, count: 1600 * 600))
    }
    @Test func revealsOnlyCompletedSpreadsInReadingOrder() {
        var book = DiaryBook(title: "progress")
        book.pages = (0..<4).map { _ in DiaryPageEntry(id: UUID(), title: "", revisionID: UUID(), size: DiaryPagePreset.a5.size) }
        var ready = Set<UUID>()
        #expect(DiaryBookPrintExporter.readySpreads(book: book, readyPageIDs: ready).isEmpty)
        ready.insert(book.pages[0].id)
        #expect(DiaryBookPrintExporter.readySpreads(book: book, readyPageIDs: ready) == [0])
        ready.insert(book.pages[1].id)
        #expect(DiaryBookPrintExporter.readySpreads(book: book, readyPageIDs: ready) == [0])
        ready.insert(book.pages[2].id)
        #expect(DiaryBookPrintExporter.readySpreads(book: book, readyPageIDs: ready) == [0, 1])
        ready.insert(book.pages[3].id)
        #expect(DiaryBookPrintExporter.readySpreads(book: book, readyPageIDs: ready) == [0, 1, 2])
    }
    @Test func proportionAllowsUniformResizingAndRejectsInvalidSizes() {
        #expect(DiaryBookPrintExporter.proportionDifference(CGSize(width: 1480, height: 2100), product: product) < 0.001)
        #expect(DiaryBookPrintExporter.proportionDifference(.zero, product: product).isInfinite)
        #expect(DiaryBookPrintExporter.proportionDifference(CGSize(width: 1000, height: 1000), product: product) > 0.15)
    }
    @Test func adaptedProductionPDFMatchesTargetSizeAndPreservesPageOrder() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = DiaryDocumentStore(ownerID: "print-adapt", baseDirectory: folder)
        let book = try await library.createBook(title: "adapt", preset: .a5)
        let store = DiaryDocumentStore(ownerID: "print-adapt", baseDirectory: folder, bookID: book.id)
        for text in ["FRONT", "INSIDE", "BACK"] { try await store.save(page(book, text: text)) }
        var spec = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(product)) as? [String: Any])
        spec["width_mm"] = 160
        let adaptedProduct = try JSONDecoder().decode(PrintProduct.self, from: JSONSerialization.data(withJSONObject: spec))
        let snapshot = try await store.loadBook()
        let output = folder.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let result = try await DiaryBookPrintExporter.prepare(book: snapshot, store: store, product: adaptedProduct, directory: output) { _,_ in }
        #expect(result.warnings.contains { $0.contains("调整比例") })
        let pdf = try #require(PDFDocument(url: output.appendingPathComponent("interior.pdf")))
        let first = try #require(pdf.page(at: 0))
        #expect(first.string?.contains("FRONT") == true)
        #expect(pdf.page(at: 1)?.string?.contains("INSIDE") == true)
        #expect(pdf.page(at: 2)?.string?.contains("BACK") == true)
        #expect(result.files.map(\.role) == ["interior"])
        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("cover.pdf").path))
        #expect(abs(first.bounds(for: .mediaBox).width * 25.4 / 72 - 160) < 0.1)
        #expect(abs(first.bounds(for: .mediaBox).height * 25.4 / 72 - 210) < 0.1)
        #expect(pdf.pageCount == 4)
    }
    @Test func addressTrimsWhitespaceAndRejectsInvalidPhone() {
        var address = PrintAddress(name: " 张三 ", phone: " 13800138000 ", region: "上海", detail: " 某街道 1 号 ")
        #expect(address.complete)
        #expect(address.trimmed.name == "张三")
        #expect(address.trimmed.phone == "13800138000")
        address.phone = "abcdefghi"
        #expect(!address.complete)
        address.phone = "13800138000"; address.detail = "  \n "
        #expect(!address.complete)
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
