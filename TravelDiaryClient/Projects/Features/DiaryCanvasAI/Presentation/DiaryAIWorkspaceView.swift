import SwiftUI
import UniformTypeIdentifiers

struct DiaryAIWorkspaceView: View {
    var onCloseDetails: (() -> Void)? = nil
    @ObservedObject var workspace: DiaryAIWorkspace
    @State private var exitConfirmation = false
    @State private var saveConfirmation = false
    @State private var showOriginal = false
    @State private var zoom: CGFloat = 1
    @GestureState private var gestureZoom: CGFloat = 1
    @State private var imageDetail: UIImage?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 10) {
                    canvas
                        .frame(height: max(120, geometry.size.height * (workspace.panelVisible ? 0.38 : 0.62)))
                    tray
                    if !workspace.panelVisible {
                        Button { workspace.panelVisible = true } label: {
                            Label(workspace.stage, systemImage: workspace.running ? "sparkles" : "list.bullet.rectangle")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.bordered)
                    }
                    if workspace.panelVisible {
                        panel
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                    }
                    Spacer(minLength: 0)
                }.padding(.horizontal, 12).padding(.top, 8)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("AI 排版")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("退出") { exitConfirmation = true } }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button { showOriginal.toggle() } label: { Image(systemName: showOriginal ? "rectangle.on.rectangle.slash" : "rectangle.on.rectangle") }.accessibilityLabel("对比排版前")
                    Button("保存") { saveConfirmation = true }.disabled(workspace.running)
                    DiaryProductionQuotaButton()
                }
            }

            .confirmationDialog("退出 AI 排版", isPresented: $exitConfirmation, titleVisibility: .visible) {
                Button("继续处理", role: .cancel) {}
                Button("保留进度，稍后继续") { Task { await workspace.keepForLater() } }
                Button("放弃本轮，恢复原版", role: .destructive) { Task { await workspace.exitRestoringOriginal() } }
            } message: { Text("已完成批次有独立恢复点，未保存前不会覆盖正式作品。") }
            .confirmationDialog("保存当前排版", isPresented: $saveConfirmation, titleVisibility: .visible) {
                if workspace.pending.isEmpty { Button("保存到作品") { Task { _ = await workspace.save() } } }
                else { Button("保存已完成部分，保留待排素材") { Task { _ = await workspace.save() } } }
                Button("继续排版", role: .cancel) {}
            } message: { Text(workspace.requiresResultRecording ? "保存当前成果。也可以保留进度，稍后继续。" : workspace.pending.isEmpty ? "发布为正式作品，可一次撤销整轮排版。" : "还有 \(workspace.pending.count) 项待排。保存后待排素材仍保留在项目中，但暂不显示在页面或导出中；下次进入可继续排版。") }
            .alert("AI 排版", isPresented: Binding(get: { workspace.error != nil && !workspace.panelVisible }, set: { if !$0 { workspace.error = nil } })) {
                Button("查看过程") { workspace.panelVisible = true }
            } message: { Text(workspace.error ?? "") }
            .onChange(of: scenePhase) { _, phase in if phase == .background && workspace.running { workspace.pause() } }
            .interactiveDismissDisabled()
        }.tint(Color(red: 0.24, green: 0.39, blue: 0.34))
            .modifier(DiaryMakingCinemaModifier(workspace: workspace))
    }
    private var canvas: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear
                if let image = showOriginal ? workspace.original : workspace.preview {
                    Image(uiImage: image).resizable().scaledToFit().padding(8)
                        .scaleEffect(zoom * gestureZoom)
                        .gesture(MagnifyGesture().updating($gestureZoom) { value, state, _ in state = value.magnification }
                            .onEnded { zoom = min(3, max(0.5, zoom * $0.magnification)) })
                } else { ProgressView("准备画布") }
            }.clipped().overlay(alignment: .topLeading) {
                Label(showOriginal ? "排版前" : "工作版本 \(workspace.version)", systemImage: "lock")
                    .font(.caption2).padding(6).background(.regularMaterial, in: Capsule()).padding(6)
            }
            .dropDestination(for: String.self) { values, point in
                guard !showOriginal else { return false }
                let ids = values.flatMap { $0.split(separator: ",").compactMap { UUID(uuidString: String($0)) } }
                guard !ids.isEmpty else { return false }
                let hint: CGPoint?
                if let image = workspace.preview {
                    let ratio = min((geometry.size.width - 16) / image.size.width, (geometry.size.height - 16) / image.size.height)
                    let origin = CGPoint(x: (geometry.size.width - image.size.width * ratio) / 2, y: (geometry.size.height - image.size.height * ratio) / 2)
                    // Drop is a soft page-relative preference, not a direct document mutation.
                    hint = CGPoint(x: min(1, max(0, (point.x - origin.x) / (image.size.width * ratio))), y: min(1, max(0, (point.y - origin.y) / (image.size.height * ratio))))
                } else { hint = nil }
                workspace.enqueue(ids, hint: hint); return true
            }
        }
    }
    private var tray: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("待排素材 · \(workspace.pending.count)").font(.subheadline.weight(.semibold))
                Spacer()
                if !workspace.selected.isEmpty {
                    Button("处理选中 \(workspace.selected.count) 项") { workspace.processSelected() }.font(.caption)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(workspace.pending, id: \.self) { id in
                        let object = workspace.objects.first { $0.id == id }
                        VStack(spacing: 4) {
                            ZStack(alignment: .topTrailing) {
                                RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .secondarySystemGroupedBackground))
                                if let image = workspace.thumbnails[id] { Image(uiImage: image).resizable().scaledToFit().padding(4) }
                                else { Image(systemName: object?.role == "text" ? "textformat" : "square.3.layers.3d").padding() }
                                if workspace.processing.contains(id) { ProgressView().padding(4) }
                                else if workspace.selected.contains(id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, Color(red: 0.24, green: 0.39, blue: 0.34)) }
                            }.frame(width: 72, height: 64)
                            Text(object?.shortID ?? "素材").font(.caption2)
                        }.contentShape(Rectangle()).onTapGesture { workspace.toggle(id) }
                            .draggable(workspace.selected.contains(id) ? workspace.selected.map(\.uuidString).joined(separator: ",") : id.uuidString)
                            .accessibilityLabel("\(object?.shortID ?? "") \(object?.name ?? "素材")，点击选择或拖入画布")
                    }
                }
            }
            if workspace.pending.isEmpty { Text("素材已放入画布，可对比原版并保存。 ").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var panel: some View {
        DiaryAIProgressPanel(workspace: workspace, onCloseDetails: onCloseDetails, onExit: {
            workspace.panelVisible = false
            exitConfirmation = true
        })
    }
}

