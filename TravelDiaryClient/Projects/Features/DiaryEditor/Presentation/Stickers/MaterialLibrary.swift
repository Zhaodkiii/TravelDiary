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
    static func networkRequest(_ path: String, body: [String: Bool]? = nil) throws -> SupportNetworkRequest {
        guard let parts = URLComponents(string: path), parts.scheme == nil, parts.host == nil, parts.fragment == nil else { throw URLError(.badURL) }
        return SupportNetworkRequest(method: body == nil ? .get : .post,
            path: "/api/v1/materials/" + parts.path, queryItems: parts.queryItems,
            body: body.map { .json(AnyEncodable($0)) } ?? .none,
            strategy: NetworkStrategy(requiresAuth: true))
    }
    func request<T: Decodable>(_ path: String, body: [String: Bool]? = nil) async throws -> T {
        guard let engine else { throw URLError(.userAuthenticationRequired) }
        let capturedOwner = owner
        let key = SHA256.hash(data: Data((owner + "|" + path).utf8)).map { String(format: "%02x", $0) }.joined()
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MaterialCatalog")
        let cache = root.appendingPathComponent(key)
        do {
            let response = try await engine.sendRaw(Self.networkRequest(path, body: body))
            guard owner == capturedOwner else { throw CancellationError() }
            let result = try JSONDecoder().decode(T.self, from: response.data)
            if body == nil {
                try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try? response.data.write(to: cache, options: .atomic)
            }
            return result
        } catch let error as URLError where body == nil && [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost].contains(error.code) {
            guard owner == capturedOwner, let data = try? Data(contentsOf: cache) else { throw error }
            return try JSONDecoder().decode(T.self, from: data)
        }
    }
}

struct MaterialLibraryBrowser: View {
    var session: DiaryEditorSession? = nil
    var templateID: String? = nil
    var templateVersion: Int? = nil
    var type = "sticker"
    @Environment(\.dismiss) private var dismiss
    @State private var libraries: [CloudMaterialLibrary] = []
    @State private var selected: String = ""
    @State private var scope = "all"
    @State private var sourceTemplates: Set<String> = []
    @State private var localFavorites: [String] = []
    @State private var localRecent: [String] = []
    @State private var progress: Double = 0
    @State private var addition: Task<Void, Never>?
    @State private var generation = UUID()
    @State private var fitBackground = false
    @State private var query = ""
    @State private var onlyFavorites = false
    @State private var kind = ""
    @State private var subcategory = ""
    @State private var taxonomy: [MaterialCategory] = []
    @State private var pausedItem: CloudMaterial?
    @State private var backgroundOwner: String?
    @State private var items: [CloudMaterial] = []
    @State private var cursor: Int?
    @State private var loading = false
    @State private var error: String?
    @State private var adding = false
    @State private var preview: CloudMaterial?
    @State private var backgroundData: Data?
    @State private var requestID = UUID()
    private var current: CloudMaterialLibrary? { libraries.first { $0.id == selected } }
    private var displayedLibraries: [CloudMaterialLibrary] { libraries.filter { (scope != "favorites" || $0.is_favorited) && (scope != "current" || sourceTemplates.contains($0.template_id)) } }
    private var categories: [(String, String)] { [("", "全部")] + taxonomy.filter { ($0.kind == "background") == (type == "background") }.map { ($0.kind, $0.title) } }

