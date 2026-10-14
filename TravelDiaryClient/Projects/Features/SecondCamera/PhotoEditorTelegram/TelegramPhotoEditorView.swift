import PencilKit
import SwiftUI

struct TelegramPhotoEditorView: View {
    let sourceImage: UIImage
    let onCancel: () -> Void
    let onComplete: (UIImage) -> Void

    @State private var selectedTool: TelegramPhotoEditorTool = .adjustments
    @State private var selectedAdjustment: AdjustmentKey = .enhance
    @State private var adjustments = TelegramPhotoAdjustments.neutral
    @State private var curves = TelegramPhotoCurves.neutral
    @State private var curveChannel: TelegramPhotoCurveChannel = .all
    @State private var cropPreset: TelegramPhotoCropPreset = .original
    @State private var quarterTurns = 0
    @State private var straightenDegrees = 0.0
    @State private var isFlippedHorizontally = false
    @State private var blur = TelegramPhotoBlur.off
    @State private var drawing = PKDrawing()
    @State private var drawingTool: TelegramPhotoDrawingTool = .pen
    @State private var drawingColor = TelegramPhotoEditorColor.palette[2]
    @State private var drawingWidth: CGFloat = 8
    @State private var drawingCanvasSize = CGSize(width: 1, height: 1)
    @State private var drawingAction: TelegramDrawingCanvasAction = .none
    @State private var drawingActionCounter = 0
    @State private var canRedoDrawing = false
    @State private var textOverlays: [TelegramPhotoTextOverlay] = []
    @State private var selectedTextID: UUID?
    @State private var textColor = TelegramPhotoEditorColor.palette[0]
    @State private var textStyle: TelegramPhotoTextStyle = .regular
    @State private var textFont: TelegramPhotoTextFont = .system
    @State private var draftText = ""
    @State private var stickerOverlays: [TelegramPhotoStickerOverlay] = []
    @State private var selectedStickerID: UUID?
    @State private var previewImage: UIImage?
    @State private var isShowingOriginal = false
    @State private var isRendering = false

