import Testing
import UIKit
@testable import TravelDiary

/// Explicit real-data run: this marker is created by the local validation command, never by the app.
@Suite(.serialized)
@MainActor struct DiaryAIBook8IntegrationTests {
    @Test func importArrangeSaveAndReopenRealBook() async throws {
        guard FileManager.default.fileExists(atPath: "/tmp/traveldiary-book8-integration-enabled") else { return }
        let input = URL(fileURLWithPath: "/tmp/traveldiary-book8-fixture.zip")
        let output = URL(fileURLWithPath: "/tmp/TravelDiaryBook8Validation")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = output.appendingPathComponent("sandbox-" + UUID().uuidString)
        let owner = "book8-validation"
        let importer = DiaryDocumentStore(ownerID: owner, baseDirectory: root)
        let book = try await importer.debugImportBook(from: input)
        #expect(book.pages.count == 3)
        let page = try #require(book.pages.first { $0.id.uuidString == "E7377B9C-4F4B-4943-B1F4-460568CB6748" })
        let store = DiaryDocumentStore(ownerID: owner, baseDirectory: root, bookID: book.id)
        let loaded = try await store.load(page.id)
        let session = DiaryEditorSession(document: loaded.document, images: loaded.images, store: store)
        let baseline = session.document
        let workspace = DiaryAIWorkspace(session: session, root: root)
        var request = DiaryAIRequest.defaults(.relayout)
        request.style = "照片故事"
        request.instruction = "用现有4张照片和4张贴纸设计旅行手帐。照片明显大小对比，主照片宽约900至1200设计单位，其余约600至900，分布左右页，不要全部缩成小图堆在上半部中央。保护背景右下画画人物与左下Paint the sky字样，贴纸在照片边角点缀。所有对象都必须安排到页面内，避开中间书脊。只移动等比缩放和轻微旋转，不新增文字不裁剪不换相框。"
        await workspace.enter(request)
        #expect(workspace.active)
        #expect(workspace.pending.count == 8)
        #expect(workspace.objects.filter { $0.role == "photo" }.count == 4)
        if let bytes = workspace.original?.pngData() { try bytes.write(to: output.appendingPathComponent("01-原版.png")) }
        if let bytes = workspace.preview?.pngData() { try bytes.write(to: output.appendingPathComponent("02-排版基础.png")) }
        workspace.processAll()
        let deadline = Date().addingTimeInterval(1200)
        var last = -1
        while workspace.running && Date() < deadline {
            if workspace.events.count != last {
                last = workspace.events.count
                if let event = workspace.events.last { print("BOOK8 \(event.kind) \(event.title) \(String(event.detail.prefix(400)))") }
                let bytes = try JSONEncoder().encode(workspace.events)
                try bytes.write(to: output.appendingPathComponent("操作记录.json"), options: .atomic)
                if let image = workspace.preview?.pngData() { try image.write(to: output.appendingPathComponent("当前效果.png"), options: .atomic) }
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        let bytes = try JSONEncoder().encode(workspace.events)
        try bytes.write(to: output.appendingPathComponent("操作记录.json"), options: .atomic)
        Attachment.record(Array(bytes), named: "book8-events.json")
        print("BOOK8_RESULT pending=\(workspace.pending.count) version=\(workspace.version) error=\(workspace.error ?? "none")")
        #expect(workspace.error == nil)
        #expect(workspace.pending.isEmpty)
        guard workspace.error == nil, workspace.pending.isEmpty else { return }
        #expect(session.document == baseline)
        #expect(await workspace.save())
        #expect(session.undoStack.count == 1)
        let reopened = try await store.load(page.id)
        #expect(reopened.document.root.layers.count == baseline.root.layers.count)
        #expect(Set(reopened.document.root.layers.map(\.id)) == Set(baseline.root.layers.map(\.id)))
        let allVisible = reopened.document.root.layers.allSatisfy { $0.visible }
        #expect(allVisible)
        // Keep an owned session alive for the weak bridge.
        let reopenedSession = DiaryEditorSession(document: reopened.document, images: reopened.images, store: store)
        let renderer = DiaryEditorAIBridge(reopenedSession)
        _ = try await renderer.capture(request)
        let final = try await renderer.originalPreview()
        try final.write(to: output.appendingPathComponent("03-保存后重开.jpg"))
        Attachment.record(Array(final), named: "book8-final.jpg")
        let exported = output.appendingPathComponent("已排版项目-" + UUID().uuidString)
        try await store.exportSourceFiles(try await store.loadBook(), to: exported)
        session.undo()
        #expect(session.scopeLayers == baseline.root.layers)
        print("BOOK8_COMPLETE \(exported.path)")
    }
}
