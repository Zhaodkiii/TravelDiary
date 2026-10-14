import SwiftUI
import PhotosUI

/// 主编辑页面只组织工具与状态；数据修改和保存均交给 Session。
struct DiaryEditorScreen: View {
    @ObservedObject var session: DiaryEditorSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
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
            VStack(spacing: 0) {
                HStack {
                    if session.groupID != nil {
                        Button("完成组合编辑") { session.leaveGroup() }
                    } else { Text(session.inkMode ? "画笔覆盖整页" : "选择元素后拖动，使用下方工具调整") }
                    Spacer()
                    Text(session.saveStatus).foregroundStyle(.secondary)
                }
                .font(.caption).padding(.horizontal).padding(.vertical, 8)
                GeometryReader { geometry in
                    let scale = max(0.01, min((geometry.size.width - 24) / 1000, (geometry.size.height - 24) / 1400))
                    ZStack(alignment: .topLeading) {
                        DiaryCanvasView(session: session)
                            .frame(width: 1000 * scale, height: 1400 * scale)
                        if session.inkMode {
                            DiaryDrawingCanvasView(session: session)
                                .frame(width: 1000, height: 1400)
                                .scaleEffect(scale, anchor: .topLeading)
                                .frame(width: 1000 * scale, height: 1400 * scale, alignment: .topLeading)
                                .clipped()
                        }
                    }
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                controls
            }
            .disabled(session.busy)
            .navigationTitle("手帐编辑器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { Task { if await session.close() { dismiss() } } }
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
            .sheet(isPresented: $showText) { textEditor }
            .sheet(isPresented: $showCrop) {
                if let layer = session.selected { DiaryCropSheet(session: session, layer: layer) }
            }
            .sheet(isPresented: $showLayers) { layerPanel }
            .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
                if let exportURL {
                    NavigationStack {
                        VStack(spacing: 20) {
                            Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                            Text("已生成 2000 × 2800 图片")
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

    private var controls: some View {
        VStack(spacing: 8) {
            if let layer = session.selected, !session.inkMode {
                HStack {
                    Text(layer.name).font(.caption).lineLimit(1)
                    Spacer()
                    if layer.kind == .group { Button("编辑组合") { session.enterGroup() } }
                    if layer.kind == .photo {
                        Button("替换") { replacementID = layer.id; showPhotoPicker = true }
                        Button("裁剪") { showCrop = true }
                    }
                    if layer.kind == .text { Button("编辑文字") { openText() } }
                    if layer.kind != .photo { Button("删除", role: .destructive) { session.removeSelected() } }
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
                            .disabled(session.groupID != nil)
                        Button { session.select(nil); openText() } label: { Label("文字", systemImage: "textformat") }
                        Menu {
                            Button("爱心") { Task { await session.addSticker(symbol: "heart.fill") } }
                            Button("星星") { Task { await session.addSticker(symbol: "star.fill") } }
                            Button("太阳") { Task { await session.addSticker(symbol: "sun.max.fill") } }
                        } label: { Label("贴纸", systemImage: "face.smiling") }
                        Button { session.select(nil); session.inkMode = true } label: { Label("画笔", systemImage: "pencil.tip") }
                            .disabled(session.groupID != nil)
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

/// 裁剪在独立工作副本中预览；取消不修改文档，完成只产生一条撤销记录。
private struct DiaryCropSheet: View {
    @ObservedObject var session: DiaryEditorSession
    let layer: DiaryLayer
    @Environment(\.dismiss) private var dismiss
    @State private var crop: DiaryCrop
    init(session: DiaryEditorSession, layer: DiaryLayer) {
        self.session = session; self.layer = layer; _crop = State(initialValue: layer.crop)
    }
    var body: some View {
        NavigationStack {
            VStack {
                if let id = layer.assetID, let image = session.images[id], let asset = session.document.assets[id] {
                    GeometryReader { geometry in
                        let fit = min(geometry.size.width / layer.size.width, geometry.size.height / layer.size.height)
                        let rect = crop.imageRect(source: asset.pixelSize, frame: layer.size)
                        Image(uiImage: image).resizable()
                            .frame(width: rect.width * fit, height: rect.height * fit)
                            .offset(x: rect.minX * fit, y: rect.minY * fit)
                            .frame(width: layer.size.width * fit, height: layer.size.height * fit, alignment: .topLeading)
                            .clipped().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: 280)
                    Form {
                        Slider(value: $crop.zoom, in: 1...5) { Text("放大照片") }
                        Text("照片放大 \(crop.zoom, specifier: "%.1f") 倍")
                        Slider(value: $crop.offset.x, in: -layer.size.width...layer.size.width) { Text("左右取景") }
                        Text("左右取景")
                        Slider(value: $crop.offset.y, in: -layer.size.height...layer.size.height) { Text("上下取景") }
                        Text("上下取景")
                    }
                }
            }
            .navigationTitle("照片取景")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { session.applyCrop(crop); dismiss() } }
            }
        }
    }
}
