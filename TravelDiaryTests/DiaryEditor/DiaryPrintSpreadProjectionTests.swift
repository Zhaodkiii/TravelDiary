import Testing
import Foundation
import CoreGraphics
@testable import TravelDiary

@MainActor
struct DiaryPrintSpreadProjectionTests {
    @Test func singlePagesRemainWholeAndSpreadProducesTwoStableFaces() {
        var book = DiaryBook(title: "混排")
        book.defaultPageSize = CGSize(width: 4370, height: 3130)
        book.pages = [CGSize(width: 2185, height: 3130), CGSize(width: 1044, height: 1507), book.defaultPageSize].map {
            DiaryPageEntry(id: UUID(), title: "", revisionID: UUID(), size: $0)
        }
        let projected = DiaryBookPrintExporter.printBook(book)
        #expect(projected.contentPages.count == 4)
        #expect(projected.pages[0] == book.pages[0])
        #expect(projected.pages[1] == book.pages[1])
        #expect(projected.pages[2].size == CGSize(width: 2185, height: 3130))
        #expect(projected.pages[3].size == CGSize(width: 2185, height: 3130))
        #expect(Set(projected.pages.map(\.id)).count == 4)
        #expect(projected.pages.map(\.id) == DiaryBookPrintExporter.printBook(book).pages.map(\.id))
        #expect(book.pages.count == 3)
    }
}
