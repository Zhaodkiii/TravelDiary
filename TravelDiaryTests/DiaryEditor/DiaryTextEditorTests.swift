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

    @Test func markedChineseTextSurvivesInlineColorChangesAndFocusRestorationIsRejected() async throws {
        let source = session()
        let presentation = DiaryTextEditorPresentation(session: source, layer: nil)
        let draft = presentation.draft
        #expect(draft.consumeInitialInputFocus())
        #expect(!draft.consumeInitialInputFocus())
        let focus = DiaryTextInputTestFocus()
        let host = UIHostingController(rootView: DiaryTextInputTestHost(draft: draft, focus: focus))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        func textView(in view: UIView) -> UITextView? {
            if let view = view as? UITextView { return view }
            return view.subviews.lazy.compactMap { textView(in: $0) }.first
        }
        try await Task.sleep(for: .milliseconds(100))
        let input = try #require(textView(in: host.view))
        #expect(input.becomeFirstResponder())
        input.setMarkedText("哈哈哈吧", selectedRange: NSRange(location: 4, length: 0))
        input.delegate?.textViewDidChange?(input)
        #expect(draft.layer.text == "哈哈哈吧")
        draft.selectFont(.system)
        draft.setTextColor(.brown)
        try await Task.sleep(for: .milliseconds(50))
        #expect(input.text == "哈哈哈吧")
        #expect(input.markedTextRange != nil)
        input.resignFirstResponder()
        focus.requested = false
        #expect(!input.becomeFirstResponder())
        // Color tools stay in the same view hierarchy; there is no presenting controller or keyboard restoration.
        draft.setTextColor(DiaryColor(red: 1, green: 0, blue: 0))
        #expect(draft.layer.text == "哈哈哈吧")
        #expect(draft.layer.textColor == DiaryColor(red: 1, green: 0, blue: 0))
        #expect(!input.isFirstResponder)
        #expect(host.presentedViewController == nil)
        // Recreating the editor's view uses the presentation's existing model, never a blank draft.
        host.rootView = DiaryTextInputTestHost(draft: presentation.draft, focus: focus)
        try await Task.sleep(for: .milliseconds(100))
        #expect(presentation.draft.layer.text == "哈哈哈吧")
        #expect(presentation.draft.preview.document.layer(draft.layer.id)?.text == "哈哈哈吧")
        #expect(!input.isFirstResponder)
        #expect(!input.becomeFirstResponder())
        focus.requested = true
        #expect(input.becomeFirstResponder())
        #expect(source.content.layers.isEmpty)
    }

    @Test func inlinePaletteDoesNotPresentOrOverwriteTextOnAppearance() async throws {
        let draft = DiaryTextDraft(session: session(), layer: nil)
        draft.setText("哈哈哈哈")
        draft.setTextColor(DiaryColor(red: 0.12, green: 0.4, blue: 0.7))
        let before = draft.layer
        let host = UIHostingController(rootView: DiaryTextColorPanel(title: "文字颜色",
            color: Binding(get: { draft.layer.textColor! }, set: { draft.setTextColor($0) })))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        #expect(draft.layer == before)
        #expect(host.presentedViewController == nil)
        func hasTextInput(_ view: UIView) -> Bool {
            view is UITextField || view is UITextView || view.subviews.contains(where: hasTextInput)
        }
        #expect(!hasTextInput(host.view))
        for color in [DiaryColor.white, .brown, .pink, DiaryColor(red: 0, green: 0, blue: 0)] {
            draft.setTextColor(color)
            #expect(draft.preview.document.layer(draft.layer.id)?.text == "哈哈哈哈")
            #expect(draft.preview.document.layer(draft.layer.id)?.textColor == color)
        }
    }

    @Test func allTemplatesAllowIndependentFontTextColorAndBackgroundEdits() throws {
        let draft = DiaryTextDraft(session: session(), layer: nil)
        draft.layer.text = "北京的春天"
        DiaryFontCatalog.shared.prepare()
        let font = try #require(DiaryFontCatalog.shared.entries.first { $0.id == "handwriting.lxgw.wenkai" }).reference
        let foreground = DiaryColor(red: 0.8, green: 0.1, blue: 0.2)
        let background = DiaryColor(red: 0.2, green: 0.5, blue: 0.9)
        for template in DiaryTextTemplate.allCases {
            draft.apply(template)
            draft.selectFont(font)
            draft.setTextColor(foreground)
            draft.setBackgroundColor(background)
            let visible = try #require(draft.preview.document.layer(draft.layer.id))
            #expect(visible.font == font)
            #expect(visible.textColor == foreground)
            #expect(visible.textAppearance?.background == background)
            #expect(visible.textAppearance?.template == template)
            #expect(visible.textAppearance?.paper == nil)
            // Re-selecting a template must not silently reset explicit font or color choices.
            draft.apply(template)
            #expect(draft.layer.font == font)
            #expect(draft.layer.textColor == foreground)
        }
        draft.applyTitle(.balanced)
        #expect(draft.layer.font == font)
        #expect(draft.layer.textColor == foreground)
        draft.selectPaper(.torn)
        draft.setBackgroundColor(background)
        #expect(draft.layer.textAppearance?.paper?.color == background)
        #expect(draft.layer.font == font)
        #expect(draft.layer.textColor == foreground)
        draft.selectPaper(nil)
        #expect(draft.layer.textAppearance?.paper == nil)
    }

    @Test func editedNestedTextInvalidatesColorAndFontPixelsAndSaves() async throws {
        let source = session()
        #expect(source.applyTextEdit(targetID: nil, text: "北京的春天", fontSize: 60, font: .system))
        let target = try #require(source.selectedEditingLayer)
        let draft = DiaryTextDraft(session: source, layer: target)
        draft.apply(.label)
        let cache = DiaryCanvasRenderCache()
        func pixels() throws -> Data {
            cache.synchronize(document: draft.preview.document, images: draft.preview.images, contentID: draft.preview.contentID)
            cache.prepareResolution(pointsToPixels: 1)
            let entry = try #require(cache.ordered.first)
            cache.rasterize(entry)
            return try #require(entry.image?.pngData())
        }
        let original = try pixels()
        draft.setTextColor(DiaryColor(red: 1, green: 0, blue: 0))
        let colored = try pixels()
        #expect(colored != original)
        let font = try #require(DiaryFontCatalog.shared.entries.first { $0.id == "handwriting.lxgw.wenkai" }).reference
        draft.selectFont(font)
        await DiaryFontCatalog.shared.prewarm([font])
        draft.refresh()
        let changedFont = try pixels()
        #expect(changedFont != colored)
        #expect(source.document.layer(target.id)?.font == .system)
        #expect(source.commitTextDraft(draft.layer, targetID: target.id))
        try await source.save()
        let loaded = try await source.store.load(source.document.id)
        #expect(loaded.document.layer(target.id)?.font == font)
        #expect(loaded.document.layer(target.id)?.textColor == DiaryColor(red: 1, green: 0, blue: 0))
    }

    @Test func colorPickerConversionStoresValidSRGB() {
        for input in [Color.black, Color.white, Color.red, Color(uiColor: UIColor(displayP3Red: 1, green: 0, blue: 0.2, alpha: 0.7))] {
            let color = DiaryColor(input)
            #expect([color.red, color.green, color.blue, color.alpha].allSatisfy { $0.isFinite && (0...1).contains($0) })
        }
        #expect(DiaryColor(.black).alpha == 1)
    }

    @Test func titlesPreserveContentAndPaperAndRespectManualBreaks() throws {
        let source = session()
        let draft = DiaryTextDraft(session: source, layer: nil)
        draft.layer.text = "把北京慢慢翻开"
        draft.layer.textColor = .brown
        var appearance = DiaryTextAppearance()
        appearance.paper = DiaryTextPaper(kind: .torn, seed: 42)
        draft.layer.textAppearance = appearance
        draft.applyTitle(.balanced)
        #expect(draft.layer.text == "把北京慢慢翻开")
        #expect(DiaryPageRenderer.displayedText(draft.layer).contains("\n"))
        #expect(draft.layer.textAppearance?.paper?.seed == 42)
        #expect(draft.layer.textColor == .brown)
        draft.layer.text = "北京\n慢慢翻开"
        #expect(DiaryPageRenderer.displayedText(draft.layer) == draft.layer.text)
        #expect(source.content.layers.isEmpty)
        #expect(source.commitTextDraft(draft.layer, targetID: nil))
        let encoded = try JSONEncoder().encode(source.document)
        let decoded = try JSONDecoder().decode(DiaryDocument.self, from: encoded)
        #expect(decoded == source.document)
    }

    @Test func oldAppearanceDecodesAndPaperParametersAreValidated() throws {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(DiaryTextAppearance())) as? [String: Any])
        json.removeValue(forKey: "paper"); json.removeValue(forKey: "titleLayout")
        let decoded = try JSONDecoder().decode(DiaryTextAppearance.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.paper == nil)
        #expect(decoded.isValid)
        var invalid = decoded
        invalid.paper = DiaryTextPaper(roughness: 2)
        #expect(!invalid.isValid)
    }

    @Test func generatedPaperIsStableAndPresetsKeepCustomTypography() throws {
        let draft = DiaryTextDraft(session: session(), layer: nil)
        draft.layer.text = "收藏今天"
        var appearance = DiaryTextAppearance()
        appearance.paper = DiaryTextPaper(kind: .torn, roughness: 1, seed: 99)
        appearance.titleLayout = .handwriting
        draft.layer.textAppearance = appearance
        let first = DiaryPageRenderer.textPreview(draft.layer).pngData()
        #expect(first == DiaryPageRenderer.textPreview(draft.layer).pngData())
        var other = appearance; other.paper?.seed = 100
        draft.layer.textAppearance = other
        #expect(first != DiaryPageRenderer.textPreview(draft.layer).pngData())
        let style = DiarySavedTextStyle(name: "自定义", appearance: appearance, font: .system,
            color: .brown, alignment: .left, lineHeight: 1.7, letterSpacing: 3, fontSize: 65, width: 500)
        let decoded = try JSONDecoder().decode(DiarySavedTextStyle.self, from: JSONEncoder().encode(style))
        draft.applySaved(decoded)
        #expect(draft.layer.text == "收藏今天")
        #expect(draft.layer.font == .system)
        #expect(draft.layer.fontSize == 65)
        #expect(draft.layer.textLineHeight == 1.7)
        #expect(draft.layer.textAppearance?.paper == appearance.paper)
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
        for tab in [DiaryTextEditorTab.templates, .color, .background, .layout, .font] {
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

@MainActor
private final class DiaryTextInputTestFocus: ObservableObject {
    @Published var requested = true
}

@MainActor
private struct DiaryTextInputTestHost: View {
    @ObservedObject var draft: DiaryTextDraft
    @ObservedObject var focus: DiaryTextInputTestFocus
    var body: some View {
        DiaryTextInput(text: Binding(get: { draft.layer.text }, set: { draft.setText($0) }), isFocused: $focus.requested)
            .frame(width: 300, height: 76)
    }
}
