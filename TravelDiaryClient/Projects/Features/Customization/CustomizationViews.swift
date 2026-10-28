import SwiftUI
import PhotosUI
import ImageIO

struct CustomizationRoute: Hashable { let id: String }

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
    @State private var step: CustomizationFormStep = .photos
    @State private var issue: CustomizationFormIssue?
    @State private var localSaved = false
    @State private var localSaveError: String?
    @State private var cloudSaved = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: String?
    private var pendingJobs: [CustomUploadJob] {
        service.jobs.filter { $0.owner == owner && $0.requestID == id && $0.state != "已完成" }
    }
    private var remainingPhotoCapacity: Int {
        guard let value else { return 30 }
        return max(1, 30 - photoCount(value))
    }
    private var saveHint: String {
        if localSaveError != nil { return "草稿尚未保存" }
        if cloudSaved { return "草稿已同步" }
        return localSaved ? "已保存到本机" : "填写后自动保存到本机"
    }
    var body: some View {
        lifecycleContent
        .photosPicker(isPresented: $showPhotoPicker, selection: $photos,
                      maxSelectionCount: remainingPhotoCapacity, matching: .images)
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
    private var navigationContent: some View {
        Group {
            if let value, value.editable { draftFlow(value) }
            else { detailList }
        }
        .navigationTitle(value?.editable == true ? "创建专属手帐" : "专属定制").navigationBarTitleDisplayMode(.inline)
        .background(DiaryLibraryStyle.background).foregroundStyle(DiaryLibraryStyle.ink).tint(DiaryLibraryStyle.accent)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(busy)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let value, value.editable { draftFooter(value) }
        }
        .toolbar {
            if value?.editable == true {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存草稿") { focusedField = nil; Task { await save() } }.disabled(isBusy || refreshing)
                }
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { focusedField = nil } }
        }
    }
    private var lifecycleContent: some View {
        navigationContent
        .onAppear { service.visibleRequestID = id }
        .onDisappear {
            if value?.editable == true { persistForm() }
            if service.visibleRequestID == id { service.visibleRequestID = nil }
        }
        .onChange(of: service.refreshSequence) { _, _ in Task { await refresh() } }
        .overlay { if busy { ProgressView("正在保存…").padding().background(.regularMaterial,in: RoundedRectangle(cornerRadius: 12)) } }
        .refreshable { await refresh() }
        .task(id: id) {
            step = CustomizationFormStep(rawValue: UserDefaults.standard.integer(forKey: CustomizationFormRules.stepKey(owner: owner, requestID: id))) ?? .photos
            await refresh(restore: true)
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(30)); if !Task.isCancelled && !isBusy && !showPhotoPicker { await refresh() } }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active && !isBusy && !showPhotoPicker { Task { await refresh() } } }
        .onChange(of: fields) { _, _ in
            cloudSaved = false
            if value?.editable == true { persistForm() }
            if let issue, fields[issue.field] != nil { self.issue = CustomizationFormRules.storyIssue(fields) }
        }
        .onChange(of: step) { _, new in
            UserDefaults.standard.set(new.rawValue, forKey: CustomizationFormRules.stepKey(owner: owner, requestID: id))
        }
    }
    private var detailList: some View {
        List {
            if let error { Section { Text(error).foregroundStyle(.red) } }
            if let v = value {
                if v.billing_quote_available == true {
                    Section("数字定制报价") { NavigationLink("查看报价与付款") { CustomizationDiamondPaymentScreen(owner: owner, requestID: id) } }
                }
                Section {
                    Text(customizationStatus(v.status)).font(.headline)
                    DisclosureGroup("需求信息") { Text(v.number).font(.caption).textSelection(.enabled) }
                    if let date = v.due_at { Text("预计交付：\(customDate(date))").font(.footnote) }
                    if v.pending_submission == true && v.status == "in_production" {
                        Label("补充资料已提交，等待制作方确认新的制作依据", systemImage: "doc.badge.clock").font(.footnote)
                    }
                    if v.cancellation_requested == true { Label("已申请取消，等待制作方处理", systemImage: "clock").font(.footnote) }
                }
                if let delivery = v.deliveries.first(where: { $0.id == v.current_delivery_id }) { deliverySection(delivery) }
                    Section("需求摘要") { Text(v.title); Text(v.brief["description"] ?? ""); Text(v.brief["important_text"] ?? "") }
                    Section("已提交照片") {
                        ForEach(v.assets) { a in HStack { CustomPrivateImage(raw: a.thumbnail_url).frame(width: 65,height: 65); Text(a.note.isEmpty ? "照片 \(a.position+1)" : a.note) } }
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
                        Button(["in_production","revision_requested"].contains(v.status) ? "申请取消" : "撤回需求",role: .destructive) { Task { await perform("cancel") } }.disabled(isBusy || refreshing)
                    }
                    Button("删除云端定制资料", role: .destructive) { showDelete = true }.disabled(isBusy || refreshing)
                }
            } else if error == nil { ProgressView("正在加载定制") }
            else { Button("重新加载") { Task { await refresh(restore: true) } } }
        }
        .scrollContentBackground(.hidden)
        .listRowSeparator(.hidden)
    }

    private func field(_ name: String) -> Binding<String> { Binding(get: { fields[name] ?? "" },set: { fields[name] = $0 }) }
    private func refresh(restore: Bool = false) async {
        restoreFormPending = restoreFormPending || restore
        guard !refreshing, !busy else { refreshPending = true; return }
        refreshing = true
        defer { refreshing = false }
        repeat {
            refreshPending = false
            do {
                let r = try await service.detail(id,owner: owner); value = r
                if restoreFormPending {
                    fields = service.loadForm(id: id,owner: owner) ?? r.brief.merging(["title":r.title]) { _, new in new }
                    restoreFormPending = false
                    if photoCount(r) == 0 { step = .photos }
                    else if step == .review && CustomizationFormRules.storyIssue(fields) != nil { step = .story }
                }
                await service.read(r,owner: owner); error = nil
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        } while refreshPending && !Task.isCancelled
    }
    private func finishWork() {
        busy = false
        if refreshPending { Task { await refresh() } }
    }
    private func persistForm() {
        do { try service.saveForm(fields, id: id, owner: owner); localSaved = true; localSaveError = nil }
        catch { localSaveError = "草稿未能保存到本机，请检查设备可用空间后重试。" }
    }
    private func save() async {
        guard let v = value, v.editable, !isBusy, !refreshing else { return }
        persistForm()
        busy = true; defer { finishWork() }
        do {
            var brief = fields
            let title = brief.removeValue(forKey: "title") ?? ""
            value = try await service.action("edit", value: v, owner: owner, body: ["title": title, "brief": brief])
            error = nil; cloudSaved = true
        } catch { self.error = error.localizedDescription }
    }
    private func submit() async {
        guard let current = value, current.editable, !isBusy, !refreshing else { return }
        if let problem = CustomizationFormRules.photoIssue(assets: current.assets, pendingJobs: pendingJobs.count, importing: photoImport.isImporting)
            ?? CustomizationFormRules.storyIssue(fields) {
            reveal(problem); return
        }
        persistForm()
        busy = true; defer { finishWork() }
        do {
            var brief = fields
            let title = brief.removeValue(forKey: "title")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let saved = try await service.action("edit", value: current, owner: owner, body: ["title": title, "brief": brief])
            value = saved
            let submitted = try await service.action("submit", value: saved, owner: owner)
            value = submitted; error = nil; cloudSaved = true; issue = nil
            await service.read(submitted, owner: owner)
            _ = await PushAdapter.shared.requestAuthorizationIfNotDetermined()
        } catch { self.error = error.localizedDescription }
    }
    private func perform(_ action: String,extra: [String: Any] = [:]) async {
        guard let v = value, !isBusy, !refreshing else { return }; busy = true; defer { finishWork() }
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
        do { let _: Ack = try await service.request("requests/\(id)/delete/",owner: owner,method: .post,body: ["expected_revision":v.revision],key: "delete-\(v.revision)"); await service.purgeLocalRequest(id,owner: owner,templateIDs: Set(v.deliveries.map(\.template_id))); UserDefaults.standard.removeObject(forKey: CustomizationFormRules.stepKey(owner: owner, requestID: id)); dismiss() }
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
        guard !busy else { return }; busy = true; defer { finishWork() }
        do { try service.require(owner); var book = d.book(owner: owner); book.customizationID = id; _ = try await downloads.enqueue(book: book,pageIDs: nil,owner: owner,target: nil,after: nil) }
        catch { self.error = error.localizedDescription }
    }
    private func eventTitle(_ action: String) -> String {
        ["submitted":"需求已提交","info_requested":"请补充资料","info_submitted":"补充资料已提交","accepted":"已受理","basis_updated":"制作方已确认补充资料","delivered":"成品已交付","redelivered":"新版已交付","revision_requested":"修改意见已提交","revision_started":"正在修改","completed":"已确认完成","due_changed":"预计日期已更新","cancelled":"已取消","rejected":"暂无法制作","delivery_withdrawn":"交付已撤回","delivery_rolled_back":"交付版本已调整","cancellation_requested":"取消申请已提交"][action] ?? action
    }
}

