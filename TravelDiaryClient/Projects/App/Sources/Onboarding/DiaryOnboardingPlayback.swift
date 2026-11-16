import SwiftUI

/// Plays the bundled published pages through the editor's material entrance renderer.
struct DiaryOnboardingPlayback: View {
    let index: Int
    @State private var sessions: [DiaryEditorSession] = []
    @State private var failed = false
    @State private var replay = UUID()
    @State private var playback = OnboardingSpreadPlayback()

    var body: some View {
        VStack(spacing: 12) {
            if sessions.count == 2 {
                GeometryReader { geometry in
                    let size = sessions[0].content.referenceSize
                    let scale = min(geometry.size.width / (size.width * 2), geometry.size.height / size.height)
                    HStack(spacing: 0) {
                        ForEach(sessions.indices, id: \.self) { position in
                            OnboardingMaterialCanvas(session: sessions[position], pageIndex: position, playback: playback)
                                .frame(width: size.width, height: size.height)
                                .scaleEffect(scale, anchor: .topLeading)
                                .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
                        }
                    }
                    .id(replay)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
                Button("重播制作过程", systemImage: "arrow.counterclockwise") { playback = OnboardingSpreadPlayback(); replay = UUID() }
                    .font(.caption)
            } else if failed {
                Image("OnboardingSpread" + String(index)).resizable().scaledToFit()
                Text("动画暂不可用，继续欣赏完整跨页").font(.caption)
            } else {
                ProgressView("正在打开手帐…")
            }
        }
        .task(id: index) {
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
                let pair = [[1, 2], [7, 8], [15, 16]][index]
                let assetIDs = Dictionary(uniqueKeysWithValues: manifest.assetTable.keys.map { ($0, UUID()) })
                let store = DiaryDocumentStore(ownerID: "onboarding-preview", baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("DiaryOnboardingPreview"))
                var loaded: [DiaryEditorSession] = []
                for position in pair {
                    let page = pages[position]
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
            catch { failed = true }
        }
    }
}

@MainActor
private final class OnboardingSpreadPlayback {
    private weak var left: DiaryCanvasSurface?
    private weak var right: DiaryCanvasSurface?
    private var started = false

    func ready(_ view: DiaryCanvasSurface, page: Int) {
        if page == 0 { left = view } else { right = view }
        guard !started, let left, let right, left.window != nil, right.window != nil else { return }
        started = true
        left.animateMaterialEntrance()
        right.animateMaterialEntrance()
    }
}

private struct OnboardingMaterialCanvas: UIViewRepresentable {
    let session: DiaryEditorSession
    let pageIndex: Int
    let playback: OnboardingSpreadPlayback
    func makeUIView(context: Context) -> DiaryCanvasSurface {
        let view = DiaryCanvasSurface()
        view.stagesEntrance = true
        view.entrancePhotosFirst = true
        view.usesPreloadedImages = true
        view.entrancePageIndex = pageIndex
        view.onEntranceReady = { [weak playback] view in playback?.ready(view, page: pageIndex) }
        view.compactViewport = true
        view.session = session
        view.showsSelection = false
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: DiaryCanvasSurface, context: Context) {
        view.refresh()
    }
    static func dismantleUIView(_ view: DiaryCanvasSurface, coordinator: ()) {
        view.finishEntrance()
    }
}
