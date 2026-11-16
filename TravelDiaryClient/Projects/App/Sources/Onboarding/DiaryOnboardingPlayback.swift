import SwiftUI

/// Plays the bundled published pages through the editor's material entrance renderer.
struct DiaryOnboardingPlayback: View {
    let index: Int
    var finishEarly = false
    var onCompleted: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var finished = false
    @State private var sessions: [DiaryEditorSession] = []
    @State private var failed = false
    @State private var playback = OnboardingSpreadPlayback()

    var body: some View {
        VStack(spacing: 12) {
            if sessions.count == 2 {
                let showsShell = true
                let size = sessions[0].content.referenceSize
                let ratio = 2 * size.width / size.height
                let rim: CGFloat = 0.0225
                let outerRatio = (ratio * (1 - 2 * rim) + 2 * rim) /
                    (1 - (1 - 2 * rim) * DiaryBookSpine.halfGapFraction)
                DiaryBoundSpread(showsShell: showsShell) {
                    pageCanvas(0, showsShell: showsShell)
                } right: {
                    pageCanvas(1, showsShell: showsShell)
                }
                .aspectRatio(showsShell ? outerRatio : ratio, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if failed {
                Image("OnboardingSpread" + String(index)).resizable().scaledToFit()
                Text("动画暂不可用，继续欣赏完整跨页").font(.caption)
            } else {
                ProgressView("正在打开手帐…")
            }
        }
        .onChange(of: finishEarly, initial: true) { _, value in
            if value { playback.finish(); complete() }
        }
        .task(id: index) {
            finished = false
            playback = OnboardingSpreadPlayback()
            sessions = []
            failed = false
            do {
                guard let root = Bundle.main.url(forResource: "OnboardingDali", withExtension: "bundle") else {
                    throw DiaryEditorError.missingResource
                }
                let manifest = try JSONDecoder().decode(PresetManifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
                let package = DiaryPresetPackage(root: root, manifest: manifest)
                let pages = try package.pages
                guard let spreads = manifest.readingUnits, spreads.indices.contains(index),
                      spreads[index].kind == "spread", spreads[index].pageIDs.count == 2 else {
                    throw DiaryEditorError.invalidDocument
                }
                let pagesByID = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, $0) })
                let assetIDs = Dictionary(uniqueKeysWithValues: manifest.assetTable.keys.map { ($0, UUID()) })
                let store = DiaryDocumentStore(ownerID: "onboarding-preview", baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("DiaryOnboardingPreview"))
                var loaded: [DiaryEditorSession] = []
                for pageID in spreads[index].pageIDs {
                    guard let page = pagesByID[pageID] else { throw DiaryEditorError.invalidDocument }
                    var document = try package.instantiate(page, bookID: UUID(), targetSize: page.size.cg, assetIDs: assetIDs)
                    if document.objects[document.rootContentID]?.background == nil {
                        document.objects[document.rootContentID]?.background = .white
                    }
                    var images: [UUID: UIImage] = [:]
                    for (sourceID, id) in assetIDs where document.assets[id] != nil {
                        guard let asset = manifest.assetTable[sourceID],
                              let image = UIImage(contentsOfFile: try package.url(asset.path).path) else {
                            throw DiaryEditorError.missingResource
                        }
                        images[id] = image
                    }
                    loaded.append(DiaryEditorSession(document: document, images: images, store: store))
                    await Task.yield()
                    try Task.checkCancellation()
                }
                sessions = loaded
            } catch is CancellationError { }
            catch { failed = true; onCompleted() }
        }
    }
    private func complete() {
        guard !finished else { return }
        finished = true
        onCompleted()
    }

    private func pageCanvas(_ index: Int, showsShell: Bool) -> some View {
        GeometryReader { geometry in
            let session = sessions[index]
            let size = session.content.referenceSize
            let scale = min(geometry.size.width / size.width, geometry.size.height / size.height)
            let cornerRadius = showsShell && scale > 0
                ? DiaryBookStageLayout.boundPaperCornerRadius(width: size.width * scale) / scale
                : 0
            OnboardingMaterialCanvas(session: session, pageIndex: index, playback: playback, paperCornerRadius: cornerRadius, finishEarly: finishEarly, onFinished: complete)
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

}

@MainActor
private final class OnboardingSpreadPlayback {
    private weak var left: DiaryCanvasSurface?
    private weak var right: DiaryCanvasSurface?
    private var started = false

    func finish() {
        started = true
        left?.finishEntrance()
        right?.finishEntrance()
    }

    func ready(_ view: DiaryCanvasSurface, page: Int, completion: @escaping () -> Void) {
        if page == 0 { left = view } else { right = view }
        guard !started, let left, let right, left.window != nil, right.window != nil else { return }
        started = true
        var remaining = 2
        let pageFinished = {
            remaining -= 1
            if remaining == 0 { completion() }
        }
        left.animateMaterialEntrance(completion: pageFinished)
        right.animateMaterialEntrance(completion: pageFinished)
    }
}

private struct OnboardingMaterialCanvas: UIViewRepresentable {
    let session: DiaryEditorSession
    let pageIndex: Int
    let playback: OnboardingSpreadPlayback
    let paperCornerRadius: CGFloat
    var finishEarly = false
    let onFinished: () -> Void
    func makeUIView(context: Context) -> DiaryCanvasSurface {
        let view = DiaryCanvasSurface()
        view.stagesEntrance = !finishEarly
        view.entrancePhotosFirst = true
        view.usesPreloadedImages = true
        view.entrancePageIndex = pageIndex
        view.onEntranceReady = { [weak playback] view in
            playback?.ready(view, page: pageIndex, completion: onFinished)
        }
        view.previewPaperCornerRadius = paperCornerRadius
        view.compactViewport = true
        view.session = session
        view.showsSelection = false
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: DiaryCanvasSurface, context: Context) {
        view.previewPaperCornerRadius = paperCornerRadius
        if finishEarly { view.finishEntrance() }
        view.refresh()
    }
    static func dismantleUIView(_ view: DiaryCanvasSurface, coordinator: ()) {
        view.finishEntrance()
    }
}


/// One persistent six-leaf book; the shell is outside UIKit's turning pages.
private struct OnboardingReadingPaper: View {
    let image: UIImage
    let index: Int
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width * (1 - DiaryBookSpine.halfGapFraction)
            Image(uiImage: image).resizable()
                .frame(width: width, height: geometry.size.height)
                .clipShape(RoundedRectangle(cornerRadius: DiaryBookStageLayout.boundPaperCornerRadius(width: width), style: .continuous))
                .frame(width: geometry.size.width, alignment: index.isMultiple(of: 2) ? .leading : .trailing)
        }
    }
}

