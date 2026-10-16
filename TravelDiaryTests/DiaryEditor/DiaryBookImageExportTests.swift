import Testing
import UIKit
@testable import TravelDiary

@MainActor
struct DiaryBookImageExportTests {
    @Test func photoChangesCanExecuteOnPhotosBackgroundQueue() async {
        let changes = DiaryBookImageExporter.photoChanges(for: [])
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                changes()
                continuation.resume()
            }
        }
    }

    @Test func pairingMatchesReaderAndExcludesShell() {
        var book = DiaryBook(title: "test")
        book.pages = (0..<5).map { _ in DiaryPageEntry(id: UUID(), title: "", revisionID: UUID(), size: CGSize(width: 100, height: 140)) }
        book.shellPageID = book.pages[0].id
        let pairs = DiaryBookImageExporter.spreadPages(book)
        #expect(pairs.count == 3)
        #expect(pairs[0][0] == nil)
        #expect(pairs[0][1]?.id == book.pages[1].id)
        #expect(pairs[1][0]?.id == book.pages[2].id)
        #expect(pairs[1][1]?.id == book.pages[3].id)
        #expect(pairs[2][0]?.id == book.pages[4].id)
        #expect(pairs[2][1] == nil)
        book.pages.removeLast()
        #expect(DiaryBookImageExporter.spreadPages(book).count == 2)
    }

    @Test func spreadExportUsesBindingAssetsAndBatchesRemainder() async throws {
        #expect(UIImage(named: "DiaryBookLeather") != nil)
        #expect(UIImage(named: "DiaryBookRing") != nil)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = DiaryDocumentStore(ownerID: "spread-tests", baseDirectory: folder)
        let book = try await library.createBook(title: "spread", preset: .square)
        let store = DiaryDocumentStore(ownerID: "spread-tests", baseDirectory: folder, bookID: book.id)
        for _ in 0..<4 {
            var page = DiaryDocument(); page.bookID = book.id
            page.objects[page.rootContentID]?.referenceSize = book.defaultPageSize
            try await store.save(page)
        }
        let snapshot = try await store.loadBook()
        let result = try await DiaryBookImageExporter.export(book: snapshot, store: store, mode: .spreads(2)) { _, _ in }
        defer { try? FileManager.default.removeItem(at: result.directory) }
        #expect(result.urls.count == 2)
        let first = try #require(UIImage(contentsOfFile: result.urls[0].path))
        let last = try #require(UIImage(contentsOfFile: result.urls[1].path))
        #expect(first.size.width == last.size.width)
        #expect(first.size.height == last.size.height)
        #expect(first.size.width / first.size.height == DiaryCollageLayout.aspectRatio)
    }

    @Test func collageInsetsPreserveAspectAndReadingOrder() throws {
        let canvas = CGSize(width: 1200, height: 1600)
        let spread = CGSize(width: 800, height: 570)
        for count in DiaryCollageLayout.supportedCounts {
            let frames = DiaryCollageLayout.frames(imageSizes: Array(repeating: spread, count: count), canvas: canvas)
            #expect(frames.count == count)
            let images = (0..<count).map { index in
                UIGraphicsImageRenderer(size: spread).image { context in
                    UIColor(hue: CGFloat(index) / 8, saturation: 0.3, brightness: 0.85, alpha: 1).setFill()
                    context.fill(CGRect(origin: .zero, size: spread))
                    ("跨页 \(index + 1)" as NSString).draw(at: CGPoint(x: 60, y: 80),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 64), .foregroundColor: UIColor.black])
                }
            }
            let image = DiaryBookImageExporter.collage(images, canvasWidth: 600, scale: 1)
            Attachment.record(Array(try #require(image.pngData())), named: "collage-\(count).png")
            for frame in frames {
                #expect(frame.minX > 0 && frame.maxX < canvas.width)
                #expect(frame.minY > 0 && frame.maxY < canvas.height)
                #expect(abs(frame.width / frame.height - spread.width / spread.height) < 0.001)
            }
            for index in 1..<frames.count {
                let previous = frames[index - 1], current = frames[index]
                #expect(current.minY > previous.minY || current.minX > previous.maxX)
                #expect(!current.intersects(previous))
            }
        }
        let one = DiaryCollageLayout.frames(imageSizes: [spread], canvas: canvas)[0]
        #expect(abs(one.width / canvas.width - 0.88) < 0.001)
        let three = DiaryCollageLayout.frames(imageSizes: Array(repeating: spread, count: 3), canvas: canvas)
        #expect((0.50...0.52).contains(three[0].width / canvas.width))
        let six = DiaryCollageLayout.frames(imageSizes: Array(repeating: spread, count: 6), canvas: canvas)
        #expect(six[0].minY == six[1].minY)
        #expect(six[2].minY == six[3].minY)
        #expect(six[4].minY == six[5].minY)
    }

    @Test func selectedPagesProduceJPEGAndCancellationCleansUp() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = DiaryDocumentStore(ownerID: "jpg-tests", baseDirectory: folder)
        let book = try await library.createBook(title: "JPG", preset: .square)
        let store = DiaryDocumentStore(ownerID: "jpg-tests", baseDirectory: folder, bookID: book.id)
        var first = DiaryDocument(); first.bookID = book.id
        first.objects[first.rootContentID]?.referenceSize = book.defaultPageSize
        var second = DiaryDocument(); second.bookID = book.id
        second.objects[second.rootContentID]?.referenceSize = book.defaultPageSize
        try await store.save(first); try await store.save(second)
        let snapshot = try await store.loadBook()
        let result = try await DiaryBookImageExporter.export(book: snapshot, store: store, mode: .pages([first.id])) { _, _ in }
        defer { try? FileManager.default.removeItem(at: result.directory) }
        #expect(result.urls.count == 1)
        let data = try Data(contentsOf: result.urls[0])
        #expect(Array(data.prefix(2)) == [0xff, 0xd8])
        #expect(UIImage(data: data)?.size == book.defaultPageSize)
        let task = Task {
            try await DiaryBookImageExporter.export(book: snapshot, store: store, mode: .pages([first.id, second.id]), outputDirectory: folder.appendingPathComponent("cancelled")) { done, _ in
                if done == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("cancelled").path).isEmpty)
    }
}
