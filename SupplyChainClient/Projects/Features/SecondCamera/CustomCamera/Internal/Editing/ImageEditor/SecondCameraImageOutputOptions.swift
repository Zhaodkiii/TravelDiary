import UIKit

enum SecondCameraImageOutputFormat {
    case jpeg
    case png
}

enum SecondCameraImageSizePreset {
    case original
    case large4096
    case standard2048
    case small1280
    case custom

    var maxLongEdge: CGFloat? {
        switch self {
        case .original: return nil
        case .large4096: return 4096
        case .standard2048: return 2048
        case .small1280: return 1280
        case .custom: return nil
        }
    }
}

enum SecondCameraEditorImageQualityPreset: CaseIterable {
    case original
    case high
    case standard
    case compressed

    var jpegQuality: CGFloat? {
        switch self {
        case .original: return nil
        case .high: return 0.92
        case .standard: return 0.85
        case .compressed: return 0.72
        }
    }

    var defaultSizePreset: SecondCameraImageSizePreset {
        switch self {
        case .original: return .original
        case .high: return .large4096
        case .standard: return .standard2048
        case .compressed: return .small1280
        }
    }

    var localizedTitle: String {
        switch self {
        case .original: return SecondCameraEditorL10n.Quality.original
        case .high: return SecondCameraEditorL10n.Quality.high
        case .standard: return SecondCameraEditorL10n.Quality.standard
        case .compressed: return SecondCameraEditorL10n.Quality.compressed
        }
    }
}

struct SecondCameraImageOutputOptions {
    var sizePreset: SecondCameraImageSizePreset = .original
    var customPixelSize: CGSize?
    var quality: SecondCameraEditorImageQualityPreset = .original
    var preserveMetadata: Bool = false
    var outputFormat: SecondCameraImageOutputFormat = .jpeg

    mutating func applySecondCameraQualityPreset(_ preset: SecondCameraEditorImageQualityPreset) {
        quality = preset
        if sizePreset == .original || sizePreset == preset.defaultSizePreset {
            sizePreset = preset.defaultSizePreset
        }
    }
}

struct SecondCameraMediaMetadata {
    let pixelSize: CGSize
    let fileSize: Int64?
    let uti: String?
    let mimeType: String?
    let outputOptions: SecondCameraImageOutputOptions?
}
