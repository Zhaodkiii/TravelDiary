import SwiftUI
import UIKit

enum DiaryTextEditorTab: String, CaseIterable {
    case content = "键盘", templates = "模板", style = "样式", font = "字体"
    // Existing toolbar entry points map into the matching style section.
    case size = "字号", color = "颜色", layout = "排版"
    static let mainTabs: [Self] = [.content, .templates, .style, .font]
    var symbol: String {
        switch self {
        case .content: "keyboard"
        case .templates: "square.grid.2x2"
        case .font: "textformat"
        default: "slider.horizontal.3"
        }
    }
}

struct DiaryTextEditorSheet: View {
    @ObservedObject var session: DiaryEditorSession
    @StateObject private var draft: DiaryTextDraft
    @Environment(\.dismiss) private var dismiss
    @FocusState private var keyboard: Bool
    @State private var tab: DiaryTextEditorTab
    @State private var styleSection: TextStyleSection
    @State private var category = ""
    @State private var search = ""
    @State private var ready = false
    @State private var error: String?
    @State private var saving = false
    @State private var committed = false

    private enum TextStyleSection: String, CaseIterable {
        case text = "文本", outline = "描边", shadow = "阴影", background = "背景", layout = "排版"
    }

    init(session: DiaryEditorSession, layer: DiaryLayer?, initialTab: DiaryTextEditorTab = .content) {
        self.session = session
        _draft = StateObject(wrappedValue: DiaryTextDraft(session: session, layer: layer))
        _tab = State(initialValue: [.size, .color, .layout].contains(initialTab) ? .style : initialTab)
        _styleSection = State(initialValue: initialTab == .layout ? .layout : .text)
    }

    var body: some View {
        VStack(spacing: 0) {
            canvasPreview
            VStack(spacing: 10) {
                inputBar
                HStack(spacing: 0) {
                    ForEach(DiaryTextEditorTab.mainTabs, id: \.self) { value in
                        Button {
                            tab = value; keyboard = value == .content
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName: value.symbol).font(.system(size: 21))
                                Text(value.rawValue).font(.caption)
                            }.frame(maxWidth: .infinity).frame(height: 52)
                                .foregroundStyle(tab == value ? DiaryLibraryStyle.accent : DiaryLibraryStyle.secondary)
                        }.accessibilityAddTraits(tab == value ? [.isSelected] : [])
                    }
                }
                if tab != .content {
                    Group {
                        switch tab {
                        case .templates: templates
                        case .font: fonts
                        default: styles
                        }
                    }.frame(height: 270)
                } else if !keyboard {
                    Text("点击输入框继续输入，文字会实时显示在画布中")
                        .font(.caption).foregroundStyle(DiaryLibraryStyle.secondary).padding(.vertical, 16)
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
            .background(DiaryLibraryStyle.background)
            .disabled(saving || committed)
        }
        .background(DiaryLibraryStyle.background)
        .foregroundStyle(DiaryLibraryStyle.ink).tint(DiaryLibraryStyle.accent)
        .interactiveDismissDisabled()
        .onChange(of: keyboard) { _, focused in if focused { tab = .content } }
        .task {
            DiaryFontCatalog.shared.prepare()
            keyboard = tab == .content
            await DiaryFontCatalog.shared.prewarm(DiaryFontCatalog.shared.entries.map(\.reference))
            guard !Task.isCancelled else { return }
            ready = true; draft.refresh()
        }
        .alert("文字编辑", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            if committed {
                Button("重试保存") { save() }
                Button("保留并关闭") { dismiss() }
            } else { Button("确定") { error = nil } }
        } message: { Text(error ?? "") }
    }

