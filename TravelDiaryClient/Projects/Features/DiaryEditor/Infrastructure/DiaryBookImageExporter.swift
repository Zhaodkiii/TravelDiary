import SwiftUI
import Photos

@MainActor
enum DiaryBookImageExporter {
    enum Mode { case pages(Set<UUID>), spreads(Int) }
    struct Result {
        let urls: [URL]
        let directory: URL
        let usedFallbackFonts: Bool
    }

    static func spreadPages(_ book: DiaryBook) -> [[DiaryPageEntry?]] {
        book.contentPages.isEmpty ? [] : book.readingSpreads
    }

    static func export(book: DiaryBook, store: DiaryDocumentStore, mode: Mode,
                       outputDirectory: URL? = nil,
                       progress: (Int, Int) -> Void) async throws -> Result {
        let bookLease = StorageActivity.shared.acquire(store.storageRoot)
        defer { withExtendedLifetime(bookLease) {} }
        let directory = try StorageWorkspace.create(owner: store.ownerID, bookID: book.id, parent: outputDirectory)
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: directory) } }
        let workspaceLease = StorageActivity.shared.acquire(directory)
        defer { withExtendedLifetime(workspaceLease) {} }
        let reservation = try StorageSpaceBudget.shared.reserve(at: directory, estimatedPeak: Int64(book.pages.count) * 16_000_000)
        defer { withExtendedLifetime(reservation) {} }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = [], fallback = false
        func render(_ page: DiaryPageEntry) async throws -> UIImage {
            let loaded = try await store.loadPDFSource(page)
            let fonts = loaded.document.objects.values.flatMap { $0.layers.compactMap(\.font) }
            await DiaryFontCatalog.shared.prewarm(fonts)
            try Task.checkCancellation()
            fallback = fallback || fonts.contains { !DiaryFontCatalog.shared.available($0) }
            return renderPage(loaded.document, images: loaded.images, longestEdge: 3000)
        }

        func write(_ image: UIImage) throws {
            try Task.checkCancellation()
            let url = directory.appendingPathComponent(String(format: "手帐-%03d.jpg", urls.count + 1))
            guard let data = image.jpegData(compressionQuality: 0.95) else { throw DiaryEditorError.exportFailed }
            try data.write(to: url, options: .atomic); urls.append(url)
        }
        switch mode {
        case .pages(let selected):
            let pages = book.pages.filter { selected.contains($0.id) }
            guard !pages.isEmpty else { throw DiaryBookPDFExporter.ExportError.emptyBook }
            progress(0, pages.count)
            for (index, page) in pages.enumerated() {
                try await write(render(page)); progress(index + 1, pages.count); await Task.yield()
            }
        case .spreads(let count):
            let spreads = spreadPages(book)
            guard DiaryCollageLayout.supportedCounts.contains(count), !spreads.isEmpty else { throw DiaryBookPDFExporter.ExportError.emptyBook }
            progress(0, spreads.count)
            for start in stride(from: 0, to: spreads.count, by: count) {
                var images: [UIImage] = []
                for index in start..<min(start + count, spreads.count) {
                    let pair = spreads[index]
                    let left = try await pair[0].asyncMap(render)
                    let right = try await pair[1].asyncMap(render)
                    images.append(try renderSpread(left: left, right: right, lining: index == 0, book: book))
                    progress(index + 1, spreads.count); await Task.yield()
                }
                try write(collage(images))
            }
        }
        try Task.checkCancellation(); try StorageWorkspace.complete(directory); completed = true
        return Result(urls: urls, directory: directory, usedFallbackFonts: fallback)
    }

    static func renderPage(_ document: DiaryDocument, images: [UUID: UIImage], longestEdge: CGFloat) -> UIImage {
        let size = document.root.referenceSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(1, longestEdge / max(size.width, size.height)); format.opaque = true
        return autoreleasepool {
            UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
                DiaryPageRenderer.draw(document, images: images, in: ctx.cgContext, cacheObjects: false)
            }
        }
    }

    static func renderSpread(left: UIImage?, right: UIImage?, lining: Bool, book: DiaryBook,
                             width: CGFloat = 800, scale: CGFloat = 3) throws -> UIImage {
        let ratio = book.contentPages.first?.size ?? book.defaultPageSize
        let height = width / 2 * (0.955 * (1 - DiaryBookSpine.halfGapFraction) * ratio.height / ratio.width + 0.09)
        let renderer = ImageRenderer(content: DiaryExportSpread(left: left, right: right, lining: lining)
            .frame(width: width, height: height))
        renderer.scale = scale
        guard let image = renderer.uiImage else { throw DiaryEditorError.exportFailed }
        return image
    }

    private static let collageBackground = UIImage(named: "DiarySpreadExportBackground")

    static func collage(_ images: [UIImage], canvasWidth: CGFloat = 1200, scale: CGFloat = 2) -> UIImage {
        let size = CGSize(width: canvasWidth, height: canvasWidth / DiaryCollageLayout.aspectRatio)
        let frames = DiaryCollageLayout.frames(imageSizes: images.map(\.size), canvas: size)
        let format = UIGraphicsImageRendererFormat(); format.scale = scale; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(red: 0.98, green: 0.975, blue: 0.96, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            if let background = collageBackground {
                let fillScale = max(size.width / background.size.width, size.height / background.size.height)
                let backgroundSize = CGSize(width: background.size.width * fillScale,
                                            height: background.size.height * fillScale)
                background.draw(in: CGRect(x: (size.width - backgroundSize.width) / 2,
                                           y: (size.height - backgroundSize.height) / 2,
                                           width: backgroundSize.width, height: backgroundSize.height))
            }
            for (image, frame) in zip(images, frames) { image.draw(in: frame) }
        }
    }

    static func saveToPhotos(_ urls: [URL]) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "DiaryExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "未获得相册保存权限。请在系统设置中允许添加照片，再点重试保存；也可以直接分享图片。"])
        }
        try await PHPhotoLibrary.shared().performChanges(photoChanges(for: urls))
    }

    // Photos executes this block on its own queue. Build it outside MainActor,
    // and capture only Sendable file URLs, never UI state or rendered images.
    nonisolated static func photoChanges(for urls: [URL]) -> @Sendable () -> Void {
        return {
            for url in urls {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
            }
        }
    }
}

private extension Optional where Wrapped == DiaryPageEntry {
    func asyncMap(_ transform: (DiaryPageEntry) async throws -> UIImage) async rethrows -> UIImage? {
        guard let value = self else { return nil }; return try await transform(value)
    }
}

struct DiaryExportSpread: View {
    let left: UIImage?
    let right: UIImage?
    let lining: Bool
    var body: some View {
        DiaryBoundSpread {
            leaf(left, lining: lining)
        } right: {
            leaf(right, lining: false)
        }
    }
    @ViewBuilder private func leaf(_ image: UIImage?, lining: Bool) -> some View {
        ZStack {
            Color(red: 0.96, green: 0.92, blue: 0.82)
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if lining { DiaryBookLining() }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
    }
}
