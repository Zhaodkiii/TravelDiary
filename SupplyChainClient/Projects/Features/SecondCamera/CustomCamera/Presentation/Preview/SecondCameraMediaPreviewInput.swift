import Foundation
import UIKit

/// SecondCamera 公共预览底座输入。只描述本地图片文件，不依赖业务模块类型。
struct SecondCameraMediaPreviewInput: Identifiable, Equatable, Sendable {
    let id: UUID
    let fileURL: URL
    let displayName: String?

    init(
        id: UUID = UUID(),
        fileURL: URL,
        displayName: String? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.displayName = displayName
    }

    var resolvedDisplayName: String {
        if let displayName, displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return displayName
        }
        let filename = fileURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return filename.isEmpty ? "Image" : filename
    }
}

/// 公共 Viewport 的无业务渲染模型。
struct SecondCameraMediaPreviewDisplayItem: Identifiable {
    let id: UUID
    let title: String?
    let revision: Int
    let thumbnail: UIImage?
    let content: Content

    enum Content {
        case idle
        case loading
        case image(UIImage)
        case video(URL)
        case failure(SecondCameraMediaPreviewLoadError)
    }

    var imageIdentity: String {
        "\(id.uuidString)-\(revision)"
    }
}

/// 公共图片预览加载失败原因。
enum SecondCameraMediaPreviewLoadError: Error, Equatable, Sendable {
    case fileMissing
    case unsupportedType
    case cannotCreateImageSource
    case cannotDecodeImage
    case cancelled

    nonisolated var localizedUserMessage: String {
        switch self {
        case .fileMissing:
            return SecondCameraEditorL10n.PublicPreview.fileMissing
        case .unsupportedType, .cannotCreateImageSource, .cannotDecodeImage, .cancelled:
            return SecondCameraEditorL10n.PublicPreview.imageLoadFailed
        }
    }

    nonisolated var logCode: String {
        switch self {
        case .fileMissing: return "file_missing"
        case .unsupportedType: return "unsupported_type"
        case .cannotCreateImageSource: return "cannot_create_image_source"
        case .cannotDecodeImage: return "cannot_decode_image"
        case .cancelled: return "cancelled"
        }
    }
}

/// 只读预览队列中的单条输入快照项。
struct SecondCameraReadOnlyPreviewItem: Identifiable {
    let id: UUID
    let fileURL: URL
    let displayName: String

    var thumbnail: UIImage?
    var image: UIImage?
    var revision: Int = 0
    var loadState: LoadState = .idle

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(SecondCameraMediaPreviewLoadError)
    }

    var displayItem: SecondCameraMediaPreviewDisplayItem {
        let content: SecondCameraMediaPreviewDisplayItem.Content
        switch loadState {
        case .idle:
            content = .idle
        case .loading:
            content = image.map(SecondCameraMediaPreviewDisplayItem.Content.image) ?? .loading
        case .loaded:
            content = image.map(SecondCameraMediaPreviewDisplayItem.Content.image) ?? .failure(.cannotDecodeImage)
        case .failed(let error):
            content = .failure(error)
        }

        return SecondCameraMediaPreviewDisplayItem(
            id: id,
            title: displayName,
            revision: revision,
            thumbnail: thumbnail,
            content: content
        )
    }
}
