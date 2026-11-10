import SwiftUI
import PhotosUI
import ImageIO

/// A presentation-only clock. Production remains owned by DiaryAIWorkspace.
enum DiaryMakingFilm: String, CaseIterable, Identifiable {
    case explosion, construction, escape, treasure, factory, journey
    var id: String { rawValue }
    var title: String {
        switch self {
        case .explosion: "旅行记忆大爆炸"
        case .construction: "手账施工现场"
        case .escape: "照片逃跑了"
        case .treasure: "从废纸到珍藏"
        case .factory: "记忆加工厂"
        case .journey: "一秒穿越一段旅行"
        }
    }
    var caption: String {
        switch self {
        case .explosion: "让旅行化作星辰，落入你的手账"
        case .construction: "为了这一页，全员出动"
        case .escape: "追上它们，就找到故事的终点"
        case .treasure: "每一片零散，都值得珍藏"
        case .factory: "正在加工一份独一无二的回忆"
        case .journey: "穿过山海，把旅途带回身边"
        }
    }
}

struct DiaryMakingAnimationSettings: View {
    @AppStorage("DiaryMaking.animationEnabled") private var enabled = true
    @AppStorage("DiaryMaking.film") private var film = DiaryMakingFilm.construction
    @State private var preview: DiaryMakingFilm?
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var previewPhotos: [UIImage] = []
    @State private var loadingPhotos = false
    @State private var photoError: String?
    var body: some View {
        Section("制作中动画") {
            Toggle("全屏制作动画", isOn: $enabled)
            Text("关闭后使用原制作页面。动画选择仅影响制作中的展示。")
                .font(.caption).foregroundStyle(.secondary)
            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 8, matching: .images) {
                Label(loadingPhotos ? "正在准备照片" : "选择照片用于动画对比", systemImage: "photo.on.rectangle")
            }
            if !previewPhotos.isEmpty { Text("已选 \(previewPhotos.count) 张照片，六种预览共用").font(.caption) }
            if let photoError { Text(photoError).font(.caption).foregroundStyle(.secondary) }
            ForEach(DiaryMakingFilm.allCases) { option in
                HStack {
                    Button { film = option } label: {
                        Label(option.title, systemImage: film == option ? "checkmark.circle.fill" : "circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                    Button("预览") { preview = option }.buttonStyle(.borderless).disabled(loadingPhotos)
                }
            }
        }
        .task(id: selectedPhotos) {
            guard !selectedPhotos.isEmpty else {
                previewPhotos = []; photoError = nil
                return
            }
            loadingPhotos = true
            defer { loadingPhotos = false }
            var images: [UIImage] = []
            for item in selectedPhotos {
                guard !Task.isCancelled else { return }
                if let data = try? await item.loadTransferable(type: Data.self),
                   let source = CGImageSourceCreateWithData(data as CFData, nil),
                   let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1400
                   ] as CFDictionary) { images.append(UIImage(cgImage: cgImage)) }
            }
            guard !Task.isCancelled else { return }
            previewPhotos = images
            photoError = images.count == selectedPhotos.count ? nil : "部分照片未能读取，请重新选择。"
        }
        .fullScreenCover(item: $preview) { option in
            DiaryMakingCinema(film: option, photos: previewPhotos, stage: "动画预览", close: { preview = nil }, pause: nil)
        }
    }
}

nonisolated struct DiaryMakingCanvasFrameKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

struct DiaryMakingCinemaModifier: ViewModifier {
    @ObservedObject var workspace: DiaryAIWorkspace
    @AppStorage("DiaryMaking.animationEnabled") private var enabled = true
    @AppStorage("DiaryMaking.film") private var film = DiaryMakingFilm.construction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var canvasFrame = CGRect.zero
    @State private var presented = false
    @State private var photos: [UIImage] = []
    @State private var stickers: [UIImage] = []
    @State private var result: UIImage?
    @State private var runFilm = DiaryMakingFilm.construction

