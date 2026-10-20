import SwiftUI
import Combine

/// A separate in-memory document lets typing preview the real canvas without saving incomplete edits.
@MainActor
final class DiaryTextDraft: ObservableObject {
    let preview: DiaryEditorSession
    let targetID: UUID?
    @Published var layer: DiaryLayer { didSet { refresh() } }

    init(session: DiaryEditorSession, layer: DiaryLayer?) {
        targetID = layer?.id
        preview = DiaryEditorSession(document: session.document, images: session.images,
            store: session.store, contentID: session.contentID, parent: session.parent)
        let width = min(900, session.content.referenceSize.width * 0.65)
        self.layer = layer ?? DiaryLayer(name: "文字", kind: .text,
            transform: DiaryTransform(position: session.scopeCenter, pivot: CGPoint(x: width / 2, y: 50)),
            size: CGSize(width: width, height: 100), fontSize: min(90, max(36, width * 0.09)),
            textAppearance: DiaryTextAppearance())
        preview.selectedID = session.selectedID
        refresh()
    }

    func refresh() {
        var visible = layer
        if visible.text.isEmpty { visible.text = "输入文字" }
        preview.previewTextDraft(visible, targetID: targetID)
    }

    func apply(_ template: DiaryTextTemplate) {
        var next = layer
        next.textAppearance = DiaryTextAppearance(template: template, bold: template == .burst,
            strokeWidth: template == .burst ? 2 : 0)
        next.textColor = template.textColor
        next.textAlignment = .center
        next.textLineHeight = 1.2
        next.textLetterSpacing = 0
        let fontID = template == .postcard || template == .tape ? "handwriting.lxgw.wenkai" : "system"
        next.font = DiaryFontCatalog.shared.entries.first { $0.id == fontID }?.reference ?? .system
        layer = next
    }
}
