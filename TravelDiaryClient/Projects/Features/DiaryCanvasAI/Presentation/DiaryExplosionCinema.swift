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
                        Text(finish >= 0 ? "星辰落下，回忆成册" : time < 5 ? "让回忆，化作星辰" : "你的旅途，正在凝聚")
                            .font(.system(size: 23, weight: .medium, design: .serif))
                        Text(finish >= 0 ? "正在呈现你的作品" : pause == nil ? "动画预览" : stage)
                            .font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(2)
                        if let pause, finish < 0 { Button("暂停制作", action: pause).font(.caption).tint(.white) }
                        if pause == nil, finish < 0 {
                            Button("预览星辰落定") { previewResult = Self.sampleArtwork(photos); ending = Date() }
                                .font(.caption).buttonStyle(.bordered).tint(.white)
                        }
                    }.foregroundStyle(.white).padding(20)
                        .opacity(finish > 0.4 && finish < 3.8 ? 0 : 1)
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
                let duration = reduceMotion || rendererFailed ? 0.9 : 5.9
                try await Task.sleep(for: .seconds(max(0, duration - Date().timeIntervalSince(ending))))
                close()
            } catch {}
        }
        .task(id: started) {
            guard pause == nil else { return }
            do {
                try await Task.sleep(for: .seconds(reduceMotion ? 1 : 12))
                guard previewResult == nil else { return }
                previewResult = Self.sampleArtwork(photos)
                ending = Date()
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
