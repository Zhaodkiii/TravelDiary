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
