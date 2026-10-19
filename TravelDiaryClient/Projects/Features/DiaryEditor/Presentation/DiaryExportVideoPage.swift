import SwiftUI

struct DiaryExportVideoPage: View {
    let book: DiaryBook
    let store: DiaryDocumentStore
    @Binding var options: DiaryVideoOptions
    let previewEnabled: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var current: UIImage?
    @State private var next: UIImage?
    @State private var rings: UIImage?
    @State private var previewTimeline = DiaryVideoTimeline(spreadCount: 1, hold: 3)
    @State private var started = Date()
    @State private var message: String?
    @State private var fallback = false
    @State private var retry = 0
    @State private var playing = true
    @State private var elapsed: Double = 0

    private var spreadCount: Int { DiaryBookImageExporter.spreadPages(book).count }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("把纸页，翻成一段回忆").font(.title3.bold())
            ZStack {
                Color(uiColor: DiaryVideoFrameRenderer.background)
                if let current, let rings {
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { context in
                        let seconds = (elapsed + (playing ? max(0, context.date.timeIntervalSince(started)) : 0)).truncatingRemainder(dividingBy: previewTimeline.duration)
                        Image(uiImage: DiaryVideoFrameRenderer.image(size: previewSize, title: book.title,
                            sample: previewTimeline.sample(at: seconds), current: previewImage(at: seconds, first: current),
                            next: next, rings: rings)).resizable().scaledToFit()
                    }
                } else if let message {
                    VStack(spacing: 10) {
                        Text(message).font(.caption)
                        Button("重新加载预览") { retry += 1 }
                    }.padding()
                } else { ProgressView("正在准备预览…") }
            }
            .aspectRatio(options.frame == .landscape ? 16.0 / 9 : 9.0 / 16, contentMode: .fit)
            .frame(maxHeight: options.frame == .portrait ? 400 : nil)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: .infinity)
            .accessibilityLabel("翻页视频效果预览")
            HStack {
                Text("效果预览 · 最多展示前两个所选跨页").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(playing ? "暂停" : "播放") { togglePlayback() }
                    .font(.caption).disabled(current == nil)
            }
            if fallback { Text("部分字体暂不可用，预览和导出将使用替代字体。").font(.caption).foregroundStyle(.orange) }
            VStack(alignment: .leading, spacing: 12) {
                Text("画幅").font(.headline)
                Picker("画幅", selection: $options.frame) {
                    ForEach(DiaryVideoOptions.Frame.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Text("每个跨页停留").font(.headline)
                Picker("翻阅速度", selection: $options.speed) {
                    ForEach(DiaryVideoOptions.Speed.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("导出范围").font(.headline)
                    Spacer()
                    Button("全部跨页") { options.firstSpread = 0; options.lastSpread = max(0, spreadCount - 1) }.font(.subheadline)
                }
                Stepper("从第 \(options.firstSpread + 1) 个跨页", value: $options.firstSpread, in: 0...max(0, options.lastSpread))
                Stepper("到第 \(options.lastSpread + 1) 个跨页", value: $options.lastSpread, in: options.firstSpread...max(options.firstSpread, spreadCount - 1))
            }
            Text("\(options.lastSpread - options.firstSpread + 1) 个跨页 · 约 \(Int(ceil(options.timeline.duration))) 秒\n1080p · 30 帧/秒 · MP4 · 无声\n完整保留左右纸页、皮革外沿和装订环。竖屏上下留白。")
                .font(.caption).foregroundStyle(.secondary)
            Text("生成期间请保持应用在前台。切换到后台将取消本次生成，可返回重试。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task(id: "\(options)-\(retry)-\(book.catalogRevision)") { await loadPreview() }
        .onDisappear { pause() }
        .onChange(of: previewEnabled) { _, enabled in if !enabled { pause() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { pause() } }
    }

    private func pause() {
        guard playing else { return }
        elapsed += max(0, Date().timeIntervalSince(started)); playing = false
    }
    private func togglePlayback() {
        if playing { pause() }
        else { started = Date(); playing = true }
    }
    private var previewSize: CGSize { options.frame == .landscape ? CGSize(width: 640, height: 360) : CGSize(width: 360, height: 640) }
    private func previewImage(at seconds: Double, first: UIImage) -> UIImage {
        previewTimeline.sample(at: seconds).spread == 0 ? first : (next ?? first)
    }
    private func loadPreview() async {
        current = nil; next = nil; rings = nil; message = nil; fallback = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DiaryVideoPreview-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try await Task.sleep(for: .milliseconds(250))
            var previewOptions = options
            previewOptions.lastSpread = min(options.lastSpread, options.firstSpread + 1)
            let prepared = try await DiaryBookVideoExporter.prepare(book: book, store: store, options: previewOptions,
                directory: directory, width: 640)
            try Task.checkCancellation()
            guard let firstURL = prepared.urls.first, let first = UIImage(contentsOfFile: firstURL.path) else {
                throw DiaryBookVideoExporter.ExportError.cannotRender
            }
            current = first
            next = prepared.urls.count > 1 ? UIImage(contentsOfFile: prepared.urls[1].path) : nil
            rings = prepared.rings; fallback = prepared.usedFallbackFonts
            previewTimeline = previewOptions.timeline; started = Date(); elapsed = playing ? 0 : 2
        } catch is CancellationError { }
        catch { message = error.localizedDescription }
    }
}