    func body(content: Content) -> some View {
        content
        .allowsHitTesting(!presented)
        .accessibilityHidden(presented)
        .overlay {
            ZStack {
                if presented {
                    DiaryMakingCinema(film: runFilm, photos: photos, stage: workspace.stage,
                                      close: dismiss, pause: { dismiss(); workspace.pause() }, result: result, stickers: stickers, canvasFrame: canvasFrame)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(uiColor: .systemBackground))
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.025)))
                        .zIndex(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(presented)
            .animation(.easeInOut(duration: 0.32), value: presented)
        }
        .task(id: "\(workspace.running)-\(workspace.saving)") {
            if workspace.running {
                guard enabled, !presented else { return }
                runFilm = film
                result = nil
                photos = workspace.makingFilmThumbnails
                stickers = workspace.makingFilmStickers
                presented = true
                let prepared = await workspace.makingFilmPhotos()
                guard !Task.isCancelled, presented else { return }
                if !prepared.isEmpty { photos = prepared }
            } else {
                // configureAndStart briefly toggles running before launching the real task.
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled, !workspace.running, !workspace.saving, presented else { return }
                if runFilm == .explosion, workspace.error == nil,
                   workspace.stage != "已暂停",
                   !workspace.hasUnfinishedWork, !workspace.needsSaveRetry,
                   let preview = workspace.preview {
                    result = preview
                } else { dismiss() }
            }
        }
        .onPreferenceChange(DiaryMakingCanvasFrameKey.self) { canvasFrame = $0 }
        .onChange(of: enabled) { _, value in if !value { dismiss() } }
    }

    private func dismiss() {
        presented = false
    }
}

struct DiaryMakingCinema: View {
    let film: DiaryMakingFilm
    let photos: [UIImage]
    let stage: String
    let close: () -> Void
    let pause: (() -> Void)?
    var result: UIImage? = nil
    var stickers: [UIImage] = []
    var canvasFrame = CGRect.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var start = Date()
    private let cream = Color(red: 0.98, green: 0.91, blue: 0.76)
    private let gold = Color(red: 1, green: 0.67, blue: 0.26)

    var body: some View {
        if film == .explosion {
            DiaryExplosionCinema(photos: photos, stage: stage, result: result, close: close, pause: pause, stickers: stickers, canvasFrame: canvasFrame)
        } else {
            legacyBody
        }
    }

