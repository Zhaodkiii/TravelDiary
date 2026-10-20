import UIKit
import PDFKit

struct DiaryBookPDFExport: Identifiable {
    let id = UUID()
    let url: URL
    let pageCount: Int
    let usedFallbackFonts: Bool
}

/// 按目录页序逐页读取不可变版本并写入 PDF，不同时持有整本的图片。
@MainActor
enum DiaryBookPDFExporter {
    enum ExportError: LocalizedError {
        case emptyBook
        case cannotWrite
        case pageFailed(Int, String)
        var errorDescription: String? {
            switch self {
            case .emptyBook: "手帐本还没有页面。"
            case .cannotWrite: "无法生成 PDF，请重试。"
            case let .pageFailed(index, reason): "第 \(index) 页导出失败：\(reason)"
            }
        }
    }

    static func pageSize(for designSize: CGSize) -> CGSize {
        if designSize == DiaryPagePreset.a5.size {
            return CGSize(width: 148 / 25.4 * 72, height: 210 / 25.4 * 72)
        }
        if designSize == DiaryPagePreset.b5.size {
            return CGSize(width: 176 / 25.4 * 72, height: 250 / 25.4 * 72)
        }
        // 自定义页面以 300 DPI 把设计像素换算为 PDF point，保留原始长宽比。
        return CGSize(width: designSize.width * 72 / 300, height: designSize.height * 72 / 300)
    }

    static func export(book: DiaryBook, store: DiaryDocumentStore,
                       outputDirectory: URL? = nil,
                       progress: (Int, Int) -> Void = { _, _ in }) async throws -> DiaryBookPDFExport {
        guard !book.pages.isEmpty else { throw ExportError.emptyBook }
        try Task.checkCancellation()
        let bookLease = StorageActivity.shared.acquire(store.storageRoot)
        defer { withExtendedLifetime(bookLease) {} }
        let directory = try StorageWorkspace.create(owner: store.ownerID, bookID: book.id, parent: outputDirectory)
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: directory) } }
        let workspaceLease = StorageActivity.shared.acquire(directory)
        defer { withExtendedLifetime(workspaceLease) {} }
        let reservation = try StorageSpaceBudget.shared.reserve(at: directory, estimatedPeak: Int64(book.pages.count) * 12_000_000)
        defer { withExtendedLifetime(reservation) {} }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = String(book.title.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && !"/\\:".unicodeScalars.contains($0)
        }.map(String.init).joined().prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = directory.appendingPathComponent((safeName.isEmpty ? "我的手帐" : safeName) + ".pdf")
        let partial = directory.appendingPathComponent("export.partial")
        var mediaBox = CGRect(origin: .zero, size: pageSize(for: book.defaultPageSize))
        guard let consumer = CGDataConsumer(url: partial as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox,
                [kCGPDFContextTitle: book.title, kCGPDFContextCreator: "TravelDiary"] as CFDictionary) else { throw ExportError.cannotWrite }
        var closed = false
        defer { if !closed { context.closePDF() } }
        var fallback = false
        progress(0, book.pages.count)
        for (index, page) in book.pages.enumerated() {
            try Task.checkCancellation()
            do {
                fallback = try await append(page, store: store, context: context) || fallback
            } catch is CancellationError { throw CancellationError() }
            catch { throw ExportError.pageFailed(index + 1, error.localizedDescription) }
            progress(index + 1, book.pages.count)
            await Task.yield()
        }
        try Task.checkCancellation()
        context.closePDF(); closed = true
        guard let pdf = CGPDFDocument(partial as CFURL), pdf.numberOfPages == book.pages.count else { throw ExportError.cannotWrite }
        try FileManager.default.moveItem(at: partial, to: destination)
        try StorageWorkspace.complete(directory)
        completed = true
        return DiaryBookPDFExport(url: destination, pageCount: book.pages.count, usedFallbackFonts: fallback)
    }

    private static func append(_ page: DiaryPageEntry, store: DiaryDocumentStore, context: CGContext) async throws -> Bool {
        let loaded = try await store.loadPDFSource(page)
        try Task.checkCancellation()
        let fonts = loaded.document.objects.values.flatMap { $0.layers.filter { $0.kind == .text }.compactMap(\.font) }
        await DiaryFontCatalog.shared.prewarm(fonts)
        try Task.checkCancellation()
        let fallback = fonts.contains { !DiaryFontCatalog.shared.available($0) }
        autoreleasepool {
            let designSize = loaded.document.root.referenceSize
            var mediaBox = CGRect(origin: .zero, size: pageSize(for: designSize))
            let pageInfo = [kCGPDFContextMediaBox: NSData(bytes: &mediaBox, length: MemoryLayout<CGRect>.size)] as CFDictionary
            context.beginPDFPage(pageInfo)
            context.saveGState()
            context.translateBy(x: 0, y: mediaBox.height)
            context.scaleBy(x: mediaBox.width / designSize.width, y: -mediaBox.height / designSize.height)
            UIGraphicsPushContext(context)
            // PDF 的纸张背景为白色；作品中的照片、文字、笔画及混合效果沿用正式导出规则。
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: designSize))
            DiaryPageRenderer.draw(loaded.document, images: loaded.images, in: context, cacheObjects: false)
            UIGraphicsPopContext()
            context.restoreGState()
            context.endPDFPage()
        }
        return fallback
    }

    static func discard(_ export: DiaryBookPDFExport) {
        try? FileManager.default.removeItem(at: export.url.deletingLastPathComponent())
    }
}
