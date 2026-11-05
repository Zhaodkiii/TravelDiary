import PhotosUI
import AVFoundation
import Combine
import SwiftUI
import UIKit

/// 主编辑页面只组织工具与状态；数据修改和保存均交给 Session。
struct DiaryEditorScreen: View {
    @ObservedObject var session: DiaryEditorSession
    var entranceOnRightPage = false
    var creationRequest: DiaryAIRequest? = nil
    var creationAutoStart = false
    var onNewPage: (() async throws -> Void)? = nil
    var discardEmptyDraft: (() async throws -> Bool)? = nil
    var onFinished: (() async throws -> Void)? = nil
    @State private var confirmsNewPage = false
    @State private var creatingNewPage = false
    @State private var creationEntered = false
    @State private var enteringCreation = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsSpreadShell = true
    @State private var childEditor: DiaryEditorSession?
    @State private var showPhotos = false
    @State private var aiPhotos: [PhotosPickerItem] = []
    @State private var confirmsSaveAIWork = false
    @State private var showAIPhotos = false
    @State private var creationFlow: DiaryAICreationFlow?
    @State private var showCreationFlow = false
    @State private var showCreationPicker = false
    @State private var creationPickerResults: [PHPickerResult] = []
    @State private var startPreparedCreation = false
    @State private var showAIStickers = false
    @State private var showCamera = false
    @State private var capturedPhotos: [UIImage] = []
    @State private var importingCameraPhotos = false
    @State private var textEditor: DiaryTextEditorPresentation?
    @State private var showCrop = false
    @State private var activeTool: DiaryEditorTool?
    @State private var showDrawing = false
    @State private var drawingEditor: DiaryEditorSession?
    @State private var showStickers = false
    @State private var selectionViewportRect: CGRect?

    @State private var studioDesign: DiaryAIDesignSelection?
    @State private var closingAIEditor = false
    @State private var openedDirectlyInAI = false
    @State private var aiMode = false
    @State private var aiCompare = false
    @State private var aiDisplaySession: DiaryEditorSession?
    private var canvasSession: DiaryEditorSession { aiMode && !aiCompare ? aiDisplaySession ?? session : session }
    private var toolOpen: Bool { activeTool != nil || showStickers || aiMode }

