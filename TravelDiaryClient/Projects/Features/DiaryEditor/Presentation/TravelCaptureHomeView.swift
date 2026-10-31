import SwiftUI
import PhotosUI
import UIKit

/// 随记只负责采集与交接，编辑始终使用已有的 DiaryEditorScreen。
struct TravelCaptureHomeView: View {
    let ownerID: String
    @State private var books: [DiaryBook] = []
    @State private var book: DiaryBook?
    @State private var pageID: UUID?
    @State private var pendingEditor: DiaryEditorSession?
    @State private var editor: DiaryEditorSession?
    @State private var camera = false
    private struct ReviewPhoto: Identifiable { let id = UUID(); let image: UIImage }
    @State private var reviewPhoto: ReviewPhoto?
    @State private var loadingPhoto = false
    @State private var image: UIImage?
    @State private var photo: PhotosPickerItem?
    @State private var busy = false
    @State private var error: String?
    @State private var preview: UIImage?
    @State private var subjects: [StickerSubject] = []
    private let size = CGSize(width: 4370, height: 3130)
    private var store: DiaryDocumentStore { DiaryDocumentStore(ownerID: ownerID, bookID: book?.id) }

    private var pendingURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TravelCapture-" + Data(ownerID.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_") + ".png")
    }
    private var captureKey: String { "TravelCaptureTarget." + ownerID }
    private func retainCapture(_ value: UIImage) {
        do {
            try FileManager.default.createDirectory(at: pendingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let data = value.pngData() else { throw DiaryEditorError.invalidImage }
            try data.write(to: pendingURL, options: .atomic)
            UserDefaults.standard.set([book?.id.uuidString ?? "", pageID?.uuidString ?? ""], forKey: captureKey)
            image = value; error = nil; reviewPhoto = ReviewPhoto(image: value)
        } catch { self.error = error.localizedDescription }
    }

    var body: some View {
        homeContent
        .background {
            Color(uiColor: .systemGroupedBackground)
            Canvas { context, size in
                for x in stride(from: 8.0, to: size.width, by: 22) {
                    for y in stride(from: 8.0, to: size.height, by: 22) {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.secondary.opacity(0.12)))
                    }
                }
            }.allowsHitTesting(false)
        }
        .disabled(busy)
        .overlay { if busy { ProgressView("正在准备…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        .task { await reload(); if let data = try? Data(contentsOf: pendingURL), let value = UIImage(data: data) {
            if let target = UserDefaults.standard.stringArray(forKey: captureKey), target.count == 2, let restored = books.first(where: { $0.id.uuidString == target[0] }) { book = restored; pageID = restored.contentPages.first(where: { $0.id.uuidString == target[1] })?.id }
            image = value; error = nil; reviewPhoto = ReviewPhoto(image: value)
        } }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                loadingPhoto = true
                defer { loadingPhoto = false; photo = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let value = UIImage(data: data) else { throw DiaryEditorError.invalidImage }
                    retainCapture(value)
                } catch { self.error = "照片读取失败，请重新选择。\n" + error.localizedDescription }
            }
        }
        .sheet(isPresented: $camera, onDismiss: {
            if let image { retainCapture(image) }
        }) { TravelCaptureCamera { image = $0; camera = false } }
        .sheet(item: $reviewPhoto, onDismiss: {
            if let pendingEditor { editor = pendingEditor; self.pendingEditor = nil }
        }) { capture in
            TravelCaptureReview(original: capture.image, submitting: busy, submissionError: error,
                onNext: { material, kind, frame in Task { await submit(kind, material: material, frame: frame) } },
                onClose: { reviewPhoto = nil })
        }
        .overlay {
            if loadingPhoto { ProgressView("正在读取照片…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) }
        }

        .fullScreenCover(item: $editor, onDismiss: { Task { await reload(); await refreshPreview() } }) { DiaryEditorScreen(session: $0) }
        .alert("旅行随记", isPresented: Binding(get: { error != nil && reviewPhoto == nil }, set: { if !$0 { error = nil } })) { Button("好") { error = nil } } message: { Text(error ?? "") }
    }

    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Menu {
                    ForEach(books) { item in Button(item.title) { book = item; pageID = item.contentPages.last?.id; Task { await refreshPreview() } } }
                    Button("开始新的旅行") { Task { await createBook() } }
                } label: { Label(book?.title ?? "选择旅行手帐", systemImage: "book.closed").font(.headline) }
                HStack(alignment: .firstTextBaseline) {
                    Text(Date.now, format: .dateTime.month().day()).font(.system(size: 44, weight: .medium, design: .serif))
                    Text(Date.now, format: .dateTime.weekday()).foregroundStyle(.secondary)
                }
                Text("今天的旅途，正在这一页继续。").foregroundStyle(.secondary)
                Spacer(minLength: 30)
                Button { Task { await open() } } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.95, green: 0.95, blue: 0.90))
                        if let preview { Image(uiImage: preview).resizable().scaledToFit() }
                        else { Text("把眼前的风景，收进这一页。").foregroundStyle(.secondary) }
                    }.aspectRatio(4370.0 / 3130, contentMode: .fit)
                }.buttonStyle(.plain).shadow(color: .black.opacity(0.08), radius: 12, y: 6)
                HStack {
                    Menu("查看全部跨页") {
                        if let book {
                            ForEach(Array(book.contentPages.enumerated()), id: \.element.id) { index, page in
                                Button("第 \(index + 1) 跨页") { pageID = page.id; Task { await refreshPreview() } }
                            }
                        }
                    }
                    Spacer()
                    Button("新跨页", systemImage: "plus") { Task { await newPage() } }
                }
                Spacer(minLength: 30)
                HStack(spacing: 20) {
                    PhotosPicker(selection: $photo, matching: .images) { Label("相册", systemImage: "photo") }
                    Button { if UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true } else { error = "当前设备无法使用相机，请从相册选择。" } } label: { Label("拍照", systemImage: "camera") }
                    Button { Task { await open() } } label: { Text(book == nil ? "开始记录" : "继续制作").padding(.vertical, 16).frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(.primary)
                }.font(.subheadline)
            }.padding(20)
        }
    }

    private func reload() async {
        do {
            books = try await DiaryDocumentStore(ownerID: ownerID).listBooks().filter { $0.defaultPageSize == size }
            book = books.first { $0.id == book?.id } ?? books.first
            if !(book?.contentPages.contains { $0.id == pageID } ?? false) { pageID = book?.contentPages.last?.id }
            await refreshPreview()
        } catch { self.error = error.localizedDescription }
    }
    private func createBook() async {
        do { book = try await DiaryDocumentStore(ownerID: ownerID).createBook(title: "旅行随记", preset: .spread); pageID = nil; await newPage(); await reload() }
        catch { self.error = error.localizedDescription }
    }
    private func newPage() async {
        if book == nil { await createBook(); return }
        busy = true; defer { busy = false }
        do {
            var document = DiaryDocument(); document.bookID = book?.id
            document.objects[document.rootContentID]?.referenceSize = size
            try await store.save(document); pageID = document.id
            await reload()
        } catch { self.error = error.localizedDescription }
    }
    private func session() async throws -> DiaryEditorSession {
        guard let pageID else { throw DiaryEditorError.invalidDocument }
        return try await TravelCaptureSessionLoader.open(pageID: pageID, store: store)
    }
    private func open() async {
        if book == nil { await createBook() }
        busy = true; defer { busy = false }
        do { editor = try await session() } catch { self.error = error.localizedDescription }
    }
    private func submit(_ kind: String, material: UIImage, frame: DiaryPhotoFrameCatalog.Item?) async {
        guard !busy else { return }
        if book == nil { await createBook() }
        busy = true; error = nil; defer { busy = false }
        do {
            let session = try await session()
            guard let data = material.pngData() else { throw DiaryEditorError.invalidDocument }
            let success: Bool
            if kind == "背景" { success = await session.importMaterialBackground(data) }
            else if kind == "照片" { success = await session.importPhotos([data], frames: [frame]) }
            else { success = await session.importPhoto(data, asSticker: true) }
            guard success else { throw DiaryEditorError.invalidDocument }
            try await session.save()
            pendingEditor = session
            reviewPhoto = nil
            self.image = nil
            try? FileManager.default.removeItem(at: pendingURL)
            UserDefaults.standard.removeObject(forKey: captureKey)
            // 等预览关闭后再呈现已有编辑页，避免两层模态同时争用。

        } catch { self.error = kind == "贴纸" ? "暂时没能分离主体，请重试或作为照片加入。" : error.localizedDescription }
    }
    private func refreshPreview() async {
        preview = nil
        guard let page = book?.contentPages.first(where: { $0.id == pageID }) else { return }
        preview = try? await DiaryPreviewService.image(page: page, store: store, large: true)
    }
}

private struct TravelCaptureCamera: UIViewControllerRepresentable {
    var complete: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(complete: complete) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let complete: (UIImage?) -> Void
        init(complete: @escaping (UIImage?) -> Void) { self.complete = complete }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { complete(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { complete(info[.originalImage] as? UIImage) }
    }
}

/// 加载和保存必须共享同一实例，保留 load 记录的乐观并发版本基线。
@MainActor
enum TravelCaptureSessionLoader {
    static func open(pageID: UUID, store: DiaryDocumentStore) async throws -> DiaryEditorSession {
        let loaded = try await store.load(pageID)
        return DiaryEditorSession(document: loaded.document, images: loaded.images, store: store)
    }
}
