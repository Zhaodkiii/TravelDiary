import SwiftUI
import PhotosUI
import ImageIO

/// 整本/当前页共用的替换入口。先列出槽位并确认选图顺序，再一次提交全部修改。
struct DiaryBatchPhotoSheet: View {
    let store: DiaryDocumentStore
    var session: DiaryEditorSession? = nil
    var preset: DiaryPresetPackage? = nil
    var presetPageIDs: [String] = []
    var preparationDirectory: URL? = nil
    var onPrepared: (([URL]) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var documents: [DiaryDocument] = []
    @State private var expectedBook: DiaryBook?
    @State private var slots: [Slot] = []
    @State private var selection: [PhotosPickerItem] = []
    @State private var thumbnails: [UIImage?] = []
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
        NavigationStack {
            List {
                Section {
                    Text(session == nil && preset == nil ? "当前手帐共 \(slots.count) 张可替换照片" : "当前页共 \(slots.count) 张可替换照片")
                    Text("按页序、组内图层从底到顶替换。隐藏及锁定图层跳过。完整图片拉伸到原框，比例不同时会变形。")
                        .font(.caption).foregroundStyle(.secondary)
                    if ready && !slots.isEmpty {
                        PhotosPicker(selection: $selection, maxSelectionCount: slots.count,
                                     selectionBehavior: .ordered, matching: .images) {
                            Label("选择照片（\(selection.count)/\(slots.count)）", systemImage: "photo.on.rectangle")
                        }
                    }
                    if ready && slots.isEmpty { Text("没有可替换照片。背景、贴纸及相框不会计入。") }
                }
                if onPrepared != nil {
                    Section {
                        Button("保留原照片，继续") { onPrepared?([]); dismiss() }.disabled(!ready)
                    }
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(onPrepared == nil ? "替换全部" : "下一步") { Task { await replace() } }
                        .disabled(!ready || busy || slots.isEmpty || selection.count != slots.count)
                }
            }
            .disabled(busy)
            .overlay { if busy { ProgressView(progress).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .interactiveDismissDisabled(busy)
            .task { await prepare() }
            .task(id: selection) { await loadThumbnails() }
        }
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
                let selected = try preset.pages.filter { presetPageIDs.contains($0.id) }
                for (index, page) in selected.enumerated() {
                    let document = try preset.instantiate(page, bookID: UUID(), targetSize: page.size.cg, assetIDs: assetIDs)
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
            documents = prepared; slots = targets; ready = true
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
        guard !busy, ready, selection.count == slots.count, !slots.isEmpty else { return }
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
                onPrepared(files); dismiss(); return
            }
            var updated = documents
            var replacements: [(UUID, DiaryAsset, UIImage, DiaryPhotoPlacement?)] = []
            // 逐张读取，失败时不提交任何图层修改；已导入的文件暂不被作品引用。
            for (index, slot) in slots.enumerated() {
                progress = "正在准备第 \(index + 1)/\(slots.count) 张照片…"
                guard let data = try await selection[index].loadTransferable(type: Data.self) else { throw DiaryEditorError.invalidImage }
                let (asset, image) = try await store.importImage(data, documentID: documents[slot.documentIndex].id)
                updated[slot.documentIndex].replacePhoto(slot.id, with: asset)
                if session != nil { replacements.append((slot.id, asset, image, nil)) }
            }
            progress = "正在保存…"
            if let session {
                guard session.applyPhotoReplacements(replacements, expected: documents[0]) else {
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
