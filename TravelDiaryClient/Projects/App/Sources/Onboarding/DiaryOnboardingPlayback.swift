import SwiftUI
import Observation

/// The guide owns its playback state; the editable document is never mutated.
@MainActor @Observable
final class DiaryOnboardingAssembly {
    enum Phase: Equatable { case loading, blank, floating, binding, revealing, complete, turning, failed }
    struct Piece: Identifiable {
        let id: UUID
        let image: UIImage
        let rect: CGRect
        let photo: Bool
        let text: Bool
        var floatingIndex: Int?
    }
    struct Paper {
        let size: CGSize
        let background: UIImage
        let assembled: UIImage
        let complete: UIImage
        let pieces: [Piece]
    }
    private(set) var papers: [Paper] = []
    private(set) var phase: Phase = .loading
    private(set) var displayed: Int
    private(set) var completed: Set<Int> = []
    private var animationTask: Task<Void, Never>?
    private var generation = 0
    var reduceMotion = false

    private static let bundledPlayback: [Paper]? = {
        guard let root = Bundle.main.url(forResource: "OnboardingThemes", withExtension: "bundle") else { return nil }
        return try? readPlayback(from: root.appendingPathComponent("Playback"))
    }()

    init(initialSpread: Int = 0, usePreparedPlayback: Bool = true) {
        displayed = initialSpread
        // Fixed onboarding art is baked ahead of shipping, never composed on first launch.
        if usePreparedPlayback, let cached = Self.bundledPlayback {
            papers = cached
            phase = .floating
        }
    }

    struct PlaybackIndex: Codable {
        let version: Int
        let pages: [Page]
        struct Page: Codable {
            let size: CGSize
            let pieces: [Part]
        }
        struct Part: Codable {
            let id: UUID
            let rect: CGRect
            let photo: Bool
            let text: Bool
            let floatingIndex: Int?
        }
    }

    static func readPlayback(from root: URL) throws -> [Paper] {
        let index = try JSONDecoder().decode(PlaybackIndex.self, from: Data(contentsOf: root.appendingPathComponent("index.json")))
        guard index.version == 1, index.pages.count == 8 else { throw DiaryEditorError.invalidDocument }
        func image(_ name: String) throws -> UIImage {
            guard let image = UIImage(contentsOfFile: root.appendingPathComponent(name + (name.contains("-piece-") ? ".png" : ".jpg")).path) else {
                throw DiaryEditorError.missingResource
            }
            return image
        }
        return try index.pages.enumerated().map { page, info in
            let pieces = try info.pieces.enumerated().map { part, meta in
                Piece(id: meta.id, image: try image("\(page)-piece-\(part)"), rect: meta.rect,
                      photo: meta.photo, text: meta.text, floatingIndex: meta.floatingIndex)
            }
            return Paper(size: info.size, background: try image("\(page)-background"),
                         assembled: try image("\(page)-assembled"), complete: try image("\(page)-complete"), pieces: pieces)
        }
    }

    #if DEBUG
    /// Regenerate after changing the bundled templates or the rendering rules.
    func exportPlayback(to root: URL) throws {
        guard papers.count == 8 else { throw DiaryEditorError.invalidDocument }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        func write(_ image: UIImage, _ name: String) throws {
            let isPiece = name.contains("-piece-")
            guard let data = isPiece ? image.pngData() : image.jpegData(compressionQuality: 0.9) else { throw DiaryEditorError.missingResource }
            try data.write(to: root.appendingPathComponent(name + (isPiece ? ".png" : ".jpg")), options: .atomic)
        }
        for (page, paper) in papers.enumerated() {
            try write(paper.background, "\(page)-background")
            try write(paper.assembled, "\(page)-assembled")
            try write(paper.complete, "\(page)-complete")
            for (part, piece) in paper.pieces.enumerated() { try write(piece.image, "\(page)-piece-\(part)") }
        }
        let index = PlaybackIndex(version: 1, pages: papers.map { paper in
            PlaybackIndex.Page(size: paper.size, pieces: paper.pieces.map {
                PlaybackIndex.Part(id: $0.id, rect: $0.rect, photo: $0.photo, text: $0.text, floatingIndex: $0.floatingIndex)
            })
        })
        try JSONEncoder().encode(index).write(to: root.appendingPathComponent("index.json"), options: .atomic)
    }
    #endif
    var showsCopy: Bool { phase == .complete || phase == .failed }
    var canAct: Bool { phase == .floating || phase == .complete || phase == .failed }
    var canNavigate: Bool { canAct }
    var buttonTitle: String {
        switch phase {
        case .loading: "正在打开手帐…"
        case .blank, .turning: "正在翻页…"
        case .binding, .revealing: "正在装订…"
        case .floating: "装订这一页"
        case .complete, .failed: "下一步"
        }
    }

