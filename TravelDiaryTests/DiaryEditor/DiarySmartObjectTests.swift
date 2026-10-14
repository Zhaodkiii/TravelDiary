import Testing
import PencilKit
@testable import TravelDiary

@MainActor
struct DiarySmartObjectTests {
    private func makeSession() -> DiaryEditorSession {
        let store = DiaryDocumentStore(ownerID: "tests", baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        return DiaryEditorSession(document: DiaryDocument(), images: [:], store: store)
    }

    /// 文字与主画布使用同一内容模型；提交内部装饰不能改变父级摆放。
    @Test
    func testCommitAndUndoPreserveOuterTransform() async throws {
        let parent = makeSession()
        parent.applyText("旅行", fontSize: 36)
        let outer = try #require(parent.selected)
        let child = try #require(parent.openObject())
        #expect(parent.content.background == nil)
        #expect(child.content.background == nil)
        child.setBackground(.yellow)
        child.select(nil)
        child.applyText("装饰", fontSize: 20)
        let committed = await child.commitToParent()
        #expect(committed)
        #expect(parent.selected?.transform == outer.transform)
        #expect(parent.document.objects[child.contentID]?.layers.count == 2)
        parent.undo()
        #expect(parent.document.objects[child.contentID]?.background == nil)
        #expect(parent.document.objects[child.contentID]?.layers.count == 1)
    }

    @Test
    func testCancelDiscardsNestedEdits() async throws {
        let parent = makeSession()
        parent.applyText("旅行", fontSize: 36)
        let before = parent.document
        let child = try #require(parent.openObject())
        child.setBackground(.pink)
        child.applyText("修改后的文字", fontSize: 50)
        await child.cancelEditor()
        #expect(parent.document == before)
    }

    @Test
    func testSaveReloadNestedLayersAndTransparentBackground() async throws {
        let session = makeSession()
        session.applyText("标题", fontSize: 36)
        let child = try #require(session.openObject())
        child.select(nil)
        child.applyText("嵌套文字", fontSize: 25)
        let nested = try #require(child.openObject())
        nested.setBackground(.mint)
        let nestedCommitted = await nested.commitToParent()
        #expect(nestedCommitted)
        let committed = await child.commitToParent()
        #expect(committed)
        let loaded = try await session.store.load(session.document.id)
        #expect(loaded.document == session.document)
        #expect(loaded.document.root.background == nil)
        #expect(loaded.document.objects.count == 3)
    }

}
