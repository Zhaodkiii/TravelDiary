import SwiftUI
import CryptoKit

nonisolated struct MaterialImageResource: Codable, Identifiable {
    let resource_id: String
    let sha256: String
    let url: String
    let width: Int
    let height: Int
    var expires_at: String?
    var id: String { resource_id }
}
nonisolated struct MaterialListPage<T: Decodable>: Decodable {
    let items: [T]
    let next_cursor: String?
}
nonisolated enum MaterialRoutes {
    static func path(_ path: String, _ values: [String: String]) -> String {
        var components = URLComponents()
        components.queryItems = values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return path + "?" + (components.percentEncodedQuery ?? "")
    }
}
@MainActor enum MaterialRecentStore {
    static func items(owner: String) -> [CloudMaterial] {
        guard let data = UserDefaults.standard.data(forKey: "material.recent.\(owner)") else { return [] }
        return (try? JSONDecoder().decode([CloudMaterial].self, from: data)) ?? []
    }
    static func save(_ items: [CloudMaterial],owner: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(items.prefix(30))),forKey:"material.recent.\(owner)")
    }
    static func recordLocal(_ item: DiaryStickerItem,owner: String) {
        record(CloudMaterial(id:"local."+item.id,revision:0,name:item.title,keywords:[],aliases:[],kind:"illustration",subcategory:"object",thumbnail_sha256:"",thumbnail_url:"",sha256:"",byte_size:0,favorite_count:0,is_favorited:false),owner:owner)
    }
    static func record(_ item: CloudMaterial, owner: String) {
        var values = items(owner: owner).filter { $0.id != item.id }
        values.insert(item, at: 0)
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(values.prefix(30))), forKey: "material.recent.\(owner)")
    }
}

