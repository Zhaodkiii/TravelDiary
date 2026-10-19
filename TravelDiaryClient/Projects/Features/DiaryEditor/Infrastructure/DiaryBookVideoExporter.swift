import SwiftUI
import AVFoundation
import Photos

nonisolated struct DiaryBookVideoExport: Sendable {
    let url: URL
    let directory: URL
    let duration: Double
    let size: CGSize
    let spreadCount: Int
    let usedFallbackFonts: Bool
}

@MainActor
enum DiaryBookVideoExporter {
    nonisolated enum ExportError: LocalizedError {
        case invalidRange, cannotRender, cannotEncode, invalidVideo, pageFailed(Int, String)
        var errorDescription: String? {
            switch self {
            case .invalidRange: "请选择有效的跨页范围。"
            case .cannotRender: "无法绘制视频画面，请重试。"
            case .cannotEncode: "无法编码视频，请检查可用存储空间后重试。"
            case .invalidVideo: "视频校验未通过，请重新生成。"
            case let .pageFailed(index, reason): "第 \(index) 个跨页准备失败：\(reason)"
            }
        }
    }
    struct Prepared {
        let urls: [URL]
        let rings: UIImage
        let usedFallbackFonts: Bool
    }

    /// Entries and revision IDs are captured by value. PNGs freeze the assets
    /// before encoding; only one spread's source documents are live at a time.
    static func prepare(book: DiaryBook, store: DiaryDocumentStore, options: DiaryVideoOptions,
                        directory: URL, width: CGFloat,
                        progress: (Int, Int) -> Void = { _, _ in }) async throws -> Prepared {
        let pairs = DiaryBookImageExporter.spreadPages(book)
        guard options.firstSpread >= 0, options.lastSpread >= options.firstSpread,
              options.lastSpread < pairs.count else { throw ExportError.invalidRange }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = [], fallback = false
        var spreadSize = CGSize.zero
        let count = options.lastSpread - options.firstSpread + 1
        progress(0, count)
        for index in options.firstSpread...options.lastSpread {
            try Task.checkCancellation()
            do {
                var leaves: [UIImage?] = []
                for page in pairs[index] {
                    guard let page else { leaves.append(nil); continue }
                    let loaded = try await store.loadPDFSource(page)
                    let fonts = loaded.document.objects.values.flatMap { $0.layers.compactMap(\.font) }
                    await DiaryFontCatalog.shared.prewarm(fonts)
                    try Task.checkCancellation()
                    fallback = fallback || fonts.contains { !DiaryFontCatalog.shared.available($0) }
                    leaves.append(DiaryBookImageExporter.renderPage(loaded.document, images: loaded.images, longestEdge: width))
                }
                let url = directory.appendingPathComponent("spread-\(index).png")
                // Autorelease image encoders before moving on to the next spread.
                spreadSize = try autoreleasepool {
                    let image = try DiaryBookImageExporter.renderSpread(left: leaves[0], right: leaves[1],
                        lining: index == 0, book: book, width: width, scale: 1)
                    guard let data = image.pngData() else { throw ExportError.cannotRender }
                    try data.write(to: url, options: .atomic)
                    return image.size
                }
                urls.append(url); progress(urls.count, count)
            } catch is CancellationError { throw CancellationError() }
            catch { throw ExportError.pageFailed(index + 1, error.localizedDescription) }
            await Task.yield()
        }
        let rim = spreadSize.width * 0.0225
        let overlay = ImageRenderer(content: DiaryBindingRings().padding(rim).frame(width: spreadSize.width, height: spreadSize.height))
        overlay.scale = 1
        guard let rings = overlay.uiImage else { throw ExportError.cannotRender }
        return Prepared(urls: urls, rings: rings, usedFallbackFonts: fallback)
    }