    func load() async {
        guard papers.isEmpty, phase == .loading else { return }
        do {
            guard let root = Bundle.main.url(forResource: "OnboardingThemes", withExtension: "bundle") else { throw DiaryEditorError.missingResource }
            let manifest = try JSONDecoder().decode(PresetManifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
            let package = DiaryPresetPackage(root: root, manifest: manifest)
            let sourcePages = Dictionary(uniqueKeysWithValues: try package.pages.map { ($0.id, $0) })
            guard let units = manifest.readingUnits, units.count == 4, units.allSatisfy({ $0.pageIDs.count == 2 }) else { throw DiaryEditorError.invalidDocument }
            let assetIDs = Dictionary(uniqueKeysWithValues: manifest.assetTable.keys.map { ($0, UUID()) })
            var loaded: [Paper] = []
            for pageID in units.flatMap(\.pageIDs) {
                try Task.checkCancellation()
                guard let page = sourcePages[pageID] else { throw DiaryEditorError.invalidDocument }
                var document = try package.instantiate(page, bookID: UUID(), targetSize: page.size.cg, assetIDs: assetIDs)
                if document.objects[document.rootContentID]?.background == nil { document.objects[document.rootContentID]?.background = .white }
                var images: [UUID: UIImage] = [:]
                for (sourceID, id) in assetIDs where document.assets[id] != nil {
                    guard let asset = manifest.assetTable[sourceID], let image = UIImage(contentsOfFile: try package.url(asset.path).path) else { throw DiaryEditorError.missingResource }
                    images[id] = image
                }
                let fonts = document.objects.values.flatMap { $0.layers.compactMap(\.font) }
                await DiaryFontCatalog.shared.prewarm(fonts, documentID: document.id)
                loaded.append(try await Self.prepare(document: document, images: images))
                await Task.yield()
            }
            try Task.checkCancellation()
            papers = loaded
            settle(on: displayed)
        } catch is CancellationError { }
        catch { phase = .failed }
    }

    static func isBackground(_ layer: DiaryLayer) -> Bool {
        layer.semanticKind == .background || layer.isLibraryBackground == true
    }
    static func isText(_ layer: DiaryLayer) -> Bool {
        layer.kind == .text || layer.category == .textImage || layer.semanticKind == .text
    }
    private static func prepare(document: DiaryDocument, images: [UUID: UIImage]) async throws -> Paper {
        guard let content = document.objects[document.rootContentID] else { throw DiaryEditorError.invalidDocument }
        func photo(_ layer: DiaryLayer, depth: Int = 0) -> Bool {
            if layer.isContentPhoto || layer.semanticKind == .photo { return true }
            guard depth < 12, let child = layer.contentID, let object = document.objects[child] else { return false }
            return object.layers.contains { photo($0, depth: depth + 1) }
        }
        func text(_ layer: DiaryLayer) -> Bool { Self.isText(layer) && !photo(layer) }
        let pageRect = CGRect(origin: .zero, size: content.referenceSize)
        func render(ids: Set<UUID>, rect: CGRect, background: Bool, ink: Bool = false) -> UIImage {
            var copy = document
            // Keep siblings for attached frame transforms, hiding rather than deleting them.
            for i in content.layers.indices {
                copy.objects[copy.rootContentID]?.layers[i].visible = content.layers[i].visible && ids.contains(content.layers[i].id)
            }
            if !background { copy.objects[copy.rootContentID]?.background = nil }
            let format = UIGraphicsImageRendererFormat()
            format.scale = min(1, 1100 / max(rect.width, rect.height))
            format.opaque = false
            return UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
                context.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
                DiaryPageRenderer.draw(copy, images: images, in: context.cgContext, viewport: rect, includeInk: ink, cacheObjects: false)
            }
        }
        let visible = content.layers.filter(\.visible)
        let background = render(ids: Set(visible.filter(isBackground).map(\.id)), rect: pageRect, background: true)
        await Task.yield(); try Task.checkCancellation()
        let assembled = render(ids: Set(visible.filter { !text($0) }.map(\.id)), rect: pageRect, background: true)
        await Task.yield(); try Task.checkCancellation()
        let complete = render(ids: Set(visible.map(\.id)), rect: pageRect, background: true, ink: true)
        var pieces: [Piece] = []
        for layer in visible where !isBackground(layer) && !layer.isPhotoFrame && !layer.name.contains("品牌") {
            try Task.checkCancellation()
            let frames = visible.filter { $0.isPhotoFrame && $0.frameTargetID == layer.id }
            var group = [layer] + frames
            if text(layer) {
                func projectedBounds(_ item: DiaryLayer) -> CGRect {
                    DiaryPageRenderer.effectiveTransform(item, siblings: content.layers).projection.bounds(
                        DiaryPageRenderer.bounds(item, document: document, siblings: content.layers))
                }
                let textBounds = projectedBounds(layer)
                let backing = visible.filter {
                    !text($0) && !isBackground($0) && !photo($0) &&
                    ($0.name.contains("纸")) &&
                    projectedBounds($0).contains(CGPoint(x: textBounds.midX, y: textBounds.midY))
                }.min {
                    let a = projectedBounds($0), b = projectedBounds($1)
                    return a.width * a.height < b.width * b.height
                }
                if let backing { group = [backing, layer] }
            }
            let bounds = group.reduce(CGRect.null) { rect, item in
                rect.union(DiaryPageRenderer.effectiveTransform(item, siblings: content.layers).projection.bounds(
                    DiaryPageRenderer.bounds(item, document: document, siblings: content.layers)))
            }.intersection(pageRect)
            guard !bounds.isNull, bounds.width > 1, bounds.height > 1 else { continue }
            pieces.append(Piece(id: layer.id, image: render(ids: Set(group.map(\.id)), rect: bounds, background: false),
                                rect: bounds, photo: photo(layer), text: text(layer)))
            await Task.yield()
        }
        // Two hero photos and one decoration per leaf keep the floating collage legible.
        let heroes = pieces.indices.filter { pieces[$0].photo }.sorted {
            pieces[$0].rect.width * pieces[$0].rect.height > pieces[$1].rect.width * pieces[$1].rect.height
        }.prefix(2)
        var selected = Array(heroes)
        if let decoration = pieces.indices.filter({ !pieces[$0].photo && !pieces[$0].text }).max(by: {
            pieces[$0].rect.width * pieces[$0].rect.height < pieces[$1].rect.width * pieces[$1].rect.height
        }) { selected.append(decoration) }
        for (slot, index) in selected.enumerated() { pieces[index].floatingIndex = slot }
        let textIndices = pieces.indices.filter { index in
            pieces[index].text && !visible.contains { $0.id == pieces[index].id && ($0.name.contains("来源") || $0.name.contains("参考")) }
        }.prefix(2)
        for (slot, index) in textIndices.enumerated() { pieces[index].floatingIndex = 10 + slot }
        return Paper(size: content.referenceSize, background: background, assembled: assembled, complete: complete, pieces: pieces)
    }

