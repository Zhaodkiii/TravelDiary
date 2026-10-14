import SwiftUI
import PhotosUI
import PencilKit

/// 手帐入口：系统选图成功后直接创建文档并进入编辑器，不要求先填写作品信息。
struct DiaryEditorHomeView: View {
    let ownerID: String
    @State private var photoItem: PhotosPickerItem?
    @State private var editor: DiaryEditorSession?
    @State private var store: DiaryDocumentStore?
    @State private var latestID: UUID?
    @State private var isLoading = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "book.pages").font(.system(size: 64)).foregroundStyle(.tint)
            Text("从一张照片开始手帐").font(.title2.bold())
            Text("选择手机中的照片，添加文字、贴纸和手绘。")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("选择照片，开始编辑", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || store == nil)
            if let latestID {
                Button("继续上次的手帐") { Task { await reopen(latestID) } }
                    .disabled(isLoading)
            }
            if isLoading { ProgressView("正在读取照片和准备画布…") }
            Spacer()
        }
        .padding(28)
        .task(id: ownerID) {
            let newStore = DiaryDocumentStore(ownerID: ownerID)
            store = newStore
            latestID = try? await newStore.latestID()
        }
        .onChange(of: photoItem) { _, item in
            guard let item, let store else { return }
            Task { await createEditor(item, store: store) }
        }
        .fullScreenCover(item: $editor, onDismiss: {
            Task { if let store { latestID = try? await store.latestID() } }
        }) { session in
            DiaryEditorScreen(session: session)
        }
        .alert("手帐", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("确定") { message = nil }
        } message: { Text(message ?? "") }
    }

    @MainActor
    private func createEditor(_ item: PhotosPickerItem, store: DiaryDocumentStore) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw DiaryEditorError.invalidImage }
            var document = DiaryDocument()
            let (asset, image) = try await store.importImage(data, documentID: document.id)
            document.assets[asset.id] = asset
            document.page.layers = [DiaryLayer.photoGroup(asset: asset)]
            let drawing = PKDrawing()
            // 文档首次完整落盘后才展示编辑器，避免选图成功但作品没有可恢复入口。
            try await store.save(document, drawing: drawing.dataRepresentation())
            latestID = document.id
            editor = DiaryEditorSession(document: document, images: [asset.id: image], store: store)
        } catch { message = error.localizedDescription }
    }

    @MainActor
    private func reopen(_ id: UUID) async {
        guard let store, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await store.load(id)
            editor = DiaryEditorSession(document: loaded.document, images: loaded.images,
                                        drawing: try PKDrawing(data: loaded.drawing), store: store)
        } catch { message = error.localizedDescription }
    }
}
