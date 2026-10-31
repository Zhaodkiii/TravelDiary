import SwiftUI
import Combine

/// A separate in-memory document lets typing preview the real canvas without saving incomplete edits.
@MainActor
final class DiaryTextDraft: ObservableObject {
    let preview: DiaryEditorSession
    let targetID: UUID?
    private var customFont: DiaryFontReference?
    private var customColor: DiaryColor?
    private var initialInputFocusConsumed = false

    func consumeInitialInputFocus() -> Bool {
        guard !initialInputFocusConsumed else { return false }
        initialInputFocusConsumed = true
        return true
    }
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

    private var parentProjection: DiaryProjection {
        var visited = Set<UUID>()
        func find(_ contentID: UUID, _ projection: DiaryProjection) -> DiaryProjection? {
            guard visited.insert(contentID).inserted,
                  let content = preview.document.objects[contentID] else { return nil }
            for candidate in content.layers {
                if candidate.id == layer.id { return projection }
                if let child = candidate.contentID,
                   let found = find(child, projection.multiplied(by: candidate.transform.projection)) { return found }
            }
            return nil
        }
        return find(preview.contentID, DiaryProjection()) ?? DiaryProjection()
    }

    /// The overlay uses page coordinates; persisted text stays in its owner's coordinates.
    var canvasLayer: DiaryLayer {
        var result = layer
        result.transform = mappedTransform(layer.transform, through: parentProjection)
        return result
    }

    func adjustCanvasLayer(_ value: DiaryLayer) {
        var next = value
        next.id = layer.id
        next.text = layer.text
        next.transform = mappedTransform(value.transform, through: parentProjection.inverse)
        layer = next
    }

    private func mappedTransform(_ transform: DiaryTransform, through parent: DiaryProjection) -> DiaryTransform {
        if parent == DiaryProjection() { return transform }
        let projection = parent.multiplied(by: transform.projection)
        let reference = DiaryPageRenderer.textBounds(layer)
        let bounds = projection.bounds(reference)
        guard bounds.width > 0, bounds.height > 0 else { return transform }
        var warp = DiaryQuadWarp(reference: reference)
        warp.corners = reference.diaryCorners.map {
            let point = projection.point($0)
            return CGPoint(x: (point.x - bounds.minX) / bounds.width, y: (point.y - bounds.minY) / bounds.height)
        }
        return DiaryTransform(position: bounds.origin, pivot: reference.origin,
                              stretch: CGSize(width: bounds.width / reference.width, height: bounds.height / reference.height), warp: warp)
    }

    func refresh() {
        var visible = layer
        if visible.text.isEmpty { visible.text = "输入文字" }
        preview.previewTextDraft(visible, targetID: targetID)
        preview.selectedID = layer.id
    }

    func titleLayer(_ layout: DiaryTitleLayout) -> DiaryLayer {
        var next = layer
        var appearance = next.textAppearance ?? DiaryTextAppearance()
        appearance.titleLayout = layout
        appearance.vertical = layout == .vertical
        appearance.bold = layout == .headline
        next.textAppearance = appearance
        next.textAlignment = .center
        next.textLineHeight = layout == .handwriting ? 1.4 : 1.15
        next.textLetterSpacing = layout == .headline ? 1 : 0
        let fontID = layout == .handwriting || layout == .vertical ? "handwriting.lxgw.wenkai" : "system"
        next.font = customFont ?? DiaryFontCatalog.shared.entries.first { $0.id == fontID }?.reference ?? .system
        let canvas = preview.content.referenceSize
        next.size.width = min(900, canvas.width * (layout == .vertical ? 0.18 : 0.72))
        let maximumHeight = canvas.height * (layout == .vertical ? 0.65 : 0.32)
        var low: CGFloat = 12, high: CGFloat = min(240, canvas.width * 0.14)
        for _ in 0..<16 {
            next.fontSize = (low + high) / 2
            let padding = DiaryPageRenderer.textInsets(next)
            let string = next.text.isEmpty ? "输入标题" : DiaryPageRenderer.displayedText(next)
            let measure = (string as NSString).boundingRect(with: CGSize(width: 100000, height: 100000),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: DiaryPageRenderer.textStyle(next), context: nil)
            if measure.width + padding.left + padding.right <= next.size.width && measure.height + padding.top + padding.bottom <= maximumHeight {
                low = next.fontSize
            } else { high = next.fontSize }
        }
        next.fontSize = floor(low)
        return next
    }

    func applyTitle(_ layout: DiaryTitleLayout) { layer = titleLayer(layout) }

    func applySaved(_ style: DiarySavedTextStyle) {
        customFont = style.font
        customColor = style.color
        var next = layer
        next.textAppearance = style.appearance; next.font = style.font; next.textColor = style.color
        next.textAlignment = style.alignment; next.textLineHeight = style.lineHeight
        next.textLetterSpacing = style.letterSpacing; next.fontSize = style.fontSize
        next.size.width = min(style.width, preview.content.referenceSize.width * 0.9)
        layer = next
    }

    func setText(_ text: String) {
        guard layer.text != text else { return }
        layer.text = text
    }

    func selectFont(_ reference: DiaryFontReference) {
        customFont = reference
        layer.font = reference
    }

    func setTextColor(_ color: DiaryColor) {
        customColor = color
        layer.textColor = color
    }

    func setBackgroundColor(_ color: DiaryColor) {
        var next = layer
        var appearance = next.textAppearance ?? DiaryTextAppearance()
        if var paper = appearance.paper {
            paper.color = color
            next.textAppearance = appearance
            next.textAppearance?.paper = paper
        } else {
            appearance.background = color
            next.textAppearance = appearance
        }
        layer = next
    }

    func selectPaper(_ kind: DiaryTextPaper.Kind?) {
        var appearance = layer.textAppearance ?? DiaryTextAppearance()
        if let kind {
            var paper = appearance.paper ?? DiaryTextPaper(color: appearance.background ?? appearance.template.background)
            paper.kind = kind
            appearance.paper = paper
        } else { appearance.paper = nil }
        layer.textAppearance = appearance
    }

    func templateLayer(_ template: DiaryTextTemplate) -> DiaryLayer {
        var next = layer
        next.textAppearance = DiaryTextAppearance(template: template, bold: template == .burst,
            strokeWidth: template == .burst ? 2 : 0)
        next.textColor = customColor ?? template.textColor
        next.textAlignment = .center
        next.textLineHeight = 1.2
        next.textLetterSpacing = 0
        let fontID = template == .postcard || template == .tape ? "handwriting.lxgw.wenkai" : "system"
        next.font = customFont ?? DiaryFontCatalog.shared.entries.first { $0.id == fontID }?.reference ?? .system
        return next
    }

    func apply(_ template: DiaryTextTemplate) { layer = templateLayer(template) }
}
