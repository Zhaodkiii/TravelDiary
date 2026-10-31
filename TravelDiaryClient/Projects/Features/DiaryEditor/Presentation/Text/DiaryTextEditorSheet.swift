import SwiftUI
import UIKit

enum DiaryTextEditorTab: String, CaseIterable {
    case content = "键盘", templates = "样式", style = "效果", font = "字体"
    // Existing toolbar entry points map into the matching style section.
    case size = "字号", color = "颜色", layout = "排版", background = "底纸"
    static let mainTabs: [Self] = [.content, .font, .size, .color, .layout, .templates, .background, .style]
    var symbol: String {
        switch self {
        case .content: "keyboard"
        case .templates: "square.grid.2x2"
        case .font: "textformat.abc"
        case .size: "textformat.size"
        case .color: "paintpalette"
        case .layout: "text.alignleft"
        case .background: "square.on.square"
        default: "slider.horizontal.3"
        }
    }
}

/// Created by the presenting editor once per user action, outside any secondary picker lifecycle.
struct DiaryTextEditorPresentation: Identifiable {
    let id = UUID()
    let draft: DiaryTextDraft
    let initialTab: DiaryTextEditorTab
    init(session: DiaryEditorSession, layer: DiaryLayer?, initialTab: DiaryTextEditorTab = .content) {
        draft = DiaryTextDraft(session: session, layer: layer)
        self.initialTab = initialTab
    }
}

struct DiaryTextEditorSheet: View {
    @ObservedObject var session: DiaryEditorSession
    @StateObject private var draft: DiaryTextDraft
    @Environment(\.dismiss) private var dismiss
    @State private var keyboard = false
    @State private var wholePage = true
    @State private var initialCanvasFocus = true
    @State private var expandedInput = false
    @State private var inputHeight: CGFloat = 28
    @State private var tab: DiaryTextEditorTab
    @State private var styleSection: TextStyleSection
    @State private var category = ""
    @State private var search = ""
    @State private var showFontGallery = false
    private enum TextColorTarget: String, Identifiable {
        case text = "文字颜色", background = "背景颜色", stroke = "描边颜色", shadow = "阴影颜色"
        var id: Self { self }
    }
    @State private var ready = false
    @State private var error: String?
    @State private var saving = false
    @State private var committed = false
    @State private var savedStyles: [DiarySavedTextStyle] = []
    @State private var namingStyle = false
    @State private var styleName = ""
    @State private var styleError: String?
    private let stylesKey = "diary.personalTextStyles.v1"

    private enum TextStyleSection: String, CaseIterable {
        case text = "文本", outline = "描边", shadow = "阴影", layout = "排版"
    }

    init(session: DiaryEditorSession, layer: DiaryLayer?, initialTab: DiaryTextEditorTab = .content) {
        self.init(session: session, draft: DiaryTextDraft(session: session, layer: layer), initialTab: initialTab)
    }

    init(session: DiaryEditorSession, draft: DiaryTextDraft, initialTab: DiaryTextEditorTab = .content) {
        self.session = session
        _draft = StateObject(wrappedValue: draft)
        _tab = State(initialValue: initialTab)
        _styleSection = State(initialValue: initialTab == .layout ? .layout : .text)
    }

