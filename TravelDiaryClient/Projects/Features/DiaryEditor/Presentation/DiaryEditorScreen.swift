import AVFoundation
import SwiftUI
import UIKit

/// 主编辑页面只组织工具与状态；数据修改和保存均交给 Session。
struct DiaryEditorScreen: View {
    @ObservedObject var session: DiaryEditorSession
    var entranceOnRightPage = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsSpreadShell = false
    @State private var childEditor: DiaryEditorSession?
    @State private var showPhotos = false
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

    private var toolOpen: Bool { activeTool != nil || showStickers }

    var body: some View {
        NavigationStack {
            editorContent
            .disabled(session.busy || importingCameraPhotos)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editorToolbar }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(toolOpen ? .hidden : .visible, for: .navigationBar)
            .overlay {
                if session.busy || importingCameraPhotos {
                    ProgressView(importingCameraPhotos ? "正在添加拍摄照片…" : "正在处理…")
                        .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .fullScreenCover(item: $childEditor) { child in
                AnyView(DiaryEditorScreen(session: child))
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
                if MaterialCatalogRepository.shared.pendingLibrary != nil { showStickers = true }
                if session.isRoot, let bookID = session.document.bookID {
                    DiaryBookAccessStore(ownerID: session.store.ownerID)
                        .record(bookID: bookID, pageID: session.document.id)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { session.finishInteraction(); Task { try? await session.save() } }
            }
            .interactiveDismissDisabled()
        }
    }

    /// 仅完整跨页比例启用外壳预览，等比例的不同分辨率同样适用。
    private var supportsSpreadPreview: Bool {
        let size = session.document.root.referenceSize
        guard session.isRoot, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return false }
        return abs(size.width / size.height - 4370.0 / 3130.0) < 0.000001
    }

    private var supportsSinglePageViewport: Bool {
        let size = session.document.root.referenceSize
        return session.isRoot && size.height > 0 && abs(size.width / size.height - 2185.0 / 3130.0) < 0.000001
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack {
                Button("完成") { Task { if await session.commitToParent() { dismiss() } } }
                if !session.isRoot { Button("取消") { Task { await session.cancelEditor(); dismiss() } } }
            }
            .disabled(session.busy || importingCameraPhotos)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if supportsSpreadPreview {
                Button { session.finishInteraction(); showsSpreadShell.toggle() } label: { Image(systemName: showsSpreadShell ? "eye.fill" : "eye") }
                    .accessibilityLabel(showsSpreadShell ? "隐藏画布外壳" : "显示画布外壳")
                    .disabled(session.busy || importingCameraPhotos)
            }
            Button { session.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(session.undoStack.isEmpty || session.busy || importingCameraPhotos).accessibilityLabel("撤销")
            Button { session.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(session.redoStack.isEmpty || session.busy || importingCameraPhotos).accessibilityLabel("重做")

        }
    }

    private var editorContent: some View {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    let size = session.canvasBounds.size
                    // 工具模式用紧凑边距适配全部可见高度，普通模式保留完整手柄空间。
                    let margin = toolOpen || session.layerMode ? DiaryCanvasSurface.toolControlMargin : DiaryCanvasSurface.controlMargin
                    let horizontalPadding: CGFloat = toolOpen ? margin * 2 : 40
                    let verticalPadding: CGFloat = toolOpen ? 0 : 24
                    let scale = max(0.01, min((geometry.size.width - horizontalPadding) / size.width,
                                             (geometry.size.height - margin * 2 - verticalPadding) / size.height))
                    DiaryZoomableCanvas(contentSize: CGSize(width: size.width * scale + margin * 2, height: size.height * scale + margin * 2), sessionID: session.id, inkMode: session.inkMode, minimumScale: 0.65, toolViewport: toolOpen, contentRevision: (showsSpreadShell ? 1 : 0) + (session.layerMode ? 2 : 0), entranceFocusRect: supportsSpreadPreview ? CGRect(x: margin + (entranceOnRightPage ? size.width * scale / 2 : 0), y: margin, width: size.width * scale / 2, height: size.height * scale) : nil, preservedCanvasRect: supportsSinglePageViewport ? CGRect(x: margin, y: margin, width: size.width * scale, height: size.height * scale) : nil) {
                      ZStack(alignment: .topLeading) {
                        if supportsSpreadPreview && showsSpreadShell {
                            DiaryLiveSpreadShell()
                                .frame(width: size.width * scale, height: size.height * scale)
                                .offset(x: margin, y: margin)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                        DiaryCanvasView(session: session, compactViewport: toolOpen, stagesEntrance: supportsSpreadPreview, onSelectionViewportRect: { rect in
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
                            .frame(width: size.width * scale + margin * 2, height: size.height * scale + margin * 2)
                        if supportsSpreadPreview && showsSpreadShell {
                            LinearGradient(colors: [.clear, .black.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: max(2, size.width * scale * 0.018), height: size.height * scale)
                                .offset(x: margin + size.width * scale * (0.5 - 0.009), y: margin)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                      }
                      .frame(width: size.width * scale + margin * 2, height: size.height * scale + margin * 2)
                    }
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
                // 画布可延伸至 Home 指示器区域；外层工具栏仍按安全区定位。
                .ignoresSafeArea(.container, edges: toolOpen ? [] : .bottom)
                .background(DiaryLibraryStyle.background)
                if showStickers {
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
            onTransform: { session.beginFreeTransform(); if session.transformDraft != nil { activeTool = .transform } },
            selectionToolsOnly: selectionToolsOnly)
    }
    private func importCapturedPhotos() {
        guard !capturedPhotos.isEmpty else { return }
        let images = capturedPhotos
        capturedPhotos = []
        importingCameraPhotos = true
        Task { @MainActor in
            defer { importingCameraPhotos = false }
            let data = images.compactMap { $0.jpegData(compressionQuality: 0.95) }
            guard data.count == images.count else {
                session.errorMessage = "无法读取拍摄照片，请重试。"; return
            }
            await session.importPhotos(data)
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
private struct DiaryCaptureCamera: View {
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
