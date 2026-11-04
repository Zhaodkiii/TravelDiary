import SwiftUI
import Combine
import UIKit
import AVFoundation

/// Transient presentation only. Never written into the document or preview cache.
struct DiaryReadingPresentation {
    struct Appearance {
        var opacity: CGFloat
        var offset: CGFloat = 0
        var characters: Int? = nil
    }
    var states: [UUID: Appearance] = [:]
    var showsInk = false
}

@MainActor
final class DiaryReadingPlayback: ObservableObject {
    enum Phase { case background, playing, complete }
    @Published var phase: Phase = .background
    var began: CFTimeInterval = 0
    func prepare() { phase = .background }
    func play(at time: CFTimeInterval) {
        began = time
        phase = UIAccessibility.isReduceMotionEnabled || !UserDefaults.standard.bool(forKey: "diary.reader.animation") ? .complete : .playing
    }
    func finish() { phase = .complete }
    init() {
        UserDefaults.standard.register(defaults: ["diary.reader.animation": true, "diary.reader.haptics": true])
    }
}

/// The schedule preserves source z-order; only start times are sorted.
@MainActor
struct DiaryReadingPlan {
    struct Unit {
        var ids: [UUID]
        var rank: Int
        var characters: Int
        var start: Double = 0
        var duration: Double = 0.3
    }
    var units: [Unit] = []
    var duration: Double = 0
    init(document: DiaryDocument) {
        var visited = Set<UUID>()
        func visit(_ id: UUID, inherited: DiaryLayerSemanticKind?) {
            guard visited.insert(id).inserted, let content = document.objects[id] else { return }
            if id != document.rootContentID, content.background != nil, inherited != .background {
                units.append(Unit(ids: [id], rank: 0, characters: 0))
            }
            for layer in content.layers where layer.visible {
                let kind = layer.semanticKind ?? (layer.isLibraryBackground == true ? .background : inherited)
                if let child = layer.contentID, layer.transform.warp == nil {
                    visit(child, inherited: kind)
                    continue
                }
                if kind == .background { continue }
                if let target = layer.frameTargetID, content.layers.contains(where: { $0.id == target && $0.visible }) { continue }
                let text = layer.kind == .text || layer.category == .textImage || kind == .text
                let rank = text ? 1 : (layer.isContentPhoto || kind == .photo) ? 2 : kind == .paper ? 0 : (layer.kind == .sticker || kind == .illustration) ? 3 : 4
                let frames = content.layers.filter { $0.visible && $0.frameTargetID == layer.id }.map(\.id)
                units.append(Unit(ids: [layer.id] + frames, rank: rank,
                                  characters: layer.kind == .text ? DiaryPageRenderer.displayedText(layer).count : 0))
            }
        }
        visit(document.rootContentID, inherited: nil)
        units = units.enumerated().sorted {
            $0.element.rank == $1.element.rank ? $0.offset < $1.offset : $0.element.rank < $1.element.rank
        }.map(\.element)
        var cursor = 0.0
        let stagger = min(0.16, 2.0 / Double(max(1, units.count)))
        var previousRank = -1
        var stageEnd = 0.0
        for index in units.indices {
            if units[index].rank != previousRank {
                cursor = max(cursor, stageEnd)
                previousRank = units[index].rank
            }
            units[index].start = cursor
            units[index].duration = units[index].characters > 0 ? min(1.8, max(0.25, Double(units[index].characters) * 0.065)) : units[index].rank == 2 ? 0.5 : 0.35
            stageEnd = max(stageEnd, cursor + units[index].duration)
            cursor += stagger
        }
        let scale = min(1, 4.2 / max(0.001, stageEnd))
        for index in units.indices {
            units[index].start *= scale
            units[index].duration *= scale
        }
        duration = stageEnd * scale + 0.15
    }
    func presentation(at time: Double) -> DiaryReadingPresentation {
        var value = DiaryReadingPresentation()
        value.showsInk = time >= duration
        for unit in units {
            let progress = min(1, max(0, (time - unit.start) / unit.duration))
            let eased = 1 - pow(1 - progress, 3)
            let distance: CGFloat = unit.rank == 2 ? 10 : unit.rank == 3 ? 4 : 0
            let count = unit.characters > 0 ? Int(Double(unit.characters) * progress) : nil
            let state = DiaryReadingPresentation.Appearance(opacity: count == nil ? eased : (progress > 0 ? 1 : 0),
                offset: -distance * (1 - eased), characters: count)
            for id in unit.ids { value.states[id] = state }
        }
        return value
    }
}