/// Owns presentation state in both the editor sheet and the full workspace.
private struct DiaryAIProgressPanel: View {
    @ObservedObject var workspace: DiaryAIWorkspace
    var onCloseDetails: (() -> Void)? = nil
    var onExit: (() -> Void)? = nil
    @State private var logURL: URL?
    @State private var exportingLog = false
    @State private var regenerateBackground = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if let error = workspace.error { Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.orange).padding(12) }
                        if workspace.canContinueText && !workspace.running {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("待添加文字").font(.headline)
                                Text("背景将在文字完成或你明确跳过后生成。").font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Button("继续添加文字") { workspace.processAll() }.buttonStyle(.borderedProminent)
                                    Button("跳过文字") { Task { await workspace.skipPendingText() } }.buttonStyle(.bordered)
                                }
                            }
                        }
                        if workspace.hasBackgroundRequest {
                            VStack(alignment: .leading, spacing: 10) {
                                if let image = workspace.backgroundPreview {
                                    Text("纯背景").font(.headline)
                                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180)
                                }
                                if workspace.canGenerateBackground {
                                    HStack {
                                        if workspace.backgroundRecord?.layerID == nil { Button("继续背景任务") { workspace.generateBackground() }.buttonStyle(.bordered) }
                                        Button("重新生成背景") { regenerateBackground = true }.buttonStyle(.bordered)
                                    }
                                }
                                if workspace.canRetryAlbum {
                                    Button("保存背景到相册") { workspace.retryBackgroundAlbum() }.buttonStyle(.bordered)
                                    if workspace.backgroundRecord?.albumState == "saving" { Text("上次写入结果不确定，请先检查相册，避免重复保存。").font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                        let groups = DiaryAIActivityGroup.build(workspace.events)
                        HStack {
                            Text("\(workspace.events.filter { $0.kind == "request" }.count) 次 AI 请求 · \(workspace.events.count) 条过程记录")
                            Spacer()
                        }.font(.caption).foregroundStyle(.secondary)
                        ForEach(groups) { group in
                            DiaryAIActivityCard(group: group, running: workspace.running && group.id == groups.last?.id)
                                .id(group.id)
                        }
                        Color.clear.frame(height: 1).id("activity-bottom")
                        if workspace.running { HStack { ProgressView(); Text(workspace.stage).font(.subheadline) }.padding(12) }
                    }.padding(16)
                }
                .overlay(alignment: .bottomTrailing) {
                    Button { withAnimation { proxy.scrollTo("activity-bottom", anchor: .bottom) } } label: { Image(systemName: "arrow.down").padding(10).background(.regularMaterial, in: Circle()) }.padding(12).accessibilityLabel("回到最新操作")
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(workspace.running ? "正在排版" : "排版进度")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("收起") { if let onCloseDetails { onCloseDetails() } else { workspace.panelVisible = false } } }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button { exportingLog = true; Task {
                        do { logURL = try await workspace.exportProductionLog() } catch { workspace.error = error.localizedDescription }
                        exportingLog = false
                    } } label: { if exportingLog { ProgressView() } else { Label("导出", systemImage: "square.and.arrow.up") } }.disabled(exportingLog)
                    if let onExit {
                        Button("退出", action: onExit)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("回退上一批") { Task { await workspace.rollback() } }.disabled(!workspace.canRollback)
                    Spacer()
                    if workspace.running { Button("暂停", role: .destructive) { workspace.pause() }.buttonStyle(.bordered) }
                    else { Button(workspace.isBackgroundOnly ? "生成背景" : "处理全部") { workspace.processAll() }.buttonStyle(.borderedProminent) }
                }.padding(16).background(.bar)
            }
        }
            .confirmationDialog("重新生成背景会发起新的付费请求", isPresented: $regenerateBackground, titleVisibility: .visible) {
                Button("重新生成") { workspace.generateBackground(regenerate: true) }
                Button("取消", role: .cancel) {}
            }
        .sheet(isPresented: Binding(get: { logURL != nil }, set: { if !$0 { logURL = nil } })) {
            if let url = logURL { DiaryAILogShareSheet(url: url) }
        }

    }
}

