import SwiftUI
import PhotosUI

struct DiaryAlbumComposerScreen: View {
    let completed: (DiaryBook) -> Void
    @State private var model: DiaryAlbumComposer
    @State private var step = 0
    @State private var selection: [PhotosPickerItem] = []
    @State private var editingPage: UUID?
    @State private var confirmingDiscard = false
    @State private var confirmUnassigned = false
    @State private var showSettings = false
    @Environment(\.dismiss) private var dismiss
    @State private var sorting = false
    @State private var changingDesign = false
    @State private var pendingTheme: DiaryAlbumTheme?
    @State private var pendingPalette: String?
    @State private var pendingDensity: DiaryAlbumDensity?
    @State private var spreadView = true
    init(model: DiaryAlbumComposer, completed: @escaping (DiaryBook) -> Void) {
        self.completed = completed
        _model = State(initialValue: model)
        _step = State(initialValue: model.draft.pages.isEmpty ? 0 : 2)
    }
    var body: some View {
        dialogs
            .task(id: selection) {
                let items = selection
                guard !items.isEmpty else { return }
                await model.importPhotos(items)
                selection = []
            }
            .onDisappear { model.persist() }
            .navigationBarBackButtonHidden(model.busy)
            .interactiveDismissDisabled(model.busy)
            .tint(DiaryLibraryStyle.accent)
    }
    private var content: some View {
            Group {
                switch step {
                case 0: photosStep
                case 1: photosStep
                default: overview
                }
            }
            .background(DiaryLibraryStyle.background)
            .navigationTitle(step < 2 ? "第 2 步 · 添加照片" : "第 3 步 · 预览并调整")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("撤销", systemImage: "arrow.uturn.backward") { model.undo() }.disabled(!model.canUndo || model.busy)
                    Button("重做", systemImage: "arrow.uturn.forward") { model.redo() }.disabled(!model.canRedo || model.busy)
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .disabled(model.busy)
            .overlay {
                if model.busy {
                    VStack(spacing: 12) {
                        ProgressView(model.progress)
                        Text("照片较多或需要从 iCloud 下载时，请稍候。").font(.caption).foregroundStyle(.secondary)
                        if model.saving { Button("取消保存") { model.cancelSaving() } }
                    }
                        .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
    }
    private var presentedSheets: some View {
        content
            .sheet(isPresented: Binding(get: { editingPage != nil }, set: { if !$0 { editingPage = nil } })) {
                if let id = editingPage { DiaryAlbumPageEditor(model: model, pageID: id) }
            }
            .sheet(isPresented: $sorting) {
                NavigationStack { photoOrderList.navigationTitle("整理照片").toolbar { Button("完成") { sorting = false } } }
            }
            .sheet(isPresented: $changingDesign) {
                NavigationStack { DiaryAlbumDesignPicker(model: model).padding().navigationTitle("更换相册设计").toolbar { Button("完成") { changingDesign = false } } }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { settings.navigationTitle("调整相册设置").toolbar { Button("完成") { showSettings = false } } }
            }
    }
    private var dialogs: some View {
        presentedSheets
            .alert("制作相册", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
                Button("知道了") { model.message = nil }
            } message: { Text(model.message ?? "") }
            .confirmationDialog("放弃这份制作草稿？", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("放弃并重新开始", role: .destructive) { model.discard(); step = 0 }
            } message: { Text("仅移除这份制作草稿，系统相册和书架中的作品不会改变。") }
            .confirmationDialog("还有 \(model.draft.unassigned.count) 张照片未放入正文", isPresented: $confirmUnassigned, titleVisibility: .visible) {
                Button("自动添加到新页面") { model.change { $0.appendUnassigned() } }
                Button("仅保存已排入的照片") { Task { await finish() } }
            } message: { Text("未排入页面的照片不会保存到这本相册，原照片仍保留在系统相册中。") }
    }
    private var picker: some View {
        let title = model.draft.photos.isEmpty ? "选择照片" : "追加照片"
        return PhotosPicker(selection: $selection, maxSelectionCount: 200, selectionBehavior: .ordered, matching: .images) {
            Label(title, systemImage: "plus")
        }
    }
    private var photosStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(model.draft.theme.title) · \(model.draft.theme.palette(model.draft.paletteID).title) · \((DiaryPagePreset(rawValue: model.draft.size) ?? .b5).albumTitle)")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button("更换") { changingDesign = true }.font(.caption)
            }
            Text("添加照片").font(.headline)
            Text("添加你的照片，按所选设计自动成册。照片增加时自动增加页面。")
                .font(.caption).foregroundStyle(.secondary)
            DiaryPhotoSelectionGrid(count: model.draft.photos.count, emptyPrompt: "点这里添加照片，自动排入相册",
                picker: { expanded in
                    PhotosPicker(selection: $selection, maxSelectionCount: 200, selectionBehavior: .ordered, matching: .images) {
                        DiaryPhotoAddLabel(expanded: expanded)
                    }
                }, thumbnail: { index in
                    DiaryAlbumPhotoThumbnail(photo: model.draft.photos[index], directory: model.directory)
                }, remove: { index in model.removePhoto(model.draft.photos[index].id) })
            HStack {
                Button("整理顺序", systemImage: "arrow.up.arrow.down") { sorting = true }.disabled(model.draft.photos.isEmpty)
                Spacer()
                Picker("密度", selection: value(\.density)) { ForEach(DiaryAlbumDensity.allCases) { Text($0.title).tag($0) } }.labelsHidden()
            }.font(.caption)
            Text(model.draft.photos.isEmpty ? "尚未选择照片" : "已选 \(model.draft.photos.count) 张 · 预计约 \(estimatedPageCount) 页")
                .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            Text("首次按拍摄时间排列，无时间的照片放在末尾。可追加、移除或手动排序。")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }.padding(16)
    }
    private var photoOrderList: some View {
        List {
            Section {
                if model.restored { Label("已恢复上次制作草稿", systemImage: "clock.arrow.circlepath").font(.footnote) }
                Text("先选想留下的照片，不必计算页数。首次按拍摄时间排列；没有拍摄时间的照片放在末尾。")
                    .font(.subheadline).foregroundStyle(.secondary)
                picker
                if !model.draft.photos.isEmpty {
                    Menu("排序方式", systemImage: "arrow.up.arrow.down") {
                        Button("按拍摄时间") { model.change { $0.sortPhotos(byDate: true) } }
                        Button("恢复选择顺序") { model.change { $0.sortPhotos(byDate: false) } }
                    }
                    Text("共 \(model.draft.photos.count) 张 · 拖动右侧把手调整顺序；向左滑动移除。追加照片不会打乱现有顺序。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(model.draft.photos) { photo in
                    HStack(spacing: 12) {
                        DiaryAlbumPhotoThumbnail(photo: photo, directory: model.directory).frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("照片 \((model.draft.photos.firstIndex(where: { $0.id == photo.id }) ?? 0) + 1)")
                            if let date = photo.date { Text(date, format: .dateTime.year().month().day()).font(.caption).foregroundStyle(.secondary) }
                            else { Text("无拍摄时间").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                .onMove { source, destination in model.change { $0.photos.move(fromOffsets: source, toOffset: destination) } }
                .onDelete { offsets in for id in offsets.map({ model.draft.photos[$0].id }) { model.removePhoto(id) } }
            }
            Section { Button("放弃草稿，重新开始", role: .destructive) { confirmingDiscard = true } }
        }.environment(\.editMode, .constant(.active))
    }
    private var settings: some View {
        Form {
            Section("相册名称") {
                TextField("相册名称", text: value(\.title))
                Text("1–60 个字，可在书架中再次修改。").font(.caption).foregroundStyle(.secondary)
            }
            Section("整本结构") {
                Picker("用途", selection: Binding(get: { model.draft.structure }, set: { selection in
                    model.change { $0.structure = selection; $0.groupByDate = selection.groupsByDate }
                })) { ForEach(DiaryAlbumStructure.allCases) { Text($0.title).tag($0) } }
                Toggle(model.draft.structure == .annual ? "按月份组织照片" : "按拍摄日期组织照片", isOn: value(\.groupByDate))
                Text("缺少时间的照片保持顺序，不推测地点和事件。已有页面保留原分组，设置用于新生成的页面。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("配色") {
                DiaryAlbumPalettePicker(theme: model.draft.theme, selected: model.draft.paletteID) { id in pendingPalette = id }
            }
            Section("视觉主题") {
                ForEach(DiaryAlbumTheme.allCases) { theme in
                    Button { pendingTheme = theme } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 6).fill(Color(uiColor: DiaryPageRenderer.color(theme.paper)))
                                .overlay { Image(systemName: "photo").foregroundStyle(Color(uiColor: DiaryPageRenderer.color(theme.ink))) }
                                .frame(width: 44, height: 56).overlay(RoundedRectangle(cornerRadius: 6).stroke(.gray.opacity(0.3)))
                            VStack(alignment: .leading, spacing: 4) { Text(theme.title).foregroundStyle(.primary); Text(theme.detail).font(.caption).foregroundStyle(.secondary) }
                            Spacer(); if model.draft.theme == theme { Image(systemName: "checkmark.circle.fill") }
                        }
                    }
                }
                if !model.draft.pages.isEmpty { Text("主题应用于未锁定页面，照片、文字和裁切保留，可撤销。").font(.caption).foregroundStyle(.secondary) }
            }
            Section("规格与排版") {
                Picker("尺寸", selection: value(\.size)) { ForEach(DiaryPagePreset.allCases) { Text($0.albumTitle).tag($0.rawValue) } }
                    .disabled(!model.draft.pages.isEmpty)
                Picker("照片密度", selection: Binding(get: { model.draft.density }, set: { density in if model.draft.pages.isEmpty { model.change { $0.density = density } } else { pendingDensity = density } })) { ForEach(DiaryAlbumDensity.allCases) { Text($0.title).tag($0) } }
                if model.draft.pages.isEmpty {
                    Toggle("封面复用第一张照片", isOn: value(\.reuseCoverPhoto))
                    Text("正文中每张照片只使用一次；封面可以另选照片。照片较少时自动采用疏朗版式。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("预计 \(estimatedPageCount) 页，含封面和照片正文").font(.subheadline.weight(.medium))
                } else { Text("尺寸在生成后固定；密度用于追加照片。现有页面可逐页换版式。").font(.caption).foregroundStyle(.secondary) }
            }
        }
            .confirmationDialog("重新按照片密度分页？", isPresented: Binding(get: { pendingDensity != nil }, set: { if !$0 { pendingDensity = nil } })) {
                if let density = pendingDensity {
                    Button("重新分页（可撤销）") { model.change { $0.repaginate(density) }; pendingDensity = nil }
                    Button("仅用于追加照片") { model.change { $0.density = density }; pendingDensity = nil }
                }
            } message: { Text("仅调整未锁定且没有文字或裁切调整的普通照片页；精修页、跨页及复制页保留。") }
            .confirmationDialog("更换未锁定页面的主题？", isPresented: Binding(get: { pendingTheme != nil }, set: { if !$0 { pendingTheme = nil } })) {
                if let theme = pendingTheme {
                    Button("应用「\(theme.title)」（可撤销）") { model.change { $0.applyTheme(theme) }; pendingTheme = nil }
                }
            } message: { Text("照片、文字和裁切保留；主题会改变未锁定页面的纸色与版式。") }
            .confirmationDialog("更换未锁定页面的配色？", isPresented: Binding(get: { pendingPalette != nil }, set: { if !$0 { pendingPalette = nil } })) {
                if let id = pendingPalette {
                    Button("应用配色（可撤销）") { model.change { $0.applyPalette(id) }; pendingPalette = nil }
                }
            } message: { Text("纸面、文字与强调色一起调整，照片原色保持不变。") }
    }
    private var estimatedPageCount: Int { var copy = model.draft; copy.generate(); return copy.pages.count }
    private func value<T>(_ keyPath: WritableKeyPath<DiaryAlbumDraft, T>) -> Binding<T> {
        Binding(get: { model.draft[keyPath: keyPath] }, set: { value in model.change { draft in
            let oldTitle = draft.title
            draft[keyPath: keyPath] = value
            if draft.title != oldTitle {
                for i in draft.pages.indices where draft.pages[i].role == .cover && !draft.pages[i].locked && draft.pages[i].title == oldTitle {
                    draft.pages[i].title = draft.title
                }
            }
        } })
    }
    private var overview: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.draft.title).font(.title2.bold())
                        Text("\(model.draft.photos.count) 张照片 · \(model.draft.pages.count) 页").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(); Button("设置", systemImage: "slider.horizontal.3") { showSettings = true }.labelStyle(.iconOnly)
                }
                Text("点击页面调整版式、文字和取景。长按照片可制作跨页大图，也可拖到另一张照片上交换，拖到照片页空白处移动；锁定页面不参与调整。")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack {
                    picker
                    Spacer()
                    Menu("添加页面", systemImage: "doc.badge.plus") {
                        ForEach(DiaryAlbumPageRole.allCases.filter { $0 != .cover }) { role in
                            Button(role.title) { model.change { $0.pages.append(DiaryAlbumPage(role: role, theme: $0.theme, paletteID: $0.paletteID)) } }
                        }
                    }
                }
                if !model.draft.unassigned.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("待分配 · \(model.draft.unassigned.count) 张").font(.headline)
                            Spacer()
                            Button("自动加页") { model.change { $0.appendUnassigned() } }
                        }
                        ScrollView(.horizontal) {
                            HStack { ForEach(model.draft.unassigned) { photo in draggablePhoto(photo).frame(width: 72, height: 72) } }
                        }
                    }.padding().background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                }
                Picker("预览方式", selection: $spreadView) { Text("跨页预览").tag(true); Text("页面总览").tag(false) }.pickerStyle(.segmented)
                if spreadView {
                    LazyVStack(spacing: 24) {
                        ForEach(previewSpreads, id: \.first!.id) { pair in
                            HStack(alignment: .top, spacing: 8) {
                                ForEach(pair) { page in pageCard(page).frame(maxWidth: .infinity) }
                                if pair.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                            }
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 24) {
                        ForEach(model.draft.pages) { page in pageCard(page) }
                    }
                }
                Button("重新适配未锁定页面的版式") { model.change { $0.rearrange() } }
                    .font(.footnote)
            }.padding(20)
        }
        .onScrollPhaseChange { _, phase in DiaryAlbumPreviewService.shared.scrolling = phase != .idle }
        .onDisappear { DiaryAlbumPreviewService.shared.scrolling = false }
    }
    private var previewSpreads: [[DiaryAlbumPage]] {
        var result: [[DiaryAlbumPage]] = [], index = 0
        let pages = model.draft.pages
        while index < pages.count {
            let page = pages[index]
            if index + 1 < pages.count, page.role != .cover,
               (page.spreadID == nil && pages[index + 1].spreadID == nil || page.spreadID != nil && page.spreadID == pages[index + 1].spreadID) {
                result.append([page, pages[index + 1]]); index += 2
            } else { result.append([page]); index += 1 }
        }
        return result
    }
    private func draggablePhoto(_ photo: DiaryAlbumPhoto, source: UUID? = nil) -> some View {
        DiaryAlbumPhotoThumbnail(photo: photo, directory: model.directory)
            .clipShape(RoundedRectangle(cornerRadius: 6)).draggable(photo.id.uuidString + "|" + (source?.uuidString ?? ""))
            .contextMenu {
                Button("制作跨页大图") { model.change { $0.makeSpread(photoID: photo.id) } }
            }
            .accessibilityLabel("照片，可拖动分配到页面")
    }
    private func pageCard(_ page: DiaryAlbumPage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { editingPage = page.id } label: {
                DiaryAlbumPagePreview(page: page, draft: model.draft, directory: model.directory)
                    .overlay(alignment: .topTrailing) {
                        if page.locked { Image(systemName: "lock.fill").padding(8).background(.regularMaterial, in: Circle()).padding(6) }
                    }
            }.buttonStyle(.plain)
                .dropDestination(for: String.self) { ids, _ in
                    guard !page.locked, let text = ids.first, let id = UUID(uuidString: String(text.split(separator: "|").first ?? "")) else { return false }
                    model.change { $0.movePhoto(id, to: page.id, sourcePageID: dragSource(text)) }; return true
                }
            HStack {
                Text("\((model.draft.pages.firstIndex(where: { $0.id == page.id }) ?? 0) + 1) · \(page.role.title)").font(.caption)
                Spacer()
                Menu {
                    Button(page.locked ? "解锁页面" : "锁定页面", systemImage: page.locked ? "lock.open" : "lock") { toggleLock(page) }
                    Button("前移一页") { movePage(page.id, by: -1) }.disabled(page.locked || model.draft.pages.first?.id == page.id)
                    Button("后移一页") { movePage(page.id, by: 1) }.disabled(page.locked || model.draft.pages.last?.id == page.id)
                    Button("复制此页") { model.change { value in
                        var copy = page; copy.id = UUID(); copy.locked = false; copy.spreadID = nil; copy.spreadSide = nil
                        if copy.role == .cover { copy.role = .photos }
                        copy.placements = copy.placements.map { var p = $0; p.id = UUID(); return p }
                        if let index = value.pages.firstIndex(where: { $0.id == page.id }) { value.pages.insert(copy, at: index + 1) }
                    } }
                    Button(page.spreadID == nil ? "删除页面" : "删除这组跨页", role: .destructive) { model.change { value in
                        let ids = relatedIDs(page)
                        value.pages.removeAll { ids.contains($0.id) }
                    } }.disabled(relatedPages(page).contains(where: \.locked))
                } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("页面操作")
            }
            if !page.placements.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) { ForEach(page.placements) { slot in
                        if let photo = model.draft.photos.first(where: { $0.id == slot.photoID }) {
                            draggablePhoto(photo, source: page.id).frame(width: 40, height: 40)
                                .dropDestination(for: String.self) { ids, _ in
                                    guard !page.locked, let text = ids.first, let id = UUID(uuidString: String(text.split(separator: "|").first ?? "")) else { return false }
                                    model.change { $0.movePhoto(id, to: page.id, replacing: photo.id, sourcePageID: dragSource(text)) }; return true
                                }
                        }
                    } }
                }
            }
        }
    }
    private func dragSource(_ text: String) -> UUID? {
        let parts = text.split(separator: "|")
        return parts.count > 1 ? UUID(uuidString: String(parts[1])) : nil
    }
    private func update(_ id: UUID, _ body: (inout DiaryAlbumPage) -> Void) {
        model.change { value in if let i = value.pages.firstIndex(where: { $0.id == id }) { body(&value.pages[i]) } }
    }
    private func relatedPages(_ page: DiaryAlbumPage) -> [DiaryAlbumPage] {
        guard let pair = page.spreadID else { return [page] }
        return model.draft.pages.filter { $0.spreadID == pair }
    }
    private func relatedIDs(_ page: DiaryAlbumPage) -> Set<UUID> { Set(relatedPages(page).map(\.id)) }
    private func toggleLock(_ page: DiaryAlbumPage) {
        let ids = relatedIDs(page)
        model.change { value in
            for i in value.pages.indices where ids.contains(value.pages[i].id) { value.pages[i].locked = !page.locked }
        }
    }
    private func movePage(_ id: UUID, by offset: Int) {
        model.change { value in
            guard let index = value.pages.firstIndex(where: { $0.id == id }) else { return }
            let pair = value.pages[index].spreadID
            let indexes = value.pages.indices.filter { pair == nil ? value.pages[$0].id == id : value.pages[$0].spreadID == pair }
            guard let first = indexes.first, let last = indexes.last,
                  !indexes.contains(where: { value.pages[$0].locked }) else { return }
            let adjacent = offset < 0 ? first - 1 : last + 1
            guard value.pages.indices.contains(adjacent) else { return }
            let adjacentPair = value.pages[adjacent].spreadID
            let neighbors = value.pages.indices.filter { adjacentPair == nil ? $0 == adjacent : value.pages[$0].spreadID == adjacentPair }
            guard !neighbors.contains(where: { value.pages[$0].locked }) else { return }
            let moving = indexes.map { value.pages[$0] }
            let targetID = value.pages[neighbors.first!].id
            let afterID = value.pages[neighbors.last!].id
            value.pages.removeAll { page in moving.contains { $0.id == page.id } }
            let insertion = offset < 0 ? value.pages.firstIndex { $0.id == targetID }! : value.pages.firstIndex { $0.id == afterID }! + 1
            value.pages.insert(contentsOf: moving, at: insertion)
        }
    }
    private var bottomBar: some View {
        HStack(spacing: 16) {
            if step == 2 { Button("添加照片") { step = 0 } }
            Button {
                if step < 2 { model.change { $0.generate() }; step = 2 }
                else if !model.draft.unassigned.isEmpty { confirmUnassigned = true }
                else { Task { await finish() } }
            } label: { Text(step < 2 ? "生成相册预览" : "完成并保存").frame(maxWidth: .infinity).padding(.vertical, 8) }
                .buttonStyle(.borderedProminent)
                .disabled(model.busy || (step < 2 && model.draft.photos.isEmpty) || (step == 2 && model.draft.pages.isEmpty) || (step > 0 && !validTitle))
        }.padding().background(.regularMaterial)
    }
    private var validTitle: Bool { let title = model.draft.title.trimmingCharacters(in: .whitespacesAndNewlines); return !title.isEmpty && title.count <= 60 }
    private func finish() async { if let book = await model.finish() { completed(book) } }
}