/// Global throttle prevents both halves of a spread from doubling feedback.
@MainActor
private final class DiaryReadingFeedback {
    static let shared = DiaryReadingFeedback()
    private let text = UIImpactFeedbackGenerator(style: .light)
    private let photo = UIImpactFeedbackGenerator(style: .soft)
    private let sticker = UIImpactFeedbackGenerator(style: .rigid)
    private var last: CFTimeInterval = 0
    private var player: AVAudioPlayer?
    func prepare() { text.prepare(); photo.prepare(); sticker.prepare() }
    func pulse(rank: Int) {
        guard UIApplication.shared.applicationState == .active else { return }
        let now = CACurrentMediaTime()
        guard now - last >= 0.16 else { return }
        last = now
        if UserDefaults.standard.bool(forKey: "diary.reader.haptics") {
            let generator = rank == 1 ? text : rank == 2 ? photo : sticker
            generator.impactOccurred(intensity: rank == 2 ? 0.65 : 0.35)
            generator.prepare()
        }
        if UserDefaults.standard.bool(forKey: "diary.reader.sound"), rank != 1 {
            // Quiet, short paper-like noise; ambient category respects silent mode and other audio.
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            let samples = 1323
            var data = Data()
            func bytes<T>(_ value: T) { var value = value; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
            data.append(Data("RIFF".utf8)); bytes(UInt32(36 + samples * 2).littleEndian)
            data.append(Data("WAVEfmt ".utf8)); bytes(UInt32(16).littleEndian)
            bytes(UInt16(1).littleEndian); bytes(UInt16(1).littleEndian); bytes(UInt32(22050).littleEndian)
            bytes(UInt32(44100).littleEndian); bytes(UInt16(2).littleEndian); bytes(UInt16(16).littleEndian)
            data.append(Data("data".utf8)); bytes(UInt32(samples * 2).littleEndian)
            var seed: UInt32 = 17
            for n in 0..<samples {
                seed = seed &* 1664525 &+ 1013904223
                let noise = Double(seed & 65535) / 32768 - 1
                let envelope = pow(1 - Double(n) / Double(samples), 4)
                bytes(Int16(noise * envelope * 1400).littleEndian)
            }
            player = try? AVAudioPlayer(data: data); player?.play()
        }
    }
    func stop() { player?.stop() }
}

/// Both halves share decoded assets. Bound memory independently of the number of pages in the book.
@MainActor
enum DiaryReadingSources {
    final class Box {
        let source: DiaryDocumentStore.Loaded
        init(_ source: DiaryDocumentStore.Loaded) { self.source = source }
    }
    static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 6; cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()
    static var pending: [String: Task<DiaryDocumentStore.Loaded, Error>] = [:]
    static func cached(page: DiaryPageEntry, store: DiaryDocumentStore) -> DiaryDocumentStore.Loaded? {
        cache.object(forKey: "\(store.previewScope)-\(page.id)-\(page.revisionID)" as NSString)?.source
    }

    static func load(page: DiaryPageEntry, store: DiaryDocumentStore) async throws -> DiaryDocumentStore.Loaded {
        let key = "\(store.previewScope)-\(page.id)-\(page.revisionID)"
        if let value = cache.object(forKey: key as NSString) { return value.source }
        let task: Task<DiaryDocumentStore.Loaded, Error>
        if let current = pending[key] { task = current }
        else {
            task = Task {
                defer { pending[key] = nil }
                let source = try await store.loadPreviewSource(page, large: true, compositePhotos: true)
                let cost = source.images.values.reduce(0) { $0 + ($1.cgImage?.bytesPerRow ?? 0) * ($1.cgImage?.height ?? 0) }
                cache.setObject(Box(source), forKey: key as NSString, cost: cost)
                return source
            }
            pending[key] = task
        }
        let source = try await task.value
        try Task.checkCancellation()
        return source
    }
}

struct DiaryAnimatedReadingPage: View {
    let page: DiaryPageEntry
    let store: DiaryDocumentStore
    let half: Bool?
    @ObservedObject var playback: DiaryReadingPlayback
    @State private var source: DiaryDocumentStore.Loaded?
    @State private var failed = false
    init(page: DiaryPageEntry, store: DiaryDocumentStore, half: Bool?, playback: DiaryReadingPlayback) {
        self.page = page; self.store = store; self.half = half; self.playback = playback
        _source = State(initialValue: DiaryReadingSources.cached(page: page, store: store))
    }
    var body: some View {
        Group {
            if let source {
                DiaryReadingSurface(source: source, half: half, phase: playback.phase, began: playback.began)
            } else {
                GeometryReader { geometry in
                    DiaryPagePreview(page: page, store: store, large: true, undecorated: true)
                        .frame(width: geometry.size.width * (half == nil ? 1 : 2), height: geometry.size.height)
                        .offset(x: half == false ? -geometry.size.width : 0)
                }.clipped()
            }
        }
        .task(id: "\(page.id)-\(page.revisionID)") {
            do {
                let loaded = try await DiaryReadingSources.load(page: page, store: store)
                try Task.checkCancellation()
                source = loaded
            } catch is CancellationError {} catch { failed = true }
        }
    }
}

@MainActor
protocol DiaryReadingSurfaceControlling: AnyObject {
    func update(phase: DiaryReadingPlayback.Phase, began: CFTimeInterval)
}

private struct DiaryReadingSurface: UIViewRepresentable {
    let source: DiaryDocumentStore.Loaded
    let half: Bool?
    let phase: DiaryReadingPlayback.Phase
    let began: CFTimeInterval
    func makeUIView(context: Context) -> Surface { Surface(source: source, half: half) }
    func updateUIView(_ view: Surface, context: Context) { view.update(phase: phase, began: began) }
    static func dismantleUIView(_ view: Surface, coordinator: ()) { view.stop() }