private struct DiaryAILogShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Embedded in the editor: the native canvas keeps its shell and viewport.
struct DiaryAIInlinePanel: View {
    @ObservedObject var workspace: DiaryAIWorkspace
    @ObservedObject var controller: DiaryAIDraftController
    @State private var customizing = false
    @State private var editingStory: DiaryStoryEntry?
    @State private var showingDetails = false
    @State private var action = DiaryAIAction.relayout
    @State private var design = DiaryAIDesignSelection()
    var onPhotos: () -> Void = {}
    var onBeginCreation: () -> Void = {}
    var onCamera: () -> Void = {}
    var onStickers: () -> Void = {}
    var onDesign: (DiaryAIDesignSelection) -> Void = { _ in }
    @State private var tab = 2
    @State private var inspecting: UUID?
    @State private var instruction = ""
    @State private var photoNote = ""
    @State private var started = false
    @State private var selectedLayoutMode: DiaryAILayoutMode?
    @AppStorage(DiaryAILayoutMode.preferenceKey) private var preferredLayoutMode: DiaryAILayoutMode = .native
    private var layoutMode: DiaryAILayoutMode {
        selectedLayoutMode ?? workspace.currentRequest.layoutMode ?? preferredLayoutMode
    }
    private var photos: [DiaryAIObject] { workspace.objects.filter { $0.role == "photo" } }
    private var stickers: [DiaryAIObject] { workspace.objects.filter { ["decoration", "group", "textImage"].contains($0.role) } }
    private var materialPhotos: [DiaryAIObject] {
        photos.filter { !(started || workspace.running) || workspace.pending.contains($0.id) }
    }
    private var materialStickers: [DiaryAIObject] {
        stickers.filter { !(started || workspace.running) || workspace.pending.contains($0.id) }
    }
    private var complete: Bool { started && !workspace.running && workspace.pending.isEmpty && !workspace.needsTextCompletion && workspace.error == nil && (!workspace.hasBackgroundRequest || workspace.backgroundPreview != nil) }
    var body: some View {
        VStack(spacing: 10) {
            if started || workspace.running {
              VStack(spacing: 0) {
                materialPage
                Spacer(minLength: 24)
                VStack(spacing: 16) {
                    HStack { Text(workspace.stage).font(.headline); Spacer(); Button("详情") { showingDetails = true }.accessibilityIdentifier("diary.ai.details") }
                    if workspace.running { ProgressView() }
                    if let mode = workspace.currentRequest.layoutMode {
                        Text(mode.title).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("已放入画布 \(max(0, workspace.objects.count - workspace.pending.count)) 项 · 待处理 \(workspace.pending.count) 项").font(.caption).foregroundStyle(.secondary)
                    if let error = workspace.error { Text(error).font(.caption).foregroundStyle(.orange).lineLimit(3) }
                    HStack {
                        Button("回退上一批") { Task { await workspace.rollback() } }.disabled(!workspace.canRollback)
                        Spacer()
                        Button("重新开始制作") { Task { await workspace.restartProduction(); started = false } }
                            .disabled(!workspace.canRestartProduction)
                        if complete { Button("调整排版") { Task { await workspace.prepareLayoutAdjustment(); started = false } }; Button("重新生成背景") { workspace.generateBackground(regenerate: true) }.disabled(!workspace.hasBackgroundRequest) }
                    }.font(.caption)
                }.padding(.bottom, 20)
              }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                  VStack(spacing: 10) {
                    materialPage
                    if let error = workspace.error {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                    HStack(spacing: 8) {
                        designToggle("排版 · " + design.layout.name, symbol: "rectangle.3.group", value: 1)
                        designToggle("风格 · " + design.style.name, symbol: "paintpalette", value: 2)
                    }
                    if tab != 0 {
                      ScrollViewReader { reader in
                        ScrollView(.horizontal, showsIndicators: false) {
                          LazyHStack(spacing: 10) {
                            if tab == 1 {
                                ForEach(DiaryAILayout.allCases) { item in
                                    choice(item.name, selected: design.layout == item, action: { design.layout = item }) {
                                        Image("TravelLayout-" + item.rawValue).resizable().scaledToFit()
                                    }.id(item.rawValue)
                                }
                            } else {
                                ForEach(DiaryAIPageStyle.allCases) { item in
                                    choice(item.name, selected: design.style == item, action: { design.style = item }) {
                                        Image("TravelStyle-" + item.rawValue).resizable().scaledToFill().frame(width: 152, height: 108).clipped()
                                    }.id(item.rawValue)
                                }
                            }
                          }.padding(2)
                        }.frame(height: 148)
                        .onAppear { reader.scrollTo(tab == 1 ? design.layout.rawValue : design.style.rawValue, anchor: .center) }
                        .onChange(of: tab) { _, value in
                            reader.scrollTo(value == 1 ? design.layout.rawValue : design.style.rawValue, anchor: .center)
                        }
                        .onChange(of: design) { _, value in
                            reader.scrollTo(tab == 1 ? value.layout.rawValue : value.style.rawValue, anchor: .center)
                        }
                      }
                    }
                  }.padding(.bottom, 2)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            HStack(spacing: 12) {
                storyTags
                Button(!workspace.preparingPhotos.isEmpty ? "照片准备中" : workspace.running ? "暂停" : workspace.needsSaveRetry ? "重试保存" : storyChanged && started ? "按新故事重新制作" : complete ? "保存作品" : photos.isEmpty && !started ? "添加照片" : started ? (workspace.error == nil ? "继续制作" : "重试本步") : "开始制作") {
                    if workspace.running { workspace.pause() }
                    else if workspace.needsSaveRetry { Task { _ = await workspace.save() } }
                    else if storyChanged && started {
                        Task {
                            guard await workspace.prepareStoryAdjustment() else { return }
                            var request = controller.form(action); request.design = design
                            request.layoutMode = workspace.currentRequest.layoutMode ?? layoutMode
                            workspace.configureAndStart(request)
                        }
                    }
                    else if complete { Task { _ = await workspace.save() } }
                    else if photos.isEmpty && !started { onBeginCreation() }
                    else if started { workspace.processAll() }
                    else {
                        var request = controller.form(action); request.design = design; request.selectedOnly = false
                        if request.creationBrief == nil { request.creationBrief = workspace.currentCreationBrief }
                        if let notes = request.creationNotes {
                            let valid = Set(photos.map { $0.id.uuidString })
                            let lines = notes.filter { valid.contains($0.key) && !$0.value.isEmpty }.sorted { $0.key < $1.key }.map { "照片\($0.key)：\($0.value)" }
                            if !lines.isEmpty { request.instruction += "\n用户逐照片说明：\n" + lines.joined(separator: "\n") }
                        }
                        request.layoutMode = layoutMode
                        workspace.configureAndStart(request)
                    }
                }.buttonStyle(.borderedProminent).controlSize(.large)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(!workspace.active || workspace.saving || workspace.addingMaterials || !workspace.preparingPhotos.isEmpty)
            }
        }.padding(16).frame(maxWidth: .infinity).background(DiaryLibraryStyle.background)
            .tint(Color(red: 0.24, green: 0.39, blue: 0.34))
            .onAppear {
                controller.restoreIfNeeded()
                design = controller.form(action).design ?? workspace.currentDesign ?? .init()
                onDesign(design)
                started = workspace.hasStartedWork
            }
            .onChange(of: workspace.active) { _, active in
                if active { started = workspace.hasStartedWork }
            }
            .onChange(of: workspace.running) { _, running in
                if running { started = true }
            }
            .onChange(of: controller.restored) { _, restored in
                if restored { design = controller.form(action).design ?? workspace.currentDesign ?? .init() }
            }
            .onChange(of: design) { _, value in
                guard controller.restored else { return }
                var request = controller.form(action); request.design = value; controller.setForm(request.coordinated()); onDesign(value)
            }
            .sheet(isPresented: Binding(get: { inspecting != nil }, set: { if !$0 { inspecting = nil } })) {
                NavigationStack {
                    VStack(spacing: 20) {
                        if let id = inspecting, let image = workspace.thumbnails[id] { Image(uiImage: image).resizable().scaledToFit().padding() }
                        if let id = inspecting {
                            Button(controller.form(action).heroID == id ? "已设为主照片" : "设为主照片", systemImage: "star") {
                                var request = controller.form(action); request.heroID = id; controller.setForm(request)
                            }
                            TextField("为这张照片补充说明", text: $photoNote, axis: .vertical).textFieldStyle(.roundedBorder).padding(.horizontal)
                            Button("保存说明") {
                                var request = controller.form(action)
                                var notes = request.creationNotes ?? [:]; notes[id.uuidString] = photoNote
                                request.creationNotes = notes; controller.setForm(request); inspecting = nil
                            }
                        }
                        if let id = inspecting, workspace.pending.contains(id) {
                            Button("从待排区移除", role: .destructive) { Task { await workspace.removePendingMaterial(id); inspecting = nil } }
                        }
                    }.navigationTitle("照片").toolbar { Button("完成") { inspecting = nil } }
                }.presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingDetails) {
                DiaryAIProgressPanel(workspace: workspace, onCloseDetails: { showingDetails = false })
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $customizing) {
                DiaryStoryInputSheet(brief: Binding(get: {
                    controller.form(action).creationBrief ?? workspace.currentCreationBrief ?? CreationBrief()
                }, set: { brief in
                    var request = controller.form(action)
                    request.creationBrief = brief
                    if brief.hasVisibleStoryEntries { request.allowsText = true }
                    controller.setForm(request)
                }), editing: editingStory)
            }
    }
    private var storyChanged: Bool {
        ((controller.form(action).creationBrief ?? workspace.currentCreationBrief)?.storyEntries ?? []) != (workspace.currentCreationBrief?.storyEntries ?? [])
    }
    private var storyEntries: [DiaryStoryEntry] {
        (controller.form(action).creationBrief ?? workspace.currentCreationBrief)?.storyEntries ?? []
    }
    private var storyTags: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    editingStory = nil; customizing = true
                } label: {
                    if storyEntries.isEmpty {
                        Label("写点故事", systemImage: "square.and.pencil")
                    } else {
                        Image(systemName: "square.and.pencil")
                            .frame(minWidth: 36, minHeight: 44)
                    }
                }
                .font(.subheadline)
                .accessibilityLabel("写点故事")
                .disabled(workspace.running || !controller.restored)
                ForEach(storyEntries) { entry in
                    Button {
                        editingStory = entry; customizing = true
                    } label: {
                        Text("\(entry.kind.rawValue) · \(entry.text)\(entry.usage == .reference && entry.kind != .direction ? " · 仅参考" : "")")
                            .font(.caption).lineLimit(1)
                            .frame(maxWidth: 200)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Color.accentColor.opacity(0.08), in: Capsule())
                            .frame(minHeight: 44)
                    }.buttonStyle(.plain).disabled(workspace.running)
                }
            }.fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 44)
    }
    private var materialPage: some View {
        VStack(spacing: 8) {
            HStack { Text(started || workspace.running ? "待排素材" : "本页素材").fontWeight(.semibold); Spacer(); Button("照片", systemImage: "plus", action: onPhotos); Button("拍摄", systemImage: "camera", action: onCamera) }.font(.caption)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(workspace.preparingPhotos, id: \.self) { _ in
                        VStack(spacing: 6) {
                            ProgressView()
                            Text("准备中").font(.caption2).foregroundStyle(.secondary)
                        }.frame(width: 88, height: 76)
                            .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("照片准备中")
                    }
                    ForEach(materialPhotos) { photo in
                        if let image = workspace.thumbnails[photo.id] {
                            Button {
                                photoNote = controller.form(action).creationNotes?[photo.id.uuidString] ?? ""
                                inspecting = photo.id
                            } label: {
                                Image(uiImage: image).resizable().scaledToFit()
                                    .frame(width: 88, height: 76)
                                    .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(alignment: .topTrailing) {
                                        if controller.form(action).heroID == photo.id {
                                            Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange)
                                        }
                                    }
                            }.accessibilityLabel("查看照片")
                        }
                    }
                    if materialPhotos.isEmpty && (started || workspace.running) {
                        Text("照片已全部放入画布").font(.caption).foregroundStyle(.secondary).frame(height: 76)
                    }
                    if !started && !workspace.running {
                      Button(action: onPhotos) {
                        Image(systemName: "plus").foregroundStyle(.secondary)
                            .frame(width: 64, height: 76)
                            .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                      }.accessibilityLabel("添加照片")
                    }
                }
            }.frame(height: 76)
        }.disabled(workspace.running)
    }
    private func designToggle(_ title: String, symbol: String, value: Int) -> some View {
        Button { tab = value } label: {
            Label(title, systemImage: symbol).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Color(red: 0.24, green: 0.39, blue: 0.34).opacity(tab == value ? 0.18 : 0.08), in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(tab == value ? .isSelected : [])
    }
    private func choice<Content: View>(_ title: String, selected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                content().frame(width: 152, height: 108).clipShape(RoundedRectangle(cornerRadius: 8))
                HStack(spacing: 3) { Text(title).font(.caption).lineLimit(1).minimumScaleFactor(0.8); if selected { Image(systemName: "checkmark.circle.fill").font(.caption) } }
            }.padding(8).frame(width: 168).background(selected ? Color(red: 0.24, green: 0.39, blue: 0.34).opacity(0.12) : Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(selected ? Color(red: 0.24, green: 0.39, blue: 0.34) : .clear, lineWidth: 1.5))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }

}

