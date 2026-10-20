import UIKit
import PDFKit
import CryptoKit

nonisolated struct PrintPrepared: Sendable {
    let directory: URL
    let snapshot: PrintSnapshot
    let files: [PrintFile]
    let warnings: [String]
    let pageCount: Int
}

@MainActor
enum DiaryBookPrintExporter {
    static func readySpreads(book: DiaryBook, readyPageIDs: Set<UUID>) -> [Int] {
        let spreads = DiaryBookImageExporter.spreadPages(book)
        return spreads.indices.filter { index in
            spreads[index].compactMap { $0 }.allSatisfy { readyPageIDs.contains($0.id) }
        }
    }

    static func proportionDifference(_ size: CGSize, product: PrintProduct) -> CGFloat {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              product.width_mm > 0, product.height_mm > 0 else { return .infinity }
        let ratio = size.width / size.height / (CGFloat(product.width_mm) / CGFloat(product.height_mm))
        return max(ratio, 1 / ratio) - 1
    }

    static func incompatiblePages(book: DiaryBook, product: PrintProduct) -> [Int] {
        book.contentPages.enumerated().compactMap { index, page in
            proportionDifference(page.size, product: product) > 0.15 + 0.000001 ? index + 1 : nil
        }
    }

    static func mapping(book: DiaryBook, product: PrintProduct) throws -> (cover: [DiaryPageEntry], inner: [DiaryPageEntry], count: Int) {
        let pages = book.contentPages
        guard !pages.isEmpty else { throw PrintFailure("请先添加内容页后再提交印制。") }
        let count = pages.count + (product.duplex ? pages.count % 2 : 0)
        guard product.min_pages <= count, count <= product.max_pages else {
            throw PrintFailure("当前为 \(count) 面内页，所选规格支持 \(product.min_pages)–\(product.max_pages) 面；请调整页数或更换规格。")
        }
        let invalid = incompatiblePages(book: book, product: product)
        guard invalid.isEmpty else {
            throw PrintFailure("第 \(invalid.map(String.init).joined(separator: "、")) 页与印制规格的比例偏差超过 15%，请更换规格或返回作品调整这些页面。")
        }
        if let shell = book.shell, proportionDifference(shell.size, product: product) > 0.15 + 0.000001 {
            throw PrintFailure("外壳与印制规格的比例偏差超过 15%，请更换规格或调整外壳。")
        }
        return (book.shell.map { [$0] } ?? [], pages, count)
    }

