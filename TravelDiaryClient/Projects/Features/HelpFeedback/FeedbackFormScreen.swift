import SwiftUI
import PhotosUI

struct FeedbackFormScreen: View {
    @StateObject private var model: FeedbackFormViewModel
    private let articleID: String?
    private let previousID: String?
    @ObservedObject private var service = HelpFeedbackService.shared
    @Environment(\.accountLoginContext) private var loginContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: FeedbackInputField?
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var moreExpanded = false
    @State private var showsLogin = false
    @State private var showsRelated = false
    @State private var showsEnvironment = false
    @State private var clearConfirm = false
    @State private var importGuestConfirm = false
    @State private var work: Task<Void, Never>?
    @ScaledMetric(relativeTo: .body) private var editorHeight = 126

    init(owner: String, articleID: String? = nil, previousID: String? = nil) {
        _model = StateObject(wrappedValue: FeedbackFormViewModel(owner: owner))
        self.articleID = articleID
        self.previousID = previousID
    }
    init(viewModel: FeedbackFormViewModel) {
        _model = StateObject(wrappedValue: viewModel)
        articleID = nil
        previousID = nil
    }
    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let ticket = model.success {
                        FeedbackSubmissionSuccess(ticket: ticket)
                    } else {
                        introduction
                        serviceStatus
                        categorySection.id(FeedbackInputField.kind)
                        writingCard
                        screenshotSection.id(FeedbackInputField.photos)
                        supplementalCard
                        privacyRow
                        notices
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DiaryLibraryStyle.background)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(scroll: scroll) }
            .refreshable { await model.refreshConfiguration() }
        }
        .foregroundStyle(DiaryLibraryStyle.ink)
        .tint(DiaryLibraryStyle.accent)
        .navigationTitle(model.success == nil ? "提交反馈" : "已提交")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.isWorking)
        .toolbar {
            if model.isWorking {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { work?.cancel() } }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if model.success != nil { Button("完成") { dismiss() } }
                else {
                    Menu {
                        Button("清空草稿", systemImage: "trash", role: .destructive) { clearConfirm = true }
                    } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
                    .disabled(model.isWorking).accessibilityLabel("草稿选项")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focusedField = nil }
            }
        }
        .task {
            await model.prepare(articleID: articleID, previousID: previousID)
            if !model.draft.contact.isEmpty || !model.draft.relatedID.isEmpty { moreExpanded = true }
            checkGuestDraft()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refreshConfiguration() } }
        }
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            focusedField = nil
            work = Task {
                model.beginPhotoImport()
                do {
                    for item in items {
                        try Task.checkCancellation()
                        guard let bytes = try await item.loadTransferable(type: Data.self) else { throw HelpFailure("截图读取失败，请重新选择") }
                        try model.addPhoto(bytes)
                    }
                    model.endPhotoImport()
                } catch { model.endPhotoImport(error: error) }
                selectedPhotos = []
            }
        }
        .onChange(of: loginContext?.isDeviceAccount) { _, guest in
            if guest == false { showsLogin = false; model.notice = "登录成功，确认内容后即可提交。" }
        }
        .onDisappear { work?.cancel(); model.saveDraft() }
        .sheet(isPresented: $showsLogin, onDismiss: checkGuestDraft) {
            if let loginContext { LoginView(viewModel: loginContext.viewModel, mode: .upgradeDeviceAccount) }
        }
        .sheet(isPresented: $showsRelated) {
            FeedbackRelatedPicker(owner: model.owner) { type, id, title in
                model.draft.relatedType = type
                model.draft.relatedID = id
                model.draft.relatedTitle = title
            }
        }
        .sheet(isPresented: $showsEnvironment) { FeedbackEnvironmentSheet() }
        .confirmationDialog("清空这份草稿？", isPresented: $clearConfirm, titleVisibility: .visible) {
            Button("清空草稿", role: .destructive) { model.clearDraft() }
        } message: { Text("只清空这次尚未提交的内容，历史反馈不会改变。") }
        .confirmationDialog("导入登录前的游客草稿？", isPresented: $importGuestConfirm, titleVisibility: .visible) {
            Button("导入并检查内容") { if let draft = service.guestDraft { model.importGuestDraft(draft); service.guestDraft = nil } }
            Button("使用当前草稿", role: .cancel) { service.guestDraft = nil }
        } message: { Text("确认后保存到当前账号，提交前仍可编辑。") }
    }

    private var introduction: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "envelope.open").font(.title3)
                .foregroundStyle(DiaryLibraryStyle.accent).frame(width: 48, height: 48)
                .background(DiaryLibraryStyle.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("把问题和想法告诉我们").font(.system(.title3, design: .serif).weight(.semibold))
                Text("问题或新想法，都可以写在这里。")
                    .font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary).fixedSize(horizontal: false, vertical: true)
                if let config = model.config, config.accepting, !config.service_hours.isEmpty {
                    Text("服务时间：\(config.service_hours)").font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                }
            }
        }
    }
    @ViewBuilder private var serviceStatus: some View {
        if model.configurationLoading && model.config == nil {
            HStack(spacing: 10) { ProgressView(); Text("正在连接反馈服务…").font(.footnote) }
        } else if let config = model.config, !config.accepting {
            FeedbackInlineNotice(message: config.pause_message, symbol: "pause.circle", actionTitle: "刷新状态") { Task { await model.refreshConfiguration() } }
        } else if let error = model.configurationError {
            FeedbackInlineNotice(message: error, symbol: "wifi.exclamationmark", actionTitle: "重试") { Task { await model.refreshConfiguration() } }
        }
    }
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("想反馈哪一类？")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                ForEach(model.config?.types ?? []) { kind in
                    FeedbackCategoryButton(kind: kind, selected: model.draft.kind == kind.code) { model.draft.kind = kind.code }
                        .disabled(model.isWorking)
                }
            }
            if let issue = model.fieldError(.kind) { fieldError(issue) }
        }
    }
    private var writingCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                sectionTitle("一句话概括")
                TextField("例如：导出手帐后，照片变模糊了", text: $model.draft.title, axis: .vertical)
                    .font(.body).lineLimit(1...3).padding(.vertical, 4)
                    .focused($focusedField, equals: .title).submitLabel(.next)
                    .onSubmit { focusedField = .description }
                    .accessibilityIdentifier("feedback.title")
                if let issue = model.fieldError(.title) { fieldError(issue) }
                else { Text("最多 \(model.limits.title_max) 字").font(.caption).foregroundStyle(DiaryLibraryStyle.secondary) }
            }.id(FeedbackInputField.title)
            Rectangle().fill(DiaryLibraryStyle.line.opacity(0.6)).frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("详细说说")
                ZStack(alignment: .topLeading) {
                    if model.draft.description.isEmpty {
                        Text("在哪里遇到问题？\n发生了什么，原本希望怎样？")
                            .font(.body).foregroundStyle(DiaryLibraryStyle.secondary.opacity(0.8))
                            .padding(.top, 8).padding(.leading, 4).allowsHitTesting(false)
                    }
                    TextEditor(text: $model.draft.description)
                        .font(.body).scrollContentBackground(.hidden)
                        .frame(height: editorHeight).focused($focusedField, equals: .description)
                        .accessibilityLabel("详细说明，至少 \(model.limits.description_min) 个字")
                        .accessibilityIdentifier("feedback.description")
                }
                HStack(alignment: .top, spacing: 12) {
                    if let issue = model.fieldError(.description) { fieldError(issue) }
                    else {
                        Text(model.descriptionCount == 0 ? "至少 \(model.limits.description_min) 个字" : model.descriptionHint)
                            .foregroundStyle(model.descriptionCount < model.limits.description_min ? DiaryLibraryStyle.accent : DiaryLibraryStyle.secondary)
                    }
                    Spacer(minLength: 0)
                    Text("\(model.descriptionCount)/\(model.limits.description_max)").monospacedDigit().foregroundStyle(DiaryLibraryStyle.secondary).fixedSize()
                }.font(.caption)
            }.id(FeedbackInputField.description)
        }
        .padding(18).feedbackPaperCard()
        .disabled(model.isWorking)
    }
    private var screenshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { sectionTitle("截图", optional: true); Spacer(); Text("\(model.draft.photos.count)/\(model.limits.attachments_max)").font(.caption).foregroundStyle(DiaryLibraryStyle.secondary) }
            FeedbackScreenshotGrid(photos: $model.draft.photos, selection: $selectedPhotos, maximum: model.limits.attachments_max,
                                   disabled: model.isWorking, uploading: model.uploadingPhotoID)
            Text("提交时一起上传；最多 \(model.limits.attachments_max) 张，请遮挡截图中的私人信息。")
                .font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
            if let issue = model.fieldError(.photos) { fieldError(issue) }
        }
    }
    private var supplementalCard: some View {
        DisclosureGroup(isExpanded: $moreExpanded) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("联系方式", optional: true)
                    TextField("手机号或邮箱，方便进一步沟通", text: $model.draft.contact)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focusedField, equals: .contact).submitLabel(.done)
                        .onSubmit { focusedField = nil }.accessibilityIdentifier("feedback.contact")
                    if let issue = model.fieldError(.contact) { fieldError(issue) }
                }.id(FeedbackInputField.contact)
                Divider().overlay(DiaryLibraryStyle.line)
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("关联订单或定制", optional: true)
                    if model.draft.relatedID.isEmpty {
                        Button { focusedField = nil; showsRelated = true } label: {
                            HStack { Label("选择相关记录", systemImage: "link"); Spacer(); Image(systemName: "chevron.right").font(.caption) }.frame(minHeight: 44)
                        }.buttonStyle(.plain)
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: model.draft.relatedType == "order" ? "shippingbox" : "sparkles").foregroundStyle(DiaryLibraryStyle.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.draft.relatedType == "order" ? "印制订单" : "专属定制").font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                                Text(model.draft.relatedTitle ?? "已关联记录").font(.subheadline).lineLimit(2)
                            }
                            Spacer()
                            Button { model.draft.relatedID = ""; model.draft.relatedType = ""; model.draft.relatedTitle = nil } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }.accessibilityLabel("移除关联记录")
                        }
                    }
                    if let issue = model.fieldError(.related) { fieldError(issue) }
                }.id(FeedbackInputField.related)
            }.padding(.top, 18)
        } label: {
            HStack(spacing: 10) {
                Text("补充信息").font(.subheadline.weight(.semibold))
                Text(model.draft.relatedID.isEmpty && model.draft.contact.isEmpty ? "选填" : "已填写")
                    .font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
            }.frame(minHeight: 28)
        }
        .padding(18).feedbackPaperCard().disabled(model.isWorking)
    }
    private var privacyRow: some View {
        Button { focusedField = nil; showsEnvironment = true } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.shield").padding(.top, 2)
                Text("自动附带版本信息，查看数据说明。")
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "info.circle")
            }.font(.caption).foregroundStyle(DiaryLibraryStyle.secondary).frame(minHeight: 44)
        }.buttonStyle(.plain)
    }
    @ViewBuilder private var notices: some View {
        if let error = model.submissionError { FeedbackInlineNotice(message: error, symbol: "exclamationmark.circle") }
        if let error = model.draftSaveError { FeedbackInlineNotice(message: error, symbol: "externaldrive.badge.exclamationmark") }
        if let notice = model.notice { FeedbackInlineNotice(message: notice, symbol: "info.circle") }
    }
    private func bottomBar(scroll: ScrollViewProxy) -> some View {
        VStack(spacing: 10) {
            if let ticket = model.success {
                NavigationLink { FeedbackDetailScreen(id: ticket.id, owner: model.owner) } label: {
                    Label("查看处理进度", systemImage: "bubble.left.and.bubble.right").frame(maxWidth: .infinity)
                }.buttonStyle(FeedbackPrimaryButtonStyle())
            } else {
                HStack(spacing: 6) {
                    Image(systemName: bottomHintSymbol)
                    Text(bottomHint).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }.font(.caption).foregroundStyle(DiaryLibraryStyle.secondary).accessibilityIdentifier("feedback.submissionHint")
                Button { activateSubmit(scroll: scroll) } label: {
                    HStack(spacing: 10) {
                        if model.isWorking || model.configurationLoading { ProgressView().tint(colorScheme == .dark ? .black : .white) }
                        else { Image(systemName: "paperplane") }
                        Text(buttonTitle).fontWeight(.semibold)
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(FeedbackPrimaryButtonStyle())
                .disabled(model.isWorking || model.configurationLoading)
                .accessibilityIdentifier("feedback.submit")
            }
        }
        .frame(maxWidth: 640).padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 12)
        .frame(maxWidth: .infinity).background(.regularMaterial)
        .overlay(alignment: .top) { Rectangle().fill(DiaryLibraryStyle.line.opacity(0.55)).frame(height: 0.5) }
    }
    private var buttonTitle: String {
        if model.isWorking { return model.stage.title }
        if model.configurationLoading { return "正在连接…" }
        if model.config == nil || model.configurationError != nil { return "重新连接服务" }
        if model.config?.accepting == false { return "刷新受理状态" }
        if loginContext?.isDeviceAccount == true { return "登录后提交" }
        return model.submissionError == nil ? "提交反馈" : "重试提交"
    }
    private var bottomHintSymbol: String {
        if model.draftSaveError != nil || model.submissionError != nil || (model.attempted && !model.issues.isEmpty) { return "exclamationmark.circle" }
        return model.issues.isEmpty && model.draftSaved ? "checkmark.circle" : "pencil.line"
    }
    private var bottomHint: String {
        if model.isWorking { return "请稍候，填写内容会继续保留。" }
        if model.draftSaveError != nil { return "草稿保存失败，请先检查设备空间。" }
        if let error = model.submissionError { return "尚未提交成功：\(error)" }
        if model.attempted, let issue = model.issues.first { return issue.message }
        if model.descriptionCount > 0 && model.descriptionCount < model.limits.description_min { return model.descriptionHint }
        return model.draftSaved ? "草稿已保存，回复可在“我的反馈”查看。" : "填写内容会自动保存在本机。"
    }
    private func activateSubmit(scroll: ScrollViewProxy) {
        guard !model.isWorking else { return }
        guard model.config != nil, model.configurationError == nil, model.config?.accepting == true else {
            work = Task { await model.refreshConfiguration() }; return
        }
        if let field = model.validateForSubmission() {
            if field == .contact || field == .related { moreExpanded = true }
            if reduceMotion { scroll.scrollTo(field, anchor: .center) }
            else { withAnimation(.easeInOut(duration: 0.2)) { scroll.scrollTo(field, anchor: .center) } }
            focusedField = [.title, .description, .contact].contains(field) ? field : nil
            return
        }
        focusedField = nil
        if loginContext?.isDeviceAccount == true { showsLogin = true; return }
        work = Task { await model.submit() }
    }
    private func checkGuestDraft() {
        if service.guestDraft != nil && loginContext?.isDeviceAccount == false { importGuestConfirm = true }
    }
    private func sectionTitle(_ text: String, optional: Bool = false) -> some View {
        HStack(spacing: 6) { Text(text).font(.subheadline.weight(.semibold)); if optional { Text("选填").font(.caption).foregroundStyle(DiaryLibraryStyle.secondary) } }
    }
    private func fieldError(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }
}