    var body: some View {
        NavigationStack {
            editorContent
            .disabled(closingAIEditor || creatingNewPage || session.busy || (!aiMode && importingCameraPhotos) || session.aiWorkspace.saving)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editorToolbar }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(toolOpen && !aiMode ? .hidden : .visible, for: .navigationBar)
            .overlay {
                if session.busy || (!aiMode && importingCameraPhotos) {
                    ProgressView(importingCameraPhotos ? "正在添加拍摄照片…" : "正在处理…")
                        .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .confirmationDialog("保存当前作品？", isPresented: $confirmsSaveAIWork, titleVisibility: .visible) {
                Button("保存已完成部分") { Task { _ = await session.aiWorkspace.save() } }
                Button("取消", role: .cancel) {}
            } message: {
                Text("制作尚未全部完成。将当前画布保存为作品，未完成步骤不会自动执行；待排素材保留在项目中，不显示在作品和导出中。")
            }
            .confirmationDialog("删除当前草稿并新建？", isPresented: $confirmsNewPage, titleVisibility: .visible) {
                Button("删除当前草稿并新建", role: .destructive) { newPage() }
                Button("取消", role: .cancel) {}
            } message: { Text("当前待处理素材和未保存的制作内容将删除，已保存的正式作品会保留。") }
            .onReceive(session.aiWorkspace.$displaySession) { aiDisplaySession = $0 }
            .onChange(of: session.aiWorkspacePresented) { _, presented in
                if !presented && !closingAIEditor { withAnimation(.smooth(duration: 0.4)) { aiMode = false } }
            }
            .fullScreenCover(item: $childEditor) { child in
                AnyView(DiaryEditorScreen(session: child))
            }
            .photosPicker(isPresented: $showAIPhotos, selection: $aiPhotos, maxSelectionCount: 30, selectionBehavior: .ordered, matching: .images)
            .onChange(of: aiPhotos) { _, items in
                guard !items.isEmpty else { return }
                aiPhotos = []
                let workspace = session.aiWorkspace
                let loadingIDs = workspace.beginPreparingPhotos(items.count)
                Task {
                    defer { workspace.finishPreparingPhotos(loadingIDs) }
                    do {
                        var bytes: [Data] = []
                        for item in items {
                            guard let data = try await item.loadTransferable(type: Data.self) else { throw DiaryEditorError.invalidImage }
                            bytes.append(data)
                        }
                        _ = await workspace.addMaterials(bytes)
                    } catch { session.errorMessage = "照片读取失败，请重新选择。" }
                }
            }

            .sheet(isPresented: $showCreationPicker, onDismiss: {
                let results = creationPickerResults
                creationPickerResults = []
                guard !results.isEmpty, let creationFlow else { return }
                showCreationFlow = true
                creationFlow.importProviders(results.map(\.itemProvider))
            }) {
                DiaryCreationSystemPicker(limit: max(1, 30 - (creationFlow?.draft.photos.count ?? 0))) { results in
                    creationPickerResults = results
                    showCreationPicker = false
                }.ignoresSafeArea()
            }
            .sheet(isPresented: $showCreationFlow, onDismiss: {
                if startPreparedCreation {
                    startPreparedCreation = false
                    session.aiWorkspace.processAll()
                }
            }) {
                if let creationFlow {
                    DiaryAICreationSheet(flow: creationFlow) {
                        studioDesign = creationFlow.design
                        startPreparedCreation = true
                        showCreationFlow = false
                    }
                }
            }
            .sheet(isPresented: $showAIStickers) {
                MaterialLibraryBrowser(keepsOpenAfterAdding: true, startsInGallery: true, onSelectForCreation: { bytes, name, material in
                    let added = await session.aiWorkspace.addMaterials([bytes], sticker: true, name: name, material: material)
                    if added && session.aiWorkspace.stickerCount >= DiaryAIWorkspace.maximumStickers { showAIStickers = false }
                })
            }
            .sheet(isPresented: $showPhotos) { DiaryPhotoManagerSheet(session: session) }
            .fullScreenCover(isPresented: $showCamera, onDismiss: importCapturedPhotos) {
                DiaryCaptureCamera(onPhotos: { images in
                    capturedPhotos = images
                    showCamera = false
                }, onClose: { showCamera = false })
            }
            .fullScreenCover(item: $textEditor) { presentation in
                DiaryTextEditorSheet(session: session, draft: presentation.draft, initialTab: presentation.initialTab)
            }
            .sheet(isPresented: $showStickers, onDismiss: { session.finishInteraction() }) {
                MaterialLibraryBrowser(session: session, keepsOpenAfterAdding: true)
            }
            .fullScreenCover(isPresented: $showCrop) {
                if let layer = session.selected { DiaryCropSheet(session: session, layer: layer) }
            }

            .sheet(isPresented: $showDrawing, onDismiss: { session.inkMode = false }) {
                DiaryDrawingSheet(session: session)
                    .presentationDetents([.large])
                    .onDisappear { session.finishFreeTransform(commit: false) }
            .interactiveDismissDisabled()
            }
            .sheet(item: $drawingEditor) { child in
                DiaryDrawingSheet(session: child, editingExisting: true)
                    .presentationDetents([.large])
                    .interactiveDismissDisabled()
            }
            .alert("手帐", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
                Button("确定") { session.errorMessage = nil }
                Button("重新保存") { Task { try? await session.save() } }
            } message: { Text(session.errorMessage ?? "") }
            .task(id: session.id) {
                if let creationRequest, !creationEntered {
                    creationEntered = true
                    session.canvasAI.setForm(creationRequest)
                    studioDesign = creationRequest.design
                    openedDirectlyInAI = true
                    aiMode = true
                    enteringCreation = true
                    await session.aiWorkspace.enter(creationRequest)
                    if session.aiWorkspace.submittedCreationID != nil {
                        session.canvasAI.setForm(session.aiWorkspace.currentRequest)
                        studioDesign = session.aiWorkspace.currentDesign
                    }
                    enteringCreation = false
                    if creationAutoStart && session.aiWorkspace.active { session.aiWorkspace.processAll() }
                }
                if MaterialCatalogRepository.shared.pendingLibrary != nil { showStickers = true }
                if session.isRoot, let bookID = session.document.bookID {
                    DiaryBookAccessStore(ownerID: session.store.ownerID)
                        .record(bookID: bookID, pageID: session.document.id)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { session.canvasAI.suspend() }
                if phase != .active { session.finishInteraction(); Task { try? await session.save() } }
            }
            .onDisappear { session.canvasAI.suspend() }
            .interactiveDismissDisabled()
        }
    }

    /// 仅完整跨页比例启用外壳预览，等比例的不同分辨率同样适用。
    private var supportsSpreadPreview: Bool {
        let size = session.document.root.referenceSize
        guard session.isRoot, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return false }
        return DiaryCanvasLayout.infer(from: size) == .spread
    }

    private var supportsSinglePageViewport: Bool {
        let size = session.document.root.referenceSize
        return session.isRoot && size.height > 0 && abs(size.width / size.height - 2185.0 / 3130.0) < 0.000001
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack {
                if aiMode {
                    Button("关闭", action: closeAIEditor)
                        .disabled(enteringCreation || !session.aiWorkspace.preparingPhotos.isEmpty)
                } else { Button("完成") { Task { await finishEditor() } }
                if !session.isRoot { Button("取消") { Task { await session.cancelEditor(); dismiss() } } }
                }
            }
            .disabled(session.busy || importingCameraPhotos || session.aiWorkspace.addingMaterials)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if onNewPage != nil && !aiMode {
                Button(creatingNewPage ? "新建中…" : "新建页", systemImage: "plus.square") {
                    if session.document.root.layers.isEmpty && session.document.assets.isEmpty && session.document.root.drawing.isEmpty && session.document.root.background == nil && session.aiWorkspace.objects.isEmpty {
                        newPage()
                    } else { confirmsNewPage = true }
                }
                .disabled(enteringCreation || !creationEntered || creatingNewPage || session.busy || importingCameraPhotos || session.aiWorkspace.addingMaterials)
            }
            if aiMode {
                if session.aiWorkspace.enteredFromDraft {
                    Button(session.aiWorkspace.saving ? "保存中…" : "保存作品") {
                        if session.aiWorkspace.hasUnfinishedWork { confirmsSaveAIWork = true }
                        else { Task { _ = await session.aiWorkspace.save() } }
                    }
                    .disabled(!session.aiWorkspace.canSaveWork)
                    .accessibilityIdentifier("diary.ai.save-work")
                }
                Menu {
                    if session.aiWorkspace.version > 0 && session.aiWorkspace.pending.isEmpty {
                        Button(aiCompare ? "查看当前作品" : "对比原版", systemImage: "rectangle.on.rectangle") { aiCompare.toggle() }
                    }
                    if onNewPage != nil {
                        Button("新建页", systemImage: "plus.square") {
                            if session.document.root.layers.isEmpty && session.document.assets.isEmpty && session.document.root.drawing.isEmpty && session.document.root.background == nil && session.aiWorkspace.objects.isEmpty { newPage() }
                            else { confirmsNewPage = true }
                        }
                        .disabled(enteringCreation || !creationEntered || creatingNewPage || session.busy || importingCameraPhotos)
                    }
                    Button("保存草稿并关闭", systemImage: "square.and.arrow.down") {
                        closeAIEditor()
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("更多操作")
                .disabled(session.aiWorkspace.running || session.aiWorkspace.addingMaterials || session.aiWorkspace.saving || !session.aiWorkspace.preparingPhotos.isEmpty)
            } else {
            if supportsSpreadPreview {
                Button { session.finishInteraction(); showsSpreadShell.toggle() } label: { Image(systemName: showsSpreadShell ? "eye.fill" : "eye") }
                    .accessibilityLabel(showsSpreadShell ? "隐藏画布外壳" : "显示画布外壳")
                    .disabled(session.busy || importingCameraPhotos || session.aiWorkspace.addingMaterials)
            }
            Button { session.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(session.undoStack.isEmpty || session.busy || importingCameraPhotos).accessibilityLabel("撤销")
            Button { session.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(session.redoStack.isEmpty || session.busy || importingCameraPhotos).accessibilityLabel("重做")

            }
        }
    }

    @MainActor private func finishEditor() async {
        guard !closingAIEditor else { return }
        closingAIEditor = true
        defer { closingAIEditor = false }
        do {
            if try await discardEmptyDraft?() == true { dismiss(); return }
            if await session.commitToParent(beforeClosing: onFinished) {
                dismiss()
            }
        } catch { session.errorMessage = error.localizedDescription }
    }

    private func closeAIEditor() {
        guard !closingAIEditor, !enteringCreation else { return }
        closingAIEditor = true
        Task {
            defer { closingAIEditor = false }
            do {
                if openedDirectlyInAI, try await discardEmptyDraft?() == true { dismiss(); return }
                if openedDirectlyInAI && session.isRoot { try await session.save() }
                guard await session.aiWorkspace.keepForLater() else { return }
                if !openedDirectlyInAI {
                    aiCompare = false
                    withAnimation { aiMode = false }
                    return
                }
                if !session.isRoot, !(await session.commitToParent()) {
                    aiMode = false
                    return
                }
                dismiss()
            } catch {
                session.errorMessage = error.localizedDescription
            }
        }
    }

    private func newPage() {
        guard !creatingNewPage, let onNewPage else { return }
        creatingNewPage = true
        Task {
            defer { creatingNewPage = false }
            do {
                let oldDraftDirectory = creationFlow?.directory
                try await onNewPage()
                creationFlow?.cancelOperation()
                if let oldDraftDirectory { try? FileManager.default.removeItem(at: oldDraftDirectory) }
                creationFlow = nil
            }
            catch { session.errorMessage = "新建页失败：" + error.localizedDescription }
        }
    }

    private var editorContent: some View {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    let size = session.canvasBounds.size
                    // 工具模式用紧凑边距适配全部可见高度，普通模式保留完整手柄空间。
                    let margin = toolOpen || session.layerMode ? DiaryCanvasSurface.toolControlMargin : DiaryCanvasSurface.controlMargin
                    let horizontalPadding: CGFloat = aiMode ? margin * 2 + 32 : (toolOpen ? margin * 2 : 40)
                    let verticalPadding: CGFloat = toolOpen ? 0 : 24
                    let scale = max(0.01, min((geometry.size.width - horizontalPadding) / size.width,
                                             (geometry.size.height - margin * 2 - verticalPadding) / size.height))
                    DiaryZoomableCanvas(contentSize: CGSize(width: size.width * scale + margin * 2, height: size.height * scale + margin * 2), sessionID: session.id, inkMode: session.inkMode, minimumScale: 0.65, toolViewport: toolOpen, fitsCanvas: aiMode, refreshContent: aiMode, contentRevision: (showsSpreadShell ? 1 : 0) + (session.layerMode ? 2 : 0), entranceFocusRect: supportsSpreadPreview && !aiMode ? CGRect(x: margin + (entranceOnRightPage ? size.width * scale / 2 : 0), y: margin, width: size.width * scale / 2, height: size.height * scale) : nil, preservedCanvasRect: supportsSinglePageViewport && !aiMode ? CGRect(x: margin, y: margin, width: size.width * scale, height: size.height * scale) : nil) {
                      ZStack(alignment: .topLeading) {
                        if supportsSpreadPreview && showsSpreadShell {
                            DiaryLiveSpreadShell()
                                .frame(width: size.width * scale, height: size.height * scale)
                                .offset(x: margin, y: margin)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                        DiaryCanvasView(session: canvasSession, compactViewport: toolOpen, stagesEntrance: supportsSpreadPreview && !aiMode && creationRequest == nil, onSelectionViewportRect: { rect in
                            DispatchQueue.main.async {
                                if selectionViewportRect != rect { selectionViewportRect = rect }
                            }
                        }, onEdit: {
                            guard let layer = session.selected else { return }
                            if layer.kind == .object { openSelectedObject() }
                            else if layer.kind == .text { openText() }
                            else if layer.isContentPhoto { showCrop = true }
                            else if layer.kind == .sticker { childEditor = session.openSelectedStickerObject() }
                        })
                            .allowsHitTesting(!aiMode)
                            .frame(width: size.width * scale + margin * 2, height: size.height * scale + margin * 2)
                        if aiMode && !aiCompare && !session.aiWorkspace.running && session.aiWorkspace.backgroundPreview == nil && (session.aiWorkspace.objects.isEmpty || session.aiWorkspace.pending.count == session.aiWorkspace.objects.count) {
                            ZStack {
                                Color(red: 0.97, green: 0.96, blue: 0.92)
                                if session.aiWorkspace.objects.contains(where: { $0.role == "photo" }) {
                                    DiaryAIDesignPreview(design: studioDesign ?? session.canvasAI.form(.relayout).design ?? .init(), photos: session.aiWorkspace.objects.filter { $0.role == "photo" }.compactMap { session.aiWorkspace.thumbnails[$0.id] })
                                } else {
                                    VStack(spacing: 12) {
                                        Text("从照片开始记录").font(.headline)
                                        HStack {
                                            Button("添加照片", systemImage: "photo.badge.plus") { showAIPhotos = true }
                                            Button("拍摄", systemImage: "camera") { capturedPhotos = []; showCamera = true }
                                        }.buttonStyle(.bordered).disabled(session.aiWorkspace.addingMaterials)
                                    }
                                }
                            }.frame(width: size.width * scale, height: size.height * scale)
                                .clipped().offset(x: margin, y: margin)
                        }
                        if supportsSpreadPreview && showsSpreadShell {
                            LinearGradient(colors: [.clear, .black.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: max(2, size.width * scale * 0.018), height: size.height * scale)
                                .offset(x: margin + size.width * scale * (0.5 - 0.009), y: margin)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                      }
                      .frame(width: size.width * scale + margin * 2, height: size.height * scale + margin * 2)
                    }
                    .padding(.horizontal, aiMode ? 16 : 0)
                    .clipped()
                    .overlay(alignment: .topLeading) {
                        if !toolOpen, session.selected != nil, let rect = selectionViewportRect {
                            let width = min(geometry.size.width - 24, CGFloat(session.contextActions.count) * 56 + 32)
                            controls(selectionToolsOnly: true)
                                .frame(width: max(1, width), height: 64)
                                .position(x: min(max(rect.midX, width / 2 + 12), geometry.size.width - width / 2 - 12),
                                          y: min(max(44, rect.minY - 52), max(44, geometry.size.height - 150)))
                        }
                    }
                }
                .modifier(DiaryAIViewportAspectRatio(enabled: aiMode, ratio: session.canvasBounds.size.width / max(1, session.canvasBounds.size.height)))
                // 画布可延伸至 Home 指示器区域；外层工具栏仍按安全区定位。
                .ignoresSafeArea(.container, edges: toolOpen ? [] : .bottom)
                .background(DiaryLibraryStyle.background)
                if aiMode {
                    DiaryAIInlinePanel(workspace: session.aiWorkspace, controller: session.canvasAI,
                        onPhotos: { showAIPhotos = true },
                        onBeginCreation: openAIPhotos,
                        onCamera: { capturedPhotos = []; showCamera = true },
                        onStickers: { showAIStickers = true },
                        onDesign: { studioDesign = $0 })
                        .frame(maxHeight: .infinity)
                } else if showStickers {
                    // Reserve the compact native sheet's space so the existing tool
                    // viewport fits the artwork above it and keeps the canvas at the top.
                    Color.clear.frame(height: MaterialLibraryBrowser.compactHeight).accessibilityHidden(true)
                } else if let activeTool {
                    DiaryEditorToolPanel(title: activeTool.title, onBack: { closeTool(commit: false) }, onDone: { closeTool(commit: true) },
                                         backAccessibilityLabel: activeTool == .transform ? "取消变形" : "返回") {
                        switch activeTool {
                        case .layers: DiaryLayerToolContent(session: session)
                        case .background: DiaryBackgroundToolContent(session: session)
                        case .transform: DiaryTransformToolContent(session: session)
                        }
                    }
                    .disabled(session.busy)
                }
            }
            .overlay(alignment: .bottom) {
                if !toolOpen { controls() }
            }
            .ignoresSafeArea(.container, edges: toolOpen ? .bottom : .top)
    }

    private func controls(selectionToolsOnly: Bool = false) -> some View {
        DiaryContextToolbar(session: session,
            onBackground: { session.finishInteraction(); session.select(nil); activeTool = .background },
            onPhotos: { session.finishInteraction(); showPhotos = true },
            onCamera: { session.finishInteraction(); capturedPhotos = []; showCamera = true },
            onDrawing: { session.finishInteraction(); session.select(nil); showDrawing = true },
            onLayers: { session.finishInteraction(); session.layerMode = true; activeTool = .layers },
            onStickers: { session.finishInteraction(); showStickers = true },
            onOpenObject: openSelectedObject,
            onAI: {
                session.finishInteraction(); session.select(nil)
                activeTool = nil
                openedDirectlyInAI = false
                withAnimation(.smooth(duration: 0.45)) { aiMode = true }
                enteringCreation = true
                Task {
                    defer { enteringCreation = false }
                    await session.aiWorkspace.enter(session.canvasAI.form(.relayout))
                }
            },
            onTransform: { session.beginFreeTransform(); if session.transformDraft != nil { activeTool = .transform } },
            selectionToolsOnly: selectionToolsOnly)
    }
    private func prepareCreationFlow() {
        if let creationFlow, creationFlow.draft.submitted, session.aiWorkspace.objects.isEmpty { creationFlow.discardDraft() }
        guard creationFlow == nil else { return }
        do { creationFlow = try DiaryAICreationFlow(session: session) }
        catch { session.errorMessage = "无法读取制作草稿：" + error.localizedDescription }
    }
    private func openAIPhotos() {
        guard session.aiWorkspace.active, !session.aiWorkspace.running else { return }
        if session.aiWorkspace.objects.isEmpty {
            prepareCreationFlow()
            guard let creationFlow else { return }
            if creationFlow.draft.photos.count >= 30 { showCreationFlow = true }
            else { showCreationPicker = true }
        } else { showAIPhotos = true }
    }

    private func importCapturedPhotos() {
        guard !capturedPhotos.isEmpty else { return }
        let images = capturedPhotos
        capturedPhotos = []
        let importingIntoAI = aiMode
        let loadingIDs = importingIntoAI ? session.aiWorkspace.beginPreparingPhotos(images.count) : []
        importingCameraPhotos = true
        Task { @MainActor in
            defer { importingCameraPhotos = false; session.aiWorkspace.finishPreparingPhotos(loadingIDs) }
            let data = (try? await DiaryAIImageWork.run { images.compactMap { $0.jpegData(compressionQuality: 0.95) } }) ?? []
            guard data.count == images.count else {
                session.errorMessage = "无法读取拍摄照片，请重试。"; return
            }
            if importingIntoAI { _ = await session.aiWorkspace.addMaterials(data) }
            else { await session.importPhotos(data) }
        }
    }
    private func openText() {
        textEditor = DiaryTextEditorPresentation(session: session, layer: session.selectedEditingLayer)
    }
    private func openSelectedObject() {
        session.finishInteraction()
        if session.selectedEditingKind == .drawing {
            guard let child = session.openObject() else { return }
            child.select(nil)
            child.inkMode = true
            drawingEditor = child
        } else {
            childEditor = session.openObject()
        }
    }
    private func closeTool(commit: Bool) {
        if activeTool == .transform { session.finishFreeTransform(commit: commit) }
        session.finishInteraction()
        session.layerMode = false
        activeTool = nil
    }

}

/// 直接复用 SecondCamera 的拍摄、预览和编辑流程，确认后交给当前画布导入。
struct DiaryCaptureCamera: View {
    let onPhotos: ([UIImage]) -> Void
    let onClose: () -> Void

    var body: some View {
        CustomCameraView()
            .setCameraOutputType(.photo)
            .setCameraPosition(.back)
            .setAudioAvailability(false)
            .setResolution(.hd1920x1080)
            .setFrameRate(30)
            .setGridVisibility(true)
            .setCloseCustomCameraAction(onClose)
            .setCameraScreen {
                DefaultCustomCameraScreen(cameraManager: $0, namespace: $1, closeCustomCameraAction: $2)
                    .cameraOutputSwitchAllowed(false)
            }
            .setCapturedMediaScreen(DefaultCustomCapturedMediaScreen.init)
            .onMediaBatchCaptured { media, _ in onPhotos(media.compactMap { $0.getImage() }) }
            .onImageCaptured { image, _ in onPhotos([image]) }
            .startSession()
    }
}

/// 独立全屏裁剪只加载照片原图，装饰始终留在对象的其他图层中。
struct DiaryCropSheet: View {
    @ObservedObject var session: DiaryEditorSession
    let layer: DiaryLayer
    @Environment(\.dismiss) private var dismiss
    @State private var editor: ImageCropEditor?
    @State private var error: String?
    @State private var submitting = false

    var body: some View {
        Group {
            if let editor { editor.ignoresSafeArea() }
            else if let error {
                VStack(spacing: 20) { Text(error); Button("关闭") { dismiss() } }
            } else { ProgressView("正在加载原图…") }
        }
        .disabled(submitting)
        .overlay { if submitting { ProgressView("正在保存裁剪…").padding().background(.regularMaterial) } }
        .interactiveDismissDisabled(submitting)
        .task {
            do {
                guard let id = layer.photoCrop?.originalAssetID ?? layer.assetID,
                      let asset = session.document.assets[id] else { throw DiaryEditorError.missingResource.logged() }
                let image = try await session.store.loadOriginalImage(asset, documentID: session.document.id)
                try Task.checkCancellation()
                editor = try ImageCropEditor(image: image, parameters: layer.photoCrop?.parameters,
                    onComplete: { image, parameters in
                        guard !submitting else { return }
                        submitting = true
                        Task {
                            if await session.commitPhotoCrop(layerID: layer.id, image: image, parameters: parameters) { dismiss() }
                            else { error = session.errorMessage ?? "保存失败"; editor = nil }
                            submitting = false
                        }
                    }, onCancel: { dismiss() }, onError: { message in error = message; editor = nil })
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}

/// 只装饰画布外围，与画布共用缩放容器，不参与图层和命中测试。
private struct DiaryLiveSpreadShell: View {
    var body: some View {
        GeometryReader { geometry in
            let rim = geometry.size.width * 0.0225
            Image("DiaryBookLeather").resizable()
                .frame(width: geometry.size.width + rim * 2, height: geometry.size.height + rim * 2)
                .mask {
                    Path { path in
                        path.addRect(CGRect(x: 0, y: 0, width: geometry.size.width + rim * 2, height: geometry.size.height + rim * 2))
                        path.addRect(CGRect(x: rim, y: rim, width: geometry.size.width, height: geometry.size.height))
                    }.fill(style: FillStyle(eoFill: true))
                }
                .offset(x: -rim, y: -rim)
                .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
        }
    }
}

/// A nil aspect ratio still constrains layout; ordinary editing must bypass the modifier entirely.
private struct DiaryAIViewportAspectRatio: ViewModifier {
    let enabled: Bool
    let ratio: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.aspectRatio(ratio, contentMode: .fit)
        } else {
            content
        }
    }
}
