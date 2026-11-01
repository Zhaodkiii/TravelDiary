import SwiftUI

struct DiaryAIRequestSheet: View {
    @ObservedObject var controller: DiaryAIDraftController
    let action: DiaryAIAction
    var onStartWorkspace: ((DiaryAIRequest) -> Void)? = nil
    var onApplied: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var editingSettings = false
    @State private var showOriginal = false
    @State private var refinement = ""
    @State private var fullPreview = false
    @FocusState private var focused: Bool
    private var request: DiaryAIRequest { controller.form(action) }
    private var candidate: DiaryAISavedCandidate? { controller.candidates[action] }
    private var reviewing: Bool { candidate != nil && !editingSettings && controller.runningAction != action }
    private func field<T>(_ key: WritableKeyPath<DiaryAIRequest, T>) -> Binding<T> {
        Binding(get: { controller.form(action)[keyPath: key] }, set: { value in var draft = request; draft[keyPath: key] = value; controller.setForm(draft) })
    }
    private var previewData: Data? { showOriginal ? candidate?.original : candidate?.preview }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let error = controller.error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(.orange).padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    }
                    if controller.runningAction == action { progress }
                    else if reviewing { review }
                    else { settings }
                }.padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(action.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly) }
                ToolbarItem(placement: .confirmationAction) {
                    if candidate != nil {
                        Button(reviewing ? "设置" : "查看草稿") { editingSettings.toggle() }
                    } else {
                        Button("重置") { controller.setForm(.defaults(action)) }.disabled(controller.running)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .fullScreenCover(isPresented: $fullPreview) {
                NavigationStack {
                    ScrollView([.horizontal, .vertical]) {
                        if let data = previewData, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFit().frame(minWidth: 600, minHeight: 400).padding()
                        }
                    }.toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { fullPreview = false } } }
                        .navigationTitle(showOriginal ? "原版" : "草稿")
                }
            }
        }
        .tint(Color(red: 0.24, green: 0.39, blue: 0.34))
        // Long forms stay expanded; scrolling should not switch sheet heights.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .presentationBackgroundInteraction(.disabled)
        .onChange(of: controller.candidates[action]?.revision) { _, _ in editingSettings = false; showOriginal = false }
        .task { controller.restoreIfNeeded() }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("调整范围") {
                Picker("范围", selection: field(\.selectedOnly)) {
                    Text(controller.bridge.scopeTitle).tag(false)
                    Text("选中对象").tag(true)
                }.pickerStyle(.segmented).disabled(request.background?.backgroundOnly == true)
                if request.selectedOnly && !controller.bridge.selectionAvailable {
                    Text("请先关闭面板并选中目标对象，或选择当前画布。")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Text("\(controller.bridge.objectChoices.filter { $0.role == "photo" }.count) 张照片 · 保留锁定内容 · 逐批更新，保存后发布")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if action == .relayout || action == .custom { backgroundSettings }
            if request.background?.backgroundOnly != true { section("排版风格") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(["保持当前风格", "自动匹配"], id: \.self) { name in
                            Button { field(\.style).wrappedValue = name } label: {
                                Label(name, systemImage: request.style == name ? "checkmark.circle.fill" : "circle")
                                    .font(.subheadline).padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(request.style == name ? Color.accentColor.opacity(0.1) : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(DiaryAIStyleLibrary.styles) { style in
                            Button { field(\.style).wrappedValue = style.name } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Image(style.imageName).resizable().scaledToFill().frame(width: 156, height: 104).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(alignment: .topTrailing) {
                                            if request.style == style.name { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, Color.accentColor).padding(6) }
                                        }
                                    Text(style.name).font(.subheadline.weight(.semibold))
                                    Text(style.detail).font(.caption).foregroundStyle(.secondary)
                                }.padding(10).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(request.style == style.name ? Color.accentColor : .clear, lineWidth: 2))
                            }.buttonStyle(.plain).accessibilityAddTraits(request.style == style.name ? .isSelected : [])
                        }
                    }.padding(2)
                }
                Text("风格示例，仅参考构图与文字；不会生成或替换你的照片。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            }
            section("心情与场景 · 选填") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 68))], spacing: 8) {
                    ForEach(["开心", "放松", "治愈", "怀念", "感动", "平静", "兴奋"], id: \.self) { mood in
                        Button {
                            var values = request.moods
                            if values.contains(mood) { values.removeAll { $0 == mood } }
                            else if values.count < 2 { values.append(mood) }
                            field(\.moods).wrappedValue = values
                        } label: {
                            Text(mood).font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                                .background(request.moods.contains(mood) ? Color.accentColor.opacity(0.14) : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
                TextField("自己的心情（最多选两项，也可补充）", text: field(\.customMood)).textFieldStyle(.roundedBorder).focused($focused)
                Picker("场景", selection: field(\.scene)) {
                    ForEach(["不指定", "山野徒步", "城市漫游", "海边旅行", "露营野餐", "朋友相聚", "亲子时光", "日常记录"], id: \.self) { Text($0) }
                }
                TextField("其他场景", text: field(\.customScene)).textFieldStyle(.roundedBorder).focused($focused)
                TextField("地点，例如：云南·雨崩", text: field(\.location)).textFieldStyle(.roundedBorder).focused($focused)
                Toggle("把地点写进文字", isOn: field(\.writesLocation)).disabled(request.location.isEmpty)
            }
            if request.background?.backgroundOnly != true { options }
            section(action == .custom ? "你想怎么改" : "补充要求 · 选填") {
                TextField("例如：突出跳跃的照片，照片有大小变化，右页留下短句的位置。", text: field(\.instruction), axis: .vertical)
                    .lineLimit(3...7).focused($focused).padding(14)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            Text("提交后，本页必要的预览、照片缩略图和文字将发送给外部 AI 处理。原作品在你应用前保持不变。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func backgroundField<T>(_ key: WritableKeyPath<DiaryAIBackgroundOptions, T>) -> Binding<T> {
        Binding(get: { (request.background ?? DiaryAIBackgroundOptions())[keyPath: key] }, set: { value in
            var draft = request; var options = draft.background ?? DiaryAIBackgroundOptions()
            options[keyPath: key] = value; draft.background = options; controller.setForm(draft)
        })
    }
    private var backgroundSettings: some View {
        section("AI 背景") {
            Toggle(action == .relayout ? "排版后生成背景" : "生成背景 · 保留当前排版", isOn: Binding(get: { request.background != nil }, set: { enabled in
                var draft = request
                draft.background = enabled ? DiaryAIBackgroundOptions(backgroundOnly: action == .custom) : nil
                if enabled { draft.selectedOnly = false; draft.preservesBackground = true }
                controller.setForm(draft)
            }))
            if request.background != nil {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 135))], spacing: 10) {
                    ForEach(DiaryAIBackgroundStyle.all) { style in
                        Button { backgroundField(\.style).wrappedValue = style.id } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: style.symbol).font(.title2)
                                Text(style.name).font(.subheadline.weight(.medium))
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                .background(request.background?.style == style.id ? Color.accentColor.opacity(0.14) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                                .overlay(alignment: .topTrailing) { if request.background?.style == style.id { Image(systemName: "checkmark.circle.fill").padding(8) } }
                        }.buttonStyle(.plain).accessibilityAddTraits(request.background?.style == style.id ? .isSelected : [])
                    }
                }
                if let size = controller.bridge.canvasSize, let target = try? DiaryAIBackgroundImaging.exactSize(size) {
                    Text("画布 \(Int(size.width)) × \(Int(size.height)) · 背景 \(Int(target.width)) × \(Int(target.height)) · 比例锁定")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("背景强度", selection: backgroundField(\.strength)) {
                    Text("轻").tag("轻"); Text("中").tag("中"); Text("浓").tag("浓")
                }.pickerStyle(.segmented)
                Toggle("生成后保存到相册", isOn: backgroundField(\.saveToAlbum))
                Text("按当前画布比例生成纯背景，替换原背景，保留照片、贴纸和文字。Seedream 2K · 保留服务水印。生成与视觉检查会产生模型请求；撤销不删除已保存的相册图片。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private var options: some View {
        section("本次允许的调整") {
            if action == .beautify {
                Picker("调整强度", selection: field(\.strength)) { Text("保守").tag("保守"); Text("明显").tag("明显") }.pickerStyle(.segmented)
                Text("保留背景、原文与照片取景，只整理位置、尺寸和已有文字样式。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if action == .writing {
                Picker("文字形式", selection: field(\.writingKind)) {
                    ForEach(["标题", "随手一句", "照片旁注", "一小段", "润色", "缩短", "只换样式"], id: \.self) { Text($0) }
                }
                Toggle("结合照片内容写作", isOn: field(\.understandsPhotos))
                Text("只调整文字，不移动照片。润色、缩短与只换样式建议先选中文字对象。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if action == .relayout || action == .custom {
                if action == .relayout {
                    Picker("主照片", selection: field(\.heroID)) {
                        Text("自动选择").tag(UUID?.none)
                        ForEach(controller.bridge.objectChoices.filter { $0.role == "photo" }) { object in Text("\(object.shortID) · \(object.name)").tag(Optional(object.id)) }
                    }
                    if request.background == nil { Toggle("保留当前背景", isOn: field(\.preservesBackground)) }
                } else { Toggle("允许移动和缩放目标对象", isOn: field(\.allowsPlacement)) }
                Toggle("允许新增文字", isOn: field(\.allowsText))
                Toggle("允许改写原文", isOn: field(\.allowsRewrite))
                if request.allowsText {
                    Picker("文字密度", selection: field(\.textDensity)) { Text("简短补充").tag("简短补充"); Text("丰富记录").tag("丰富记录") }
                }
                Toggle("允许调整照片取景", isOn: field(\.allowsCrop))
                Toggle("允许调整相框", isOn: field(\.allowsFrames))
                Toggle("允许隐藏装饰", isOn: field(\.allowsDecorations))
                if action == .relayout {
                    Toggle("允许复用本页已有贴纸", isOn: field(\.allowsMaterials))
                    if request.allowsMaterials {
                        ForEach(controller.bridge.objectChoices.filter { $0.role == "decoration" && !$0.assetIDs.isEmpty }) { item in
                            Toggle("\(item.shortID) · \(item.name)", isOn: Binding(get: { request.materialIDs.contains(item.id) }, set: { enabled in
                                var ids = request.materialIDs; ids.removeAll { $0 == item.id }; if enabled { ids.append(item.id) }; field(\.materialIDs).wrappedValue = ids
                            }))
                        }
                        Text("只复用勾选的现有资源，不下载或生成新图片。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    private var progress: some View {
        VStack(spacing: 20) {
            ProgressView().controlSize(.large)
            Text(controller.stage).font(.headline)
            if let date = controller.startedAt { Text(date, style: .timer).monospacedDigit().foregroundStyle(.secondary) }
            Text("可以关闭面板继续浏览；回来后仍可查看进度。")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 60)
    }
    private var review: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("对比", selection: $showOriginal) { Text("原版").tag(true); Text("新版").tag(false) }.pickerStyle(.segmented)
            if let data = previewData, let image = UIImage(data: data) {
                Button { fullPreview = true } label: {
                    Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).accessibilityLabel("放大查看\(showOriginal ? "原版" : "草稿")")
            }
            Text(candidate?.summary ?? "").font(.body)
            ForEach(candidate?.warnings ?? [], id: \.self) { Text($0).font(.footnote).foregroundStyle(.orange) }
            section("继续调整") {
                TextField("例如：标题再小一点，保留其余排版", text: $refinement, axis: .vertical)
                    .lineLimit(2...5).textFieldStyle(.roundedBorder).focused($focused)
                Button("按补充要求再调整") { editingSettings = false; controller.start(request, refinement: refinement) }
                    .disabled(refinement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || controller.running)
            }
            if let tokens = controller.inputTokens { Text("本次输入 \(tokens) tokens · 输出 \(controller.outputTokens ?? 0) tokens").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var bottomBar: some View {
        HStack(spacing: 12) {
            if controller.runningAction == action {
                Button("停止生成", role: .destructive) { controller.cancel() }.buttonStyle(.bordered).frame(maxWidth: .infinity)
            } else if reviewing {
                Button("放弃", role: .destructive) { controller.discard(action) }.buttonStyle(.bordered)
                Button("应用到画布") { if controller.apply(action) { onApplied(); dismiss() } }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity).disabled(controller.running)
            } else {
                Button { focused = false; editingSettings = false; if let onStartWorkspace { onStartWorkspace(request); dismiss() } else { controller.start(request) } } label: {
                    Label(controller.running ? "另一个任务正在生成" : (request.background?.backgroundOnly == true ? "开始生成背景" : action.submitTitle), systemImage: "sparkles").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent)
                    .disabled(!request.canSubmit || controller.running || !controller.restored || (request.background?.backgroundOnly != true && request.selectedOnly && !controller.bridge.selectionAvailable))
            }
        }.controlSize(.large).padding(.horizontal, 20).padding(.vertical, 12).background(.bar)
    }
}