    static func export(book: DiaryBook, store: DiaryDocumentStore, options: DiaryVideoOptions,
                       outputDirectory: URL = FileManager.default.temporaryDirectory,
                       progress: @escaping @MainActor @Sendable (String, Double) -> Void) async throws -> DiaryBookVideoExport {
        let directory = outputDirectory.appendingPathComponent("DiaryMP4-\(UUID())", isDirectory: true)
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: directory) } }
        let framesDirectory = directory.appendingPathComponent("frames", isDirectory: true)
        let prepared = try await prepare(book: book, store: store, options: options, directory: framesDirectory,
            width: options.frame.size.width * 0.9) { done, total in
                progress("正在准备跨页 · \(done)/\(total)", Double(done) / Double(total) * 0.2)
            }
        try Task.checkCancellation()
        let partial = directory.appendingPathComponent("export.partial.mp4")
        try await encode(urls: prepared.urls, rings: prepared.rings, title: book.title,
                         options: options, destination: partial, progress: progress)
        progress("正在校验视频…", 0.97)
        try await validate(url: partial, timeline: options.timeline, size: options.frame.size)
        try Task.checkCancellation()
        let safeName = String(book.title.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && !"/\\:".unicodeScalars.contains($0)
        }.map(String.init).joined().prefix(70)).trimmingCharacters(in: .whitespacesAndNewlines)
        let url = directory.appendingPathComponent((safeName.isEmpty ? "我的手帐" : safeName) + "-翻页.mp4")
        try FileManager.default.moveItem(at: partial, to: url)
        try FileManager.default.removeItem(at: framesDirectory)
        completed = true; progress("视频已生成", 1)
        return DiaryBookVideoExport(url: url, directory: directory, duration: options.timeline.duration,
            size: options.frame.size, spreadCount: prepared.urls.count, usedFallbackFonts: prepared.usedFallbackFonts)
    }

    /// Encoding and Core Graphics drawing run on the concurrent executor.
    /// The receiver provides back-pressure instead of spinning on writer readiness.
    @concurrent private static func encode(urls: [URL], rings: UIImage, title: String, options: DiaryVideoOptions,
                                           destination: URL,
                                           progress: @escaping @MainActor @Sendable (String, Double) -> Void) async throws {
        let size = options.frame.size, timeline = options.timeline
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000,
                AVVideoExpectedSourceFrameRateKey: timeline.fps, AVVideoMaxKeyFrameIntervalKey: timeline.fps * 2]
        ])
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw ExportError.cannotEncode }
        let attributes = CVPixelBufferCreationAttributes(pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA),
            size: CVImageSize(size), compatibility: [.cgBitmapContext, .cgImage])
        // This API adds its input to the writer itself.
        let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: attributes)
        let pool = try CVMutablePixelBuffer.Pool(pixelBufferAttributes: attributes,
            configuration: .init(minimumBufferCount: 3))
        var finished = false
        defer { if !finished { writer.cancelWriting() } }
        guard writer.startWriting() else { throw writer.error ?? ExportError.cannotEncode }
        writer.startSession(atSourceTime: .zero)
        var cache: [Int: UIImage] = [:]
        for frame in 0..<timeline.frameCount {
            try Task.checkCancellation()
            let sample = timeline.sample(frame: frame)
            let needed = Set([sample.spread, sample.next].compactMap { $0 })
            cache = cache.filter { needed.contains($0.key) }
            for index in needed where cache[index] == nil {
                guard urls.indices.contains(index), let image = UIImage(contentsOfFile: urls[index].path) else { throw ExportError.cannotRender }
                cache[index] = image
            }
            guard let current = cache[sample.spread] else { throw ExportError.cannotRender }
            let mutable = try pool.makeMutablePixelBuffer()
            try autoreleasepool {
                try mutable.withUnsafeBuffer { buffer in
                    try drawBuffer(buffer, size: size, title: title, sample: sample, current: current,
                                   next: sample.next.flatMap { cache[$0] }, rings: rings)
                }
            }
            try await receiver.append(CVReadOnlyPixelBuffer(mutable), with: CMTime(value: Int64(frame), timescale: Int32(timeline.fps)))
            if frame % timeline.fps == 0 {
                await progress("正在生成视频 · \(Int(Double(frame) / Double(timeline.frameCount) * 100))%",
                               0.2 + Double(frame) / Double(timeline.frameCount) * 0.75)
            }
        }
        try Task.checkCancellation()
        writer.endSession(atSourceTime: CMTime(value: Int64(timeline.frameCount), timescale: Int32(timeline.fps)))
        receiver.finish()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ExportError.cannotEncode }
        finished = true
    }

    nonisolated private static func drawBuffer(_ buffer: CVPixelBuffer, size: CGSize, title: String,
        sample: DiaryVideoTimeline.Sample, current: UIImage, next: UIImage?, rings: UIImage) throws {
        guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { throw ExportError.cannotRender }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else { throw ExportError.cannotRender }
        ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(ctx); defer { UIGraphicsPopContext() }
        DiaryVideoFrameRenderer.draw(in: ctx, size: size, title: title, sample: sample, current: current, next: next, rings: rings)
    }

    nonisolated static func validate(url: URL, timeline: DiaryVideoTimeline, size: CGSize) async throws {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: url)
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard playable, duration.isFinite, abs(duration - timeline.duration) <= 1 / Double(timeline.fps),
              let track = tracks.first, try await track.load(.naturalSize) == size else { throw ExportError.invalidVideo }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 320, height: 320)
        for frame in [0, timeline.frameCount - 1] {
            try Task.checkCancellation()
            _ = try await generator.image(at: CMTime(value: Int64(frame), timescale: Int32(timeline.fps)))
        }
    }

    static func saveToPhotos(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "DiaryVideo", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "未获得相册保存权限。请在系统设置中允许添加照片后重试，也可以分享或存储视频到文件。"])
        }
        try Task.checkCancellation()
        try await PHPhotoLibrary.shared().performChanges(photoChanges(for: url))
    }
    nonisolated static func photoChanges(for url: URL) -> @Sendable () -> Void {
        { PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil) }
    }
}