    private var canvasPreview: some View {
        GeometryReader { geometry in
            let bounds = draft.preview.canvasBounds
            let margin = DiaryCanvasSurface.toolControlMargin
            let scale = max(0.01, min((geometry.size.width - 32) / (bounds.width + margin * 2),
                                     (geometry.size.height - 24) / (bounds.height + margin * 2)))
            DiaryCanvasView(session: draft.preview, compactViewport: true)
                .frame(width: bounds.width * scale + margin * 2, height: bounds.height * scale + margin * 2)
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.clipped().accessibilityLabel("文字实时画布预览")
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            Button { keyboard = false; dismiss() } label: {
                Image(systemName: "chevron.left").font(.title3).frame(width: 44, height: 44)
                    .background(DiaryLibraryStyle.surface, in: Circle())
            }.accessibilityLabel("取消文字修改")
            HStack {
                TextField("记录此刻的心情…", text: $draft.layer.text, axis: .vertical)
                    .lineLimit(1...3).focused($keyboard).font(.body)
                    .accessibilityIdentifier("diary.text.input")
                if !draft.layer.text.isEmpty {
                    Button { draft.layer.text = ""; keyboard = true } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.accessibilityLabel("清空文字")
                }
            }.padding(.horizontal, 14).padding(.vertical, 12)
                .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 22))
            Button { keyboard = false; save() } label: {
                Group {
                    if saving { ProgressView() }
                    else { Image(systemName: "checkmark").font(.title3) }
                }.frame(width: 44, height: 44).background(DiaryLibraryStyle.surface, in: Circle())
            }.disabled(draft.layer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.busy)
                .accessibilityLabel("完成文字编辑")
        }
    }

    private var templates: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                ForEach(DiaryTextTemplate.allCases) { template in
                    Button { draft.apply(template) } label: {
                        VStack(spacing: 5) {
                            Image(uiImage: DiaryPageRenderer.textTemplateThumbnail(template))
                                .resizable().scaledToFit().frame(height: 62).frame(maxWidth: .infinity)
                            Text(template.title).font(.caption)
                        }.padding(8)
                            .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12).strokeBorder(
                                    appearance.template == template ? DiaryLibraryStyle.accent : .clear, lineWidth: 2)
                            }
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(appearance.template == template ? [.isSelected] : [])
                }
            }.padding(.vertical, 4)
        }
    }

    private var appearance: DiaryTextAppearance { draft.layer.textAppearance ?? DiaryTextAppearance() }
    private func appearanceBinding<T>(_ key: WritableKeyPath<DiaryTextAppearance, T>) -> Binding<T> {
        Binding(get: { appearance[keyPath: key] }, set: {
            var next = appearance; next[keyPath: key] = $0; draft.layer.textAppearance = next
        })
    }
    private func colorBinding(_ key: WritableKeyPath<DiaryTextAppearance, DiaryColor>) -> Binding<Color> {
        Binding(get: { Color(uiColor: DiaryPageRenderer.color(appearance[keyPath: key])) }, set: {
            var next = appearance; next[keyPath: key] = DiaryColor($0); draft.layer.textAppearance = next
        })
    }

    private var styles: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(TextStyleSection.allCases, id: \.self) { section in
                        Button(section.rawValue) { styleSection = section }
                            .foregroundStyle(styleSection == section ? DiaryLibraryStyle.accent : DiaryLibraryStyle.secondary)
                            .frame(minHeight: 36)
                    }
                }
            }
            ScrollView {
                VStack(spacing: 16) {
                    switch styleSection {
                    case .text:
                        ColorPicker("文字颜色", selection: Binding(
                            get: { Color(uiColor: draft.layer.textColor.map(DiaryPageRenderer.color) ?? .darkText) },
                            set: { draft.layer.textColor = DiaryColor($0) }), supportsOpacity: false)
                        HStack { Text("字号 \(Int(draft.layer.fontSize))"); Slider(value: $draft.layer.fontSize, in: 12...300, step: 1) }
                        HStack { Text("透明度"); Slider(value: appearanceBinding(\.opacity), in: 0...1) }
                        HStack {
                            formatButton("粗体", symbol: "bold", key: \.bold)
                            formatButton("斜体", symbol: "italic", key: \.italic)
                            formatButton("下划线", symbol: "underline", key: \.underline)
                            formatButton("删除线", symbol: "strikethrough", key: \.strikethrough)
                        }
                    case .outline:
                        ColorPicker("描边颜色", selection: colorBinding(\.strokeColor), supportsOpacity: false)
                        HStack { Text("粗细"); Slider(value: appearanceBinding(\.strokeWidth), in: 0...12, step: 0.5) }
                        Button("移除描边") { appearanceBinding(\.strokeWidth).wrappedValue = 0 }
                    case .shadow:
                        ColorPicker("阴影颜色", selection: colorBinding(\.shadowColor))
                        HStack { Text("柔和程度"); Slider(value: appearanceBinding(\.shadowRadius), in: 0...30, step: 1) }
                        Button("移除阴影") { appearanceBinding(\.shadowRadius).wrappedValue = 0 }
                    case .background:
                        ColorPicker("文字底色", selection: Binding(
                            get: { Color(uiColor: DiaryPageRenderer.color(appearance.background ?? appearance.template.background)) },
                            set: { var next = appearance; next.background = DiaryColor($0); draft.layer.textAppearance = next }))
                        Button("移除装饰背景") {
                            var next = appearance; next.template = .plain; next.background = nil; draft.layer.textAppearance = next
                        }
                    case .layout:
                        Picker("对齐", selection: Binding(get: { draft.layer.textAlignment ?? .center }, set: { draft.layer.textAlignment = $0 })) {
                            ForEach(DiaryTextAlignment.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented)
                        HStack { Text("行距"); Slider(value: Binding(get: { draft.layer.textLineHeight ?? 1.2 }, set: { draft.layer.textLineHeight = $0 }), in: 0.8...3, step: 0.1) }
                        HStack { Text("字距"); Slider(value: Binding(get: { draft.layer.textLetterSpacing ?? 0 }, set: { draft.layer.textLetterSpacing = $0 }), in: -2...20, step: 0.5) }
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
                            Button { draft.layer.font = entry.reference } label: {
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

    private func save() {
        guard !saving else { return }
        if !committed {
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
