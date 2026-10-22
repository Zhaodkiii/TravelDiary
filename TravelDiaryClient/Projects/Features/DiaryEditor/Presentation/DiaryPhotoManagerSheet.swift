import SwiftUI
import PhotosUI
import ImageIO

/// 照片入口只展示一个页面：已有照片与待添加照片都按照片、相框成组编辑。
struct DiaryPhotoManagerSheet: View {
    @ObservedObject var session: DiaryEditorSession
    @Environment(\.dismiss) private var dismiss
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPicker = false
    @State private var pickerTarget: PickerTarget = .add
    @State private var frameTarget: FrameTarget?
    @State private var drafts: [PhotoDraft] = []
    @State private var importing = false
    @State private var errorMessage: String?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    private enum PickerTarget { case add, existing(UUID), draft(UUID) }
    private enum FrameTarget: Identifiable {
        case existing(UUID), draft(UUID)
        var id: String {
            switch self {
            case .existing(let id): return "existing-\(id)"
            case .draft(let id): return "draft-\(id)"
            }
        }
    }
    private struct PhotoDraft: Identifiable {
        let id = UUID()
        var data: Data
        var preview: UIImage
        var frame: DiaryPhotoFrameCatalog.Item?
    }
    private var remainingCount: Int { max(0, min(30 - drafts.count, 200 - session.scopeLayers.count - drafts.count)) }
    private var pickerLimit: Int {
        if case .add = pickerTarget { return max(1, remainingCount) }
        return 1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    existingSection
                    additionSection
                }
                .padding(16)
            }
            .background(DiaryLibraryStyle.background)
            .navigationTitle("照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        Task { @MainActor in
                            if await addDrafts() { dismiss() }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !drafts.isEmpty {
                    DiaryImportFloatingActions {
                        Button { Task { await addDrafts() } } label: {
                            Text("添加 \(drafts.count) 张照片").frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .disabled(importing || session.busy)
            .overlay {
                if importing {
                    ProgressView("正在处理照片…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .sheet(item: $frameTarget) { target in
                switch target {
                case .existing(let id): DiaryPhotoFramePicker(session: session, photoID: id)
                case .draft(let id):
                    DiaryPhotoFrameChoiceSheet(selectedID: drafts.first(where: { $0.id == id })?.frame?.id) { item in
                        if let index = drafts.firstIndex(where: { $0.id == id }) { drafts[index].frame = item }
                    }
                }
            }
            .photosPicker(isPresented: $showPicker, selection: $photoItems,
                          maxSelectionCount: pickerLimit, selectionBehavior: .ordered, matching: .images)
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                let target = pickerTarget
                importing = true
                Task { @MainActor in
                    defer { photoItems = []; importing = false }
                    do { try await receive(items, target: target) }
                    catch { errorMessage = error.localizedDescription }
                }
            }
            .alert("照片处理失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("确定") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .interactiveDismissDisabled(importing || session.busy || !drafts.isEmpty)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var existingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("当前页已有照片（\(session.managedPhotos.count)）").font(.headline)
            Text("点击照片替换，点击相框更换样式。")
                .font(.caption).foregroundStyle(.secondary)
            if session.managedPhotos.isEmpty {
                Text("还没有照片，可在下方添加。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(session.managedPhotos.enumerated()), id: \.element.id) { index, photo in
                        VStack(spacing: 8) {
                            HStack {
                                Text("照片 \(index + 1)").font(.caption).foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                if photo.locked { Image(systemName: "lock.fill").font(.caption) }
                                if !photo.visible { Image(systemName: "eye.slash").font(.caption) }
                                Button(role: .destructive) { session.removePhoto(photo.id) } label: {
                                    Image(systemName: "trash").font(.caption).frame(width: 28, height: 28)
                                }.accessibilityLabel("删除第 \(index + 1) 张照片")
                            }
                            HStack(spacing: 8) {
                                tile(image: photo.layer.assetID.flatMap { session.images[$0] }, title: "照片", symbol: "photo") {
                                    pickerTarget = .existing(photo.id); showPicker = true
                                }
                                tile(image: frameImage(for: photo), title: "相框", symbol: "rectangle.dashed") {
                                    frameTarget = .existing(photo.id)
                                }
                            }
                        }
                        .padding(10)
                        .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                        .disabled(photo.locked)
                    }
                }
            }
        }
    }

    private var additionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("添加新的照片").font(.headline)
            Text("可多选，添加前可分别选择相框。页面已满时叠加放置。")
                .font(.caption).foregroundStyle(.secondary)
            Button { pickerTarget = .add; showPicker = true } label: {
                VStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 26, weight: .light))
                    Text("点这里添加新的照片").font(.subheadline)
                }
                .foregroundStyle(DiaryLibraryStyle.accent)
                .frame(maxWidth: .infinity).frame(height: 100)
                .background(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(DiaryLibraryStyle.line, style: StrokeStyle(lineWidth: 1.5, dash: [6])))
            }.buttonStyle(.plain).disabled(remainingCount == 0)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                    VStack(spacing: 8) {
                        HStack {
                            Text("新照片 \(index + 1)").font(.caption).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Button { drafts.removeAll { $0.id == draft.id } } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                    .frame(width: 28, height: 28)
                            }.accessibilityLabel("移除第 \(index + 1) 张新照片")
                        }
                        HStack(spacing: 8) {
                            tile(image: draft.preview, title: "照片", symbol: "photo") {
                                pickerTarget = .draft(draft.id); showPicker = true
                            }
                            tile(image: draft.frame?.image, title: draft.frame == nil ? "无相框" : "相框", symbol: "rectangle.dashed") {
                                frameTarget = .draft(draft.id)
                            }
                        }
                    }
                    .padding(10)
                    .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private func tile(image: UIImage?, title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Color.clear.frame(height: 88)
                    .overlay {
                        if let image { Image(uiImage: image).resizable().scaledToFit() }
                        else { Image(systemName: symbol).font(.title2).foregroundStyle(.secondary) }
                    }
                    .clipped()
                Text(title).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func frameImage(for photo: DiaryEditorSession.ManagedPhoto) -> UIImage? {
        let frame = session.document.objects[photo.ownerID]?.layers.first { $0.isPhotoFrame && $0.frameTargetID == photo.id }
        return frame?.assetID.flatMap { session.images[$0] }
    }

    @MainActor private func receive(_ items: [PhotosPickerItem], target: PickerTarget) async throws {
        var loaded: [(Data, UIImage)] = []
        for item in items {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 320
                  ] as CFDictionary) else { throw DiaryEditorError.invalidImage }
            loaded.append((data, UIImage(cgImage: cg)))
        }
        switch target {
        case .add:
            guard loaded.count <= remainingCount else { errorMessage = "本次照片过多，请分批添加。"; return }
            let frames = DiaryPhotoFrameCatalog.select(for: loaded.map { $0.1.size })
            guard frames.count == loaded.count else { throw DiaryEditorError.invalidImage }
            drafts += loaded.enumerated().map { index, photo in
                PhotoDraft(data: photo.0, preview: photo.1, frame: frames[index])
            }
        case .existing(let id):
            guard let data = loaded.first?.0 else { return }
            if !(await session.importPhoto(data, replacing: id)) {
                errorMessage = session.errorMessage ?? "无法替换这张照片。"
                session.errorMessage = nil
            }
        case .draft(let id):
            guard let photo = loaded.first, let index = drafts.firstIndex(where: { $0.id == id }) else { return }
            drafts[index].data = photo.0; drafts[index].preview = photo.1
        }
    }

    @MainActor @discardableResult private func addDrafts() async -> Bool {
        guard !importing, !session.busy else { return false }
        guard !drafts.isEmpty else { return true }
        importing = true
        defer { importing = false }
        guard await session.importPhotos(drafts.map(\.data), frames: drafts.map(\.frame)) else {
            errorMessage = session.errorMessage ?? "照片添加失败，请重试。"
            session.errorMessage = nil
            return false
        }
        drafts = []
        return true
    }
}

/// 待添加照片无需先写入画布，就能选择或移除相框。
private struct DiaryPhotoFrameChoiceSheet: View {
    let selectedID: String?
    let onSelect: (DiaryPhotoFrameCatalog.Item?) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                    choice(nil)
                    ForEach(DiaryPhotoFrameCatalog.items) { choice($0) }
                }.padding()
            }
            .navigationTitle("选择相框")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
    private func choice(_ item: DiaryPhotoFrameCatalog.Item?) -> some View {
        Button { onSelect(item); dismiss() } label: {
            VStack(spacing: 6) {
                Group {
                    if let image = item?.image { Image(uiImage: image).resizable().scaledToFit() }
                    else { Image(systemName: "rectangle.slash").font(.title) }
                }.frame(height: 84)
                Text(item?.title ?? "无相框").font(.caption2).lineLimit(1)
            }
            .frame(maxWidth: .infinity).padding(6)
            .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selectedID == item?.id ? DiaryLibraryStyle.accent : .clear, lineWidth: 2))
        }.buttonStyle(.plain)
    }
}
