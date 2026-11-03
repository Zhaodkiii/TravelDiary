import SwiftUI
import Combine
import PhotosUI
import UIKit
import CoreLocation

struct CreationFlowView: View {
    @StateObject private var model: CreationCoordinator
    var initialSource: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var picks: [PhotosPickerItem] = []
    @State private var showPicker = false
    @State private var showCamera = false
    @State private var showStickers = false
    @State private var editor: DiaryEditorSession?
    @State private var loading = false
    @State private var assetDetail: CreationAsset?
    @State private var books: [DiaryBook] = []
    @State private var restored = false
    @State private var launched = false
    @StateObject private var locator = CreationLocation()
    init(owner: String, draft: CreationDraft? = nil, bookID: UUID? = nil, initialSource: String? = nil) {
        _model = StateObject(wrappedValue: CreationCoordinator(owner: owner, draft: draft, bookID: bookID))
        self.initialSource = initialSource
    }
    private var baseContent: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label("\(model.draft.step + 1) / 3 · \(["选照片", "补充故事", "选成品效果"][min(2, model.draft.step)])", systemImage: "book.pages").font(.subheadline).foregroundStyle(.secondary)
                    if model.draft.handoffID != nil {
                        Text("这份草稿已进入制作。继续会恢复进度，不会自动重复请求。修改素材或故事请新建一份制作。").font(.callout)
                        Button("继续制作") { Task { await openEditor() } }.buttonStyle(.borderedProminent)
                    } else {
                        switch model.draft.step {
                        case 0: photoStep
                        case 1: storyStep
                        default: designStep
                        }
                    }
                    if let error = model.error { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.orange).font(.callout) }
                }.padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(["收集这一刻", "想留下什么？", "做成喜欢的样子"][min(2, model.draft.step)])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("存草稿") { Task { await model.persist(); if model.error == nil { dismiss() } } }.disabled(loading || model.busy) }
                ToolbarItem(placement: .primaryAction) { if model.draft.step > 0 && model.draft.handoffID == nil { Button("上一步") { model.draft.step -= 1 } } }
            }
            .safeAreaInset(edge: .bottom) { footer }
            .disabled(model.busy || loading)
            .overlay { if model.busy || loading { ProgressView(model.busy ? model.status : "正在保存照片…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .task {
                guard !restored else { return }; restored = true
                books = (try? await DiaryDocumentStore(ownerID: model.draft.owner).listBooks()) ?? []
                await model.loadThumbnails()
                await model.persist()
                if model.draft.handoffID == nil {
                    if initialSource == "相册" { showPicker = true }
                    if initialSource == "拍照" { showCamera = true }
                }
            }
            .onChange(of: model.draft) { _, _ in Task { await model.persist() } }
            .interactiveDismissDisabled()
        }.tint(Color(red: 0.24, green: 0.39, blue: 0.34))
    }
    var body: some View {
        mediaContent
            .sheet(item: $assetDetail) { asset in assetEditor(asset) }
            .fullScreenCover(item: $editor, onDismiss: { if model.draft.published { dismiss() } }) { session in
                DiaryEditorScreen(session: session, creationRequest: model.draft.request(), creationAutoStart: launched)
            }
    }
    private var mediaContent: some View {
        baseContent
            .photosPicker(isPresented: $showPicker, selection: $picks, maxSelectionCount: max(1, 30 - model.draft.assets.filter { !$0.isSticker }.count), selectionBehavior: .ordered, matching: .images)
            .onChange(of: picks) { _, items in
                guard !items.isEmpty else { return }
                loading = true
                Task {
                    for item in items {
                        do {
                            guard let bytes = try await item.loadTransferable(type: Data.self) else { throw DiaryEditorError.invalidImage }
                            await model.add(bytes, name: "相册照片")
                        } catch { model.error = "有照片读取失败，请重新从相册选择。" }
                    }
                    picks = []; loading = false
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CreationCamera { bytes in await model.add(bytes, name: "拍摄照片") }
            }
            .sheet(isPresented: $showStickers) {
                MaterialLibraryBrowser(keepsOpenAfterAdding: true, onSelectForCreation: { bytes, name, material in
                    await model.add(bytes, name: name, sticker: true, material: material)
                    model.draft.stickerMode = "我来选"
                    await model.persist()
                })
            }
    }
    private var photoStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("可多次拍摄，也可以混合加入相册照片。选中的照片都会保留。").foregroundStyle(.secondary)
            HStack {
                Button("相册多选", systemImage: "photo.on.rectangle") { showPicker = true }
                Spacer()
                Button("继续拍照", systemImage: "camera") { showCamera = true }
            }.buttonStyle(.bordered).disabled(model.draft.assets.filter { !$0.isSticker }.count >= 30)
            Text("本页 \(model.draft.photos.count) 张 · 素材篮 \(model.draft.assets.filter { !$0.isSticker }.count) / 30").font(.subheadline)
            if model.draft.photos.count > 8 { Text("超过 8 张会分批处理。建议一页选 1–8 张，让照片更清楚；未选照片继续留在草稿。 ").font(.caption).foregroundStyle(.secondary) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 12) {
                ForEach(model.draft.assets.filter { !$0.isSticker }) { asset in
                    Button { assetDetail = asset } label: {
                        VStack(alignment: .leading) {
                            thumbnail(asset).frame(height: 130).clipped()
                            HStack { Text(model.draft.heroID == asset.id ? "主照" : "照片"); Spacer(); Image(systemName: asset.included ? "checkmark.circle.fill" : "circle") }
                            if !asset.note.isEmpty { Text(asset.note).lineLimit(2).font(.caption) }
                        }.padding(10).background(.background, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain).accessibilityLabel("\(asset.name)，\(asset.included ? "已选" : "未选")，点击编辑说明或主照")
                }
            }
            if model.draft.assets.isEmpty { ContentUnavailableView("把这一段经历收进来", systemImage: "photo.stack", description: Text("至少选一张照片，就能开始制作。")) }
        }
    }
    private var storyStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("这些都可以跳过。你的说明会用于标题、旁注、背景和构图。").foregroundStyle(.secondary)
            Text("这一刻的心情").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82))]) {
                ForEach(["轻松", "开心", "感动", "平静", "怀念", "疲惫"], id: \.self) { mood in
                    Button {
                        if model.draft.brief.moods.contains(mood) { model.draft.brief.moods.removeAll { $0 == mood } }
                        else if model.draft.brief.moods.count < 3 { model.draft.brief.moods.append(mood) }
                    } label: { Label(mood, systemImage: model.draft.brief.moods.contains(mood) ? "checkmark.circle.fill" : "circle").frame(minHeight: 44) }.buttonStyle(.bordered)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack { ForEach(["自动", "城市漫游", "山野徒步", "海边假期", "聚餐", "庆祝", "日常片刻"], id: \.self) { theme in
                    Button { model.draft.brief.theme = theme } label: {
                        Text(theme).padding(.horizontal, 12).frame(minHeight: 44)
                            .background(model.draft.brief.theme == theme ? Color.accentColor.opacity(0.15) : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                    }.buttonStyle(.plain).accessibilityAddTraits(model.draft.brief.theme == theme ? .isSelected : [])
                } }
            }
            field("自定义主题", text: $model.draft.brief.theme, hint: "例如：山野徒步、聚餐、日常片刻")
            field("想记录的话", text: $model.draft.brief.story, hint: "发生了什么，哪一刻最想留下？")
            Text("\(model.draft.brief.story.count) / 1000 字").font(.caption).foregroundStyle(.secondary)
            field("场景补充", text: $model.draft.brief.scene, hint: "例如：傍晚在山顶等日落")
            field("地点", text: $model.draft.brief.location, hint: "手动填写，不会自动使用拍摄地点")
            Button("使用当前位置", systemImage: "location") { locator.locate { model.draft.brief.location = $0 } }
            Text(locator.message.isEmpty ? "当前位置不一定是这些照片拍摄的地方，请确认后使用。" : locator.message).font(.caption).foregroundStyle(.secondary)
            Toggle("把地点写到页面上", isOn: $model.draft.brief.displaysLocation)
            DisclosureGroup("更多故事细节") {
                VStack(spacing: 16) {
                    field("事件日期或范围", text: $model.draft.brief.eventDate, hint: "不填就不会自动写日期")
                    field("人物关系或称呼", text: $model.draft.brief.relationships, hint: "仅使用你确认的称呼")
                    field("必须原样使用的话", text: $model.draft.brief.exactQuote, hint: "文字不会被擅自改写")
                    field("仅供理解", text: $model.draft.brief.privateContext, hint: "不直接写进成品的补充")
                    field("不要出现的词语", text: $model.draft.brief.forbidden, hint: "多个词语用逗号分隔")
                }.padding(.top)
            }
        }
    }
    private var designStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            DiaryAIDesignChooser(selection: $model.draft.design, photos: model.draft.photos.prefix(3).compactMap { model.thumbnails[$0.id] })
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("贴纸", selection: $model.draft.stickerMode) { ForEach(["自动搭配", "我来选", "不加贴纸"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                    if model.draft.stickerMode == "自动搭配" { Text("从现有内置素材搭配少量装饰，可由 AI 精选。不会额外生成贴纸。").font(.caption).foregroundStyle(.secondary) }
                    if model.draft.stickerMode == "我来选" { Button("选择贴纸 · \(model.draft.stickers.count)/12", systemImage: "face.smiling") { showStickers = true } }
                    if model.draft.stickerMode != "不加贴纸" {
                        ScrollView(.horizontal) { HStack { ForEach(model.draft.stickers) { asset in
                            VStack { thumbnail(asset).frame(width: 70, height: 70); Button("移除") { Task { await model.remove(asset) } }.font(.caption) }
                        } } }
                    }
                }
            }
            GroupBox {
                VStack(spacing: 14) {
                    Toggle("自动生成背景", isOn: $model.draft.background)
                    Toggle("添加可编辑文字", isOn: $model.draft.writing)
                    if model.draft.writing { Picker("文字多少", selection: $model.draft.textDensity) { ForEach(["少量文字", "适量记录", "丰富记录"], id: \.self) { Text($0) } } }
                    Toggle("允许照片裁剪", isOn: $model.draft.allowsCrop)
                    Picker("保存到", selection: $model.draft.targetBookID) {
                        Text("新建旅行随记").tag(Optional<UUID>.none)
                        ForEach(books.filter { $0.defaultPageSize == DiaryPagePreset.spread.size }) { book in Text(book.title + " · 新跨页").tag(Optional(book.id)) }
                    }
                }
            }
            Text("\(model.draft.photos.count) 张照片 · \(model.draft.design.layout.name) × \(model.draft.design.style.name)").font(.headline)
            Text("点击开始后，所选图片和用于创作的说明会发送给 AI 服务。完成后可检查、修改并保存；不会覆盖已有跨页。").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var footer: some View {
        VStack(spacing: 8) {
            if model.draft.handoffID == nil {
                if model.draft.step == 0 && !model.draft.photos.isEmpty {
                    Button("暂不写故事，直接选效果") { model.draft.step = 2 }.font(.subheadline)
                }
                Button {
                    model.error = nil
                    if model.draft.step < 2 { model.draft.step += 1 }
                    else { Task { await openEditor() } }
                } label: { Text(model.draft.step == 2 ? "开始制作" : model.draft.step == 0 ? "继续：补充故事" : "继续：选成品效果").font(.headline).frame(maxWidth: .infinity).padding(16) }
                .buttonStyle(.borderedProminent).disabled(loading || model.busy || (model.draft.step == 0 && model.draft.photos.isEmpty))
            }
        }.padding().background(.regularMaterial)
    }
    private func openEditor() async {
        guard let session = await model.prepare() else { return }
        do { launched = try await model.claimLaunch(); editor = session }
        catch { model.error = error.localizedDescription }
    }
    private func thumbnail(_ asset: CreationAsset) -> some View {
        Group { if let image = model.thumbnails[asset.id] { Image(uiImage: image).resizable().scaledToFit() } else { Image(systemName: "photo").foregroundStyle(.secondary) } }
    }
    private func field(_ title: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.subheadline.weight(.medium)); TextField(hint, text: text, axis: .vertical).lineLimit(1...6).padding(12).background(.background, in: RoundedRectangle(cornerRadius: 10)) }
    }
    private func assetEditor(_ asset: CreationAsset) -> some View {
        NavigationStack {
            Form {
                thumbnail(asset).frame(maxHeight: 230)
                if let index = model.draft.assets.firstIndex(where: { $0.id == asset.id }) {
                    Toggle("用于这一页", isOn: $model.draft.assets[index].included)
                    Toggle("设为主照", isOn: Binding(get: { model.draft.heroID == asset.id }, set: { model.draft.heroID = $0 ? asset.id : nil }))
                    TextField("这张照片的故事", text: $model.draft.assets[index].note, axis: .vertical)
                    HStack {
                        Button("向前移") { if index > 0 { model.draft.assets.swapAt(index, index - 1) } }.disabled(index == 0)
                        Spacer()
                        Button("向后移") { if index + 1 < model.draft.assets.count { model.draft.assets.swapAt(index, index + 1) } }.disabled(index + 1 == model.draft.assets.count)
                    }
                    Button("从草稿移除", role: .destructive) { assetDetail = nil; Task { await model.remove(asset) } }
                }
            }.navigationTitle("照片说明").toolbar { Button("完成") { assetDetail = nil } }
        }.presentationDetents([.medium, .large])
    }
}

