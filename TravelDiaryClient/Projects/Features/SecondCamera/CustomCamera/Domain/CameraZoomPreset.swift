import AVFoundation
import Foundation

internal struct CameraZoomPreset: Identifiable, Equatable {
    enum Kind: Equatable {
        case ultraWide
        case wide
        case telephoto
        case custom
    }

    let id: String
    let kind: Kind
    let displayZoomFactor: CGFloat
    let deviceZoomFactor: CGFloat
}

extension CameraZoomPreset {
    static func zoomLabel(
        displayZoomFactor: CGFloat,
        currentDisplayZoomFactor: CGFloat,
        isSelected: Bool
    ) -> String {
        let value = isSelected ? currentDisplayZoomFactor : displayZoomFactor
        let adjusted = floor(value * 10) / 10

        if adjusted < 1 {
            return isSelected ? "0.5×" : ".5"
        }
        if adjusted.rounded() == adjusted {
            return "\(Int(adjusted))" + (isSelected ? "×" : "")
        }
        return String(format: "%.1f", adjusted) + (isSelected ? "×" : "")
    }
}