/// Pending materials sit below the artwork, independently of the bottom controls.
struct DiaryAIMaterialRows: View {
    @ObservedObject var workspace: DiaryAIWorkspace
    var onPhotos: (() -> Void)? = nil
    var onCamera: (() -> Void)? = nil
    var onStickers: (() -> Void)? = nil
    private func items(photos: Bool) -> [UUID] {
        workspace.pending.filter { id in
            guard let object = workspace.objects.first(where: { $0.id == id }) else { return false }
            return photos ? object.role == "photo" : ["decoration", "group", "textImage"].contains(object.role)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("照片", photos: true)
            row("贴纸", photos: false)
        }.padding(.horizontal, 20).padding(.top, 8)
    }
    private func row(_ title: String, photos: Bool) -> some View {
        let ids = items(photos: photos)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(title) · \(ids.count)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if photos {
                    if let onPhotos { Button("添加照片", systemImage: "photo.badge.plus", action: onPhotos) }
                    if let onCamera { Button("拍摄", systemImage: "camera", action: onCamera) }
                } else if let onStickers { Button("贴纸库", systemImage: "plus.circle", action: onStickers) }
            }.font(.caption).disabled(workspace.running)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(ids, id: \.self) { id in
                        if let image = workspace.thumbnails[id] {
                            Image(uiImage: image).resizable().scaledToFit().frame(width: 64, height: 66)
                                .overlay(alignment: .topTrailing) {
                                    if workspace.processing.contains(id) { ProgressView() }
                                }
                                .accessibilityLabel("待处理\(title)")
                        }
                    }
                }
                if ids.isEmpty { Text("暂无待处理\(title)").font(.caption2).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading) }
            }.frame(height: 66)
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Local, zero-request composition preview. It never represents a generated background.
/// A die-cut edge follows the asset alpha, rather than a rectangular image container.
struct DiaryDieCutSticker: View {
    let image: UIImage
    var paperTape = false
    var body: some View {
        ZStack {
            if !paperTape {
                ForEach(0..<12, id: \.self) { index in
                    Image(uiImage: image).renderingMode(.template).resizable().scaledToFit()
                        .foregroundStyle(.white)
                        .offset(x: cos(Double(index) * .pi / 6) * 2.5,
                                y: sin(Double(index) * .pi / 6) * 2.5)
                }
            }
            Image(uiImage: image).resizable().scaledToFit()
        }.compositingGroup()
            .shadow(color: .black.opacity(paperTape ? 0.06 : 0.16), radius: paperTape ? 1 : 2, x: 0, y: 2)
            .padding(4)
    }
}

