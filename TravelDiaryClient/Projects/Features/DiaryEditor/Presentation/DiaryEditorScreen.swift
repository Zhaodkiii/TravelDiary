import AVFoundation
import SwiftUI
import UIKit

/// 主编辑页面只组织工具与状态；数据修改和保存均交给 Session。
struct DiaryEditorScreen: View {
    @ObservedObject var session: DiaryEditorSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var childEditor: DiaryEditorSession?
    @State private var showPhotos = false
    @State private var showCamera = false
    @State private var capturedPhotos: [UIImage] = []
    @State private var importingCameraPhotos = false
    @State private var showText = false
    @State private var showCrop = false
    @State private var activeTool: DiaryEditorTool?
    @State private var showDrawing = false
    @State private var showStickers = false

    private var toolOpen: Bool { activeTool != nil || showStickers }
    @State private var textLayer: DiaryLayer?

    var body: some View {
        NavigationStack {
            editorContent
            .disabled(session.busy || importingCameraPhotos)
            .navigationTitle(session.isRoot ? "画布编辑器" : "对象编辑器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editorToolbar }
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
            .sheet(isPresented: $showText) { DiaryTextEditorSheet(session: session, layer: textLayer) }
            .sheet(isPresented: $showStickers, onDismiss: { session.finishInteraction() }) {
                MaterialLibraryBrowser(session: session, keepsOpenAfterAdding: true)
            }
            .fullScreenCover(isPresented: $showCrop) {
                if let layer = session.selected { DiaryCropSheet(session: session, layer: layer) }
            }

            .sheet(isPresented: $showDrawing, onDismiss: { session.inkMode = false }) {
                DiaryDrawingSheet(session: session)
                    .presentationDetents([.large])
                    .interactiveDismissDisabled()
            }
            .alert("手帐", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
                Button("确定") { session.errorMessage = nil }
                Button("重新保存") { Task { try? await session.save() } }
            } message: { Text(session.errorMessage ?? "") }
            .task(id: session.id) {
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
            Button { session.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(session.undoStack.isEmpty || session.busy || importingCameraPhotos).accessibilityLabel("撤销")
            Button { session.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(session.redoStack.isEmpty || session.busy || importingCameraPhotos).accessibilityLabel("重做")

        }
    }

    private var editorContent: some View {
            VStack(spacing: 0) {
                if !toolOpen { HStack {
                    Text(session.inkMode ? "单指绘画，双指缩放或移动画布" : "单击选择，再点取消；双指缩放或移动画布")
                    Spacer()
                    Text(session.saveStatus).foregroundStyle(.secondary)
                }
                .font(.caption).padding(.horizontal).padding(.vertical, 8) }
                GeometryReader { geometry in
                    let size = session.canvasBounds.size
                    // 工具模式用紧凑边距适配全部可见高度，普通模式保留完整手柄空间。
                    let margin = toolOpen ? DiaryCanvasSurface.toolControlMargin : DiaryCanvasSurface.controlMargin
                    let horizontalPadding: CGFloat = toolOpen ? margin * 2 : 40
                    let verticalPadding: CGFloat = toolOpen ? 0 : 24
                    let scale = max(0.01, min((geometry.size.width - horizontalPadding) / size.width,
                                             (geometry.size.height - margin * 2 - verticalPadding) / size.height))
                    DiaryZoomableCanvas(contentSize: CGSize(width: size.width * scale + margin * 2, height: size.height * scale + margin * 2), sessionID: session.id, inkMode: session.inkMode, minimumScale: 0.65, toolViewport: toolOpen) {
                      ZStack(alignment: .topLeading) {
                        DiaryCanvasView(session: session, compactViewport: toolOpen, onEdit: {
                            guard let layer = session.selected else { return }
                            if layer.kind == .object { childEditor = session.openObject() }
                            else if layer.kind == .text { openText() }
                            else if layer.kind == .photo { showCrop = true }
                            else if layer.kind == .sticker { childEditor = session.openSelectedStickerObject() }
                        })
                            .frame(width: size.width * scale + margin * 2, height: size.height * scale + margin * 2)

                      }
                      .frame(width: size.width * scale + margin * 2, height: size.height * scale + margin * 2)
                    }
                    .clipped()
                }
                .background(DiaryLibraryStyle.background)
                if showStickers {
                    // Reserve the compact native sheet's space so the existing tool
                    // viewport fits the artwork above it and keeps the canvas at the top.
                    Color.clear.frame(height: MaterialLibraryBrowser.compactHeight).accessibilityHidden(true)
                } else if let activeTool {
                    DiaryEditorToolPanel(title: activeTool.title, onBack: closeTool, onDone: closeTool) {
                        switch activeTool {
                        case .layers: DiaryLayerToolContent(session: session)
                        }
                    }
                    .disabled(session.busy)
                } else { controls }
            }
            .ignoresSafeArea(.container, edges: toolOpen ? .bottom : [])
    }

    private var controls: some View {
        DiaryContextToolbar(session: session,
            onPhotos: { session.finishInteraction(); showPhotos = true },
            onCamera: { session.finishInteraction(); capturedPhotos = []; showCamera = true },
            onDrawing: { session.finishInteraction(); session.select(nil); session.inkMode = true; showDrawing = true },
            onLayers: { session.finishInteraction(); session.layerMode = true; activeTool = .layers },
            onStickers: { session.finishInteraction(); showStickers = true },
            onOpenObject: { childEditor = session.openObject() })
    }
    private func importCapturedPhotos() {
        guard !capturedPhotos.isEmpty else { return }
        let images = capturedPhotos
        capturedPhotos = []
        importingCameraPhotos = true
        Task { @MainActor in
            defer { importingCameraPhotos = false }
            for image in images {
                guard let data = image.jpegData(compressionQuality: 0.95) else {
                    session.errorMessage = "无法读取拍摄照片，请重试。"
                    return
                }
                guard await session.importPhoto(data) else { return }
            }
        }
    }
    private func openText() {
        textLayer = session.selected?.kind == .text ? session.selected : nil
        showText = true
    }
    private func closeTool() {
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
