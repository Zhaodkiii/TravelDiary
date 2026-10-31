import SwiftUI
import PhotosUI

/// The add entry remains anchored while object tools scroll horizontally.
struct DiaryContextToolbar: View {
    @ObservedObject var session: DiaryEditorSession
    let onBackground: () -> Void
    let onPhotos: () -> Void
    let onCamera: () -> Void
    let onDrawing: () -> Void
    let onLayers: () -> Void
    let onStickers: () -> Void
    let onOpenObject: () -> Void
    var onTransform: () -> Void = {}
    var selectionToolsOnly = false
    @State private var panel: Panel?
    @State private var textEditor: DiaryTextEditorPresentation?
    @State private var target: DiaryLayer?
    @State private var cropTarget: DiaryLayer?
    @State private var emptyFrameTarget: DiaryEmptyPhotoFrameTarget?
    @State private var replacementID: UUID?
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var importing = false
    @State private var addExpanded = false

    private enum Panel: String, Identifiable {
        case replacement, photos
        case opacity, arrange, placement, frame, editText, font, fontSize, textColor, typography
        var id: Self { self }
    }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
        VStack(spacing: 18) {
            if selectionToolsOnly, session.selected != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(session.contextActions) { action in
                            Button { perform(action) } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: action.symbol).font(.system(size: 20))
                                    Text(action.title).font(.system(size: 11)).fixedSize()
                                }.frame(minWidth: 38, minHeight: 48).contentShape(Rectangle())
                            }.accessibilityIdentifier("diary.tool.\(action.rawValue)")
                        }
                    }.padding(.horizontal, 20)
                }
            }
            if !selectionToolsOnly {
            if addExpanded {
                HStack(alignment: .top, spacing: 0) {
                    toolButton("拍照", symbol: "camera", action: onCamera)
                        .accessibilityIdentifier("diary.add.camera")
                    toolButton("相册", symbol: "photo.on.rectangle", action: onPhotos)
                    toolButton("画笔", symbol: "pencil.tip", action: onDrawing)
                    toolButton("贴纸", symbol: "seal", action: onStickers)
                    toolButton("背景", symbol: "square.3.layers.3d", action: onBackground)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(alignment: .top, spacing: 22) {
                Menu {
                    Section {
                        Button { session.undo() } label: { Label("撤销", systemImage: "arrow.uturn.backward") }
                            .disabled(session.undoStack.isEmpty)
                        Button { session.redo() } label: { Label("重做", systemImage: "arrow.uturn.forward") }
                            .disabled(session.redoStack.isEmpty)
                    }
                    Section {
                        Button(action: onBackground) { Label("画布背景", systemImage: "square.3.layers.3d") }
                        Button(action: onLayers) { Label("图层管理", systemImage: "square.3.layers.3d.top.filled") }
                        if session.selectedEditingLayer?.kind == .text {
                            Button { target = session.selectedEditingLayer; presentTextEditor(.font) } label: {
                                Label("字体", systemImage: "textformat")
                            }
                        }
                    }
                } label: { toolLabel("更多", symbol: "ellipsis") }
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { addExpanded.toggle() }
                } label: { toolLabel(addExpanded ? "收起" : "添加", symbol: addExpanded ? "xmark" : "plus") }
                    .accessibilityIdentifier("diary.add.toggle")
                Button { openTool(onStickers) } label: { toolLabel("贴纸", symbol: "seal") }
                Button {
                    openTool { target = nil; presentTextEditor(.editText) }
                } label: { toolLabel("文字", symbol: "square.and.pencil") }
            }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, selectionToolsOnly ? 6 : 16)
        .padding(.bottom, selectionToolsOnly ? 6 : 12)
        .frame(maxWidth: .infinity)
        .foregroundStyle(Color(red: 0.45, green: 0.51, blue: 0.49))
        }
        .background {
            if selectionToolsOnly { Capsule().fill(.regularMaterial).overlay(Capsule().stroke(.white.opacity(0.8), lineWidth: 1)) }
        }
        .shadow(color: .black.opacity(selectionToolsOnly ? 0.12 : 0), radius: 12, y: 6)
        .disabled(session.busy || importing)
        .fullScreenCover(item: $textEditor) { presentation in
            DiaryTextEditorSheet(session: session, draft: presentation.draft, initialTab: presentation.initialTab)
        }
        .sheet(item: $panel) { panel in panelContent(panel) }
        .fullScreenCover(item: $cropTarget) { layer in DiaryCropSheet(session: session, layer: layer) }
        .photosPicker(isPresented: Binding(get: { panel != .photos && showPhotoPicker }, set: { showPhotoPicker = $0 }), selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item, replacementID != nil || emptyFrameTarget != nil else { return }
            let frameTarget = emptyFrameTarget, id = replacementID
            importing = true
            Task { @MainActor in
                defer { photoItem = nil; importing = false; emptyFrameTarget = nil; replacementID = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw DiaryEditorError.invalidImage }
                    if let frameTarget {
                        _ = await session.addPhotoToEmptyFrame(data, target: frameTarget)
                    } else if let id, !(await session.importPhoto(data, replacing: id)), session.errorMessage == nil {
                        session.errorMessage = "照片已变化，请重新选择。"
                    }
                } catch { session.errorMessage = error.localizedDescription }
            }
        }
        .overlay { if importing { ProgressView(emptyFrameTarget == nil ? "正在替换照片…" : "正在添加照片…").padding().background(.regularMaterial, in: Capsule()) } }
    }

    private func toolLabel(_ title: String, symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .regular))
                .frame(width: 46, height: 46)
                .glassEffect(.regular.interactive(), in: Circle())
            Text(title).font(.caption).fixedSize(horizontal: true, vertical: false)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func toolButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button { openTool(action) } label: {
            toolLabel(title, symbol: symbol).frame(maxWidth: .infinity)
        }
    }

    private func openTool(_ action: () -> Void) {
        session.finishInteraction()
        addExpanded = false
        action()
    }

    private func presentTextEditor(_ panel: Panel) {
        textEditor = DiaryTextEditorPresentation(session: session, layer: target, initialTab: textTab(panel))
    }

    private func perform(_ action: DiaryContextAction) {
        session.finishInteraction()
        target = session.selectedEditingLayer
        switch action {
        case .addPhotoToFrame:
            emptyFrameTarget = session.selectedEmptyPhotoFrameTarget
            replacementID = nil
            if emptyFrameTarget != nil { showPhotoPicker = true }
        case .transform: onTransform()
        case .background: onBackground()
        case .layers: onLayers()
        case .replacePhoto:
            emptyFrameTarget = nil
            let photos = session.selectedPhotos
            if photos.count == 1 { replacementID = photos[0].id; showPhotoPicker = true }
            else if !photos.isEmpty { panel = .photos }
        case .crop: cropTarget = target
        case .frame:
            if target?.kind == .photo || target?.isPhotoFrame == true { panel = .frame }
        case .opacity: target = session.selected; panel = .opacity
        case .arrange: target = session.selected; panel = .arrange
        case .editText: presentTextEditor(.editText)
        case .font: presentTextEditor(.font)
        case .fontSize: presentTextEditor(.fontSize)
        case .textColor: presentTextEditor(.textColor)
        case .typography: presentTextEditor(.typography)
        case .replaceMaterial: target = session.selectedMaterialLayer; if target != nil { panel = .replacement }
        case .replaceBackground: onBackground()
        case .placement: target = session.selected; panel = .placement
        case .lock, .unlock:
            if let id = session.selectedID { session.toggleLock(id) }
        case .frameColor, .frameWidth: panel = .frame
        case .editContent, .editDrawing: onOpenObject()
        case .flip: session.flipSelected(horizontal: true)
        }
    }

    @ViewBuilder private func panelContent(_ panel: Panel) -> some View {
        switch panel {
        case .replacement: MaterialLibraryBrowser(session: session, replacingID: target?.id)
        case .photos:
            NavigationStack {
                List(session.selectedPhotos) { photo in
                    Button {
                        replacementID = photo.id; showPhotoPicker = true
                    } label: {
                        HStack {
                            if let id = photo.assetID, let image = session.images[id] {
                                Image(uiImage: image).resizable().scaledToFit().frame(width: 64, height: 64)
                            }
                            Text(photo.name); Spacer(); Text("替换").foregroundStyle(.purple)
                        }
                    }.disabled(importing)
                }.navigationTitle("选择要替换的照片")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { self.panel = nil } } }
            }.presentationDetents([.medium, .large])
                .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
                .interactiveDismissDisabled(importing)
        case .editText, .font, .fontSize, .textColor, .typography:
            DiaryTextEditorSheet(session: session, layer: target, initialTab: textTab(panel))
        case .frame:
            if let target, target.isContentPhoto { DiaryPhotoFramePicker(session: session, photoID: target.id) }
            else if let target, target.assetID != nil, let photoID = target.frameTargetID {
                DiaryPhotoFramePicker(session: session, photoID: photoID)
            } else if let target { DiaryLayerPropertyPanel(session: session, layer: target, mode: .frame) }
        case .opacity, .placement:
            if let target { DiaryLayerPropertyPanel(session: session, layer: target,
                mode: panel == .opacity ? .opacity : panel == .placement ? .placement : .frame) }
        case .arrange:
            DiaryArrangementPanel(session: session)
        }
    }

    private func textTab(_ panel: Panel) -> DiaryTextEditorTab {
        switch panel {
        case .font: .font
        case .fontSize: .size
        case .textColor: .color
        case .typography: .layout
        default: .content
        }
    }
}

