import Testing
import UIKit
import AVFoundation
@testable import TravelDiary

@MainActor
@Suite(.serialized)
struct DiaryBookVideoExportTests {
    @Test func timelineHasExactBoundariesAndFinalRest() {
        let timeline = DiaryVideoTimeline(spreadCount: 3, hold: 3)
        #expect(timeline.frameCount == 408)
        #expect(timeline.duration == 13.6)
        #expect(timeline.sample(at: 0).intro)
        #expect(!timeline.sample(at: 2).intro)
        #expect(timeline.sample(at: 4.999).next == nil)
        #expect(timeline.sample(at: 5).next == 1)
        #expect(timeline.sample(at: 5).turn == 0)
        #expect(timeline.sample(at: 5.4).turn == 0.5)
        #expect(timeline.sample(at: 5.8).spread == 1)
        #expect(timeline.sample(at: timeline.duration).spread == 2)
        #expect(timeline.sample(at: timeline.duration).next == nil)
        #expect(timeline.sample(at: .infinity).intro)
        #expect(DiaryVideoTimeline(spreadCount: 1, hold: 2).duration == 5)
    }

    private func solid(_ color: UIColor, bottom: UIColor? = nil, size: CGSize = CGSize(width: 600, height: 600)) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill(); context.fill(CGRect(origin: .zero, size: size))
            if let bottom {
                bottom.setFill(); context.fill(CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2))
            }
        }
    }
    private func pixel(_ image: UIImage, x: CGFloat, y: CGFloat) throws -> [UInt8] {
        let cg = try #require(image.cgImage)
        let crop = try #require(cg.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes {
            let ctx = CGContext(data: $0.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes
    }

    @Test func rendererUsesNextLeftAsPaperBackAndKeepsCompleteBookInBothFrames() throws {
        let size = CGSize(width: 800, height: 560)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let current = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 400, height: 560))
            UIColor.blue.setFill(); context.fill(CGRect(x: 400, y: 0, width: 400, height: 560))
        }
        let next = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 400, height: 560))
            UIColor.yellow.setFill(); context.fill(CGRect(x: 400, y: 0, width: 400, height: 560))
        }
        let transparent = UIGraphicsImageRenderer(size: size, format: format).image { _ in }
        for canvas in [CGSize(width: 640, height: 360), CGSize(width: 360, height: 640)] {
            let rect = DiaryVideoFrameRenderer.bookRect(size: canvas, spreadSize: size)
            #expect(rect.minX > 0 && rect.maxX < canvas.width)
            #expect(rect.minY > 0 && rect.maxY < canvas.height)
            for p in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let sample = DiaryVideoTimeline.Sample(spread: 0, next: 1, turn: p, intro: false, opacity: 1)
                let image = DiaryVideoFrameRenderer.image(size: canvas, title: "", sample: sample, current: current, next: next, rings: transparent)
                if p == 0 {
                    let right = try pixel(image, x: rect.minX + rect.width * 0.75, y: rect.midY)
                    #expect(right[2] > 230 && right[0] < 20)
                }
                if p == 0.75 {
                    let back = try pixel(image, x: rect.minX + rect.width * 0.3, y: rect.midY)
                    #expect(back[1] > 150 && back[0] < 30 && back[2] < 30)
                }
                if p == 1 {
                    let left = try pixel(image, x: rect.minX + rect.width * 0.25, y: rect.midY)
                    #expect(left[1] > 230 && left[0] < 20)
                }
                Attachment.record(Array(try #require(image.pngData())), named: "flip-\(Int(canvas.width))-\(p).png")
            }
        }
    }

    private func fixture(folder: URL) async throws -> (DiaryBook, DiaryDocumentStore, DiaryDocument) {
        let library = DiaryDocumentStore(ownerID: "video-tests", baseDirectory: folder)
        let book = try await library.createBook(title: "旅途/回忆:视频", preset: .square)
        let store = DiaryDocumentStore(ownerID: "video-tests", baseDirectory: folder, bookID: book.id)
        var first = DiaryDocument()
        for (index, color) in [UIColor.red, .green, .yellow].enumerated() {
            var page = DiaryDocument(); page.bookID = book.id
            page.objects[page.rootContentID]?.referenceSize = book.defaultPageSize
            let image = solid(color, bottom: index == 0 ? .blue : nil)
            let (asset, _) = try await store.importImage(try #require(image.pngData()), documentID: page.id)
            page.assets[asset.id] = asset
            page.appendObject(containing: DiaryLayer(name: "page-\(index)", kind: .sticker,
                transform: DiaryTransform(position: .zero, pivot: .zero), size: book.defaultPageSize, assetID: asset.id))
            try await store.save(page)
            if index == 0 { first = page }
        }
        return (try await store.loadBook(), store, first)
    }

    @Test(arguments: DiaryVideoOptions.Frame.allCases)
    func exportsPlayableH264WithCorrectOrientationAndLastFrame(frame: DiaryVideoOptions.Frame) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (snapshot, store, _) = try await fixture(folder: folder)
        let options = DiaryVideoOptions(frame: frame, speed: .quick, firstSpread: 0, lastSpread: 1)
        var stages: [String] = []
        let result = try await DiaryBookVideoExporter.export(book: snapshot, store: store, options: options,
            outputDirectory: folder) { stage, fraction in
                #expect((0...1).contains(fraction)); stages.append(stage)
            }
        #expect(result.spreadCount == 2)
        #expect(result.url.lastPathComponent == "旅途回忆视频-翻页.mp4")
        #expect(!FileManager.default.fileExists(atPath: result.directory.appendingPathComponent("frames").path))
        let asset = AVURLAsset(url: result.url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try #require(tracks.first)
        #expect(try await track.load(.nominalFrameRate) == 30)
        let descriptions = try await track.load(.formatDescriptions)
        #expect(CMFormatDescriptionGetMediaSubType(try #require(descriptions.first)) == kCMVideoCodecType_H264)
        #expect(stages.last == "视频已生成")
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let first = try await generator.image(at: CMTime(seconds: 2, preferredTimescale: 30))
        let last = try await generator.image(at: CMTime(value: Int64(options.timeline.frameCount - 1), timescale: 30))
        let rect = DiaryVideoFrameRenderer.bookRect(size: result.size, spreadSize: CGSize(width: 800, height: 800 * (0.955 * (1 - DiaryBookSpine.halfGapFraction) + 0.09) / 2))
        let top = try pixel(UIImage(cgImage: first.image), x: rect.minX + rect.width * 0.75, y: rect.minY + rect.height * 0.25)
        let bottom = try pixel(UIImage(cgImage: first.image), x: rect.minX + rect.width * 0.75, y: rect.minY + rect.height * 0.75)
        #expect(top[0] > 200 && top[2] < 40)
        #expect(bottom[2] > 200 && bottom[0] < 40)
        let left = try pixel(UIImage(cgImage: last.image), x: rect.minX + rect.width * 0.25, y: rect.midY)
        let right = try pixel(UIImage(cgImage: last.image), x: rect.minX + rect.width * 0.75, y: rect.midY)
        #expect(left[1] > 200 && left[0] < 40)
        #expect(right[0] > 200 && right[1] > 200 && right[2] < 40)
        Attachment.record(Array(try Data(contentsOf: result.url)), named: "diary-\(frame.rawValue).mp4")
    }

    @Test func preparationUsesCapturedRevisionAndRejectsMissingPages() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (snapshot, store, original) = try await fixture(folder: folder)
        var edited = original
        edited.objects[edited.rootContentID]?.layers[0].visible = false
        try await store.save(edited)
        let options = DiaryVideoOptions()
        let prepared = try await DiaryBookVideoExporter.prepare(book: snapshot, store: store, options: options,
            directory: folder.appendingPathComponent("frozen"), width: 800)
        let first = try #require(UIImage(contentsOfFile: prepared.urls[0].path))
        let sample = try pixel(first, x: first.size.width * 0.75, y: first.size.height * 0.25)
        #expect(sample[0] > 230 && sample[2] < 20)
        var missing = snapshot
        missing.pages[0].revisionID = UUID()
        do {
            _ = try await DiaryBookVideoExporter.export(book: missing, store: store, options: options, outputDirectory: folder) { _, _ in }
            Issue.record("Expected missing page failure")
        } catch { #expect(error.localizedDescription.contains("第 1 个跨页")) }
        let remaining = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(!remaining.contains { $0.hasPrefix("DiaryMP4-") })
    }

    @Test func cancellationDuringPreparationAndEncodingRemovesPartialFiles() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (book, store, _) = try await fixture(folder: folder)
        for duringEncoding in [false, true] {
            let task = Task {
                try await DiaryBookVideoExporter.export(book: book, store: store,
                    options: DiaryVideoOptions(lastSpread: 1), outputDirectory: folder) { stage, _ in
                        if duringEncoding ? stage.hasPrefix("正在生成视频") : stage.contains("1/2") {
                            withUnsafeCurrentTask { $0?.cancel() }
                        }
                    }
            }
            do { _ = try await task.value; Issue.record("Expected cancellation") }
            catch { #expect(error is CancellationError) }
            let remaining = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            #expect(!remaining.contains { $0.hasPrefix("DiaryMP4-") })
        }
    }

    @Test func emptyAndInvalidRangesAndCorruptVideoAreRejected() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (book, store, _) = try await fixture(folder: folder)
        for options in [DiaryVideoOptions(firstSpread: -1), DiaryVideoOptions(lastSpread: 100), DiaryVideoOptions(firstSpread: 1, lastSpread: 0)] {
            do {
                _ = try await DiaryBookVideoExporter.export(book: book, store: store, options: options, outputDirectory: folder) { _, _ in }
                Issue.record("Expected range failure")
            } catch { #expect(error is DiaryBookVideoExporter.ExportError) }
        }
        do {
            _ = try await DiaryBookVideoExporter.export(book: DiaryBook(title: "empty"), store: store,
                options: DiaryVideoOptions(), outputDirectory: folder) { _, _ in }
            Issue.record("Expected empty book failure")
        } catch { #expect(error is DiaryBookVideoExporter.ExportError) }
        let bad = folder.appendingPathComponent("corrupt.mp4")
        try Data("not a video".utf8).write(to: bad)
        do {
            try await DiaryBookVideoExporter.validate(url: bad, timeline: DiaryVideoTimeline(spreadCount: 1, hold: 2), size: CGSize(width: 1920, height: 1080))
            Issue.record("Expected validation failure")
        } catch { }
    }
}
