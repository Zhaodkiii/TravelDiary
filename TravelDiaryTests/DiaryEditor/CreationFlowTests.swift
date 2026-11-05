import Testing
import UIKit
import SwiftUI
@testable import TravelDiary

@Suite(.serialized)
@MainActor struct CreationFlowTests {
    private func bytes(_ index: Int = 0) throws -> Data {
        try #require(UIGraphicsImageRenderer(size: CGSize(width: 90 + index, height: 120)).image { ctx in
            UIColor.systemBlue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 90 + index, height: 120))
        }.pngData())
    }
    @Test func emptyStyleEntryReusesDocumentWithoutPublishingBlankPage() async throws {
        let owner = "style-empty-" + UUID().uuidString
        let coordinator = CreationCoordinator(owner: owner)
        coordinator.draft.styleEntry = true
        coordinator.draft.stickerMode = "不使用"
        let first = try #require(await coordinator.prepare(allowEmpty: true))
        let id = first.document.id
        try await first.creationPublish?()
        #expect(try await DiaryDocumentStore(ownerID: owner).listBooks().isEmpty)
        let drafts = try await CreationDraftStore(owner: owner).list()
        let saved = try #require(drafts.first { $0.styleEntry == true })
        let next = CreationCoordinator(owner: owner, draft: saved)
        let second = try #require(await next.prepare(allowEmpty: true))
        #expect(second.document.id == id)
        #expect(second.document.root.layers.isEmpty)
        #expect(try await DiaryDocumentStore(ownerID: owner).listBooks().isEmpty)
    }
    @Test(arguments: [false, true])
    func styleExitDiscardsOnlyEmptyDrafts(_ wroteStory: Bool) async throws {
        let owner = UUID().uuidString
        let coordinator = CreationCoordinator(owner: owner)
        coordinator.draft.styleEntry = true
        let session = try #require(await coordinator.prepare(allowEmpty: true))
        var request = coordinator.draft.request()
        if wroteStory {
            var brief = CreationBrief()
            brief.story = "在山脚等到了日出"
            request.creationBrief = brief
        }
        session.canvasAI.setForm(request)
        await session.aiWorkspace.enter(request)
        let discarded = try await coordinator.discardIfEmpty(session)
        #expect(discarded == !wroteStory)
        #expect(try await DiaryDocumentStore(ownerID: owner).listBooks().isEmpty)
        if wroteStory {
            #expect(try await coordinator.store.load(coordinator.draft.id).brief.story == "在山脚等到了日出")
        } else {
            #expect(try await coordinator.store.list().isEmpty)
        }
    }

    @Test func publishedStylePageIsReadableBeforeCloseAndPreparationCanRetry() async throws {
        let owner = UUID().uuidString
        let coordinator = CreationCoordinator(owner: owner)
        await coordinator.add(try bytes(), name: "旅行照片")
        let session = try #require(await coordinator.prepare(allowEmpty: true))
        var preparedPage: UUID?
        let first = await session.commitToParent {
            throw DiaryAIError.invalid("模拟阅读器准备失败")
        }
        #expect(!first)
        let retry = await session.commitToParent {
            let id = try #require(coordinator.draft.targetBookID)
            let store = DiaryDocumentStore(ownerID: owner, bookID: id)
            let book = try await store.loadBook()
            let matches = book.contentPages.filter { $0.id == session.document.id }
            #expect(matches.count == 1)
            let page = try #require(matches.first)
            _ = try await DiaryPreviewService.image(page: page, store: store, large: true)
            preparedPage = page.id
        }
        #expect(retry)
        #expect(preparedPage == coordinator.draft.documentID)
    }

    @Test func newPageDeletesOldWorkspaceWithoutRecreatingItOnSave() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = StoragePaths(support: root, caches: root.appendingPathComponent("Cache"), temporary: root.appendingPathComponent("Temp"))
        let store = CreationDraftStore(owner: "new-page-test", paths: paths)
        let previous = CreationCoordinator(owner: "new-page-test", store: store)
        previous.draft.styleEntry = true
        await previous.add(try bytes(), name: "旧照片")
        let oldSession = try #require(await previous.prepare(allowEmpty: true))
        await oldSession.aiWorkspace.enter(previous.draft.request())
        let oldDirectory = store.directory(previous.draft.id)
        #expect(StorageActivity.shared.isInUse(oldDirectory))
        try await previous.discardForNewPage()
        #expect(!FileManager.default.fileExists(atPath: oldDirectory.path))
        try await oldSession.save()
        #expect(!FileManager.default.fileExists(atPath: oldDirectory.path))
        let next = CreationCoordinator(owner: "new-page-test", store: store)
        let newSession = try #require(await next.prepare(allowEmpty: true))
        #expect(newSession.document.id != oldSession.document.id)
        #expect(newSession.document.root.layers.isEmpty)
        #expect(next.draft.assets.isEmpty)
    }

    @Test func durableDraftRetainsOriginalNotesAndAccountScope() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = StoragePaths(support: root, caches: root.appendingPathComponent("Cache"), temporary: root.appendingPathComponent("Temp"))
        let store = CreationDraftStore(owner: "creation-test", paths: paths)
        let original = try bytes()
        var draft = try await store.add(original, to: CreationDraft(owner: "creation-test"), name: "照片")
        draft.assets[0].note = "返程时拍的"; draft.brief.location = "黄山"; draft.heroID = draft.assets[0].id
        try await store.save(draft)
        let loaded = try await store.load(draft.id)
        #expect(loaded == draft)
        #expect(try await store.data(loaded.assets[0], draftID: draft.id) == original)
        #expect(try await CreationDraftStore(owner: "another-account", paths: paths).list().isEmpty)
        do { _ = try await store.add(original, to: draft, name: "重复"); Issue.record("duplicate must be rejected") } catch {}
        let removed = try await store.removeAsset(draft.assets[0].id, from: draft)
        #expect(removed.assets.isEmpty && removed.heroID == nil)
    }
    @Test func storyReachesToolsAndPrivateLocationIsRejected() throws {
        var draft = CreationDraft(owner: "test")
        let asset = CreationAsset(filename: "a.image", digest: "a", name: "照片", note: "返程")
        let object = UUID(); draft.assets = [asset]; draft.mapping[asset.id] = object; draft.heroID = asset.id
        draft.brief.location = "黄山"; draft.brief.relationships = "妈妈"; draft.brief.story = "一起看日落"
        let request = draft.request()
        #expect(request.heroID == object && request.creationNotes?[object.uuidString] == "返程")
        #expect(try DiaryAIWorkspace.executionPermissions(request).contains("一起看日落"))
        try DiaryAIWorkspaceTools.validateTextEvidence(["text": "和妈妈一起"], request: request)
        do { try DiaryAIWorkspaceTools.validateTextEvidence(["text": "黄山之旅"], request: request); Issue.record("private location must not be printed") } catch {}
    }
    @Test func photoCountsAndQuotePermissionsPreflight() {
        var draft = CreationDraft(owner: "test")
        #expect(draft.preflightError != nil)
        draft.assets = (0..<16).map { .init(filename: "\($0)", digest: "\($0)", name: "照片") }
        #expect(draft.preflightError == nil)
        draft.assets.append(.init(filename: "17", digest: "17", name: "照片"))
        #expect(draft.preflightError != nil)
        draft.assets[16].included = false; draft.brief.exactQuote = "原话"; draft.writing = false
        #expect(draft.preflightError != nil)
    }
    @Test func interruptedHandoffRestoresStableObjectsWithoutDuplicating() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = StoragePaths(support: root, caches: root.appendingPathComponent("Cache"), temporary: root.appendingPathComponent("Temp"))
        let store = CreationDraftStore(owner: "handoff-test", paths: paths)
        let coordinator = CreationCoordinator(owner: "handoff-test", store: store)
        coordinator.draft.stickerMode = "不加贴纸"
        for index in 0..<3 { await coordinator.add(try bytes(index), name: "照片") }
        let first = try #require(await coordinator.prepare())
        #expect(first.scopeLayers.count == 3)
        #expect(coordinator.draft.mapping.count == 3)
        #expect(try await coordinator.claimLaunch())
        #expect(try await coordinator.claimLaunch() == false)
        let resumed = CreationCoordinator(owner: "handoff-test", draft: try await store.load(coordinator.draft.id), store: store)
        let second = try #require(await resumed.prepare())
        #expect(second.scopeLayers.map(\.id) == first.scopeLayers.map(\.id))
        #expect(Set(second.document.assets.keys) == Set(first.document.assets.keys))
        #expect(second.document.creation?.assetObjects.count == 3)
        #expect(try await resumed.claimLaunch() == false)
        #expect(try await DiaryDocumentStore(ownerID: "handoff-test", baseDirectory: root).listBooks().isEmpty)
    }
    @Test func disablingEntranceRevealsExistingAndNewAIObjects() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DiaryDocumentStore(ownerID: "entrance-test", baseDirectory: root)
        let session = DiaryEditorSession(document: DiaryDocument(), images: [:], store: store)
        #expect(await session.importPhotos([try bytes()]))
        let surface = DiaryCanvasSurface(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        surface.session = session; surface.stagesEntrance = true
        surface.refresh(force: true)
        try await Task.sleep(for: .milliseconds(300))
        func objectLayers() -> [CALayer] {
            func all(_ layer: CALayer) -> [CALayer] { [layer] + (layer.sublayers ?? []).flatMap(all) }
            return all(surface.layer).filter { $0.name.flatMap(UUID.init(uuidString:)) != nil }
        }
        #expect(!objectLayers().isEmpty)
        #expect(objectLayers().allSatisfy { $0.opacity == 0 })
        surface.stagesEntrance = false
        surface.refresh(force: true)
        try await Task.sleep(for: .milliseconds(300))
        #expect(objectLayers().allSatisfy { $0.opacity > 0 && !$0.isHidden })
        #expect(await session.importPhotos([try bytes(1)]))
        surface.refresh(force: true)
        try await Task.sleep(for: .milliseconds(300))
        #expect(objectLayers().count == 2)
        #expect(objectLayers().allSatisfy { $0.opacity > 0 && !$0.isHidden })
    }
    @Test func provenanceSurvivesNativeEncoding() throws {
        var document = DiaryDocument()
        document.creation = .init(draftID: UUID(), brief: .init(), design: .init(), assetObjects: [:], photoNotes: [:])
        let restored = try JSONDecoder().decode(DiaryDocument.self, from: JSONEncoder().encode(document))
        #expect(restored == document)
    }
    @Test(arguments: Array(0..<6)) func liveCreationScenesWhenEnabled(_ index: Int) async throws {
        let marker = URL(fileURLWithPath: "/tmp/creation-live-enabled")
        guard let enabled = try? String(contentsOf: marker, encoding: .utf8), enabled.trimmingCharacters(in: .whitespacesAndNewlines) == "all" || enabled.trimmingCharacters(in: .whitespacesAndNewlines) == String(index) else { return }
        let names = ["archive-city", "archive-family", "archive-food", "archive-nature", "archive-portrait", "archive-mixed"]
        let themes = ["城市漫游", "日常片刻", "聚餐", "山野旅行", "合影纪念", "旅途片刻"]
        let stories = ["记录城市里不同的光线和街角，不编造具体城市。", "把照片里的小表情留下，不推断人物亲属关系。", "记录桌上的食物与相聚的感觉，不编造生日或纪念日。", "以山野、湖泊和树林为主题，照片来自不同地方，不编造行程顺序。", "以合影为主角，轻松、有活力，不推断人物关系。", "收集不同地点的人与风景，不把所有照片说成同一天。"]
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let input = documents.appendingPathComponent("DesignFixtures/" + names[index])
        let output = documents.appendingPathComponent("CreationSceneResults/" + names[index] + "-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let coordinator = CreationCoordinator(owner: "creation-live-test")
        coordinator.draft.stickerMode = "我来选"
        coordinator.draft.brief.theme = themes[index]
        coordinator.draft.brief.story = stories[index]
        coordinator.draft.brief.moods = ["轻松"]
        coordinator.draft.design = .init(layout: [DiaryAILayout.hero, .story, .headline, .collage, .editorial, .automatic][index], style: DiaryAIPageStyle.allCases[index])
        for folder in ["photos", "stickers"] {
            let files = try FileManager.default.contentsOfDirectory(at: input.appendingPathComponent(folder), includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
            for file in files { await coordinator.add(try Data(contentsOf: file), name: file.lastPathComponent, sticker: folder == "stickers") }
        }
        let session = try #require(await coordinator.prepare())
        let request = coordinator.draft.request()
        try JSONEncoder().encode(request).write(to: output.appendingPathComponent("request.json"))
        let workspace = DiaryAIWorkspace(session: session, parallelExecution: true)
        let start = Date()
        await workspace.enter(request); workspace.processAll()
        let deadline = Date().addingTimeInterval(900)
        while workspace.running && Date() < deadline { try await Task.sleep(for: .milliseconds(250)) }
        if workspace.running { workspace.pause() }
        try JSONEncoder().encode(workspace.events).write(to: output.appendingPathComponent("events.json"))
        if let bytes = workspace.preview?.jpegData(compressionQuality: 0.92) { try bytes.write(to: output.appendingPathComponent("composed.jpg")) }
        if let bytes = workspace.backgroundPreview?.pngData() { try bytes.write(to: output.appendingPathComponent("background.png")) }
        if let url = try? await workspace.exportProductionLog() { try FileManager.default.copyItem(at: url, to: output.appendingPathComponent("production-log.zip")) }
        try JSONSerialization.data(withJSONObject: ["seconds": Date().timeIntervalSince(start), "scene": names[index], "error": workspace.error ?? "", "pending": workspace.pending.count], options: .prettyPrinted).write(to: output.appendingPathComponent("metrics.json"))
        print("CREATION_SCENE \(names[index]) \(Date().timeIntervalSince(start)) error=\(workspace.error ?? "none") output=\(output.path)")
        #expect(workspace.error == nil && workspace.pending.isEmpty && workspace.backgroundRecord?.verified == true)
        if workspace.error == nil && workspace.pending.isEmpty && workspace.backgroundRecord?.verified == true {
            #expect(await workspace.save())
            let bookID = try #require(coordinator.draft.targetBookID)
            let reopened = try await DiaryDocumentStore(ownerID: coordinator.draft.owner, bookID: bookID).load(session.document.id)
            #expect(reopened.document.creation?.brief == coordinator.draft.brief)
            #expect(reopened.document.creation?.assetObjects.count == coordinator.draft.mapping.count)
        }
    }

}
