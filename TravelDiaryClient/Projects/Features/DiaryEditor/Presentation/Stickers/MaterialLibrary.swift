import SwiftUI
import CryptoKit

nonisolated struct CloudMaterialLibrary: Codable, Identifiable {
    let id: String
    let template_id: String
    let title: String
    let type: String
    let series: String
    let version: Int
    let count: Int
    var favorite_count: Int
    var is_favorited: Bool
}
nonisolated struct CloudMaterial: Codable, Identifiable {
    let id: String
    let revision: Int
    let name: String
    let keywords: [String]
    let aliases: [String]
    let kind: String
    let subcategory: String
    let thumbnail_sha256: String
    let thumbnail_url: String
    let sha256: String
    let byte_size: Int
    var favorite_count: Int
    var is_favorited: Bool
}
nonisolated struct MaterialCategory: Decodable {
    struct Subcategory: Decodable, Identifiable { let id: String; let title: String }
    let kind: String
    let title: String
    let subcategories: [Subcategory]
}
nonisolated struct MaterialPage: Decodable { let version: Int; let items: [CloudMaterial]; let next: Int? }
nonisolated struct MaterialDownload: Decodable { let url: String; let sha256: String; let byte_size: Int }
nonisolated struct MaterialFavoriteResult: Decodable { let is_favorited: Bool; let favorite_count: Int }

@MainActor
final class MaterialCatalogRepository {
    static let shared = MaterialCatalogRepository()
    var engine: SupportNetworkEngine?
    private(set) var owner = ""
    func activate(_ owner: String) { self.owner = owner }
    static func networkRequest(_ path: String, body: [String: Bool]? = nil, method: SupportHTTPMethod? = nil) throws -> SupportNetworkRequest {
        guard let parts = URLComponents(string: path), parts.scheme == nil, parts.host == nil, parts.fragment == nil else { throw URLError(.badURL) }
        return SupportNetworkRequest(method: method ?? (body == nil ? .get : .post),
            path: "/api/v1/materials/" + parts.path, queryItems: parts.queryItems,
            body: body.map { .json(AnyEncodable($0)) } ?? .none,
            strategy: NetworkStrategy(requiresAuth: true))
    }
    func request<T: Decodable>(_ path: String, body: [String: Bool]? = nil, method: SupportHTTPMethod? = nil) async throws -> T {
        guard let engine else { throw URLError(.userAuthenticationRequired) }
        let cacheable = (method ?? (body == nil ? .get : .post)) == .get
        let capturedOwner = owner
        let key = SHA256.hash(data: Data((owner + "|" + path).utf8)).map { String(format: "%02x", $0) }.joined()
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MaterialCatalog")
        let cache = root.appendingPathComponent(key)
        do {
            let response = try await engine.sendRaw(Self.networkRequest(path, body: body, method: method))
            guard owner == capturedOwner else { throw CancellationError() }
            let result = try JSONDecoder().decode(T.self, from: response.data)
            if cacheable {
                try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try? response.data.write(to: cache, options: .atomic)
            }
            return result
        } catch let error as URLError where cacheable && [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost].contains(error.code) {
            guard owner == capturedOwner, let data = try? Data(contentsOf: cache) else { throw error }
            return try JSONDecoder().decode(T.self, from: data)
        }
    }
}

struct MaterialLibraryBrowser: View {
    var session: DiaryEditorSession? = nil
    var replacingID: UUID? = nil
    var templateID: String? = nil
    var templateVersion: Int? = nil
    var type = "sticker"
    @Environment(\.dismiss) private var dismiss
    /// The editor keeps its native sheet open for consecutive additions.
    var keepsOpenAfterAdding = false
    static let compactHeight: CGFloat = 260
    static let compactDetent: PresentationDetent = .height(compactHeight)
    @State private var sheetDetent: PresentationDetent = compactDetent
    @State private var localFavorites: [String] = []
    @State private var localRecent: [String] = []
    @State private var progress: Double = 0
    @State private var addition: Task<Void, Never>?
    @State private var generation = UUID()
    @State private var query = ""
    @State private var kind = ""
    @State private var subcategory = ""
    @State private var taxonomy: [MaterialCategory] = []
    @State private var pausedItem: CloudMaterial?
    @State private var items: [CloudMaterial] = []
    @State private var cursor: Int?
    @State private var loading = false
    @State private var error: String?
    @State private var adding = false
    @State private var preview: CloudMaterial?
    @State private var requestID = UUID()
    private var isLocal: Bool { kind == "builtin" }
    private var title: String { type == "background" ? "背景" : "贴纸" }
    private var categories: [(String, String)] {
        var result = [("", "全部")] + taxonomy
            .filter { ($0.kind == "background") == (type == "background") }
            .map { ($0.kind, $0.title) }
        if type == "sticker", session != nil { result.append(("builtin", "内置")) }
        return result
    }
    private var filterKey: String { query + "|" + kind + "|" + subcategory }