/// Local drafts keep cancel/confirm predictable and produce one undo record.
private struct DiaryLayerPropertyPanel: View {
    enum Mode { case opacity, placement, frame }
    @ObservedObject var session: DiaryEditorSession
    let layer: DiaryLayer
    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @State private var opacity: Double
    @State private var x: Double
    @State private var y: Double
    @State private var scale: Double
    @State private var angle: Double
    @State private var color: Color
    @State private var width: Double
    init(session: DiaryEditorSession, layer: DiaryLayer, mode: Mode) {
        self.session = session; self.layer = layer; self.mode = mode
        _opacity = State(initialValue: layer.effectiveOpacity)
        _x = State(initialValue: layer.transform.position.x); _y = State(initialValue: layer.transform.position.y)
        _scale = State(initialValue: layer.transform.scale); _angle = State(initialValue: layer.transform.rotationDegrees)
        _color = State(initialValue: Color(uiColor: DiaryPageRenderer.color(layer.frameColor ?? .white)))
        _width = State(initialValue: layer.frameWidth ?? 20)
    }
    private var title: String { mode == .opacity ? "透明度" : mode == .placement ? "位置与大小" : "相框" }
    var body: some View {
        NavigationStack {
            Form {
                switch mode {
                case .opacity:
                    Text("透明度 \(Int(opacity * 100))%")
                    Slider(value: $opacity, in: 0...1)
                    RoundedRectangle(cornerRadius: 8).fill(.purple.opacity(opacity)).frame(height: 48)
                case .placement:
                    TextField("水平位置", value: $x, format: .number).keyboardType(.numbersAndPunctuation)
                    TextField("垂直位置", value: $y, format: .number).keyboardType(.numbersAndPunctuation)
                    Text("缩放 \(scale, specifier: "%.2f") 倍")
                    Slider(value: $scale, in: 0.05...20)
                    Text("旋转 \(angle, specifier: "%.0f")°")
                    Slider(value: $angle, in: -180...180)
                case .frame:
                    ColorPicker("边框颜色", selection: $color)
                    Text("边框粗细 \(Int(width))")
                    Slider(value: $width, in: 0...100, step: 1)
                    RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: width / 4).padding(15).frame(height: 80)
                }
            }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("完成") {
                        switch mode {
                        case .opacity: session.setLayerOpacity(layer.id, value: opacity)
                        case .placement: session.updatePlacement(layer.id, position: CGPoint(x: x, y: y), scale: scale, angle: angle)
                        case .frame: session.updateFrame(layer.id, color: DiaryColor(color), width: width)
                        }
                        dismiss()
                    }.disabled(!x.isFinite || !y.isFinite || !scale.isFinite || !angle.isFinite) }
                }
        }.presentationDetents([.medium, .large])
    }
}

