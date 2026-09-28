import Foundation

enum SecondCameraPhotoLibraryError: LocalizedError {
    case emptySelection
    case unsupportedType
    case imageLoadFailed
    case videoLoadFailed
    case videoCopyFailed
    case mediaBuildFailed

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "未选择媒体"
        case .unsupportedType:
            return "暂不支持该媒体类型"
        case .imageLoadFailed:
            return "图片读取失败"
        case .videoLoadFailed:
            return "视频读取失败"
        case .videoCopyFailed:
            return "视频复制失败"
        case .mediaBuildFailed:
            return "媒体生成失败"
        }
    }
}