    var body: some View {
        VStack(spacing: 6) {
            DiaryLibrarySearch(text: $query, prompt: "搜索\(title)")
                .padding(.horizontal, 16).padding(.top, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.0) { entry in
                        DiaryLibraryChip(title: entry.1, selected: kind == entry.0, compact: true) {
                            kind = entry.0; subcategory = ""
                        }
                    }
                }.padding(.horizontal, 16)
            }.frame(height: 44)
            if let category = taxonomy.first(where: { $0.kind == kind }), !category.subcategories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        DiaryLibraryChip(title: "全部", selected: subcategory.isEmpty, compact: true) { subcategory = "" }
                        ForEach(category.subcategories) { sub in
                            DiaryLibraryChip(title: sub.title, selected: subcategory == sub.id, compact: true) { subcategory = sub.id }
                        }
                    }.padding(.horizontal, 16)
                }.frame(height: 44)
            }
            if let error {
                DiaryLibraryNotice(message: error) {
                    Task { await loadCategories(); await loadItems(more: false) }
                }.padding(.horizontal, 16)
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                    if isLocal {
                        ForEach(DiaryStickerCatalog.items.filter {
                            query.isEmpty || ($0.title + $0.category).localizedCaseInsensitiveContains(query)
                        }) { item in
                            Button { addition = Task { await addLocal(item) } } label: {
                                VStack(spacing: 6) {
                                    if let image = item.image() {
                                        Image(uiImage: image).resizable().scaledToFit()
                                            .frame(height: 84).frame(maxWidth: .infinity)
                                            .padding(6)
                                            .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                                    }
                                    Text(item.title).font(.caption2).lineLimit(1)
                                }
                            }.buttonStyle(.plain).disabled(adding)
                            .contextMenu {
                                Button(localFavorites.contains(item.id) ? "取消收藏" : "收藏") {
                                    if localFavorites.contains(item.id) { localFavorites.removeAll { $0 == item.id } }
                                    else { localFavorites.append(item.id) }
                                    saveLocalPreferences()
                                }
                            }
                        }
                    } else {
                        ForEach(items) { item in
                            materialCell(item)
                        }
                    }
                }.padding(.horizontal, 16)
                if !isLocal {
                    if cursor != nil {
                        Button("加载更多") { Task { await loadItems(more: true) } }
                            .disabled(loading).padding(.vertical, 12)
                    }
                    if loading { ProgressView().padding() }
                    if !loading && items.isEmpty {
                        ContentUnavailableView("暂无素材", systemImage: "square.grid.2x2",
                            description: Text("试试其他分类或搜索词"))
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            DiaryEditorToolFooter(title: title, onBack: { dismiss() }, onDone: { dismiss() })
        }
        .interactiveDismissDisabled(true) // 重点：禁止下拉关闭
        .foregroundStyle(DiaryLibraryStyle.ink)
        .tint(DiaryLibraryStyle.accent)
        .background(DiaryLibraryStyle.background)
        // The shared footer supplies the clearance above the home indicator.
        // Extend the layout as well as its background to avoid a second bottom inset.
        .ignoresSafeArea(.container, edges: .bottom)
        .presentationBackground(DiaryLibraryStyle.background)
        .presentationDetents([Self.compactDetent, .fraction(0.66)], selection: $sheetDetent)
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(keepsOpenAfterAdding ? .enabled(upThrough: Self.compactDetent) : .disabled)
        .task {
            if let session {
                localFavorites = UserDefaults.standard.stringArray(forKey: session.store.stickerPreferenceKey + ".favorites") ?? []
                localRecent = UserDefaults.standard.stringArray(forKey: session.store.stickerPreferenceKey + ".recent") ?? []
            }
            await loadCategories()
        }
        .onDisappear { generation = UUID(); addition?.cancel() }
        .task(id: filterKey) {
            do { try await Task.sleep(for: .milliseconds(300)); await loadItems(more: false) } catch { }
        }
        .sheet(item: $preview) { item in
            VStack(spacing: 12) {
                MaterialThumbnail(item: item)
                Text(item.name)
                Text("\(item.favorite_count) 人收藏")
                Text(item.keywords.joined(separator: " · ")).font(.caption)
                Button(item.is_favorited ? "取消收藏" : "收藏") {
                    Task { await favoriteItem(item); preview = nil }
                }
            }.padding().presentationDetents([.medium])
        }
    }

    private func materialCell(_ item: CloudMaterial) -> some View {
        VStack(spacing: 6) {
            Button {
                if session == nil { preview = item }
                else { addition = Task { await add(item) } }
            } label: {
                VStack(spacing: 6) {
                    MaterialThumbnail(item: item)
                        .frame(height: 84).frame(maxWidth: .infinity).padding(6)
                        .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(alignment: .topTrailing) {
                            if item.is_favorited {
                                Image(systemName: "heart.fill").font(.caption2)
                                    .foregroundStyle(DiaryLibraryStyle.accent).padding(5)
                            }
                        }
                        .overlay {
                            if adding && pausedItem?.id == item.id {
                                VStack(spacing: 4) {
                                    ProgressView(value: progress)
                                    Text(progress >= 1 ? "正在添加…" : "\(Int(progress * 100))%")
                                        .font(.caption2)
                                }.padding(8).background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    Text(item.name).font(.caption2).lineLimit(1)
                }
            }.buttonStyle(.plain).disabled(adding)
            .contextMenu {
                Button(item.is_favorited ? "取消收藏" : "收藏贴纸") { Task { await favoriteItem(item) } }
                Button("查看详情") { preview = item }
            }
            if pausedItem?.id == item.id {
                if adding {
                    HStack {
                        Button("暂停") { generation = UUID(); addition?.cancel(); adding = false }
                        Button("取消") { generation = UUID(); addition?.cancel(); adding = false; pausedItem = nil }
                    }.font(.caption2)
                } else {
                    Button("继续添加") { addition = Task { await add(item) } }.font(.caption2)
                }
            }
        }
    }

    private func loadCategories() async {
        do {
            taxonomy = try await MaterialCatalogRepository.shared.request("categories/")
        } catch { self.error = error.localizedDescription }
    }
    private func loadItems(more: Bool) async {
        guard !isLocal else { items = []; cursor = nil; loading = false; return }
        let token = UUID(); requestID = token; loading = true
        if !more { items = []; cursor = nil }
        defer { if requestID == token { loading = false } }
        do {
            var components = URLComponents(); components.queryItems = [URLQueryItem(name:"version",value:"0"),URLQueryItem(name:"q",value:query),URLQueryItem(name:"kind",value:kind),URLQueryItem(name:"subcategory",value:subcategory),URLQueryItem(name:"after",value:String(more ? cursor ?? 0 : 0))]
            components.queryItems?.append(URLQueryItem(name: "type", value: type))
            if let templateID { components.queryItems?.append(URLQueryItem(name: "template", value: templateID)) }
            if let templateVersion { components.queryItems?.append(URLQueryItem(name: "template_version", value: String(templateVersion))) }
            let path = "items/?"
            let page: MaterialPage = try await MaterialCatalogRepository.shared.request(path + (components.percentEncodedQuery ?? ""))
            try Task.checkCancellation()
            guard token == requestID else { return }
            items = more ? items + page.items : page.items; cursor = page.next; error = nil
        } catch { if token == requestID && !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func favoriteItem(_ item: CloudMaterial) async {
        do {
            let r: MaterialFavoriteResult = try await MaterialCatalogRepository.shared.request("items/\(item.id)/favorite/",body:["favorite":!item.is_favorited])
            if let i = items.firstIndex(where: {$0.id == item.id}) { items[i].is_favorited = r.is_favorited; items[i].favorite_count = r.favorite_count }
        } catch { self.error = error.localizedDescription }
    }
    private func saveLocalPreferences() {
        guard let session else { return }
        UserDefaults.standard.set(localFavorites, forKey: session.store.stickerPreferenceKey + ".favorites")
        UserDefaults.standard.set(localRecent, forKey: session.store.stickerPreferenceKey + ".recent")
    }
    private func finishAdding() {
        if keepsOpenAfterAdding {
            withAnimation { sheetDetent = Self.compactDetent }
        } else { dismiss() }
    }
    private func addLocal(_ item: DiaryStickerItem) async {
        guard !adding, let session, let data = item.image()?.pngData() else { return }
        adding = true; defer { adding = false }
        if await session.importPhoto(data, replacing: replacingID, asSticker: true, stickerName: item.title) {
            localRecent.removeAll { $0 == item.id }; localRecent.insert(item.id, at: 0); localRecent = Array(localRecent.prefix(30))
            saveLocalPreferences(); finishAdding()
        } else { error = session.errorMessage }
    }
    private func add(_ item: CloudMaterial) async {
        guard !adding, let session else { return }
        adding = true; progress = 0; pausedItem = item; error = nil
        let intent = UUID(); generation = intent
        defer { if generation == intent { adding = false } }
        let owner = MaterialCatalogRepository.shared.owner
        do {
            let data = try await PresetDownloadManager.shared.materialData(item) { value in if generation == intent { progress = value } }
            try Task.checkCancellation()
            guard generation == intent, MaterialCatalogRepository.shared.owner == owner else { throw CancellationError() }
            let imported: Bool
            if let replacingID {
                imported = await session.importPhoto(data, replacing: replacingID)
            } else if type == "background" {
                imported = await session.importMaterialBackground(data, name: item.name)
            } else {
                imported = await session.importPhoto(data, asSticker: true, stickerName: item.name, semanticKind: DiaryLayerSemanticKind(rawValue: item.kind))
            }
            if imported { pausedItem = nil; finishAdding() }
            else { error = session.errorMessage }
        } catch { if generation == intent && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

actor MaterialThumbnailCache {
    static let shared = MaterialThumbnailCache()
    func cachedOriginal(_ item: CloudMaterial) -> Data? {
        guard item.thumbnail_sha256 == item.sha256, item.sha256.count == 64,
              item.sha256.allSatisfy({ $0.isHexDigit }) else { return nil }
        let path = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MaterialThumbnails").appendingPathComponent(item.sha256)
        guard let data = try? Data(contentsOf: path), data.count == item.byte_size,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == item.sha256 else { return nil }
        return data
    }
    func load(_ item: CloudMaterial) async throws -> Data {
        guard item.thumbnail_sha256.count == 64, item.thumbnail_sha256.allSatisfy({ $0.isHexDigit }) else { throw URLError(.badURL) }
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MaterialThumbnails")
        let path = root.appendingPathComponent(item.thumbnail_sha256)
        if let data = try? Data(contentsOf: path) { return data }
        guard let url = URL(string: item.thumbnail_url), url.scheme == "https", url.host?.hasSuffix(".aliyuncs.com") == true else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 2_000_000,
              SHA256.hash(data: data).map({String(format: "%02x", $0)}).joined() == item.thumbnail_sha256 else { throw URLError(.badServerResponse) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: path, options: .atomic)
        return data
    }
}

private struct MaterialThumbnail: View {
    let item: CloudMaterial
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if failed { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
            else { ProgressView() }
        }.task(id: item.thumbnail_sha256) {
            do {
                let data = try await MaterialThumbnailCache.shared.load(item)
                try Task.checkCancellation()
                image = UIImage(data: data)
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}


/// Local/cached and remote preset readers share the same material entry points.
struct PresetMaterialLibraryLinks: View {
    let templateID: String
    let templateVersion: Int
    private enum LibraryType: String, Identifiable {
        case sticker, background
        var id: String { rawValue }
    }
    @State private var selection: LibraryType?
    var body: some View {
        HStack {
            Button("贴纸库") { selection = .sticker }
            Button("背景库") { selection = .background }
        }.padding(.top)
        .sheet(item: $selection) { type in
            if UUID(uuidString: templateID) != nil {
                MaterialLibraryBrowser(templateID: templateID, templateVersion: templateVersion, type: type.rawValue)
            } else {
                ContentUnavailableView("暂无关联素材库", systemImage: "square.grid.2x2",
                    description: Text("这本内置模板尚未关联云端素材库。"))
                    .presentationDetents([.medium])
            }
        }
    }
}
