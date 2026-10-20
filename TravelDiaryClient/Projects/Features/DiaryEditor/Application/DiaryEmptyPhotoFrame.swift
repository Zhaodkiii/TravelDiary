import UIKit

nonisolated struct DiaryEmptyPhotoFrameTarget: Equatable, Sendable {
    let selectionID: UUID
    let ownerID: UUID
    let frameID: UUID
}

extension DiaryEditorSession {
    var selectedEmptyPhotoFrameTarget: DiaryEmptyPhotoFrameTarget? {
        selectedID.flatMap { emptyPhotoFrameTarget(for: $0) }
    }

    /// 从语义识别空相框，不通过名称猜测；多个相框或任何已有照片都需要用户明确选择。
    func emptyPhotoFrameTarget(for selectionID: UUID) -> DiaryEmptyPhotoFrameTarget? {
        guard let selection = editableLayer(selectionID), !selection.locked else { return nil }
        var visited = Set<UUID>(), frames: [(UUID, UUID)] = []
        var hasPhoto = false
        func visit(_ layer: DiaryLayer, ownerID: UUID, locked: Bool) {
            if layer.isContentPhoto { hasPhoto = true }
            let protected = locked || layer.locked
            if !protected, layer.contentID == nil, layer.assetID != nil, layer.frameTargetID == nil,
               layer.subcategory == "frame", (layer.semanticKind == .photo || layer.isPhotoFrame) {
                frames.append((ownerID, layer.id))
            }
            if let child = layer.contentID, visited.insert(child).inserted, let content = document.objects[child] {
                for item in content.layers { visit(item, ownerID: child, locked: protected) }
            }
        }
        guard let owner = document.objects.values.first(where: { $0.layers.contains { $0.id == selectionID } }) else { return nil }
        visit(selection, ownerID: owner.id, locked: false)
        guard !hasPhoto, frames.count == 1 else { return nil }
        return DiaryEmptyPhotoFrameTarget(selectionID: selectionID, ownerID: frames[0].0, frameID: frames[0].1)
    }

}