    var body: some View {
        VStack(spacing: 0) {
            canvasPreview
                .overlay(alignment: .top) { editorHeader }
            VStack(spacing: 6) {
                if tab == .content { inputBar }
                toolStrip
                if tab != .content {
                    Group {
                        switch tab {
                        case .templates: templates
                        case .font: fonts
                        case .background: paperControls
                        case .color:
                            ScrollView { colorButton(.text).padding(.horizontal, 4).padding(.bottom, 12) }
                        default: styles
                        }
                    }.frame(height: 250)
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
            .disabled(saving || committed)
        }
        .background(DiaryLibraryStyle.background)
        .foregroundStyle(DiaryLibraryStyle.ink).tint(DiaryLibraryStyle.accent)
        .interactiveDismissDisabled()
        .onChange(of: tab) { _, value in
            if value == .color { styleSection = .text }
            if value == .layout { styleSection = .layout }
        }
        .onAppear {
            if let data = UserDefaults.standard.data(forKey: stylesKey) {
                savedStyles = (try? JSONDecoder().decode([DiarySavedTextStyle].self, from: data)) ?? []
            }
        }
        .alert("保存为我的样式", isPresented: $namingStyle) {
            TextField("样式名称", text: $styleName)
            Button("取消", role: .cancel) { }
            Button("保存") { saveStyle() }
        } message: { Text("保存字体、颜色、排版和背景，供其他文字使用。") }
        .task {
            guard !ready else { return }
            DiaryFontCatalog.shared.prepare()
            ready = true
            let initialFocus = draft.consumeInitialInputFocus()
            keyboard = tab == .content && initialFocus
        }
        .task(id: draft.layer.font ?? .system) {
            let reference = draft.layer.font ?? .system
            await DiaryFontCatalog.shared.prewarm([reference], documentID: session.document.id)
            guard !Task.isCancelled, reference == (draft.layer.font ?? .system) else { return }
            draft.refresh()
        }
        .sheet(isPresented: $expandedInput, onDismiss: { keyboard = tab == .content }) {
            DiaryExpandedTextInput(text: Binding(get: { draft.layer.text }, set: { draft.setText($0) }),
                                   onClose: { expandedInput = false })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showFontGallery) {
            NavigationStack {
                FontGalleryScreen(documentID: session.document.id) { reference in
                    guard showFontGallery, !committed else { return }
                    draft.selectFont(reference); showFontGallery = false
                }.toolbar { ToolbarItem(placement: .topBarLeading) { Button("返回编辑器") { showFontGallery = false } } }
            }
        }
        .alert("文字编辑", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            if committed {
                Button("重试保存") { save() }
                Button("保留并关闭") { dismiss() }
            } else { Button("确定") { error = nil } }
        } message: { Text(error ?? "") }
    }

    private var editorHeader: some View {
        HStack {
            Button("取消") { finishTextInput(); dismiss() }
                .frame(minWidth: 44, minHeight: 44)
                .disabled(saving || committed)
            Spacer()
            Button { finishTextInput(); save() } label: {
                HStack(spacing: 6) {
                    if saving { ProgressView().tint(.white) }
                    Text("完成").fontWeight(.semibold)
                }
                .padding(.horizontal, 18).frame(height: 44)
                .foregroundStyle(.white)
                .background(DiaryLibraryStyle.accent, in: Capsule())
            }
            .disabled(saving || committed || draft.layer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.busy)
            .accessibilityIdentifier("diary.text.done")
        }.padding(.horizontal, 16).padding(.vertical, 4)
    }

    private var previewHeader: some View {
        HStack {
            Text("双指缩放 · 单指调整文字").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { initialCanvasFocus = false; wholePage.toggle() } label: {
                Label("恢复整页", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption).frame(minHeight: 44)
            }.accessibilityIdentifier("diary.text.previewMode")
        }.padding(.horizontal, 20)
    }

    private var canvasPreview: some View {
        GeometryReader { geometry in
            let bounds = draft.preview.canvasBounds
            let margin = DiaryCanvasSurface.toolControlMargin
            let scale = max(0.01, (geometry.size.width - 32) / bounds.width)
            let size = CGSize(width: bounds.width * scale + margin * 2,
                              height: bounds.height * scale + margin * 2)
            let textBounds = DiaryPageRenderer.textBounds(draft.layer)
            let corners = [CGPoint(x: textBounds.minX, y: textBounds.minY), CGPoint(x: textBounds.maxX, y: textBounds.minY),
                           CGPoint(x: textBounds.maxX, y: textBounds.maxY), CGPoint(x: textBounds.minX, y: textBounds.maxY)]
                .map { draft.canvasLayer.transform.projection.point($0) }
            let left = corners.map(\.x).min() ?? 0
            let top = corners.map(\.y).min() ?? 0
            let focus = CGRect(x: (left - bounds.minX) * scale + margin, y: (top - bounds.minY) * scale + margin,
                               width: ((corners.map(\.x).max() ?? left) - left) * scale,
                               height: ((corners.map(\.y).max() ?? top) - top) * scale)
            let fullPageScale = min(1, max(0.01, geometry.size.height / size.height))
            DiaryZoomableCanvas(contentSize: size, sessionID: draft.preview.id, inkMode: false,
                                minimumScale: fullPageScale, refreshContent: true,
                                initialFocusRect: initialCanvasFocus ? focus : CGRect(origin: .zero, size: size)) {
                DiaryCanvasView(session: draft.preview, compactViewport: true, showsSelection: true,
                                editingTextLayer: draft.canvasLayer, lockedTextID: draft.layer.id, onTextAdjustment: { adjusted in
                    draft.adjustCanvasLayer(adjusted)
                })
                .frame(width: size.width, height: size.height)
            }.id(wholePage)
                .overlay(alignment: .bottomTrailing) {
                    Button { initialCanvasFocus = false; wholePage.toggle() } label: {
                        Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44)
                    }.accessibilityLabel("恢复整页")
                }
        }.clipped().accessibilityLabel("文字编辑画布，双指缩放与移动，单指调整当前文字")
    }

    private var toolStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DiaryTextEditorTab.mainTabs, id: \.self) { value in
                    Button {
                        finishTextInput()
                        tab = value
                        if value == .content { keyboard = true }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: value.symbol).font(.system(size: 19))
                            Text(value == .content ? "输入" : value.rawValue).font(.caption)
                        }.frame(width: 56, height: 46)
                            .foregroundStyle(tab == value ? DiaryLibraryStyle.accent : DiaryLibraryStyle.secondary)
                            .background(tab == value ? DiaryLibraryStyle.accent.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(tab == value ? [.isSelected] : [])
                }
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 4) {
            DiaryTextInput(text: Binding(get: { draft.layer.text }, set: { draft.setText($0) }), isFocused: $keyboard,
                           maximumHeight: 120, onHeightChange: { inputHeight = $0 })
                .frame(height: inputHeight)
                .overlay(alignment: .topLeading) {
                    if draft.layer.text.isEmpty {
                        Text("写点什么…").foregroundStyle(.secondary).allowsHitTesting(false)
                    }
                }
                .simultaneousGesture(TapGesture().onEnded { keyboard = true })
                .accessibilityAction { keyboard = true }
                .accessibilityIdentifier("diary.text.input")
                .padding(.horizontal, 14).padding(.top, 12)
            HStack(spacing: 8) {
                Button { finishTextInput() } label: {
                    Image(systemName: "keyboard.chevron.compact.down").frame(width: 44, height: 44)
                }.accessibilityLabel("收起键盘")
                Spacer()
                if !draft.layer.text.isEmpty {
                    Text("\(draft.layer.text.count) 字").font(.caption).foregroundStyle(.secondary)
                }
                Button { finishTextInput(); expandedInput = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
                }.accessibilityLabel("展开长文编辑")
            }.padding(.horizontal, 4)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    private var templates: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("文字样式").font(.headline)
                    Spacer()
                    Button("保存我的样式") { finishTextInput(); styleName = "我的标题 \(savedStyles.count + 1)"; namingStyle = true }.font(.caption)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(DiaryTextTemplate.allCases) { template in
                        Button { draft.apply(template) } label: {
                            VStack(spacing: 6) {
                                Image(uiImage: DiaryPageRenderer.textPreview(templatePreview(template)))
                                    .resizable().scaledToFit().frame(height: 58).frame(maxWidth: .infinity)
                                Text(template.title).font(.caption)
                            }.padding(8).background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
                                    appearance.titleLayout == nil && appearance.template == template ? DiaryLibraryStyle.accent : .clear, lineWidth: 2))
                        }.buttonStyle(.plain)
                    }
                }
                Text("标题排版").font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                    ForEach(DiaryTitleLayout.allCases) { layout in
                        Button { draft.applyTitle(layout) } label: {
                            VStack(spacing: 6) {
                                Image(uiImage: DiaryPageRenderer.textPreview(titlePreview(layout)))
                                    .resizable().scaledToFit().frame(height: 58).frame(maxWidth: .infinity)
                                Text(layout.title).font(.caption)
                            }.padding(10).background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(appearance.titleLayout == layout ? DiaryLibraryStyle.accent : .clear, lineWidth: 2))
                        }.buttonStyle(.plain)
                    }
                }
                Text("保留输入内容与手动换行，自动匹配字号。之后可继续微调。").font(.caption).foregroundStyle(.secondary)
                if let styleError { Text(styleError).font(.caption).foregroundStyle(.red) }
                if !savedStyles.isEmpty {
                    Text("我的样式").font(.headline)
                    ForEach(savedStyles) { style in
                        HStack {
                            Button { draft.applySaved(style) } label: { Label(style.name, systemImage: "textformat").frame(maxWidth: .infinity, alignment: .leading) }
                            Button(role: .destructive) {
                                let next = savedStyles.filter { $0.id != style.id }
                                persistStyles(next)
                            } label: { Image(systemName: "trash").frame(width: 44, height: 44) }.accessibilityLabel("删除样式" + style.name)
                        }.padding(.horizontal, 10).background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }.padding(.vertical, 4)
        }
    }

    private func templatePreview(_ template: DiaryTextTemplate) -> DiaryLayer {
        var layer = appearance.titleLayout == nil && appearance.template == template ? draft.layer : draft.templateLayer(template)
        if layer.text.isEmpty { layer.text = "记录美好" }
        return layer
    }

    private func titlePreview(_ layout: DiaryTitleLayout) -> DiaryLayer {
        var layer = appearance.titleLayout == layout ? draft.layer : draft.titleLayer(layout)
        if layer.text.isEmpty { layer.text = "把日子慢慢收藏" }
        return layer
    }

    private func saveStyle() {
        let name = styleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { styleError = "请输入样式名称。"; return }
        guard savedStyles.count < 30 else { styleError = "最多保存 30 个样式，请先删除不再使用的样式。"; return }
        let layer = draft.layer
        let style = DiarySavedTextStyle(name: String(name.prefix(40)), appearance: appearance, font: layer.font,
            color: layer.textColor, alignment: layer.textAlignment, lineHeight: layer.textLineHeight,
            letterSpacing: layer.textLetterSpacing, fontSize: layer.fontSize, width: layer.size.width)
        persistStyles(savedStyles + [style])
    }

    private func persistStyles(_ styles: [DiarySavedTextStyle]) {
        do {
            let data = try JSONEncoder().encode(styles)
            UserDefaults.standard.set(data, forKey: stylesKey)
            savedStyles = styles; styleError = nil
        } catch { styleError = "样式保存失败，请重试。" }
    }

    private var paper: DiaryTextPaper { appearance.paper ?? DiaryTextPaper() }
    private func paperBinding<T>(_ key: WritableKeyPath<DiaryTextPaper, T>) -> Binding<T> {
        Binding(get: { paper[keyPath: key] }, set: {
            var next = appearance; var value = paper; value[keyPath: key] = $0
            next.paper = value; draft.layer.textAppearance = next
        })
    }
    private var paperControls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("背景类型", selection: Binding<DiaryTextPaper.Kind?>(
                    get: { appearance.paper?.kind }, set: { draft.selectPaper($0) })) {
                    Text("模板原样").tag(Optional<DiaryTextPaper.Kind>.none)
                    ForEach(DiaryTextPaper.Kind.allCases) { Text($0.title).tag(Optional($0)) }
                }.pickerStyle(.segmented)
                if appearance.paper == nil && appearance.template != .plain {
                    HStack {
                        Text("当前装饰：" + appearance.template.title).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("移除背景") { paperBinding(\.kind).wrappedValue = .none }
                    }
                }
                if appearance.paper?.kind != DiaryTextPaper.Kind.none {
                    colorButton(.background)
                }
                if appearance.paper != nil && paper.kind != .none {
                    if paper.kind == .torn {
                        HStack { Text("手撕程度"); Slider(value: paperBinding(\.roughness), in: 0...1) }
                        Button { paperBinding(\.seed).wrappedValue = Int.random(in: 1...999999) } label: { Label("换一个形状", systemImage: "shuffle") }
                    }
                    HStack { Text("左右留白"); Slider(value: paperBinding(\.horizontalPadding), in: 0.1...2) }
                    HStack { Text("上下留白"); Slider(value: paperBinding(\.verticalPadding), in: 0.1...2) }
                    HStack { Text("纸张阴影"); Slider(value: paperBinding(\.shadow), in: 0...1) }
                    if paper.kind == .note { HStack { Text("圆角"); Slider(value: paperBinding(\.cornerRadius), in: 0...1) } }
                }

            }.font(.subheadline).padding(.horizontal, 4).padding(.bottom, 12)
        }
    }

    private var appearance: DiaryTextAppearance { draft.layer.textAppearance ?? DiaryTextAppearance() }
    private func appearanceBinding<T>(_ key: WritableKeyPath<DiaryTextAppearance, T>) -> Binding<T> {
        Binding(get: { appearance[keyPath: key] }, set: {
            var next = appearance; next[keyPath: key] = $0; draft.layer.textAppearance = next
        })
    }
    private var styles: some View {
        VStack(spacing: 10) {
            if tab == .style {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(TextStyleSection.allCases, id: \.self) { section in
                        Button(section.rawValue) { styleSection = section }
                            .foregroundStyle(styleSection == section ? DiaryLibraryStyle.accent : DiaryLibraryStyle.secondary)
                            .frame(minHeight: 36)
                    }
                }
            }
            }
            ScrollView {
                VStack(spacing: 16) {
                    switch (tab == .color || tab == .size) ? .text : (tab == .layout ? .layout : styleSection) {
                    case .text:
                        colorButton(.text)
                        HStack { Text("字号 \(Int(draft.layer.fontSize))"); Slider(value: $draft.layer.fontSize, in: 12...300, step: 1) }
                        HStack { Text("透明度"); Slider(value: appearanceBinding(\.opacity), in: 0...1) }
                        HStack {
                            formatButton("粗体", symbol: "bold", key: \.bold)
                            formatButton("斜体", symbol: "italic", key: \.italic)
                            formatButton("下划线", symbol: "underline", key: \.underline)
                            formatButton("删除线", symbol: "strikethrough", key: \.strikethrough)
                        }
                    case .outline:
                        colorButton(.stroke)
                        HStack { Text("粗细"); Slider(value: appearanceBinding(\.strokeWidth), in: 0...12, step: 0.5) }
                        Button("移除描边") { appearanceBinding(\.strokeWidth).wrappedValue = 0 }
                    case .shadow:
                        colorButton(.shadow)
                        HStack { Text("柔和程度"); Slider(value: appearanceBinding(\.shadowRadius), in: 0...30, step: 1) }
                        Button("移除阴影") { appearanceBinding(\.shadowRadius).wrappedValue = 0 }
                    case .layout:
                        Picker("对齐", selection: Binding(get: { draft.layer.textAlignment ?? .center }, set: { draft.layer.textAlignment = $0 })) {
                            ForEach(DiaryTextAlignment.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented)
                        HStack { Text("行距 \(String(format: "%.1f", draft.layer.textLineHeight ?? 1.2))"); Slider(value: Binding(get: { draft.layer.textLineHeight ?? 1.2 }, set: { draft.layer.textLineHeight = $0 }), in: 0.8...3, step: 0.1) }
                        HStack { Text("字距 \(String(format: "%.1f", draft.layer.textLetterSpacing ?? 0))"); Slider(value: Binding(get: { draft.layer.textLetterSpacing ?? 0 }, set: { draft.layer.textLetterSpacing = $0 }), in: -2...20, step: 0.5) }
                        HStack { Text("宽度 \(Int(draft.layer.size.width))"); Slider(value: $draft.layer.size.width, in: 120...max(121, session.content.referenceSize.width * 0.9)) }
                        Toggle("逐字竖排", isOn: appearanceBinding(\.vertical))
                    }
                }.font(.subheadline).padding(.horizontal, 4).padding(.bottom, 12)
            }
        }
    }

    private func formatButton(_ title: String, symbol: String, key: WritableKeyPath<DiaryTextAppearance, Bool>) -> some View {
        Button { appearanceBinding(key).wrappedValue.toggle() } label: {
            VStack(spacing: 5) { Image(systemName: symbol); Text(title).font(.caption2) }
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(appearance[keyPath: key] ? DiaryLibraryStyle.accent.opacity(0.15) : DiaryLibraryStyle.surface,
                            in: RoundedRectangle(cornerRadius: 8))
        }.accessibilityLabel(title).accessibilityAddTraits(appearance[keyPath: key] ? [.isSelected] : [])
    }

    private var fonts: some View {
        VStack(spacing: 8) {
            Button("字体集市 · 我的字体") { finishTextInput(); showFontGallery = true }
            Picker("字体分类", selection: $category) {
                Text("全部").tag("")
                Text("手写").tag("handwriting")
                Text("书法").tag("calligraphy")
                Text("标题").tag("display")
            }.pickerStyle(.segmented)
            TextField("搜索字体", text: $search).textFieldStyle(.roundedBorder)
            if ready {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(DiaryFontCatalog.shared.entries.filter {
                            (category.isEmpty || $0.category == category) && (search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search))
                        }) { entry in
                            Button { draft.selectFont(entry.reference) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.displayName).font(.caption)
                                        Text(draft.layer.text.isEmpty ? "山川与日常 Aa 123" : draft.layer.text)
                                            .font(Font(DiaryFontCatalog.shared.font(entry.reference, size: 22))).lineLimit(1)
                                    }
                                    Spacer()
                                    if (draft.layer.font ?? .system) == entry.reference { Image(systemName: "checkmark.circle.fill") }
                                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).disabled(!DiaryFontCatalog.shared.available(entry.reference))
                        }
                    }
                    if let warning = DiaryFontCatalog.shared.warning(draft.layer.font, text: draft.layer.text) {
                        Text(warning).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else { ProgressView("正在准备字体…").frame(maxHeight: .infinity) }
        }
    }

    private func pickerColor(_ target: TextColorTarget) -> Binding<DiaryColor> {
        switch target {
        case .text:
            Binding(get: { draft.layer.textColor ?? DiaryColor(red: 0, green: 0, blue: 0) }, set: { draft.setTextColor($0) })
        case .background:
            Binding(get: { appearance.paper?.color ?? appearance.background ?? appearance.template.background }, set: { draft.setBackgroundColor($0) })
        case .stroke: appearanceBinding(\.strokeColor)
        case .shadow: appearanceBinding(\.shadowColor)
        }
    }

    private func colorButton(_ target: TextColorTarget) -> some View {
        DiaryTextColorPanel(title: target.rawValue, color: pickerColor(target),
            supportsAlpha: target == .background || target == .shadow,
            onBegin: finishTextInput)
    }

    private func finishTextInput() {
        // End marked-text composition before a tool or another input takes focus.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        keyboard = false
    }

    private func save() {
        guard !saving else { return }
        if !committed {
            if let font = draft.layer.font { CloudFontRepository.shared.recordUse(font) }
            guard session.commitTextDraft(draft.layer, targetID: draft.targetID) else {
                error = session.errorMessage ?? "暂时无法保存文字，请重试。"; return
            }
            committed = true
        }
        saving = true
        Task {
            do { try await session.save(); dismiss() }
            catch { self.error = "文字已保留在编辑器中，写入失败：" + error.localizedDescription }
            saving = false
        }
    }
}