    private var legacyBody: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1 / 30, paused: scenePhase != .active || reduceMotion)) { timeline in
                let time = reduceMotion ? 7.0 : timeline.date.timeIntervalSince(start)
                let beat = time.truncatingRemainder(dividingBy: 16)
                ZStack {
                    LinearGradient(colors: [.init(red: 0.035, green: 0.07, blue: 0.13), .init(red: 0.12, green: 0.24, blue: 0.28)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Canvas { context, size in
                        draw(context: context, size: size, time: beat)
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("TRAVEL DIARY / MOTION STUDIO").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2)
                            Spacer()
                            Button(action: close) { Image(systemName: "xmark").padding(14).background(.white.opacity(0.1), in: Circle()) }
                                .accessibilityLabel(pause == nil ? "关闭预览" : "返回制作详情")
                        }
                        Spacer()
                        Text(film.title).font(.system(size: 32, weight: .black, design: .rounded))
                        Text(film.caption).font(.subheadline).foregroundStyle(cream.opacity(0.8))
                        HStack(spacing: 12) {
                            ProgressView().tint(gold)
                            Text(stage).font(.caption).lineLimit(2)
                            Spacer()
                            if let pause { Button("暂停制作", action: pause).font(.caption.bold()).padding(12).background(.white.opacity(0.1), in: Capsule()) }
                        }.padding(.top, 16)
                    }.foregroundStyle(cream).padding(28).padding(.top, geometry.safeAreaInsets.top).padding(.bottom, geometry.safeAreaInsets.bottom + 12)
                }.ignoresSafeArea()
            }
        }.preferredColorScheme(.dark)
    }

    private func draw(context: GraphicsContext, size: CGSize, time t: Double) {
        var c = context
        let scale = min(size.width / 390, size.height / 780)
        c.translateBy(x: size.width / 2, y: size.height * 0.43)
        c.scaleBy(x: scale, y: scale)
        for i in 0..<38 {
            let x = sin(Double(i) * 39.7) * 220
            let y = cos(Double(i) * 17.3) * 310
            c.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(cream.opacity(0.25)))
        }
        // Anticipation → action → hold → resolution. The loop never asserts completion.
        let resolve = ease((t - 12) / 3)
        switch film {
        case .explosion:
            break // Dedicated cinematic scene above.
        case .construction:
            line(from: CGPoint(x: -145, y: 130), to: CGPoint(x: -145, y: -175), color: gold, width: 10, context: c)
            line(from: CGPoint(x: -145, y: -175), to: CGPoint(x: 135, y: -175), color: gold, width: 8, context: c)
            let hookX = 70 * sin(t * 0.6)
            line(from: CGPoint(x: hookX, y: -175), to: CGPoint(x: hookX, y: -65), color: cream, width: 2, context: c)
            card(0, x: hookX, y: -20, rotation: sin(t * 2) * 8 * (1 - resolve), scale: 1.4, context: c)
            for i in 0..<4 {
                let x = -130 + Double(i) * 80 + sin(t * 2 + Double(i)) * 12
                symbol("figure.walk", x: x, y: 130 - abs(sin(t * 4 + Double(i))) * 8, size: 40, color: gold, context: c)
                symbol("cone.fill", x: x, y: 102, size: 20, color: gold, context: c)
            }
            symbol("paintbrush.pointed.fill", x: 100, y: 65 + sin(t * 3) * 25, size: 65, color: .mint, context: c)
        case .escape:
            for i in 0..<5 {
                let x = (Double(i) * 105 + t * 65).truncatingRemainder(dividingBy: 550) - 275
                let jump = abs(sin(t * 4 + Double(i)))
                card(i, x: x, y: 25 - jump * 45, rotation: sin(t * 4 + Double(i)) * 12, scale: 0.8, context: c)
                symbol("figure.run", x: x, y: 88 - jump * 45, size: 34, color: cream, context: c)
            }
            let stamp = -180 + 100 * pow(max(0, sin(t * 1.5)), 8)
            symbol("seal.fill", x: 105, y: stamp, size: 100, color: .pink, context: c)
            line(from: CGPoint(x: -230, y: 140), to: CGPoint(x: 230, y: 140), color: .mint, width: 4, context: c)
        case .treasure:
            let bloom = ease((t - 2) / 5)
            for i in 0..<14 {
                var paper = c
                paper.rotate(by: .degrees(Double(i) * 26 + t * 4))
                let radius = 30 + bloom * 100
                paper.fill(Path(roundedRect: CGRect(x: radius * 0.3, y: -25, width: radius, height: 65), cornerRadius: 8), with: .color((i.isMultiple(of: 2) ? gold : .mint).opacity(0.15 + bloom * 0.65)))
            }
            for i in 0..<4 {
                let a = Double(i) * .pi / 2 + t * 0.15
                card(i, x: cos(a) * 110 * bloom, y: sin(a) * 110 * bloom, rotation: sin(a) * 15, scale: 0.35 + bloom * 0.5, context: c)
            }
        case .factory:
            c.fill(Path(roundedRect: CGRect(x: -145, y: -155, width: 290, height: 280), cornerRadius: 32), with: .color(.mint.opacity(0.14)))
            c.stroke(Path(roundedRect: CGRect(x: -145, y: -155, width: 290, height: 280), cornerRadius: 32), with: .color(.mint.opacity(0.7)), lineWidth: 3)
            for i in 0..<3 {
                var gear = c
                gear.translateBy(x: Double(i - 1) * 85, y: -90)
                gear.rotate(by: .degrees(t * (i.isMultiple(of: 2) ? 70 : -70)))
                symbol("gearshape.fill", x: 0, y: 0, size: 65, color: gold, context: gear)
                let x = (t * 45 + Double(i) * 110).truncatingRemainder(dividingBy: 330) - 165
                card(i, x: x, y: 25, rotation: 0, scale: 0.7, context: c)
            }
            line(from: CGPoint(x: -175, y: 85), to: CGPoint(x: 175, y: 85), color: cream, width: 12, context: c)
            symbol("cloud.fill", x: 120 + sin(t) * 15, y: -180 - t.truncatingRemainder(dividingBy: 3) * 20, size: 35, color: cream.opacity(0.5), context: c)
        case .journey:
            for i in (0..<6).reversed() {
                let depth = (t * 0.22 + Double(i) / 6).truncatingRemainder(dividingBy: 1)
                var portal = c
                portal.scaleBy(x: 0.2 + depth * 3, y: 0.2 + depth * 3)
                portal.stroke(Path(roundedRect: CGRect(x: -95, y: -130, width: 190, height: 260), cornerRadius: 60), with: .color((i.isMultiple(of: 2) ? gold : .mint).opacity(depth)), lineWidth: 3)
            }
            symbol("mountain.2.fill", x: -70, y: 100, size: 170, color: .mint, context: c)
            symbol("sun.max.fill", x: 100, y: -140, size: 65, color: gold, context: c)
            card(Int(t / 3) % max(1, photos.count), x: sin(t * 0.5) * 35, y: -15, rotation: sin(t) * 6, scale: 1.5, context: c)
        }
        if resolve > 0 {
            var book = c
            book.opacity = resolve
            book.fill(Path(roundedRect: CGRect(x: -150, y: -105, width: 300, height: 210), cornerRadius: 12), with: .color(cream))
            line(from: CGPoint(x: 0, y: -95), to: CGPoint(x: 0, y: 95), color: .brown.opacity(0.4), width: 2, context: book)
            for i in 0..<4 { card(i, x: Double(i % 2) * 140 - 70, y: Double(i / 2) * 90 - 45, rotation: Double(i - 2) * 3, scale: 0.58, context: book) }
        }
    }

    private func ease(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return x * x * (3 - 2 * x)
    }
    private func symbol(_ name: String, x: Double, y: Double, size: Double, color: Color, context: GraphicsContext) {
        context.draw(Text(Image(systemName: name)).font(.system(size: size)).foregroundColor(color), at: CGPoint(x: x, y: y))
    }
    private func line(from: CGPoint, to: CGPoint, color: Color, width: Double, context: GraphicsContext) {
        var path = Path(); path.move(to: from); path.addLine(to: to)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
    private func card(_ index: Int, x: Double, y: Double, rotation: Double, scale: Double, context: GraphicsContext) {
        var c = context
        c.translateBy(x: x, y: y); c.rotate(by: .degrees(rotation)); c.scaleBy(x: scale, y: scale)
        c.addFilter(.shadow(color: .black.opacity(0.3), radius: 7, x: 0, y: 5))
        c.fill(Path(roundedRect: CGRect(x: -42, y: -53, width: 84, height: 106), cornerRadius: 3), with: .color(cream))
        if !photos.isEmpty {
            let image = photos[index % photos.count]
            var clipped = c
            let rect = CGRect(x: -36, y: -47, width: 72, height: 80)
            clipped.clip(to: Path(rect))
            let ratio = max(rect.width / image.size.width, rect.height / image.size.height)
            let width = image.size.width * ratio, height = image.size.height * ratio
            clipped.draw(Image(uiImage: image), in: CGRect(x: -width / 2, y: -7 - height / 2, width: width, height: height))
        } else {
            c.fill(Path(CGRect(x: -36, y: -47, width: 72, height: 80)), with: .color(index.isMultiple(of: 2) ? .teal : .indigo))
            symbol("mountain.2.fill", x: 0, y: 0, size: 40, color: gold, context: c)
        }
    }
}
