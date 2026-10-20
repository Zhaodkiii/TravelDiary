import SwiftUI

struct DiaryPhotoFramePicker: View {
    @ObservedObject var session: DiaryEditorSession
    let photoID: UUID
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView { DiaryPhotoFrameGrid(session: session, photoID: photoID).padding() }
                .navigationTitle("贴纸相框")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}

struct DiaryPhotoFrameGrid: View {
    @ObservedObject var session: DiaryEditorSession
    var photoID: UUID?
    var query = ""
    @State private var applying = false
    @State private var error: String?
    private var targetID: UUID? { photoID ?? session.selectedPhotos.first?.id }
    var body: some View {
        VStack(spacing: 12) {
            if targetID == nil { Text("先在画布中选择照片，再选择相框贴纸").font(.caption).foregroundStyle(.secondary) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                Button { apply(nil) } label: {
                    VStack { Image(systemName: "rectangle.slash").frame(height: 84); Text("无相框").font(.caption) }
                        .frame(maxWidth: .infinity)
                }
                ForEach(DiaryPhotoFrameCatalog.items.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }) { item in
                    Button { apply(item) } label: {
                        VStack(spacing: 6) {
                            if let image = item.image { Image(uiImage: image).resizable().scaledToFit().frame(height: 84) }
                            Text(item.title).font(.caption2).lineLimit(1)
                        }.frame(maxWidth: .infinity)
                    }
                }
            }.buttonStyle(.plain).disabled(applying || session.busy || targetID == nil)
            if applying { ProgressView("正在应用相框…") }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }
    private func apply(_ item: DiaryPhotoFrameCatalog.Item?) {
        guard let id = targetID else { return }
        applying = true; error = nil
        Task { @MainActor in
            if !(await session.applyPhotoFrame(item, to: id)) { error = session.errorMessage ?? "无法修改这张照片的相框" }
            applying = false
        }
    }
}
