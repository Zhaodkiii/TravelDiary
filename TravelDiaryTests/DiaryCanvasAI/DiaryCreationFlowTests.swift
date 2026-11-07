import Testing
import UIKit
import SwiftUI
@testable import TravelDiary

struct DiaryStickerDrawEngineTests {
    private var pool: [DiaryStickerDrawEngine.Candidate] { (0..<40).map { .init(id: String($0), pack: String($0 / 8)) } }
    @Test func firstDrawIsBoundedUniqueAndReproducible() {
        for seed in UInt64(0)..<100 {
            let first = DiaryStickerDrawEngine.draw(candidates: pool, current: [], kept: [], excluded: [], history: [], seed: seed)
            #expect((3...6).contains(first.ids.count))
            #expect(Set(first.ids).count == first.ids.count)
            #expect(first == DiaryStickerDrawEngine.draw(candidates: pool, current: [], kept: [], excluded: [], history: [], seed: seed))
        }
    }
    @Test func keepDeleteAndHistoryAreRespected() {
        let result = DiaryStickerDrawEngine.draw(candidates: pool, current: ["0", "1", "2", "3"], kept: ["1"], excluded: ["4", "5"], history: [["6", "7"]], seed: 7)
        #expect(result.ids.contains("1"))
        #expect(!result.ids.contains { ["0", "2", "3", "4", "5", "6", "7"].contains($0) })
        #expect(result.ids.firstIndex(of: "1") == 1)
    }
    @Test func exhaustedPoolDoesNotPretendToChange() {
        let current = ["0", "1"]
        let result = DiaryStickerDrawEngine.draw(candidates: Array(pool.prefix(2)), current: current, kept: [], excluded: [], history: [], seed: 3)
        #expect(result.ids == current)
        let empty = DiaryStickerDrawEngine.draw(candidates: pool, current: [], kept: [], excluded: Set(pool.map(\.id)), history: [], seed: 3)
        #expect(empty.ids.isEmpty)
    }
    @Test func smallPoolAndDuplicateCatalogAreSafe() {
        let result = DiaryStickerDrawEngine.draw(candidates: [pool[0], pool[0], pool[1]], current: [], kept: [], excluded: [], history: [], seed: 20)
        #expect(Set(result.ids) == ["0", "1"])
    }
    @Test func sixSevenAndEightKeptItems() {
        for count in 6...8 {
            let current = (0..<8).map(String.init)
            let kept = Set(current.prefix(count))
            let result = DiaryStickerDrawEngine.draw(candidates: pool, current: current, kept: kept, excluded: [], history: [], seed: 4)
            #expect(result.ids.count == 8)
            #expect(Array(result.ids.prefix(count)) == Array(current.prefix(count)))
        }
    }
}