actor MaterialImageCache {
    static let shared = MaterialImageCache()
    private var generation = 0
    private var pending: [String: Task<Data, Error>] = [:]
    private func key(_ hash: String) -> ResourceCacheKey { ResourceCacheKey(scope: "shared", category: "material-images", identity: hash) }
    func clear() throws {
        generation += 1
        for task in pending.values { task.cancel() }; pending.removeAll()
        ResourceCache.shared.clear(category: "material-images")
        let root = StoragePaths.system.cache("MaterialImages")
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }
    func load(_ resource: MaterialImageResource) async throws -> Data {
        if let task = pending[resource.sha256] { return try await task.value }
        let task = Task { try await self.fetch(resource) }
        pending[resource.sha256] = task
        defer { pending[resource.sha256] = nil }
        return try await task.value
    }
    private func fetch(_ resource: MaterialImageResource) async throws -> Data {
        guard resource.sha256.count == 64, resource.sha256.allSatisfy(\.isHexDigit) else { throw URLError(.badURL) }
        let root = StoragePaths.system.cache("MaterialImages")
        let path = root.appendingPathComponent(resource.sha256)
        let cacheKey = key(resource.sha256)
        if let data = ResourceCache.shared.data(for: cacheKey), SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined() == resource.sha256 { return data }
        if let data = try? Data(contentsOf:path), SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined() == resource.sha256 {
            ResourceCache.shared.register(path, for: cacheKey); return data
        }
        guard let url=URL(string:resource.url),url.scheme == "https", url.host?.hasSuffix(".aliyuncs.com") == true else { throw URLError(.badURL) }
        let started = generation
        let cacheGeneration = ResourceCache.shared.generation(for: cacheKey)
        let (data,response) = try await ResourceDownloadSession.shared.data(from:url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 15*1024*1024,
            SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined() == resource.sha256 else { throw URLError(.badServerResponse) }
        if started == generation {
            try Task.checkCancellation()
            ResourceCache.shared.store(data, for: cacheKey, expectedGeneration: cacheGeneration)
        }
        return data
    }
}

struct MaterialResourceImage: View {
    let resource: MaterialImageResource?
    var libraryID: String? = nil
    var version: Int? = nil
    @State private var bitmap: UIImage?
    @State private var displayedID: String?
    @State private var failed = false
    @State private var retry = 0
    var body: some View {
        Group {
            if displayedID == resource?.sha256, let bitmap { Image(uiImage: bitmap).resizable().scaledToFit() }
            else {
                RoundedRectangle(cornerRadius: 12).fill(DiaryLibraryStyle.surface)
                    .overlay {
                        if failed { Button { retry += 1 } label: { Image(systemName:"arrow.clockwise") }.accessibilityLabel("重试图片") }
                        else { Image(systemName: "photo").foregroundStyle(.secondary) }
                    }
            }
        }.task(id: (resource?.sha256 ?? "") + String(retry)) {
            failed = false
            guard var resource else { return }
            if displayedID != resource.sha256 { bitmap = nil; displayedID = resource.sha256 }
            let imageRequest = PreviewImageRequest(key: ResourceCacheKey(scope: "shared", category: "material-images", identity: resource.sha256), url: URL(string: resource.url), maxPixelSize: 2048)
            if let image = PreviewImagePipeline.shared.cached(imageRequest) { bitmap = image; return }
            do {
                let data: Data
                do { data = try await MaterialImageCache.shared.load(resource) }
                catch {
                    guard let libraryID, let version else { throw error }
                    resource = try await MaterialCatalogRepository.shared.refreshPreview(resourceID:resource.resource_id,libraryID:libraryID,version:version)
                    data = try await MaterialImageCache.shared.load(resource)
                }
                let image = try await PreviewImagePipeline.shared.decoded(data, request: imageRequest)
                try Task.checkCancellation(); bitmap = image
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}

private struct MaterialLargePreview: View {
    let resource: MaterialImageResource
    let library: CloudMaterialLibrary
    @State private var scale: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView([.horizontal,.vertical]) {
                MaterialResourceImage(resource:resource,libraryID:library.id,version:library.version)
                    .frame(width: 350 * scale * magnification, height: 350 * CGFloat(resource.height) / CGFloat(max(1,resource.width)) * scale * magnification)
                    .gesture(MagnifyGesture().updating($magnification) { value,state,_ in state=value.magnification }.onEnded { scale=min(5,max(1,scale*$0.magnification)) })
            }.navigationTitle("贴纸展示").toolbar { Button("完成") { dismiss() } }
        }
    }
}


struct StickerGalleryScreen: View {
    var mine = false
    var onUse: ((CloudMaterialLibrary) -> Void)? = nil
    @ObservedObject private var repository = MaterialCatalogRepository.shared
    @State private var packs: [CloudMaterialLibrary] = []
    @State private var stickers: [CloudMaterial] = []
    @State private var query = ""
    @State private var mode = "包"
    @State private var sort = "recommended"
    @State private var tags: [String] = []
    @State private var tag = ""
    @State private var showCache = false
    @State private var cursor: String?
    @State private var loading = false
    @State private var error: String?
    @State private var managing = false
    @State private var selection: Set<String> = []
    @State private var preview: CloudMaterial?
    @State private var requestID = UUID()
    @State private var removing = false
    @Environment(\.dismiss) private var dismiss
    init(mine: Bool = false, onUse: ((CloudMaterialLibrary) -> Void)? = nil, initialQuery: String = "", initialMode: String = "包") {
        self.mine=mine;self.onUse=onUse
        _query=State(initialValue:initialQuery);_mode=State(initialValue:initialMode)
    }
    private var filter: String { query + "|" + mode + "|" + sort + "|" + tag }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                DiaryLibrarySearch(text: $query, prompt: mine ? "搜索我的贴纸" : "搜索贴纸包或单张贴纸")
                Picker("内容", selection: $mode) {
                    Text("贴纸包").tag("包")
                    Text(mine ? "单张收藏" : "单张贴纸").tag("单张")
                }.pickerStyle(.segmented)
                if !mine && mode == "包" {
                    Picker("排序", selection: $sort) { Text("推荐").tag("recommended"); Text("最新").tag("latest") }.pickerStyle(.segmented)
                }
                if !mine && mode == "包" && !tags.isEmpty {
                    ScrollView(.horizontal,showsIndicators:false) {
                        HStack {
                            DiaryLibraryChip(title:"全部主题",selected:tag.isEmpty,compact:true) { tag="" }
                            ForEach(tags,id: \.self) { value in DiaryLibraryChip(title:value,selected:tag==value,compact:true) { tag=value } }
                        }
                    }
                }
                if repository.isOffline { Text("离线缓存").font(.caption).foregroundStyle(.secondary) }
                if let error { DiaryLibraryNotice(message: error) { Task { await load() } } }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 20) {
                    if mode == "包" {
                        ForEach(packs) { pack in
                            if managing {
                                Button { toggle(pack.id) } label: { packCell(pack).overlay(alignment: .topTrailing) { Image(systemName: selection.contains(pack.id) ? "checkmark.circle.fill" : "circle") } }
                            } else {
                                NavigationLink { StickerPackDetailScreen(library: pack, onUse: onUse) } label: { packCell(pack) }
                            }
                        }
                    } else {
                        ForEach(stickers) { item in
                            Button { if managing { toggle(item.id) } else { preview = item } } label: {
                                VStack { MaterialThumbnail(item: item).frame(height: 90); Text(item.name).font(.caption).lineLimit(2) }
                                    .overlay(alignment: .topTrailing) { if managing { Image(systemName: selection.contains(item.id) ? "checkmark.circle.fill" : "circle") } }
                            }
                        }
                    }
                }.buttonStyle(.plain)
                if loading { ProgressView() }
                if cursor != nil { Button("加载更多") { Task { await load(more: true) } }.disabled(loading) }
                if !loading && packs.isEmpty && stickers.isEmpty && error == nil {
                    ContentUnavailableView("暂无贴纸", systemImage: "square.grid.2x2", description: Text(mine ? "把喜欢的贴纸包加入这里，或收藏单张贴纸。" : "试试其他关键词。"))
                    if mine { NavigationLink("去找贴纸") { StickerGalleryScreen(onUse: onUse) } }
                }
            }.padding(16)
        }
        .background(DiaryLibraryStyle.background).foregroundStyle(DiaryLibraryStyle.ink).tint(DiaryLibraryStyle.accent)
        .navigationTitle(mine ? "我的贴纸" : "贴纸").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if mine {
                ToolbarItem(placement: .topBarTrailing) { Button(managing ? "完成" : "管理") { managing.toggle(); selection = [] } }
                ToolbarItem(placement: .topBarTrailing) { Button { showCache=true } label:{Image(systemName:"internaldrive")}.accessibilityLabel("缓存管理") }
            }
            else { ToolbarItem(placement: .topBarTrailing) { NavigationLink("我的贴纸") { StickerGalleryScreen(mine: true, onUse: onUse) } } }
        }
        .safeAreaInset(edge: .bottom) {
            if managing { Button("移除所选（\(selection.count)）") { Task { await removeSelected() } }.buttonStyle(.borderedProminent).disabled(selection.isEmpty || removing).padding().frame(maxWidth: .infinity).background(.regularMaterial) }
        }
        .task(id: filter) { do { try await Task.sleep(for: .milliseconds(300)); await load() } catch { } }
        .onChange(of: repository.owner) { _, _ in packs=[];stickers=[];selection=[];cursor=nil;requestID=UUID() }
        .onChange(of: repository.changeID) { _, _ in Task { await load() } }
        .onChange(of: mode) { _, _ in selection = [] }
        .refreshable { await load() }
        .task { if !mine { tags = (try? await repository.request("tags/")) ?? [] } }
        .sheet(isPresented:$showCache) { MaterialCacheScreen() }
        .sheet(item: $preview) { item in MaterialItemPreview(item: item) }
    }
    private func packCell(_ pack: CloudMaterialLibrary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MaterialResourceImage(resource: pack.cover, libraryID:pack.id, version:pack.version).aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
            Text(pack.title).font(.subheadline).lineLimit(2)
            Text(pack.availability == "unavailable" ? "已下架" : "\(pack.count) 张\(pack.is_favorited ? " · 已加入" : "")").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func toggle(_ id: String) { if selection.contains(id) { selection.remove(id) } else { selection.insert(id) } }
    private func load(more: Bool = false) async {
        let token = UUID(); requestID = token; loading = true
        defer { if requestID == token { loading = false } }
        var params = ["schema":"2", "type":"sticker", "q":query]
        if mine { params["favorites"] = "1" }
        if !tag.isEmpty && mode == "包" { params["tag"] = tag }
        if mode == "包" { params["sort"] = mine ? "added" : sort }
        if more { params["cursor"] = cursor }
        do {
            if mode == "包" {
                let page: MaterialListPage<CloudMaterialLibrary> = try await repository.request(MaterialRoutes.path("libraries/",params))
                guard requestID == token && !Task.isCancelled else { return }
                packs = more ? packs + page.items : page.items; stickers = []; cursor = page.next_cursor
            } else {
                let page: MaterialListPage<CloudMaterial> = try await repository.request(MaterialRoutes.path("items/",params))
                guard requestID == token && !Task.isCancelled else { return }
                stickers = more ? stickers + page.items : page.items; packs = []; cursor = page.next_cursor
            }
            error = nil
        } catch { if requestID == token && !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func removeSelected() async {
        removing = true; defer { removing = false }
        let target = mode == "包" ? "libraries" : "items"
        var failed = false
        for id in Array(selection) {
            do { let _: MaterialFavoriteResult = try await repository.request("\(target)/\(id)/favorite/", body: ["favorite":false]); selection.remove(id) }
            catch { failed = true; self.error = "部分项目移除失败，请重试：" + error.localizedDescription }
        }
        let failure = error
        await load()
        if failed { error = failure }
    }
}

struct MaterialItemPreview: View {
    @State var item: CloudMaterial
    @State private var error: String?
    @State private var saving = false
    var body: some View {
        VStack(spacing: 16) {
            MaterialThumbnail(item: item).frame(maxHeight: 300)
            Text(item.name).font(.headline)
            Text(item.keywords.joined(separator: " · ")).font(.caption)
            if let error { Text(error).foregroundStyle(.red) }
            Button(item.is_favorited ? "取消收藏" : "收藏贴纸") {
                saving = true
                Task {
                    defer { saving = false }
                    do {
                        let r: MaterialFavoriteResult = try await MaterialCatalogRepository.shared.request("items/\(item.id)/favorite/",body:["favorite":!item.is_favorited])
                        item.is_favorited = r.is_favorited
                    } catch { self.error = error.localizedDescription }
                }
            }.disabled(saving)
        }.padding().presentationDetents([.medium,.large])
    }
}

struct StickerPackDetailScreen: View {
    @State var library: CloudMaterialLibrary
    var onUse: ((CloudMaterialLibrary) -> Void)? = nil
    @State private var items: [CloudMaterial] = []
    @State private var cursor: String?
    @State private var error: String?
    @State private var preview: CloudMaterial?
    @State private var choosingBook = false
    @State private var largePreview: MaterialImageResource?
    @State private var category = ""
    @State private var query = ""
    @State private var saving = false
    @State private var loading = false
    @State private var requestID = UUID()
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text(library.title).font(.title.bold())
                Text("\(library.count) 张 · v\(library.version)").foregroundStyle(.secondary)
                if let description = library.description { Text(description) }
                if let error { DiaryLibraryNotice(message: error) { Task { await load() } } }
                ForEach(library.previews ?? []) { image in
                    Button { largePreview=image } label: {
                        MaterialResourceImage(resource: image,libraryID:library.id,version:library.version).aspectRatio(CGFloat(image.width)/CGFloat(max(1,image.height)),contentMode: .fit)
                    }.buttonStyle(.plain)
                }
                Text("全部贴纸").font(.headline)
                DiaryLibrarySearch(text:$query,prompt:"搜索本包贴纸")
                Picker("分类",selection:$category) {
                    Text("全部").tag("");Text("插画与装饰").tag("illustration");Text("纸卡与票据").tag("paper");Text("文字贴纸").tag("text");Text("相框与照片卡").tag("photo");Text("品牌标识").tag("branding")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))]) {
                    ForEach(items) { item in Button { preview = item } label: { MaterialThumbnail(item: item).frame(height: 85) }.buttonStyle(.plain) }
                }
                if loading { ProgressView() }
                if cursor != nil { Button("加载更多") { Task { await load(more:true) } }.disabled(loading) }
            }.padding()
        }
        .background(DiaryLibraryStyle.background)
        .navigationTitle("贴纸详情").navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button(library.is_favorited ? "已加入 · 移除" : "加入我的贴纸") { Task { await favorite() } }.disabled(saving)
                Spacer()
                Button("去使用") { if let onUse { onUse(library) } else { choosingBook = true } }.buttonStyle(.borderedProminent)
                    .disabled(library.availability == "unavailable")
            }.padding().background(.regularMaterial)
        }
        .task(id:query + "|" + category) { do { try await Task.sleep(for:.milliseconds(300)); await load() } catch {} }
        .sheet(item:$largePreview) { resource in MaterialLargePreview(resource:resource,library:library) }
        .sheet(item: $preview) { item in MaterialItemPreview(item:item) }
        .sheet(isPresented: $choosingBook) { StickerBookChooser(library:library) }
    }
    private func load(more: Bool = false) async {
        let token=UUID();requestID=token;loading=true
        defer { if requestID==token { loading=false } }
        do {
            if !more {
                let detail: CloudMaterialLibrary = try await MaterialCatalogRepository.shared.request("libraries/\(library.id)/?version=\(library.version)")
                guard requestID==token,!Task.isCancelled else { return };library=detail
            }
            guard library.availability != "unavailable" else { error = "该贴纸包已下架"; return }
            var params=["schema":"2","version":String(library.version),"q":query,"kind":category]
            if more { params["cursor"] = cursor }
            let page: MaterialListPage<CloudMaterial> = try await MaterialCatalogRepository.shared.request(MaterialRoutes.path("libraries/\(library.id)/items/",params))
            guard requestID==token,!Task.isCancelled else { return }
            items = more ? items + page.items : page.items; cursor = page.next_cursor; error = nil
        } catch { if requestID==token && !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func favorite() async {
        saving = true; defer { saving = false }
        do { let r: MaterialFavoriteResult = try await MaterialCatalogRepository.shared.request("libraries/\(library.id)/favorite/",body:["favorite":!library.is_favorited]);library.is_favorited = r.is_favorited }
        catch { self.error = error.localizedDescription }
    }
}

private struct StickerBookChooser: View {
    let library: CloudMaterialLibrary
    @State private var books: [DiaryBook] = []
    @State private var session: DiaryEditorSession?
    @State private var error: String?
    @State private var opening = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red) }
                ForEach(books) { book in
                    Section(book.title) {
                        ForEach(book.pages) { page in Button(page.title) { Task { await open(book,page) } }.disabled(opening) }
                    }
                }
                if books.isEmpty { Text("暂无手帐，请先创建一本手帐后使用贴纸。") }
            }.navigationTitle("选择手帐页面").toolbar { Button("取消") { dismiss() } }
                .task { do { books = try await DiaryDocumentStore(ownerID:MaterialCatalogRepository.shared.owner).listBooks() } catch { self.error = error.localizedDescription } }
                .fullScreenCover(item:$session) { s in DiaryEditorScreen(session:s) }
        }
    }
    private func open(_ book: DiaryBook,_ page: DiaryPageEntry) async {
        opening = true; defer { opening = false }
        do {
            let store = DiaryDocumentStore(ownerID: MaterialCatalogRepository.shared.owner,bookID:book.id)
            let loaded = try await store.load(page.id)
            MaterialCatalogRepository.shared.pendingLibrary = library
            session = DiaryEditorSession(document:loaded.document, images:loaded.images,store:store)
        } catch { self.error = error.localizedDescription }
    }
}