    final class Surface: UIView, DiaryReadingSurfaceControlling {
        let source: DiaryDocumentStore.Loaded
        let half: Bool?
        let plan: DiaryReadingPlan
        var phase: DiaryReadingPlayback.Phase = .background
        var began: CFTimeInterval = 0
        var link: CADisplayLink?
        var feedbackSteps: [Int: Int] = [:]
        init(source: DiaryDocumentStore.Loaded, half: Bool?) {
            self.source = source; self.half = half; self.plan = DiaryReadingPlan(document: source.document)
            super.init(frame: .zero)
            isOpaque = false; backgroundColor = .clear; isUserInteractionEnabled = false
            contentMode = .redraw
        }
        required init?(coder: NSCoder) { fatalError("No storyboard") }
        func update(phase: DiaryReadingPlayback.Phase, began: CFTimeInterval) {
            guard self.phase != phase || self.began != began else { return }
            stop(); self.phase = phase; self.began = began; feedbackSteps = [:]
            if phase == .playing, CACurrentMediaTime() - began < plan.duration {
                DiaryReadingFeedback.shared.prepare()
                let link = CADisplayLink(target: self, selector: #selector(tick))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 30)
                link.add(to: .main, forMode: .common); self.link = link
            }
            setNeedsDisplay()
        }
        func stop() { link?.invalidate(); link = nil; DiaryReadingFeedback.shared.stop() }
        override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { stop() } }
        @objc func tick() {
            guard window != nil, UIApplication.shared.applicationState == .active else { stop(); return }
            if UIAccessibility.isReduceMotionEnabled || !UserDefaults.standard.bool(forKey: "diary.reader.animation") {
                phase = .complete; stop(); setNeedsDisplay(); return
            }
            let time = CACurrentMediaTime() - began
            if time >= plan.duration { stop(); setNeedsDisplay(); return }
            // A full-spread document is rendered twice, but produces feedback only once.
            if half != false {
                for (index, unit) in plan.units.enumerated() where time >= unit.start {
                    let progress = min(1, max(0, (time - unit.start) / unit.duration))
                    let step = unit.characters > 0 ? Int(Double(unit.characters) * progress) : progress >= 0.7 ? 1 : 0
                    if step > (feedbackSteps[index] ?? 0) {
                        feedbackSteps[index] = step
                        if unit.rank < 4 { DiaryReadingFeedback.shared.pulse(rank: unit.rank) }
                    }
                }
            }
            setNeedsDisplay()
        }
        override func draw(_ rect: CGRect) {
            guard let context = UIGraphicsGetCurrentContext(), bounds.width > 0, bounds.height > 0 else { return }
            let size = source.document.root.referenceSize
            let width = half == nil ? size.width : size.width / 2
            context.saveGState(); defer { context.restoreGState() }
            context.scaleBy(x: bounds.width / width, y: bounds.height / size.height)
            if half == false { context.translateBy(x: -size.width / 2, y: 0) }
            let time = phase == .background ? -1 : CACurrentMediaTime() - began
            let presentation = phase == .complete || time >= plan.duration ? nil : plan.presentation(at: time)
            DiaryPageRenderer.draw(source.document, images: source.images, in: context, cacheObjects: presentation == nil, presentation: presentation)
        }
    }
}
