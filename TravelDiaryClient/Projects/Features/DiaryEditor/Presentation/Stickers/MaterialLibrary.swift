import SwiftUI
import CryptoKit
import Combine

nonisolated struct CloudMaterialLibrary: Codable, Identifiable {
    let id: String
    let template_id: String?
    let title: String
    let type: String
    let series: String
    let version: Int
    let count: Int
    var favorite_count: Int
    var is_favorited: Bool
    var description: String? = nil
    var cover: MaterialImageResource? = nil
    var previews: [MaterialImageResource]? = nil
    var tags: [String]? = nil
    var availability: String? = nil
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
    var library_id: String? = nil
    var library_version: Int? = nil
    var availability: String? = nil
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
final class MaterialCatalogRepository: ObservableObject {
    @Published var changeID = UUID()
    struct PickerState {
        var source: String
        var library: CloudMaterialLibrary?
        var query: String
        var kind: String
        var subcategory: String
        var scrollID: String?
    }
    var pickerStates: [UUID:PickerState] = [:]
    @Published var pendingLibrary: CloudMaterialLibrary?
    @Published var isOffline = false
    static let shared = MaterialCatalogRepository()
    var engine: SupportNetworkEngine?
    @Published private(set) var owner = ""
    func activate(_ owner: String) { if self.owner != owner { pickerStates = [:]; pendingLibrary = nil; changeID = UUID(); isOffline = false }; self.owner = owner }
    static func networkRequest(_ path: String, body: [String: Bool]? = nil, method: SupportHTTPMethod? = nil) throws -> SupportNetworkRequest {
        guard let parts = URLComponents(string: path), parts.scheme == nil, parts.host == nil, parts.fragment == nil else { throw URLError(.badURL) }
        return SupportNetworkRequest(method: method ?? (body == nil ? .get : .post),
            path: "/api/v1/materials/" + parts.path, queryItems: parts.queryItems,
            body: body.map { .json(AnyEncodable($0)) } ?? .none,
            strategy: NetworkStrategy(requiresAuth: true))
    }
    func favoriteLibraries() async throws -> [CloudMaterialLibrary] {
        var result:[CloudMaterialLibrary]=[]
        var cursor:String?
        repeat {
            try Task.checkCancellation()
            var params=["schema":"2","type":"sticker","favorites":"1","sort":"added","limit":"100"]
            if let cursor { params["cursor"]=cursor }
            let page:MaterialListPage<CloudMaterialLibrary>=try await request(MaterialRoutes.path("libraries/",params))
            result += page.items;cursor=page.next_cursor
        } while cursor != nil
        return result
    }

    func refreshPreview(resourceID: String, libraryID: String, version: Int) async throws -> MaterialImageResource {
        struct Entry: Encodable { let resource_id: String; let library_id: String; let version: Int }
        struct Body: Encodable { let resources: [Entry] }
        guard let engine else { throw URLError(.userAuthenticationRequired) }
        let captured = owner
        let request = SupportNetworkRequest(method: .post, path: "/api/v1/materials/previews/resolve/",
            body: .json(AnyEncodable(Body(resources: [Entry(resource_id:resourceID,library_id:libraryID,version:version)]))),strategy: NetworkStrategy(requiresAuth:true))
        let response = try await engine.sendRaw(request)
        guard owner == captured else { throw CancellationError() }
        guard let resource = try JSONDecoder().decode([MaterialImageResource].self,from:response.data).first else { throw URLError(.badServerResponse) }
        return resource
    }

    func downloadPlan(_ item: CloudMaterial) async throws -> MaterialDownload {
        guard let engine else { throw URLError(.userAuthenticationRequired) }
        struct Context: Encodable { let library_id: String?; let library_version: Int? }
        let account = owner
        let request = SupportNetworkRequest(method: .post, path: "/api/v1/materials/revisions/\(item.revision)/download/",
            queryItems: [URLQueryItem(name: "schema", value: "2")],
            body: .json(AnyEncodable(Context(library_id: item.library_id, library_version: item.library_version))),
            strategy: NetworkStrategy(requiresAuth: true))
        let data = try await engine.sendRaw(request)
        guard owner == account else { throw CancellationError() }
        return try JSONDecoder().decode(MaterialDownload.self, from: data.data)
    }

    func request<T: Decodable>(_ path: String, body: [String: Bool]? = nil, method: SupportHTTPMethod? = nil) async throws -> T {
        guard let engine else { throw URLError(.userAuthenticationRequired) }
        let cacheable = (method ?? (body == nil ? .get : .post)) == .get
        let capturedOwner = owner
        let key = SHA256.hash(data: Data((owner + "|" + path).utf8)).map { String(format: "%02x", $0) }.joined()
        let root = StoragePaths.system.cacheAccount(capturedOwner).appendingPathComponent("MaterialCatalog")
        let cache = root.appendingPathComponent(key)
        let cacheKey = ResourceCacheKey.account(capturedOwner, category: "material-catalog", identity: path)
        let cacheGeneration = ResourceCache.shared.generation(for: cacheKey)
        do {
            let response = try await engine.sendRaw(Self.networkRequest(path, body: body, method: method))
            guard owner == capturedOwner else { throw CancellationError() }
            let result = try JSONDecoder().decode(T.self, from: response.data)
            if cacheable {
                if ResourceCache.shared.store(response.data, for: cacheKey, expectedGeneration: cacheGeneration) != nil {
                    try? FileManager.default.removeItem(at: cache)
                }
            }
            isOffline = false
            if !cacheable { changeID = UUID() }
            return result
        } catch let error as URLError where cacheable && [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost].contains(error.code) {
            guard owner == capturedOwner, let data = ResourceCache.shared.data(for: cacheKey) ?? (try? Data(contentsOf: cache)) else { throw error }
            if ResourceCache.shared.data(for: cacheKey) == nil, FileManager.default.fileExists(atPath: cache.path) { ResourceCache.shared.register(cache, for: cacheKey) }
            isOffline = true
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
    var initialLibrary: CloudMaterialLibrary? = nil
    @Environment(\.dismiss) private var dismiss
    /// The editor keeps its native sheet open for consecutive additions.
    var keepsOpenAfterAdding = false
    static let compactHeight: CGFloat = 260
    static let compactDetent: PresentationDetent = .height(compactHeight)
    @State private var sheetDetent: PresentationDetent = compactDetent
    @ObservedObject private var catalog = MaterialCatalogRepository.shared
    @State private var source = "最近"
    @State private var selectedLibrary: CloudMaterialLibrary?
    @State private var myLibraries: [CloudMaterialLibrary] = []
    @State private var currentLibraries: [CloudMaterialLibrary] = []
    @State private var nextCursor: String?
    @State private var paginationFilter = ""
    @State private var selectedGalleryItem: CloudMaterial?
    @State private var showGallery = false
    @State private var showFilters = false
    @State private var showAllPacks = false
    @State private var searchScope = "本包"
    @State private var scrollID: String?
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

    init(session: DiaryEditorSession? = nil, replacingID: UUID? = nil,
         templateID: String? = nil, templateVersion: Int? = nil,
         type: String = "sticker", keepsOpenAfterAdding: Bool = false, initialLibrary: CloudMaterialLibrary? = nil) {
        self.session = session
        self.replacingID = replacingID
        self.templateID = templateID
        self.templateVersion = templateVersion
        self.type = type
        self.initialLibrary = initialLibrary
        _selectedLibrary = State(initialValue: initialLibrary)
        self.keepsOpenAfterAdding = keepsOpenAfterAdding
        _kind = State(initialValue: "")
    }

    private var isLocal: Bool { kind == "builtin" }
    private var title: String { type == "background" ? "背景" : "贴纸" }
    private var categories: [(String, String)] {
        var result = [("", "全部")] + taxonomy
            .filter { ($0.kind == "background") == (type == "background") }
            .map { ($0.kind, $0.title) }
        if type == "sticker", session != nil { result.append(("frames", "相框")); result.append(("builtin", "内置")) }
        return result
    }
    private var filterKey: String { query + "|" + kind + "|" + subcategory + "|" + source + "|" + (selectedLibrary?.id ?? "") + "|" + searchScope }

    var body: some View {
        VStack(spacing: 6) {
            if session != nil && type == "sticker" {
                HStack {
                    Picker("来源", selection: Binding(get: { source }, set: { value in
                        source = value; kind = ""; selectedLibrary = value == "当前手帐" ? currentLibraries.first : nil
                    })) {
                        ForEach(["最近", "当前手帐", "我的"], id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.segmented)
                    Button { showGallery = true } label: { Image(systemName: "square.grid.2x2") }.accessibilityLabel("更多贴纸")
                    Button { showFilters.toggle() } label: { Image(systemName: "line.3.horizontal.decrease") }.accessibilityLabel("分类筛选")
                }.padding(.horizontal, 16)
                if source != "最近" {
                    ScrollView(.horizontal) {
                        HStack {
                            if source == "我的" { Button("单张收藏") { selectedLibrary = nil; kind = "" } }
                            ForEach(source == "我的" ? myLibraries : currentLibraries) { lib in
                                Button { selectedLibrary = lib; kind = "" } label: {
                                    VStack(spacing: 2) {
                                        MaterialResourceImage(resource: lib.cover).frame(width: 34, height: 34)
                                        Text(lib.title).font(.caption2).lineLimit(1)
                                    }.frame(width: 65).padding(3)
                                        .background(selectedLibrary?.id == lib.id ? DiaryLibraryStyle.accent.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            if source == "我的" { Button("全部包") { showAllPacks = true } }
                            Button("内置") { kind = "builtin"; selectedLibrary = nil }
                        }.padding(.horizontal, 16)
                    }
                }
            }
            if source == "我的" && !query.isEmpty {
                Picker("搜索范围", selection: $searchScope) { Text(selectedLibrary == nil ? "单张收藏" : "本包").tag("本包"); Text("我的全部贴纸").tag("我的全部") }
                    .pickerStyle(.segmented).padding(.horizontal, 16)
            }
            if catalog.isOffline { Text("离线缓存").font(.caption).foregroundStyle(.secondary) }
            DiaryLibrarySearch(text: $query, prompt: "搜索\(title)")
                .padding(.horizontal, 16).padding(.top, 8)
            if showFilters || session == nil || type != "sticker" {
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
            }
            if let error {
                DiaryLibraryNotice(message: error) {
                    Task { await loadCategories(); await loadItems(more: false) }
                }.padding(.horizontal, 16)
            }
            ScrollView {
                if kind == "frames", let session {
                    DiaryPhotoFrameGrid(session: session, query: query).padding(.horizontal, 16)
                } else {
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
                    }.scrollTargetLayout().padding(.horizontal, 16)
                    if !isLocal {
                        if cursor != nil || nextCursor != nil {
                            DiaryPaginationFooter(token: filterKey + "|" + (nextCursor ?? cursor.map(String.init) ?? ""), loading: loading, error: error) { await loadItems(more: true) }
                        }
                        if loading { ProgressView().padding() }
                        if !loading && items.isEmpty {
                            Button("搜索全部贴纸") { showGallery = true }
                            ContentUnavailableView("暂无素材", systemImage: "square.grid.2x2",
                                description: Text("试试其他分类或搜索词"))
                        }
                    }
                }
            }
            .scrollPosition(id:$scrollID)
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
            await loadSources()
            await loadCategories()
        }
        .onChange(of: catalog.owner) { _, _ in
            generation=UUID();addition?.cancel();items=[];myLibraries=[];currentLibraries=[];selectedLibrary=nil;localFavorites=[];localRecent=[]
        }
        .onChange(of: catalog.changeID) { _, _ in Task { await loadSources(refresh: true) } }
        .sheet(isPresented: $showGallery, onDismiss: useSelectedGalleryItem) {
            NavigationStack { StickerGalleryScreen(onUse: { lib in selectedLibrary = lib; source = "我的"; kind = ""; showGallery = false }, onUseItem: { item in selectedGalleryItem = item; showGallery = false }, initialQuery:query, initialMode:query.isEmpty ? "包" : "单张").toolbar { ToolbarItem(placement:.topBarLeading) { Button("返回编辑器") { showGallery=false } } } }
        }
        .sheet(isPresented: $showAllPacks, onDismiss: useSelectedGalleryItem) {
            NavigationStack { StickerGalleryScreen(mine: true, onUse: { lib in selectedLibrary = lib; kind = ""; showAllPacks = false }, onUseItem: { item in selectedGalleryItem = item; showAllPacks = false }).toolbar { ToolbarItem(placement:.topBarLeading) { Button("返回编辑器") { showAllPacks=false } } } }
        }
        .onDisappear {
            generation = UUID(); addition?.cancel()
            if let session { catalog.pickerStates[session.id] = .init(source:source,library:selectedLibrary,query:query,kind:kind,subcategory:subcategory,scrollID:scrollID) }
        }
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
                else if item.revision == 0, let local = DiaryStickerCatalog.items.first(where: { "local."+$0.id == item.id }) { addition = Task { await addLocal(local) } }
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
            }.buttonStyle(.plain).disabled(adding || item.availability == "unavailable")
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

    private func loadSources(refresh: Bool = false) async {
        guard type == "sticker" else { return }
        do {
            myLibraries = try await catalog.favoriteLibraries()
            if let session, let book = try? await session.store.loadBook(),
               let entry = book.pages.first(where: { $0.id == session.document.id }), let origin = entry.presetSource {
                let current: MaterialListPage<CloudMaterialLibrary> = try await catalog.request(MaterialRoutes.path("libraries/", ["schema":"2", "type":"sticker", "template":origin.bookID, "template_version":String(origin.version)]))
                currentLibraries = current.items
            }
            if !refresh {
                if let initialLibrary { selectedLibrary = initialLibrary; source = "我的" }
                else if let pending = catalog.pendingLibrary { source = "我的"; selectedLibrary = pending; catalog.pendingLibrary = nil }
                else if let session, let saved=catalog.pickerStates[session.id] {
                    source=saved.source;selectedLibrary=saved.library;query=saved.query;kind=saved.kind;subcategory=saved.subcategory;scrollID=saved.scrollID
                }
                else if let first = currentLibraries.first { source = "当前手帐"; selectedLibrary = first }
                else if MaterialRecentStore.items(owner: catalog.owner).isEmpty { kind = "builtin" }
            }
            await loadItems(more: false)
        } catch { self.error = error.localizedDescription }
    }

    private func loadCategories() async {
        do {
            taxonomy = try await MaterialCatalogRepository.shared.request("categories/")
        } catch { self.error = error.localizedDescription }
    }
    private func loadItems(more: Bool) async {
        if more { guard !loading, paginationFilter == filterKey, cursor != nil || nextCursor != nil else { return } }
        else { paginationFilter = filterKey }
        if !more { cursor = nil; nextCursor = nil }
        guard !isLocal && kind != "frames" else { items = []; cursor = nil; loading = false; return }
        if type == "sticker", session != nil || selectedLibrary != nil {
            await loadStickerItems(more: more); return
        }
        let activeFilter = filterKey
        let previousCursor = more ? cursor : nil
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
            guard token == requestID, activeFilter == filterKey else { return }
            items = more ? items.appendingUnique(page.items) : page.items; cursor = page.next == previousCursor ? nil : page.next; error = nil
        } catch { if token == requestID && !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func loadStickerItems(more: Bool) async {
        let activeFilter = filterKey
        let previousCursor = more ? nextCursor : nil
        let token = UUID(); requestID = token; loading = true
        defer { if requestID == token { loading = false } }
        do {
            if source == "最近", selectedLibrary == nil {
                var recent = MaterialRecentStore.items(owner: catalog.owner)
                if !catalog.isOffline {
                    for i in recent.indices where recent[i].revision != 0 {
                        do { recent[i] = try await catalog.request("items/\(recent[i].id)/") }
                        catch let error as URLError where [.notConnectedToInternet,.networkConnectionLost,.timedOut,.cannotConnectToHost].contains(error.code) { break }
                        catch { recent[i].availability = "unavailable" }
                    }
                }
                guard requestID == token, activeFilter == filterKey, !Task.isCancelled else { return }
                MaterialRecentStore.save(recent,owner:catalog.owner)
                items = recent.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
                nextCursor = nil; error = nil; return
            }
            if source == "当前手帐", selectedLibrary == nil { items = []; nextCursor = nil; return }
            var params = ["schema":"2", "type":"sticker", "q":query, "kind":kind, "subcategory":subcategory]
            var path = "items/"
            if searchScope == "我的全部" && source == "我的" && !query.isEmpty { params["scope"] = "my" }
            else if let lib = selectedLibrary { path = "libraries/\(lib.id)/items/"; params["version"] = String(lib.version) }
            else { params["favorites"] = "1" }
            if more { params["cursor"] = nextCursor }
            let page: MaterialListPage<CloudMaterial> = try await catalog.request(MaterialRoutes.path(path, params))
            guard requestID == token, activeFilter == filterKey, !Task.isCancelled else { return }
            items = more ? items.appendingUnique(page.items) : page.items; nextCursor = page.next_cursor == previousCursor ? nil : page.next_cursor; cursor = nil; error = nil
        } catch { if requestID == token && !Task.isCancelled { self.error = error.localizedDescription } }
    }

    private func favoriteItem(_ item: CloudMaterial) async {
        if item.revision == 0 {
            let id=String(item.id.dropFirst(6))
            if localFavorites.contains(id) { localFavorites.removeAll { $0==id } } else { localFavorites.append(id) }
            saveLocalPreferences();return
        }
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
    private func useSelectedGalleryItem() {
        guard let item = selectedGalleryItem else { return }
        selectedGalleryItem = nil
        addition = Task { await add(item) }
    }
    private func addLocal(_ item: DiaryStickerItem) async {
        guard !adding, let session, session.store.ownerID == catalog.owner, let data = item.image()?.pngData() else { return }
        adding = true; defer { adding = false }
        if await session.importPhoto(data, replacing: replacingID, asSticker: true, stickerName: item.title) {
            localRecent.removeAll { $0 == item.id }; localRecent.insert(item.id, at: 0); localRecent = Array(localRecent.prefix(30))
            MaterialRecentStore.recordLocal(item,owner:catalog.owner)
            saveLocalPreferences(); finishAdding()
        } else { error = session.errorMessage }
    }
    private func add(_ item: CloudMaterial) async {
        guard !adding, let session, session.store.ownerID == catalog.owner else { return }
        adding = true; progress = 0; pausedItem = item; error = nil
        let intent = UUID(); generation = intent
        defer { if generation == intent { adding = false } }
        let owner = MaterialCatalogRepository.shared.owner
        let documentID = session.document.id
        let contentID = session.contentID
        do {
            let data = try await PresetDownloadManager.shared.materialData(item) { value in if generation == intent { progress = value } }
            try Task.checkCancellation()
            guard generation == intent, MaterialCatalogRepository.shared.owner == owner, session.acceptsMaterialInsertion(documentID: documentID, contentID: contentID, replacingID: replacingID) else { throw CancellationError() }
            let imported: Bool
            if type == "background" {
                imported = await session.importMaterialBackground(data, name: item.name)
            } else if let replacingID {
                imported = await session.importPhoto(data, replacing: replacingID,
                    canCommit: { generation == intent && catalog.owner == owner && session.acceptsMaterialInsertion(documentID: documentID, contentID: contentID, replacingID: replacingID) })
            } else {
                imported = await session.importPhoto(data, asSticker: true, stickerName: item.name,
                    semanticKind: DiaryLayerSemanticKind(rawValue: item.kind),
                    subcategory: item.subcategory, renderType: "image",
                    materialSource: DiaryMaterialSource(materialID: item.id, revision: item.revision, libraryID: item.library_id, libraryVersion: item.library_version),
                    canCommit: { generation == intent && catalog.owner == owner && session.acceptsMaterialInsertion(documentID: documentID, contentID: contentID, replacingID: replacingID) })
            }
            if imported { MaterialRecentStore.record(item, owner: owner); pausedItem = nil; finishAdding() }
            else { error = session.errorMessage }
        } catch { if generation == intent && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

actor MaterialThumbnailCache {
    static let shared = MaterialThumbnailCache()
    private var generation = 0
    private var pending: [String: Task<Data, Error>] = [:]
    private func key(_ hash: String) -> ResourceCacheKey { ResourceCacheKey(scope: "shared", category: "material-thumbnails", identity: hash) }
    func clear() throws {
        generation += 1
        for task in pending.values { task.cancel() }; pending.removeAll()
        ResourceCache.shared.clear(category: "material-thumbnails")
        let root = StoragePaths.system.cache("MaterialThumbnails")
        if FileManager.default.fileExists(atPath:root.path) { try FileManager.default.removeItem(at:root) }
    }
    func cachedOriginal(_ item: CloudMaterial) -> Data? {
        guard item.thumbnail_sha256 == item.sha256, item.sha256.count == 64,
              item.sha256.allSatisfy({ $0.isHexDigit }) else { return nil }
        let path = StoragePaths.system.cache("MaterialThumbnails").appendingPathComponent(item.sha256)
        guard let data = ResourceCache.shared.data(for: key(item.sha256)) ?? (try? Data(contentsOf: path)), data.count == item.byte_size,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == item.sha256 else { return nil }
        return data
    }
    func load(_ item: CloudMaterial) async throws -> Data {
        if let task = pending[item.thumbnail_sha256] { return try await task.value }
        let task = Task { try await self.fetch(item) }
        pending[item.thumbnail_sha256] = task
        defer { pending[item.thumbnail_sha256] = nil }
        return try await task.value
    }
    private func fetch(_ item: CloudMaterial) async throws -> Data {
        guard item.thumbnail_sha256.count == 64, item.thumbnail_sha256.allSatisfy({ $0.isHexDigit }) else { throw URLError(.badURL) }
        let root = StoragePaths.system.cache("MaterialThumbnails")
        let path = root.appendingPathComponent(item.thumbnail_sha256)
        let cacheKey = key(item.thumbnail_sha256)
        if let data = ResourceCache.shared.data(for: cacheKey), SHA256.hash(data: data).map({String(format: "%02x", $0)}).joined() == item.thumbnail_sha256 { return data }
        if let data = try? Data(contentsOf: path), SHA256.hash(data: data).map({String(format: "%02x", $0)}).joined() == item.thumbnail_sha256 {
            ResourceCache.shared.register(path, for: cacheKey)
            return data
        }
        guard let url = URL(string: item.thumbnail_url), url.scheme == "https", url.host?.hasSuffix(".aliyuncs.com") == true else { throw URLError(.badURL) }
        let started = generation
        let cacheGeneration = ResourceCache.shared.generation(for: cacheKey)
        var (data, response) = try await ResourceDownloadSession.shared.data(from: url)
        if (response as? HTTPURLResponse)?.statusCode == 403, let libraryID = item.library_id, let version = item.library_version {
            let refreshed = try await MaterialCatalogRepository.shared.refreshPreview(resourceID: item.thumbnail_sha256, libraryID: libraryID, version: version)
            guard let refreshedURL = URL(string: refreshed.url), refreshedURL.scheme == "https", refreshedURL.host?.hasSuffix(".aliyuncs.com") == true else { throw URLError(.badURL) }
            (data, response) = try await ResourceDownloadSession.shared.data(from: refreshedURL)
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 2_000_000,
              SHA256.hash(data: data).map({String(format: "%02x", $0)}).joined() == item.thumbnail_sha256 else { throw URLError(.badServerResponse) }
        if started == generation {
            try Task.checkCancellation()
            ResourceCache.shared.store(data, for: cacheKey, expectedGeneration: cacheGeneration)
        }
        return data
    }
}

struct MaterialThumbnail: View {
    let item: CloudMaterial
    @State private var image: UIImage?
    @State private var displayedID = ""
    @State private var failed = false
    var body: some View {
        Group {
            if displayedID == item.id + item.thumbnail_sha256, let image { Image(uiImage: image).resizable().scaledToFit() }
            else if failed { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
            else { ProgressView() }
        }.task(id: item.id + item.thumbnail_sha256) {
            if displayedID != item.id + item.thumbnail_sha256 { image = nil; displayedID = item.id + item.thumbnail_sha256 }
            failed=false
            if item.revision == 0, let local=DiaryStickerCatalog.items.first(where:{"local."+$0.id == item.id}) { image=local.image();return }
            if item.availability == "unavailable" { failed=true;return }
            do {
                let request = PreviewImageRequest(key: ResourceCacheKey(scope: "shared", category: "material-thumbnails", identity: item.thumbnail_sha256), url: URL(string: item.thumbnail_url), maxPixelSize: 640)
                if let cached = PreviewImagePipeline.shared.cached(request) { image = cached; return }
                let data = try await MaterialThumbnailCache.shared.load(item)
                let loaded = try await PreviewImagePipeline.shared.decoded(data, request: request)
                try Task.checkCancellation()
                image = loaded
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}


/// Local/cached and remote preset readers share the same material entry points.
struct PresetMaterialLibraryLinks: View {
    let templateID: String
    let templateVersion: Int
    @State private var libraries: [CloudMaterialLibrary] = []
    @State private var error: String?
    @State private var selected: CloudMaterialLibrary?
    var body: some View {
        VStack {
            if let error { DiaryLibraryNotice(message: error) { Task { await load() } } }
            ForEach(libraries) { library in
                Button { selected = library } label: {
                    HStack {
                        Text(library.type == "sticker" ? "配套贴纸" : "配套背景")
                        Spacer(); Text("\(library.count) 张"); Image(systemName: "chevron.right")
                    }
                }.padding(.vertical, 6)
            }
        }.padding(.horizontal)
        .task { await load() }
        .sheet(item: $selected) { library in
            NavigationStack {
                if library.type == "sticker" { StickerPackDetailScreen(library: library) }
                else { MaterialLibraryBrowser(templateID: templateID, templateVersion: templateVersion, type: "background") }
            }
        }
    }
    private func load() async {
        guard UUID(uuidString: templateID) != nil else { return }
        do {
            let page: MaterialListPage<CloudMaterialLibrary> = try await MaterialCatalogRepository.shared.request(MaterialRoutes.path("libraries/",["schema":"2","template":templateID,"template_version":String(templateVersion)]))
            libraries = page.items; error = nil
        } catch { self.error = error.localizedDescription }
    }
}