    static func prepare(book: DiaryBook, store: DiaryDocumentStore, product: PrintProduct,
                        directory: URL, onPageReady: ((UUID, URL) -> Void)? = nil, progress: (Int, Int) -> Void) async throws -> PrintPrepared {
        let lease = StorageActivity.shared.acquire(store.storageRoot)
        defer { withExtendedLifetime(lease) {} }
        let map = try mapping(book: book, product: product)
        let sourceDirectory = directory.appendingPathComponent("source")
        let source = try await store.freezeForPrinting(book, at: sourceDirectory)
        defer { try? FileManager.default.removeItem(at: sourceDirectory) }
        let adapted = book.contentPages.enumerated().compactMap { index, page in
            proportionDifference(page.size, product: product) > 0.001 ? String(index + 1) : nil
        }
        var warnings: [String] = adapted.isEmpty ? [] : ["第 \(adapted.joined(separator: "、")) 页已整页调整比例，请放大检查文字与照片。"]
        if let shell = book.shell, proportionDifference(shell.size, product: product) > 0.001 {
            warnings.append("外壳已整页调整比例，请放大检查文字与照片。")
        }
        var files: [PrintFile] = []
        let previewDirectory = directory.appendingPathComponent("previews", isDirectory: true)
        if onPageReady != nil { try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true) }
        var done = 0
        let total = map.cover.count + map.inner.count
        for (role, pages, blank) in [("cover", map.cover, false), ("interior", map.inner, map.count > map.inner.count)] {
            guard !pages.isEmpty else { continue }
            let url = directory.appendingPathComponent(role + ".pdf")
            var box = CGRect(x: 0, y: 0, width: CGFloat(product.width_mm) / 25.4 * 72, height: CGFloat(product.height_mm) / 25.4 * 72)
            for (index, page) in pages.enumerated() {
                try Task.checkCancellation()
                let loaded = try await source.loadPDFSource(page)
                let fonts = loaded.document.objects.values.flatMap { $0.layers.filter { $0.kind == .text }.compactMap(\.font) }
                await DiaryFontCatalog.shared.prewarm(fonts)
                guard !fonts.contains(where: { !DiaryFontCatalog.shared.available($0) }) else { throw PrintFailure("\(role == "cover" ? "外壳" : "内页")第 \(index+1) 面存在缺失字体，请修复后再印制") }
                let design = loaded.document.root.referenceSize
                guard proportionDifference(design, product: product) <= 0.15 + 0.000001 else {
                    throw PrintFailure("页面实际内容比例与规格偏差超过 15%，请返回作品调整后重试。")
                }
                warnings += inspect(loaded.document, widthMM: CGFloat(product.width_mm)).map { "\(role == "cover" ? "外壳" : "内页")第 \(index+1) 面：\($0)" }
                // 单页先落盘，再合入生产 PDF；缩略图从同一张 PDF 生成，完成一页即可发布。
                let pageURL = directory.appendingPathComponent("page-\(page.id).pdf")

                guard let pageConsumer = CGDataConsumer(url: pageURL as CFURL),
                      let pageContext = CGContext(consumer: pageConsumer, mediaBox: &box, nil) else { throw PrintFailure("无法准备页面") }
                var pageClosed = false
                defer { if !pageClosed { pageContext.closePDF() } }
                do {
                    let data = NSData(bytes: &box, length: MemoryLayout<CGRect>.size)
                    pageContext.beginPDFPage([kCGPDFContextMediaBox:data, kCGPDFContextTrimBox:data, kCGPDFContextBleedBox:data] as CFDictionary)
                    pageContext.saveGState(); pageContext.translateBy(x: 0, y: box.height)
                    pageContext.scaleBy(x: box.width/design.width, y: -box.height/design.height)
                    pageContext.setFillColor(UIColor.white.cgColor); pageContext.fill(CGRect(origin: .zero, size: design))
                    try await DiaryPageRenderer.drawForPrinting(loaded.document, images: loaded.images, in: pageContext)
                    pageContext.restoreGState(); pageContext.endPDFPage()
                    pageContext.closePDF(); pageClosed = true
                }
                if let onPageReady {
                    let thumbnailURL = previewDirectory.appendingPathComponent("\(page.id).jpg")
                    try await Task.detached(priority: .utility) {
                        try writeThumbnail(pdfURL: pageURL, destination: thumbnailURL)
                    }.value
                    onPageReady(page.id, thumbnailURL)
                }
                done += 1; progress(done, total); await Task.yield()
            }
            if blank { warnings.append("为双面印刷，在内页末尾补了一面空白，请在预览中确认。") }
            let sources = pages.map { directory.appendingPathComponent("page-\($0.id).pdf") }
            let file = try await Task.detached(priority: .utility) {
                try assemble(sources: sources, blank: blank, role: role, destination: url, widthMM: product.width_mm, heightMM: product.height_mm)
            }.value
            files.append(file)
        }
        let entries = map.cover.map { PrintSnapshot.Page(page_id: $0.id, revision_id: $0.revisionID, role: "shell") }
            + map.inner.map { PrintSnapshot.Page(page_id: $0.id, revision_id: $0.revisionID, role: "interior") }
        return PrintPrepared(directory: directory, snapshot: PrintSnapshot(book_id: book.id, catalog_revision: book.catalogRevision, pages: entries, exporter_version: "print-v1"), files: files, warnings: warnings, pageCount: map.count)
    }

    nonisolated private static func assemble(sources: [URL], blank: Bool, role: String, destination: URL, widthMM: Int, heightMM: Int) throws -> PrintFile {
        var box = CGRect(x: 0, y: 0, width: CGFloat(widthMM) / 25.4 * 72, height: CGFloat(heightMM) / 25.4 * 72)
        guard let consumer = CGDataConsumer(url: destination as CFURL), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw PrintFailure("无法写入生产文件") }
        var closed = false
        defer { if !closed { context.closePDF() } }
        for url in sources {
            try Task.checkCancellation()
            try autoreleasepool {
                guard let pdf = CGPDFDocument(url as CFURL), let page = pdf.page(at: 1) else { throw PrintFailure("页面准备失败") }
                let data = NSData(bytes: &box, length: MemoryLayout<CGRect>.size)
                context.beginPDFPage([kCGPDFContextMediaBox:data, kCGPDFContextTrimBox:data, kCGPDFContextBleedBox:data] as CFDictionary)
                context.drawPDFPage(page); context.endPDFPage()
            }
        }
        if blank {
            let data = NSData(bytes: &box, length: MemoryLayout<CGRect>.size)
            context.beginPDFPage([kCGPDFContextMediaBox:data, kCGPDFContextTrimBox:data, kCGPDFContextBleedBox:data] as CFDictionary)
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(box); context.endPDFPage()
        }
        context.closePDF(); closed = true
        let count = sources.count + (blank ? 1 : 0)
        guard let pdf = CGPDFDocument(destination as CFURL), pdf.numberOfPages == count, !pdf.isEncrypted else { throw PrintFailure("生产 PDF 检查失败") }
        for index in 1...count {
            guard let page = pdf.page(at: index), page.rotationAngle % 360 == 0 else { throw PrintFailure("生产稿页面方向不正确") }
            for kind in [CGPDFBox.mediaBox, .trimBox, .bleedBox] {
                let bounds = page.getBoxRect(kind)
                guard abs(bounds.width * 25.4 / 72 - CGFloat(widthMM)) < 0.2,
                      abs(bounds.height * 25.4 / 72 - CGFloat(heightMM)) < 0.2 else { throw PrintFailure("生产稿物理尺寸不一致") }
            }
        }
        let hash = try hashFile(destination)
        let size = try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int ?? 0
        guard size > 0, size <= 512*1024*1024 else { throw PrintFailure("生产文件过大，请减少页面或照片后重试") }
        return PrintFile(role: role, sha256: hash, size: size, page_count: count)
    }

    nonisolated private static func writeThumbnail(pdfURL: URL, destination: URL) throws {
        try autoreleasepool {
            guard let page = PDFDocument(url: pdfURL)?.page(at: 0),
                  let jpeg = page.thumbnail(of: CGSize(width: 360, height: 520), for: .mediaBox).jpegData(compressionQuality: 0.9) else { throw PrintFailure("无法生成页面预览") }
            try jpeg.write(to: destination, options: .atomic)
        }
    }

    /// 递归检查实例变换后的照片尺寸；复杂槽位提示人工放大检查，不宣称自动通过。
    private static func inspect(_ document: DiaryDocument, widthMM: CGFloat) -> [String] {
        var notes = Set<String>()
        func visit(_ id: UUID, scale: CGFloat, depth: Int) {
            guard depth < 32, let content = document.objects[id] else { return }
            for layer in content.layers where layer.visible && layer.effectiveOpacity > 0 {
                let s = scale * abs(layer.transform.scale) * max(abs(layer.transform.stretchX), abs(layer.transform.stretchY))
                if let child = layer.contentID, let object = document.objects[child] {
                    let ratio = max(layer.size.width / max(object.referenceSize.width, 1), layer.size.height / max(object.referenceSize.height, 1))
                    visit(child, scale: s * ratio, depth: depth + 1)
                }
                if layer.kind == .photo, let assetID = layer.assetID, let asset = document.assets[assetID] {
                    if layer.photoSlot != nil || layer.photoPlacement != nil { notes.insert("含裁切照片槽位，请放大检查清晰度及照片边缘。") }
                    let printedWidth = layer.size.width * s / document.root.referenceSize.width * widthMM
                    let ppi = asset.pixelSize.width / max(printedWidth / 25.4 * max(layer.crop.zoom, 1), 0.01)
                    if ppi < 200 { notes.insert("有照片估算清晰度低于 200 PPI，印刷可能模糊，请放大检查。") }
                }
            }
        }
        visit(document.rootContentID, scale: 1, depth: 0)
        return notes.sorted()
    }
    nonisolated static func hashFile(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024*1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
