import Foundation

enum SecondCameraEditorOperation {
    static func formattedNs(_ nanoseconds: UInt64) -> String {
        let seconds = Double(nanoseconds) / 1_000_000_000
        return String(format: "%.3fs", seconds)
    }
}