struct DiaryAIDesignPreview: View {
    let design: DiaryAIDesignSelection
    var photos: [UIImage] = []
    var stickers: [UIImage] = []
    var stickerNames: [String] = []
    var story: String = ""
    static func isTape(_ name: String) -> Bool {
        name.contains("胶带") || ["左上", "右上", "顶部照片左上", "顶部照片右上"].contains(name)
    }
    private var ink: Color {
        switch design.style {
        case .scenic: Color(red: 0.18, green: 0.32, blue: 0.27)
        case .illustrated: Color(red: 0.21, green: 0.36, blue: 0.48)
        case .vintage: Color(red: 0.40, green: 0.27, blue: 0.17)
        case .clean: Color(red: 0.20, green: 0.28, blue: 0.34)
        case .playful: Color(red: 0.75, green: 0.30, blue: 0.19)
        case .gentle: Color(red: 0.57, green: 0.35, blue: 0.36)
        }
    }
    private var paperColor: Color {
        switch design.style {
        case .vintage: Color(red: 0.94, green: 0.88, blue: 0.76)
        case .clean: Color(red: 0.98, green: 0.99, blue: 0.97)
        case .gentle: Color(red: 0.99, green: 0.94, blue: 0.91)
        case .illustrated: Color(red: 0.94, green: 0.97, blue: 0.96)
        case .playful: Color(red: 1, green: 0.98, blue: 0.90)
        case .scenic: Color(red: 0.97, green: 0.96, blue: 0.92)
        }
    }
    private var frames: [CGRect] {
        if !photos.isEmpty {
            return Self.photoFrames(count: photos.count, layout: design.layout)
        }
        return sampleFrames
    }
    static func photoFrames(count: Int, layout: DiaryAILayout) -> [CGRect] {
        guard count > 0 else { return [] }
        let top = layout == .headline ? 0.25 : 0.12
        let bottom = 0.87
        if count == 1 { return [CGRect(x: 0.09, y: top, width: 0.82, height: bottom - top)] }
        let hero = layout == .hero && count <= 6
        var result = hero ? [CGRect(x: 0.06, y: top, width: 0.53, height: bottom - top)] : []
        let remaining = count - result.count
        let columns = hero ? (remaining > 3 ? 2 : 1) : (count <= 4 ? 2 : (count <= 9 ? 3 : 4))
        let rows = Int(ceil(Double(remaining) / Double(columns)))
        let left = hero ? 0.62 : 0.06
        let width = hero ? 0.32 : 0.88
        let w = width / Double(columns), h = (bottom - top) / Double(rows)
        for index in 0..<remaining {
            let stagger = layout == .collage && index % 2 == 1 ? 0.025 : 0
            result.append(CGRect(x: left + Double(index % columns) * w,
                                 y: top + Double(index / columns) * h + stagger,
                                 width: w - 0.025, height: h - 0.025 - stagger))
        }
        return result
    }
    private func fittedFrame(_ rect: CGRect, image: UIImage?, size: CGSize) -> CGRect {
        let box = CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
                         width: rect.width * size.width, height: rect.height * size.height)
        guard let image, image.size.width > 0, image.size.height > 0 else { return box }
        let scale = min(box.width / image.size.width, box.height / image.size.height)
        let width = image.size.width * scale, height = image.size.height * scale
        return CGRect(x: box.midX - width / 2, y: box.midY - height / 2, width: width, height: height)
    }
    private var sampleFrames: [CGRect] {
        switch design.layout {
        case .hero: [CGRect(x: 0.06, y: 0.26, width: 0.53, height: 0.58), CGRect(x: 0.64, y: 0.27, width: 0.27, height: 0.26), CGRect(x: 0.64, y: 0.57, width: 0.27, height: 0.26)]
        case .headline: [CGRect(x: 0.08, y: 0.48, width: 0.44, height: 0.41), CGRect(x: 0.57, y: 0.49, width: 0.34, height: 0.25), CGRect(x: 0.70, y: 0.76, width: 0.21, height: 0.16)]
        case .collage: [CGRect(x: 0.07, y: 0.24, width: 0.41, height: 0.53), CGRect(x: 0.50, y: 0.37, width: 0.35, height: 0.37), CGRect(x: 0.24, y: 0.69, width: 0.30, height: 0.24)]
        case .editorial: [CGRect(x: 0.07, y: 0.27, width: 0.43, height: 0.30), CGRect(x: 0.07, y: 0.62, width: 0.43, height: 0.29), CGRect(x: 0.58, y: 0.59, width: 0.33, height: 0.23)]
        case .story: [CGRect(x: 0.06, y: 0.27, width: 0.34, height: 0.48), CGRect(x: 0.43, y: 0.36, width: 0.24, height: 0.31), CGRect(x: 0.71, y: 0.49, width: 0.24, height: 0.34)]
        case .automatic: [CGRect(x: 0.07, y: 0.28, width: 0.39, height: 0.43), CGRect(x: 0.55, y: 0.30, width: 0.35, height: 0.27), CGRect(x: 0.57, y: 0.65, width: 0.33, height: 0.26)]
        }
    }
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                paperColor
                Canvas { context, canvas in
                    for index in 0..<180 {
                        let x = CGFloat((index * 73) % 997) / 997 * canvas.width
                        let y = CGFloat((index * 137) % 991) / 991 * canvas.height
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(ink.opacity(0.10)))
                    }
                }.accessibilityHidden(true)
                Text(design.layout == .headline ? "旅行手记" : "TRAVEL NOTES")
                    .font(.system(size: size.width * (design.layout == .headline ? 0.075 : 0.027), weight: .medium, design: .serif))
                    .tracking(size.width * 0.004).foregroundStyle(ink.opacity(0.8))
                    .offset(x: size.width * 0.07, y: size.height * 0.045)
                ForEach(Array(frames.enumerated()), id: \.offset) { index, rect in
                    let image = photos.indices.contains(index) ? photos[index] : nil
                    let fitted = fittedFrame(rect, image: image, size: size)
                    Group {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFit()
                        } else {
                            Rectangle().fill(ink.opacity(0.08))
                                .overlay(Image(systemName: "photo").foregroundStyle(ink.opacity(0.3)))
                        }
                    }.frame(width: fitted.width, height: fitted.height)
                        .padding(size.width * 0.008).background(.white)
                        .shadow(color: .black.opacity(0.09), radius: 2, y: 2)
                        .rotationEffect(.degrees(design.layout == .collage ? (index % 2 == 0 ? -3 : 3) : 0))
                        .offset(x: fitted.minX - size.width * 0.008, y: fitted.minY - size.width * 0.008)
                }
                if !story.isEmpty {
                    Text(story).font(.system(size: max(8, size.width * 0.029), design: .serif)).foregroundStyle(ink)
                        .lineLimit(2).frame(width: size.width * 0.84, alignment: .leading)
                        .offset(x: size.width * 0.07, y: size.height * 0.91)
                }
                ForEach(Array(stickers.enumerated()), id: \.offset) { index, image in
                    if !frames.isEmpty {
                        let photoIndex = index % frames.count
                        let frame = fittedFrame(frames[photoIndex], image: photos.indices.contains(photoIndex) ? photos[photoIndex] : nil, size: size)
                        let lowerEdge = index >= frames.count
                        DiaryDieCutSticker(image: image, paperTape: stickerNames.indices.contains(index) && Self.isTape(stickerNames[index]))
                            .frame(width: size.width * 0.115, height: size.height * 0.085)
                            .rotationEffect(.degrees(index % 2 == 0 ? -12 : 9))
                            .offset(x: min(size.width * 0.86, max(0, frame.minX - size.width * 0.025)),
                                    y: (lowerEdge ? frame.maxY : frame.minY) - size.height * 0.04)
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius: 12))
        }.aspectRatio(1.04, contentMode: .fit)
            .accessibilityLabel("\(design.layout.name)，\(design.style.name)，构图示意，非生成成品")
    }
}