    func bind() {
        guard phase == .floating else { return }
        animationTask?.cancel()
        phase = .binding
        let token = generation
        animationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(self.reduceMotion ? 0 : 1350))
                guard self.generation == token else { return }
                self.phase = .revealing
                if !self.reduceMotion { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7) }
                try await Task.sleep(for: .milliseconds(self.reduceMotion ? 0 : 480))
                guard self.generation == token else { return }
                self.completed.insert(self.displayed)
                self.phase = .complete
            } catch { }
        }
    }
    func beginTurn() {
        guard canNavigate else { return }
        generation += 1
        animationTask?.cancel()
        phase = .turning
    }
    func settle(on spread: Int) {
        guard (0..<4).contains(spread) else { return }
        generation += 1
        let token = generation
        animationTask?.cancel()
        displayed = spread
        if completed.contains(spread) { phase = .complete; return }
        guard !papers.isEmpty else { phase = .failed; return }
        phase = .blank
        animationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(self.reduceMotion ? 0 : 450))
                guard self.generation == token else { return }
                self.phase = .floating
            } catch { }
        }
    }
    func suspend() {
        generation += 1
        animationTask?.cancel()
    }
}

private struct OnboardingReadingPaper: View {
    let assembly: DiaryOnboardingAssembly
    let index: Int
    var body: some View {
        GeometryReader { geometry in
            let paper = assembly.papers[index]
            let complete = assembly.completed.contains(index / 2)
            let revealing = assembly.displayed == index / 2 && assembly.phase == .revealing
            ZStack {
                Image(uiImage: complete ? paper.complete : revealing ? paper.assembled : paper.background).resizable()
                Image(uiImage: paper.complete).resizable().opacity(revealing ? 1 : 0)
                    .animation(assembly.reduceMotion ? nil : .easeIn(duration: 0.45), value: revealing)
            }
            .frame(width: geometry.size.width * (1 - DiaryBookSpine.halfGapFraction), height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: DiaryBookStageLayout.boundPaperCornerRadius(width: geometry.size.width)))
            .frame(width: geometry.size.width, alignment: index.isMultiple(of: 2) ? .leading : .trailing)
        }
    }
}