private struct MaterialCacheScreen: View {
    @State private var bytes = 0
    @State private var busy = false
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("可清理贴纸缓存",value:ByteCountFormatter.string(fromByteCount:Int64(bytes),countStyle:.file))
                Text("清理目录、预览图和未被模板下载任务使用的贴纸原图。已保存作品中的图片会保留。")
                if let message { Text(message) }
                Button("清理缓存") { Task { await clear() } }.disabled(busy)
            }.navigationTitle("缓存管理").toolbar { Button("完成") { dismiss() } }.task { await measure() }
        }
    }
    private func roots() -> [URL] {
        [StoragePaths.system.cache("MaterialImages"),StoragePaths.system.cache("MaterialThumbnails"),StoragePaths.system.cacheAccount(MaterialCatalogRepository.shared.owner).appendingPathComponent("MaterialCatalog")]
    }
    private func measure() async {
        let files=roots()+PresetDownloadManager.shared.materialCacheFiles()
        let scope = StoragePaths.scopeKey(MaterialCatalogRepository.shared.owner)
        bytes=await Task.detached(priority:.utility) {
            let managed = ResourceCache.shared.entries().filter { ($0.scope == "shared" || $0.scope == scope) && $0.category.hasPrefix("material-") && StoragePaths.contains($0.url, in: ResourceCache.shared.root) }.reduce(0) { $0 + Int($1.bytes) }
            return managed + files.reduce(0) { total,url in
                if let enumerator=FileManager.default.enumerator(at:url,includingPropertiesForKeys:[.fileSizeKey]) {
                    return total + enumerator.compactMap { $0 as? URL }.reduce(0) { $0 + ((try? $1.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0) }
                }
                return total + ((try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0)
            }
        }.value
    }
    private func clear() async {
        busy=true;defer { busy=false }
        do {
            try await PresetDownloadManager.shared.clearMaterialCache()
            try await MaterialImageCache.shared.clear()
            try await MaterialThumbnailCache.shared.clear()
            let scope = StoragePaths.scopeKey(MaterialCatalogRepository.shared.owner)
            ResourceCache.shared.clear(scope: scope, category: "material-catalog")
            PreviewImagePipeline.shared.clearMemory()
            let catalog=roots().last!
            try await Task.detached(priority:.utility) { if FileManager.default.fileExists(atPath:catalog.path) { try FileManager.default.removeItem(at:catalog) } }.value
            message="缓存已清理";await measure()
        } catch { message=error.localizedDescription }
    }
}