@MainActor
private final class CreationLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var message = ""
    private let manager = CLLocationManager()
    private var completion: ((String) -> Void)?
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyKilometer }
    func locate(_ completion: @escaping (String) -> Void) {
        self.completion = completion
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { message = "未授权定位，可以手动填写地点。" }
        else { message = "正在获取地点…"; manager.requestLocation() }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if completion != nil, manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] places, _ in
            Task { @MainActor in
                guard let self else { return }
                if let place = places?.first {
                    let name = [place.locality, place.subLocality].compactMap { $0 }.joined(separator: " · ")
                    if !name.isEmpty { self.completion?(name); self.message = "已填入当前地区，请确认是否是故事发生地。" }
                    else { self.message = "无法获得地区名称，请手动填写。" }
                } else { self.message = "定位失败，可以手动填写地点。" }
                self.completion = nil
            }
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { message = "定位失败，可以手动填写地点。"; completion = nil }
}

/// Reuses the app's camera batch workflow, copying confirmed images to durable draft storage.
private struct CreationCamera: View {
    let onPhoto: (Data) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    var body: some View {
        DiaryCaptureCamera(onPhotos: { images in
            guard !saving else { return }; saving = true
            Task {
                for image in images { if let bytes = image.jpegData(compressionQuality: 0.95) { await onPhoto(bytes) } }
                saving = false; dismiss()
            }
        }, onClose: { if !saving { dismiss() } })
        .disabled(saving).overlay { if saving { ProgressView("正在保存拍摄照片…").padding().background(.regularMaterial) } }
        .interactiveDismissDisabled(saving)
    }
}
