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
    static func mapping(book: DiaryBook, front: UUID, back: UUID, product: PrintProduct) throws -> (cover: [DiaryPageEntry], inner: [DiaryPageEntry], count: Int) {
        guard front != back, let f = book.contentPages.first(where: { $0.id == front }), let b = book.contentPages.first(where: { $0.id == back }) else {
            throw PrintFailure("请分别选择封面和封底；外壳不能作为印刷页面")
        }
        let inner = book.contentPages.filter { $0.id != front && $0.id != back }
        guard !inner.isEmpty else { throw PrintFailure("除封面和封底外，至少保留一页内页") }
        let count = inner.count + (product.duplex ? inner.count % 2 : 0)
        guard (product.min_pages...product.max_pages).contains(count), product.cover_mode == "separate_front_back" else { throw PrintFailure("当前页面数量或封面工艺不符合所选规格") }
        for page in book.contentPages {
            let size = DiaryBookPDFExporter.pageSize(for: page.size)
            guard abs(size.width * 25.4 / 72 - CGFloat(product.width_mm)) < 0.2,
                  abs(size.height * 25.4 / 72 - CGFloat(product.height_mm)) < 0.2 else {
                throw PrintFailure("页面尺寸与印制规格不一致，请选择对应尺寸的手帐")
            }
        }
        return ([f, b], inner, count)
    }

    static func prepare(book: DiaryBook, store: DiaryDocumentStore, product: PrintProduct, front: UUID, back: UUID,
                        directory: URL, progress: (Int, Int) -> Void) async throws -> PrintPrepared {
        let map = try mapping(book: book, front: front, back: back, product: product)
        let sourceDirectory = directory.appendingPathComponent("source")
        let source = try await store.freezeForPrinting(book, at: sourceDirectory)
        defer { try? FileManager.default.removeItem(at: sourceDirectory) }
        var warnings: [String] = [], files: [PrintFile] = []
        var done = 0
        let total = map.cover.count + map.inner.count
        for (role, pages, blank) in [("cover", map.cover, false), ("interior", map.inner, map.count > map.inner.count)] {
            let url = directory.appendingPathComponent(role + ".pdf")
            var box = CGRect(x: 0, y: 0, width: CGFloat(product.width_mm) / 25.4 * 72, height: CGFloat(product.height_mm) / 25.4 * 72)
            guard let consumer = CGDataConsumer(url: url as CFURL), let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw PrintFailure("无法写入生产文件") }
            var closed = false
            defer { if !closed { ctx.closePDF() } }
            for (index, page) in pages.enumerated() {
                try Task.checkCancellation()
                let loaded = try await source.loadPDFSource(page)
                let fonts = loaded.document.objects.values.flatMap { $0.layers.filter { $0.kind == .text }.compactMap(\.font) }
                await DiaryFontCatalog.shared.prewarm(fonts)
                guard !fonts.contains(where: { !DiaryFontCatalog.shared.available($0) }) else { throw PrintFailure("\(role == "cover" ? "封面" : "内页")第 \(index+1) 面存在缺失字体，请修复后再印制") }
                let design = loaded.document.root.referenceSize
                warnings += inspect(loaded.document, widthMM: CGFloat(product.width_mm)).map { "\(role == "cover" ? "封面" : "内页")第 \(index+1) 面：\($0)" }
                autoreleasepool {
                    let data = NSData(bytes: &box, length: MemoryLayout<CGRect>.size)
                    ctx.beginPDFPage([kCGPDFContextMediaBox:data, kCGPDFContextTrimBox:data, kCGPDFContextBleedBox:data] as CFDictionary)
                    ctx.saveGState(); ctx.translateBy(x: 0, y: box.height)
                    ctx.scaleBy(x: box.width/design.width, y: -box.height/design.height)
                    UIGraphicsPushContext(ctx)
                    ctx.setFillColor(UIColor.white.cgColor); ctx.fill(CGRect(origin: .zero, size: design))
                    DiaryPageRenderer.draw(loaded.document, images: loaded.images, in: ctx, cacheObjects: false)
                    UIGraphicsPopContext(); ctx.restoreGState(); ctx.endPDFPage()
                }
                done += 1; progress(done, total); await Task.yield()
            }
            if blank {
                let data = NSData(bytes: &box, length: MemoryLayout<CGRect>.size)
                ctx.beginPDFPage([kCGPDFContextMediaBox:data,kCGPDFContextTrimBox:data,kCGPDFContextBleedBox:data] as CFDictionary)
                ctx.setFillColor(UIColor.white.cgColor); ctx.fill(box); ctx.endPDFPage()
                warnings.append("为双面印刷，在内页末尾补了一面空白，请在预览中确认。")
            }
            ctx.closePDF(); closed = true
            let count = pages.count + (blank ? 1 : 0)
            guard let pdf = CGPDFDocument(url as CFURL), pdf.numberOfPages == count else { throw PrintFailure("生产 PDF 校验失败") }
            guard !pdf.isEncrypted else { throw PrintFailure("生产稿不可加密") }
            for index in 1...count {
                guard let page = pdf.page(at: index), page.rotationAngle % 360 == 0 else { throw PrintFailure("生产稿页面方向不正确") }
                for kind in [CGPDFBox.mediaBox, .trimBox, .bleedBox] {
                    let bounds = page.getBoxRect(kind)
                    guard abs(bounds.width * 25.4 / 72 - CGFloat(product.width_mm)) < 0.2,
                          abs(bounds.height * 25.4 / 72 - CGFloat(product.height_mm)) < 0.2 else { throw PrintFailure("生产稿物理尺寸不一致") }
                }
            }
            let hash = try await Task.detached { try hashFile(url) }.value
            let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
            guard size > 0, size <= 512*1024*1024 else { throw PrintFailure("生产文件过大，请减少页面或照片后重试") }
            files.append(PrintFile(role: role, sha256: hash, size: size, page_count: count))
        }
        let entries = map.cover.enumerated().map { PrintSnapshot.Page(page_id: $0.element.id, revision_id: $0.element.revisionID, role: $0.offset == 0 ? "front" : "back") }
            + map.inner.map { PrintSnapshot.Page(page_id: $0.id, revision_id: $0.revisionID, role: "interior") }
        return PrintPrepared(directory: directory, snapshot: PrintSnapshot(book_id: book.id, catalog_revision: book.catalogRevision, pages: entries, exporter_version: "print-v1"), files: files, warnings: warnings, pageCount: map.count)
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
