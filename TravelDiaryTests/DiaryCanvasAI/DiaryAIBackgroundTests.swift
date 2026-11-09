import Testing
import UIKit
import SwiftUI
@testable import TravelDiary

@Suite(.serialized)
@MainActor struct DiaryAIBackgroundTests {
    @Test func textOnlyRequestOmitsImage() {
        let body = DiarySeedreamBackgroundProvider.body(reference: Data(), prompt: "松林夕阳")
        #expect(body["image"] == nil)
        #expect(body["prompt"] as? String == "松林夕阳")
        let guided = DiarySeedreamBackgroundProvider.body(reference: Data([1, 2]), prompt: "松林夕阳")
        #expect(guided["image"] != nil)
    }
    @Test func legacyBackgroundOptionsRemainGuided() throws {
        let options = try JSONDecoder().decode(DiaryAIBackgroundOptions.self, from: Data(#"{"style":"paper","strength":"中","saveToAlbum":true,"backgroundOnly":false}"#.utf8))
        #expect(!options.isTextOnly)
    }
    @Test func gardenPaperNativePreviews() throws {
        let output = URL(fileURLWithPath: "/tmp/DiaryGardenPaperPreviews")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for kind in DiaryTextPaper.Kind.allCases where kind.isGarden {
            #expect(UIImage(named: kind.assetName!) != nil)
            var layer = DiaryLayer(name: "花园便签", kind: .text,
                                   transform: DiaryTransform(position: .zero, pivot: .zero),
                                   size: CGSize(width: 700, height: 400))
            layer.text = "把温柔收藏\n让日子慢慢开花"
            layer.fontSize = 40
            layer.textAppearance = DiaryTextAppearance(paper: DiaryTextPaper(kind: kind))
            let image = DiaryPageRenderer.textPreview(layer)
            #expect(image.size.width > 0 && image.size.height > 0)
            try #require(image.pngData()).write(to: output.appendingPathComponent(kind.rawValue + ".png"))
        }
    }
    @Test func planningMinorOverflowTranslatesWithoutResizeOrNewCollision() async throws {
        let (session, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let context = try await DiaryEditorAIBridge(session).capture(request())
        let region = DiaryAILayoutRegion(role: "text", x: 10, y: 650, width: 100, height: 160)
        let fitted = DiaryAIWorkspace.fitPlanningRegions([region], context: context)[0]
        #expect(fitted.y == 640)
        #expect(fitted.width == region.width && fitted.height == region.height)
        let blocker = DiaryAILayoutRegion(role: "text", x: 10, y: 630, width: 100, height: 15)
        #expect(DiaryAIWorkspace.fitPlanningRegions([region, blocker], context: context)[0].y == region.y)
        let excessive = DiaryAILayoutRegion(role: "text", x: 10, y: 700, width: 100, height: 160)
        #expect(DiaryAIWorkspace.fitPlanningRegions([excessive], context: context)[0].y == excessive.y)
    }
    private func image(_ size: CGSize = CGSize(width: 1000, height: 800)) throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return try #require(UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(white: 0.97, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }.pngData())
    }
    private func fixture() async throws -> (DiaryEditorSession, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var document = DiaryDocument(); document.objects[document.rootContentID]?.referenceSize = CGSize(width: 1000, height: 800)
        let store = DiaryDocumentStore(ownerID: "background-tests", baseDirectory: root)
        let (asset, decoded) = try await store.importImage(image(CGSize(width: 100, height: 150)), documentID: document.id)
        document.assets[asset.id] = asset
        document.appendObject(containing: .photo(asset: asset, center: CGPoint(x: 350, y: 350)))
        return (DiaryEditorSession(document: document, images: [asset.id: decoded], store: store), root)
    }
    private func request() -> DiaryAIRequest {
        var r = DiaryAIRequest.defaults(.custom); r.selectedOnly = false
        r.background = .init(backgroundOnly: true); return r
    }
    private func wait(_ w: DiaryAIWorkspace) async throws {
        let end = Date().addingTimeInterval(20)
        while w.running && Date() < end { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!w.running)
    }
    /// Explicitly opt-in: twelve paid image requests, never run during ordinary regression.
    @Test func liveStyleStudy() async throws {
        let marker = URL(fileURLWithPath: "/tmp/traveldiary-style-study-enabled")
        guard let roundData = try? Data(contentsOf: marker), let round = String(data: roundData, encoding: .utf8), ["baseline", "optimized", "verify"].contains(round) else { return }
        let root = URL(fileURLWithPath: "/tmp/DiaryStyleStudy")
        let source = try DiaryAIBackgroundImaging.jpeg(Data(contentsOf: root.appendingPathComponent("source.image")))
        let sourceImage = try #require(UIImage(data: source))
        let size = CGSize(width: 1311, height: 939)
        let bounds = CGRect(x: 110, y: 230, width: 360, height: 450)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let reference = try #require(UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(white: 0.975, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            sourceImage.draw(in: bounds)
        }.jpegData(compressionQuality: 0.9))
        let object = DiaryAIObject(id: UUID(), shortID: "L1", name: "山谷徒步", role: "photo", center: CGPoint(x: bounds.midX, y: bounds.midY), bounds: bounds, scale: 1, angle: 0, locked: false, visible: true, editable: true, assetIDs: [])
        let guide = try DiaryAIBackgroundImaging.occupancyGuide(canvas: size, objects: [object])
        try source.write(to: root.appendingPathComponent("source.jpg"))
        try reference.write(to: root.appendingPathComponent("layout.jpg"))
        try guide.write(to: root.appendingPathComponent("guide.jpg"))
        let prompts = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: root.appendingPathComponent("skill-prompts.json")))
        let filter = (try? Data(contentsOf: root.appendingPathComponent("style-filter.json"))).flatMap { try? JSONDecoder().decode([String].self, from: $0) }
        let styles = DiaryAIBackgroundStyle.all.filter { filter == nil || filter!.contains($0.id) }
        #expect(!styles.isEmpty)
        for start in stride(from: 0, to: styles.count, by: 3) {
            let tasks = styles[start..<min(start + 3, styles.count)].map { style in
                Task { @MainActor in
                    let directory = root.appendingPathComponent(style.id)
                    do {
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        let log = DiaryAIProductionLog(owner: "style-study", page: UUID(), root: directory)
                        let client = DiarySeedreamBackgroundProvider(); client.productionLog = log
                        if round == "baseline" && !FileManager.default.fileExists(atPath: directory.appendingPathComponent("skill.png").path) {
                            let prompt = try #require(prompts[style.id])
                            try Data(prompt.utf8).write(to: directory.appendingPathComponent("skill-prompt.txt"))
                            let url = try await client.generate(reference: source, prompt: prompt)
                            let bytes = try await client.download(url)
                            try bytes.write(to: directory.appendingPathComponent("skill.png"))
                            print("STYLE_STUDY skill \(style.id) complete")
                        }
                        let resultFile = directory.appendingPathComponent(round + ".png")
                        if round != "verify" && !FileManager.default.fileExists(atPath: resultFile.path) {
                            let context = "画幅1311×939；唯一真实照片L1边界x110,y230,w360,h450；右上和右侧大片空隙，左上安静。来源只认本图。风格：" + style.name + "；" + style.brief + "；强度中。" + style.sceneDirection("中")
                            let design = try await client.design(reference: reference, context: context)
                            try Data(design.brief.utf8).write(to: directory.appendingPathComponent(round + "-brief.txt"))
                            let prepared: String
                            do { prepared = try DiarySeedreamBackgroundProvider.preparePrompt(design.prompt) }
                            catch { prepared = try await client.repairPrompt(design.prompt) }
                            let prompt = DiaryAIBackgroundStyle.generationPrompt(design: prepared, style: style, strength: "中", size: size)
                            try Data(prompt.utf8).write(to: directory.appendingPathComponent(round + "-prompt.txt"))
                            let url = try await client.generate(reference: guide, prompt: prompt)
                            let bytes = try await client.download(url)
                            try bytes.write(to: resultFile)
                            let fitted = try DiaryAIBackgroundImaging.prepare(bytes, canvas: size)
                            try fitted.write(to: directory.appendingPathComponent(round + "-fitted.png"))
                            let background = try #require(UIImage(data: fitted))
                            let composed = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                                background.draw(in: CGRect(origin: .zero, size: size)); sourceImage.draw(in: bounds)
                            }
                            try composed.pngData()?.write(to: directory.appendingPathComponent("composed.png"))
                            do {
                                try await client.validate(reference: reference, background: fitted, style: style)
                                try Data("accepted".utf8).write(to: directory.appendingPathComponent(round + "-validation.txt"))
                            } catch {
                                try Data(error.localizedDescription.utf8).write(to: directory.appendingPathComponent(round + "-validation.txt"))
                            }
                            print("STYLE_STUDY \(round) \(style.id) complete")
                        }
                        if round == "verify" {
                            let fitted = try Data(contentsOf: directory.appendingPathComponent("optimized-fitted.png"))
                            let background = try #require(UIImage(data: fitted))
                            let composed = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                                background.draw(in: CGRect(origin: .zero, size: size)); sourceImage.draw(in: bounds)
                            }
                            try composed.pngData()?.write(to: directory.appendingPathComponent("composed.png"))
                            do {
                                try await client.validate(reference: reference, background: fitted, style: style)
                                try Data("accepted".utf8).write(to: directory.appendingPathComponent("style-validation.txt"))
                            } catch {
                                try Data(error.localizedDescription.utf8).write(to: directory.appendingPathComponent("style-validation.txt"))
                            }
                        }
                    } catch {
                        try? Data(error.localizedDescription.utf8).write(to: directory.appendingPathComponent(round + "-error.txt"))
                        Issue.record("Style study \(style.id): \(error.localizedDescription)")
                    }
                }
            }
            for task in tasks { await task.value }
        }
    }
    @Test(arguments: [false, true, true]) func liveBook8FullFlowBenchmark(_ parallel: Bool) async throws {
        guard !FileManager.default.fileExists(atPath: "/tmp/traveldiary-design-flow-enabled") else { return }
        try await runFullFlow(parallel)
    }
    @Test(arguments: Array(0..<98)) func liveDesignFlow(_ index: Int) async throws {
        guard FileManager.default.fileExists(atPath: "/tmp/traveldiary-design-flow-enabled") else { return }
        let selectedCase = try String(contentsOfFile: "/tmp/traveldiary-design-flow-enabled", encoding: .utf8)
        guard selectedCase == "all" || selectedCase.split(separator: ",").contains(Substring(String(index))) else { return }
        let layouts: [DiaryAILayout] = [.hero, .story, .headline, .collage, .editorial, .automatic]
        let datasets = ["archive-city", "archive-family", "archive-food", "archive-nature", "archive-portrait", "archive-mixed"]
        let parallel = !FileManager.default.fileExists(atPath: "/tmp/traveldiary-design-flow-serial")
        if index >= 26 {
            let combination = index >= 62 ? index - 62 : index - 26
            let layoutIndex = combination / DiaryAIPageStyle.allCases.count
            let styleIndex = combination % DiaryAIPageStyle.allCases.count
            try await runFullFlow(parallel,
                                  design: .init(layout: layouts[layoutIndex], style: DiaryAIPageStyle.allCases[styleIndex]),
                                  dataset: index >= 62 ? "regression-36-\(combination)" : "cross-scene-\(combination)", mode: "guided")
        } else {
            let designIndex = index >= 8 ? (index - 8) % 6 : index % 6
            try await runFullFlow(parallel, design: .init(layout: layouts[designIndex], style: DiaryAIPageStyle.allCases[designIndex]), dataset: index >= 8 ? datasets[designIndex] : index >= 6 ? (index == 6 ? "wedding" : "coast") : nil, mode: (14..<20).contains(index) ? "textOnly" : "guided")
        }
    }
    @Test(arguments: [DiaryAILayoutMode.native, .ai])
    func liveSelectableLayoutModes(_ layoutMode: DiaryAILayoutMode) async throws {
        let marker = "/tmp/traveldiary-dual-layout-enabled"
        guard FileManager.default.fileExists(atPath: marker) else { return }
        let selection = try String(contentsOfFile: marker, encoding: .utf8)
        guard selection.isEmpty || selection == layoutMode.rawValue else { return }
        try await runFullFlow(true, design: .init(layout: .hero, style: .scenic),
                              dataset: "archive-city", mode: "textOnly", layoutMode: layoutMode)
    }
    private func runFullFlow(_ parallel: Bool, design: DiaryAIDesignSelection? = nil, dataset: String? = nil, mode: String = "guided", storyCase: Int? = nil, layoutMode: DiaryAILayoutMode? = nil) async throws {
        guard FileManager.default.fileExists(atPath: "/tmp/traveldiary-fullflow-benchmark-enabled") else { return }
        let output = URL(fileURLWithPath: "/tmp/TravelDiaryBook8Validation/fullflow-benchmark").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let parent = URL(fileURLWithPath: "/tmp/TravelDiaryBook8Validation")
        let input = try #require(FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("已排版项目-") })
        let root = output.appendingPathComponent("sandbox-" + UUID().uuidString)
        let owner = "background-live"
        let book = try await DiaryDocumentStore(ownerID: owner, baseDirectory: root).debugImportBook(from: input)
        let page = try #require(book.pages.first { $0.id.uuidString == "E7377B9C-4F4B-4943-B1F4-460568CB6748" })
        let store = DiaryDocumentStore(ownerID: owner, baseDirectory: root, bookID: book.id)
        let loaded = try await store.load(page.id)
        var sourceDocument = loaded.document
        if dataset != nil {
            var content = sourceDocument.objects[sourceDocument.rootContentID]!
            content.layers = []; content.background = nil; content.drawing = Data()
            sourceDocument.objects = [sourceDocument.rootContentID: content]
            sourceDocument.assets = [:]
        }
        let session = DiaryEditorSession(document: sourceDocument, images: dataset == nil ? loaded.images : [:], store: store)
        if let dataset {
            let input = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("DesignFixtures/" + dataset)
            func files(in folder: String) throws -> [URL] {
                let files = try FileManager.default.contentsOfDirectory(at: input.appendingPathComponent(folder), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).sorted { $0.path < $1.path }
                let currentStudy = files.filter { $0.lastPathComponent.hasPrefix("study-") }
                return currentStudy.isEmpty ? files : currentStudy
            }
            let photos = try files(in: "photos")
            #expect(await session.importPhotos(try photos.map { try Data(contentsOf: $0) }))
            for sticker in try files(in: "stickers").prefix(8) {
                #expect(await session.importPhoto(try Data(contentsOf: sticker), asSticker: true, stickerName: sticker.deletingPathExtension().lastPathComponent))
            }
        }
        let fixtureInfo = dataset.map { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("DesignFixtures/" + $0 + "/fixture-info.json") }
        defer { withExtendedLifetime(session) {} }
        let before = session.document
        let testConfig = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("DiaryIntegrationTest/runtime.json")
        try DiaryAITaskRuntime.installTestConfiguration(Data(contentsOf: testConfig))
        defer { DiaryAITaskRuntime.clearTestConfiguration() }
        let runtimeClient = DiaryArkResponsesClient()
        runtimeClient.workspaceMode = true
        let w = DiaryAIWorkspace(session: session, model: runtimeClient, root: root, parallelExecution: parallel)
        let measuredStart = Date()
        var r = DiaryAIRequest.defaults(.relayout); r.allowsText = true; r.background = .init(saveToAlbum: false); r.scene = "山野徒步"; r.location = "雨崩"
        if dataset != nil { r.scene = "不指定"; r.location = "" }
        if let storyCase {
            let scenario = storyCase / 6
            let titles = ["热气里的小确幸", "把日子读慢一点", "池边的慢时光", "雪落成诗", "花树下的我们", "和你一起看湖"]
            let stories = ["绕了几条街，终于吃到了想念的那一碗面。", "今天没有赶路，读了几页书，也看了很久的树影。", "池边坐了十分钟，才发现慢下来也能看见很多。", "手指冻得发红，还是舍不得把相机收起来。", "最喜欢这张树下合照，笑起来的那一刻很自然。", "那天风有点大，我们蹲在木栏边，笑成了一团。"]
            let locations = ["重庆·街角小店", "杭州·午后公园", "杭州·池边", "哈尔滨·冬日", "杭州·花园", "九寨沟·湖边栈道"]
            var brief = CreationBrief()
            brief.upsertStoryEntry(.init(kind: .title, text: titles[scenario], usage: .exact))
            brief.upsertStoryEntry(.init(kind: .content, text: stories[scenario], usage: storyCase % 3 == 0 ? .exact : .rewrite))
            brief.upsertStoryEntry(.init(kind: .direction, text: "保留全部照片与已有贴纸，标题醒目，旁注贴近对应照片。新增装饰少一点，文字清楚，避免遮脸。", usage: .reference))
            brief.upsertStoryEntry(.init(kind: .location, text: locations[scenario], usage: storyCase % 2 == 0 ? .exact : .reference))
            r.creationBrief = brief
        }
        r.background?.generationMode = mode
        r.design = design; r.layoutMode = layoutMode; r = r.coordinated()
        print("DESIGN_DATASET \(dataset ?? "book8")")
        print("DESIGN_CASE \(design?.layout.rawValue ?? "legacy") \(design?.style.rawValue ?? "legacy")")
        await w.enter(r, preparingNewCreation: true); w.configureAndStart(r)
        print("NATIVE_ENTRY active=\(w.active) running=\(w.running) pending=\(w.pending.count) error=\(w.error ?? "none")")
        let deadline = Date().addingTimeInterval(1200)
        var count = 0
        while w.running && Date() < deadline {
            if w.events.count != count {
                count = w.events.count
                if let e = w.events.last { print("BACKGROUND_LIVE \(e.title) \(e.detail.prefix(200))") }
                try JSONEncoder().encode(w.events).write(to: output.appendingPathComponent("events.json"), options: .atomic)
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        try JSONEncoder().encode(w.events).write(to: output.appendingPathComponent("events.json"), options: .atomic)
        // Test-only explicit retries: production never automatically repeats a paid image.
        var backgroundRetries = 0
        while w.error != nil && w.pending.isEmpty && !w.needsTextCompletion && w.backgroundRecord?.layerID == nil && w.canGenerateBackground && backgroundRetries < 2 {
            backgroundRetries += 1
            print("BENCHMARK_TEST_RETRY mode=\(parallel) attempt=\(backgroundRetries) reason=\(w.error ?? "")")
            w.generateBackground(regenerate: true)
            let retryDeadline = Date().addingTimeInterval(600)
            while w.running && Date() < retryDeadline { try await Task.sleep(for: .milliseconds(250)) }
            if w.error == nil && parallel { w.processAll(); while w.running && Date() < retryDeadline { try await Task.sleep(for: .milliseconds(250)) } }
        }
        let runFolder = output.appendingPathComponent((design.map { "design-" + (dataset.map { $0 + "-" } ?? "") + $0.layout.rawValue + "-" + $0.style.rawValue + "-" } ?? (parallel ? "parallel-" : "serial-")) + UUID().uuidString)
        try FileManager.default.createDirectory(at: runFolder, withIntermediateDirectories: true)
        if let fixtureInfo, FileManager.default.fileExists(atPath: fixtureInfo.path) {
            try FileManager.default.copyItem(at: fixtureInfo, to: runFolder.appendingPathComponent("fixture-info.json"))
        }
        try JSONEncoder().encode(r.creationBrief).write(to: runFolder.appendingPathComponent("user-input.json"), options: .atomic)
        try JSONEncoder().encode(w.events).write(to: runFolder.appendingPathComponent("events.json"), options: .atomic)
        if let png = w.backgroundPreview?.pngData() { try png.write(to: runFolder.appendingPathComponent("background.png")) }
        if let jpg = w.preview?.jpegData(compressionQuality: 0.9) { try jpg.write(to: runFolder.appendingPathComponent("composed.jpg")) }
        if let diagnostics = try? await w.exportProductionLog() {
            try FileManager.default.copyItem(at: diagnostics, to: runFolder.appendingPathComponent("production-log.zip"))
        }
        try JSONSerialization.data(withJSONObject: ["layoutMode": layoutMode?.rawValue ?? "legacy", "execution": parallel ? "parallel" : "serial", "finalModelReview": false, "mode": mode, "dataset": dataset ?? "book8", "layout": design?.layout.rawValue ?? "legacy", "style": design?.style.rawValue ?? "legacy", "elapsed": Date().timeIntervalSince(measuredStart), "error": w.error ?? "", "backgroundRetries": backgroundRetries], options: [.prettyPrinted, .sortedKeys]).write(to: runFolder.appendingPathComponent("metrics.json"))
        if let layoutMode {
            #expect(w.events.contains { $0.kind == "layout-mode" && $0.title == layoutMode.title })
            #expect(w.events.contains { $0.title == "整体构图规划" } == (layoutMode == .ai))
            #expect(w.events.contains { $0.title == "文字与贴纸并行生成提案" } == (layoutMode == .ai))
            #expect(w.events.contains { $0.kind == "native-layout" } == (layoutMode == .native))
        }
        if !parallel {
            #expect(!w.events.contains { $0.title == "背景与图层排版同时开始" || $0.title == "文字与贴纸并行生成提案" })
        }
        #expect(!w.events.contains { $0.title == "最终整页验收开始" })
        #expect(!w.running && w.backgroundRecord?.layerID != nil)
        #expect(w.error == nil)
        guard w.backgroundRecord?.layerID != nil else { return }
        #expect(w.backgroundRecord?.verified == true)
        #expect(await w.save())
        let reopened = try await store.load(page.id)
        if let brief = r.creationBrief {
            let texts = reopened.document.objects.values.flatMap(\.layers).filter { $0.kind == .text }.map(\.text)
            let missing = brief.requiredStoryTexts.filter { required in !texts.contains(where: { $0.contains(required) }) }
            let privateLocations = (brief.storyEntries ?? []).filter { $0.kind == .location && $0.usage == .reference }.map(\.text)
            let leaked = privateLocations.filter { place in texts.contains(where: { $0.contains(place) }) }
            try JSONSerialization.data(withJSONObject: ["renderedTexts": texts, "missingExactTexts": missing, "leakedReferenceLocations": leaked], options: [.prettyPrinted, .sortedKeys]).write(to: runFolder.appendingPathComponent("story-check.json"))
            #expect(missing.isEmpty)
            #expect(leaked.isEmpty)
        }
        let exported = output.appendingPathComponent("背景生成项目-" + UUID().uuidString)
        try await store.exportSourceFiles(try await store.loadBook(), to: exported)
        print("BACKGROUND_EXPORT \(exported.path)")
        #expect(reopened.document.root.layers.first?.semanticKind == .background)
        for layer in before.root.layers where layer.semanticKind != .background && layer.isLibraryBackground != true {
            #expect(reopened.document.layer(layer.id) != nil)
        }
        session.undo()
        #expect(session.scopeLayers == before.root.layers)
    }
    @Test func backgroundPromptKeepsSourceFurnitureAndRejectsBookMockups() throws {
        #expect(try DiarySeedreamBackgroundProvider.preparePrompt("左侧旧书架与木书桌，右侧暖白安静区") == "左侧旧书架与木书桌，右侧暖白安静区")
        #expect(throws: (any Error).self) { try DiarySeedreamBackgroundProvider.preparePrompt("立体书页与中央书脊") }
        #expect(try DiarySeedreamBackgroundProvider.preparePrompt("照片组下缘与文字周围保留暖白") == "预留区域组下缘与安静区周围保留暖白")
        #expect(try DiarySeedreamBackgroundProvider.preparePrompt("右侧两列照片之间的空隙保留暖白，不与任何照片内部地平线对齐。文字与旁注区域保持素净。") == "右侧两列预留区域之间的空隙保留暖白，不与任何局部水平线对齐。安静区域保持素净。")
    }
    @Test func liveBook8Background() async throws {
        guard FileManager.default.fileExists(atPath: "/tmp/traveldiary-background-live-enabled") else { return }
        let output = URL(fileURLWithPath: "/tmp/TravelDiaryBook8Validation/background")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let parent = URL(fileURLWithPath: "/tmp/TravelDiaryBook8Validation")
        let input = try #require(FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("已排版项目-") })
        let root = output.appendingPathComponent("sandbox-" + UUID().uuidString)
        let owner = "background-live"
        let book = try await DiaryDocumentStore(ownerID: owner, baseDirectory: root).debugImportBook(from: input)
        let page = try #require(book.pages.first { $0.id.uuidString == "E7377B9C-4F4B-4943-B1F4-460568CB6748" })
        let store = DiaryDocumentStore(ownerID: owner, baseDirectory: root, bookID: book.id)
        let loaded = try await store.load(page.id)
        let session = DiaryEditorSession(document: loaded.document, images: loaded.images, store: store)
        let before = session.document
        let w = DiaryAIWorkspace(session: session, root: root)
        var r = request(); r.scene = "山野徒步"; r.location = "雨崩"
        await w.enter(r, preparingNewCreation: true); w.configureAndStart(r)
        print("NATIVE_ENTRY active=\(w.active) running=\(w.running) pending=\(w.pending.count) error=\(w.error ?? "none")")
        let deadline = Date().addingTimeInterval(650)
        var count = 0
        while w.running && Date() < deadline {
            if w.events.count != count {
                count = w.events.count
                if let e = w.events.last { print("BACKGROUND_LIVE \(e.title) \(e.detail.prefix(200))") }
                try JSONEncoder().encode(w.events).write(to: output.appendingPathComponent("events.json"), options: .atomic)
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        try JSONEncoder().encode(w.events).write(to: output.appendingPathComponent("events.json"), options: .atomic)
        if let png = w.backgroundPreview?.pngData() { try png.write(to: output.appendingPathComponent("background.png")) }
        if let jpg = w.preview?.jpegData(compressionQuality: 0.9) { try jpg.write(to: output.appendingPathComponent("composed.jpg")) }
        print("BACKGROUND_LIVE_RESULT \(w.error ?? w.stage)")
        #expect(!w.running && w.backgroundRecord?.layerID != nil)
        guard w.backgroundRecord?.layerID != nil else { return }
        #expect(w.backgroundRecord?.albumState == "saved")
        #expect(await w.save())
        let reopened = try await store.load(page.id)
        let exported = output.appendingPathComponent("背景生成项目-" + UUID().uuidString)
        try await store.exportSourceFiles(try await store.loadBook(), to: exported)
        print("BACKGROUND_EXPORT \(exported.path)")
        #expect(reopened.document.root.layers.first?.semanticKind == .background)
        for layer in before.root.layers where layer.semanticKind != .background && layer.isLibraryBackground != true {
            #expect(reopened.document.layer(layer.id) == layer)
        }
        session.undo()
        #expect(session.scopeLayers == before.root.layers)
    }
    @Test func backgroundSettingsSnapshot() async throws {
        let (session, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let runtime = session.canvasAI
        runtime.restoreIfNeeded()
        let end = Date().addingTimeInterval(5)
        while !runtime.restored && Date() < end { try await Task.sleep(for: .milliseconds(10)) }
        var form = DiaryAIRequest.defaults(.relayout); form.background = .init()
        runtime.setForm(form)
        let host = UIHostingController(rootView: DiaryAIRequestSheet(controller: runtime, action: .relayout))
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
        host.view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(200))
        let data = try #require(UIGraphicsImageRenderer(size: window.bounds.size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }.pngData())
        try data.write(to: URL(fileURLWithPath: "/tmp/diary-background-settings.png"))
        Attachment.record(Array(data), named: "background-settings.png"); window.isHidden = true
    }
    @Test func productionLogExportsImagesAndRedactsCredentials() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = DiaryAIProductionLog(owner: "test", page: UUID(), root: root)
        log.registerSecret("secret")
        log.record("request", ["Authorization": "Bearer secret", "prompt": "测试", "image": "data:image/png;base64,AQI="])
        for i in 0..<4000 { log.record("sse", ["delta": "a", "index": i]) }
        let archive = try await log.export()
        let combined = try String(contentsOf: log.directory.appendingPathComponent("events.jsonl"), encoding: .utf8)
        #expect(!combined.contains("Bearer secret") && combined.contains("attachments") && combined.contains("测试"))
        let rows = combined.split(separator: "\n")
        #expect(rows.count == 4002)
        let files = try FileManager.default.contentsOfDirectory(at: log.directory, includingPropertiesForKeys: nil)
        #expect(files.count == 2)
        #expect(FileManager.default.fileExists(atPath: log.directory.appendingPathComponent("attachments").path))
        let unpacked = root.appendingPathComponent("export-check")
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: archive, to: unpacked)
        let exported = try FileManager.default.subpathsOfDirectory(atPath: unpacked.path).first { $0.hasSuffix("events.jsonl") }
        let exportedText = try String(contentsOf: unpacked.appendingPathComponent(try #require(exported)), encoding: .utf8)
        #expect(exportedText.contains("payload") && exportedText.contains("测试"))
        #expect(!exportedText.contains("Bearer secret"))
        #expect((try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0)
    }
    @Test func activityGroupsPreserveRequestsErrorsAndBatchBoundaries() {
        let values: [DiaryAIWorkspaceEvent] = [
            .init(kind: "checkpoint", title: "恢复点", detail: ""),
            .init(kind: "phase", title: "整体构图规划", detail: ""),
            .init(kind: "request", title: "发送", detail: ""),
            .init(kind: "transport", title: "连接", detail: ""),
            .init(kind: "phase", title: "第 1 批 · L2、L3", detail: ""),
            .init(kind: "request", title: "发送", detail: ""),
            .init(kind: "tool", title: "移动", detail: ""),
            .init(kind: "error", title: "移动失败", detail: "版本错误"),
            .init(kind: "result", title: "L2 · 摆放", detail: "暂存"),
            .init(kind: "batch", title: "本批完成", detail: "")
        ]
        let groups = DiaryAIActivityGroup.build(values)
        #expect(groups.count == 3)
        #expect(groups.flatMap(\.events).map(\.id) == values.map(\.id))
        #expect(groups.reduce(0) { $0 + $1.requests } == 2)
        #expect(groups.last?.summaries.contains { $0.kind == "error" } == true)
        #expect(groups.last?.summaries.contains { $0.kind == "tool" } == false)
        #expect(DiaryAIActivityGroup.build([]).isEmpty)
    }
    @Test func boundVersionRejectsStaleValuesAndSuppliesMissingVersion() throws {
        let call = DiaryAIToolCall(id: "a", name: "finish_batch", arguments: "{}")
        let bound = try DiaryArkResponsesClient.bindVersion(call, version: 5)
        let raw = try #require(JSONSerialization.jsonObject(with: Data(bound.arguments.utf8)) as? [String: Any])
        #expect(raw["expectedVersion"] as? Int == 5)
        #expect(throws: (any Error).self) { try DiaryArkResponsesClient.bindVersion(.init(id: "b", name: "finish_batch", arguments: "{\"expectedVersion\":4}"), version: 5) }
    }
    @Test func backgroundAnalysisExplainsTruncation() {
        #expect(throws: (any Error).self) { try DiarySeedreamBackgroundProvider.requireComplete(["status": "incomplete", "incomplete_details": ["reason": "length"]]) }
    }
    @Test func backgroundRequiresTextCompletionOrExplicitSkip() async throws {
        let (session, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let provider = BackgroundFake(try image()), album = BackgroundAlbumFake()
        let w = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
        var r = DiaryAIRequest.defaults(.relayout); r.allowsText = true; r.selectedOnly = false
        r.background = .init()
        await w.enter(r)
        #expect(w.needsTextCompletion && !w.canGenerateBackground)
        w.generateBackground()
        #expect(provider.generations == 0)
        await w.skipPendingText()
        #expect(w.needsTextCompletion && !w.canContinueText)
        await w.keepForLater()
        let restored = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
        await restored.enter(r)
        #expect(restored.needsTextCompletion && !restored.canContinueText)
    }
    @Test func negativeSubjectListDoesNotBlockParallelBackground() throws {
        let cleaned = try DiarySeedreamBackgroundProvider.preparePrompt("暖白纸底，深绿山谷与彩旗。不出现水岸、建筑、人物或任何文字。")
        #expect(cleaned.contains("深绿山谷与彩旗"))
        #expect(!cleaned.contains("人物"))
        #expect(throws: (any Error).self) { try DiarySeedreamBackgroundProvider.preparePrompt("暖白纸底，人物站在山谷中。") }
    }
    @Test func promptRepairKeepsThemeAndDoesNotEraseSubjectInstructions() throws {
        let source = "左上区域在照片后方延展淡黄色与淡粉色的小色块与细黑线条。右侧中部照片群之后，用细黑线勾一条柔和的屋檐轮廓。"
        #expect(try DiarySeedreamBackgroundProvider.preparePrompt("浅米色从左侧照片群下方向右延伸") == "浅米色从左侧预留区域下方向右延伸")
        let fixed = try DiarySeedreamBackgroundProvider.preparePrompt(source)
        #expect(!fixed.contains("照片"))
        #expect(fixed.contains("左上区域") && fixed.contains("淡黄色") && fixed.contains("屋檐"))
        #expect(try DiarySeedreamBackgroundProvider.preparePrompt(fixed) == fixed)
        #expect(throws: (any Error).self) { try DiarySeedreamBackgroundProvider.preparePrompt("绘制三张照片和人物") }
    }
    @Test func restoreAppliesNewBackgroundSettingsAndPreservesProgress() async throws {
        let (session, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let provider = BackgroundFake(try image()), album = BackgroundAlbumFake()
        let first = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
        var r = DiaryAIRequest.defaults(.relayout)
        await first.enter(r)
        let pending = first.pending
        await first.keepForLater()
        r.background = .init(style: "doodle")
        let second = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
        await second.enter(r)
        #expect(second.active && second.hasBackgroundRequest)
        #expect(second.pending == pending && second.version == first.version)
        #expect(second.events.contains { $0.title == "已将新设置应用到恢复任务" })
        #expect(provider.generations == 0)
        await second.keepForLater()
        let third = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
        await third.enter(r)
        #expect(third.hasBackgroundRequest && third.pending == pending)
    }
    @Test func exactRatioAndNoStretch() throws {
        #expect(try DiaryAIBackgroundImaging.exactSize(CGSize(width: 4370, height: 3130)) == CGSize(width: 1311, height: 939))
        #expect(try DiaryAIBackgroundImaging.exactSize(CGSize(width: 2003, height: 1009)) == CGSize(width: 2003, height: 1009))
        #expect(throws: (any Error).self) { try DiaryAIBackgroundImaging.exactSize(CGSize(width: CGFloat.nan, height: 1)) }
        #expect(throws: (any Error).self) { try DiaryAIBackgroundImaging.prepare(image(CGSize(width: 500, height: 500)), canvas: CGSize(width: 4370, height: 3130)) }
        let bytes = try DiaryAIBackgroundImaging.prepare(image(CGSize(width: 1400, height: 1000)), canvas: CGSize(width: 4370, height: 3130))
        let cg = try #require(UIImage(data: bytes)?.cgImage)
        #expect(cg.width * 3130 == cg.height * 4370)
    }
    @Test func selectedStyleReachesGenerationAndQualityCheckWithoutExtraRequests() async throws {
        for style in DiaryAIBackgroundStyle.all {
            let (session, root) = try await fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            let provider = BackgroundFake(try image()), album = BackgroundAlbumFake()
            let workspace = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
            var r = request(); r.background?.style = style.id; r.background?.saveToAlbum = false
            await workspace.enter(r); workspace.processAll(); try await wait(workspace)
            #expect(workspace.error == nil)
            #expect(provider.checkedStyle == style.id)
            #expect(provider.generatedPrompt?.contains(style.name) == true)
            #expect(provider.generations == 1 && provider.validations == 1)
            #expect(album.saves == 0 && workspace.backgroundRecord?.verified == true)
        }
    }
    @Test func requestContractAndBackwardDecoding() throws {
        let body = DiarySeedreamBackgroundProvider.body(reference: Data([1,2]), prompt: "背景")
        #expect(body["model"] == nil) // Model is injected from the task configuration at transport time.
        #expect(body["watermark"] as? Bool == false)
        #expect(body["stream"] as? Bool == false)
        #expect(body["image"] as? String == "data:image/jpeg;base64,AQI=")
        var old = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request())) as? [String: Any])
        old.removeValue(forKey: "background")
        #expect(try JSONDecoder().decode(DiaryAIRequest.self, from: JSONSerialization.data(withJSONObject: old)).background == nil)
    }
    @Test func backgroundSaveReopenAndUndoPreserveForeground() async throws {
        let (session, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = session.document, provider = BackgroundFake(try image()), album = BackgroundAlbumFake()
        let workspace = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
        await workspace.enter(request()); workspace.processAll(); try await wait(workspace)
        #expect(workspace.error == nil)
        // Album delivery is independent of canvas completion; await its durable terminal state.
        for _ in 0..<200 where workspace.backgroundRecord?.albumState != "saved" {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(workspace.backgroundRecord?.albumState == "saved")
        #expect(provider.generations == 1 && provider.downloads == 1 && provider.validations == 1 && album.saves == 1)
        #expect(session.document == before)
        workspace.processAll(); try await wait(workspace)
        #expect(provider.generations == 1 && album.saves == 1)
        #expect(await workspace.save())
        let reloaded = try await session.store.load(session.document.id)
        #expect(reloaded.document.root.layers.first?.semanticKind == .background)
        for layer in before.root.layers { #expect(reloaded.document.layer(layer.id) == layer) }
        #expect(session.undoStack.count == 1)
        session.undo(); #expect(session.scopeLayers == before.root.layers)
    }
    @Test func downloadAndAlbumRetryNeverRegenerate() async throws {
        let (session, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let provider = BackgroundFake(try image()), album = BackgroundAlbumFake(); provider.failDownload = true; album.fails = true
        let w = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
        await w.enter(request()); w.processAll(); try await wait(w)
        #expect(w.error != nil && provider.generations == 1)
        w.generateBackground(); try await wait(w)
        #expect(w.backgroundRecord?.layerID != nil && w.canRetryAlbum)
        #expect(provider.generations == 1 && provider.downloads == 2)
        album.fails = false; w.retryBackgroundAlbum(); try await wait(w)
        #expect(w.backgroundRecord?.albumState == "saved" && provider.generations == 1)
    }
    @Test func failedQualityCanResumeWithoutNewImageRequest() async throws {
        let (session, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let provider = BackgroundFake(try image()), album = BackgroundAlbumFake(); provider.failQuality = true
        let w = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
        await w.enter(request()); w.processAll(); try await wait(w)
        #expect(w.backgroundRecord?.layerID == nil && album.saves == 0)
        await w.keepForLater()
        let resumed = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
        await resumed.enter(request()); provider.failQuality = false
        resumed.generateBackground(); try await wait(resumed)
        #expect(resumed.error == nil && provider.generations == 1 && provider.downloads == 1)
        await resumed.rollback()
        #expect(resumed.backgroundRecord == nil)
    }
    @Test(arguments: ["generation", "download", "quality", "invalidImage"])
    func injectedBackgroundFailureWaitsForManualContinue(_ failure: String) async throws {
        let (session, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let valid = try image()
        let provider = BackgroundFake(failure == "invalidImage" ? Data([0, 1, 2]) : valid)
        provider.failGeneration = failure == "generation"
        provider.failDownload = failure == "download"
        provider.failQuality = failure == "quality"
        let workspace = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: BackgroundAlbumFake())
        var r = request(); r.background?.saveToAlbum = false
        await workspace.enter(r)
        workspace.processAll()
        try await wait(workspace)
        #expect(workspace.error != nil && workspace.backgroundRecord?.layerID == nil)
        let counts = [provider.generations, provider.downloads, provider.validations]
        try await Task.sleep(for: .milliseconds(150))
        #expect(counts == [provider.generations, provider.downloads, provider.validations])
        provider.failGeneration = false; provider.failQuality = false; provider.data = valid
        workspace.processAll()
        try await wait(workspace)
        #expect(workspace.error == nil && workspace.backgroundRecord?.layerID != nil)
        #expect(provider.generations == (failure == "generation" ? 2 : 1))
    }
    @Test func restartAfterFailureRestoresInputsAndWaitsForStart() async throws {
        let (session, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = BackgroundFake(try image()); provider.failGeneration = true
        let workspace = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: BackgroundAlbumFake())
        await workspace.enter(request()); workspace.processAll(); try await wait(workspace)
        #expect(workspace.error != nil && workspace.canRestartProduction)
        await workspace.restartProduction()
        #expect(workspace.error == nil && workspace.backgroundRecord == nil && !workspace.running)
        let attempts = provider.generations
        try await Task.sleep(for: .milliseconds(150))
        #expect(provider.generations == attempts)
        provider.failGeneration = false
        workspace.processAll(); try await wait(workspace)
        #expect(workspace.error == nil && workspace.backgroundRecord?.layerID != nil)
    }
    @Test func restartRejectsLateBackgroundAndRetainsInputs() async throws {
        let (session, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = BackgroundFake(try image()); provider.delay = true
        let album = BackgroundAlbumFake()
        let w = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
        await w.enter(request())
        let ids = Set(w.objects.map(\.id))
        w.processAll()
        for _ in 0..<200 where provider.generations == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(provider.generations > 0)
        await w.restartProduction()
        #expect(!w.running && w.backgroundRecord == nil && w.error == nil)
        #expect(Set(w.objects.map(\.id)) == ids)
        #expect(album.saves == 0)
        await w.keepForLater()
        let restored = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
        await restored.enter(request())
        #expect(restored.canRestartProduction && Set(restored.objects.map(\.id)) == ids)
        let count = provider.generations
        try await Task.sleep(for: .milliseconds(200))
        #expect(provider.generations == count && restored.backgroundRecord == nil)
    }
    @Test func cancellationCannotApplyLateGeneration() async throws {
        let (session, root) = try await fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let before = session.document, provider = BackgroundFake(try image()), album = BackgroundAlbumFake(); provider.delay = true
        let w = DiaryAIWorkspace(session: session, root: root, backgroundProvider: provider, albumSaver: album)
        await w.enter(request()); w.processAll()
        for _ in 0..<200 where provider.generations == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(provider.generations > 0)
        w.pause(); try await Task.sleep(for: .milliseconds(250))
        #expect(w.backgroundRecord?.layerID == nil && album.saves == 0 && session.document == before)
    }
}

@MainActor final class BackgroundFake: DiaryAIBackgroundProvider {
    var data: Data; var generations = 0; var downloads = 0; var validations = 0
    var checkedStyle: String?; var generatedPrompt: String?
    var failGeneration = false
    var failDownload = false; var failQuality = false; var delay = false
    init(_ data: Data) { self.data = data }
    func generate(reference: Data, prompt: String) async throws -> URL {
        generations += 1; generatedPrompt = prompt
        if failGeneration { throw URLError(.timedOut) }
        if delay { try? await Task.sleep(for: .milliseconds(200)) }
        return URL(string: "https://example.com/background.png")!
    }
    func download(_ url: URL) async throws -> Data {
        downloads += 1
        if failDownload { failDownload = false; throw URLError(.networkConnectionLost) }
        return data
    }
    func validate(reference: Data, background: Data, style: DiaryAIBackgroundStyle) async throws {
        checkedStyle = style.id
        try await validate(reference: reference, background: background)
    }
    func validate(reference: Data, background: Data) async throws {
        validations += 1
        if failQuality { throw DiaryAIError.invalid("重复照片") }
    }
}
@MainActor final class BackgroundAlbumFake: DiaryAIBackgroundAlbumSaving {
    var saves = 0; var fails = false
    func save(_ data: Data) async throws { saves += 1; if fails { throw DiaryAIError.invalid("没有相册权限") } }
}
