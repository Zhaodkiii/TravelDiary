import SwiftUI
import PhotosUI
import ImageIO

struct CustomizationRoute: Hashable { let id: String }

struct CustomizationHomeView: View {
    let owner: String
    @ObservedObject private var service = CustomizationService.shared
    @State private var rows: [CustomRequestRow] = []
    @State private var error: String?
    @State private var busy = false
    @State private var nextPage: Int? = 1
    @State private var reminders = true
    @ObservedObject private var push = PushAdapter.shared
    @State private var quiet = false
    @State private var quietStart = "22:00"
    @State private var quietEnd = "08:00"
    var body: some View {
        List {
            Section {
                Text("把照片和故事交给我们，为你制作专属主题手帐。成品可预览、添加到书架并继续编辑。")
                Button { Task { await create() } } label: { Label("发起定制", systemImage: "sparkles") }.disabled(busy)
                Toggle("定制进度与成品提醒", isOn: $reminders).onChange(of: reminders) { _, value in Task { await preference(value) } }
                Button("开启系统通知") { Task { _ = await PushAdapter.shared.requestAuthorizationIfNotDetermined(openSettingsIfDenied: true) } }
                if push.notificationsEnabled == false { Text("系统通知尚未开启，仍可在这里查看全部进度。").font(.footnote).foregroundStyle(.secondary) }
                if let problem = push.registrationError { Text(problem).font(.footnote).foregroundStyle(.secondary) }
                DisclosureGroup("免打扰设置") {
                    Toggle("使用静默时段", isOn: $quiet)
                    if quiet {
                        TextField("开始时间 HH:mm", text: $quietStart)
                        TextField("结束时间 HH:mm", text: $quietEnd)
                        Text("时区：\(TimeZone.current.identifier)").font(.caption)
                    }
                    Button("保存免打扰设置") { Task { await saveQuiet() } }
                }
                Text("照片和成品默认仅你可见，不会进入公共模板或素材库。关闭通知仍可领取成品。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            if let problem = service.routeError { Section { Text(problem).foregroundStyle(.secondary) } }
            Section("我的定制") {
                if rows.isEmpty { Text("还没有定制需求").foregroundStyle(.secondary) }
                ForEach(rows) { row in
                    NavigationLink(value: CustomizationRoute(id: row.id)) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(row.title.isEmpty ? "未命名草稿" : row.title); if row.unread { Circle().fill(.orange).frame(width: 7,height: 7) } }
                            Text(customizationStatus(row.status)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let nextPage { Button("加载更多") { Task { await load(page: nextPage) } } }
            }
        }
        .overlay { if busy { ProgressView() } }
        .refreshable { await load() }
        .task {
            await load()
            struct Pref: Decodable { let enabled: Bool; let quiet_hours: [String: String] }
            if let value: Pref = try? await service.request("preferences/", owner: owner) {
                reminders = value.enabled; quiet = !value.quiet_hours.isEmpty
                quietStart = value.quiet_hours["start"] ?? "22:00"; quietEnd = value.quiet_hours["end"] ?? "08:00"
            }
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(30)); if !Task.isCancelled { await service.refreshUnread(owner: owner) } }
        }
    }
    private func load(page: Int = 1) async {
        do { let r = try await service.list(owner: owner,page: page); rows = page == 1 ? r.results : rows + r.results; nextPage = r.next_page; error = nil; await service.refreshUnread(owner: owner) }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func create() async {
        busy = true; defer { busy = false }
        do { let value = try await service.create(owner: owner); service.routeID = value.id; await load() }
        catch { self.error = error.localizedDescription }
    }
    private func saveQuiet() async {
        struct Pref: Decodable { let enabled: Bool }
        do { let _: Pref = try await service.request("preferences/", owner: owner, method: .patch,
            body: ["enabled":reminders,"quiet_hours":quiet ? ["start":quietStart,"end":quietEnd,"timezone":TimeZone.current.identifier] : [:]]) }
        catch { self.error = error.localizedDescription }
    }
    private func preference(_ enabled: Bool) async {
        struct Pref: Decodable { let enabled: Bool }
        do { let _: Pref = try await service.request("preferences/", owner: owner, method: .patch, body: ["enabled":enabled]) }
        catch { self.error = error.localizedDescription }
    }
}

struct CustomizationDetailView: View {
    let id: String; let owner: String
    @ObservedObject private var service = CustomizationService.shared
    @ObservedObject private var downloads = PresetDownloadManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var value: CustomRequest?
    @State private var fields: [String: String] = [:]
    @State private var photos: [PhotosPickerItem] = []
    @StateObject private var photoImport = CustomPhotoImportState()
    @State private var showPhotoPicker = false
    @State private var refreshing = false
    @State private var refreshPending = false
    @State private var restoreFormPending = false
    @State private var error: String?
    @State private var busy = false
    @State private var message = ""
    @State private var editingAsset: CustomAsset?
    @State private var showDelete = false
    @Environment(\.dismiss) private var dismiss
    private var isBusy: Bool { busy || photoImport.isImporting }
    private var hasPendingPhotos: Bool {
        service.jobs.contains { $0.owner == owner && $0.requestID == id && $0.state != "已完成" }
    }
    var body: some View {
        List {
            if let error { Section { Text(error).foregroundStyle(.red) } }
            if let v = value {
                Section {
                    Text(customizationStatus(v.status)).font(.headline)
                    Text(v.number).font(.caption).foregroundStyle(.secondary)
                    if let date = v.due_at { Text("预计交付：\(customDate(date))").font(.footnote) }
                    if v.pending_submission == true && v.status == "in_production" {
                        Label("补充资料已提交，等待制作方确认新的制作依据", systemImage: "doc.badge.clock").font(.footnote)
                    }
                    if v.cancellation_requested == true { Label("已申请取消，等待制作方处理", systemImage: "clock").font(.footnote) }
                }
                if let delivery = v.deliveries.first(where: { $0.id == v.current_delivery_id }) { deliverySection(delivery) }
                if v.editable {
                    Section("主题与想法") {
                        TextField("主题名称（必填）", text: field("title"))
                        TextField("想记录的故事（必填）", text: field("description"), axis: .vertical).lineLimit(4...8)
                        TextField("场景：旅行、亲子、爱情、生日等", text: field("category"))
                        TextField("风格偏好", text: field("style"))
                        TextField("必须保留的姓名、日期或短句", text: field("important_text"), axis: .vertical)
                        TextField("故事顺序与页数偏好", text: field("story_order"), axis: .vertical)
                        TextField("不希望出现的内容", text: field("avoid"), axis: .vertical)
                        Button("保存草稿") { Task { await save() } }.disabled(isBusy)
                    }
                    Section("照片（1～30 张）") {
                        Button(action: choosePhotos) { Label("添加照片", systemImage: "photo.badge.plus") }
                            .disabled(isBusy || v.assets.count >= 30)
                        if let message = photoImport.message {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                        }
                        if let problem = photoImport.error {
                            Label(problem, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red)
                        }
                        Text("上传制作图长边最多 4096px；Live Photo 仅取静态图，保留方向并移除位置元数据。")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(v.assets) { a in
                            HStack {
                                Group {
                                    if a.thumbnail_url == nil, let job = service.jobs.first(where: { $0.owner == owner && $0.requestID == id && $0.id.uuidString.lowercased() == a.client_id.lowercased() }) {
                                        CustomLocalPhotoThumbnail(file: job.file)
                                    } else { CustomPrivateImage(raw: a.thumbnail_url) }
                                }.frame(width: 65,height: 65).clipped()
                                VStack(alignment: .leading) { Text(a.note.isEmpty ? "照片 \(a.position+1)" : a.note); Text(a.status == "ready" ? (a.must_use ? "必用照片" : "已就绪") : a.status).font(.caption) }
                                Spacer(); Button("设置") { editingAsset = a }.buttonStyle(.borderless)
                            }
                        }
                        ForEach(service.jobs.filter { job in
                            job.owner == owner && job.requestID == id && job.state != "已完成" &&
                            !v.assets.contains { $0.client_id.lowercased() == job.id.uuidString.lowercased() }
                        }) { job in
                            HStack {
                                CustomLocalPhotoThumbnail(file: job.file).frame(width: 65, height: 65)
                                VStack(alignment: .leading) {
                                    Text("已添加照片")
                                    Text(job.state).font(.caption).foregroundStyle(.secondary)
                                    if let progress = job.progress { ProgressView(value: progress) }
                                    if let problem = job.error { Text(problem).font(.footnote).foregroundStyle(.red) }
                                }
                            }
                        }
                    }
                    Section {
                        Button(v.status == "needs_info" ? "提交补充资料" : "提交定制需求") { Task { await submit() } }
                            .disabled(isBusy || hasPendingPhotos || v.assets.isEmpty || v.assets.contains { $0.status != "ready" })
                        if hasPendingPhotos || v.assets.contains(where: { $0.status != "ready" }) {
                            Text("还有照片未完成上传，请在下方查看进度或重试；上传完成后即可提交。")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else if v.assets.isEmpty {
                            Text("请至少添加 1 张照片，并等待上传完成后提交。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Text("提交后资料用于人工制作，默认不会公开。请确认你有权使用所选照片。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Section("需求摘要") { Text(v.title); Text(v.brief["description"] ?? ""); Text(v.brief["important_text"] ?? "") }
                    Section("已提交照片") {
                        ForEach(v.assets) { a in HStack { CustomPrivateImage(raw: a.thumbnail_url).frame(width: 65,height: 65); Text(a.note.isEmpty ? "照片 \(a.position+1)" : a.note) } }
                    }
                }
                let jobs = service.jobs.filter { $0.owner == owner && $0.requestID == id && $0.state != "已完成" }
                if !jobs.isEmpty {
                    Section("照片上传") {
                        ForEach(jobs) { job in
                            VStack(alignment: .leading) {
                                Text(job.state); if let progress = job.progress { ProgressView(value: progress) }; if let e = job.error { Text(e).font(.footnote).foregroundStyle(.red) }
                                HStack { Button("继续 / 重试") { service.resume(job.id) }; Button("暂停") { service.pause(job.id) }; Button("移除任务",role: .destructive) { Task { do { try await service.discard(job.id) } catch { self.error = error.localizedDescription } } } }.buttonStyle(.borderless)
                            }
                        }
                        Button("刷新照片状态") { Task { await refresh() } }
                    }
                }
                if !v.submissions.isEmpty {
                    Section("提交记录") {
                        ForEach(v.submissions) { sub in
                            CustomSubmissionRecord(submission: sub, accepted: sub.id == v.accepted_submission_id, latest: sub.id == v.latest_submission_id)
                        }
                    }
                }
                if v.deliveries.count > 1 {
                    Section("历史交付") {
                        ForEach(v.deliveries.filter { $0.id != v.current_delivery_id }) { d in
                            DisclosureGroup("第 \(d.number) 版 · \(d.title)") {
                                Text(d.note)
                                ScrollView(.horizontal) { LazyHStack { ForEach(d.pages) { p in CustomPrivateImage(raw: p.preview_url).frame(width: 160,height: 220) } } }
                                Button("将此版本添加为独立手帐") { Task { await add(d) } }
                            }
                        }
                    }
                }
                Section("动态") {
                    ForEach(v.events.reversed()) { e in
                        VStack(alignment: .leading,spacing: 5) {
                            Text(eventTitle(e.action)).font(.subheadline.weight(.medium))
                            if !e.message.isEmpty { Text(e.message) }
                            Text(customDate(e.created_at)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                if v.status == "delivered" {
                    Section("交付反馈") {
                        TextField("修改意见（最多两轮）", text: $message, axis: .vertical)
                        Button("提出修改") { Task { await perform("revision", extra: ["message":message,"delivery_id":v.current_delivery_id ?? ""]) } }.disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !v.permits("revision", fallback: v.revision_round < 2) || isBusy)
                        Button("确认完成") { Task { await perform("confirm", extra: ["delivery_id":v.current_delivery_id ?? ""]) } }.disabled(isBusy || !v.permits("confirm"))
                    }
                }
                Section {
                    if v.permits("cancel", fallback: ["draft","submitted","needs_info","in_production","revision_requested"].contains(v.status)) {
                        Button(["in_production","revision_requested"].contains(v.status) ? "申请取消" : "撤回需求",role: .destructive) { Task { await perform("cancel") } }.disabled(isBusy)
                    }
                    Button("删除云端定制资料", role: .destructive) { showDelete = true }.disabled(isBusy)
                }
            } else { ProgressView("正在加载定制") }
        }
        .navigationTitle("专属定制").navigationBarTitleDisplayMode(.inline)
        .onAppear { service.visibleRequestID = id }
        .onDisappear { if service.visibleRequestID == id { service.visibleRequestID = nil } }
        .onChange(of: service.refreshSequence) { _, _ in Task { await refresh() } }
        .overlay { if isBusy { ProgressView(photoImport.isImporting ? (photoImport.message ?? "正在读取照片…") : "正在处理…").padding().background(.regularMaterial,in: RoundedRectangle(cornerRadius: 12)) } }
        .refreshable { await refresh() }
        .task(id: id) {
            await refresh(restore: true)
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(30)); if !Task.isCancelled && !isBusy && !showPhotoPicker { await refresh() } }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active && !isBusy && !showPhotoPicker { Task { await refresh() } } }
        .onChange(of: fields) { _, new in service.saveForm(new,id: id,owner: owner) }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photos,
                      maxSelectionCount: max(1, 30 - (value?.assets.count ?? 0)), matching: .images)
        .onChange(of: photos) { _, selected in
            guard !selected.isEmpty else { return }
            Task { await upload(selected) }
        }
        .alert("照片添加失败", isPresented: $photoImport.showError) {
            Button("知道了", role: .cancel) { }
        } message: { Text(photoImport.error ?? "请重新选择照片后重试") }
        .sheet(item: $editingAsset) { a in CustomAssetSettings(asset: a, requestID: id,owner: owner) { value = $0 } }
        .confirmationDialog("删除后停止云端访问并进入清理流程；已添加的本地手帐仍保留。",isPresented: $showDelete) {
            Button("删除云端资料",role: .destructive) { Task { await remove() } }
        }
    }
    private func field(_ name: String) -> Binding<String> { Binding(get: { fields[name] ?? "" },set: { fields[name] = $0 }) }
    private func refresh(restore: Bool = false) async {
        restoreFormPending = restoreFormPending || restore
        guard !refreshing else { refreshPending = true; return }
        refreshing = true
        defer { refreshing = false }
        repeat {
            refreshPending = false
            do {
                let r = try await service.detail(id,owner: owner); value = r
                if restoreFormPending {
                    fields = service.loadForm(id: id,owner: owner) ?? r.brief.merging(["title":r.title]) { _, new in new }
                    restoreFormPending = false
                }
                await service.read(r,owner: owner); error = nil
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        } while refreshPending && !Task.isCancelled
    }
    private func save() async {
        guard let v = value else { return }; busy = true; defer { busy = false }
        do { var brief = fields; let title = brief.removeValue(forKey: "title") ?? ""; value = try await service.action("edit",value: v,owner: owner,body: ["title":title,"brief":brief]); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func submit() async {
        await save(); guard error == nil else { return }; await perform("submit")
        if error == nil { _ = await PushAdapter.shared.requestAuthorizationIfNotDetermined() }
    }
    private func perform(_ action: String,extra: [String: Any] = [:]) async {
        guard let v = value else { return }; busy = true; defer { busy = false }
        do { value = try await service.action(action,value: v,owner: owner,body: extra); error = nil; if let value { await service.read(value,owner: owner) } }
        catch { self.error = error.localizedDescription }
    }
    private func choosePhotos() {
        do {
            try service.require(owner, bound: true)
            showPhotoPicker = true
        } catch { photoImport.report(error, stage: "account") }
    }
    private func upload(_ selection: [PhotosPickerItem]) async {
        guard !selection.isEmpty, !isBusy else { return }
        defer { photos = [] }
        let added = await photoImport.add(selection, load: { try await $0.loadTransferable(type: Data.self) }, enqueue: {
            try await service.enqueuePhoto($0, request: id, owner: owner)
        })
        if added > 0 { await refresh() }
    }
    private func remove() async {
        guard let v = value else { return }
        struct Ack: Decodable { let deleted: Bool }
        do { let _: Ack = try await service.request("requests/\(id)/delete/",owner: owner,method: .post,body: ["expected_revision":v.revision],key: "delete-\(v.revision)"); await service.purgeLocalRequest(id,owner: owner,templateIDs: Set(v.deliveries.map(\.template_id))); dismiss() }
        catch { self.error = error.localizedDescription }
    }
    @ViewBuilder private func deliverySection(_ d: CustomDelivery) -> some View {
        Section("专属成品 · 第 \(d.number) 版") {
            Text(d.title).font(.headline); if !d.note.isEmpty { Text(d.note) }
            Text("\(d.page_count) 页 · 可替换照片 \(d.photo_slots) 处 · 原生可编辑文字 \(d.text_slots) 处").font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal) { LazyHStack { ForEach(d.pages) { p in CustomPrivateImage(raw: p.preview_url).frame(width: 230,height: 310).accessibilityLabel(p.title) } } }
            if let job = matchingJob(d) {
                if job.status == "completed", let book = job.resultID {
                    NavigationLink("打开手帐",value: DiaryBookRoute(bookID: book))
                } else {
                    Text(["queued":"等待下载","downloading":"正在下载","verifying":"正在校验","importing":"正在添加","paused":"已暂停","failed":"下载失败"][job.status] ?? job.status)
                    ProgressView(value: Double(job.bytes),total: Double(max(1,job.total)))
                    if let e = job.error { Text(e).font(.footnote).foregroundStyle(.red) }
                    HStack { Button("继续 / 重试") { downloads.resume(job.id) }; Button("暂停") { downloads.pause(job.id) } }
                }
                Button("保留已有手帐，再创建一本") { Task { await add(d) } }
            } else { Button("添加到我的手帐") { Task { await add(d) } }.disabled(busy) }
            Text("添加后可继续编辑。领取新版会创建独立副本，不覆盖你原来的手帐。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func matchingJob(_ d: CustomDelivery) -> PresetDownloadJob? {
        downloads.jobs.last { job in
            guard job.owner == owner, job.downloadOnly != true,job.status != "cancelled",let m = try? JSONDecoder().decode(PresetManifest.self,from: job.manifestData) else { return false }
            return m.templateBookID == d.template_id && m.packageVersion == d.version
        }
    }
    private func add(_ d: CustomDelivery) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { try service.require(owner); var book = d.book(owner: owner); book.customizationID = id; _ = try await downloads.enqueue(book: book,pageIDs: nil,owner: owner,target: nil,after: nil) }
        catch { self.error = error.localizedDescription }
    }
    private func eventTitle(_ action: String) -> String {
        ["submitted":"需求已提交","info_requested":"请补充资料","info_submitted":"补充资料已提交","accepted":"已受理","basis_updated":"制作方已确认补充资料","delivered":"成品已交付","redelivered":"新版已交付","revision_requested":"修改意见已提交","revision_started":"正在修改","completed":"已确认完成","due_changed":"预计日期已更新","cancelled":"已取消","rejected":"暂无法制作","delivery_withdrawn":"交付已撤回","delivery_rolled_back":"交付版本已调整","cancellation_requested":"取消申请已提交"][action] ?? action
    }
}

private struct CustomSubmissionRecord: View {
    let submission: CustomSubmission
    let accepted: Bool
    let latest: Bool
    private var title: String {
        var result = "提交 #\(submission.number)"
        if accepted { result += " · 制作依据" }
        if latest { result += " · 最新" }
        return result + " · " + submission.snapshot.title
    }
    var body: some View {
        DisclosureGroup(title) {
            Text(submission.snapshot.brief["description"] ?? "")
            if let important = submission.snapshot.brief["important_text"], !important.isEmpty {
                Text("重要文字：\(important)").font(.footnote)
            }
            ForEach(Array(submission.snapshot.assets.enumerated()), id: \.element.id) { index, photo in
                Text((photo.must_use ? "必用 · " : "") + "照片 \(index+1)" + (photo.note.isEmpty ? "" : " · " + photo.note)).font(.caption)
            }
        }
    }
}

private struct CustomAssetSettings: View {
    let asset: CustomAsset; let requestID: String; let owner: String; let updated: (CustomRequest) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""; @State private var must = false; @State private var crop = true; @State private var cover = false; @State private var position = 0
    @State private var error: String?; @State private var busy = false
    var body: some View {
        NavigationStack { Form {
            CustomPrivateImage(raw: asset.url).frame(height: 240)
            TextField("照片备注",text: $note,axis: .vertical);Toggle("必须使用",isOn: $must);Toggle("允许排版裁切",isOn: $crop);Toggle("封面偏好",isOn: $cover);Stepper("排序：\(position+1)",value: $position,in: 0...29)
            if let error { Text(error).foregroundStyle(.red) }
            Button("保存") { Task { await save(delete: false) } }.disabled(busy)
            Button("移除此照片",role: .destructive) { Task { await save(delete: true) } }.disabled(busy)
        }.navigationTitle("照片要求").toolbar { Button("关闭") { dismiss() } } }
        .onAppear { note = asset.note; must = asset.must_use;crop = asset.crop_allowed;cover = asset.cover_preferred;position = asset.position }
    }
    private func save(delete: Bool) async {
        busy = true; defer { busy = false }
        do { updated(try await CustomizationService.shared.asset(asset,request: requestID,owner: owner,body: ["note":note,"must_use":must,"crop_allowed":crop,"cover_preferred":cover,"position":position],delete: delete)); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

private struct CustomLocalPhotoThumbnail: View {
    let file: URL
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }
        .accessibilityLabel("待上传照片")
        .task(id: file) {
            let url = file
            let thumbnail = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil as CGImage? }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 195
                ] as CFDictionary)
            }.value
            if !Task.isCancelled { image = thumbnail.map { UIImage(cgImage: $0) } }
        }
    }
}

private struct CustomPrivateImage: View {
    let raw: String?
    @State private var image: UIImage?
    @State private var loadedPath: String?
    var body: some View {
        Group { if let image { Image(uiImage: image).resizable().scaledToFit() } else { Image(systemName: "photo").foregroundStyle(.secondary).frame(maxWidth: .infinity,maxHeight: .infinity) } }
        .task(id: raw) {
            guard let raw, let url = URL(string: raw),url.scheme == "https",url.host?.hasSuffix(".aliyuncs.com") == true else { return }
            if image != nil, loadedPath == url.path { return }
            image = nil
            let session = URLSession(configuration: .ephemeral); defer { session.finishTasksAndInvalidate() }
            if let (data,response) = try? await session.data(from: url), (response as? HTTPURLResponse)?.statusCode == 200, !Task.isCancelled { image = UIImage(data: data); loadedPath = url.path }
        }
    }
}

private func customDate(_ raw: String) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = parser.date(from: raw)
    if date == nil { parser.formatOptions = [.withInternetDateTime]; date = parser.date(from: raw) }
    return date?.formatted(date: .abbreviated, time: .shortened) ?? raw
}
