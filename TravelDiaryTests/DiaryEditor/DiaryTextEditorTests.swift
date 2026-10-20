import Testing
import SwiftUI
import UIKit
@testable import TravelDiary

@MainActor
struct DiaryTextEditorTests {
    private func session() -> DiaryEditorSession {
        var document = DiaryDocument()
        document.objects[document.rootContentID]?.background = .paper
        return DiaryEditorSession(document: document, images: [:],
            store: DiaryDocumentStore(ownerID: "text-editor-tests",
                baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
    }

    @Test func typingAndTemplatesRemainIsolatedUntilSingleCommit() throws {
        let source = session()
        let before = source.document
        let draft = DiaryTextDraft(session: source, layer: nil)
        draft.layer.text = "上海的比赛"
        draft.apply(.burst)
        draft.layer.text = "记录旅途的美好"
        #expect(source.document == before)
        #expect(source.undoStack.isEmpty)
        #expect(draft.preview.document.layer(draft.layer.id)?.text == "记录旅途的美好")
        #expect(draft.preview.document.layer(draft.layer.id)?.textAppearance?.template == .burst)
        #expect(source.commitTextDraft(draft.layer, targetID: nil))
        #expect(source.undoStack.count == 1)
        let text = try #require(source.selectedEditingLayer)
        #expect(text.kind == .text)
        #expect(text.textAppearance?.template == .burst)
        let decoded = try JSONDecoder().decode(DiaryDocument.self, from: JSONEncoder().encode(source.document))
        #expect(decoded.layer(text.id)?.textAppearance == text.textAppearance)
        source.undo()
        #expect(source.content.layers.isEmpty)
        source.redo()
        #expect(source.document.layer(text.id)?.text == "记录旅途的美好")
    }

    @Test func editingPreservesObjectPlacementAndRejectsLockedTargets() throws {
        let source = session()
        #expect(source.applyTextEdit(targetID: nil, text: "原文字", fontSize: 48, font: nil))
        let target = try #require(source.selectedEditingLayer)
        let object = try #require(source.selected)
        let draft = DiaryTextDraft(session: source, layer: target)
        draft.layer.text = "新文字"
        draft.apply(.ticket)
        #expect(source.document.layer(target.id)?.text == "原文字")
        #expect(source.commitTextDraft(draft.layer, targetID: target.id))
        #expect(source.selected?.transform == object.transform)
        #expect(source.document.layer(target.id)?.id == target.id)
        source.toggleLock(object.id)
        #expect(!source.commitTextDraft(draft.layer, targetID: target.id))
    }

    @Test func draftDoesNotCommitEmptyTextAndEffectsExpandRenderBounds() {
        let source = session()
        let draft = DiaryTextDraft(session: source, layer: nil)
        #expect(!source.commitTextDraft(draft.layer, targetID: nil))
        draft.layer.text = "旅途"
        let plain = DiaryPageRenderer.bounds(draft.layer)
        draft.apply(.bubble)
        var style = draft.layer.textAppearance!
        style.shadowRadius = 20
        draft.layer.textAppearance = style
        let decorated = DiaryPageRenderer.bounds(draft.layer)
        #expect(decorated.minX < 0)
        #expect(decorated.height > plain.height)
        #expect(decorated.width > plain.width)
    }

    @Test func textEditorVisualVerification() async throws {
        let source = session()
        let draft = DiaryTextDraft(session: source, layer: nil)
        draft.layer.text = "上海的比赛"
        draft.apply(.label)
        #expect(source.commitTextDraft(draft.layer, targetID: nil))
        for tab in [DiaryTextEditorTab.templates, .style, .font] {
            let host = UIHostingController(rootView: DiaryTextEditorSheet(session: source,
                layer: source.selectedEditingLayer, initialTab: tab))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = host; window.makeKeyAndVisible()
            host.view.frame = window.bounds; host.view.layoutIfNeeded()
            try await Task.sleep(for: .seconds(1))
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("diary-text-\(tab.rawValue).png")
            try #require(image.pngData()).write(to: destination)
            print("Text visual QA: \(destination.path)")
            window.isHidden = true
        }
    }
}