private struct DiaryArrangementPanel: View {
    @ObservedObject var session: DiaryEditorSession
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Button("前移一层") { session.reorderSelected(forward: true) }.disabled(!session.canMoveSelected(forward: true))
                Button("后移一层") { session.reorderSelected(forward: false) }.disabled(!session.canMoveSelected(forward: false))
                Button("置于顶层") { move(to: session.scopeLayers.count - 1) }.disabled(!session.canMoveSelected(forward: true))
                Button("置于底层") { move(to: 0) }.disabled(!session.canMoveSelected(forward: false))
            }.navigationTitle("排列").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.presentationDetents([.medium])
    }
    private func move(to index: Int) { if let id = session.selectedID { session.moveLayer(id, to: index) } }
}

extension DiaryColor {
    @MainActor init(_ color: Color) {
        let source = UIColor(color).resolvedColor(with: .current)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let normalized = source.cgColor.converted(to: space, intent: .defaultIntent, options: nil).map(UIColor.init(cgColor:)) ?? source
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        if !normalized.getRed(&r, green: &g, blue: &b, alpha: &a) {
            var white: CGFloat = 0
            if normalized.getWhite(&white, alpha: &a) { r = white; g = white; b = white }
        }
        // The document stores bounded sRGB; ColorPicker may supply extended or Display P3 components.
        func bounded(_ value: CGFloat) -> Double { value.isFinite ? Double(min(1, max(0, value))) : 0 }
        self.init(red: bounded(r), green: bounded(g), blue: bounded(b), alpha: bounded(a))
    }
}
