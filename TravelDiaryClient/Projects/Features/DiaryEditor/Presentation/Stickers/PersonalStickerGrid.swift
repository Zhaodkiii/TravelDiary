import SwiftUI

struct PersonalStickerGrid: View {
    var query: String
    var onCreate: () -> Void
    var onSelect: (PersonalSticker, Data) async -> Void
    @State private var items: [PersonalSticker] = []
    @State private var next: Int?
    @State private var loading = false
    @State private var error: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack {
            if let error { Text(error).foregroundStyle(.secondary); Button("重试") { Task { await load(false) } } }
            if items.isEmpty && !loading {
                ContentUnavailableView {
                    Label("把旅途里的小物，变成贴纸", systemImage: "scissors")
                } actions: { Button("制作贴纸", action: onCreate) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 2 : 4)) {
                ForEach(items) { sticker in
                    Button { Task { await select(sticker) } } label: {
                        AsyncImage(url: sticker.url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }
                            .frame(height: 88).frame(maxWidth: .infinity).padding(6)
                            .background(.background, in: RoundedRectangle(cornerRadius: 12))
                    }.disabled(loading).accessibilityLabel("添加我制作的贴纸")
                        .contextMenu { Button("从我的贴纸删除", role: .destructive) { Task { await remove(sticker) } } }
                }
            }
            if loading { ProgressView().padding() }
            if next != nil { Button("加载更多") { Task { await load(true) } }.disabled(loading) }
        }.padding(.horizontal, 16).task(id: MaterialCatalogRepository.shared.owner) { await load(false) }
    }
    private func load(_ more: Bool) async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let page = try await PersonalStickerService.list(offset: more ? next ?? 0 : 0)
            var seen = Set<String>()
            items = (more ? items + page.items : page.items).filter { seen.insert($0.id).inserted }
            next = page.next
        }
        catch { self.error = "无法加载我的贴纸，请检查登录状态或网络" }
    }
    private func select(_ sticker: PersonalSticker) async {
        loading = true; defer { loading = false }
        let owner = MaterialCatalogRepository.shared.owner
        do { let data = try await PersonalStickerService.image(sticker); guard owner == MaterialCatalogRepository.shared.owner else { return }; await onSelect(sticker, data) }
        catch { self.error = "贴纸加载失败，请刷新后重试" }
    }
    private func remove(_ sticker: PersonalSticker) async {
        do { try await PersonalStickerService.delete(sticker); items.removeAll { $0.id == sticker.id }; if let offset = next { next = max(0, offset - 1) } }
        catch { self.error = "删除失败，请重试" }
    }
}

struct PersonalStickerLibraryScreen: View {
    @State private var showMaker = false
    @State private var refreshID = UUID()
    @State private var preview: UIImage?
    var body: some View {
        ScrollView {
            PersonalStickerGrid(query: "", onCreate: { showMaker = true }) { _, data in preview = UIImage(data: data) }
                .id(refreshID).padding(.vertical)
        }
        .background(DiaryLibraryStyle.background)
        .navigationTitle("我制作的")
        .toolbar { Button("制作", systemImage: "scissors") { showMaker = true } }
        .fullScreenCover(isPresented: $showMaker) {
            StickerMakerScreen(addsToCanvas: false) { _, _ in refreshID = UUID() }
        }
        .sheet(isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })) {
            if let preview {
                VStack {
                    Image(uiImage: preview).resizable().scaledToFit().padding()
                    Text("在手帐编辑器的“我的 → 我制作的”中添加").font(.callout).padding()
                }.presentationDetents([.medium, .large])
            }
        }
    }
}
