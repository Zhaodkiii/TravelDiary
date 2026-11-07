import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

/// PHPicker's dismissal completes before the editor presents the preparation sheet.
struct DiaryCreationSystemPicker: UIViewControllerRepresentable {
    var limit: Int
    var completed: ([PHPickerResult]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completed: completed) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.preferredAssetRepresentationMode = .current
        configuration.filter = .images; configuration.selectionLimit = max(1, limit); configuration.selection = .ordered
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completed: ([PHPickerResult]) -> Void
        init(completed: @escaping ([PHPickerResult]) -> Void) { self.completed = completed }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            completed(results)
        }
    }
}

struct DiaryAICreationSheet: View {
    @ObservedObject var flow: DiaryAICreationFlow
    var submitted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var path: [Route] = []
    @State private var photos: [PhotosPickerItem] = []
    @State private var picking = false
    @State private var query = ""
    @State private var discarding = false
    @State private var submitting = false
    @State private var appeared = false
    @State private var librarySource = "推荐"
    @State private var discardsDraft = false
    private let ink = Color(red: 0.24, green: 0.39, blue: 0.34)
    private enum Route: Hashable { case stickers, design, library, photo(UUID), sticker(String), story }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 2 : 3) }
    var body: some View {
        NavigationStack(path: $path) {
            photoPage
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .stickers: stickerPage
                    case .design: designPage
                    case .library: libraryPage
                    case .photo(let id): photoDetail(id)
                    case .sticker(let id): stickerDetail(id)
                    case .story: storyPage
                    }
                }
        }
        .tint(ink)
        .disabled(submitting)
        .onReceive(MaterialCatalogRepository.shared.$owner) { owner in
            if owner != flow.draft.owner { flow.cancelOperation(); dismiss() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(submitting || flow.saveError != nil)
        .onAppear {
            flow.resumePreparation()
            guard !appeared else { return }; appeared = true
            if flow.draft.step == 1 { path = [.stickers] }
            if flow.draft.step == 2 { path = [.stickers, .design] }
        }
        .onChange(of: path) { _, value in
            let step = value.contains(.design) ? 2 : value.contains(.stickers) ? 1 : 0
            flow.setStep(step)
            if !value.contains(.library) { query = "" }
        }
        .onDisappear { if !submitting { flow.cancelStickerOperation() } }
        .confirmationDialog("丢弃这次制作草稿？", isPresented: $discardsDraft, titleVisibility: .visible) {
            Button("丢弃草稿", role: .destructive) { flow.discardDraft(); dismiss() }
        } message: { Text("将移除这次准备的照片、贴纸与选择，已有作品不受影响。") }
        .confirmationDialog("放弃未能保存的更改并退出？", isPresented: $discarding, titleVisibility: .visible) {
            Button("放弃并退出", role: .destructive) { dismiss() }
        }
    }
    private func page<Content: View>(_ title: String, step: String?, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let step { Text(step).font(.subheadline).foregroundStyle(.secondary) }
                content()
                if !flow.pendingPhotoIDs.isEmpty { Text("照片正在后台读取，可继续下一步。").font(.footnote).foregroundStyle(.secondary) }
                if flow.busy { HStack { ProgressView(); Text(flow.status).font(.footnote) } }
                if let error = flow.error { Text(error).font(.footnote).foregroundStyle(.orange) }
                if let error = flow.saveError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                    Button("重新保存草稿") { flow.save() }
                    Button("放弃并退出", role: .destructive) { discarding = true }
                }
            }.padding(20).frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { flow.cancelOperation(); if flow.save() { dismiss() } }.disabled(submitting) } }
    }
    private func footer(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.headline).frame(maxWidth: .infinity, minHeight: 44) }
            .buttonStyle(.borderedProminent).controlSize(.large).disabled(disabled)
            .padding(.horizontal, 20).padding(.vertical, 12).background(.regularMaterial)
    }
    private var photoPage: some View {
        page("确认照片", step: "第 1 步，共 3 步 · 已选 \(flow.selectedPhotoCount)/30 张") {
            Text("按顺序讲述这次旅行。3–8 张更便于突出重点。").font(.subheadline).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(Array(flow.draft.photos.enumerated()), id: \.element.id) { index, photo in
                    VStack(spacing: 6) {
                        NavigationLink(value: Route.photo(photo.id)) {
                            thumbnail(photo.filename).frame(height: 110).clipped()
                                .overlay(alignment: .topLeading) { Text("\(index + 1)").font(.caption.bold()).padding(6).background(.regularMaterial, in: Circle()) }
                        }.accessibilityLabel("第 \(index + 1) 张照片，查看大图")
                        HStack {
                            if photo.id == flow.draft.heroID { Label("主照", systemImage: "star.fill").font(.caption) }
                            Spacer(minLength: 0)
                            Button { flow.removePhoto(photo.id) } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }.accessibilityLabel("删除第 \(index + 1) 张照片")
                        }
                    }
                    .draggable(photo.id.uuidString)
                    .dropDestination(for: String.self) { values, _ in
                        guard let first = values.first, let id = UUID(uuidString: first) else { return false }
                        flow.movePhoto(id, before: photo.id); return true
                    }
                    .accessibilityAction(named: "前移") { flow.movePhoto(photo.id, offset: -1) }
                    .accessibilityAction(named: "后移") { flow.movePhoto(photo.id, offset: 1) }
                }
                ForEach(flow.pendingPhotoIDs, id: \.self) { id in
                    VStack {
                        if let image = flow.selectedPhotoImages[id] {
                            Image(uiImage: image).resizable().scaledToFit().frame(height: 110)
                        } else {
                            ProgressView("正在从相册读取").frame(maxWidth: .infinity, minHeight: 110)
                        }
                        Button("移除") { flow.removePhoto(id) }.font(.caption)
                    }
                }
                Button { picking = true } label: {
                    Label("继续添加", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 110)
                        .background(ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                }.disabled(flow.selectedPhotoCount >= 30)
            }.disabled(flow.isSubmitting)
            ForEach(flow.failures.keys.sorted { $0.uuidString < $1.uuidString }, id: \.self) { id in
                HStack { Text(flow.failures[id] ?? "照片读取失败"); Spacer(); Button("重试") { flow.retryFailure(id) }; Button("移除") { flow.removeFailure(id) } }.font(.footnote).disabled(flow.isSubmitting)
            }
            NavigationLink(value: Route.story) { Label(flow.draft.story.isEmpty ? "写点故事（选填）" : "编辑故事", systemImage: "square.and.pencil") }
            Button("丢弃这次草稿", role: .destructive) { discardsDraft = true }.font(.footnote).disabled(flow.isSubmitting)
        }
        .safeAreaInset(edge: .bottom) { footer("下一步 · 搭配贴纸", disabled: !flow.canContinue) { path.append(.stickers) } }
        .photosPicker(isPresented: $picking, selection: $photos, maxSelectionCount: max(1, 30 - flow.selectedPhotoCount), selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current)
        .onChange(of: photos) { _, values in guard !values.isEmpty else { return }; photos = []; flow.importPhotos(values) }
    }
    @ViewBuilder private func thumbnail(_ file: String) -> some View {
        if let image = flow.images[file] { Image(uiImage: image).resizable().scaledToFit() }
        else { ContentUnavailableView("素材缺失", systemImage: "photo.badge.exclamationmark").font(.caption) }
    }
    private func photoDetail(_ id: UUID) -> some View {
        page("照片预览", step: nil) {
            if let photo = flow.draft.photos.first(where: { $0.id == id }) {
                DiaryCreationAssetPreview(url: flow.directory.appendingPathComponent(photo.filename), fallback: flow.images[photo.filename]).frame(maxWidth: .infinity, minHeight: 300)
                TextField("这张照片的故事（选填）", text: Binding(get: { flow.draft.photoNotes?[id.uuidString] ?? "" }, set: { flow.setPhotoNote(id, value: $0) }), axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(3...6)
                Button(flow.draft.heroID == id ? "已设为主照片" : "设为主照片", systemImage: "star") { flow.setHero(id) }
                HStack { Button("前移") { flow.movePhoto(id, offset: -1) }; Button("后移") { flow.movePhoto(id, offset: 1) } }
                Button("删除照片", role: .destructive) { flow.removePhoto(id); path.removeLast() }
            }
        }
    }
    private var storyPage: some View {
        page("写点故事", step: "选填 · 描述你想留下的记忆") {
            TextEditor(text: Binding(get: { flow.draft.story }, set: { flow.setStory($0) }))
                .frame(minHeight: 240).padding(8).background(.background, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("故事内容")
        }
    }
    private var stickerPage: some View {
        page("搭配贴纸", step: "第 2 步，共 3 步") {
            HStack {
                Picker("主题", selection: Binding(get: { flow.draft.theme }, set: { flow.setTheme($0) })) {
                    ForEach(availableThemes, id: \.self) { Text($0) }
                }.pickerStyle(.menu)
                Spacer(); Text("已选 \(flow.selectedStickerCount)/8").font(.subheadline.monospacedDigit())
            }.disabled(flow.isSubmitting)
            VStack(spacing: 12) {
                HStack { Image(systemName: "sparkles"); Text("今天的贴纸搭配").font(.headline); Spacer(); Circle().fill(ink).frame(width: 7, height: 7) }.foregroundStyle(ink)
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(flow.draft.stickers) { sticker in
                        stickerCard(sticker)
                    }
                    NavigationLink(value: Route.library) { Label("添加", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 110) }.disabled(flow.draft.stickers.count >= 8)
                }.disabled(flow.isSubmitting)
                if flow.draft.stickers.isEmpty { Text("也可以不加贴纸，留白同样好看。").font(.footnote).foregroundStyle(.secondary) }
            }.padding(16).background(ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(ink.opacity(0.15), lineWidth: 2))
                .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.38, dampingFraction: 0.78), value: flow.draft.stickers.map(\.id))
                .sensoryFeedback(.selection, trigger: flow.draft.batch)
            HStack {
                Button("换一批", systemImage: "arrow.clockwise") { flow.draw() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(flow.busy || flow.loadingCatalog || flow.allKept || flow.candidates.isEmpty)
                Text(flow.allKept ? "取消保留后可换新" : "保留喜欢的，其余换新").font(.footnote).foregroundStyle(.secondary)
            }
            if flow.loadingCatalog { ProgressView("正在寻找贴纸…") }
            if flow.candidates.isEmpty && !flow.loadingCatalog { Button("重新加载贴纸") { flow.loadCatalog() } }
            HStack { Button("撤销上次操作") { flow.undoLast() }.disabled(!flow.undoAvailable || flow.isSubmitting); Spacer(); Button("不用贴纸") { flow.skipStickers(); path.append(.design) }.disabled(flow.isSubmitting) }.font(.footnote)
            if flow.busy { Button("取消本次准备") { flow.cancelStickerOperation() } }
        }
        .safeAreaInset(edge: .bottom) { footer("下一步 · 选择排版", disabled: flow.isSubmitting || flow.saveError != nil) { path.append(.design) } }
        .task { flow.loadCatalog() }
    }
    private var availableThemes: [String] {
        ["全部"] + Set(flow.themes + [flow.draft.theme]).filter { $0 != "全部" }.sorted()
    }
    private func stickerAnimation(_ sticker: DiaryCreationSticker) -> Animation {
        let index = flow.draft.stickers.firstIndex { $0.id == sticker.id } ?? 0
        return reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.35, dampingFraction: 0.8).delay(Double(index) * 0.035)
    }
    private func stickerCard(_ sticker: DiaryCreationSticker) -> some View {
VStack(spacing: 4) {
                            NavigationLink(value: Route.sticker(sticker.id)) {
                                thumbnail(sticker.filename).frame(height: 92)
                            }.accessibilityLabel("查看贴纸：" + sticker.item.name)
                            Text(sticker.item.name).font(.caption).lineLimit(1)
                            HStack(spacing: 0) {
                                Button { flow.toggleKeep(sticker.id) } label: { Image(systemName: sticker.kept ? "pin.fill" : "pin").frame(minWidth: 44, minHeight: 44) }
                                    .accessibilityLabel(sticker.kept ? "取消保留：" + sticker.item.name : "保留：" + sticker.item.name)
                                Button { flow.removeSticker(sticker.id) } label: { Image(systemName: "xmark.circle").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("删除：" + sticker.item.name)
                            }
                        }.padding(4).background(.background.opacity(sticker.kept ? 0.9 : 0.45), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(sticker.kept ? ink.opacity(0.6) : .clear))
                            .animation(stickerAnimation(sticker), value: flow.draft.batch)
                            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity).combined(with: .offset(y: -12)), removal: .scale(scale: 0.9).combined(with: .opacity)))
    }
    private func stickerDetail(_ id: String) -> some View {
        page("贴纸预览", step: nil) {
            if let sticker = flow.draft.stickers.first(where: { $0.id == id }) {
                DiaryCreationAssetPreview(url: flow.directory.appendingPathComponent(sticker.filename), fallback: flow.images[sticker.filename]).frame(maxWidth: .infinity, minHeight: 300)
                Text(sticker.item.name).font(.headline)
                Button(sticker.kept ? "取消保留" : "保留这张", systemImage: "pin") { flow.toggleKeep(id) }
                Button("删除这张", role: .destructive) { flow.removeSticker(id); path.removeLast() }
            }
        }
    }
    private var libraryItems: [CloudMaterial] {
        flow.candidates.filter { item in
            (query.isEmpty || (item.name + item.keywords.joined(separator: " ")).localizedCaseInsensitiveContains(query)) &&
            (librarySource != "收藏" || item.is_favorited) &&
            (librarySource != "最近" || MaterialRecentStore.items(owner: flow.draft.owner).contains(where: { $0.id == item.id }))
        }
    }
    private var libraryPage: some View {
        page("添加一张贴纸", step: "手动添加的贴纸会自动保留") {
            Picker("贴纸来源", selection: $librarySource) {
                ForEach(["推荐", "收藏", "最近", "我的"], id: \.self) { Text($0) }
            }.pickerStyle(.segmented)
            if librarySource == "我的" {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(flow.personalItems) { item in
                        let selected = flow.pendingStickerIDs.contains("personal." + item.id) || flow.draft.stickers.contains { $0.id == "personal." + item.id }
                        Button {
                            flow.addPersonal(item) { if path.last == .library { path.removeLast() } }
                        } label: {
                            VStack {
                                CachedPreviewImage(request: PersonalStickerService.imageRequest(item)).frame(height: 100)
                                Text(selected ? "已添加" : "添加这张").font(.caption)
                            }
                        }.disabled(selected || flow.isSubmitting || flow.selectedStickerCount >= 8)
                    }
                }
                if flow.personalItems.isEmpty { Text("还没有制作过贴纸，可先选择推荐贴纸。").font(.footnote).foregroundStyle(.secondary) }
                if flow.loadingPersonal { ProgressView() }
                Button(flow.personalCursor == nil ? "刷新我的贴纸" : "加载更多") { Task { await flow.loadPersonal(more: flow.personalCursor != nil) } }.disabled(flow.loadingPersonal)
            } else {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(libraryItems) { item in
                    let selected = flow.pendingStickerIDs.contains(item.id) || flow.draft.stickers.contains { $0.id == item.id }
                    Button {
                        flow.addSticker(item) { if path.last == .library { path.removeLast() } }
                    } label: {
                        VStack {
                            MaterialResourceImage(resource: .init(resource_id: item.id, sha256: item.thumbnail_sha256, url: item.thumbnail_url, width: 256, height: 256), libraryID: item.library_id, version: item.library_version)
                                .frame(height: 100)
                            Text(selected ? "已添加" : item.name).font(.caption).lineLimit(2)
                        }
                    }.disabled(selected || flow.isSubmitting || flow.selectedStickerCount >= 8)
                }
            }
            }
            if flow.candidates.isEmpty { Button("加载贴纸库") { flow.loadCatalog() } }
            if flow.hasMoreCatalog { Button("加载更多贴纸") { flow.loadCatalog(more: true) }.disabled(flow.loadingCatalog) }
            if flow.loadingCatalog { ProgressView("正在加载…") }
        }.searchable(text: $query, prompt: "搜索贴纸")
        .task(id: librarySource) { if librarySource == "我的" { await flow.loadPersonal() } }
    }
    private var designPage: some View {
        page("选择排版", step: "第 3 步，共 3 步 · 照片 \(flow.draft.photos.count) 张 · 贴纸 \(flow.draft.stickers.count) 张") {
            DiaryAIDesignPreview(design: flow.design, photos: flow.photoPreviews).frame(height: 180).frame(maxWidth: .infinity)
            if !flow.draft.stickers.isEmpty {
                ScrollView(.horizontal) { HStack { ForEach(flow.draft.stickers) { sticker in thumbnail(sticker.filename).frame(width: 48, height: 48) } } }
            }
            if flow.preparingMaterials {
                ProgressView("正在准备素材 \(flow.preparedCount)/\(flow.draft.photos.count + flow.draft.stickers.count)")
                    .font(.caption)
            } else if !flow.preparationFailures.isEmpty {
                Text("有 \(flow.preparationFailures.count) 项素材准备失败，可重试或返回移除。").font(.caption).foregroundStyle(.orange)
                Button("重试准备素材") { flow.resumePreparation() }
            }
            Text("排版示意，制作后可继续调整。贴纸会融入正式构图。").font(.caption).foregroundStyle(.secondary)
            if flow.draft.photos.count > 8 { Text("照片较多，成品中会较小；可返回删减或调整主照。").font(.footnote).foregroundStyle(.orange) }
            DiaryAIDesignChooser(selection: Binding(get: { flow.design }, set: { flow.setDesign($0) }), photos: flow.photoPreviews)
            NavigationLink(value: Route.story) { Label("故事与制作说明（选填）", systemImage: "square.and.pencil") }
        }
        .navigationBarBackButtonHidden(submitting)
        .safeAreaInset(edge: .bottom) {
            footer(submitting ? (flow.preparingMaterials ? "正在准备素材 \(flow.preparedCount)/\(flow.draft.photos.count + flow.draft.stickers.count)…" : flow.status) : "开始制作", disabled: !flow.canContinue || submitting) {
                submitting = true
                Task {
                    if await flow.submit() { submitted() } else { submitting = false }
                }
            }
        }
    }
}

private struct DiaryCreationAssetPreview: View {
    let url: URL
    let fallback: UIImage?
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @GestureState private var gestureScale: CGFloat = 1
    var body: some View {
        Group {
            if let image = image ?? fallback {
                Image(uiImage: image).resizable().scaledToFit()
                    .scaleEffect(min(4, max(1, scale * gestureScale)))
                    .gesture(MagnifyGesture().updating($gestureScale) { value, state, _ in state = value.magnification }
                        .onEnded { scale = min(4, max(1, scale * $0.magnification)) })
                    .clipped().accessibilityLabel("素材大图，可双指放大")
            } else { ContentUnavailableView("素材缺失，请重新添加", systemImage: "photo") }
        }.task(id: url) {
            image = try? await DiaryAIImageWork.run {
                let data = try Data(contentsOf: url)
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1600] as CFDictionary) else { throw DiaryEditorError.invalidImage }
                return UIImage(cgImage: cg)
            }
        }
    }
}
