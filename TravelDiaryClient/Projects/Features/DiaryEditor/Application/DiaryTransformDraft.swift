import Foundation
import CoreGraphics

struct DiaryTransformDraft: Equatable {
    let original: DiaryLayer
    var layer: DiaryLayer
    let reference: CGRect
    var mode: DiaryTransformMode = .free
}

extension DiaryEditorSession {
    var canTransformSelection: Bool {
        guard let selected else { return false }
        return selected.visible && !selected.locked && !selected.isPhotoFrame && selected.kind != .canvas
    }
    func beginFreeTransform() {
        guard transformDraft == nil, canTransformSelection, let selected else { return }
        finishInteraction()
        let bounds=DiaryPageRenderer.bounds(selected, document: document, siblings: scopeLayers)
        transformDraft=DiaryTransformDraft(original: selected, layer: selected, reference: selected.transform.warp?.reference ?? bounds)
    }
    func setTransformMode(_ mode: DiaryTransformMode) { transformDraft?.mode=mode }
    func previewFreeTransform(_ layer: DiaryLayer) {
        guard transformDraft?.layer.id == layer.id, isValidFreeTransform(layer) else { return }
        transformDraft?.layer=layer
    }
    func isValidFreeTransform(_ layer: DiaryLayer) -> Bool {
        guard layer.transform.warp?.isValid != false,
              layer.transform.position.x.isFinite, layer.transform.position.y.isFinite else { return false }
        if let warp = layer.transform.warp {
            var area=DiaryPageRenderer.bounds(layer, document: document, siblings: scopeLayers)
            for frame in scopeLayers where frame.frameTargetID == layer.id {
                area=area.union(DiaryPageRenderer.bounds(frame, document: document, siblings: scopeLayers))
            }
            let weights=area.diaryCorners.map { warp.projection.g*$0.x+warp.projection.h*$0.y+warp.projection.i }
            guard weights.allSatisfy({ $0 > 0.001 }) else { return false }
        }
        return true
    }
    func resetFreeTransform() {
        guard let original=transformDraft?.original else { return }
        transformDraft?.layer=original
    }
    func finishFreeTransform(commit: Bool) {
        guard let draft=transformDraft else { return }
        transformDraft=nil
        if commit { commitTransform(draft.layer) }
    }
}
