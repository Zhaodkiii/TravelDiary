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
    @State private var panel: Panel?
    @State private var textPanel: Panel?
    @State private var target: DiaryLayer?
    @State private var cropTarget: DiaryLayer?
    @State private var replacementID: UUID?
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var importing = false

    private enum Panel: String, Identifiable {
        case replacement, photos
        case opacity, arrange, placement, frame, editText, font, fontSize, textColor, typography
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 6) {
            // 保留信息行的布局高度，选择切换不会改变画布尺寸或重置浏览倍率。
            HStack {
                Text(session.selected?.name ?? "").font(.caption).lineLimit(1).foregroundStyle(.secondary)
                Spacer()
                Button(action: onLayers) { Label("图层", systemImage: "square.3.layers.3d") }.font(.caption)
            }
            .padding(.horizontal, 16)
            .opacity(session.selected == nil ? 0 : 1)
            .allowsHitTesting(session.selected != nil)
            .accessibilityHidden(session.selected == nil)
            HStack(spacing: 0) {
                Menu {
                    Button(action: onPhotos) { Label("照片（可多选）", systemImage: "photo.on.rectangle") }
                    Button(action: onCamera) { Label("相机", systemImage: "camera") }
                        .accessibilityIdentifier("diary.add.camera")
                    Button { target = nil; textPanel = .editText } label: { Label("文字", systemImage: "textformat") }
                    Button(action: onStickers) { Label("贴纸", systemImage: "face.smiling") }
                    Button(action: onBackground) { Label("背景", systemImage: "photo.fill") }
                    Button(action: onDrawing) { Label("画笔", systemImage: "pencil.tip") }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 29)).foregroundStyle(.purple)
                        Text("添加").font(.caption)
                    }.frame(width: 66, height: 62).contentShape(Rectangle())
                }.accessibilityLabel("添加")
                Divider().frame(height: 38)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(session.contextActions) { action in
                            Button { perform(action) } label: {
                                VStack(spacing: 7) {
                                    Image(systemName: action.symbol).font(.system(size: 23))
                                    Text(action == .replaceMaterial && session.selectedEditingKind == .textImage ? "替换素材" : action.title)
                                        .font(.caption).lineLimit(1)
                                }.frame(minWidth: 64, minHeight: 62).contentShape(Rectangle())
                            }.accessibilityIdentifier("diary.tool.\(action.rawValue)")
                        }
                    }.padding(.horizontal, 10)
                }
            }
        }
        .padding(.vertical, 8).foregroundStyle(DiaryLibraryStyle.ink).background(DiaryLibraryStyle.background)
        .disabled(session.busy || importing)
        .fullScreenCover(item: $textPanel) { value in
            DiaryTextEditorSheet(session: session, layer: target, initialTab: textTab(value))
        }
        .sheet(item: $panel) { panel in panelContent(panel) }
        .fullScreenCover(item: $cropTarget) { layer in DiaryCropSheet(session: session, layer: layer) }
        .photosPicker(isPresented: Binding(get: { panel != .photos && showPhotoPicker }, set: { showPhotoPicker = $0 }), selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item, let id = replacementID else { return }
            importing = true
            Task { @MainActor in
                defer { photoItem = nil; importing = false }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw DiaryEditorError.invalidImage }
                    if !(await session.importPhoto(data, replacing: id)), session.errorMessage == nil {
                        session.errorMessage = "照片已变化，请重新选择。"
                    }
                } catch { session.errorMessage = error.localizedDescription }
            }
        }
        .overlay { if importing { ProgressView("正在替换照片…").padding().background(.regularMaterial, in: Capsule()) } }
    }

    private func perform(_ action: DiaryContextAction) {
        session.finishInteraction()
        target = session.selectedEditingLayer
        switch action {
        case .transform: onTransform()
        case .background: onBackground()
        case .layers: onLayers()
        case .replacePhoto:
            let photos = session.selectedPhotos
            if photos.count == 1 { replacementID = photos[0].id; showPhotoPicker = true }
            else if !photos.isEmpty { panel = .photos }
        case .crop: cropTarget = target
        case .frame:
            if target?.kind == .photo || target?.isPhotoFrame == true { panel = .frame }
        case .opacity: target = session.selected; panel = .opacity
        case .arrange: target = session.selected; panel = .arrange
        case .editText: textPanel = .editText
        case .font: textPanel = .font
        case .fontSize: textPanel = .fontSize
        case .textColor: textPanel = .textColor
        case .typography: textPanel = .typography
        case .replaceMaterial: target = session.selectedMaterialLayer; if target != nil { panel = .replacement }
        case .replaceBackground: onBackground()
        case .placement: target = session.selected; panel = .placement
        case .lock, .unlock:
            if let id = session.selectedID { session.toggleLock(id) }
        case .frameColor, .frameWidth: panel = .frame
        case .editContent: onOpenObject()
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
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