extension CustomizationDetailView {
    private func draftFlow(_ request: CustomRequest) -> some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    CustomizationFormSteps(selection: step, onSelect: { selectStep($0, request: request) }).id("stepTop")
                    if request.status == "needs_info" {
                        DiaryLibraryNotice(message: request.events.last(where: { $0.action == "info_requested" })?.message.nonEmpty
                            ?? "制作方需要你补充资料，请确认后重新提交。")
                    }
                    if let error { DiaryLibraryNotice(message: error) { Task { await refresh() } } }
                    if let localSaveError { DiaryLibraryNotice(message: localSaveError, actionTitle: "重新保存") { persistForm() } }
                    switch step {
                    case .photos: photoStep(request)
                    case .story: CustomizationStoryFields(fields: $fields, focus: $focusedField, issue: issue)
                    case .review: reviewStep(request)
                    }
                    DisclosureGroup("需求信息与更多操作") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(request.number).font(.caption).textSelection(.enabled)
                            if request.permits("cancel") {
                                Button("撤回需求", role: .destructive) { Task { await perform("cancel") } }.disabled(isBusy || refreshing)
                            }
                            Button("删除云端定制资料", role: .destructive) { showDelete = true }.disabled(isBusy || refreshing)
                        }.padding(.top, 12)
                    }.font(.subheadline)
                }
                .frame(maxWidth: 640, alignment: .leading).padding(20).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: step) { _, _ in
                focusedField = nil
                if reduceMotion { scroll.scrollTo("stepTop", anchor: .top) }
                else { withAnimation(.easeInOut(duration: 0.2)) { scroll.scrollTo("stepTop", anchor: .top) } }
            }
        }
        .disabled(busy)
    }
    private func draftFooter(_ request: CustomRequest) -> some View {
        VStack(spacing: 10) {
            if step == .review,
               let problem = CustomizationFormRules.photoIssue(assets: request.assets, pendingJobs: pendingJobs.count, importing: photoImport.isImporting) {
                Button { reveal(problem) } label: { Label(problem.message, systemImage: "info.circle").font(.caption) }
            }
            HStack(spacing: 12) {
                if step != .photos {
                    Button("上一步") { selectStep(CustomizationFormStep(rawValue: step.rawValue - 1) ?? .photos, request: request) }
                        .frame(minHeight: 44).disabled(isBusy || refreshing)
                }
                Button {
                    focusedField = nil
                    switch step {
                    case .photos: selectStep(.story, request: request)
                    case .story: selectStep(.review, request: request)
                    case .review: Task { await submit() }
                    }
                } label: {
                    HStack {
                        if busy { ProgressView() }
                        Text(step == .photos ? "下一步 · 讲讲故事" : step == .story ? "下一步 · 确认需求" : request.status == "needs_info" ? "提交补充资料" : "提交定制需求")
                    }.frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(isBusy || refreshing || (step == .review && (!request.permits("submit") || CustomizationFormRules.photoIssue(assets: request.assets, pendingJobs: pendingJobs.count, importing: photoImport.isImporting) != nil)))
            }
            Label(saveHint, systemImage: localSaveError == nil ? "checkmark.circle" : "exclamationmark.circle")
                .font(.caption).foregroundStyle(localSaveError == nil ? DiaryLibraryStyle.secondary : Color.red)
        }
        .frame(maxWidth: 640).padding(.horizontal, 20).padding(.vertical, 12).frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }
    private func selectStep(_ target: CustomizationFormStep, request: CustomRequest) {
        guard !isBusy else { return }
        if let problem = CustomizationFormRules.navigationIssue(from: step, to: target, fields: fields, selectedPhotos: photoCount(request)) {
            reveal(problem); return
        }
        issue = nil; step = target; persistForm()
    }
    private func reveal(_ problem: CustomizationFormIssue) {
        issue = problem; step = problem.step
        if problem.step == .story { focusedField = problem.field }
    }
    private func unregisteredJobs(_ request: CustomRequest) -> [CustomUploadJob] {
        let registered = Set(request.assets.map { $0.client_id.lowercased() })
        return pendingJobs.filter { !registered.contains($0.id.uuidString.lowercased()) }
    }
    private func photoCount(_ request: CustomRequest) -> Int { request.assets.count + unregisteredJobs(request).count }
    private func photoStep(_ request: CustomRequest) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("先选几张喜欢的照片").font(.title2.weight(.semibold))
                Text("选择 1～30 张。上传期间可以继续填写故事，之后也能调整照片顺序和要求。")
                    .font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack { photoCountLabel(request); Spacer(); addPhotoButton(request) }
                VStack(alignment: .leading) { photoCountLabel(request); addPhotoButton(request) }
            }
            if let message = photoImport.message { Label(message, systemImage: photoImport.isImporting ? "photo" : "checkmark.circle").font(.footnote).foregroundStyle(DiaryLibraryStyle.secondary) }
            if let problem = photoImport.error { Label(problem, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red) }
            if issue?.step == .photos { Text(issue?.message ?? "").font(.footnote).foregroundStyle(.red) }
            if request.assets.isEmpty && unregisteredJobs(request).isEmpty {
                Button(action: choosePhotos) {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.plus").font(.largeTitle.weight(.light))
                        Text("添加你的旅行与生活照片").font(.headline)
                        Text("之后可以逐张添加备注、标记必用照片。").font(.footnote).foregroundStyle(DiaryLibraryStyle.secondary)
                    }.frame(maxWidth: .infinity, minHeight: 170).padding(20)
                        .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).disabled(isBusy || refreshing)
            } else {
                photoGrid(request)
            }
            if !pendingJobs.isEmpty { uploadTasks }
            DisclosureGroup("照片使用说明") {
                Text("照片仅用于本次定制。可逐张设置是否允许裁切、标记必用及封面偏好。Live Photo 使用静态照片，上传前会移除位置信息。")
                    .font(.footnote).foregroundStyle(DiaryLibraryStyle.secondary).padding(.top, 8)
            }.font(.subheadline)
        }
    }
    private func photoCountLabel(_ request: CustomRequest) -> some View {
        Text("已选 \(photoCount(request))/30 张").font(.subheadline.weight(.medium)).monospacedDigit()
    }
    private func addPhotoButton(_ request: CustomRequest) -> some View {
        Button(action: choosePhotos) { Label("添加照片", systemImage: "plus").frame(minHeight: 44) }
            .disabled(isBusy || photoCount(request) >= 30)
    }
    private func photoGrid(_ request: CustomRequest) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], alignment: .leading, spacing: 16) {
            ForEach(request.assets) { asset in
                Button { editingAsset = asset } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        GeometryReader { geometry in
                            Group {
                                if asset.thumbnail_url == nil, let job = service.jobs.first(where: { $0.owner == owner && $0.requestID == id && $0.id.uuidString.lowercased() == asset.client_id.lowercased() }) {
                                    CustomLocalPhotoThumbnail(file: job.file)
                                } else { CustomPrivateImage(raw: asset.thumbnail_url) }
                            }.frame(width: geometry.size.width, height: geometry.size.height)
                        }.aspectRatio(1, contentMode: .fit)
                            .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 12)).clipShape(RoundedRectangle(cornerRadius: 12))
                        Text(asset.note.isEmpty ? "照片 \(asset.position + 1)" : asset.note).font(.subheadline).lineLimit(2)
                        Text(asset.status == "ready" ? (asset.must_use ? "必用 · 编辑要求" : "已上传 · 编辑要求") : asset.status == "failed" ? "上传失败 · 查看要求" : "上传中 · 编辑要求")
                            .font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(isBusy || refreshing)
            }
            ForEach(unregisteredJobs(request)) { job in
                VStack(alignment: .leading, spacing: 8) {
                    CustomLocalPhotoThumbnail(file: job.file).aspectRatio(1, contentMode: .fit)
                        .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                    Text("已添加照片").font(.subheadline)
                    Text(job.state).font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                }
            }
        }
    }
    private var uploadTasks: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("照片上传").font(.headline)
            ForEach(pendingJobs) { job in
                VStack(alignment: .leading, spacing: 8) {
                    Text(job.state).font(.subheadline)
                    if let progress = job.progress { ProgressView(value: progress) }
                    if let problem = job.error { Text(problem).font(.footnote).foregroundStyle(.red) }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) { jobActions(job) }
                        VStack(alignment: .leading, spacing: 8) { jobActions(job) }
                    }
                }
                if job.id != pendingJobs.last?.id { Divider() }
            }
            Button("刷新照片状态") { Task { await refresh() } }.frame(minHeight: 44)
        }.padding(16).background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 16))
    }
    @ViewBuilder private func jobActions(_ job: CustomUploadJob) -> some View {
        Button("继续 / 重试") { service.resume(job.id) }.frame(minHeight: 44)
        Button("暂停") { service.pause(job.id) }.frame(minHeight: 44)
        Button("移除", role: .destructive) {
            Task { do { try await service.discard(job.id); await refresh() } catch { self.error = error.localizedDescription } }
        }.frame(minHeight: 44)
    }
    private func reviewStep(_ request: CustomRequest) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("确认这次想留下的回忆").font(.title2.weight(.semibold))
                Text("提交后由制作方受理，再与你确认制作安排。")
                    .font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
            }
            if let issue, issue.step == .story { Text(issue.message).font(.footnote).foregroundStyle(.red) }
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("主题与故事").font(.headline); Spacer(); Button("修改") { selectStep(.story, request: request) }.frame(minHeight: 44) }
                Text(fields["title"] ?? "").font(.title3.weight(.semibold))
                Text(fields["description"] ?? "").font(.body).fixedSize(horizontal: false, vertical: true)
                ForEach(["category", "style", "important_text", "story_order", "avoid"], id: \.self) { key in
                    if let text = fields[key], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(["category":"场景", "style":"风格偏好", "important_text":"重要文字", "story_order":"顺序与页数偏好", "avoid":"不希望出现的内容"][key] ?? key)
                                .font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                            Text(text).font(.subheadline)
                        }
                    }
                }
            }.padding(16).background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("照片与要求").font(.headline); Spacer(); Button("修改") { selectStep(.photos, request: request) }.frame(minHeight: 44) }
                Text("\(request.assets.count) 张照片 · \(request.assets.filter(\.must_use).count) 张必用")
                    .font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
                ForEach(request.assets.filter { $0.must_use || $0.cover_preferred || !$0.crop_allowed || !$0.note.isEmpty }) { asset in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("照片 \(asset.position + 1)").font(.subheadline.weight(.medium))
                        Text(([asset.must_use ? "必用" : nil, asset.cover_preferred ? "封面偏好" : nil, !asset.crop_allowed ? "不可裁切" : nil].compactMap { $0 } + (asset.note.isEmpty ? [] : [asset.note])).joined(separator: " · "))
                            .font(.footnote).foregroundStyle(DiaryLibraryStyle.secondary)
                    }
                }
            }.padding(16).background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 16))
            Label("资料仅用于本次制作与交付，默认不公开。请确认你有权使用所选照片。", systemImage: "lock")
                .font(.footnote).foregroundStyle(DiaryLibraryStyle.secondary)
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
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

struct CustomLocalPhotoThumbnail: View {
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

struct CustomPrivateImage: View {
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
