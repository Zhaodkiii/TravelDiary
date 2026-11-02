import Testing
import UIKit
import SwiftUI
@testable import TravelDiary

@Suite(.serialized)
@MainActor struct DiaryCanvasAITests {
    private func fixture() -> (DiaryEditorSession, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var document = DiaryDocument()
        document.objects[document.rootContentID]?.referenceSize = CGSize(width: 1000, height: 800)
        let text = DiaryLayer(name: "标题", kind: .text,
            transform: DiaryTransform(position: CGPoint(x: 100, y: 100), pivot: CGPoint(x: 37, y: 12)),
            size: CGSize(width: 200, height: 50), text: "雨崩", fontSize: 28)
        document.appendObject(containing: text)
        return (DiaryEditorSession(document: document, images: [:], store: DiaryDocumentStore(ownerID: "ai-test", baseDirectory: root)), root)
    }
    private func contentEquivalent(_ lhs: DiaryDocument, _ rhs: DiaryDocument) -> Bool {
        var a = lhs, b = rhs
        for id in a.objects.keys { a.objects[id]?.revision = 1 }
        for id in b.objects.keys { b.objects[id]?.revision = 1 }
        return a == b
    }
    private func plan(_ context: DiaryAIContext, _ operations: [DiaryAIOperation]) -> DiaryAIPlan {
        .init(schemaVersion: 1, contextID: context.id, baseDigest: context.digest, summary: "调整完成", operations: operations)
    }
    @Test func placementDefaultsAngleAndRejectsMissingCenterImmediately() async throws {
        let (session, root) = fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let context = try await DiaryEditorAIBridge(session).capture(.defaults(.relayout))
        let target = try #require(context.objects.first)
        let raw: [String: Any] = ["expectedVersion": 0, "objectID": target.shortID, "width": 200, "center": ["x": 400, "y": 300]]
        let call = DiaryAIToolCall(id: "placement", name: "place_layer", arguments: String(decoding: try JSONSerialization.data(withJSONObject: raw), as: UTF8.self))
        let parsed = try DiaryAIWorkspaceTools.parse(call, version: 0, context: context)
        let operation = try #require(parsed)
        #expect(operation.angle == target.angle)
        var invalid = raw; invalid.removeValue(forKey: "center")
        let bad = DiaryAIToolCall(id: "bad", name: "place_layer", arguments: String(decoding: try JSONSerialization.data(withJSONObject: invalid), as: UTF8.self))
        #expect(throws: (any Error).self) { try DiaryAIWorkspaceTools.parse(bad, version: 0, context: context) }
    }
    @Test func importedPaperStylesGrowAndRemainEditable() throws {
        var paperLayer = DiaryLayer(name: "纸卡测试", kind: .text, transform: DiaryTransform(position: .zero, pivot: .zero), size: CGSize(width: 500, height: 80))
        paperLayer.text = "把日子收藏"; paperLayer.fontSize = 48
        for kind in DiaryTextPaper.Kind.allCases where kind.assetName != nil {
            let assetName = try #require(kind.assetName)
            #expect(UIImage(named: assetName) != nil)
            paperLayer.textAppearance = DiaryTextAppearance(paper: DiaryTextPaper(kind: kind))
            let short = DiaryPageRenderer.textBounds(paperLayer)
            paperLayer.text = "把日子收藏\n一起走过的路\n慢慢写下来"
            let long = DiaryPageRenderer.textBounds(paperLayer)
            #expect(long.height > short.height)
            let decoded = try JSONDecoder().decode(DiaryLayer.self, from: JSONEncoder().encode(paperLayer))
            #expect(decoded.textAppearance?.paper?.kind == kind && decoded.text == paperLayer.text)
            #expect(DiaryPageRenderer.textPreview(decoded).size.height > 0)
            paperLayer.text = "把日子收藏"
        }
    }
    @Test func paperDrawsIntoStandaloneCanvasContext() throws {
        var layer = DiaryLayer(name: "纸卡", kind: .text, transform: DiaryTransform(position: .zero, pivot: .zero), size: CGSize(width: 500, height: 100))
        layer.text = " "; layer.fontSize = 48
        layer.textAppearance = DiaryTextAppearance(paper: DiaryTextPaper(kind: .coralUnderline))
        let context = try #require(CGContext(data: nil, width: 600, height: 300, bitsPerComponent: 8, bytesPerRow: 2400, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // No UIGraphics renderer/current context: mirrors SwiftUI Canvas.
        DiaryPageRenderer.drawText(layer, in: context)
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let opaquePixels = stride(from: 3, to: 2400 * 300, by: 4).filter { bytes[$0] > 0 }.count
        #expect(opaquePixels > 10000)
    }
    @Test func newTextDefaultsCanBeCancelledWithoutChangingExistingText() {
        let (session, root) = fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let fresh = DiaryTextDraft(session: session, layer: nil)
        #expect(fresh.layer.font == DiaryNewTextDefaults.font)
        #expect(fresh.layer.textAppearance?.paper?.kind == .blueTape)
        fresh.selectPaper(DiaryTextPaper.Kind.none)
        #expect(fresh.layer.textAppearance?.paper?.kind == DiaryTextPaper.Kind.none)
        var existing = fresh.layer; existing.font = .system
        let reopened = DiaryTextDraft(session: session, layer: existing)
        #expect(reopened.layer.font == .system)
        #expect(reopened.layer.textAppearance?.paper?.kind == DiaryTextPaper.Kind.none)
    }
    @Test func decoratedTextFitsCanvasWithoutRemovingPaperOrShrinkingFont() async throws {
        let (session, root) = fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bridge = DiaryEditorAIBridge(session)
        let context = try await bridge.capture(.defaults(.writing))
        bridge.layoutRegions = [.init(role: "text", x: 0, y: 0, width: 1000, height: 800)]
        let operation = DiaryAIOperation(operationID: "title", type: "createText", clientObjectKey: "card", center: CGPoint(x: 400, y: 5), text: "山风正好", fontID: "system", fontSize: 48, width: 350, paper: "blueTape")
        _ = try await bridge.propose(plan(context, [operation]))
        try bridge.apply()
        let layer = try #require(session.document.objects.values.flatMap(\.layers).first { $0.text == "山风正好" })
        #expect(layer.fontSize == 48 && layer.textAppearance?.paper?.kind == .blueTape)
        let bounds = DiaryPageRenderer.bounds(layer, document: session.document, siblings: session.scopeLayers).applying(layer.transform.matrix)
        let visibleCard = try #require(bridge.objectChoices.first { $0.text == "山风正好" })
        #expect(visibleCard.bounds.minY >= -0.01)
    }
    @Test func newPaperCardAutomaticallyAvoidsPhotoWithoutChangingContentOrFont() async throws {
        let (session, root) = fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try #require(UIGraphicsImageRenderer(size: CGSize(width: 200, height: 300)).image { c in UIColor.green.setFill(); c.fill(CGRect(x: 0, y: 0, width: 200, height: 300)) }.pngData())
        let (asset, image) = try await session.store.importImage(bytes, documentID: session.document.id)
        var document = session.document; document.objects[session.contentID]?.layers = []; document.assets[asset.id] = asset
        var photo = DiaryLayer.photo(asset: asset, center: CGPoint(x: 500, y: 400)); photo.size = CGSize(width: 200, height: 300); photo.transform.scale = 1
        document.appendObject(containing: photo)
        let editor = DiaryEditorSession(document: document, images: [asset.id: image], store: session.store)
        let bridge = DiaryEditorAIBridge(editor)
        let context = try await bridge.capture(.defaults(.writing))
        let photoBefore = try #require(context.objects.first { $0.role == "photo" })
        let operation = DiaryAIOperation(operationID: "card", type: "createText", clientObjectKey: "caption", center: photoBefore.center, text: "把这一刻留下", fontID: "system", fontSize: 32, width: 260, paper: "blueTape")
        _ = try await bridge.propose(plan(context, [operation])); try bridge.apply()
        let card = try #require(bridge.objectChoices.first { $0.text == "把这一刻留下" })
        #expect(card.bounds.intersection(photoBefore.bounds).isNull)
        #expect(CGRect(origin: .zero, size: context.size).contains(card.bounds))
        #expect(bridge.objectChoices.first { $0.id == photoBefore.id }?.bounds == photoBefore.bounds)
        let text = try #require(editor.document.objects.values.flatMap(\.layers).first { $0.text == "把这一刻留下" })
        #expect(text.fontSize == 32 && text.textAppearance?.paper?.kind == .blueTape)
    }
    @Test func efficientTextCanExtendShortRegionWithoutShrinkingCard() async throws {
        let (session, root) = fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var empty = session.document; empty.objects[session.contentID]?.layers = []
        let editor = DiaryEditorSession(document: empty, images: session.images, store: session.store)
        let bridge = DiaryEditorAIBridge(editor); bridge.autoFitPhotoRegions = true
        let context = try await bridge.capture(.defaults(.writing))
        bridge.layoutRegions = [.init(role: "text", x: 50, y: 30, width: 600, height: 80)]
        let operation = DiaryAIOperation(operationID: "extended", type: "createText", clientObjectKey: "title", center: CGPoint(x: 350, y: 70), text: "山风正好", fontID: "system", fontSize: 48, width: 500, paper: "blueTape")
        _ = try await bridge.propose(plan(context, [operation])); try bridge.apply()
        let object = try #require(bridge.objectChoices.first { $0.text == "山风正好" })
        #expect(object.bounds.height > 80)
        #expect(CGRect(origin: .zero, size: context.size).contains(object.bounds))
    }
    @Test func visualCenterAndSingleUndo() async throws {
        let (session, root) = fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bridge = DiaryEditorAIBridge(session)
        let before = session.document
        let context = try await bridge.capture(.defaults(.relayout))
        let id = try #require(context.objects.first?.id)
        _ = try await bridge.propose(plan(context, [.init(operationID: "move", type: "setPlacement", objectID: id,
            center: CGPoint(x: 450, y: 350), scale: 1.2, angle: 7)]))
        #expect(session.document == before)
        try bridge.apply()
        let layer = try #require(session.document.layer(id))
        let bounds = DiaryPageRenderer.bounds(layer, document: session.document, siblings: session.scopeLayers).applying(layer.transform.matrix)
        #expect(abs(bounds.midX - 450) < 0.001)
        #expect(abs(bounds.midY - 350) < 0.001)
        #expect(session.undoStack.count == 1)
        session.undo(); #expect(contentEquivalent(session.document, before))
        session.redo(); #expect(session.document != before)
        #expect(throws: (any Error).self) { try bridge.apply() }
    }
    @Test func invalidPlanIsAtomicAndVersionConflicts() async throws {
        let (session, root) = fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bridge = DiaryEditorAIBridge(session), before = session.document
        let context = try await bridge.capture(.defaults(.relayout))
        let id = try #require(context.objects.first?.id)
        let good = plan(context, [.init(operationID: "move", type: "setPlacement", objectID: id, center: CGPoint(x: 400, y: 300), scale: 1, angle: 0)])
        _ = try await bridge.propose(good)
        do {
            _ = try await bridge.propose(plan(context, [.init(operationID: "bad", type: "setPlacement", objectID: id, center: CGPoint(x: -900, y: 300), scale: 1, angle: 0)]))
            Issue.record("Accepted out-of-bounds plan")
        } catch {}
        #expect(session.document == before)
        session.toggleLock(id)
        #expect(throws: (any Error).self) { try bridge.apply() }
        #expect(session.document.layer(id)?.locked == true)
    }
    @Test func writingPermissionsAndStableTextRevision() async throws {
        let (session, root) = fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bridge = DiaryEditorAIBridge(session)
        let context = try await bridge.capture(.defaults(.writing))
        let operation = DiaryAIOperation(operationID: "text", type: "createText", clientObjectKey: "caption",
            center: CGPoint(x: 500, y: 500), text: "把山风记住", fontID: "system", fontSize: 30, width: 300, color: "#355A49", paper: "none")
        let first = try await bridge.propose(plan(context, [operation]))
        let second = try await bridge.propose(plan(context, [operation]))
        #expect(second.revision == first.revision + 1)
        try bridge.apply()
        #expect(session.scopeLayers.count == 2)
        let textCount = session.document.objects.values.flatMap(\.layers).filter { $0.kind == .text && $0.text == "把山风记住" }.count
        #expect(textCount == 1)
    }
    @Test func beautifyCannotCreateTextOrRewrite() async throws {
        let (session, root) = fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bridge = DiaryEditorAIBridge(session)
        let context = try await bridge.capture(.defaults(.beautify))
        let id = try #require(context.objects.first?.id)
        do {
            _ = try await bridge.propose(plan(context, [.init(operationID: "rewrite", type: "updateText", objectID: id, text: "新标题")]))
            Issue.record("Unauthorized rewrite accepted")
        } catch {}
        do {
            _ = try await bridge.propose(plan(context, [.init(operationID: "new", type: "createText", clientObjectKey: "new", center: CGPoint(x: 400, y: 400), text: "新文字")]))
            Issue.record("Unauthorized creation accepted")
        } catch {}
    }
    @Test func lockedDescendantCannotBeMoved() async throws {
        let (session, root) = fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let inner = try #require(session.selectedEditingLayer ?? session.document.objects.values.flatMap(\.layers).first { $0.kind == .text })
        session.toggleLock(inner.id)
        let bridge = DiaryEditorAIBridge(session)
        let context = try await bridge.capture(.defaults(.relayout))
        #expect(context.objects.first?.editable == false)
        do {
            _ = try await bridge.propose(plan(context, [.init(operationID: "move", type: "setPlacement", objectID: context.objects[0].id, center: CGPoint(x: 400, y: 400), scale: 1, angle: 0)]))
            Issue.record("Locked descendant moved")
        } catch {}
    }
    @Test func persistedCandidateRestoresAndApplies() async throws {
        let (session, root) = fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bridge = DiaryEditorAIBridge(session)
        let context = try await bridge.capture(.defaults(.writing))
        let draft = try await bridge.propose(plan(context, [.init(operationID: "new", type: "createText", clientObjectKey: "note", center: CGPoint(x: 500, y: 400), text: "一起走过的路", fontID: "system", fontSize: 28, width: 350)]))
        let repository = DiaryAILocalTaskStore(key: "test", root: root)
        let candidate = DiaryAISavedCandidate(archive: draft.archive, preview: draft.preview, original: Data(), summary: draft.summary, warnings: [], revision: 1)
        try await repository.save(.init(forms: [:], candidates: ["writing": candidate], interrupted: false), sequence: 2)
        try await repository.save(.init(forms: [:], candidates: [:], interrupted: false), sequence: 1)
        let saved = try #require(try await repository.load()?.candidates["writing"])
        let restored = DiaryEditorAIBridge(session)
        _ = try restored.restore(saved.archive); try restored.apply()
        #expect(session.scopeLayers.count == 2)
    }
    @Test func responseRejectsIncompleteAndMalformedCalls() throws {
        #expect(throws: (any Error).self) { try DiaryArkResponsesClient.decode(Data(#"{"status":"incomplete","output":[]}"#.utf8)) }
        #expect(throws: (any Error).self) { try DiaryArkResponsesClient.decode(Data(#"{"status":"completed","output":[{"type":"function_call"}]}"#.utf8)) }
        let reply = try DiaryArkResponsesClient.decode(Data(#"{"status":"completed","output":[{"type":"function_call","call_id":"a","name":"inspect_assets","arguments":"{}"}],"usage":{"input_tokens":12,"output_tokens":8}}"#.utf8))
        #expect(reply.calls.count == 1 && reply.inputTokens == 12)
    }
    @Test func rejectsUnknownOperationFields() {
        let payload = #"{"contextID":"00000000-0000-0000-0000-000000000001","plan":{"operations":[{"type":"setPlacement","shell":"bad"}]}}"#
        #expect(throws: (any Error).self) { try DiaryAIDraftController.decodeArguments(payload) }
    }
    @Test func styleNeverExpandsPermissions() {
        var request = DiaryAIRequest.defaults(.beautify); request.style = "复古票根"; request.allowsText = true; request.allowsRewrite = true
        #expect(!request.canCreateText && !request.canRewrite)
        request = .defaults(.writing); request.writingKind = "只换样式"
        #expect(!request.canCreateText && !request.canRewrite && !request.canMove)
    }
    @Test func completeRuntimeReviewsThenApplies() async throws {
        let (session, root) = fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let model = LayoutModel()
        let runtime = DiaryAIDraftController(bridge: DiaryEditorAIBridge(session), model: model,
            repository: DiaryAILocalTaskStore(key: "runtime", root: root))
        runtime.restoreIfNeeded()
        while !runtime.restored { try await Task.sleep(for: .milliseconds(20)) }
        let before = session.document
        runtime.start(.defaults(.writing))
        let deadline = Date().addingTimeInterval(20)
        while runtime.running && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(runtime.error == nil)
        #expect(model.round == 2)
        #expect(runtime.candidates[.writing] != nil)
        #expect(session.document == before)
        #expect(runtime.apply(.writing))
        #expect(session.scopeLayers.count == 2)
        #expect(!runtime.apply(.writing))
        session.undo(); #expect(contentEquivalent(session.document, before))
    }
    @Test func cancellationPreventsLateCandidate() async throws {
        let (session, root) = fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let model = LayoutModel(); model.delayed = true
        let runtime = DiaryAIDraftController(bridge: DiaryEditorAIBridge(session), model: model,
            repository: DiaryAILocalTaskStore(key: "cancel", root: root))
        runtime.start(.defaults(.writing))
        try await Task.sleep(for: .milliseconds(50))
        runtime.cancel()
        try await Task.sleep(for: .milliseconds(200))
        #expect(!runtime.running && runtime.candidates.isEmpty)
        #expect(session.scopeLayers.count == 1)
    }
    @Test func toolCoordinatesUseExplicitXY() throws {
        let id = UUID().uuidString
        let payload = "{\"contextID\":\"\(id)\",\"plan\":{\"schemaVersion\":1,\"contextID\":\"\(id)\",\"baseDigest\":\"abc\",\"summary\":\"test\",\"operations\":[{\"operationID\":\"move\",\"type\":\"setPlacement\",\"center\":{\"x\":120,\"y\":230}}]}}"
        let decoded = try DiaryAIDraftController.decodeArguments(payload)
        #expect(decoded.plan?.operations.first?.center == CGPoint(x: 120, y: 230))
    }
    /// Explicit opt-in; ordinary test runs never send user content or paid network requests.
    @Test func liveModelEndToEndWhenEnabled() async throws {
        guard FileManager.default.fileExists(atPath: "/tmp/traveldiary-ai-live-test-enabled") else { return }
        let (session, root) = fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = session.document
        let runtime = DiaryAIDraftController(bridge: DiaryEditorAIBridge(session), model: DiaryArkResponsesClient(),
            repository: DiaryAILocalTaskStore(key: "live", root: root))
        runtime.restoreIfNeeded()
        while !runtime.restored { try await Task.sleep(for: .milliseconds(30)) }
        var request = DiaryAIRequest.defaults(.writing)
        request.understandsPhotos = false
        request.instruction = "在画布中下方添加一段简短旁注：把山风记住。使用系统字体、字号28、宽度300，中心500,500。不要移动或改变原标题。"
        runtime.start(request)
        let deadline = Date().addingTimeInterval(125)
        while runtime.running && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        print("AI_LIVE_RESULT=\(runtime.error ?? runtime.stage)")
        #expect(runtime.candidates[.writing] != nil)
        #expect(session.document == before)
        #expect(runtime.apply(.writing))
        #expect(session.scopeLayers.count == 2)
        session.undo(); #expect(contentEquivalent(session.document, before))
    }
    @Test func streamDoesNotExposePartialToolArguments() throws {
        var decoder = DiaryAIStreamDecoder()
        _ = try decoder.accept("data: {\"type\":\"response.function_call_arguments.delta\",\"delta\":\"{\"}")
        _ = try decoder.accept("")
        #expect(decoder.completed == nil)
        _ = try decoder.accept("data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output\":[]}}")
        _ = try decoder.accept("")
        let data = try #require(decoder.completed)
        let response = try DiaryArkResponsesClient.decode(data)
        #expect(response.calls.isEmpty)
    }
    @Test func streamCompletesWhenFoundationDropsBlankLines() throws {
        var decoder = DiaryAIStreamDecoder()
        _ = try decoder.acceptNetworkLine("event: response.created")
        _ = try decoder.acceptNetworkLine("data: {\"type\":\"response.created\"}")
        #expect(decoder.completed == nil)
        _ = try decoder.acceptNetworkLine("data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output\":[]}}")
        #expect(decoder.completed != nil)
    }
    @Test func failedStreamIsNeverCompleted() throws {
        var decoder = DiaryAIStreamDecoder()
        _ = try decoder.accept("data: {\"type\":\"response.incomplete\"}")
        #expect(throws: (any Error).self) { try decoder.accept("") }
        #expect(decoder.completed == nil)
    }
    @Test func allStylePreviewsAreBundled() throws {
        for style in DiaryAIStyleLibrary.styles {
            let image = try #require(UIImage(named: style.imageName), "Missing style asset: \(style.imageName)")
            #expect(image.size.width > 0 && image.size.height > 0)
        }
    }
    @Test func nativeSheetSnapshots() async throws {
        let (session, root) = fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let runtime = DiaryAIDraftController(bridge: DiaryEditorAIBridge(session), model: LayoutModel(),
            repository: DiaryAILocalTaskStore(key: "ui", root: root))
        runtime.restoreIfNeeded()
        for (index, action) in DiaryAIAction.allCases.enumerated() {
            let host = UIHostingController(rootView: DiaryAIRequestSheet(controller: runtime, action: action))
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host; window.makeKeyAndVisible()
            host.view.frame = window.bounds; host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
            let renderer = UIGraphicsImageRenderer(size: window.bounds.size)
            let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("diary-ai-sheet-\(index).png")
            try image.pngData()?.write(to: url)
            if let bytes = image.pngData() { Attachment.record(Array(bytes), named: "diary-ai-sheet-\(index).png") }
            print("AI_SNAPSHOT=\(url.path)")
            window.isHidden = true
        }
    }

}

@MainActor private final class LayoutModel: DiaryAIModelClient {
    var round = 0
    var delayed = false
    private var context: DiaryAIContext?
    func respond(prompt: String?, images: [DiaryAIImage], continuation: Data?, results: [DiaryAIToolResult]) async throws -> DiaryAIModelReply {
        if delayed { try? await Task.sleep(for: .milliseconds(150)) }
        round += 1
        if let prompt {
            let marker = "可用字体、图层和精确几何："
            let raw = String(prompt.components(separatedBy: marker).last!.split(separator: "\n").first!)
            context = try JSONDecoder().decode(DiaryAIContext.self, from: Data(raw.utf8))
        }
        let context = try #require(context)
        let call: DiaryAIToolCall
        if round == 1 {
            let operation = DiaryAIOperation(operationID: "text", type: "createText", clientObjectKey: "note", center: CGPoint(x: 500, y: 450), text: "一起走过的路", fontID: "system", fontSize: 28, width: 350)
            let plan = DiaryAIPlan(schemaVersion: 1, contextID: context.id, baseDigest: context.digest, summary: "新增一段旁注", operations: [operation])
            let args = DiaryAIToolArguments(contextID: context.id, plan: plan)
            call = .init(id: "first", name: "propose_layout", arguments: try DiaryAIDraftController.json(args))
        } else {
            #expect(results.first?.images.isEmpty == false)
            call = .init(id: "finish", name: "finish_candidate", arguments: try DiaryAIDraftController.json(DiaryAIToolArguments(contextID: context.id, draftRevision: 1)))
        }
        return .init(calls: [call], text: "", continuation: Data(), inputTokens: 100, outputTokens: 100)
    }
}
