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
            strategy: NetworkStrategy(requiresAuth: true, allowETag: (method ?? (body == nil ? .get : .post)) == .get))
    }
    func favoriteLibraries() async throws -> [CloudMaterialLibrary] {
        var result:[CloudMaterialLibrary]=[]
        var cursor:String?
        var restarted = false
        while true {
            try Task.checkCancellation()
            var params=["schema":"2","type":"sticker","favorites":"1","sort":"added","limit":"100"]
            if let cursor { params["cursor"]=cursor }
            do {
                let page: MaterialListPage<CloudMaterialLibrary> = try await request(MaterialRoutes.path("libraries/",params), forceRefresh: restarted)
                result += page.items; cursor = page.next_cursor
                if cursor == nil { break }
            } catch {
                guard cursor != nil, !restarted, MaterialPaginationPolicy.shouldRestart(error) else { throw error }
                restarted = true; result = []; cursor = nil
                continue
            }
        }
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

    func request<T: Decodable>(_ path: String, body: [String: Bool]? = nil, method: SupportHTTPMethod? = nil,
                               forceRefresh: Bool = false, onCached: ((T) -> Void)? = nil) async throws -> T {
        guard let engine else { throw URLError(.userAuthenticationRequired) }
        let cacheable = (method ?? (body == nil ? .get : .post)) == .get
        let capturedOwner = owner
        let capturedChange = changeID
        let cursor = URLComponents(string: path)?.queryItems?.first(where: { $0.name == "cursor" })?.value
        if let cursor, MaterialPaginationPolicy.expired(cursor) {
            CatalogResponseCache.shared.invalidate(owner: capturedOwner, domain: "materials")
            throw MaterialPaginationPolicy.Expired()
        }
        let fetch: @MainActor () async throws -> Data = { [self] in
            guard owner == capturedOwner, changeID == capturedChange else { throw CancellationError() }
            let response = try await engine.sendRaw(Self.networkRequest(path, body: body, method: method))
            guard owner == capturedOwner, changeID == capturedChange else { throw CancellationError() }
            _ = try JSONDecoder().decode(T.self, from: response.data)
            isOffline = false
            return response.data
        }
        let data: Data
        if cacheable {
            do {
                data = try await CatalogResponseCache.shared.load(owner: capturedOwner, domain: "materials",
                    path: engine.serviceBaseURL.absoluteString + "/materials/" + path, forceRefresh: forceRefresh,
                    onCached: { data in if let value = try? JSONDecoder().decode(T.self, from: data) { onCached?(value) } }, onOffline: { [weak self] in self?.isOffline = true }, fetch: fetch)
            } catch {
                if owner == capturedOwner, cursor != nil, MaterialPaginationPolicy.shouldRestart(error) {
                    CatalogResponseCache.shared.invalidate(owner: capturedOwner, domain: "materials")
                }
                throw error
            }
        } else {
            data = try await fetch()
            CatalogResponseCache.shared.invalidate(owner: capturedOwner, domain: "materials")
            changeID = UUID()
        }
        guard owner == capturedOwner else { throw CancellationError() }
        return try JSONDecoder().decode(T.self, from: data)
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
    @State private var showMaker = false
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
    @State private var additionFeedback = 0
    @State private var lastAddedID: String?
    @State private var lastAddedName: String?
    @FocusState private var searchFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        if type == "sticker", session != nil { result.append(("frames", "相框")) }
        return result
    }
    private var filterKey: String { query + "|" + kind + "|" + subcategory + "|" + source + "|" + (selectedLibrary?.id ?? "") + "|" + searchScope }

    private var isStickerPicker: Bool { session != nil && type == "sticker" }
    private var isCompact: Bool { isStickerPicker && sheetDetent == Self.compactDetent }
    private var contextTitle: String {
        if kind == "personal" { return "我制作的" }
        if isLocal { return "历史贴纸" }
        if kind == "frames" { return "相框" }
        return selectedLibrary?.title ?? (source == "我的" ? "单张收藏" : source == "最近" ? "最近使用" : "手帐配套贴纸")
    }
    private var localItems: [DiaryStickerItem] {
        DiaryStickerCatalog.items.filter { query.isEmpty || ($0.title + $0.category).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 8) {
            if isStickerPicker {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(replacingID == nil ? "添加贴纸" : "替换贴纸").font(.headline)
                        if !isCompact {
                            Text(lastAddedName.map { "已添加 · " + $0 } ?? "点击贴纸即可添加")
                                .font(.caption2).foregroundStyle(DiaryLibraryStyle.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Button { showGallery = true } label: {
                        Label("贴纸库", systemImage: "square.grid.2x2")
                    }.font(.subheadline).frame(minHeight: 44)
                    Button("完成") { dismiss() }
                        .font(.subheadline.weight(.semibold)).frame(minWidth: 52, minHeight: 44)
                        .accessibilityHint("关闭贴纸面板，已添加的贴纸会保留")
                }.padding(.horizontal, 16).padding(.top, 8)
                if !isCompact {
                    Picker("贴纸来源", selection: Binding(get: { source }, set: { value in
                        source = value; kind = ""; subcategory = ""; searchScope = "本包"
                        selectedLibrary = value == "当前手帐" ? currentLibraries.first : nil
                    })) {
                        ForEach(["最近", "当前手帐", "我的"], id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.segmented).padding(.horizontal, 16)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if source == "我的" {
                                packChip("单张收藏", symbol: "heart", selected: selectedLibrary == nil && kind.isEmpty) {
                                    selectedLibrary = nil; kind = ""; subcategory = ""
                                }
                            }
                            ForEach(source == "我的" ? myLibraries : source == "当前手帐" ? currentLibraries : []) { lib in
                                Button {
                                    selectedLibrary = lib; kind = ""; subcategory = ""; searchScope = "本包"
                                } label: {
                                    HStack(spacing: 7) {
                                        MaterialResourceImage(resource: lib.cover, libraryID: lib.id, version: lib.version)
                                            .frame(width: 30, height: 30).accessibilityHidden(true)
                                        Text(lib.title).font(.caption.weight(.medium)).lineLimit(1)
                                        Text("\(lib.count)").font(.caption2).foregroundStyle(DiaryLibraryStyle.secondary)
                                    }.padding(.horizontal, 10).frame(minHeight: 44)
                                        .background(selectedLibrary?.id == lib.id && kind.isEmpty ? DiaryLibraryStyle.accent.opacity(0.12) : DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain)
                                    .accessibilityLabel("\(lib.title)，\(lib.count) 张贴纸")
                                    .accessibilityAddTraits(selectedLibrary?.id == lib.id && kind.isEmpty ? [.isSelected] : [])
                            }
                            packChip("制作", symbol: "scissors", selected: false) { showMaker = true }
                            if source == "我的" {
                                packChip("我制作的", symbol: "person.crop.square", selected: kind == "personal") {
                                    kind = "personal"; selectedLibrary = nil; subcategory = ""
                                }
                            }
                            if source == "我的" {
                                Button("全部贴纸包") { showAllPacks = true }.font(.caption).frame(minHeight: 44)
                            }
                        }.padding(.horizontal, 16)
                    }
                }
            }
            if !isCompact && kind != "personal" && source == "我的" && !query.isEmpty {
                Picker("搜索范围", selection: $searchScope) { Text(selectedLibrary == nil ? "单张收藏" : "本包").tag("本包"); Text("我的全部贴纸").tag("我的全部") }
                    .pickerStyle(.segmented).padding(.horizontal, 16)
            }
            if catalog.isOffline { Text("离线缓存").font(.caption).foregroundStyle(.secondary) }
            if !isCompact && kind != "personal" {
                HStack(spacing: 10) {
                    DiaryLibrarySearch(text: $query, prompt: isStickerPicker ? "搜索\(contextTitle)" : "搜索\(title)")
                        .focused($searchFocused)
                    if isStickerPicker {
                        Button { showFilters.toggle() } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                                .frame(width: 44, height: 48)
                                .background(showFilters ? DiaryLibraryStyle.accent.opacity(0.12) : DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                        }.accessibilityLabel("分类筛选")
                            .accessibilityValue(showFilters ? "已展开" : "已收起")
                    }
                }.padding(.horizontal, 16)
            }
            if isCompact {
                HStack(spacing: 8) {
                    if let lastAddedName {
                        Label("已添加 · \(lastAddedName)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(DiaryLibraryStyle.accent).lineLimit(1)
                    } else {
                        Text(contextTitle).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button("展开浏览", systemImage: "chevron.up") {
                        withAnimation { sheetDetent = .fraction(0.66) }
                    }.frame(minHeight: 44)
                }.font(.caption).padding(.horizontal, 16)
            }
            if kind != "personal" && ((!isCompact && showFilters) || session == nil || type != "sticker") {
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
                if kind == "personal" {
                    PersonalStickerGrid(query: query, onCreate: { showMaker = true }) { sticker, data in
                        await insertPersonal(sticker, data: data)
                    }
                } else if kind == "frames", let session {
                    DiaryPhotoFrameGrid(session: session, query: query).padding(.horizontal, 16)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: dynamicTypeSize.isAccessibilitySize ? 2 : 4), spacing: 12) {
                        if isLocal {
                            ForEach(localItems) { item in
                                Button { addition = Task { await addLocal(item) } } label: {
                                    VStack(spacing: 6) {
                                        if let image = item.image() {
                                            Image(uiImage: image).resizable().scaledToFit()
                                                .frame(height: 84).frame(maxWidth: .infinity)
                                                .padding(6)
                                                .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                                                .overlay { addedOutline(selected: lastAddedID == "local." + item.id) }
                                        }
                                        Text(item.title).font(.caption2).lineLimit(1)
                                    }
                                }.buttonStyle(.plain).disabled(adding)
                                .accessibilityLabel("添加\(item.title)")
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
                    if isLocal && localItems.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                    if !isLocal {
                        if cursor != nil || nextCursor != nil {
                            DiaryPaginationFooter(token: filterKey + "|" + (nextCursor ?? cursor.map(String.init) ?? ""), loading: loading, error: error) { await loadItems(more: true) }
                        }
                        if loading { ProgressView().padding() }
                        if !loading && items.isEmpty {
                            ContentUnavailableView {
                                Label(query.isEmpty ? "这里还没有贴纸" : "没有找到贴纸", systemImage: "square.grid.2x2")
                            } description: {
                                Text(query.isEmpty ? "可以制作自己的贴纸，或前往贴纸库挑选。" : "试试其他关键词，或前往贴纸库搜索。")
                            } actions: {
                                Button("浏览贴纸库") { showGallery = true }
                            }
                        }
                    }
                }
            }
            .scrollPosition(id:$scrollID)
            .scrollDismissesKeyboard(.interactively)
            if !isStickerPicker {
                DiaryEditorToolFooter(title: title, onBack: { dismiss() }, onDone: { dismiss() })
            }
        }
        .interactiveDismissDisabled(true) // 重点：禁止下拉关闭
        .foregroundStyle(DiaryLibraryStyle.ink)
        .tint(DiaryLibraryStyle.accent)
        .background(DiaryLibraryStyle.background)
        // Sticker content respects the home indicator; legacy tools retain their footer inset.
        .ignoresSafeArea(.container, edges: isStickerPicker ? [] : .bottom)
        .presentationBackground(DiaryLibraryStyle.background)
        .presentationDetents([Self.compactDetent, .fraction(0.66), .large], selection: $sheetDetent)
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(keepsOpenAfterAdding ? .enabled(upThrough: Self.compactDetent) : .disabled)
        .task {
            if let session {
                localFavorites = UserDefaults.standard.stringArray(forKey: session.store.stickerPreferenceKey + ".favorites") ?? []
                localRecent = UserDefaults.standard.stringArray(forKey: session.store.stickerPreferenceKey + ".recent") ?? []
            }
            await loadSources()
            if kind == "builtin" { kind = "personal"; source = "我的" }
            await loadCategories()
        }
        .onChange(of: catalog.owner) { _, _ in
            generation=UUID();addition?.cancel();items=[];myLibraries=[];currentLibraries=[];selectedLibrary=nil;localFavorites=[];localRecent=[]
        }
        .onChange(of: catalog.changeID) { _, _ in Task { await loadSources(refresh: true) } }
        .fullScreenCover(isPresented: $showMaker) {
            StickerMakerScreen(addsToCanvas: session != nil) { sticker, data in
                source = "我的"; kind = "personal"; selectedLibrary = nil
                await insertPersonal(sticker, data: data)
            }
        }
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
        .onChange(of: filterKey) { _, _ in
            requestID = UUID(); items = []; cursor = nil; nextCursor = nil
            scrollID = nil; error = nil; lastAddedID = nil; lastAddedName = nil
            loading = !isLocal && kind != "personal" && kind != "frames"
        }
        .onChange(of: searchFocused) { _, focused in
            if focused { sheetDetent = .large }
        }
        .sensoryFeedback(.success, trigger: additionFeedback)
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

    private func insertPersonal(_ sticker: PersonalSticker, data: Data) async {
        guard let session else { return }
        let owner = catalog.owner
        let documentID = session.document.id
        let contentID = session.contentID
        let canCommit = { catalog.owner == owner && session.acceptsMaterialInsertion(documentID: documentID, contentID: contentID, replacingID: replacingID) }
        let imported: Bool
        if let replacingID { imported = await session.importPhoto(data, replacing: replacingID, canCommit: canCommit) }
        else { imported = await session.importPhoto(data, asSticker: true, stickerName: "我制作的贴纸", canCommit: canCommit) }
        if imported { finishAdding(id: "personal." + sticker.id, name: "我制作的贴纸") }
        else { error = "贴纸已保存，可从我的贴纸重新添加" }
    }

    private func packChip(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.caption.weight(.medium))
                .padding(.horizontal, 12).frame(minHeight: 44)
                .background(selected ? DiaryLibraryStyle.accent.opacity(0.12) : DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func addedOutline(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(selected ? DiaryLibraryStyle.accent : .clear, lineWidth: 2)
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.caption)
                        .foregroundStyle(DiaryLibraryStyle.accent)
                        .background(DiaryLibraryStyle.surface, in: Circle()).padding(5)
                }
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
                        .overlay { addedOutline(selected: lastAddedID == item.id) }
                        .overlay(alignment: .topTrailing) {
                            if item.is_favorited && lastAddedID != item.id {
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
            .accessibilityLabel(item.name)
            .accessibilityHint(item.availability == "unavailable" ? "该贴纸已下架" : session == nil ? "查看贴纸详情" : "点击添加到画布，长按查看详情或收藏")
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
                else if MaterialRecentStore.items(owner: catalog.owner).isEmpty { source = "我的"; kind = "personal" }
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
        guard !isLocal && kind != "personal" && kind != "frames" else { items = []; cursor = nil; loading = false; return }
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
    private func loadStickerItems(more: Bool, forceRefresh: Bool = false) async {
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
                items = recent.filter {
                    (query.isEmpty || ($0.name + $0.keywords.joined(separator: " ")).localizedCaseInsensitiveContains(query)) &&
                    (kind.isEmpty || $0.kind == kind) && (subcategory.isEmpty || $0.subcategory == subcategory)
                }
                nextCursor = nil; error = nil; return
            }
            if source == "当前手帐", selectedLibrary == nil { items = []; nextCursor = nil; return }
            var params = ["schema":"2", "type":"sticker", "q":query, "kind":kind, "subcategory":subcategory]
            var path = "items/"
            if searchScope == "我的全部" && source == "我的" && !query.isEmpty { params["scope"] = "my" }
            else if let lib = selectedLibrary { path = "libraries/\(lib.id)/items/"; params["version"] = String(lib.version) }
            else { params["favorites"] = "1" }
            if more { params["cursor"] = nextCursor }
            let page: MaterialListPage<CloudMaterial> = try await catalog.request(MaterialRoutes.path(path, params), forceRefresh: forceRefresh)
            guard requestID == token, activeFilter == filterKey, !Task.isCancelled else { return }
            items = more ? items.appendingUnique(page.items) : page.items; nextCursor = page.next_cursor == previousCursor ? nil : page.next_cursor; cursor = nil; error = nil
        } catch {
            guard requestID == token, activeFilter == filterKey, !Task.isCancelled else { return }
            if more, MaterialPaginationPolicy.shouldRestart(error) {
                nextCursor = nil; cursor = nil; loading = false
                await loadStickerItems(more: false, forceRefresh: true)
            } else if !CatalogLoadError.isCancellation(error) { self.error = error.localizedDescription }
        }
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
    private func finishAdding(id: String, name: String) {
        lastAddedID = id; lastAddedName = name; additionFeedback += 1; searchFocused = false
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
        adding = true; error = nil
        let intent = UUID(); generation = intent
        let owner = catalog.owner
        let documentID = session.document.id
        let contentID = session.contentID
        defer { if generation == intent { adding = false } }
        if await session.importPhoto(data, replacing: replacingID, asSticker: true, stickerName: item.title,
            canCommit: { generation == intent && catalog.owner == owner && session.acceptsMaterialInsertion(documentID: documentID, contentID: contentID, replacingID: replacingID) }) {
            localRecent.removeAll { $0 == item.id }; localRecent.insert(item.id, at: 0); localRecent = Array(localRecent.prefix(30))
            MaterialRecentStore.recordLocal(item,owner:catalog.owner)
            saveLocalPreferences(); finishAdding(id: "local." + item.id, name: item.title)
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
            if imported { MaterialRecentStore.record(item, owner: owner); pausedItem = nil; finishAdding(id: item.id, name: item.name) }
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
