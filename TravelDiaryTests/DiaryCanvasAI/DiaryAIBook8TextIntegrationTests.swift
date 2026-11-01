import Testing
import UIKit
@testable import TravelDiary

@Suite(.serialized)
@MainActor struct DiaryAIBook8TextIntegrationTests {
    @Test func addEditableTextToArrangedRealBook() async throws {
        guard FileManager.default.fileExists(atPath: "/tmp/traveldiary-book8-text-enabled") else { return }
        let output = URL(fileURLWithPath: "/tmp/TravelDiaryBook8Validation")
        let exports = try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.lastPathComponent.hasPrefix("已排版项目-") }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        let input = try #require(exports.first)
        let root = output.appendingPathComponent("text-sandbox-" + UUID().uuidString)
        let owner = "book8-text-validation"
        let book = try await DiaryDocumentStore(ownerID: owner, baseDirectory: root).debugImportBook(from: input)
        let page = try #require(book.pages.first { $0.id.uuidString == "E7377B9C-4F4B-4943-B1F4-460568CB6748" })
        let store = DiaryDocumentStore(ownerID: owner, baseDirectory: root, bookID: book.id)
        let loaded = try await store.load(page.id)
        let session = DiaryEditorSession(document: loaded.document, images: loaded.images, store: store)
        let before = session.document
        let workspace = DiaryAIWorkspace(session: session, root: root)
        var request = DiaryAIRequest.defaults(.writing)
        request.style = "山野手记"; request.writingKind = "标题"; request.understandsPhotos = false
        request.instruction = "仅新增一个可编辑文字对象，正文是‘把山风记住’，不要额外副标题。用可用目录中的马善政或龙藏手写字体、深绿色#355A49、字号72、文本框宽1000、视觉中心x1300 y2800、角度0；此处在左页下方留白。只增加文字，不移动照片和贴纸，不修改背景和原有任何图层。不要输出图片形式的文字。"
        await workspace.enter(request); workspace.processAll()
        let deadline = Date().addingTimeInterval(700)
        var last = -1
        while workspace.running && Date() < deadline {
            if workspace.events.count != last {
                last = workspace.events.count
                if let e = workspace.events.last { print("BOOK8_TEXT \(e.kind) \(e.title) \(e.detail.prefix(300))") }
                try JSONEncoder().encode(workspace.events).write(to: output.appendingPathComponent("文字操作记录.json"), options: .atomic)
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        let events = try JSONEncoder().encode(workspace.events)
        Attachment.record(Array(events), named: "book8-text-events.json")
        try events.write(to: output.appendingPathComponent("文字操作记录.json"), options: .atomic)
        print("BOOK8_TEXT_RESULT \(workspace.error ?? workspace.stage)")
        #expect(workspace.error == nil)
        guard workspace.error == nil else { return }
        #expect(session.document == before)
        #expect(await workspace.save())
        let saved = try await store.load(page.id)
        #expect(saved.document.root.layers.count == before.root.layers.count + 1)
        for old in before.root.layers { #expect(saved.document.layer(old.id) == old) }
        for (id, content) in before.objects where id != before.rootContentID { #expect(saved.document.objects[id] == content) }
        let texts = saved.document.objects.values.flatMap(\.layers).filter { $0.kind == .text && $0.text == "把山风记住" }
        #expect(texts.count == 1)
        let text = try #require(texts.first)
        #expect(text.font?.id != "system")
        let reopened = DiaryEditorSession(document: saved.document, images: saved.images, store: store)
        let renderer = DiaryEditorAIBridge(reopened)
        _ = try await renderer.capture(request)
        let final = try await renderer.originalPreview()
        try final.write(to: output.appendingPathComponent("04-加入文字后重开.jpg"))
        Attachment.record(Array(final), named: "book8-with-text.jpg")
        let exported = output.appendingPathComponent("已添加文字项目-" + UUID().uuidString)
        try await store.exportSourceFiles(try await store.loadBook(), to: exported)
        session.undo()
        #expect(session.scopeLayers == before.root.layers)
        print("BOOK8_TEXT_COMPLETE \(exported.path)")
    }
}