/// Change this one flag to compare both implementations using the same draft and toolbar.
private enum DiaryTextInputImplementation {
    case uiKit, nativeSwiftUI
    static let current: Self = .nativeSwiftUI // Switch to .nativeSwiftUI for the native multiline TextField.
}

private struct DiaryComparisonTextInput: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    @FocusState private var nativeFocused: Bool

    var body: some View {
        Group {
            switch DiaryTextInputImplementation.current {
            case .uiKit:
                DiaryTextInput(text: $text, isFocused: $isFocused,
                               placeholder: "写点什么…", maximumHeight: 72)
            case .nativeSwiftUI:
                TextField("写点什么…", text: $text, axis: .vertical)
                    .font(.body)
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .focused($nativeFocused)
                    .onAppear { nativeFocused = isFocused }
                    .onChange(of: isFocused) { _, value in
                        if nativeFocused != value { nativeFocused = value }
                    }
                    .onChange(of: nativeFocused) { _, value in
                        if isFocused != value { isFocused = value }
                    }
            }
        }
    }
}

/// Own the text-input lifecycle instead of replacing a SwiftUI TextField's entire layer binding.
/// Style changes never write back into an active IME composition.
struct DiaryTextInput: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String = ""
    var maximumHeight: CGFloat = 76
    var onHeightChange: ((CGFloat) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = DiaryFocusTextView()
        view.shouldRequestFocus = { [weak coordinator = context.coordinator] in coordinator?.parent.isFocused == true }
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = true
        view.accessibilityIdentifier = "diary.text.input"
        view.accessibilityLabel = "文字内容"
        view.text = text
        view.updatePlaceholder(placeholder)
        context.coordinator.synchronizedText = text
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.measure(view)
        (view as? DiaryFocusTextView)?.updatePlaceholder(placeholder)
        // Only intentional external edits (such as Clear) replace text. A redraw while typing does not.
        if text != context.coordinator.synchronizedText, view.markedTextRange == nil {
            view.text = text
            context.coordinator.synchronizedText = text
            (view as? DiaryFocusTextView)?.updatePlaceholder(placeholder)
        }
        if isFocused && !view.isFirstResponder && view.window != nil {
            view.becomeFirstResponder()
        } else if !isFocused && view.isFirstResponder {
            view.unmarkText()
            view.resignFirstResponder()
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 200
        let height = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        context.coordinator.publishHeight(min(maximumHeight, max(28, height)))
        return CGSize(width: width, height: min(maximumHeight, max(28, height)))
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: DiaryTextInput
        var synchronizedText = ""
        private var reportedHeight: CGFloat = 0
        func publishHeight(_ height: CGFloat) {
            guard abs(height - reportedHeight) > 0.5 else { return }
            reportedHeight = height
            DispatchQueue.main.async { [weak self] in
                guard let self, self.reportedHeight == height else { return }
                self.parent.onHeightChange?(height)
            }
        }
        func measure(_ view: UITextView) {
            guard view.bounds.width > 0 else { return }
            let height = view.sizeThatFits(CGSize(width: view.bounds.width, height: .greatestFiniteMagnitude)).height
            publishHeight(min(parent.maximumHeight, max(28, ceil(height))))
        }
        init(_ parent: DiaryTextInput) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            measure(textView)
            (textView as? DiaryFocusTextView)?.updatePlaceholder(parent.placeholder)
            synchronizedText = textView.text ?? ""
            if parent.text != synchronizedText { parent.text = synchronizedText }
        }
        func textViewShouldEndEditing(_ textView: UITextView) -> Bool {
            textView.unmarkText()
            textViewDidChange(textView)
            return true
        }
        func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
            // UIKit may try to restore its previous responder after a modal presentation.
            // Only an explicit input request is allowed to reopen the keyboard.
            parent.isFocused
        }
        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
        }
        func textViewDidEndEditing(_ textView: UITextView) {
            // Publish the final composed text before accepting a color/font edit.
            textViewDidChange(textView)
            if parent.isFocused { parent.isFocused = false }
        }
    }
}

