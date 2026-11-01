import Testing
import UIKit
import SwiftUI
@testable import TravelDiary

@Suite(.serialized)
@MainActor struct DiaryAIBackgroundTests {
    private func image(_ size: CGSize = CGSize(width: 1000, height: 800)) throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return try #require(UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(white: 0.97, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }.pngData())
    }
    private func fixture() async throws -> (DiaryEditorSession, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var document = DiaryDocument(); document.objects[document.rootContentID]?.referenceSize = CGSize(width: 1000, height: 800)
        let store = DiaryDocumentStore(ownerID: "background-tests", baseDirectory: root)
        let (asset, decoded) = try await store.importImage(image(CGSize(width: 100, height: 150)), documentID: document.id)
        document.assets[asset.id] = asset
        document.appendObject(containing: .photo(asset: asset, center: CGPoint(x: 350, y: 350)))
        return (DiaryEditorSession(document: document, images: [asset.id: decoded], store: store), root)
    }
    private func request() -> DiaryAIRequest {
        var r = DiaryAIRequest.defaults(.custom); r.selectedOnly = false
        r.background = .init(backgroundOnly: true); return r
    }
    private func wait(_ w: DiaryAIWorkspace) async throws {
        let end = Date().addingTimeInterval(20)
        while w.running && Date() < end { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!w.running)
    }
    @Test func liveBook8Background() async throws {
        guard FileManager.default.fileExists(atPath: "/tmp/traveldiary-background-live-enabled") else { return }
        let output = URL(fileURLWithPath: "/tmp/TravelDiaryBook8Validation/background")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let parent = output.deletingLastPathComponent()
        let input = try #require(FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("已排版项目-") })
        let root = output.appendingPathComponent("sandbox-" + UUID().uuidString)
        let owner = "background-live"
        let book = try await DiaryDocumentStore(ownerID: owner, baseDirectory: root).debugImportBook(from: input)
        let page = try #require(book.pages.first { $0.id.uuidString == "E7377B9C-4F4B-4943-B1F4-460568CB6748" })
        let store = DiaryDocumentStore(ownerID: owner, baseDirectory: root, bookID: book.id)
        let loaded = try await store.load(page.id)
        let session = DiaryEditorSession(document: loaded.document, images: loaded.images, store: store)
        let before = session.document
        let w = DiaryAIWorkspace(session: session, root: root)
        var r = request(); r.scene = "山野徒步"; r.location = "雨崩"
        await w.enter(r); w.processAll()
        let deadline = Date().addingTimeInterval(650)
        var count = 0
        while w.running && Date() < deadline {
            if w.events.count != count {
                count = w.events.count
                if let e = w.events.last { print("BACKGROUND_LIVE \(e.title) \(e.detail.prefix(200))") }
                try JSONEncoder().encode(w.events).write(to: output.appendingPathComponent("events.json"), options: .atomic)
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        try JSONEncoder().encode(w.events).write(to: output.appendingPathComponent("events.json"), options: .atomic)
        if let png = w.backgroundPreview?.pngData() { try png.write(to: output.appendingPathComponent("background.png")) }
        if let jpg = w.preview?.jpegData(compressionQuality: 0.9) { try jpg.write(to: output.appendingPathComponent("composed.jpg")) }
        print("BACKGROUND_LIVE_RESULT \(w.error ?? w.stage)")
        #expect(!w.running && w.backgroundRecord?.layerID != nil)
        guard w.backgroundRecord?.layerID != nil else { return }
        #expect(w.backgroundRecord?.albumState == "saved")
        #expect(await w.save())
        let reopened = try await store.load(page.id)
        let exported = output.appendingPathComponent("背景生成项目-" + UUID().uuidString)
        try await store.exportSourceFiles(try await store.loadBook(), to: exported)
        print("BACKGROUND_EXPORT \(exported.path)")
        #expect(reopened.document.root.layers.first?.semanticKind == .background)
        for layer in before.root.layers where layer.semanticKind != .background && layer.isLibraryBackground != true {
            #expect(reopened.document.layer(layer.id) == layer)
        }
        session.undo()
        #expect(session.scopeLayers == before.root.layers)
    }
    @Test func backgroundSettingsSnapshot() async throws {
        let (session, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let runtime = session.canvasAI
        runtime.restoreIfNeeded()
        let end = Date().addingTimeInterval(5)
        while !runtime.restored && Date() < end { try await Task.sleep(for: .milliseconds(10)) }
        var form = DiaryAIRequest.defaults(.relayout); form.background = .init()
        runtime.setForm(form)
        let host = UIHostingController(rootView: DiaryAIRequestSheet(controller: runtime, action: .relayout))
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
        host.view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(200))
        let data = try #require(UIGraphicsImageRenderer(size: window.bounds.size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }.pngData())
        try data.write(to: URL(fileURLWithPath: "/tmp/diary-background-settings.png"))
        Attachment.record(Array(data), named: "background-settings.png"); window.isHidden = true
    }
    @Test func productionLogExportsImagesAndRedactsCredentials() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = DiaryAIProductionLog(owner: "test", page: UUID(), root: root)
        log.record("request", ["Authorization": "Bearer secret", "prompt": "测试", "image": "data:image/png;base64,AQI="])
        for i in 0..<4000 { log.record("sse", ["delta": "a", "index": i]) }
        let archive = try await log.export()
        let combined = try String(contentsOf: log.directory.appendingPathComponent("events.jsonl"), encoding: .utf8)
        #expect(!combined.contains("Bearer secret") && combined.contains("attachments"))
        let rows = combined.split(separator: "\n")
        #expect(rows.count == 4002)
        let files = try FileManager.default.contentsOfDirectory(at: log.directory, includingPropertiesForKeys: nil)
        #expect(files.count == 2)
        #expect(FileManager.default.fileExists(atPath: log.directory.appendingPathComponent("attachments").path))
        #expect((try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0)
    }
    @Test func activityGroupsPreserveRequestsErrorsAndBatchBoundaries() {
        let values: [DiaryAIWorkspaceEvent] = [
            .init(kind: "checkpoint", title: "恢复点", detail: ""),
            .init(kind: "phase", title: "整体构图规划", detail: ""),
            .init(kind: "request", title: "发送", detail: ""),
            .init(kind: "transport", title: "连接", detail: ""),
            .init(kind: "phase", title: "第 1 批 · L2、L3", detail: ""),
            .init(kind: "request", title: "发送", detail: ""),
            .init(kind: "tool", title: "移动", detail: ""),
            .init(kind: "error", title: "移动失败", detail: "版本错误"),
            .init(kind: "result", title: "L2 · 摆放", detail: "暂存"),
            .init(kind: "batch", title: "本批完成", detail: "")
        ]
        let groups = DiaryAIActivityGroup.build(values)
        #expect(groups.count == 3)
        #expect(groups.flatMap(\.events).map(\.id) == values.map(\.id))
        #expect(groups.reduce(0) { $0 + $1.requests } == 2)
        #expect(groups.last?.summaries.contains { $0.kind == "error" } == true)
        #expect(groups.last?.summaries.contains { $0.kind == "tool" } == false)
        #expect(DiaryAIActivityGroup.build([]).isEmpty)
    }
    @Test func boundVersionRejectsStaleValuesAndSuppliesMissingVersion() throws {
        let call = DiaryAIToolCall(id: "a", name: "finish_batch", arguments: "{}")
        let bound = try DiaryArkResponsesClient.bindVersion(call, version: 5)
        let raw = try #require(JSONSerialization.jsonObject(with: Data(bound.arguments.utf8)) as? [String: Any])
        #expect(raw["expectedVersion"] as? Int == 5)
        #expect(throws: (any Error).self) { try DiaryArkResponsesClient.bindVersion(.init(id: "b", name: "finish_batch", arguments: "{\"expectedVersion\":4}"), version: 5) }
    }
    @Test func backgroundAnalysisExplainsTruncation() {
        #expect(throws: (any Error).self) { try DiarySeedreamBackgroundProvider.requireComplete(["status": "incomplete", "incomplete_details": ["reason": "length"]]) }
    }
    @Test func backgroundRequiresTextCompletionOrExplicitSkip() async throws {
        let (session, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let provider = BackgroundFake(try image()), album = BackgroundAlbumFake()
        let w = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
        var r = DiaryAIRequest.defaults(.relayout); r.allowsText = true; r.selectedOnly = false
        r.background = .init()
        await w.enter(r)
        #expect(w.needsTextCompletion && !w.canGenerateBackground)
        w.generateBackground()
        #expect(provider.generations == 0)
        await w.skipPendingText()
        #expect(!w.needsTextCompletion)
        await w.keepForLater()
        let restored = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
        await restored.enter(r)
        #expect(!restored.needsTextCompletion)
    }
    @Test func promptRepairKeepsThemeAndDoesNotEraseSubjectInstructions() throws {
        let source = "左上区域在照片后方延展淡黄色与淡粉色的小色块与细黑线条。右侧中部照片群之后，用细黑线勾一条柔和的屋檐轮廓。"
        #expect(try DiarySeedreamBackgroundProvider.preparePrompt("浅米色从左侧照片群下方向右延伸") == "浅米色从左侧预留区域下方向右延伸")
        let fixed = try DiarySeedreamBackgroundProvider.preparePrompt(source)
        #expect(!fixed.contains("照片"))
        #expect(fixed.contains("左上区域") && fixed.contains("淡黄色") && fixed.contains("屋檐"))
        #expect(try DiarySeedreamBackgroundProvider.preparePrompt(fixed) == fixed)
        #expect(throws: (any Error).self) { try DiarySeedreamBackgroundProvider.preparePrompt("绘制三张照片和人物") }
    }
    @Test func restoreAppliesNewBackgroundSettingsAndPreservesProgress() async throws {
        let (session, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let provider = BackgroundFake(try image()), album = BackgroundAlbumFake()
        let first = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
        var r = DiaryAIRequest.defaults(.relayout)
        await first.enter(r)
        let pending = first.pending
        await first.keepForLater()
        r.background = .init(style: "doodle")
        let second = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
        await second.enter(r)
        #expect(second.active && second.hasBackgroundRequest)
        #expect(second.pending == pending && second.version == first.version)
        #expect(second.events.contains { $0.title == "已将新设置应用到恢复任务" })
        #expect(provider.generations == 0)
        await second.keepForLater()
        let third = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
        await third.enter(r)
        #expect(third.hasBackgroundRequest && third.pending == pending)
    }
    @Test func exactRatioAndNoStretch() throws {
        #expect(try DiaryAIBackgroundImaging.exactSize(CGSize(width: 4370, height: 3130)) == CGSize(width: 1311, height: 939))
        #expect(try DiaryAIBackgroundImaging.exactSize(CGSize(width: 2003, height: 1009)) == CGSize(width: 2003, height: 1009))
        #expect(throws: (any Error).self) { try DiaryAIBackgroundImaging.exactSize(CGSize(width: CGFloat.nan, height: 1)) }
        #expect(throws: (any Error).self) { try DiaryAIBackgroundImaging.prepare(image(CGSize(width: 500, height: 500)), canvas: CGSize(width: 4370, height: 3130)) }
        let bytes = try DiaryAIBackgroundImaging.prepare(image(CGSize(width: 1400, height: 1000)), canvas: CGSize(width: 4370, height: 3130))
        let cg = try #require(UIImage(data: bytes)?.cgImage)
        #expect(cg.width * 3130 == cg.height * 4370)
    }
    @Test func requestContractAndBackwardDecoding() throws {
        let body = DiarySeedreamBackgroundProvider.body(reference: Data([1,2]), prompt: "背景")
        #expect(body["model"] as? String == "doubao-seedream-5-0-flash-260915")
        #expect(body["watermark"] as? Bool == true)
        #expect(body["stream"] as? Bool == false)
        #expect(body["image"] as? String == "data:image/jpeg;base64,AQI=")
        var old = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request())) as? [String: Any])
        old.removeValue(forKey: "background")
        #expect(try JSONDecoder().decode(DiaryAIRequest.self, from: JSONSerialization.data(withJSONObject: old)).background == nil)
    }
    @Test func backgroundSaveReopenAndUndoPreserveForeground() async throws {
        let (session, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = session.document, provider = BackgroundFake(try image()), album = BackgroundAlbumFake()
        let workspace = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
        await workspace.enter(request()); workspace.processAll(); try await wait(workspace)
        #expect(workspace.error == nil)
        #expect(provider.generations == 1 && provider.downloads == 1 && provider.validations == 1 && album.saves == 1)
        #expect(session.document == before)
        workspace.processAll(); try await wait(workspace)
        #expect(provider.generations == 1 && album.saves == 1)
        #expect(await workspace.save())
        let reloaded = try await session.store.load(session.document.id)
        #expect(reloaded.document.root.layers.first?.semanticKind == .background)
        for layer in before.root.layers { #expect(reloaded.document.layer(layer.id) == layer) }
        #expect(session.undoStack.count == 1)
        session.undo(); #expect(session.scopeLayers == before.root.layers)
    }
    @Test func downloadAndAlbumRetryNeverRegenerate() async throws {
        let (session, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let provider = BackgroundFake(try image()), album = BackgroundAlbumFake(); provider.failDownload = true; album.fails = true
        let w = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
        await w.enter(request()); w.processAll(); try await wait(w)
        #expect(w.error != nil && provider.generations == 1)
        w.generateBackground(); try await wait(w)
        #expect(w.backgroundRecord?.layerID != nil && w.canRetryAlbum)
        #expect(provider.generations == 1 && provider.downloads == 2)
        album.fails = false; w.retryBackgroundAlbum(); try await wait(w)
        #expect(w.backgroundRecord?.albumState == "saved" && provider.generations == 1)
    }
    @Test func failedQualityCanResumeWithoutNewImageRequest() async throws {
        let (session, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let provider = BackgroundFake(try image()), album = BackgroundAlbumFake(); provider.failQuality = true
        let w = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
        await w.enter(request()); w.processAll(); try await wait(w)
        #expect(w.backgroundRecord?.layerID == nil && album.saves == 0)
        await w.keepForLater()
        let resumed = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
        await resumed.enter(request()); provider.failQuality = false
        resumed.generateBackground(); try await wait(resumed)
        #expect(resumed.error == nil && provider.generations == 1 && provider.downloads == 1)
        await resumed.rollback()
        #expect(resumed.backgroundRecord == nil)
    }
    @Test func cancellationCannotApplyLateGeneration() async throws {
        let (session, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = session.document, provider = BackgroundFake(try image()), album = BackgroundAlbumFake(); provider.delay = true
        let w = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
        await w.enter(request()); w.processAll()
        while provider.generations == 0 { try await Task.sleep(for: .milliseconds(10)) }
        w.pause(); try await Task.sleep(for: .milliseconds(250))
        #expect(w.backgroundRecord?.layerID == nil && album.saves == 0 && session.document == before)
    }
}

@MainActor final class BackgroundFake: DiaryAIBackgroundProvider {
    var data: Data; var generations = 0; var downloads = 0; var validations = 0
    var failDownload = false; var failQuality = false; var delay = false
    init(_ data: Data) { self.data = data }
    func generate(reference: Data, prompt: String) async throws -> URL {
        generations += 1
        if delay { try? await Task.sleep(for: .milliseconds(200)) }
        return URL(string: "https://example.com/background.png")!
    }
    func download(_ url: URL) async throws -> Data {
        downloads += 1
        if failDownload { failDownload = false; throw URLError(.networkConnectionLost) }
        return data
    }
    func validate(reference: Data, background: Data) async throws {
        validations += 1
        if failQuality { throw DiaryAIError.invalid("重复照片") }
    }
}
@MainActor final class BackgroundAlbumFake: DiaryAIBackgroundAlbumSaving {
    var saves = 0; var fails = false
    func save(_ data: Data) async throws { saves += 1; if fails { throw DiaryAIError.invalid("没有相册权限") } }
}
