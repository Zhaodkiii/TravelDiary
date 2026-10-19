import Foundation
import CoreGraphics

nonisolated struct DiaryVideoOptions: Equatable, Sendable {
    enum Frame: String, CaseIterable, Identifiable, Sendable {
        case landscape, portrait
        var id: Self { self }
        var title: String { self == .landscape ? "横屏 16:9" : "竖屏 9:16" }
        var size: CGSize { self == .landscape ? CGSize(width: 1920, height: 1080) : CGSize(width: 1080, height: 1920) }
    }
    enum Speed: Int, CaseIterable, Identifiable, Sendable {
        case quick = 2, gentle = 3, reading = 5
        var id: Self { self }
        var title: String {
            switch self { case .quick: "轻快 · 2 秒"; case .gentle: "舒缓 · 3 秒"; case .reading: "细读 · 5 秒" }
        }
    }
    var frame: Frame = .landscape
    var speed: Speed = .gentle
    /// Zero-based inclusive spread range, preserving the physical front/back order.
    var firstSpread = 0
    var lastSpread = 0
    var timeline: DiaryVideoTimeline { DiaryVideoTimeline(spreadCount: lastSpread - firstSpread + 1, hold: Double(speed.rawValue)) }
}

/// Integer frame boundaries make preview, encoding and duration agree exactly.
nonisolated struct DiaryVideoTimeline: Sendable {
    struct Sample: Sendable {
        let spread: Int
        let next: Int?
        let turn: Double
        let intro: Bool
        let opacity: Double
    }
    let spreadCount: Int
    let hold: Double
    let fps = 30
    let introFrames = 60
    let turnFrames = 24
    let outroFrames = 30
    var holdFrames: Int { max(1, Int(hold * Double(fps))) }
    var frameCount: Int { introFrames + max(1, spreadCount) * holdFrames + max(0, spreadCount - 1) * turnFrames + outroFrames }
    var duration: Double { Double(frameCount) / Double(fps) }

    func sample(at seconds: Double) -> Sample {
        let safeSeconds = seconds.isFinite ? max(0, min(seconds, duration)) : 0
        return sample(frame: Int((safeSeconds * Double(fps) + 0.000001).rounded(.down)))
    }

    func sample(frame requested: Int) -> Sample {
        let frame = max(0, min(frameCount - 1, requested))
        if frame < introFrames {
            return Sample(spread: 0, next: nil, turn: 0, intro: true, opacity: min(1, Double(frame) / 15))
        }
        let local = frame - introFrames
        let span = holdFrames + turnFrames
        let spread = min(max(0, spreadCount - 1), local / span)
        let offset = local - spread * span
        if spread < spreadCount - 1 && offset >= holdFrames {
            return Sample(spread: spread, next: spread + 1,
                          turn: Double(offset - holdFrames) / Double(turnFrames), intro: false, opacity: 1)
        }
        // Keep the final frame visible; the ending rests on the last spread.
        return Sample(spread: spread, next: nil, turn: 0, intro: false, opacity: 1)
    }
}