private final class DiaryFocusTextView: UITextView {
    private let placeholderLabel = UILabel()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 0
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.isAccessibilityElement = false
        addSubview(placeholderLabel)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updatePlaceholder(_ value: String) {
        placeholderLabel.text = value
        placeholderLabel.font = font
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.isHidden = !text.isEmpty || value.isEmpty
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = textContainerInset
        let x = inset.left + textContainer.lineFragmentPadding
        let width = max(0, bounds.width - x - inset.right - textContainer.lineFragmentPadding)
        let size = placeholderLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        placeholderLabel.frame = CGRect(x: x, y: inset.top, width: width, height: size.height)
    }

    var shouldRequestFocus: (() -> Bool)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, self.shouldRequestFocus?() == true else { return }
            self.becomeFirstResponder()
        }
    }
}

private struct DiaryExpandedTextInput: View {
    @Binding var text: String
    let onClose: () -> Void
    @FocusState private var focused: Bool
    @State private var confirmClear = false
    var body: some View {
        VStack(spacing: 8) {
            TextEditor(text: $text)
                .font(.body).focused($focused)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("完整文字内容")
            HStack {
                Button { confirmClear = true } label: {
                    Image(systemName: "trash").frame(width: 44, height: 44)
                }.disabled(text.isEmpty).accessibilityLabel("清空文字")
                Spacer()
                Text("\(text.count) 字").font(.caption).foregroundStyle(.secondary)
                Button { focused = false; onClose() } label: {
                    Label("收起", systemImage: "chevron.down").frame(minHeight: 44)
                }
            }.padding(.horizontal, 12)
                .background(.thinMaterial, in: Capsule())
        }.padding(16).padding(.top, 12)
            .background(Color(uiColor: .systemGroupedBackground))
            .tint(DiaryLibraryStyle.accent)
            .task { focused = true }
            .confirmationDialog("清空这段文字？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清空文字", role: .destructive) { text = "" }
            }
    }
}
