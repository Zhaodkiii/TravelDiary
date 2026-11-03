import Testing
import Combine
import UIKit
import SwiftUI
@testable import TravelDiary

@Suite(.serialized)
@MainActor struct DiaryAIWorkspaceTests {
    private func fixture(count: Int = 3, size: CGSize = CGSize(width: 1000, height: 800)) async throws -> (DiaryEditorSession, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var document = DiaryDocument(); document.objects[document.rootContentID]?.referenceSize = size
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
    @Test func addMaterialsToEmptyStyleCanvasSurvivesResumeAndPublishes() async throws {
        let (session, root) = try await fixture(count: 0)
        defer { try? FileManager.default.removeItem(at: root) }
        let baseline = session.document
        let model = WorkspaceModel()
        let workspace = DiaryAIWorkspace(session: session, model: model, root: root)
        var request = DiaryAIRequest.defaults(.relayout)
        request.design = .init(style: .vintage)
        await workspace.enter(request)
        let data = try #require(UIGraphicsImageRenderer(size: CGSize(width: 100, height: 150)).image { c in
            UIColor.orange.setFill(); c.fill(CGRect(x: 0, y: 0, width: 100, height: 150))
        }.pngData())
        #expect(await workspace.addMaterials([data, data]))
        #expect(await workspace.addMaterials([data], sticker: true, name: "测试贴纸"))
        #expect(workspace.pending.count == 3)
        #expect(workspace.objects.filter { $0.role == "photo" }.count == 2)
        #expect(session.document == baseline)
        #expect(workspace.displaySession?.scopeLayers.isEmpty == true)
        #expect(model.batchSizes.isEmpty)
        await workspace.keepForLater()
        let resumed = DiaryAIWorkspace(session: session, model: model, root: root)
        await resumed.enter(request)
        #expect(resumed.pending.count == 3 && resumed.thumbnails.count == 3)
        model.version = resumed.version
        resumed.processAll(); try await wait(resumed)
        #expect(resumed.error == nil)
        #expect(resumed.pending.isEmpty)
        #expect(resumed.displaySession?.scopeLayers.count == 3)
        #expect(await resumed.save())
        #expect(session.scopeLayers.count == 3)
    }
    @Test func styleArtworkIsBundledAndDeckRenders() throws {
        for style in DiaryAIPageStyle.allCases {
            #expect(UIImage(named: "TravelStyle-" + style.rawValue) != nil)
            var request = DiaryAIRequest.editorDefaults(.relayout)
            request.design = .init(style: style)
            #expect(request.coordinated().background?.style == style.backgroundID)
        }
        let host = UIHostingController(rootView: TravelStyleDeck(selection: .constant(.scenic), open: {}))
        host.view.frame = CGRect(x: 0, y: 0, width: 393, height: 470)
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        try image.pngData()?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("travel-style-deck.png"))
    }
    @Test func emptyCanvasDoesNotStartPaidModelWork() async throws {
        let (session, root) = try await fixture(count: 0); defer { try? FileManager.default.removeItem(at: root) }
        let model = WorkspaceModel()
        let workspace = DiaryAIWorkspace(session: session, model: model, root: root)
        await workspace.enter(.editorDefaults(.relayout)); workspace.processAll(); try await wait(workspace)
        #expect(!workspace.running && model.batchSizes.isEmpty && workspace.version == 0)
        #expect(workspace.error?.contains("没有") == true || workspace.error?.contains("添加") == true)
    }
    @Test func editorRelayoutDefaultsIncludeBackgroundTextAndFrames() {
        let request = DiaryAIRequest.editorDefaults(.relayout)
        #expect(request.background != nil && request.allowsText && request.allowsFrames)
        #expect(!request.allowsCrop)
    }
    @Test func inlineStartDetailsReturnAndSave() async throws {
        let (session, root) = try await fixture(count: 7)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = DiaryAIWorkspace(session: session, model: WorkspaceModel(), root: root)
        await workspace.enter(.defaults(.relayout))
        #expect(workspace.active && workspace.pending.count == 7)
        #expect(workspace.displaySession?.scopeLayers.isEmpty == true)
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let host = UIHostingController(rootView: DiaryAIInlinePanel(workspace: workspace, controller: session.canvasAI))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        var displayedCounts: [Int] = []
        let displaySubscription = workspace.$displaySession.sink { display in
            displayedCounts.append(display?.scopeLayers.count ?? 0)
        }
        defer { displaySubscription.cancel() }
        workspace.configureAndStart(.defaults(.relayout))
        let deadline = Date().addingTimeInterval(15)
        while workspace.version == 0 && workspace.error == nil && Date() < deadline {
            try await Task.sleep(for: .milliseconds(30))
        }
        try await wait(workspace)
        #expect(workspace.error == nil && workspace.pending.isEmpty && workspace.version == 1)
        #expect(displayedCounts.contains(7))
        let details = UIHostingController(rootView: DiaryAIWorkspaceView(workspace: workspace))
        host.present(details, animated: false)
        details.view.layoutIfNeeded()
        #expect(host.presentedViewController === details)
        #expect(!workspace.events.isEmpty)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            host.dismiss(animated: false) { continuation.resume() }
        }
        #expect(host.presentedViewController == nil)
        #expect(workspace.displaySession?.scopeLayers.count == 7)
        #expect(await workspace.save())
        #expect(session.scopeLayers.count == 7 && session.undoStack.count == 1)
    }
    @Test(arguments: [false, true]) func backgroundModesFinishSaveAndUndo(_ parallel: Bool) async throws {
        let (session, root) = try await fixture(count: 7); defer { try? FileManager.default.removeItem(at: root) }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let bytes = try #require(UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 800), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 800))
        }.pngData())
        let provider = BackgroundFake(bytes), album = BackgroundAlbumFake(), model = WorkspaceModel()
        let w = DiaryAIWorkspace(session: session, model: model, root: root, backgroundProvider: provider, albumSaver: album, parallelExecution: parallel)
        var request = DiaryAIRequest.defaults(.relayout); request.background = .init()
        await w.enter(request); w.processAll(); try await wait(w)
        #expect(w.error == nil && w.pending.isEmpty)
        #expect(model.batchSizes == [7] && provider.generations == 1 && album.saves == 1)
        #expect(w.version == 2)
        #expect(w.events.contains { $0.kind == "parallel" } == parallel)
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
        #expect(workspace.version == 2)
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
    @Test func efficientExecutionCommitsLocallyAndKeepsFinalVisualReview() async throws {
        let (session, root) = try await fixture(count: 1); defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(session.scopeLayers.first?.id)
        var decisions = 0
        let model = ScriptedWorkspaceModel { round, prompt, _, _, _ in
            decisions += 1
            if prompt?.contains("上一批已提交") == true { return [try scriptedCall("finish_batch", ["expectedVersion": 1])] }
            return [try scriptedCall("place_layer", ["expectedVersion": 0, "objectID": id.uuidString, "width": 180, "angle": 0, "center": ["x": 400, "y": 300]])]
        }
        let workspace = DiaryAIWorkspace(session: session, model: model, root: root, efficientExecution: true)
        await workspace.enter(.defaults(.relayout)); workspace.processAll(); try await wait(workspace)
        #expect(workspace.error == nil && workspace.pending.isEmpty && workspace.version == 1)
        #expect(decisions == 2)
        #expect(workspace.events.contains { $0.kind == "client" })
        #expect(await workspace.save())
        #expect(session.undoStack.count == 1)
    }
    @Test func nativePhotoFitUsesActualRotatedBounds() async throws {
        let (session, root) = try await fixture(count: 1); defer { try? FileManager.default.removeItem(at: root) }
        let bridge = DiaryEditorAIBridge(session)
        let context = try await bridge.capture(.defaults(.relayout))
        let id = try #require(context.objects.first?.id)
        bridge.autoFitPhotoRegions = true
        let region = DiaryAILayoutRegion(role: "photo", objectID: id.uuidString, x: 200, y: 100, width: 400, height: 500)
        bridge.layoutRegions = [region]
        let before = session.document
        _ = try await bridge.propose(.init(schemaVersion: 1, contextID: context.id, baseDigest: context.digest, summary: "适配区域", operations: [.init(operationID: "fit", type: "setPlacement", objectID: id, center: CGPoint(x: -100, y: -100), scale: 2, angle: 12, width: 900)]))
        #expect(session.document == before)
        try bridge.apply()
        let object = try #require(bridge.objectChoices.first { $0.id == id })
        #expect(region.bounds.insetBy(dx: -0.1, dy: -0.1).contains(object.bounds))
    }
    @Test func localDecorationSeparationAvoidsHeavyOverlap() async throws {
        let (session, root) = try await fixture(count: 1); defer { try? FileManager.default.removeItem(at: root) }
        let asset = try #require(session.document.assets.values.first)
        let a = DiaryLayer(name: "装饰一", kind: .sticker, transform: DiaryTransform(position: .zero, pivot: .zero), size: CGSize(width: 100, height: 150), assetID: asset.id)
        var b = a; b.id = UUID(); b.name = "装饰二"
        var document = session.document; document.objects[session.contentID]?.layers += [a, b]
        let editor = DiaryEditorSession(document: document, images: session.images, store: session.store, contentID: session.contentID)
        let bridge = DiaryEditorAIBridge(editor); bridge.autoFitPhotoRegions = true; bridge.allowedBatchIDs = [a.id, b.id]
        let context = try await bridge.capture(.defaults(.relayout))
        let ops = [a, b].map { DiaryAIOperation(operationID: $0.id.uuidString, type: "setPlacement", objectID: $0.id, center: CGPoint(x: 500, y: 400), scale: 1, angle: 0, width: 150) }
        _ = try await bridge.propose(.init(schemaVersion: 1, contextID: context.id, baseDigest: context.digest, summary: "错开装饰", operations: ops)); try bridge.apply()
        let objects = bridge.objectChoices.filter { [a.id, b.id].contains($0.id) }
        #expect(objects.count == 2)
        #expect(!objects[0].bounds.intersects(objects[1].bounds))
    }
    @Test func ninePhotosSplitIntoEightAndOne() async throws {
        let (session, root) = try await fixture(count: 9); defer { try? FileManager.default.removeItem(at: root) }
        let model = WorkspaceModel()
        let workspace = DiaryAIWorkspace(session: session, model: model, root: root)
        await workspace.enter(.defaults(.relayout)); workspace.processAll(); try await wait(workspace)
        #expect(workspace.error == nil && workspace.pending.isEmpty)
        #expect(model.batchSizes == [8, 1])
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
        #expect(model.batchSizes == [7])
        #expect(workspace.version == 1)
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
    @Test func recoveryRebuildsTextTaskAndAutomaticallyPlacesCard() async throws {
        let (session, root) = try await fixture(count: 1, size: CGSize(width: 4370, height: 3130))
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ScriptedWorkspaceModel { round, prompt, images, continuation, results in
            switch round {
            case 1:
                // Reproduce the snapshot: unavailable tool and string coordinates.
                return [try scriptedCall("place_layer", ["expectedVersion": 0, "width": "1520"]),
                        try scriptedCall("place_layer", ["expectedVersion": 0, "width": "720"])]
            case 2:
                #expect(continuation == nil && results.isEmpty)
                #expect(prompt?.contains("createText") == true && prompt?.contains("山风与经幡") == true)
                #expect(prompt?.contains("fonts") == true && prompt?.contains("4370") == true)
                #expect(prompt?.contains("工具不属于当前阶段") == true)
                #expect(!images.isEmpty)
                return [try scriptedCall("create_text", ["expectedVersion": 0, "clientObjectKey": "title", "text": "山风与经幡", "fontID": "system", "fontSize": 80, "width": 1200, "center": ["x": 2185, "y": 400]])]
            case 3: return [try scriptedCall("commit_batch", ["expectedVersion": 0, "summary": "创建标题"])]
            case 4:
                let error = try #require(results.first?.text)
                #expect(error.contains("提交成功"))
                return [try scriptedCall("finish_batch", ["expectedVersion": 1])]

            default: return [try scriptedCall("finish_batch", ["expectedVersion": 1])]
            }
        }
        let workspace = DiaryAIWorkspace(session: session, model: model, root: root)
        var request = DiaryAIRequest.defaults(.writing); request.instruction = "山风与经幡"
        await workspace.enter(request); workspace.processAll(); try await wait(workspace)
        #expect(workspace.error == nil && workspace.version == 1)
        #expect(await workspace.save())
        let created = session.document.objects.values.flatMap(\.layers).filter { $0.text == "山风与经幡" }
        #expect(created.count == 1)
        #expect(!workspace.events.contains { $0.kind == "tool" && $0.title.contains("rollback_batch") })
    }
    @Test func visualRevisionIsScopedAndStopsAfterTwoRepairs() async throws {
        let (session, root) = try await fixture(count: 1)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(session.scopeLayers.first?.id)
        let model = ScriptedWorkspaceModel { round, prompt, _, _, results in
            if round == 10 {
                #expect(results.first?.text.contains("工具不属于当前阶段") == true)
                return [try scriptedCall("finish_batch", ["expectedVersion": 3])]
            }
            let version = (round - 1) / 3
            switch (round - 1) % 3 {
            case 0:
                if version > 0 { #expect(prompt?.contains("visualRevision") == true && prompt?.contains("遮挡人物") == true) }
                return [try scriptedCall("place_layer", ["expectedVersion": version, "objectID": id.uuidString, "width": 180, "angle": 0, "center": ["x": 200 + version * 100, "y": 300]])]
            case 1: return [try scriptedCall("commit_batch", ["expectedVersion": version, "summary": "摆放照片"])]
            default:
                return [try scriptedCall("request_batch_revision", ["expectedVersion": version + 1, "objectIDs": [id.uuidString], "reason": "小照片遮挡人物，请移动"])]
            }
        }
        let workspace = DiaryAIWorkspace(session: session, model: model, root: root)
        await workspace.enter(.defaults(.relayout)); workspace.processAll(); try await wait(workspace)
        #expect(workspace.error != nil && workspace.version == 3 && workspace.pending.isEmpty)
        #expect(workspace.events.contains { $0.kind == "warning" && $0.title == "仍有视觉问题，需要人工检查" })
        #expect(workspace.events.filter { $0.title == "已安排局部视觉修复" }.count == 2)
        #expect(workspace.objects.first { $0.id == id }?.center.x == 400)
    }
    @Test func failedVisualRepairSurvivesArchiveRestore() async throws {
        let (session, root) = try await fixture(count: 1)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(session.scopeLayers.first?.id)
        let failing = ScriptedWorkspaceModel { round, _, _, _, _ in
            switch round {
            case 1: return [try scriptedCall("place_layer", ["expectedVersion": 0, "objectID": id.uuidString, "width": 180, "angle": 0, "center": ["x": 200, "y": 300]])]
            case 2: return [try scriptedCall("commit_batch", ["expectedVersion": 0, "summary": "摆放照片"])]
            case 3: return [try scriptedCall("request_batch_revision", ["expectedVersion": 1, "objectIDs": [id.uuidString], "reason": "修复人物遮挡"])]
            default: throw DiaryAIError.invalid("模拟请求中断")
            }
        }
        let first = DiaryAIWorkspace(session: session, model: failing, root: root)
        await first.enter(.defaults(.relayout)); first.processAll(); try await wait(first)
        #expect(first.error != nil && first.version == 1)
        await first.keepForLater()
        let resumed = ScriptedWorkspaceModel { round, prompt, _, _, _ in
            switch round {
            case 1:
                #expect(prompt?.contains("修复人物遮挡") == true)
                return [try scriptedCall("place_layer", ["expectedVersion": 1, "objectID": id.uuidString, "width": 180, "angle": 0, "center": ["x": 400, "y": 300]])]
            case 2: return [try scriptedCall("commit_batch", ["expectedVersion": 1, "summary": "完成修复"])]
            default: return [try scriptedCall("finish_batch", ["expectedVersion": 2])]
            }
        }
        let second = DiaryAIWorkspace(session: session, model: resumed, root: root)
        await second.enter(.defaults(.relayout)); second.processAll(); try await wait(second)
        #expect(second.error == nil && second.version == 2)
        #expect(second.objects.first { $0.id == id }?.center.x == 400)
    }
    @Test func interruptedConfirmationRetainsRevisionChoice() async throws {
        let (session, root) = try await fixture(count: 1)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(session.scopeLayers.first?.id)
        let failing = ScriptedWorkspaceModel { round, _, _, _, _ in
            switch round {
            case 1: return [try scriptedCall("place_layer", ["expectedVersion": 0, "objectID": id.uuidString, "width": 180, "angle": 0, "center": ["x": 200, "y": 300]])]
            case 2: return [try scriptedCall("commit_batch", ["expectedVersion": 0, "summary": "摆放照片"])]
            default: throw DiaryAIError.invalid("确认前连接中断")
            }
        }
        let first = DiaryAIWorkspace(session: session, model: failing, root: root)
        await first.enter(.defaults(.relayout)); first.processAll(); try await wait(first)
        #expect(first.version == 1 && first.error != nil)
        await first.keepForLater()
        let model = ScriptedWorkspaceModel { round, prompt, _, _, _ in
            switch round {
            case 1:
                #expect(prompt?.contains("request_batch_revision") == true && prompt?.contains(id.uuidString) == true)
                return [try scriptedCall("request_batch_revision", ["expectedVersion": 1, "objectIDs": [id.uuidString], "reason": "人物被遮挡"])]
            case 2: return [try scriptedCall("place_layer", ["expectedVersion": 1, "objectID": id.uuidString, "width": 180, "angle": 0, "center": ["x": 400, "y": 300]])]
            case 3: return [try scriptedCall("commit_batch", ["expectedVersion": 1, "summary": "完成修复"])]
            default: return [try scriptedCall("finish_batch", ["expectedVersion": 2])]
            }
        }
        let second = DiaryAIWorkspace(session: session, model: model, root: root)
        await second.enter(.defaults(.relayout)); second.processAll(); try await wait(second)
        #expect(second.error == nil && second.version == 2)
        #expect(second.objects.first { $0.id == id }?.center.x == 400)
    }
    @Test func advisoryTextRegionAllowsPhotoAndWarnsBeforeCommit() async throws {
        let (session, root) = try await fixture(count: 1)
        defer { try? FileManager.default.removeItem(at: root) }
        let before = session.document
        let bridge = DiaryEditorAIBridge(session)
        let context = try await bridge.capture(.defaults(.relayout))
        let target = try #require(context.objects.first)
        bridge.layoutRegions = [.init(role: "text", x: 50, y: 50, width: 400, height: 150)]
        let move = DiaryAIOperation(operationID: "move", type: "setPlacement", objectID: target.id, center: CGPoint(x: 250, y: 160), scale: target.scale, angle: 0, width: 180)
        let draft = try await bridge.propose(.init(schemaVersion: 1, contextID: context.id, baseDigest: context.digest, summary: "建议区不是实际文字", operations: [move]))
        #expect(draft.warnings.contains { $0.contains("建议文字区域") })
        #expect(session.document == before)
    }
    @Test func maxHeightFitsFinalRotatedFrameWithoutStretching() async throws {
        let (session, root) = try await fixture(count: 1)
        defer { try? FileManager.default.removeItem(at: root) }
        var request = DiaryAIRequest.defaults(.relayout); request.allowsFrames = true
        let bridge = DiaryEditorAIBridge(session), context = try await bridge.capture(request)
        let target = try #require(context.objects.first)
        let call = try scriptedCall("place_layer", ["expectedVersion": 0, "objectID": target.shortID, "width": 500, "maxHeight": 260, "angle": 12, "center": ["x": 400, "y": 400]])
        let parsed = try DiaryAIWorkspaceTools.parse(call, version: 0, context: context)
        let move = try #require(parsed)
        let frame = DiaryAIOperation(operationID: "frame", type: "setFrameStyle", objectID: target.id, frameStyle: "拍立得")
        _ = try await bridge.propose(.init(schemaVersion: 1, contextID: context.id, baseDigest: context.digest, summary: "限制竖图高度", operations: [move, frame]))
        try bridge.apply()
        let updated = try await DiaryEditorAIBridge(session).capture(request)
        let actual = try #require(updated.objects.first { $0.id == target.id })
        #expect(actual.bounds.width <= 501 && abs(actual.bounds.height - 260) < 1)
        #expect(abs(actual.center.x - 400) < 1 && abs(actual.center.y - 400) < 1)
    }
    @Test func structuredRegionsProtectTextSpace() throws {
        let id = UUID()
        let object = DiaryAIObject(id: id, shortID: "L2", name: "照片", role: "photo", center: .zero, bounds: CGRect(x: 0, y: 0, width: 200, height: 300), scale: 1, angle: 0, locked: false, visible: true, editable: true, assetIDs: [])
        let context = DiaryAIContext(id: UUID(), digest: "x", contentID: UUID(), size: CGSize(width: 1000, height: 800), spineX: 500, objects: [object], fonts: [])
        let photo = DiaryAILayoutRegion(role: "photo", objectID: "L2", x: 30, y: 200, width: 400, height: 550)
        let text = DiaryAILayoutRegion(role: "text", x: 30, y: 30, width: 400, height: 140)
        let regions = try DiaryAIWorkspace.validatedRegions([photo, text], context: context, allowsText: true)
        #expect(regions.first?.objectID == id.uuidString)
        var overlap = text; overlap.y = 220
        #expect(try DiaryAIWorkspace.validatedRegions([photo, overlap], context: context, allowsText: true).count == 2)
        var crossing = photo; crossing.x = 300
        #expect(throws: (any Error).self) { try DiaryAIWorkspace.validatedRegions([crossing], context: context, allowsText: true) }
    }
    @Test func initialRelayoutDoesNotPretendTextFailed() async throws {
        let (session, root) = try await fixture(count: 3)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = DiaryAIWorkspace(session: session, model: WorkspaceModel(), root: root)
        var request = DiaryAIRequest.defaults(.relayout); request.allowsText = true
        await workspace.enter(request)
        #expect(workspace.needsTextCompletion && !workspace.canContinueText)
        await workspace.skipPendingText()
        #expect(workspace.needsTextCompletion && workspace.pending.count == 3)
    }
    @Test func authenticationFailureIsNotMisreportedAsToolIncompatibility() throws {
        let body = Data(#"{"error":{"message":"invalid parameter: AuthHeader"}}"#.utf8)
        let error = DiaryAIServiceError.response(status: 400, code: "AuthN_InvalidParameter", body: body)
        #expect(error.localizedDescription.contains("认证失败"))
        #expect(!error.localizedDescription.contains("工具"))
        #expect(throws: (any Error).self) { try DiaryAITestConfig.validatedKey("  ") }
        #expect(throws: (any Error).self) { try DiaryAITestConfig.validatedKey("Bearer test") }
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
                values.append(try call("place_layer", ["expectedVersion": version, "objectID": item.id.uuidString, "center": ["x": 150 + (index % 4) * 220, "y": 200 + (index / 4) * 300], "width": 180, "angle": 0]))
            }
            if targets.isEmpty {
                values.append(try call("create_text", ["expectedVersion": version, "clientObjectKey": "title", "text": "一起走过的路", "fontID": "system", "fontSize": 30, "width": 300, "center": ["x": 500, "y": 730]]))
            }
            calls = values
        } else if results.contains(where: { $0.text.contains("操作已暂存") }) {
            calls = [try call("commit_batch", ["expectedVersion": version, "summary": "完成本批照片摆放"])]
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
                calls = [try call("create_text", ["expectedVersion": 0, "clientObjectKey": "title", "text": "把山风记住", "fontID": "system", "fontSize": 30, "width": 300, "center": ["x": 500, "y": 650]])]
            case 4: calls = [try call("commit_batch", ["expectedVersion": 0, "summary": "新增标题"])]
            default: calls = [try call("finish_batch", ["expectedVersion": 1])]
            }
        }
        return .init(calls: calls, text: calls.isEmpty ? "好的" : "", continuation: Data(), inputTokens: 100, outputTokens: 100)
    }
}

@MainActor private func scriptedCall(_ name: String, _ arguments: [String: Any]) throws -> DiaryAIToolCall {
    .init(id: UUID().uuidString, name: name, arguments: String(decoding: try JSONSerialization.data(withJSONObject: arguments), as: UTF8.self))
}
@MainActor private final class ScriptedWorkspaceModel: DiaryAIModelClient {
    typealias Response = (Int, String?, [DiaryAIImage], Data?, [DiaryAIToolResult]) throws -> [DiaryAIToolCall]
    private var round = 0
    private let response: Response
    init(_ response: @escaping Response) { self.response = response }
    func respond(prompt: String?, images: [DiaryAIImage], continuation: Data?, results: [DiaryAIToolResult]) async throws -> DiaryAIModelReply {
        let calls: [DiaryAIToolCall]
        if prompt?.contains("只调用 plan_composition") == true {
            calls = [try scriptedCall("plan_composition", ["expectedVersion": 0, "summary": "主照片突出，顶部预留文字区。"])]
        } else {
            round += 1
            calls = try response(round, prompt, images, continuation, results)
        }
        return .init(calls: calls, text: "", continuation: Data([1]), inputTokens: 100, outputTokens: 100)
    }
}
