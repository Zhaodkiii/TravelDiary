import SwiftUI

struct DiaryExplosionCinema: View {
    let photos: [UIImage]
    let stage: String
    let result: UIImage?
    let close: () -> Void
    let pause: (() -> Void)?
    var stickers: [UIImage] = []
    var canvasFrame = CGRect.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var started = Date()
    @State private var ending: Date?
    @State private var suspended: Date?
    @State private var previewResult: UIImage?
    @State private var rendererFailed = false

    private var artwork: UIImage? { result ?? previewResult }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: scenePhase != .active || reduceMotion)) { timeline in
            let time = reduceMotion ? 9 : timeline.date.timeIntervalSince(started)
            let finish = ending.map { reduceMotion ? 5.3 : timeline.date.timeIntervalSince($0) } ?? -1
            ZStack {
                Color(red: 0.008, green: 0.012, blue: 0.035).ignoresSafeArea()
                if rendererFailed || reduceMotion {
                    if let image = artwork ?? photos.first {
                        Image(uiImage: image).resizable().scaledToFit().padding(24)
                    }
                } else {
                    DiaryCosmicSurface(photos: photos, stickers: stickers, result: artwork,
                                       time: time, ending: finish, canvasFrame: canvasFrame, active: scenePhase == .active,
                                       onFailure: { rendererFailed = true })
                        .ignoresSafeArea().accessibilityHidden(true)
                }
                if !reduceMotion && !rendererFailed && finish >= 0 {
                    DiaryTravelAlbumSeal(elapsed: finish)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                VStack {
                    HStack {
                        if pause == nil {
                            Button("重播") {
                                ending = nil; previewResult = nil; started = Date()
                            }
                        }
                        Spacer()
                        Button(pause == nil ? "关闭预览" : "制作详情", action: close)
                    }.font(.subheadline).buttonStyle(.bordered).tint(.white)
                    Spacer()
                    VStack(spacing: 10) {
                        Text(finish >= 2.17 ? "这一程，值得珍藏" : finish >= 0 ? "把这段旅途，收进手账" : "把这段旅途，收进手账")
                            .font(.system(size: 23, weight: .medium, design: .serif))
                        Text(finish >= 0 ? "正在呈现你的作品" : pause == nil ? "持续预览中，点击下方按钮模拟制作完成" : stage)
                            .font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(2)
                        if let pause, finish < 0 { Button("暂停制作", action: pause).font(.caption).tint(.white) }
                        if pause == nil, finish < 0 {
                            Button("预览收拢成册") { previewResult = Self.sampleArtwork(photos); ending = Date() }
                                .font(.caption).buttonStyle(.bordered).tint(.white)
                        }
                    }.foregroundStyle(.white).padding(20)
                        .opacity(finish > 1.25 && finish < 4.82 ? 0 : 1)
                }.padding(.horizontal, 20).padding(.top, 8)
            }
        }
        .task(id: result.map(ObjectIdentifier.init)) {
            guard result != nil else { return }
            ending = Date()
        }
        .task(id: scenePhase == .active ? ending : nil) {
            guard let ending, pause != nil, scenePhase == .active else { return }
            do {
                let duration = reduceMotion || rendererFailed ? 0.9 : 6.92
                try await Task.sleep(for: .seconds(max(0, duration - Date().timeIntervalSince(ending))))
                close()
            } catch {}
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, suspended == nil { suspended = Date() }
            if phase == .active, let suspended {
                let delay = Date().timeIntervalSince(suspended)
                started = started.addingTimeInterval(delay)
                ending = ending?.addingTimeInterval(delay)
                self.suspended = nil
            }
        }
    }

    /// Only settings previews synthesize an example spread. Production always supplies workspace.preview.
    private static func sampleArtwork(_ photos: [UIImage]) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800), format: format).image { output in
            UIColor(red: 0.96, green: 0.93, blue: 0.85, alpha: 1).setFill()
            output.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
            ("TRAVEL MEMORIES" as NSString).draw(at: CGPoint(x: 70, y: 55), withAttributes: [.font: UIFont.systemFont(ofSize: 38, weight: .medium), .foregroundColor: UIColor.darkGray])
            ("动画效果预览" as NSString).draw(at: CGPoint(x: 70, y: 725), withAttributes: [.font: UIFont.systemFont(ofSize: 22), .foregroundColor: UIColor.gray])
            for (index, image) in photos.prefix(4).enumerated() {
                let bounds = CGRect(x: 70 + (index % 2) * 550, y: 145 + (index / 2) * 275, width: 490, height: 245)
                let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height))
            }
        }
    }
}

/// The prints gather behind a tangible album. Only its decorative light bursts outward.
private struct DiaryTravelAlbumSeal: View {
    let elapsed: Double

    private func progress(_ start: Double, _ end: Double) -> Double {
        let t = min(1, max(0, (elapsed - start) / (end - start)))
        return t * t * (3 - 2 * t)
    }

    var body: some View {
        let arrival = progress(0.65, 1.35)
        let opening = progress(1.5, 2.15)
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(red: 0.94, green: 0.88, blue: 0.72))
                .padding(.leading, 4).padding(.vertical, 3)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(.brown.opacity(0.25)).frame(width: 2).padding(.trailing, 5)
                }
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(red: 0.14, green: 0.35, blue: 0.32))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(red: 0.85, green: 0.70, blue: 0.40), lineWidth: 1)
                        .padding(7)
                }
                .overlay {
                    VStack(spacing: 7) {
                        Image(systemName: "sun.max").font(.system(size: 22, weight: .light))
                        Text("旅途珍藏").font(.system(size: 11, weight: .medium, design: .serif))
                    }.foregroundStyle(Color(red: 0.95, green: 0.83, blue: 0.57))
                }
                .rotation3DEffect(.degrees(-opening * 155), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.5)
        }
        .frame(width: 92, height: 118)
        .shadow(color: .black.opacity(0.35), radius: 15, y: 8)
        .scaleEffect(0.72 + arrival * 0.28 + opening * 0.35)
        .offset(y: (1 - arrival) * 24)
        .opacity(arrival * (1 - progress(1.85, 2.3)))
    }
}