    private var filterKey: String { selected + "|" + query + "|" + kind + "|" + scope + "|" + String(onlyFavorites) + "|" + subcategory }
    var body: some View {
        VStack(spacing: 12) {
            HStack { Text(type == "background" ? "背景库" : "贴纸库").font(.headline); Spacer(); Button("关闭") { dismiss() } }.padding(.horizontal)
            Picker("来源", selection: $scope) { Text("发现").tag("all"); Text("我的库").tag("favorites"); if session != nil { Text("当前手帐").tag("current") }; if type == "sticker" && session != nil { Text("内置").tag("local") } }.pickerStyle(.segmented).padding(.horizontal)
            ScrollView(.horizontal) {
                HStack { if scope != "local" { Button("全部库") { selected = "" } }; ForEach(displayedLibraries) { lib in Button { selected = lib.id } label: {
                    VStack { Text(lib.title); Text("\(lib.favorite_count) 人收藏 · \(lib.count) 项").font(.caption) }
                        .padding(8).background(selected == lib.id ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                } } }.padding(.horizontal)
            }
            if scope != "local" {
            if let lib = current {
                Button(lib.is_favorited ? "已收藏此库" : "收藏此库") { Task { await favoriteLibrary(lib) } }

            }
                if scope != "local" {
                    ScrollView(.horizontal) { HStack { ForEach(categories, id: \.0) { entry in
                        Button(entry.1) { kind = entry.0; subcategory = "" }.buttonStyle(.bordered).tint(kind == entry.0 ? .accentColor : .gray)
                    } }.padding(.horizontal) }
                }
            }
            Toggle("只看收藏单张", isOn: $onlyFavorites).padding(.horizontal)
            if let category = taxonomy.first(where: { $0.kind == (type == "background" ? "background" : kind) }), scope != "local" {
                ScrollView(.horizontal) { HStack {
                    Button("全部子类") { subcategory = "" }
                    ForEach(category.subcategories) { sub in Button(sub.title) { subcategory = sub.id }.buttonStyle(.bordered).tint(subcategory == sub.id ? .accentColor : .gray) }
                }.padding(.horizontal) }
            }
            TextField("搜索名称、别名、关键词", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal)
            if let error { Text(error).foregroundStyle(.red); Button("重试") { Task { await loadLibraries() } } }
            ScrollView {
                if scope == "local" {
                    Picker("内置范围", selection: $kind) { Text("全部").tag(""); Text("收藏").tag("favorite"); Text("最近").tag("recent") }.pickerStyle(.segmented).padding(.horizontal)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))]) {
                        ForEach(DiaryStickerCatalog.items.filter { item in
                            (query.isEmpty || (item.title + item.category).localizedCaseInsensitiveContains(query)) &&
                            (kind != "favorite" || localFavorites.contains(item.id)) && (kind != "recent" || localRecent.contains(item.id))
                        }) { item in
                            Button { addition = Task { await addLocal(item) } } label: {
                                VStack { if let image = item.image() { Image(uiImage: image).resizable().scaledToFit().frame(height: 80) }; Text(item.title).font(.caption) }
                            }.contextMenu { Button(localFavorites.contains(item.id) ? "取消收藏" : "收藏") {
                                if localFavorites.contains(item.id) { localFavorites.removeAll { $0 == item.id } } else { localFavorites.append(item.id) }
                                saveLocalPreferences()
                            } }
                        }
                    }.padding(.horizontal)
                } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))]) {
                    ForEach(items) { item in
                        Button { if session == nil { preview = item } else { addition = Task { await add(item) } } } label: {
                            VStack {
                                MaterialThumbnail(item: item)
                                    .frame(height: 90)
                                Text(item.name).font(.caption).lineLimit(2)
                                if item.is_favorited { Image(systemName: "heart.fill").foregroundStyle(.pink) }
                            }.frame(maxWidth: .infinity).padding(6)
                        }.buttonStyle(.plain).contextMenu {
                            Button(item.is_favorited ? "取消收藏" : "收藏贴纸") { Task { await favoriteItem(item) } }
                            Button("查看详情") { preview = item }
                        }
                    }
                }.padding(.horizontal)
                if cursor != nil { Button("加载更多") { Task { await loadItems(more: true) } }.disabled(loading) }
                if loading { ProgressView() }
                if !loading && items.isEmpty { ContentUnavailableView("暂无素材", systemImage: "square.grid.2x2", description: Text("选择素材库或调整搜索条件")) }
            }
            }
            if adding {
                ProgressView(value: progress) { Text("正在下载并校验素材…") }.padding(.horizontal)
                HStack {
                    Button("暂停") { generation = UUID(); addition?.cancel(); adding = false }
                    Button("取消添加") { generation = UUID(); addition?.cancel(); adding = false; pausedItem = nil }
                }
            }
            if !adding, let item = pausedItem {
                Button("继续下载：" + item.name) { addition = Task { await add(item) } }
            }
            if let data = backgroundData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().frame(height: 130)
                Toggle("完整显示（关闭则填满）", isOn: $fitBackground).padding(.horizontal)
                HStack { Button("取消预览") { backgroundData = nil }; Button("应用背景") { Task {
                    guard let session, backgroundOwner == MaterialCatalogRepository.shared.owner else { backgroundData = nil; return }
                    if await session.importMaterialBackground(data, fit: fitBackground) { dismiss() } else { error = session.errorMessage }
                } } }
            }
        }.padding(.vertical)
        .presentationDetents([.medium, .large])
        .task {
            if let session {
                localFavorites = UserDefaults.standard.stringArray(forKey: session.store.stickerPreferenceKey + ".favorites") ?? []
                localRecent = UserDefaults.standard.stringArray(forKey: session.store.stickerPreferenceKey + ".recent") ?? []
                if let book = try? await session.store.loadBook() { sourceTemplates = Set(book.pages.compactMap { $0.presetSource?.bookID }) }
            }
            await loadLibraries()
        }
        .onDisappear { generation = UUID(); addition?.cancel() }
        .task(id: filterKey) {
            do { try await Task.sleep(for: .milliseconds(300)); await loadItems(more: false) } catch { }
        }
        .onChange(of: scope) { _, _ in kind = ""; selected = displayedLibraries.first?.id ?? "" }
        .sheet(item: $preview) { item in VStack {
            MaterialThumbnail(item: item)
            Text(item.name); Text("\(item.favorite_count) 人收藏"); Text(item.keywords.joined(separator: " · ")).font(.caption)
            Button(item.is_favorited ? "取消收藏" : "收藏") { Task { await favoriteItem(item); preview = nil } }
        }.padding().presentationDetents([.medium]) }
    }
    private func loadLibraries() async {
        do {
            let suffix = (templateID.map { "&template=\($0)" } ?? "") + (templateVersion.map { "&template_version=\($0)" } ?? "")
            taxonomy = try await MaterialCatalogRepository.shared.request("categories/")
            libraries = try await MaterialCatalogRepository.shared.request("libraries/?type=\(type)" + suffix)
            if !libraries.contains(where: { $0.id == selected }) { selected = libraries.first?.id ?? "" }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func loadItems(more: Bool) async {
        guard scope != "local" else { items = []; cursor = nil; return }
        let lib = current
        let token = UUID(); requestID = token; loading = true
        if !more { items = []; cursor = nil }
        defer { if requestID == token { loading = false } }
        do {
            var components = URLComponents(); components.queryItems = [URLQueryItem(name:"version",value:String(lib?.version ?? 0)),URLQueryItem(name:"q",value:query),URLQueryItem(name:"kind",value:kind),URLQueryItem(name:"subcategory",value:subcategory),URLQueryItem(name:"after",value:String(more ? cursor ?? 0 : 0))]
            if onlyFavorites { components.queryItems?.append(URLQueryItem(name: "favorites", value: "1")) }
            components.queryItems?.append(URLQueryItem(name: "type", value: type))
            if scope == "favorites" { components.queryItems?.append(URLQueryItem(name: "scope", value: "libraries")) }
            if let templateID { components.queryItems?.append(URLQueryItem(name: "template", value: templateID)) }
            if scope == "current", lib == nil {
                let ids = sourceTemplates.filter { UUID(uuidString: $0) != nil }
                if ids.isEmpty { items = []; cursor = nil; return }
                components.queryItems?.append(URLQueryItem(name: "template_ids", value: ids.sorted().joined(separator: ",")))
            }
            let path = lib.map { "libraries/\($0.id)/items/?" } ?? "items/?"
            let page: MaterialPage = try await MaterialCatalogRepository.shared.request(path + (components.percentEncodedQuery ?? ""))
            try Task.checkCancellation()
            guard token == requestID else { return }
            items = more ? items + page.items : page.items; cursor = page.next; error = nil
        } catch { if token == requestID && !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func favoriteLibrary(_ lib: CloudMaterialLibrary) async {
        do {
            let r: MaterialFavoriteResult = try await MaterialCatalogRepository.shared.request("libraries/\(lib.id)/favorite/",body:["favorite":!lib.is_favorited])
            if let i = libraries.firstIndex(where: {$0.id == lib.id}) { libraries[i].is_favorited = r.is_favorited; libraries[i].favorite_count = r.favorite_count }
            if scope == "favorites" && !r.is_favorited { selected = "" }
        } catch { self.error = error.localizedDescription }
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
    private func addLocal(_ item: DiaryStickerItem) async {
        guard !adding, let session, let data = item.image()?.pngData() else { return }
        adding = true; defer { adding = false }
        if await session.importPhoto(data, asSticker: true, stickerName: item.title) {
            localRecent.removeAll { $0 == item.id }; localRecent.insert(item.id, at: 0); localRecent = Array(localRecent.prefix(30))
            saveLocalPreferences(); dismiss()
        } else { error = session.errorMessage }
    }
    private func add(_ item: CloudMaterial) async {
        guard !adding, let session else { return }
        adding = true; progress = 0; pausedItem = item
        let intent = UUID(); generation = intent
        defer { if generation == intent { adding = false } }
        let owner = MaterialCatalogRepository.shared.owner
        do {
            let data = try await PresetDownloadManager.shared.materialData(item) { value in if generation == intent { progress = value } }
            try Task.checkCancellation()
            guard generation == intent, MaterialCatalogRepository.shared.owner == owner else { throw CancellationError() }
            if type == "background" { backgroundData = data; backgroundOwner = owner; pausedItem = nil }
            else if await session.importPhoto(data, asSticker: true, stickerName: item.name) { pausedItem = nil; dismiss() }
            else { error = session.errorMessage }
        } catch { if generation == intent && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

private actor MaterialThumbnailCache {
    static let shared = MaterialThumbnailCache()
    func load(_ item: CloudMaterial) async throws -> Data {
        guard item.thumbnail_sha256.count == 64, item.thumbnail_sha256.allSatisfy({ $0.isHexDigit }) else { throw URLError(.badURL) }
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MaterialThumbnails")
        let path = root.appendingPathComponent(item.thumbnail_sha256)
        if let data = try? Data(contentsOf: path) { return data }
        guard let url = URL(string: item.thumbnail_url), url.scheme == "https" else { throw URLError(.badURL) }
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
