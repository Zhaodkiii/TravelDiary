import SwiftUI

/// 选择器不修改图层树；成功导入才更新最近使用并关闭，取消不会产生历史。
struct DiaryStickerPickerSheet: View {
    @ObservedObject var session: DiaryEditorSession
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var category = "全部"
    @State private var recent: [String] = []
    @State private var favorites: [String] = []
    @State private var images: [String: UIImage] = [:]
    @State private var loading = true
    @State private var adding = false
    @State private var message: String?
    private let items = DiaryStickerCatalog.items
    private var preferenceKey: String { session.store.stickerPreferenceKey }
    private var filtered: [DiaryStickerItem] {
        let matches = items.filter {
            (category == "全部" || category == $0.category || (category == "最近" && recent.contains($0.id)) ||
                (category == "收藏" && favorites.contains($0.id))) &&
            (search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                ($0.title + $0.category).localizedCaseInsensitiveContains(search.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return category == "最近" ? matches.sorted { (recent.firstIndex(of: $0.id) ?? 99) < (recent.firstIndex(of: $1.id) ?? 99) } : matches
    }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索贴纸名称或分类", text: $search).submitLabel(.search)
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("清除搜索") }
            }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 24)).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(DiaryStickerCatalog.categories, id: \.self) { value in
                        Button { category = value } label: {
                            Text(value).font(.subheadline.weight(category == value ? .bold : .regular))
                                .foregroundStyle(category == value ? Color.accentColor : .primary).padding(.vertical, 8)
                        }.accessibilityAddTraits(category == value ? .isSelected : [])
                    }
                }.padding(.horizontal)
            }
            ScrollView {
                if loading { ProgressView("正在加载贴纸…") }
                else if filtered.isEmpty {
                    ContentUnavailableView(category == "收藏" ? "还没有收藏贴纸" : category == "最近" ? "还没有使用记录" : "没有匹配的贴纸",
                        systemImage: "face.smiling", description: Text("长按贴纸可收藏；也可以切换分类或清除搜索。"))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 12)], spacing: 12) {
                        ForEach(filtered) { item in
                            Button { add(item) } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemGroupedBackground))
                                    if let image = images[item.id] { Image(uiImage: image).resizable().scaledToFit().padding(8) }
                                    else { Image(systemName: "exclamationmark.triangle").frame(maxWidth: .infinity, maxHeight: .infinity) }
                                    if favorites.contains(item.id) { Image(systemName: "heart.fill").font(.caption).foregroundStyle(.pink).padding(6) }
                                }.aspectRatio(1, contentMode: .fit)
                            }.buttonStyle(.plain).disabled(images[item.id] == nil)
                                .accessibilityLabel(item.title).accessibilityHint("添加到当前对象，长按可收藏")
                                .contextMenu { Button(favorites.contains(item.id) ? "取消收藏" : "收藏", systemImage: "heart") { toggleFavorite(item.id) } }
                        }
                    }.padding(.horizontal)
                }
            }.scrollDismissesKeyboard(.interactively)
            HStack {
                Button("关闭") { dismiss() }
                Spacer()
                Text(adding ? "正在添加…" : "贴纸").font(.headline)
                Spacer()
                Text("点击添加").font(.caption).foregroundStyle(.secondary)
            }.padding().background(.bar)
        }
        .padding(.top, 20)
        .disabled(adding).interactiveDismissDisabled(adding)
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .task {
            recent = UserDefaults.standard.stringArray(forKey: preferenceKey + ".recent") ?? []
            favorites = UserDefaults.standard.stringArray(forKey: preferenceKey + ".favorites") ?? []
            for item in items { images[item.id] = item.image() }
            loading = false
        }
        .alert("无法添加贴纸", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("确定", role: .cancel) { }
        } message: { Text(message ?? "") }
    }
    private func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.removeAll { $0 == id } } else { favorites.append(id) }
        UserDefaults.standard.set(favorites, forKey: preferenceKey + ".favorites")
    }
    private func add(_ item: DiaryStickerItem) {
        guard !adding, let data = images[item.id]?.pngData() else { return }
        adding = true
        Task {
            let success = await session.importPhoto(data, asSticker: true, stickerName: item.title)
            adding = false
            if success {
                recent.removeAll { $0 == item.id }; recent.insert(item.id, at: 0); recent = Array(recent.prefix(30))
                UserDefaults.standard.set(recent, forKey: preferenceKey + ".recent")
                dismiss()
            } else { message = session.errorMessage ?? "请稍后重试。"; session.errorMessage = nil }
        }
    }
}
