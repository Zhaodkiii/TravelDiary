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
            } message: { Text(workspace.pending.isEmpty ? "发布为正式作品，可一次撤销整轮排版。" : "还有 \(workspace.pending.count) 项待排。保存后待排素材仍保留在项目中，但暂不显示在页面或导出中；下次进入可继续排版。") }
            .alert("AI 排版", isPresented: Binding(get: { workspace.error != nil && !workspace.panelVisible }, set: { if !$0 { workspace.error = nil } })) {
                Button("查看过程") { workspace.panelVisible = true }
            } message: { Text(workspace.error ?? "") }
            .onChange(of: scenePhase) { _, phase in if phase == .background && workspace.running { workspace.pause() } }
            .interactiveDismissDisabled()
        }.tint(Color(red: 0.24, green: 0.39, blue: 0.34))
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
                                else if workspace.selected.contains(id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, Color.accentColor) }
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
    @State private var showingDetails = false
    @State private var action = DiaryAIAction.relayout
    @State private var design = DiaryAIDesignSelection()
    @State private var choosingDesign = false
    @State private var designTab = 0
    @State private var instruction = ""
    @State private var started = false
    var body: some View {
        VStack(spacing: 14) {
            if started || workspace.running {
                VStack(spacing: 14) {
                    HStack {
                        if workspace.running { ProgressView() }
                        Text(workspace.stage).font(.headline)
                        Spacer()
                        Button("详情") { showingDetails = true }
                            .accessibilityIdentifier("diary.ai.details")
                    }
                    Text("待处理 \(workspace.pending.count) 项").font(.caption).foregroundStyle(.secondary)
                    if let error = workspace.error { Text(error).font(.caption).foregroundStyle(.orange) }
                    HStack {
                        Button("回退上一批") { Task { await workspace.rollback() } }.disabled(!workspace.canRollback)
                        Spacer()
                        if workspace.running { Button("暂停") { workspace.pause() } }
                        else { Button("继续") { workspace.processAll() } }
                    }
                }.padding(20)
            } else {
                HStack(spacing: 12) {
                    Button { choosingDesign = !choosingDesign || designTab != 0; designTab = 0 } label: {
                        Label("排版 · \(design.layout.name)", systemImage: "rectangle.3.group")
                    }
                    Button { choosingDesign = !choosingDesign || designTab != 1; designTab = 1 } label: {
                        Label("风格 · \(design.style.name)", systemImage: "paintpalette")
                    }
                }.buttonStyle(.bordered).font(.subheadline).padding(.horizontal, 16)
                if choosingDesign {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            if designTab == 0 {
                                ForEach(DiaryAILayout.allCases) { item in
                                    Button { design.layout = item } label: {
                                        Text(item.name).font(.subheadline.weight(design.layout == item ? .semibold : .regular))
                                            .padding(.horizontal, 16).padding(.vertical, 12)
                                            .background(design.layout == item ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08), in: Capsule())
                                    }.accessibilityAddTraits(design.layout == item ? [.isSelected] : [])
                                }
                            } else {
                                ForEach(DiaryAIPageStyle.allCases) { item in
                                    Button { design.style = item } label: {
                                        VStack(spacing: 5) {
                                            TravelStyleArtwork(style: item).frame(width: 92, height: 100).clipShape(RoundedRectangle(cornerRadius: 12))
                                            Text(item.name).font(.caption)
                                        }.padding(5).background(design.style == item ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 16))
                                    }.accessibilityAddTraits(design.style == item ? [.isSelected] : [])
                                }
                            }
                        }.padding(.horizontal, 20)
                    }
                }
                Text(controller.form(action).background == nil ? "保留现有背景 · 按所选排版与风格制作" : "自动生成背景 · 按所选排版与风格制作标题及旁注")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Menu {
                        Picker("选择功能", selection: $action) {
                            ForEach(DiaryAIAction.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        VStack(spacing: 4) { Image(systemName: action.symbol); Text(action.rawValue).font(.caption) }
                    }
                    Spacer()
                    Button {
                        var request = controller.form(action)
                        request.design = design; request = request.coordinated(); request.selectedOnly = false
                        if !instruction.isEmpty { request.instruction = instruction }
                        controller.setForm(request); customizing = true
                    } label: { VStack(spacing: 4) { Image(systemName: "slider.horizontal.3"); Text("更多").font(.caption) } }
                    Spacer()
                    Button(action.submitTitle) {
                        var request = controller.form(action)
                        request.design = design; request = request.coordinated(); request.selectedOnly = false
                        if !instruction.isEmpty { request.instruction = instruction }
                        started = true; workspace.configureAndStart(request)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(!workspace.active || (action == .custom && instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && controller.form(action).instruction.isEmpty))
                }.padding(.horizontal, 20)
            }
            Spacer(minLength: 0)
        }.padding(.top, 12).background(DiaryLibraryStyle.background)
            .tint(Color(red: 0.24, green: 0.39, blue: 0.34))
            .onAppear { design = controller.form(action).design ?? .init() }
            .onChange(of: action) { _, value in design = controller.form(value).design ?? .init() }
            .onChange(of: design) { _, value in
                var request = controller.form(action); request.design = value
                controller.setForm(request.coordinated())
            }
            .sheet(isPresented: $showingDetails) {
                DiaryAIProgressPanel(workspace: workspace, onCloseDetails: { showingDetails = false })
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $customizing) {
                DiaryAIRequestSheet(controller: controller, action: action, onConfigure: { request in
                    controller.setForm(request)
                    action = request.action; design = request.design ?? .init(); instruction = request.instruction
                })
            }
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
            }.font(.caption).disabled(workspace.running || workspace.addingMaterials)
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
struct DiaryAIDesignPreview: View {
    let design: DiaryAIDesignSelection
    var photos: [UIImage] = []
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
    private var frames: [CGRect] {
        switch design.layout {
        case .hero: [CGRect(x: 0.06, y: 0.26, width: 0.53, height: 0.58), CGRect(x: 0.64, y: 0.27, width: 0.27, height: 0.26), CGRect(x: 0.64, y: 0.57, width: 0.27, height: 0.26)]
        case .headline: [CGRect(x: 0.08, y: 0.48, width: 0.44, height: 0.41), CGRect(x: 0.57, y: 0.49, width: 0.34, height: 0.25), CGRect(x: 0.70, y: 0.76, width: 0.21, height: 0.16)]
        case .collage: [CGRect(x: 0.07, y: 0.24, width: 0.41, height: 0.53), CGRect(x: 0.50, y: 0.37, width: 0.35, height: 0.37), CGRect(x: 0.24, y: 0.69, width: 0.30, height: 0.24)]
        case .editorial: [CGRect(x: 0.07, y: 0.27, width: 0.43, height: 0.30), CGRect(x: 0.07, y: 0.62, width: 0.43, height: 0.29), CGRect(x: 0.58, y: 0.59, width: 0.33, height: 0.23)]
        case .automatic, .story: [CGRect(x: 0.07, y: 0.28, width: 0.39, height: 0.43), CGRect(x: 0.55, y: 0.30, width: 0.35, height: 0.27), CGRect(x: 0.57, y: 0.65, width: 0.33, height: 0.26)]
        }
    }
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                Color(uiColor: .secondarySystemGroupedBackground)
                Ellipse().fill(ink.opacity(0.10)).frame(width: size.width * 0.75, height: size.height * 0.7).offset(x: size.width * 0.4, y: size.height * 0.5)
                VStack(alignment: .leading, spacing: 3) {
                    Text(design.layout == .headline ? "把这一刻\n留在手帐里" : "把日子收藏").font(.system(size: size.width * (design.layout == .headline ? 0.085 : 0.064), weight: .bold, design: .serif))
                    if design.layout != .headline { Text("照片与故事 · 留下此刻").font(.system(size: size.width * 0.027)) }
                }.foregroundStyle(ink).offset(x: size.width * 0.07, y: size.height * 0.05)
                ForEach(Array(frames.enumerated()), id: \.offset) { index, rect in
                    ZStack {
                        Color.white
                        if photos.indices.contains(index) {
                            Image(uiImage: photos[index]).resizable().scaledToFit().padding(3)
                        } else {
                            Image(systemName: "photo").resizable().scaledToFit().foregroundStyle(ink.opacity(0.4)).padding(10)
                        }
                    }.frame(width: size.width * rect.width, height: size.height * rect.height)
                        .rotationEffect(.degrees(design.layout == .collage ? (index == 1 ? 5 : -4) : 0))
                        .offset(x: size.width * rect.minX, y: size.height * rect.minY)
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<3) { index in Rectangle().fill(ink.opacity(0.55)).frame(width: size.width * (index == 2 ? 0.13 : 0.22), height: 2) }
                }.offset(x: size.width * (design.layout == .editorial ? 0.59 : 0.08), y: size.height * (design.layout == .editorial ? 0.32 : 0.85))
            }.clipShape(RoundedRectangle(cornerRadius: 12))
        }.aspectRatio(1.4, contentMode: .fit)
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
            Text("构图与配色示意 · 正式背景将根据你的照片生成，照片数量自适应")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func card(_ design: DiaryAIDesignSelection, title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                DiaryAIDesignPreview(design: design, photos: photos)
                HStack { Text(title).font(.subheadline.weight(.semibold)); Spacer(); if selected { Image(systemName: "checkmark.circle.fill") } }
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(height: 32, alignment: .topLeading)
            }.padding(10).frame(width: 190)
                .background(selected ? Color.accentColor.opacity(0.10) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
