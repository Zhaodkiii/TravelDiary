import SwiftUI
import UniformTypeIdentifiers

struct DiaryAIWorkspaceView: View {
    var onCloseDetails: (() -> Void)? = nil
    @ObservedObject var workspace: DiaryAIWorkspace
    @State private var logURL: URL?
    @State private var exportingLog = false
    @State private var exitConfirmation = false
    @State private var saveConfirmation = false
    @State private var regenerateBackground = false
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
    var panel: some View {
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
                    if onCloseDetails == nil {
                        Button("退出") { workspace.panelVisible = false; exitConfirmation = true }
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
    @State private var style = "自动匹配"
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        Button("自动匹配") { style = "自动匹配" }.buttonStyle(.bordered)
                        ForEach(DiaryAIStyleLibrary.styles) { item in
                            Button { style = item.name } label: {
                                VStack(spacing: 4) {
                                    Image(item.imageName).resizable().scaledToFill().frame(width: 92, height: 60).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                                    Text(item.name).font(.caption)
                                }.padding(4).background(style == item.name ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 20)
                }
                HStack {
                    Menu {
                        Picker("选择功能", selection: $action) {
                            ForEach(DiaryAIAction.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        VStack(spacing: 4) { Image(systemName: action.symbol); Text(action.rawValue).font(.caption) }
                    }
                    Spacer()
                    Menu {
                        Picker("选择模板", selection: $style) {
                            Text("自动匹配").tag("自动匹配")
                            ForEach(DiaryAIStyleLibrary.styles) { Text($0.name).tag($0.name) }
                        }
                    } label: {
                        VStack(spacing: 4) { Image(systemName: "rectangle.3.group"); Text("选择模板").font(.caption) }
                    }
                    Spacer()
                    Button {
                        var request = controller.form(action)
                        request.style = style; request.selectedOnly = false
                        if !instruction.isEmpty { request.instruction = instruction }
                        controller.setForm(request); customizing = true
                    } label: { VStack(spacing: 4) { Image(systemName: "slider.horizontal.3"); Text("自定义").font(.caption) } }
                    Spacer()
                    Button(action.submitTitle) {
                        var request = controller.form(action)
                        request.style = style; request.selectedOnly = false
                        if !instruction.isEmpty { request.instruction = instruction }
                        started = true; workspace.configureAndStart(request)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(!workspace.active || (action == .custom && instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && controller.form(action).instruction.isEmpty))
                }.padding(.horizontal, 20)
            }
            Spacer(minLength: 0)
        }.padding(.top, 12).background(DiaryLibraryStyle.background)
            .tint(Color(red: 0.24, green: 0.39, blue: 0.34))
            .sheet(isPresented: $showingDetails) {
                DiaryAIWorkspaceView(onCloseDetails: { showingDetails = false }, workspace: workspace).panel
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $customizing) {
                DiaryAIRequestSheet(controller: controller, action: action, onConfigure: { request in
                    controller.setForm(request)
                    action = request.action; style = request.style; instruction = request.instruction
                })
            }
    }
}

/// Pending materials sit below the artwork, independently of the bottom controls.
struct DiaryAIMaterialRows: View {
    @ObservedObject var workspace: DiaryAIWorkspace
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
            Text("\(title) · \(ids.count)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
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
