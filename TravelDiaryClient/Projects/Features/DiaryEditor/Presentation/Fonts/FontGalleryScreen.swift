import SwiftUI

struct FontGalleryScreen: View {
    var mine = false
    var embedded = false
    var documentID: UUID? = nil
    var onUse: ((DiaryFontReference) -> Void)? = nil
    @ObservedObject private var repository = CloudFontRepository.shared
    @State private var fonts: [CloudFont] = []
    @State private var query = ""
    @State private var sort = "popular"
    @State private var category = "全部"
    @State private var section = "已获取"
    @State private var downloadedOnly = false
    @State private var page = 1
    @State private var total = 0
    @State private var loading = false
    @State private var error: String?
    @State private var requestID = UUID()
    @Environment(\.dynamicTypeSize) private var typeSize
    private var visible: [CloudFont] {
        fonts.filter { font in
            (query.isEmpty || font.title.localizedCaseInsensitiveContains(query)) &&
            (category == "全部" || font.content.styles.contains(category) || (category == "手写笔记" && font.content.styles.contains("手写")) || font.content.languages.contains(category)) &&
            (!downloadedOnly || FontDisk.records().contains { $0.entry.id == font.id }) &&
            (!mine || (section == "收藏" ? font.favorite == true : section == "最近" ? repository.recent().contains { $0.id == font.id } : font.acquired == true))
        }
    }
    var body: some View {
        Group {
            if embedded { galleryContent }
            else {
                galleryContent
                    .navigationTitle(mine ? "我的字体" : "字体集市")
                    .navigationBarTitleDisplayMode(.inline)
                    .searchable(text: $query, prompt: mine ? "搜索我的字体" : "搜索字体")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            if mine { NavigationLink("管理") { FontStorageScreen() } }
                            else { NavigationLink("我的字体") { FontGalleryScreen(mine: true, documentID: documentID, onUse: onUse) } }
                        }
                    }
            }
        }
        .onSubmit(of: .search) { Task { await load(reset: true) } }
        .onChange(of: sort) { _, _ in Task { await load(reset: true) } }
        .task(id: "\(repository.generation)|\(repository.catalogRevision)") { await load(reset: true) }
        .onChange(of: repository.generation) { _, _ in fonts = []; total = 0; error = nil }
    }
    private var galleryContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if mine {
                    Picker("个人字体", selection: $section) {
                        ForEach(["已获取", "收藏", "最近"], id: \.self) { Text($0) }
                    }.pickerStyle(.segmented)
                    Toggle("仅显示已下载", isOn: $downloadedOnly).font(.subheadline)
                } else { filterChips }
                if let error {
                    Text(error).foregroundStyle(.secondary)
                    Button("重试") { Task { await load(reset: true) } }
                }
                if visible.isEmpty && !loading {
                    ContentUnavailableView("暂无字体", systemImage: "textformat",
                        description: Text(mine ? "收藏或获取喜欢的字体后，会出现在这里。" : "试试其他分类，或稍后再来看看。"))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 160 : 72), spacing: 12)], spacing: 24) {
                    ForEach(visible) { font in
                        NavigationLink {
                            FontDetailScreen(font: font, documentID: documentID, onUse: onUse)
                                .toolbar(.hidden, for: .tabBar)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                FontSpecimenImage(font: font, resourceID: font.content.cover)
                                    .aspectRatio(1, contentMode: .fit)
                                Text(font.title).font(.system(size: 13)).foregroundStyle(DiaryLibraryStyle.ink).lineLimit(1)
                                Text(font.priceLabel).font(.caption)
                                    .foregroundStyle(font.access.permanently_owned ? Color.teal : font.commerce?.access_mode == "free" ? DiaryLibraryStyle.secondary : DiaryLibraryStyle.accent)
                            }
                        }.buttonStyle(.plain).accessibilityLabel("\(font.title)，\(font.priceLabel)")
                    }
                }
                if loading { ProgressView() }
                if !mine && fonts.count < total {
                    Button("加载更多") { Task { await load(reset: false) } }.disabled(loading)
                }
                if mine { NavigationLink("逛字体集市") { FontGalleryScreen(documentID: documentID, onUse: onUse) } }
            }.padding(16)
        }.background(DiaryLibraryStyle.background)
            .refreshable { await load(reset: true, forceRefresh: true) }
    }
    private var filterChips: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 100 : 62), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(["热门", "最新", "正文", "可爱", "标题", "古风", "简约", "盐系", "手写笔记", "英文"], id: \.self) { value in
                let selected = category == "全部" ? value == (sort == "latest" ? "最新" : "热门") : value == category
                Button {
                    if value == "热门" || value == "最新" {
                        category = "全部"; sort = value == "最新" ? "latest" : "popular"
                    } else { category = category == value ? "全部" : value }
                } label: {
                    Text(value).font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(selected ? Color.white : DiaryLibraryStyle.secondary)
                        .background(selected ? DiaryLibraryStyle.accent : DiaryLibraryStyle.surface, in: Capsule())
                        .overlay { Capsule().stroke(selected ? Color.clear : DiaryLibraryStyle.line, lineWidth: 1) }
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }.padding(.bottom, 6)
    }
    private func load(reset: Bool, forceRefresh: Bool = false) async {
        if !reset && loading { return }
        let stamp=UUID();requestID=stamp;loading=true;error=nil
        defer { if requestID == stamp { loading = false } }
        let next=reset ? 1 : page+1
        do {
            let result=try await repository.list(mine:mine,query:query,sort:sort,page:next,forceRefresh:forceRefresh, onCached: { cached in
                guard requestID == stamp, reset else { return }
                fonts = cached.items; total = cached.count ?? cached.items.count; page = next
            })
            guard requestID==stamp, !Task.isCancelled else { return }
            fonts=reset ? result.items : fonts+result.items;total=result.count ?? result.items.count;page=next;error=nil
        } catch {
            guard requestID == stamp, !Task.isCancelled, !CatalogLoadError.isCancellation(error) else { return }
            self.error = error.localizedDescription
        }
    }
}

