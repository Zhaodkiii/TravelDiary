import Foundation
import UIKit

/// 多图预览队列中的单条媒体，各自持有独立编辑状态，避免切图串改。
struct SecondCameraPreviewItem: Identifiable {
    enum Source: Equatable {
        case camera
        case systemLibrary(assetIdentifier: String?)
    }

    let id: UUID
    let source: Source
    var media: CustomCameraMedia

    var editableImage: UIImage?
    var editorModel: SecondCameraImageEditorModel?
    var approvalItem: SecondCameraAttachmentApprovalItem?
    var imageOutputOptions: SecondCameraImageOutputOptions
    var renderedPreviewImage: UIImage?
    var thumbnail: UIImage?
    /// 编辑 / 裁剪 / 质量切换后递增，驱动 UIKit 预览刷新与缩放重置。
    var previewRevision: Int = 0

    init(
        id: UUID = UUID(),
        source: Source,
        media: CustomCameraMedia,
        imageOutputOptions: SecondCameraImageOutputOptions = SecondCameraImageOutputOptions(),
        thumbnail: UIImage? = nil
    ) {
        self.id = id
        self.source = source
        self.media = media
        self.imageOutputOptions = imageOutputOptions
        self.thumbnail = thumbnail ?? SecondCameraPreviewThumbnailBuilder.makeThumbnail(from: media)
        self.editableImage = media.getImage()
        self.renderedPreviewImage = media.getImage()
    }

    var isImage: Bool { media.getImage() != nil }
    var isVideo: Bool { media.getVideo() != nil }

    var displayImage: UIImage? {
        renderedPreviewImage ?? editableImage ?? media.getImage() ?? thumbnail
    }

    /// SwiftUI / UIKit bridge 用的稳定预览身份：多图切换 + 同图编辑刷新。
    var previewImageIdentity: String {
        "\(id.uuidString)-\(previewRevision)"
    }

    mutating func bumpPreviewRevision() {
        previewRevision += 1
    }

    /// 映射为公共 Viewport 显示模型，保持 id / revision 身份规则。
    var asMediaPreviewDisplayItem: SecondCameraMediaPreviewDisplayItem {
        let content: SecondCameraMediaPreviewDisplayItem.Content
        if let image = displayImage {
            content = .image(image)
        } else if let video = media.getVideo() {
            content = .video(video)
        } else {
            content = .idle
        }
        return SecondCameraMediaPreviewDisplayItem(
            id: id,
            title: nil,
            revision: previewRevision,
            thumbnail: thumbnail,
            content: content
        )
    }
}

extension SecondCameraPreviewItem: Equatable {
    static func == (lhs: SecondCameraPreviewItem, rhs: SecondCameraPreviewItem) -> Bool {
        lhs.id == rhs.id
    }
}