    private let stickers = ["😀", "😍", "🥳", "😎", "😂", "❤️", "🔥", "✨", "👍", "👏", "🎉", "🌈", "⭐️", "📍", "✈️", "☕️", "🐳", "⬆️", "➡️", "✅"]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                editorPreview
                toolPanel
                toolBar
            }
            if isRendering {
                Color.black.opacity(0.48).ignoresSafeArea()
                ProgressView("正在生成原尺寸照片…")
                    .tint(.white)
                    .foregroundStyle(.white)
                    .padding(22)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .preferredColorScheme(.dark)
        .task(id: previewKey) {
            await Task.yield()
            previewImage = TelegramPhotoEditorRenderer.preview(
                sourceImage: sourceImage,
                adjustments: adjustments,
                curves: curves,
                cropPreset: cropPreset,
                quarterTurns: quarterTurns,
                straightenDegrees: straightenDegrees,
                isFlippedHorizontally: isFlippedHorizontally,
                blur: blur
            )
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button("取消", action: onCancel)
            Spacer()
            Button {
                resetEditor()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .accessibilityLabel("重置全部编辑")
            Button {
            } label: {
                Image(systemName: "eye")
            }
            .onLongPressGesture(minimumDuration: 0, pressing: { isShowingOriginal = $0 }, perform: {})
            .accessibilityLabel("按住查看原图")
            Button("完成", action: completeEditing)
                .fontWeight(.semibold)
                .foregroundStyle(telegramBlue)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(height: 52)
    }

    private var editorPreview: some View {
        GeometryReader { proxy in
            let available = CGSize(width: max(proxy.size.width - 24, 1), height: max(proxy.size.height - 18, 1))
            let canvasSize = fittedCanvasSize(in: available)
            ZStack {
                Image(uiImage: isShowingOriginal ? sourceImage : (previewImage ?? sourceImage))
                    .resizable()
                    .scaledToFill()
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .clipped()

                if !isShowingOriginal {
                    TelegramDrawingCanvasView(
                        drawing: $drawing,
                        color: drawingColor.uiColor,
                        lineWidth: drawingWidth,
                        selectedTool: drawingTool,
                        isEnabled: selectedTool == .draw,
                        action: drawingAction,
                        historyChanged: { _, canRedo in canRedoDrawing = canRedo }
                    )
                    .frame(width: canvasSize.width, height: canvasSize.height)

                    textOverlayLayer(canvasSize: canvasSize)
                    stickerOverlayLayer(canvasSize: canvasSize)

                    if selectedTool == .blur, blur.mode != .off {
                        blurGuide(canvasSize: canvasSize)
                    }
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .clipShape(Rectangle())
            .overlay(Rectangle().stroke(.white.opacity(0.14), lineWidth: 1))
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .onAppear { drawingCanvasSize = canvasSize }
            .onChange(of: canvasSize) { _, value in drawingCanvasSize = value }
        }
        .frame(maxHeight: .infinity)
    }

    private func textOverlayLayer(canvasSize: CGSize) -> some View {
        ForEach($textOverlays) { $overlay in
            Text(overlay.text)
                .font(swiftUIFont(overlay.font, size: 28 * overlay.scale))
                .multilineTextAlignment(.center)
                .foregroundStyle(overlay.style == .filled ? Color.black : overlay.color.color)
                .padding(.horizontal, overlay.style == .filled ? 9 : 0)
                .padding(.vertical, overlay.style == .filled ? 5 : 0)
                .background(overlay.style == .filled ? overlay.color.color : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .shadow(color: overlay.style == .regular ? .black.opacity(0.75) : .clear, radius: 2, y: 1)
                .overlay {
                    if overlay.style == .outline {
                        Text(overlay.text)
                            .font(swiftUIFont(overlay.font, size: 28 * overlay.scale))
                            .foregroundStyle(overlay.color.color)
                    }
                }
                .rotationEffect(.radians(overlay.rotation))
                .position(x: canvasSize.width * overlay.normalizedPosition.x, y: canvasSize.height * overlay.normalizedPosition.y)
                .overlay(selectionBorder(selected: selectedTextID == overlay.id))
                .onTapGesture { selectedTextID = overlay.id; selectedStickerID = nil }
                .gesture(dragGesture(position: $overlay.normalizedPosition, canvasSize: canvasSize))
                .allowsHitTesting(selectedTool == .text)
        }
    }

    private func stickerOverlayLayer(canvasSize: CGSize) -> some View {
        ForEach($stickerOverlays) { $sticker in
            Text(sticker.content)
                .font(.system(size: 58 * sticker.scale))
                .rotationEffect(.radians(sticker.rotation))
                .position(x: canvasSize.width * sticker.normalizedPosition.x, y: canvasSize.height * sticker.normalizedPosition.y)
                .overlay(selectionBorder(selected: selectedStickerID == sticker.id))
                .onTapGesture { selectedStickerID = sticker.id; selectedTextID = nil }
                .gesture(dragGesture(position: $sticker.normalizedPosition, canvasSize: canvasSize))
                .allowsHitTesting(selectedTool == .sticker)
        }
    }

    private func selectionBorder(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 7)
            .stroke(selected ? telegramBlue : .clear, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            .padding(-5)
    }

    private func dragGesture(position: Binding<CGPoint>, canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0).onChanged { value in
            position.wrappedValue = CGPoint(
                x: min(max(value.location.x / canvasSize.width, 0), 1),
                y: min(max(value.location.y / canvasSize.height, 0), 1)
            )
        }
    }

    private func blurGuide(canvasSize: CGSize) -> some View {
        Circle()
            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .frame(width: canvasSize.width * blur.size * 2, height: canvasSize.width * blur.size * 2)
            .position(x: canvasSize.width * blur.position.x, y: canvasSize.height * blur.position.y)
            .gesture(dragGesture(position: $blur.position, canvasSize: canvasSize))
    }

    @ViewBuilder
    private var toolPanel: some View {
        Group {
            switch selectedTool {
            case .adjustments: adjustmentPanel
            case .curves: curvesPanel
            case .crop: cropPanel
            case .blur: blurPanel
            case .draw: drawingPanel
            case .text: textPanel
            case .sticker: stickerPanel
            }
        }
        .frame(height: 190)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(white: 0.075))
    }

    private var adjustmentPanel: some View {
        VStack(spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AdjustmentKey.allCases) { key in
                        Button(key.title) { selectedAdjustment = key }
                            .buttonStyle(TelegramEditorCapsuleButtonStyle(isSelected: selectedAdjustment == key))
                    }
                }
            }
            editorSlider(title: selectedAdjustment.title, value: adjustmentBinding, range: selectedAdjustment.range)
            HStack {
                Text("Telegram 调节工具")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("归零") { adjustmentBinding.wrappedValue = selectedAdjustment.neutralValue }
                    .font(.caption.weight(.semibold))
            }
        }
    }

    private var curvesPanel: some View {
        VStack(spacing: 7) {
            HStack {
                ForEach(TelegramPhotoCurveChannel.allCases) { channel in
                    Button(channel.title) { curveChannel = channel }
                        .buttonStyle(TelegramEditorCapsuleButtonStyle(isSelected: curveChannel == channel))
                        .tint(channel.color)
                }
                Spacer()
                Button("重置") { curves[curveChannel] = .neutral }
                    .font(.caption)
            }
            curveSlider("黑场", keyPath: \TelegramPhotoCurve.blacks)
            curveSlider("阴影", keyPath: \TelegramPhotoCurve.shadows)
            curveSlider("中间调", keyPath: \TelegramPhotoCurve.midtones)
            curveSlider("高光", keyPath: \TelegramPhotoCurve.highlights)
            curveSlider("白场", keyPath: \TelegramPhotoCurve.whites)
        }
    }

    private var cropPanel: some View {
        VStack(spacing: 13) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TelegramPhotoCropPreset.allCases) { preset in
                        Button(preset.title) { cropPreset = preset }
                            .buttonStyle(TelegramEditorCapsuleButtonStyle(isSelected: cropPreset == preset))
                    }
                }
            }
            editorSlider(title: "校正", value: $straightenDegrees, range: -45...45, suffix: "°")
            HStack(spacing: 12) {
                Button { quarterTurns = (quarterTurns + 3) % 4 } label: { Label("左转", systemImage: "rotate.left") }
                Button { quarterTurns = (quarterTurns + 1) % 4 } label: { Label("右转", systemImage: "rotate.right") }
                Button { isFlippedHorizontally.toggle() } label: { Label("镜像", systemImage: "arrow.left.and.right") }
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
    }

    private var blurPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(TelegramPhotoBlurMode.allCases) { mode in
                    Button(mode.title) { blur.mode = mode }
                        .buttonStyle(TelegramEditorCapsuleButtonStyle(isSelected: blur.mode == mode))
                }
            }
            editorSlider(title: "强度", value: $blur.intensity, range: 0...1)
            editorSlider(title: "范围", value: $blur.size, range: 0.08...0.65)
            editorSlider(title: "过渡", value: $blur.falloff, range: 0.03...0.4)
            if blur.mode == .linear {
                editorSlider(title: "角度", value: $blur.rotation, range: -.pi...(.pi), suffix: "")
            }
        }
    }

    private var drawingPanel: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TelegramPhotoDrawingTool.allCases) { tool in
                        Button(tool.title) { drawingTool = tool }
                            .buttonStyle(TelegramEditorCapsuleButtonStyle(isSelected: drawingTool == tool))
                    }
                }
            }
            colorPalette(selection: $drawingColor)
            HStack(spacing: 10) {
                Text("粗细").font(.caption).foregroundStyle(.secondary)
                Slider(value: $drawingWidth, in: 2...28).tint(drawingColor.color)
                Button { issueDrawingAction(undo: true) } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(drawing.strokes.isEmpty)
                Button { issueDrawingAction(undo: false) } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!canRedoDrawing)
                Button(role: .destructive) { drawing = PKDrawing() } label: { Image(systemName: "trash") }
            }
        }
    }

    private var textPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("输入文字", text: $draftText)
                    .padding(.horizontal, 11)
                    .frame(height: 38)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                Button("添加", action: addTextOverlay)
                    .buttonStyle(.borderedProminent)
                    .tint(telegramBlue)
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack(spacing: 7) {
                ForEach(TelegramPhotoTextStyle.allCases) { style in
                    Button(style.title) { textStyle = style; updateSelectedText { $0.style = style } }
                        .buttonStyle(TelegramEditorCapsuleButtonStyle(isSelected: textStyle == style))
                }
                Menu(textFont.title) {
                    ForEach(TelegramPhotoTextFont.allCases) { font in
                        Button(font.title) { textFont = font; updateSelectedText { $0.font = font } }
                    }
                }
                .buttonStyle(.bordered)
            }
            colorPalette(selection: $textColor, onSelect: { color in updateSelectedText { $0.color = color } })
            overlayTransformControls(isText: true)
        }
    }

    private var stickerPanel: some View {
        VStack(spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(stickers, id: \.self) { sticker in
                        Button(sticker) { addSticker(sticker) }
                            .font(.system(size: 32))
                    }
                }
            }
            Text("添加后可在照片上拖动；使用下方按钮缩放、旋转或删除")
                .font(.caption)
                .foregroundStyle(.secondary)
            overlayTransformControls(isText: false)
        }
    }

    private func overlayTransformControls(isText: Bool) -> some View {
        HStack(spacing: 18) {
            Button { transformSelected(isText: isText, scale: 0.86) } label: { Label("缩小", systemImage: "minus.magnifyingglass") }
            Button { transformSelected(isText: isText, scale: 1.16) } label: { Label("放大", systemImage: "plus.magnifyingglass") }
            Button { transformSelected(isText: isText, rotation: -.pi / 12) } label: { Image(systemName: "rotate.left") }
            Button { transformSelected(isText: isText, rotation: .pi / 12) } label: { Image(systemName: "rotate.right") }
            Button(role: .destructive) { deleteSelected(isText: isText) } label: { Image(systemName: "trash") }
        }
        .font(.caption)
        .buttonStyle(.bordered)
        .tint(.white)
    }

    private var toolBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(TelegramPhotoEditorTool.allCases) { tool in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { selectedTool = tool }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tool.systemImage).font(.system(size: 17, weight: .semibold))
                            Text(tool.title).font(.caption2)
                        }
                        .foregroundStyle(selectedTool == tool ? telegramBlue : .white.opacity(0.72))
                        .frame(width: 62, height: 58)
                    }
                }
            }
        }
        .background(Color(white: 0.035))
    }

    private var telegramBlue: Color { Color(red: 0.21, green: 0.65, blue: 0.96) }

    private var previewKey: String {
        "\(adjustments)|\(curves)|\(cropPreset.rawValue)|\(quarterTurns)|\(straightenDegrees)|\(isFlippedHorizontally)|\(blur)"
    }

    private var previewSize: CGSize {
        previewImage?.size ?? sourceImage.size
    }

    private func fittedCanvasSize(in available: CGSize) -> CGSize {
        let ratio = previewSize.width / max(previewSize.height, 1)
        if available.width / max(available.height, 1) > ratio {
            return CGSize(width: available.height * ratio, height: available.height)
        }
        return CGSize(width: available.width, height: available.width / ratio)
    }

    private func editorSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String = "") -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
            Slider(value: value, in: range).tint(telegramBlue)
            Text(value.wrappedValue.formatted(.number.precision(.fractionLength(suffix == "°" ? 0 : 2))) + suffix)
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
        }
    }

    private func curveSlider(_ title: String, keyPath: WritableKeyPath<TelegramPhotoCurve, Double>) -> some View {
        let binding = Binding<Double>(
            get: { curves[curveChannel][keyPath: keyPath] },
            set: { curves[curveChannel][keyPath: keyPath] = $0 }
        )
        return HStack(spacing: 7) {
            Text(title).font(.caption2).foregroundStyle(.secondary).frame(width: 42, alignment: .leading)
            Slider(value: binding, in: 0...1).tint(curveChannel.color)
            Text(binding.wrappedValue.formatted(.number.precision(.fractionLength(2))))
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 30)
        }
    }

    private func colorPalette(selection: Binding<TelegramPhotoEditorColor>, onSelect: ((TelegramPhotoEditorColor) -> Void)? = nil) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(TelegramPhotoEditorColor.palette) { color in
                    Button {
                        selection.wrappedValue = color
                        onSelect?(color)
                    } label: {
                        Circle().fill(color.color).frame(width: 24, height: 24)
                            .overlay(Circle().stroke(.white, lineWidth: selection.wrappedValue == color ? 3 : 0)).padding(2)
                    }
                }
            }
        }
    }

    private var adjustmentBinding: Binding<Double> {
        Binding(
            get: {
                switch selectedAdjustment {
                case .enhance: adjustments.enhance
                case .brightness: adjustments.brightness
                case .contrast: adjustments.contrast
                case .saturation: adjustments.saturation
                case .warmth: adjustments.warmth
                case .fade: adjustments.fade
                case .highlights: adjustments.highlights
                case .shadows: adjustments.shadows
                case .vignette: adjustments.vignette
                case .grain: adjustments.grain
                case .sharpen: adjustments.sharpen
                }
            },
            set: {
                switch selectedAdjustment {
                case .enhance: adjustments.enhance = $0
                case .brightness: adjustments.brightness = $0
                case .contrast: adjustments.contrast = $0
                case .saturation: adjustments.saturation = $0
                case .warmth: adjustments.warmth = $0
                case .fade: adjustments.fade = $0
                case .highlights: adjustments.highlights = $0
                case .shadows: adjustments.shadows = $0
                case .vignette: adjustments.vignette = $0
                case .grain: adjustments.grain = $0
                case .sharpen: adjustments.sharpen = $0
                }
            }
        )
    }

    private func addTextOverlay() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let overlay = TelegramPhotoTextOverlay(text: text, color: textColor, style: textStyle, font: textFont)
        textOverlays.append(overlay)
        selectedTextID = overlay.id
        selectedStickerID = nil
        draftText = ""
    }

    private func addSticker(_ content: String) {
        let overlay = TelegramPhotoStickerOverlay(content: content)
        stickerOverlays.append(overlay)
        selectedStickerID = overlay.id
        selectedTextID = nil
    }

    private func updateSelectedText(_ update: (inout TelegramPhotoTextOverlay) -> Void) {
        guard let id = selectedTextID, let index = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        update(&textOverlays[index])
    }

    private func transformSelected(isText: Bool, scale: CGFloat = 1, rotation: Double = 0) {
        if isText, let id = selectedTextID, let index = textOverlays.firstIndex(where: { $0.id == id }) {
            textOverlays[index].scale = min(max(textOverlays[index].scale * scale, 0.4), 4)
            textOverlays[index].rotation += rotation
        } else if !isText, let id = selectedStickerID, let index = stickerOverlays.firstIndex(where: { $0.id == id }) {
            stickerOverlays[index].scale = min(max(stickerOverlays[index].scale * scale, 0.35), 4)
            stickerOverlays[index].rotation += rotation
        }
    }

    private func deleteSelected(isText: Bool) {
        if isText, let id = selectedTextID {
            textOverlays.removeAll { $0.id == id }
            selectedTextID = nil
        } else if let id = selectedStickerID {
            stickerOverlays.removeAll { $0.id == id }
            selectedStickerID = nil
        }
    }

    private func issueDrawingAction(undo: Bool) {
        drawingActionCounter += 1
        drawingAction = undo ? .undo(drawingActionCounter) : .redo(drawingActionCounter)
    }

    private func resetEditor() {
        adjustments = .neutral
        curves = .neutral
        cropPreset = .original
        quarterTurns = 0
        straightenDegrees = 0
        isFlippedHorizontally = false
        blur = .off
        drawing = PKDrawing()
        textOverlays = []
        stickerOverlays = []
        selectedTextID = nil
        selectedStickerID = nil
    }

    private func completeEditing() {
        guard !isRendering else { return }
        isRendering = true
        defer { isRendering = false }
        guard let result = TelegramPhotoEditorRenderer.render(
            sourceImage: sourceImage,
            adjustments: adjustments,
            curves: curves,
            cropPreset: cropPreset,
            quarterTurns: quarterTurns,
            straightenDegrees: straightenDegrees,
            isFlippedHorizontally: isFlippedHorizontally,
            blur: blur,
            drawing: drawing,
            drawingCanvasSize: drawingCanvasSize,
            textOverlays: textOverlays,
            stickerOverlays: stickerOverlays
        ) else { return }
        onComplete(result)
    }

    private func swiftUIFont(_ font: TelegramPhotoTextFont, size: CGFloat) -> Font {
        switch font {
        case .system: .system(size: size, weight: .bold)
        case .rounded: .system(size: size, weight: .bold, design: .rounded)
        case .serif: .system(size: size, weight: .bold, design: .serif)
        case .monospaced: .system(size: size, weight: .bold, design: .monospaced)
        }
    }
}

private enum AdjustmentKey: String, CaseIterable, Identifiable {
    case enhance, brightness, contrast, saturation, warmth, fade, highlights, shadows, vignette, grain, sharpen
    var id: Self { self }
    var title: String {
        switch self {
        case .enhance: "增强"
        case .brightness: "亮度"
        case .contrast: "对比度"
        case .saturation: "饱和度"
        case .warmth: "色温"
        case .fade: "褪色"
        case .highlights: "高光"
        case .shadows: "阴影"
        case .vignette: "暗角"
        case .grain: "颗粒"
        case .sharpen: "锐化"
        }
    }
    var range: ClosedRange<Double> {
        switch self {
        case .brightness, .warmth, .highlights, .shadows: -1...1
        case .contrast: 0.5...1.5
        case .saturation: 0...2
        default: 0...1
        }
    }
    var neutralValue: Double {
        switch self {
        case .contrast, .saturation: 1
        default: 0
        }
    }
}

private struct TelegramEditorCapsuleButtonStyle: ButtonStyle {
    let isSelected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Color.black : Color.white)
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(isSelected ? Color.white : Color.white.opacity(configuration.isPressed ? 0.18 : 0.1))
            .clipShape(Capsule())
    }
}