private final class OnboardingReadingController: UIHostingController<OnboardingReadingPaper>, DiaryIndexedPaper {
    let index: Int
    init(index: Int, image: UIImage) {
        self.index = index
        super.init(rootView: OnboardingReadingPaper(image: image, index: index))
        view.backgroundColor = .clear
    }
    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

struct DiaryOnboardingBook: View {
    let requestedSpread: Int
    let playsIntroduction: Bool
    let onTurning: (Bool) -> Void
    let onSettled: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var images: [UIImage] = []
    @State private var spread = 0
    @State private var introductionFinished = false
    @State private var failed = false

    private var showingIntroduction: Bool { playsIntroduction && !introductionFinished && !reduceMotion }
    var body: some View {
        ZStack {
            if images.count == 6 {
                let ratio = 2 * images[0].size.width / images[0].size.height
                let outerRatio = (ratio * 0.955 + 0.045) / (1 - 0.955 * DiaryBookSpine.halfGapFraction)
                GeometryReader { geometry in
                    ZStack {
                        Image("DiaryBookLeather").resizable()
                        DiaryPageCurlReader(spreadCount: 3, spread: $spread, reduceMotion: reduceMotion,
                            allowsPageActions: false, onTransitionChange: { turning, displayed in
                                guard !showingIntroduction else { return }
                                onTurning(turning)
                                if !turning { onSettled(displayed) }
                            }) { index, _ in
                                OnboardingReadingController(index: index, image: images[index])
                            }
                            .padding(geometry.size.width * 0.0225)
                    }
                }
                .aspectRatio(outerRatio, contentMode: .fit)
                .opacity(showingIntroduction ? 0 : 1)
                .allowsHitTesting(!showingIntroduction)
                if showingIntroduction {
                    DiaryOnboardingPlayback(index: 0, finishEarly: requestedSpread != 0) {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { introductionFinished = true }
                    }
                }
            } else if failed {
                DiaryBoundSpread {
                    fallbackPaper(left: true)
                } right: {
                    fallbackPaper(left: false)
                }.aspectRatio(1.4, contentMode: .fit)
            } else {
                ProgressView("正在打开手帐…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            spread = requestedSpread
            do {
                guard let root = Bundle.main.url(forResource: "OnboardingDali", withExtension: "bundle") else { throw DiaryEditorError.missingResource }
                let manifest = try JSONDecoder().decode(PresetManifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
                let package = DiaryPresetPackage(root: root, manifest: manifest)
                let pages = Dictionary(uniqueKeysWithValues: try package.pages.map { ($0.id, $0) })
                guard let units = manifest.readingUnits, units.count == 3 else { throw DiaryEditorError.invalidDocument }
                var loaded: [UIImage] = []
                for id in units.flatMap(\.pageIDs) {
                    guard let page = pages[id], let image = UIImage(contentsOfFile: try package.url(page.preview.largePath).path) else { throw DiaryEditorError.missingResource }
                    loaded.append(image.preparingForDisplay() ?? image)
                    await Task.yield()
                    try Task.checkCancellation()
                }
                guard loaded.count == 6 else { throw DiaryEditorError.invalidDocument }
                images = loaded
            } catch is CancellationError { }
            catch { failed = true; onTurning(false); onSettled(requestedSpread) }
        }
        .task(id: requestedSpread * 2 + (showingIntroduction ? 1 : 0)) {
            guard !showingIntroduction else { return }
            // Let the intro resolve to the full first spread before starting a curl.
            if requestedSpread != spread {
                do { try await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 220)) } catch { return }
                spread = requestedSpread
            }
            if failed { onTurning(false); onSettled(requestedSpread) }
        }
    }
    private func fallbackPaper(left: Bool) -> some View {
        GeometryReader { geometry in
            Image("OnboardingSpread" + String(requestedSpread)).resizable()
                .frame(width: geometry.size.width * 2, height: geometry.size.height)
                .offset(x: left ? 0 : -geometry.size.width)
        }.clipped()
    }
}
