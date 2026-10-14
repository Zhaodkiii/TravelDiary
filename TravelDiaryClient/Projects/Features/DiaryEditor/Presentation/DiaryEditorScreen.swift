import SwiftUI
import PhotosUI

/// 主编辑页面只组织工具与状态；数据修改和保存均交给 Session。
struct DiaryEditorScreen: View {
    @ObservedObject var session: DiaryEditorSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var childEditor: DiaryEditorSession?
    @State private var photoItem: PhotosPickerItem?
    @State private var replacementID: UUID?
    @State private var showPhotoPicker = false
    @State private var showText = false
    @State private var showCrop = false
    @State private var showLayers = false
    @State private var exportURL: URL?
    @State private var textDraft = ""
    @State private var fontSize: CGFloat = 36

    var body: some View {
        NavigationStack {
            editorContent
            .disabled(session.busy)
            .navigationTitle(session.isRoot ? "画布编辑器" : "对象编辑器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editorToolbar }
            .overlay { if session.busy { ProgressView("正在处理…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                let target = replacementID
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw DiaryEditorError.invalidImage }
                        await session.importPhoto(data, replacing: target)
                    } catch { session.errorMessage = error.localizedDescription }
                    photoItem = nil
                }
            }
            .fullScreenCover(item: $childEditor) { child in
                AnyView(DiaryEditorScreen(session: child))
            }
            .sheet(isPresented: $showText) { textEditor }
            .fullScreenCover(isPresented: $showCrop) {
                if let layer = session.selected { DiaryCropSheet(session: session, layer: layer) }
            }
            .sheet(isPresented: $showLayers) { layerPanel }
            .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
                if let exportURL {
                    NavigationStack {
                        VStack(spacing: 20) {
                            Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                            Text("已生成 PNG 图片（保留透明区域）")
                            ShareLink(item: exportURL) { Label("分享或保存图片", systemImage: "square.and.arrow.up") }
                                .buttonStyle(.borderedProminent)
                        }
                        .navigationTitle("导出完成")
                        .toolbar { Button("完成") { self.exportURL = nil } }
                    }
                    .presentationDetents([.medium])
                }
            }
            .alert("手帐", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
                Button("确定") { session.errorMessage = nil }
                Button("重新保存") { Task { try? await session.save() } }
            } message: { Text(session.errorMessage ?? "") }
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
            .disabled(session.busy)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { session.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(session.undoStack.isEmpty || session.busy).accessibilityLabel("撤销")
            Button { session.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(session.redoStack.isEmpty || session.busy).accessibilityLabel("重做")
            Button { Task { exportURL = await session.export() } } label: { Image(systemName: "square.and.arrow.up") }
                .disabled(session.busy).accessibilityLabel("导出图片")
        }
    }

    private var editorContent: some View {
            VStack(spacing: 0) {
                HStack {
                    Text(session.inkMode ? "涂鸦属于当前对象，返回后跟随对象移动" : "选中对象后打开独立编辑页面")
                    Spacer()
                    Text(session.saveStatus).foregroundStyle(.secondary)
                }
                .font(.caption).padding(.horizontal).padding(.vertical, 8)
                GeometryReader { geometry in
                    let size = session.canvasBounds.size
                    let scale = max(0.01, min((geometry.size.width - 24) / size.width, (geometry.size.height - 24) / size.height))
                    ZStack(alignment: .topLeading) {
                        DiaryCanvasView(session: session)
                            .frame(width: size.width * scale, height: size.height * scale)
                        if session.inkMode {
                            DiaryDrawingCanvasView(session: session)
                                .frame(width: size.width, height: size.height)
                                .scaleEffect(scale, anchor: .topLeading)
                                .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
                                .clipped()
                        }
                    }
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                controls
            }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            if let layer = session.selected, !session.inkMode {
                HStack {
                    Text(layer.name).font(.caption).lineLimit(1)
                    Spacer()
                    if layer.kind == .object { Button("打开对象") { childEditor = session.openObject() } }
                    if layer.kind == .photo {
                        Button("替换") { replacementID = layer.id; showPhotoPicker = true }
                        Button("裁剪") { showCrop = true }
                        if layer.photoCrop != nil { Button("恢复原图") { session.restoreOriginalPhoto() } }
                        Button("相框") { session.addFrame() }
                    }
                    if layer.kind == .text { Button("编辑文字") { openText() } }
                    if layer.id != session.content.primaryLayerID { Button("删除", role: .destructive) { session.removeSelected() } }
                }.font(.caption).disabled(layer.locked)
                HStack {
                    Text("大小").font(.caption)
                    Slider(value: Binding(get: { session.selected?.transform.scale ?? 1 }, set: { session.previewScale($0) }),
                           in: 0.2...3, onEditingChanged: { interactionChanged($0) })
                    Text("方向").font(.caption)
                    Slider(value: Binding(get: { session.selected?.transform.rotationDegrees ?? 0 }, set: { session.previewAngle($0) }),
                           in: -180...180, onEditingChanged: { interactionChanged($0) })
                }
                .disabled(layer.locked)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    if session.inkMode {
                        Button("完成绘画") { session.finishInteraction(); session.inkMode = false }
                        Button(session.eraser ? "使用画笔" : "橡皮擦") { session.eraser.toggle() }
                        Button("清空画笔", role: .destructive) { session.clearDrawing() }
                    } else {
                        Button { replacementID = nil; showPhotoPicker = true } label: { Label("照片", systemImage: "photo") }
                        Button { session.select(nil); openText() } label: { Label("文字", systemImage: "textformat") }
                        Menu {
                            Button("爱心") { Task { await session.addSticker(symbol: "heart.fill") } }
                            Button("星星") { Task { await session.addSticker(symbol: "star.fill") } }
                            Button("太阳") { Task { await session.addSticker(symbol: "sun.max.fill") } }
                        } label: { Label("贴纸", systemImage: "face.smiling") }
                        Button { session.select(nil); session.inkMode = true } label: { Label("画笔", systemImage: "pencil.tip") }
                        Menu {
                            Button("透明") { session.setBackground(nil) }
                            Button("白色") { session.setBackground(.white) }
                            Button("暖黄") { session.setBackground(.yellow) }
                            Button("粉色") { session.setBackground(.pink) }
                            Button("薄荷绿") { session.setBackground(.mint) }
                        } label: { Label("背景", systemImage: "paintpalette") }
                        Button { showLayers = true } label: { Label("图层", systemImage: "square.3.layers.3d") }
                    }
                }.font(.subheadline)
            }
        }
        .padding(12).background(.regularMaterial).disabled(session.busy)
    }
    private func interactionChanged(_ editing: Bool) {
        if editing { session.beginInteraction() } else { session.finishInteraction() }
    }
    private func openText() {
        textDraft = session.selected?.kind == .text ? session.selected?.text ?? "" : ""
        fontSize = session.selected?.kind == .text ? session.selected?.fontSize ?? 36 : 36
        showText = true
    }
    private var textEditor: some View {
        NavigationStack {
            Form {
                TextEditor(text: $textDraft).frame(minHeight: 160)
                Slider(value: $fontSize, in: 18...90) { Text("字号") }
                Text("字号 \(Int(fontSize))")
            }
            .navigationTitle("文字")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { showText = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { session.applyText(textDraft, fontSize: fontSize); showText = false }
                        .disabled(textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    private var layerPanel: some View {
        NavigationStack {
            List {
                ForEach(session.scopeLayers.reversed()) { layer in
                    HStack {
                        Button(layer.name) { session.select(layer.id) }
                            .fontWeight(session.selectedID == layer.id ? .bold : .regular)
                        Spacer()
                        Button { session.toggleVisibility(layer.id) } label: { Image(systemName: layer.visible ? "eye" : "eye.slash") }
                            .accessibilityLabel(layer.visible ? "隐藏" : "显示")
                        Button { session.toggleLock(layer.id) } label: { Image(systemName: layer.locked ? "lock.fill" : "lock.open") }
                            .accessibilityLabel(layer.locked ? "解锁" : "锁定")
                    }.buttonStyle(.borderless)
                }
                if session.selectedID != nil {
                    Button("上移一层") { session.reorderSelected(forward: true) }
                    Button("下移一层") { session.reorderSelected(forward: false) }
                }
            }
            .navigationTitle("图层（上方盖住下方）")
            .toolbar { Button("完成") { showLayers = false } }
        }
    }
}

/// 独立全屏裁剪只加载照片原图，装饰始终留在对象的其他图层中。
private struct DiaryCropSheet: View {
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
                      let asset = session.document.assets[id] else { throw DiaryEditorError.missingResource }
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
