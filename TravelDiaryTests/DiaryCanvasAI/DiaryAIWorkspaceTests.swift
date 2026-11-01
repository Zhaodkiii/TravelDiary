import Testing
import UIKit
import SwiftUI
@testable import TravelDiary

@Suite(.serialized)
@MainActor struct DiaryAIWorkspaceTests {
    private func fixture(count: Int = 3) async throws -> (DiaryEditorSession, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var document = DiaryDocument(); document.objects[document.rootContentID]?.referenceSize = CGSize(width: 1000, height: 800)
        let store = DiaryDocumentStore(ownerID: "workspace-test", baseDirectory: root)
        let bytes = try #require(UIGraphicsImageRenderer(size: CGSize(width: 100, height: 150)).image { ctx in
            UIColor.systemGreen.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 150))
        }.pngData())
        let (asset, image) = try await store.importImage(bytes, documentID: document.id)
        document.assets[asset.id] = asset
        for i in 0..<count {
            var photo = DiaryLayer.photo(asset: asset, center: CGPoint(x: 200 + 250 * i, y: 300))
            photo.transform.scale = 0.25
            document.appendObject(containing: photo)
        }
        let session = DiaryEditorSession(document: document, images: [asset.id: image], store: store)
        return (session, root)
    }
    private func wait(_ workspace: DiaryAIWorkspace) async throws {
        let deadline = Date().addingTimeInterval(15)
        while workspace.running && Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
    }
    @Test func allBatchesFinishBeforeBackgroundGeneration() async throws {
        let (session, root) = try await fixture(count: 7); defer { try? FileManager.default.removeItem(at: root) }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let bytes = try #require(UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 800), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 800))
        }.pngData())
        let provider = BackgroundFake(bytes), album = BackgroundAlbumFake(), model = WorkspaceModel()
        let w = DiaryAIWorkspace(session: session, model: model, root: root, backgroundProvider: provider, albumSaver: album)
        var request = DiaryAIRequest.defaults(.relayout); request.background = .init()
        await w.enter(request); w.processAll(); try await wait(w)
        #expect(w.error == nil && w.pending.isEmpty)
        #expect(model.batchSizes == [5, 2] && provider.generations == 1 && album.saves == 1)
        #expect(w.version == 3)
        #expect(await w.save())
        #expect(session.scopeLayers.filter { $0.semanticKind == .background }.count == 1)
        #expect(session.undoStack.count == 1)
    }
    @Test func relayoutCreatesTextAfterPhotosBeforeFinishing() async throws {
        let (session, root) = try await fixture(count: 7); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = DiaryAIWorkspace(session: session, model: WorkspaceModel(), root: root)
        var request = DiaryAIRequest.defaults(.relayout); request.allowsText = true
        await workspace.enter(request); workspace.processAll(); try await wait(workspace)
        #expect(workspace.error == nil)
        #expect(!workspace.needsTextCompletion && workspace.pending.isEmpty)
        #expect(workspace.version == 3)
        #expect(await workspace.save())
        #expect(session.document.objects.values.flatMap(\.layers).contains { $0.text == "一起走过的路" })
    }
    @Test func lockedBackgroundBlocksBeforeAnyModelCall() async throws {
        let (session, root) = try await fixture(count: 1); defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(session.scopeLayers.first?.id)
        var lockedDocument = session.document
        lockedDocument.update(id) { $0.semanticKind = .background; $0.locked = true }
        let lockedSession = DiaryEditorSession(document: lockedDocument, images: session.images, store: session.store)
        let model = WorkspaceModel()
        let workspace = DiaryAIWorkspace(session: lockedSession, model: model, root: root)
        var request = DiaryAIRequest.defaults(.relayout); request.background = .init()
        await workspace.enter(request); workspace.processAll(); try await wait(workspace)
        #expect(workspace.error?.contains("背景已锁定") == true)
        #expect(model.batchSizes.isEmpty && workspace.version == 0)
        #expect(!workspace.events.contains { $0.kind == "request" })
    }
    @Test func placementUsesFinalFrameGeometry() async throws {
        let (session, root) = try await fixture(count: 1); defer { try? FileManager.default.removeItem(at: root) }
        var request = DiaryAIRequest.defaults(.relayout); request.allowsFrames = true
        let bridge = DiaryEditorAIBridge(session), context = try await bridge.capture(request)
        let target = try #require(context.objects.first)
        let move = DiaryAIOperation(operationID: "move", type: "setPlacement", objectID: target.id, center: CGPoint(x: 400, y: 400), scale: target.scale, angle: 12, width: 230)
        let frame = DiaryAIOperation(operationID: "frame", type: "setFrameStyle", objectID: target.id, frameStyle: "拍立得")
        _ = try await bridge.propose(.init(schemaVersion: 1, contextID: context.id, baseDigest: context.digest, summary: "换框后定位", operations: [move, frame]))
        try bridge.apply()
        let updated = try await DiaryEditorAIBridge(session).capture(request)
        let actual = try #require(updated.objects.first { $0.id == target.id })
        #expect(abs(actual.center.x - 400) < 1 && abs(actual.center.y - 400) < 1)
        #expect(abs(actual.bounds.width - 230) < 1)
    }
    @Test func dynamicToolScopeNarrowsToOneConfirmationTool() {
        let base: Set<String> = ["place_layer", "commit_batch", "rollback_batch", "finish_batch", "inspect_layers"]
        #expect(DiaryAIWorkspace.toolsForBatchStage(base: base, hasOperations: true, committed: true) == ["finish_batch"])
        #expect(!DiaryAIWorkspace.toolsForBatchStage(base: base, hasOperations: false, committed: false).contains("finish_batch"))
        #expect(!DiaryAIWorkspace.toolsForBatchStage(base: base, hasOperations: true, committed: false).contains("inspect_layers"))
    }
    @Test func batchesPublishAndOneUndoRestoresOriginal() async throws {
        let (session, root) = try await fixture(count: 7); defer { try? FileManager.default.removeItem(at: root) }
        let before = session.document, model = WorkspaceModel()
        let workspace = DiaryAIWorkspace(session: session, model: model, root: root)
        await workspace.enter(.defaults(.relayout))
        #expect(workspace.pending.count == 7)
        #expect(session.document == before)
        workspace.processAll(); try await wait(workspace)
        #expect(workspace.error == nil)
        #expect(workspace.pending.isEmpty)
        #expect(model.batchSizes == [5, 2])
        #expect(workspace.version == 2)
        #expect(session.document == before)
        #expect(workspace.events.contains { $0.kind == "request" && !$0.images.isEmpty })
        #expect(await workspace.save())
        #expect(session.undoStack.count == 1)
        session.undo()
        #expect(session.scopeLayers == before.root.layers)
    }
    @Test func rollbackAndExitDoNotMutateSource() async throws {
        let (session, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = session.document
        let workspace = DiaryAIWorkspace(session: session, model: WorkspaceModel(), root: root)
        await workspace.enter(.defaults(.relayout)); workspace.processAll(); try await wait(workspace)
        await workspace.rollback()
        #expect(workspace.pending.count == 3)
        await workspace.exitRestoringOriginal()
        #expect(session.document == before && !workspace.active)
    }
    @Test func partialSaveRetainsPendingAndRestores() async throws {
        let (session, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = DiaryAIWorkspace(session: session, model: WorkspaceModel(), root: root)
        await workspace.enter(.defaults(.relayout))
        workspace.enqueue([try #require(workspace.pending.first)])
        try await wait(workspace)
        #expect(workspace.pending.count == 2)
        #expect(await workspace.save())
        #expect(session.scopeLayers.filter(\.visible).count == 1)
        let restored = DiaryAIWorkspace(session: session, model: WorkspaceModel(), root: root)
        await restored.enter(.defaults(.relayout))
        #expect(restored.pending.count == 2)
        #expect(restored.events.contains { $0.kind == "restore" })
        await restored.exitRestoringOriginal()
        #expect(session.scopeLayers.count == 3)
    }
    @Test func inputCanvasExcludesAllPendingThenAddsOnlyCompleted() async throws {
        let (session, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bridge = DiaryEditorAIBridge(session)
        let ids = session.scopeLayers.map(\.id)
        bridge.excludedRenderIDs = Set(ids)
        _ = try await bridge.capture(.defaults(.relayout))
        let clean = try await bridge.originalPreview()
        var blank = session.document
        blank.objects[session.contentID]?.layers = []
        let blankSession = DiaryEditorSession(document: blank, images: session.images, store: session.store)
        blankSession.aiTransientSession = true
        let blankBridge = DiaryEditorAIBridge(blankSession)
        _ = try await blankBridge.capture(.defaults(.relayout))
        let expected = try await blankBridge.originalPreview()
        #expect(clean == expected)
        bridge.excludedRenderIDs = Set(ids.dropFirst())
        let onePlaced = try await bridge.originalPreview()
        #expect(onePlaced != clean)
        bridge.excludedRenderIDs = Set(ids)
        let clearedAgain = try await bridge.originalPreview()
        #expect(clearedAgain == clean)
    }
    @Test func shortLayerReferenceResolvesWithoutReturningDocument() throws {
        let id = UUID()
        let object = DiaryAIObject(id: id, shortID: "L2", name: "照片", role: "photo", center: CGPoint(x: 100, y: 100), bounds: CGRect(x: 0, y: 0, width: 200, height: 300), scale: 1, angle: 0, locked: false, visible: true, editable: true, text: nil, assetIDs: [])
        let context = DiaryAIContext(id: UUID(), digest: "x", contentID: UUID(), size: CGSize(width: 1000, height: 800), spineX: nil, objects: [object], fonts: [])
        let arguments = #"{"expectedVersion":3,"objectID":"L2","center":{"x":350,"y":400},"width":400,"angle":-3}"#
        let parsed = try DiaryAIWorkspaceTools.parse(.init(id: "a", name: "place_layer", arguments: arguments), version: 3, context: context)
        let operation = try #require(parsed)
        #expect(operation.objectID == id)
        #expect(operation.scale == 2)
        #expect(operation.center == CGPoint(x: 350, y: 400))
    }
    @Test func toolRejectsStaleVersionAndForeignObject() throws {
        let context = DiaryAIContext(id: UUID(), digest: "x", contentID: UUID(), size: CGSize(width: 1000, height: 800), spineX: nil, objects: [], fonts: [])
        #expect(throws: (any Error).self) {
            try DiaryAIWorkspaceTools.parse(.init(id: "a", name: "place_layer", arguments: "{\"expectedVersion\":2}"), version: 3, context: context)
        }
    }
    @Test func liveWorkspaceWhenExplicitlyEnabled() async throws {
        guard FileManager.default.fileExists(atPath: "/tmp/traveldiary-workspace-live-enabled") else { return }
        let (session, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = DiaryAIWorkspace(session: session, root: root)
        var request = DiaryAIRequest.defaults(.relayout)
        request.instruction = "照片分布在画布左中右，保持大尺寸和留白。只排照片，不新增文字，不修改相框。"
        await workspace.enter(request)
        workspace.enqueue(Array(workspace.pending.prefix(2)))
        let deadline = Date().addingTimeInterval(240)
        while workspace.running && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        let events = try JSONEncoder().encode(workspace.events.map { [$0.kind, $0.title, $0.detail] })
        Attachment.record(Array(events), named: "live-workspace-events.json")
        print("WORKSPACE_LIVE_RESULT=\(workspace.error ?? workspace.stage)")
        #expect(workspace.error == nil)
        #expect(workspace.version == 1)
        #expect(workspace.pending.count == 1)
        if let image = workspace.preview?.pngData() { Attachment.record(Array(image), named: "live-workspace-result.png") }
        await workspace.exitRestoringOriginal()
    }
    @Test func writingRecoversFromEarlyFinishAndPlainText() async throws {
        let (session, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = session.document
        let model = WritingRecoveryModel()
        let workspace = DiaryAIWorkspace(session: session, model: model, root: root)
        await workspace.enter(.defaults(.writing)); workspace.processAll(); try await wait(workspace)
        #expect(workspace.error == nil)
        #expect(workspace.version == 1)
        #expect(workspace.events.contains { $0.kind == "recovery" })
        #expect(await workspace.save())
        #expect(session.scopeLayers.count == before.root.layers.count + 1)
        let created = session.document.objects.values.flatMap(\.layers).filter { $0.kind == .text && $0.text == "把山风记住" }
        #expect(created.count == 1)
    }
    @Test func finishIsOnlyOfferedAfterCommit() {
        let all: Set<String> = ["create_text", "commit_batch", "rollback_batch", "finish_batch", "get_workspace"]
        let initial = DiaryAIWorkspace.toolsForBatchStage(base: all, hasOperations: false, committed: false)
        #expect(initial.contains("create_text") && !initial.contains("finish_batch") && !initial.contains("commit_batch"))
        let staged = DiaryAIWorkspace.toolsForBatchStage(base: all, hasOperations: true, committed: false)
        #expect(staged.contains("commit_batch") && !staged.contains("finish_batch"))
        let committed = DiaryAIWorkspace.toolsForBatchStage(base: all, hasOperations: true, committed: true)
        #expect(committed.contains("finish_batch") && !committed.contains("create_text") && !committed.contains("commit_batch"))
    }
    @Test func workspaceSnapshot() async throws {
        let (session, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = DiaryAIWorkspace(session: session, model: WorkspaceModel(), root: root)
        await workspace.enter(.defaults(.relayout))
        workspace.panelVisible = false
        let host = UIHostingController(rootView: DiaryAIWorkspaceView(workspace: workspace))
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852); window.rootViewController = host; window.makeKeyAndVisible()
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        if let bytes = image.pngData() { Attachment.record(Array(bytes), named: "ai-workspace.png") }
        window.isHidden = true
    }
}

@MainActor private final class WorkspaceModel: DiaryAIModelClient {
    var batchSizes: [Int] = []
    var version = 0
    func respond(prompt: String?, images: [DiaryAIImage], continuation: Data?, results: [DiaryAIToolResult]) async throws -> DiaryAIModelReply {
        func call(_ name: String, _ arguments: [String: Any]) throws -> DiaryAIToolCall {
            .init(id: UUID().uuidString, name: name, arguments: String(decoding: try JSONSerialization.data(withJSONObject: arguments), as: UTF8.self))
        }
        let calls: [DiaryAIToolCall]
        if prompt?.contains("只调用 plan_composition") == true {
            calls = [try call("plan_composition", ["expectedVersion": version, "summary": "左右分区，主照片突出，底部留白。"])]
        } else if let prompt {
            let contextText = String(prompt.components(separatedBy: "页面及每个图层详细数据（只读输入，绝不复述或原样输出）：").last!.split(separator: "\n").first!)
            let context = try JSONDecoder().decode(DiaryAIContext.self, from: Data(contextText.utf8))
            let targets = context.objects.filter(\.editable)
            batchSizes.append(targets.count)
            var values: [DiaryAIToolCall] = []
            for (index, item) in targets.enumerated() {
                values.append(try call("place_layer", ["expectedVersion": version, "objectID": item.id.uuidString, "center": ["x": 200 + (index % 3) * 300, "y": 230 + (index / 3) * 330], "width": 180, "angle": 0]))
            }
            if targets.isEmpty {
                values.append(try call("create_text", ["expectedVersion": version, "clientObjectKey": "title", "text": "一起走过的路", "fontID": "system", "fontSize": 30, "width": 300, "center": ["x": 500, "y": 730]]))
            }
            values.append(try call("commit_batch", ["expectedVersion": version, "summary": "完成本批照片摆放"])); calls = values
            version += 1
        } else { calls = [try call("finish_batch", ["expectedVersion": version])] }
        return .init(calls: calls, text: "", continuation: Data(), inputTokens: 100, outputTokens: 100)
    }
}

@MainActor private final class WritingRecoveryModel: DiaryAIModelClient {
    private var executionRound = 0
    func respond(prompt: String?, images: [DiaryAIImage], continuation: Data?, results: [DiaryAIToolResult]) async throws -> DiaryAIModelReply {
        func call(_ name: String, _ args: [String: Any]) throws -> DiaryAIToolCall {
            .init(id: UUID().uuidString, name: name, arguments: String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self))
        }
        let calls: [DiaryAIToolCall]
        if prompt?.contains("只调用 plan_composition") == true {
            calls = [try call("plan_composition", ["expectedVersion": 0, "summary": "在空白区域加一段手写标题，保留照片。"])]
        } else {
            executionRound += 1
            switch executionRound {
            case 1: calls = [try call("finish_batch", ["expectedVersion": 0])]
            case 2: calls = []
            case 3:
                calls = [try call("create_text", ["expectedVersion": 0, "clientObjectKey": "title", "text": "把山风记住", "fontID": "system", "fontSize": 30, "width": 300, "center": ["x": 500, "y": 650]]),
                         try call("commit_batch", ["expectedVersion": 0, "summary": "新增标题"]),
                         try call("finish_batch", ["expectedVersion": 1])]
            default: calls = [try call("finish_batch", ["expectedVersion": 1])]
            }
        }
        return .init(calls: calls, text: calls.isEmpty ? "好的" : "", continuation: Data(), inputTokens: 100, outputTokens: 100)
    }
}
