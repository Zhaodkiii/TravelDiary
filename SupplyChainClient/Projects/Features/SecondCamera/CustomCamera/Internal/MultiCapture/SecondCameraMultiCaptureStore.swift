import Combine
import Foundation
import UIKit

/// 多图预览会话状态。挂在相机生命周期上，继续拍摄时预览页销毁也不丢队列。
@MainActor
final class SecondCameraMultiCaptureStore: ObservableObject {
    static let maxCount = 10

    @Published private(set) var items: [SecondCameraPreviewItem] = []
    @Published private(set) var selectedID: UUID?

    var selectedItem: SecondCameraPreviewItem? {
        if let selectedID {
            return items.first(where: { $0.id == selectedID })
        }
        return items.first
    }

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }
    /// 允许删除当前选中项；删到空队列时由预览页退出。
    var canRemoveSelected: Bool { !isEmpty }
    var canAddMore: Bool { count < Self.maxCount }
    var remainingCapacity: Int { max(0, Self.maxCount - count) }

    /// 拍照追加；选中新拍图片，便于立刻确认。
    func appendCamera(_ media: CustomCameraMedia) {
        guard canAddMore else { return }
        let item = SecondCameraPreviewItem(source: .camera, media: media)
        items.append(item)
        selectedID = item.id
    }

    /// 相册追加；按选择顺序写入，并选中第一张新增图。
    func appendLibrary(_ picked: [SecondCameraPickedMedia]) {
        guard !picked.isEmpty else { return }

        let before = count
        var firstNewID: UUID?
        var added = 0
        for media in picked {
            guard canAddMore else { break }
            guard let cameraMedia = media.customCameraMedia else { continue }

            let source: SecondCameraPreviewItem.Source
            switch media {
            case .image(_, let assetIdentifier), .video(_, let assetIdentifier):
                source = .systemLibrary(assetIdentifier: assetIdentifier)
            }

            let item = SecondCameraPreviewItem(source: source, media: cameraMedia)
            items.append(item)
            added += 1
            if firstNewID == nil {
                firstNewID = item.id
            }
        }

        if let firstNewID {
            selectedID = firstNewID
        } else if selectedID == nil {
            selectedID = items.first?.id
        }

        SparkLogger.log(
            level: .info,
            module: .camera,
            message: "SecondCameraMultiCaptureStore appendLibrary before=\(before) added=\(added) after=\(count) selectedID=\(selectedID?.uuidString ?? "nil")"
        )
    }

    func select(id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    /// 删除后自动选中相邻项；队列为空时 `selectedID` 置空。
    func remove(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: idx)
        if selectedID == id {
            if items.isEmpty {
                selectedID = nil
            } else {
                selectedID = items[min(idx, items.count - 1)].id
            }
        }
    }

    func updateSelected(_ mutation: (inout SecondCameraPreviewItem) -> Void) {
        guard let selectedID,
              let idx = items.firstIndex(where: { $0.id == selectedID })
        else { return }
        mutation(&items[idx])
    }

    func updateItem(id: UUID, _ mutation: (inout SecondCameraPreviewItem) -> Void) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        mutation(&items[idx])
    }

    func clear() {
        items.removeAll()
        selectedID = nil
    }
}
