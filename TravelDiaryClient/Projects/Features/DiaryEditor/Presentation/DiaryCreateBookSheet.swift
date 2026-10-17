import SwiftUI
import PhotosUI
import ImageIO

/// 选择完整预设、选图、原子创建；关闭后由书架进入新本预览。
struct DiaryCreateBookSheet: View {
    let ownerID: String
    let completed: (DiaryBook) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var packages: [DiaryPresetPackage] = []
    @State private var selectedID: String?
    @State private var title = ""
    @State private var photoStep = false
    @State private var capacity = 0
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photos: [Photo] = []
    @State private var preview: Photo?
    @State private var picking = false
    @State private var busy = false
    @State private var loadingPhotos = false
    @State private var loaded = false
    @State private var error: String?
    @State private var progress = ""
    @State private var operationID = UUID()
    @State private var temporaryFiles = DiaryCreationTemporaryFiles()
    private var temporaryDirectory: URL { temporaryFiles.directory }

    private struct Photo: Identifiable {
        let id = UUID()
        let url: URL
        let thumbnail: UIImage
    }
    private var package: DiaryPresetPackage? { packages.first { $0.id == selectedID } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if photoStep { photoPage } else { presetsPage }
                if let error { Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal) }
            }
            .background(DiaryLibraryStyle.background)
            .tint(DiaryLibraryStyle.accent)
            .navigationTitle(photoStep ? "上传照片" : "新建手帐本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark") { dismiss() }.disabled(busy || loadingPhotos)
                }
            }
            .safeAreaInset(edge: .bottom) { actions.padding().background(.regularMaterial) }
            .disabled(busy || loadingPhotos)
            .overlay {
                if busy || loadingPhotos {
                    ProgressView(loadingPhotos ? "正在读取照片…" : progress)
                        .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
            }
            .interactiveDismissDisabled(busy || loadingPhotos)
            .task { await loadCatalog() }
            .photosPicker(isPresented: $picking, selection: $pickerItems,
                          maxSelectionCount: max(1, capacity - photos.count), selectionBehavior: .ordered, matching: .images)
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                loadingPhotos = true
                Task { await addPhotos(items) }
            }
            .fullScreenCover(item: $preview) { photo in
                NavigationStack {
                    PhotoPreview(url: photo.url)
                        .toolbar { Button("完成") { preview = nil } }
                }
            }
        }
    }

    private var presetsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("选择一本喜欢的预设，完整保留所有页面和设计。")
                    .foregroundStyle(.secondary)
                if !loaded { ProgressView("正在读取预设…") }
                if loaded && packages.isEmpty {
                    ContentUnavailableView("暂无可用预设", systemImage: "books.vertical")
                    Button("重新加载") { Task { await loadCatalog() } }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 16) {
                    ForEach(packages) { item in
                        Button {
                            selectedID = item.id; title = item.manifest.title
                            operationID = UUID(); error = nil
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                DiaryPresetCover(package: item)
                                Text(item.manifest.title).font(.headline)
                                HStack {
                                    Text("完整预设 · \(item.manifest.pages.count) 页").font(.caption)
                                    Spacer()
                                    Image(systemName: selectedID == item.id ? "checkmark.circle.fill" : "circle")
                                }
                            }.padding(10)
                                .background(selectedID == item.id ? Color.accentColor.opacity(0.08) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(selectedID == item.id ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 2))
                        }.buttonStyle(.plain).accessibilityAddTraits(selectedID == item.id ? .isSelected : [])
                    }
                }
                TextField("手帐名称", text: $title).textFieldStyle(.roundedBorder)
                Text("名称最多 60 个字符").font(.caption).foregroundStyle(.secondary)
            }.padding()
        }
    }

    private var photoPage: some View {
        VStack(spacing: 20) {
            Text(capacity == 0 ? "这本预设没有可替换照片，可直接创建。" : "这本手帐可一键替换 \(capacity) 张照片")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            ScrollView {
                if photos.isEmpty {
                    Button { openPicker() } label: {
                        VStack(spacing: 20) {
                            Image(systemName: "plus").font(.system(size: 40, weight: .light))
                            Text(capacity == 0 ? "保留完整预设，开始制作" : "还是空的，点这里加照片吧")
                        }.foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(minHeight: 230)
                            .background(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.gray.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [7])))
                    }.disabled(capacity == 0)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 85), spacing: 12)], spacing: 12) {
                        if photos.count < capacity {
                            Button { openPicker() } label: {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.gray.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [5]))
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay { Image(systemName: "plus").font(.largeTitle).foregroundStyle(.secondary) }
                            }.accessibilityLabel("添加照片")
                        }
                        ForEach(photos) { photo in
                            Button { preview = photo } label: {
                                // 网格先确定正方形尺寸，图片只在内部填充，避免原图比例撑宽单元。
                                Color.clear
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay {
                                        GeometryReader { geometry in
                                            Image(uiImage: photo.thumbnail)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: geometry.size.width, height: geometry.size.height)
                                                .clipped()
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        photos.removeAll { $0.id == photo.id }
                                        try? FileManager.default.removeItem(at: photo.url)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 28, height: 28)
                                            .background(.black.opacity(0.65), in: Circle())
                                            .padding(4)
                                            .contentShape(Rectangle())
                                    }.accessibilityLabel("删除照片")
                                }
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal)
            Text("已选 \(photos.count) / \(capacity)").foregroundStyle(.secondary)
            Text("按选择顺序替换，未选择的位置保留预设照片。创建后仍可编辑。")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
        }
    }

    private var actions: some View {
        HStack(spacing: 16) {
            if photoStep {
                Button("上一步") { photoStep = false; error = nil }.buttonStyle(.bordered)
                Spacer()
                Button(photos.isEmpty ? "跳过并创建" : "创建") { Task { await create() } }
                    .buttonStyle(.borderedProminent)
            } else {
                Button { Task { await prepare() } } label: { Text("下一步").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .disabled(package == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 60)
            }
        }.controlSize(.large).disabled(busy || loadingPhotos)
    }

    private func loadCatalog() async {
        do {
            let catalog = try await Task.detached { try BundleDiaryPresetProvider().catalog() }.value
            packages = catalog.books; loaded = true
            if !catalog.issues.isEmpty { error = "部分预设暂不可用，请选择其他预设。" }
        } catch { loaded = true; self.error = error.localizedDescription }
    }

    private func prepare() async {
        guard let package, !busy else { return }
        busy = true; error = nil; progress = "正在统计可替换照片…"
        defer { busy = false }
        do {
            capacity = try await Task.detached {
                try package.validate()
                let ids = Dictionary(uniqueKeysWithValues: package.manifest.assetTable.keys.map { ($0, UUID()) })
                return try package.pages.reduce(0) { count, page in
                    count + (try package.instantiate(page, bookID: UUID(), targetSize: page.size.cg, assetIDs: ids)).replaceablePhotos().count
                }
            }.value
            if photos.count > capacity {
                for photo in photos.dropFirst(capacity) { try? FileManager.default.removeItem(at: photo.url) }
                photos = Array(photos.prefix(capacity))
            }
            photoStep = true
        } catch { self.error = error.localizedDescription }
    }

    private func openPicker() { pickerItems = []; picking = true }

    private func addPhotos(_ items: [PhotosPickerItem]) async {
        defer { loadingPhotos = false; pickerItems = [] }
        error = nil
        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            for item in items.prefix(max(0, capacity - photos.count)) {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw DiaryEditorError.invalidImage }
                let photo = try await Task.detached {
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 320] as CFDictionary) else { throw DiaryEditorError.invalidImage }
                    return UIImage(cgImage: cg)
                }.value
                let url = temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try data.write(to: url, options: .atomic)
                photos.append(Photo(url: url, thumbnail: photo))
            }
        } catch { self.error = "部分照片读取失败，已读取的照片已保留，请重新添加。" }
    }

    private func create() async {
        guard let package, !busy else { return }
        busy = true; error = nil; progress = "正在创建手帐…"
        defer { busy = false }
        do {
            let book = try await DiaryDocumentStore(ownerID: ownerID).importPreset(package,
                pageIDs: package.manifest.pages.map(\.id), title: title, operationID: operationID,
                replacementPhotos: photos.map(\.url), progress: { value in Task { @MainActor in progress = value } })
            try? FileManager.default.removeItem(at: temporaryDirectory)
            completed(book)
        } catch { self.error = "创建未完成，请重试。\(error.localizedDescription)" }
    }
}

private struct PhotoPreview: View {
    let url: URL
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { ProgressView() }
        }.task {
            image = await Task.detached {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2000] as CFDictionary) else { return UIImage?.none }
                return UIImage(cgImage: cg)
            }.value
        }
    }
}

/// 生命周期独立于照片预览的展示，关闭整个创建流程时清理源文件。
private final class DiaryCreationTemporaryFiles {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    deinit { try? FileManager.default.removeItem(at: directory) }
}
