import Testing
import UIKit
@testable import TravelDiary

@Suite(.serialized)
@MainActor struct DiaryAIPerformanceTests {
    @Test func imageWorkRunsOffMainThreadAndBoundsThumbnail() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 1000), format: format).image { c in
            UIColor.orange.setFill(); c.fill(CGRect(x: 0, y: 0, width: 2000, height: 1000))
        }
        let data = try await DiaryAIImageWork.jpeg(image)
        let result = try await DiaryAIImageWork.run { (Thread.isMainThread, DiaryAIImageWork.thumbnail(data)) }
        #expect(!result.0)
        let thumbnail = try #require(result.1.flatMap { UIImage(data: $0) })
        #expect(thumbnail.size == CGSize(width: 480, height: 240))
    }

    @Test func segmentedPreviewMatchesNativeRendererAndAllowsUIWork() async throws {
        var document = DiaryDocument()
        let size = CGSize(width: 320, height: 240)
        document.objects[document.rootContentID]?.referenceSize = size
        for i in 0..<12 {
            var layer = DiaryLayer(name: "Text", kind: .text,
                transform: DiaryTransform(position: CGPoint(x: 10 + (i % 3) * 100, y: 10 + (i / 3) * 50), pivot: .zero),
                size: CGSize(width: 80, height: 40))
            layer.text = "测试 \(i)"; layer.fontSize = 18
            document.appendObject(containing: layer)
        }
        var uiRan = false
        let ui = Task { @MainActor in uiRan = true }
        let preview = try await DiaryPageRenderer.aiPreview(document, contentID: document.rootContentID, images: [:], size: size)
        #expect(uiRan)
        await ui.value
        let context = try #require(CGContext(data: nil, width: 320, height: 240, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(UIColor.systemBackground.cgColor); context.fill(CGRect(origin: .zero, size: size))
        context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        DiaryPageRenderer.draw(document, images: [:], in: context, cacheObjects: false)
        UIGraphicsPopContext()
        let reference = try #require(context.makeImage()?.dataProvider?.data) as Data
        let actual = try #require(preview.cgImage?.dataProvider?.data) as Data
        #expect(actual == reference)
    }

    @Test func cancelledPreviewStopsBeforePublishingAnImage() async throws {
        let document = DiaryDocument()
        let task = Task { @MainActor in
            try await DiaryPageRenderer.aiPreview(document, contentID: document.rootContentID, images: [:], size: document.root.referenceSize)
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled preview returned an image")
        } catch is CancellationError {} catch { throw error }
    }

    @Test func rawLogRecordsKeepOrderAndRedactionThroughFlush() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = DiaryAIProductionLog(owner: "performance", page: UUID(), root: root)
        for i in 0..<1000 {
            let bytes = try JSONSerialization.data(withJSONObject: ["index": i, "Authorization": "private-token",
                "nested": ["api_key": "private-token"], "image": "data:image/png;base64,AQI="])
            log.data("sse", bytes)
        }
        log.record("end", ["done": true])
        try await log.flush()
        let data = try Data(contentsOf: log.directory.appendingPathComponent("events.jsonl"))
        let rows = try data.split(separator: 10).map { try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any]) }
        #expect(rows.count == 1002)
        #expect(rows.compactMap { $0["sequence"] as? Int } == Array(1...1002))
        #expect(!String(decoding: data, as: UTF8.self).contains("private-token"))
        let attachments = try FileManager.default.contentsOfDirectory(at: log.directory.appendingPathComponent("attachments"), includingPropertiesForKeys: nil)
        #expect(attachments.count == 1)
    }
}