struct DiaryAIDesignChooser: View {
    @Binding var selection: DiaryAIDesignSelection
    var photos: [UIImage] = []
    @State private var tab: Int
    init(selection: Binding<DiaryAIDesignSelection>, photos: [UIImage] = [], initialTab: Int = 0) {
        self._selection = selection; self.photos = photos; self._tab = State(initialValue: initialTab)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("设计选项", selection: $tab) {
                Text("排版").tag(0); Text("风格").tag(1)
            }.pickerStyle(.segmented)
            Text(tab == 0 ? "决定照片主次与阅读顺序" : "统一背景、字体、纸卡与装饰")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if tab == 0 {
                        ForEach(DiaryAILayout.allCases) { layout in
                            card(.init(layout: layout, style: selection.style), title: layout.name, detail: layout.detail, selected: selection.layout == layout) { selection.layout = layout }
                        }
                    } else {
                        ForEach(DiaryAIPageStyle.allCases) { style in
                            card(.init(layout: selection.layout, style: style), title: style.name, detail: style.detail, selected: selection.style == style) { selection.style = style }
                        }
                    }
                }.padding(2)
            }
            Text("正式背景将结合照片生成，保留全部所选照片")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func card(_ design: DiaryAIDesignSelection, title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                DiaryAIDesignPreview(design: design, photos: photos)
                HStack { Text(title).font(.subheadline.weight(.semibold)); Spacer(); if selected { Image(systemName: "checkmark.circle.fill") } }

            }.padding(7).frame(width: 112)
                .background(selected ? Color(red: 0.24, green: 0.39, blue: 0.34).opacity(0.10) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color(red: 0.24, green: 0.39, blue: 0.34) : .clear, lineWidth: 1))
        }.buttonStyle(.plain).accessibilityHint(detail).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