@Suite(.serialized) @MainActor struct DiaryCreationDraftTests {
    private func fixture() -> (DiaryEditorSession, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let document = DiaryDocument()
        let store = DiaryDocumentStore(ownerID: "creation-flow-test", baseDirectory: root)
        return (DiaryEditorSession(document: document, images: [:], store: store), root)
    }
    @Test func draftRestoresStableSelectionAndStep() throws {
        let (session, root) = fixture()
        let flow = try DiaryAICreationFlow(session: session)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: flow.directory) }
        flow.draft.didDraw = true; flow.draft.excluded = ["deleted"]
        flow.draft.history = [["first"]]; flow.setStory("旅行故事"); flow.setStep(2)
        #expect(flow.save())
        let restored = try DiaryAICreationFlow(session: session)
        #expect(restored.id == flow.id)
        #expect(restored.draft.step == 2)
        #expect(restored.draft.story == "旅行故事")
        #expect(restored.draft.excluded == ["deleted"])
        #expect(restored.draft.didDraw)
    }
    @Test func deletingDoesNotRefillAndUndoRestoresExclusion() throws {
        let (session, root) = fixture()
        let flow = try DiaryAICreationFlow(session: session)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: flow.directory) }
        let item = CloudMaterial(id: "one", revision: 1, name: "贴纸", keywords: [], aliases: [], kind: "illustration", subcategory: "", thumbnail_sha256: "", thumbnail_url: "", sha256: "", byte_size: 0, favorite_count: 0, is_favorited: false)
        flow.draft.stickers = [.init(item: item, filename: "one", kept: true)]
        flow.removeSticker("one")
        #expect(flow.draft.stickers.isEmpty)
        #expect(flow.draft.excluded.contains("one"))
        flow.undoLast()
        #expect(flow.draft.stickers.count == 1)
        #expect(flow.draft.stickers[0].kept)
        #expect(!flow.draft.excluded.contains("one"))
    }
    @Test func creationCommitIsDurableAndIdempotent() async throws {
        let (session, root) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = DiaryAIWorkspace(session: session, root: root)
        let request = DiaryAIRequest.defaults(.relayout)
        await workspace.enter(request)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 100))
        let bytes = try #require(renderer.image { ctx in UIColor.orange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 100)) }.pngData())
        let id = UUID()
        #expect(await workspace.commitCreation(id: id, photos: [bytes, bytes], stickers: [], heroIndex: 1, photoNotes: ["第一张说明", "第二张说明"], request: request))
        #expect(workspace.objects.filter { $0.role == "photo" }.count == 2)
        let hero = try #require(workspace.currentRequest.heroID)
        #expect(workspace.currentRequest.creationNotes?[hero.uuidString] == "第二张说明")
        #expect(await workspace.commitCreation(id: id, photos: [bytes], stickers: [], heroIndex: 0, request: request))
        #expect(workspace.objects.filter { $0.role == "photo" }.count == 2)
        #expect(!workspace.running)
        #expect(await workspace.keepForLater())
        let restored = DiaryAIWorkspace(session: session, root: root)
        await restored.enter(request)
        #expect(await restored.commitCreation(id: id, photos: [bytes], stickers: [], heroIndex: 0, request: request))
        #expect(restored.objects.filter { $0.role == "photo" }.count == 2)
        #expect(!restored.running)
        #expect(restored.currentRequest.heroID == hero)
        #expect(restored.currentRequest.creationNotes?[hero.uuidString] == "第二张说明")
    }
    @Test func submissionFourPhotosFourStickersTiming() async throws {
        let (session, root) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = session.aiWorkspace
        let request = DiaryAIRequest.defaults(.relayout)
        await workspace.enter(request)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 3024, height: 4032), format: format).image { ctx in
            UIColor.systemTeal.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 3024, height: 4032))
        }
        let bytes = try #require(photo.jpegData(compressionQuality: 0.9))
        let sticker = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024), format: format).image { ctx in
            UIColor.orange.setFill(); ctx.fill(CGRect(x: 100, y: 100, width: 800, height: 800))
        }
        let stickerBytes = try #require(sticker.pngData())
        let flow = try DiaryAICreationFlow(session: session)
        let oldOwner = MaterialCatalogRepository.shared.owner
        MaterialCatalogRepository.shared.activate(session.store.ownerID)
        defer {
            MaterialCatalogRepository.shared.activate(oldOwner)
            try? FileManager.default.removeItem(at: flow.directory)
        }
        for i in 0..<4 {
            let filename = "photo-\(i).jpg"
            try bytes.write(to: flow.directory.appendingPathComponent(filename))
            flow.draft.photos.append(.init(filename: filename, digest: "\(i)", name: filename))
            flow.images[filename] = photo
            let name = "sticker-\(i).png"
            try stickerBytes.write(to: flow.directory.appendingPathComponent(name))
            let item = CloudMaterial(id: "timing-\(i)", revision: 0, name: name, keywords: [], aliases: [], kind: "illustration", subcategory: "", thumbnail_sha256: "", thumbnail_url: "", sha256: "", byte_size: stickerBytes.count, favorite_count: 0, is_favorited: false)
            flow.draft.stickers.append(.init(item: item, filename: name, kept: false))
            flow.images[name] = sticker
        }
        let preparationStarted = Date()
        await flow.waitForPreparation()
        print("CREATION_TIMING prepare-total=\(Date().timeIntervalSince(preparationStarted))")
        #expect(flow.preparedCount == 8)
        #expect(flow.preparationBuildCount == 8)
        let hero = flow.draft.photos[2].id
        flow.setHero(hero)
        flow.setPhotoNote(hero, value: "主照片说明")
        flow.movePhoto(hero, offset: -1)
        flow.setStory("返回修改故事")
        await flow.waitForPreparation()
        #expect(flow.preparationBuildCount == 8, "Metadata changes must reuse prepared materials")
        flow.cancelOperation()
        let restored = try DiaryAICreationFlow(session: session)
        await restored.waitForPreparation()
        #expect(restored.preparedCount == 8)
        #expect(restored.preparationBuildCount == 0, "Reopening must restore the prepared cache")
        restored.cancelOperation()
        flow.resumePreparation()
        let started = Date()
        #expect(await flow.submit())
        print("CREATION_TIMING submit-total=\(Date().timeIntervalSince(started))")
        #expect(workspace.objects.filter { $0.role == "photo" }.count == 4)
        #expect(workspace.objects.filter { $0.role == "decoration" }.count == 4)
        #expect(flow.draft.submitted)
        let objectHero = try #require(workspace.currentRequest.heroID)
        #expect(workspace.currentRequest.creationNotes?[objectHero.uuidString] == "主照片说明")
    }
    @Test func preparationRetriesOnlyFailedMaterialsAndRejectsCancelledResults() async throws {
        let (session, root) = fixture()
        let flow = try DiaryAICreationFlow(session: session)
        let oldOwner = MaterialCatalogRepository.shared.owner
        MaterialCatalogRepository.shared.activate(session.store.ownerID)
        defer {
            flow.cancelOperation()
            MaterialCatalogRepository.shared.activate(oldOwner)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: flow.directory)
        }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 160)).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 160))
        }
        let bytes = try #require(image.pngData())
        for name in ["good", "bad"] {
            flow.draft.photos.append(.init(filename: name, digest: name, name: name))
            flow.images[name] = image
            try (name == "good" ? bytes : Data([0, 1])).write(to: flow.directory.appendingPathComponent(name))
        }
        await flow.waitForPreparation()
        #expect(flow.preparedCount == 1)
        #expect(flow.preparationFailures.count == 1)
        try bytes.write(to: flow.directory.appendingPathComponent("bad"))
        await flow.waitForPreparation()
        #expect(flow.preparedCount == 2)
        #expect(flow.preparationBuildCount == 2)
        #expect(flow.preparationFailures.isEmpty)
        let removed = flow.draft.photos[0]
        flow.removePhoto(removed.id)
        await flow.waitForPreparation()
        #expect(flow.preparedCount == 1)
        #expect(flow.preparationBuildCount == 2)
        flow.draft.photos.append(.init(filename: "cancelled", digest: "cancelled", name: "cancelled"))
        flow.images["cancelled"] = image
        try bytes.write(to: flow.directory.appendingPathComponent("cancelled"))
        flow.resumePreparation()
        flow.cancelOperation()
        await Task.yield()
        #expect(!flow.preparingMaterials)
        #expect(flow.preparationBuildCount == 2)
        flow.draft.photos.removeAll { $0.filename == "cancelled" }
        await flow.waitForPreparation()
        #expect(flow.preparedCount == 1)
        #expect(session.document.assets.isEmpty, "Preparation must not publish into the source document")
    }
    @Test func selectedPhotoPreviewUsesOriginalImage() async throws {
        let (session, root) = fixture()
        let flow = try DiaryAICreationFlow(session: session)
        let owner = MaterialCatalogRepository.shared.owner
        MaterialCatalogRepository.shared.activate(session.store.ownerID)
        defer {
            flow.cancelOperation(); MaterialCatalogRepository.shared.activate(owner)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: flow.directory)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let bytes = try #require(UIGraphicsImageRenderer(size: CGSize(width: 900, height: 700), format: format).image { _ in }.pngData())
        await flow.importCamera([bytes])
        let photo = try #require(flow.draft.photos.first)
        let preview = try #require(flow.images[photo.filename])
        #expect(preview.size == CGSize(width: 900, height: 700))
        #expect(flow.pendingPhotoIDs.isEmpty)
        #expect(flow.selectedPhotoImages.isEmpty)
    }
    @Test func fastSubmitWaitsForPhotoLoadingWithoutBlockingNavigation() async throws {
        let (session, root) = fixture()
        let flow = try DiaryAICreationFlow(session: session)
        let owner = MaterialCatalogRepository.shared.owner
        MaterialCatalogRepository.shared.activate(session.store.ownerID)
        defer {
            flow.cancelOperation(); MaterialCatalogRepository.shared.activate(owner)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: flow.directory)
        }
        await session.aiWorkspace.enter(.defaults(.relayout))
        let bytes = try #require(UIGraphicsImageRenderer(size: CGSize(width: 100, height: 120)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 120))
        }.pngData())
        let gate = PhotoLoadGate()
        flow.enqueuePhotoLoads([{ await gate.wait(); return bytes }])
        #expect(flow.pendingPhotoIDs.count == 1)
        #expect(flow.canContinue)
        #expect(!flow.busy)
        flow.setStep(1); flow.setStory("读取期间编辑"); flow.setStep(2)
        #expect(flow.draft.step == 2)
        let submit = Task { await flow.submit() }
        while !flow.isSubmitting { await Task.yield() }
        #expect(session.aiWorkspace.objects.isEmpty)
        #expect(!(await flow.submit()), "Repeated submit must not start a second request")
        gate.release()
        #expect(await submit.value)
        #expect(flow.pendingPhotoIDs.isEmpty)
        #expect(session.aiWorkspace.objects.filter { $0.role == "photo" }.count == 1)
        #expect(flow.draft.submitted)
    }
    @Test func removedPendingPhotoNeverReturnsAndAdditionalSelectionIsQueued() async throws {
        let (session, root) = fixture()
        let flow = try DiaryAICreationFlow(session: session)
        let owner = MaterialCatalogRepository.shared.owner
        MaterialCatalogRepository.shared.activate(session.store.ownerID)
        defer {
            flow.cancelOperation(); MaterialCatalogRepository.shared.activate(owner)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: flow.directory)
        }
        let bytes = try #require(UIGraphicsImageRenderer(size: CGSize(width: 80, height: 100)).image { _ in }.pngData())
        let gate = PhotoLoadGate()
        flow.enqueuePhotoLoads([{ await gate.wait(); return bytes }])
        let removed = try #require(flow.pendingPhotoIDs.first)
        await Task.yield()
        flow.enqueuePhotoLoads([{ bytes }])
        #expect(flow.selectedPhotoCount == 2)
        flow.removePhoto(removed)
        gate.release()
        // Camera's empty enqueue provides the same queue barrier used by submit.
        await flow.importCamera([])
        #expect(flow.draft.photos.count == 1)
        #expect(!flow.draft.photos.contains { $0.id == removed })
        #expect(flow.pendingPhotoIDs.isEmpty)
    }
    @Test func invalidCreationNeverPartiallyPublishes() async throws {
        let (session, root) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = DiaryAIWorkspace(session: session, root: root)
        let request = DiaryAIRequest.defaults(.relayout)
        await workspace.enter(request)
        #expect(!(await workspace.commitCreation(id: UUID(), photos: [Data([0, 1])], stickers: [], heroIndex: 0, request: request)))
        #expect(workspace.objects.isEmpty)
        #expect(workspace.pending.isEmpty)
        #expect(!workspace.addingMaterials)
    }
    @Test func preparationPagesRenderWithoutNetwork() async throws {
        let (session, root) = fixture()
        let flow = try DiaryAICreationFlow(session: session)
        let oldOwner = MaterialCatalogRepository.shared.owner
        MaterialCatalogRepository.shared.activate(session.store.ownerID)
        defer {
            MaterialCatalogRepository.shared.activate(oldOwner)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: flow.directory)
        }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 180)).image { ctx in
            UIColor.systemTeal.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 240, height: 180))
        }
        for i in 0..<4 {
            flow.draft.photos.append(.init(filename: "photo-\(i)", digest: "\(i)", name: "照片"))
            flow.images["photo-\(i)"] = image
            let item = CloudMaterial(id: "s\(i)", revision: 1, name: "旅行贴纸 \(i+1)", keywords: [], aliases: [], kind: "illustration", subcategory: "", thumbnail_sha256: "", thumbnail_url: "", sha256: "", byte_size: 0, favorite_count: 0, is_favorited: false)
            flow.draft.stickers.append(.init(item: item, filename: "s\(i)", kept: i == 0))
            flow.images["s\(i)"] = UIImage(systemName: ["leaf.fill", "sun.max.fill", "camera.fill", "airplane"][i])
            flow.candidates.append(item)
        }
        flow.draft.heroID = flow.draft.photos.first?.id
        flow.draft.didDraw = true
        let output = URL(fileURLWithPath: "/tmp/DiaryCreationFlowPreviews")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for step in 0...2 {
            flow.draft.step = step
            let host = UIHostingController(rootView: DiaryAICreationSheet(flow: flow, submitted: {}))
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host; window.windowLevel = .alert + 1; window.makeKeyAndVisible()
            host.view.frame = window.bounds
            try await Task.sleep(for: .milliseconds(500))
            host.view.layoutIfNeeded()
            let preview = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let cg = try #require(preview.cgImage)
            let data = try #require(cg.dataProvider?.data)
            let buffer = try #require(CFDataGetBytePtr(data))
            let samples = stride(from: 0, to: CFDataGetLength(data), by: 127).map { buffer[$0] }
            #expect(Set(samples).count > 8, "Snapshot must contain rendered UI, not an empty black window")
            try #require(preview.pngData()).write(to: output.appendingPathComponent("step-\(step+1).png"))
            window.isHidden = true; window.rootViewController = nil
        }
    }

}

@MainActor private final class PhotoLoadGate {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