private struct FontSpecimenImage: View {
    let font: CloudFont
    let resourceID: String?
    var body: some View {
        let owner = CloudFontRepository.shared.owner
        let identity = "\(font.id):\(font.version):\(resourceID ?? "cover")"
        CachedPreviewImage(request: PreviewImageRequest(
            key: .account(owner, category: "font-images", identity: identity),
            url: resourceID.flatMap { font.images[$0] }.flatMap(URL.init(string:)),
            refreshURL: {
                let updated: CloudFont = try await CloudFontRepository.shared.request("families/\(font.id)/", forceRefresh: true)
                guard await CloudFontRepository.shared.owner == owner, updated.version == font.version else { throw CancellationError() }
                return resourceID.flatMap { updated.images[$0] }.flatMap(URL.init(string:))
            }))
            .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct FontDetailScreen: View {
    let font: CloudFont
    var documentID: UUID?
    var onUse: ((DiaryFontReference)->Void)?
    @ObservedObject private var repository=CloudFontRepository.shared
    @State private var face=""
    @State private var favorite=false
    @State private var text="把日子写成诗 Aa 123"
    @State private var selected: DiaryFontReference?
    @State private var loading=false
    @State private var error: String?
    @State private var downloaded=false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Text(font.title).font(.title.bold())
                Text(font.content.author).foregroundStyle(.secondary)
                FontSpecimenImage(font: font, resourceID: font.content.cover).frame(maxWidth:.infinity).frame(height:280)
                HStack { Text(font.priceLabel).foregroundStyle(.pink);Spacer();Button(favorite ? "已收藏" : "收藏") { Task { do { try await repository.favorite(font,value:!favorite);favorite.toggle() } catch { self.error=error.localizedDescription } } } }
                Text(font.content.description)
                Text(font.content.languages.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)
                Picker("字重",selection:$face) { ForEach(font.content.faces) { Text($0.label).tag($0.id) } }
                if let selected {
                    TextField("输入试写文字",text:$text).textFieldStyle(.roundedBorder)
                    Text(text).font(Font(DiaryFontCatalog.shared.font(selected,size:28)))
                    if let warning=DiaryFontCatalog.shared.warning(selected,text:text) { Text(warning).font(.caption).foregroundStyle(.secondary) }
                }
                ForEach(font.content.previews,id:\.self) { id in FontSpecimenImage(font: font, resourceID: id).frame(maxWidth:.infinity).frame(height:280) }
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
                if downloaded && onUse == nil { Text("字体已加入我的字体。打开手帐的文字编辑器即可使用。") }
            }.padding()
        }.navigationTitle("字体详情").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge:.bottom) {
            VStack {
                if loading { ProgressView("下载、校验并准备字体…") }
                else {
                    BillingContentAction(owner:repository.owner,kind:"font",targetID:font.id,title:onUse == nil ? "获取并下载字体" : "下载并使用") {
                        Task { await use() }
                    }
                }
            }.padding().frame(maxWidth:.infinity).background(.regularMaterial)
        }
        .onAppear { face=font.content.default_face;favorite=font.favorite ?? false }
        .onChange(of:repository.generation) { _,_ in selected=nil;downloaded=false }
    }
    private func use() async {
        guard !loading else { return };loading=true;error=nil
        defer { loading=false }
        do {
            let reference=try await repository.use(font,face:face,documentID:documentID)
            guard !Task.isCancelled else { return }
            selected=reference;downloaded=true;onUse?(reference)
        } catch { self.error=error.localizedDescription }
    }
}

struct FontStorageScreen: View {
    @State private var records=FontDisk.records()
    @State private var removing: FontLocalRecord?
    @State private var error: String?
    var body: some View {
        List {
            Section { Text("字体文件 \(ByteCountFormatter.string(fromByteCount:Int64(records.reduce(0) { $0+$1.byteSize }),countStyle:.file))") }
            Section(footer:Text("清除本机下载不会取消购买权益。已使用这些字体的作品可能需要联网重新下载；请在关闭编辑器后清理。")) {
                ForEach(records) { record in
                    HStack { VStack(alignment:.leading) { Text(record.entry.displayName);Text("v\(record.entry.version) · \(ByteCountFormatter.string(fromByteCount:Int64(record.byteSize),countStyle:.file))").font(.caption) };Spacer();Button("清除下载",role:.destructive) { removing=record } }
                }
            }
            if let error { Text(error) }
        }.navigationTitle("字体存储")
        .confirmationDialog("清除下载后，相关作品可能暂时无法离线显示原字体。",isPresented:Binding(get:{removing != nil},set:{if !$0 {removing=nil}}),titleVisibility:.visible) {
            Button("清除本机下载",role:.destructive) {
                guard let record=removing else{return}
                Task { do { if DiaryFontCatalog.shared.isRegistered(record.entry) { throw BillingFailure("字体已用于本次会话，请重新启动 App 后在打开作品前清理") };try await FontDownloadManager.shared.remove(record);DiaryFontCatalog.shared.forgetDownloaded(record.entry);records=FontDisk.records() } catch { self.error=error.localizedDescription };removing=nil }
            }
        }
    }
}
