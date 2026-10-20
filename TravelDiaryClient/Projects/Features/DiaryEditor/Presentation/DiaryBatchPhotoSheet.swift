import SwiftUI
import PhotosUI
import ImageIO

/// 整本/当前页共用的替换入口。先列出槽位并确认选图顺序，再一次提交全部修改。
struct DiaryBatchPhotoSheet: View {
    let store: DiaryDocumentStore
    var session: DiaryEditorSession? = nil
    var preset: DiaryPresetPackage? = nil
    var presetPageIDs: [String] = []
    var hiddenPresetCategories: Set<DiaryLayerSemanticKind> = []
    var preparationDirectory: URL? = nil
    var finishesImport = false
    var embedded = false
    var creationFlow = false
    var onPrepared: (([URL], DiaryPhotoSlot.Fill) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var documents: [DiaryDocument] = []
    @State private var expectedBook: DiaryBook?
    @State private var slots: [Slot] = []
    @State private var recommendedAdditionCount = 0

    private var addsPhotos: Bool { creationFlow && slots.isEmpty }
    private var photoLimit: Int { addsPhotos ? recommendedAdditionCount : slots.count }
    @State private var selection: [PhotosPickerItem] = []
    @State private var thumbnails: [UIImage?] = []
    private let fill: DiaryPhotoSlot.Fill = .cover
    @State private var busy = false
    @State private var ready = false
    @State private var message: String?
    @State private var progress = "正在统计照片…"

    private struct Slot: Identifiable {
        let id: UUID
        let documentIndex: Int
        let pageNumber: Int
        let name: String
        let size: CGSize
        let preview: UIImage?
    }

    var body: some View {
        Group {
            if creationFlow { creationContent }
            else if embedded { content } else { NavigationStack { content } }
        }
    }
    private var creationContent: some View {
        VStack(spacing: 12) {
            Text(addsPhotos
                 ? "已选 \(documents.count) 页，建议添加 \(photoLimit) 张照片"
                 : "这本手帐可一键替换 \(slots.count) 张照片")
                .font(.subheadline)
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            if !slots.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("项目中已有的照片").font(.subheadline.weight(.semibold))
                    ScrollView {
                        LazyVGrid(columns: photoColumns, spacing: 10) {
                            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                                VStack(spacing: 4) {
                                    Group {
                                        if let preview = slot.preview {
                                            Image(uiImage: preview).resizable().scaledToFit()
                                        } else { Image(systemName: "photo").foregroundStyle(.secondary) }
                                    }
                                    .frame(maxWidth: .infinity).frame(height: 72)
                                    .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                                    Text("\(index + 1) · 第 \(slot.pageNumber) 页")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(addsPhotos ? "添加照片" : "选择替换照片")
                    .font(.subheadline.weight(.semibold))
                if addsPhotos {
                    Text(photoLimit > 0 ? "根据页面空间建议数量，选好后自动配相框并排入手帐。" : "当前页面空间不足，请返回增加页面或调整内容。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                ScrollView {
                    if selection.isEmpty {
                        photoPicker {
                            VStack(spacing: 8) {
                                Image(systemName: "plus").font(.system(size: 26, weight: .light))
                                Text(addsPhotos ? "点这里添加照片，自动配框排版" : "点这里选择照片进行替换")
                                    .font(.caption)
                            }
                            .foregroundStyle(DiaryLibraryStyle.accent.opacity(0.55))
                            .frame(maxWidth: .infinity).frame(height: 100)
                            .background(RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(DiaryLibraryStyle.line, style: StrokeStyle(lineWidth: 1.5, dash: [6])))
                        }
                    } else {
                        LazyVGrid(columns: photoColumns, spacing: 10) {
                            photoPicker {
                                Image(systemName: "plus").font(.title2)
                                    .frame(maxWidth: .infinity).frame(height: 72)
                                    .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                            }
                            ForEach(selection.indices, id: \.self) { index in
                                Color.clear.frame(height: 72)
                                    .overlay {
                                        if thumbnails.indices.contains(index), let image = thumbnails[index] {
                                            Image(uiImage: image).resizable().scaledToFill()
                                        } else { ProgressView() }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(alignment: .bottomLeading) {
                                        Text("\(index + 1)").font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .foregroundStyle(.white).background(.black.opacity(0.5), in: Capsule())
                                            .padding(3)
                                    }
                                    .overlay(alignment: .topTrailing) {
                                        Button { selection.remove(at: index) } label: {
                                            Image(systemName: "xmark.circle.fill").font(.system(size: 18))
                                                .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.6))
                                                .frame(width: 32, height: 32)
                                        }.accessibilityLabel("删除第 \(index + 1) 张照片")
                                    }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
            if let message {
                Text(message).font(.caption2).foregroundStyle(.red)
                if !ready { Button("重试") { Task { await prepare() } } }
            }
            Text("已选 \(selection.count) / \(photoLimit)")
                .font(.footnote).foregroundStyle(.secondary)
            Text(addsPhotos ? "按选择顺序分配到页面，自动添加相框并排版。创建后仍可编辑。" : "按选择顺序替换，未选择的位置保留预设照片。创建后仍可编辑。")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DiaryLibraryStyle.background)
        .navigationTitle("第 3 步 · 添加照片")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(busy)
        .safeAreaInset(edge: .bottom) {
            DiaryImportFloatingActions {
                Button { Task { await replace() } } label: {
                    Text(selection.isEmpty ? "跳过并创建" : "创建").frame(maxWidth: .infinity)
                }.disabled(!ready)
            }
        }
        .disabled(busy)
        .overlay { if busy { ProgressView(progress).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .interactiveDismissDisabled(busy)
        .task { await prepare() }
        .task(id: selection) { await loadThumbnails() }
    }

    private var photoColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 64, maximum: 76), spacing: 10)]
    }

    private func photoPicker<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        PhotosPicker(selection: $selection, maxSelectionCount: max(1, photoLimit),
                     selectionBehavior: .ordered, matching: .images, label: label)
            .disabled(!ready || photoLimit == 0)
    }

    private var content: some View {
            List {
                Section {
                    Text(preset != nil ? "已选 \(presetPageIDs.count) 页，共 \(slots.count) 张可替换照片" : session == nil ? "当前手帐共 \(slots.count) 张可替换照片" : "当前页共 \(slots.count) 张可替换照片")
                    Text("按页序、组内图层从底到顶替换。隐藏及锁定图层跳过。照片保留原框的角度与轮廓，比例不同时默认等比例填充。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("替换后可选中照片，使用“裁剪”调整取景。")
                        .font(.caption).foregroundStyle(.secondary)
                    if ready && !slots.isEmpty {
                        PhotosPicker(selection: $selection, maxSelectionCount: slots.count,
                                     selectionBehavior: .ordered, matching: .images) {
                            Label("选择照片（\(selection.count)/\(slots.count)）", systemImage: "photo.on.rectangle")
                        }
                    }
                    if ready && slots.isEmpty { Text("没有可替换照片。背景、贴纸及相框不会计入。") }
                }
                Section("替换对应顺序") {
                    ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                        HStack {
                            thumbnail(slot.preview)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            thumbnail(thumbnails.indices.contains(index) ? thumbnails[index] : nil)
                            VStack(alignment: .leading) {
                                Text("\(index + 1). 第 \(slot.pageNumber) 页 · \(slot.name)").font(.subheadline)
                                Text("原框 \(Int(slot.size.width)) × \(Int(slot.size.height))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if index < selection.count {
                                VStack {
                                    Button { swap(index, index - 1) } label: { Image(systemName: "arrow.up") }
                                        .disabled(index == 0)
                                    Button { swap(index, index + 1) } label: { Image(systemName: "arrow.down") }
                                        .disabled(index + 1 >= selection.count)
                                }.buttonStyle(.borderless)
                            }
                        }
                    }
                }
                if let message { Text(message).foregroundStyle(.red) }
            }
            .navigationTitle(onPrepared == nil ? "一键替换照片" : "第 2 步 · 选择照片")
        .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                }
            }
            .navigationBarBackButtonHidden(busy)
            .safeAreaInset(edge: .bottom) {
                DiaryImportFloatingActions {
                    if onPrepared != nil {
                        Button(finishesImport ? "保留原照片，完成添加" : "保留原照片，继续") {
                            onPrepared?([], fill)
                            if !embedded { dismiss() }
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .disabled(!ready || busy)
                    }
                    Button { Task { await replace() } } label: {
                        Text(onPrepared == nil ? "替换全部" : finishesImport ? "完成添加" : "下一步")
                            .frame(maxWidth: .infinity)
                    }.disabled(!ready || busy || slots.isEmpty || selection.count != slots.count)
                }
            }
            .disabled(busy)
            .overlay { if busy { ProgressView(progress).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .interactiveDismissDisabled(busy)
            .task { await prepare() }
            .task(id: selection) { await loadThumbnails() }
    }

    private func thumbnail(_ image: UIImage?) -> some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }.frame(width: 44, height: 60)
    }

    private func swap(_ a: Int, _ b: Int) {
        guard selection.indices.contains(a), selection.indices.contains(b) else { return }
        selection.swapAt(a, b)
    }

    @MainActor private func prepare() async {
        guard !ready else { return }
        busy = true
        defer { busy = false }
        do {
            var prepared: [DiaryDocument] = []
            var targets: [Slot] = []
            func append(_ document: DiaryDocument, images: [UUID: UIImage], page: Int) {
                let index = prepared.count
                prepared.append(document)
                for layer in document.replaceablePhotos() {
                    let source = layer.assetID.flatMap { images[$0] }
                    targets.append(Slot(id: layer.id, documentIndex: index, pageNumber: page,
                                        name: layer.name, size: layer.size,
                                        preview: source?.preparingThumbnail(of: CGSize(width: 88, height: 120))))
                }
            }
            if let preset {
                let assetIDs = Dictionary(uniqueKeysWithValues: preset.manifest.assetTable.keys.map { ($0, UUID()) })
                let selected = try presetPageIDs.map { id -> PresetPage in
                    guard let reference = preset.manifest.pages.first(where: { $0.id == id }) else { throw DiaryEditorError.invalidDocument }
                    return try preset.read(PresetPage.self, reference.path)
                }
                for (index, page) in selected.enumerated() {
                    let document = try preset.instantiate(page, bookID: UUID(), targetSize: page.size.cg, assetIDs: assetIDs)
                        .excludingPresetCategories(hiddenPresetCategories)
                    var images: [UUID: UIImage] = [:]
                    let needed = Set(document.replaceablePhotos().compactMap(\.assetID))
                    for (key, asset) in preset.manifest.assetTable {
                        guard let id = assetIDs[key], needed.contains(id) else { continue }
                        let url = try preset.url(asset.path)
                        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                           let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: 160
                           ] as CFDictionary) { images[id] = UIImage(cgImage: cg) }
                    }
                    append(document, images: images, page: index + 1)
                }
            } else if let session {
                session.finishInteraction()
                append(session.document, images: session.images, page: 1)
            } else {
                let book = try await store.loadBook()
                expectedBook = book
                for (index, page) in book.pages.enumerated() {
                    let loaded = try await store.load(page.id)
                    append(loaded.document, images: loaded.images, page: index + 1)
                }
                guard try await store.loadBook().catalogRevision == book.catalogRevision else { throw DiaryEditorError.pageConflict }
            }
            documents = prepared; slots = targets
            if creationFlow && targets.isEmpty {
                recommendedAdditionCount = prepared.reduce(0) { count, document in
                    count + DiaryEditorSession(document: document, images: [:], store: store).recommendedPhotoCount
                }
            }
            ready = true
        } catch { message = error.localizedDescription }
    }

    @MainActor private func loadThumbnails() async {
        let items = selection
        thumbnails = Array(repeating: nil, count: items.count)
        for (index, item) in items.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self), !Task.isCancelled else { return }
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 160
                      ] as CFDictionary) else { continue }
                guard !Task.isCancelled, items == selection else { return }
                thumbnails[index] = UIImage(cgImage: cg)
            } catch { if !Task.isCancelled { message = "照片预览加载失败，可重新选择。" } }
        }
    }

    @MainActor private func replace() async {
        guard !busy, ready else { return }
        if creationFlow {
            guard onPrepared != nil, preparationDirectory != nil, selection.count <= photoLimit else { return }
        } else {
            guard selection.count == slots.count, !slots.isEmpty else { return }
        }
        busy = true; message = nil
        defer { busy = false }
        do {
            if let onPrepared, let preparationDirectory {
                try FileManager.default.createDirectory(at: preparationDirectory, withIntermediateDirectories: true)
                var files: [URL] = []
                do {
                    for (index, item) in selection.enumerated() {
                        progress = "正在准备第 \(index + 1)/\(selection.count) 张照片…"
                        guard let data = try await item.loadTransferable(type: Data.self),
                              CGImageSourceCreateWithData(data as CFData, nil) != nil else { throw DiaryEditorError.invalidImage }
                        let url = preparationDirectory.appendingPathComponent(UUID().uuidString)
                        try data.write(to: url, options: .atomic); files.append(url)
                    }
                } catch {
                    for file in files { try? FileManager.default.removeItem(at: file) }
                    throw error
                }
                onPrepared(files, fill); if !embedded { dismiss() }; return
            }
            var updated = documents
            var replacements: [(UUID, DiaryAsset, UIImage, DiaryPhotoPlacement?)] = []
            var photoSlots: [UUID: DiaryPhotoSlot] = [:]
            // 逐张读取，失败时不提交任何图层修改；已导入的文件暂不被作品引用。
            for (index, slot) in slots.enumerated() {
                progress = "正在准备第 \(index + 1)/\(slots.count) 张照片…"
                guard let data = try await selection[index].loadTransferable(type: Data.self) else { throw DiaryEditorError.invalidImage }
                let document = documents[slot.documentIndex]
                guard let layer = document.layer(slot.id) else { throw DiaryEditorError.invalidDocument }
                var geometry = try await store.photoSlot(for: layer, document: document)
                geometry.fill = fill
                photoSlots[slot.id] = geometry
                let (asset, image) = try await store.importImage(data, documentID: document.id)
                updated[slot.documentIndex].replacePhoto(slot.id, with: asset, slot: geometry)
                if session != nil { replacements.append((slot.id, asset, image, nil)) }
            }
            progress = "正在保存…"
            if let session {
                guard session.applyPhotoReplacements(replacements, expected: documents[0], slots: photoSlots) else {
                    message = session.errorMessage; return
                }
                // 编辑页采用既有自动保存与撤销机制，不强制关闭编辑会话。
            } else if let expectedBook {
                let changed = Set(slots.map(\.documentIndex))
                try await store.savePhotoReplacementBatch(updated.enumerated().filter { changed.contains($0.offset) }.map(\.element), expected: expectedBook)
            }
            dismiss()
        } catch { message = "替换未完成，原照片保持不变。\(error.localizedDescription)" }
    }
}