private final class OnboardingReadingController: UIHostingController<OnboardingReadingPaper>, DiaryIndexedPaper {
    let index: Int
    init(index: Int, assembly: DiaryOnboardingAssembly) {
        self.index = index
        super.init(rootView: OnboardingReadingPaper(assembly: assembly, index: index))
        safeAreaRegions = []
        view.backgroundColor = .clear
    }
    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

struct DiaryOnboardingBook: View {
    let requestedSpread: Int
    let assembly: DiaryOnboardingAssembly
    let onSettled: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spread = 0

    init(requestedSpread: Int, assembly: DiaryOnboardingAssembly, onSettled: @escaping (Int) -> Void) {
        self.requestedSpread = requestedSpread
        self.assembly = assembly
        self.onSettled = onSettled
        _spread = State(initialValue: requestedSpread)
    }

    var body: some View {
        GeometryReader { geometry in
            if assembly.papers.count == 8 {
                let size = assembly.papers[0].size
                let ratio = (2 * size.width / size.height * 0.955 + 0.045) / (1 - 0.955 * DiaryBookSpine.halfGapFraction)
                let width = min(geometry.size.width, geometry.size.height * 0.49 * ratio)
                let height = width / ratio
                let origin = CGPoint(x: (geometry.size.width - width) / 2, y: geometry.size.height * 0.12)
                ZStack(alignment: .topLeading) {
                    collageBackdrop(size: geometry.size)
                    ZStack {
                        Image("DiaryBookLeather").resizable()
                        DiaryPageCurlReader(spreadCount: 4, spread: $spread, reduceMotion: reduceMotion,
                            allowsPageActions: false, onTransitionChange: { turning, displayed in
                                if !turning {
                                    assembly.settle(on: displayed)
                                    onSettled(displayed)
                                }
                            }) { index, _ in
                                OnboardingReadingController(index: index, assembly: assembly)
                            }
                            .padding(width * 0.0225)
                            .allowsHitTesting(false)
                    }
                    .frame(width: width, height: height)
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 10)
                    .offset(x: origin.x, y: origin.y)
                    floatingMaterials(stage: geometry.size, book: CGRect(origin: origin, size: CGSize(width: width, height: height)))
                }
            } else if assembly.phase == .failed {
                if let root = Bundle.main.url(forResource: "OnboardingThemes", withExtension: "bundle"),
                   let image = UIImage(contentsOfFile: root.appendingPathComponent("fallback\(requestedSpread).jpg").path) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxHeight: .infinity)
                        .accessibilityLabel("手帐成品预览，动画暂不可用")
                }
            } else {
                ProgressView("正在打开手帐…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(assembly.phase == .floating ? "照片与贴纸已展开，点击装订这一页" : assembly.showsCopy ? "装订完成的旅行手帐" : "手帐正在准备")
        .task {
            spread = requestedSpread
            assembly.reduceMotion = reduceMotion
            await assembly.load()
            if assembly.phase != .loading && assembly.displayed != requestedSpread { assembly.settle(on: requestedSpread) }
        }
        .onChange(of: requestedSpread) { _, value in
            if assembly.phase == .failed { onSettled(value) }
            else { spread = value }
        }
        .onChange(of: reduceMotion) { _, value in assembly.reduceMotion = value }
    }

    private var collageVisible: Bool { assembly.phase == .floating || assembly.phase == .binding }
    private func collageBackdrop(size: CGSize) -> some View {
        Canvas { context, bounds in
            for x in stride(from: CGFloat(8), to: bounds.width, by: 18) {
                for y in stride(from: CGFloat(8), to: bounds.height, by: 18) {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.brown.opacity(0.13)))
                }
            }
            var route = Path()
            route.move(to: CGPoint(x: bounds.width * 0.08, y: bounds.height * 0.72))
            route.addCurve(to: CGPoint(x: bounds.width * 0.91, y: bounds.height * 0.83),
                           control1: CGPoint(x: bounds.width * 0.27, y: bounds.height * 0.96),
                           control2: CGPoint(x: bounds.width * 0.66, y: bounds.height * 0.61))
            context.stroke(route, with: .color(.brown.opacity(0.28)), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
        }
        .mask(LinearGradient(colors: [.clear, .black.opacity(0.8), .black, .clear], startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func floatingMaterials(stage: CGSize, book: CGRect) -> some View {
        let rim = book.width * 0.0225
        let inner = book.insetBy(dx: rim, dy: rim)
        let gap = inner.width * DiaryBookSpine.halfGapFraction
        let pageWidth = (inner.width - gap) / 2
        let active = assembly.phase == .floating || assembly.phase == .binding
        let landed = assembly.phase == .binding
        return ZStack(alignment: .topLeading) {
            ForEach(0..<2) { side in
                let paper = assembly.papers[assembly.displayed * 2 + side]
                ForEach(paper.pieces) { piece in
                    let target = CGRect(x: inner.minX + CGFloat(side) * (pageWidth + gap) + piece.rect.minX / paper.size.width * pageWidth,
                                        y: inner.minY + piece.rect.minY / paper.size.height * inner.height,
                                        width: piece.rect.width / paper.size.width * pageWidth,
                                        height: piece.rect.height / paper.size.height * inner.height)
                    let slot = piece.floatingIndex ?? 0
                    let floatingWidth = stage.width * (piece.text ? 0.42 : piece.photo ? (slot == 0 ? 0.40 : 0.28) : 0.30)
                    let scale = min(floatingWidth / max(1, target.width), stage.height * (piece.text ? 0.105 : 0.34) / max(1, target.height))
                    let floatingX = stage.width * (piece.text ? (side == 0 ? 0.29 : 0.72) : side == 0 ? (slot == 1 ? 0.30 : 0.24) : (slot == 1 ? 0.72 : 0.74))
                    let floatingY = stage.height * (piece.text ? (0.73 + Double(max(0, slot - 10)) * 0.13) : slot == 0 ? (side == 0 ? 0.22 : 0.33) : slot == 1 ? 0.49 : 0.10)
                    Image(uiImage: piece.image).resizable()
                        .frame(width: target.width, height: target.height)
                        .scaleEffect(landed ? 1 : scale)
                        .rotationEffect(.degrees(landed ? 0 : (piece.text ? 0 : side == 0 ? -6 : 6)))
                        .shadow(color: .black.opacity(landed || piece.text ? 0 : 0.18), radius: landed ? 0 : 10, x: 0, y: landed ? 0 : 16)
                        .position(x: landed ? target.midX : floatingX, y: landed ? target.midY : floatingY)
                        .opacity(active && (landed ? !piece.text : piece.floatingIndex != nil) ? 1 : 0)
                        .animation(reduceMotion || assembly.phase != .floating ? nil : .easeInOut(duration: 0.38), value: active)
                        .animation(reduceMotion ? nil : .interpolatingSpring(stiffness: 115, damping: 19).delay(piece.photo ? 0 : 0.18), value: landed)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
