import SwiftUI
import PhotosUI

struct FeedbackDetailScreen: View {
    let id: String; let owner: String
    @Environment(\.scenePhase) private var scenePhase
    @State private var ticket: FeedbackTicket?
    @State private var messages: [FeedbackMessage] = []
    @State private var cursor: String?
    @State private var busy = false
    @State private var loading = false
    @State private var error: String?
    @State private var text = ""
    @State private var photos: [FeedbackPhoto] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var preview: IdentifiableURL?
    @State private var closeConfirm = false
    @State private var highestDisplayed = 0
    @State private var readTask: Task<Void,Never>?
    @State private var draftLoaded = false
    @State private var composing = false
    @State private var replyError: String?
    @State private var saveTask: Task<Void, Never>?
    @State private var importing = false
    private var draftName: String { "reply-"+id }
    private var canReply: Bool { ticket?.allowed_actions.contains("reply") == true }
    var body: some View {
        SupportCanvas {
            if let ticket {
                FeedbackDetailSummary(ticket: ticket)
                HStack {
                    Text("问题与回复").font(.headline)
                    Spacer()
                    if loading { ProgressView().controlSize(.small) }
                }
            }
            if ticket == nil && loading { ProgressView("正在加载反馈…").frame(maxWidth: .infinity).padding() }
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(messages) { item in
                    FeedbackMessageRow(message: item, onAttachment: { asset in Task { await openAttachment(asset.id) } }).onAppear { displayed(item) }
                }
            }
            if let cursor { DiaryPaginationFooter(token: cursor + "|\(messages.count)", loading: loading, error: error) { await load(more: true) } }
            if let error { FeedbackInlineNotice(message: error, symbol: "exclamationmark.circle", actionTitle: "重新加载", action: { Task { await load() } }) }
            if let ticket, ticket.status == "closed" {
                NavigationLink { FeedbackFormScreen(owner: owner, previousID: id) } label: {
                    Label("基于此问题发起新反馈", systemImage: "square.and.pencil").frame(maxWidth: .infinity)
                }.buttonStyle(FeedbackPrimaryButtonStyle())
            }
        }
        .safeAreaInset(edge: .bottom) {
            if canReply {
                VStack(spacing: 10) {
                    if ticket?.status == "resolved", ticket?.allowed_actions.contains("close") == true {
                        Button("确认解决") { closeConfirm = true }.buttonStyle(.bordered).disabled(busy)
                    }
                    Button { replyError = nil; composing = true } label: {
                        Label(text.isEmpty && photos.isEmpty ? "补充问题" : "继续编辑补充", systemImage: "square.and.pencil").frame(maxWidth: .infinity)
                    }.buttonStyle(FeedbackPrimaryButtonStyle()).disabled(busy)
                }.padding(.horizontal, 20).padding(.vertical, 12).background(.regularMaterial)
            }
        }
        .toolbar {
            if ticket?.allowed_actions.contains("close") == true {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu { Button("结束此反馈", systemImage: "checkmark.seal") { closeConfirm = true } } label: { Image(systemName: "ellipsis.circle") }.disabled(busy)
                }
            }
        }
        .navigationTitle("反馈详情").navigationBarTitleDisplayMode(.inline)
        .task {
            if !draftLoaded { if let draft = HelpFeedbackService.shared.load(owner:owner,name:draftName) { text = draft.description;photos = draft.photos };draftLoaded = true }
            await load()
            while !Task.isCancelled { do { try await Task.sleep(for:.seconds(30)) } catch { return };if scenePhase == .active && !busy { await load() } }
        }
        .onChange(of:scenePhase) { _,phase in if phase == .active { Task { await load() } } }
        .onChange(of:text) { _,_ in scheduleSave() }
        .onChange(of:photos.count) { _,_ in scheduleSave() }
        .onChange(of:selectedPhotos) { _,items in guard !items.isEmpty else { return };Task { await importPhotos(items) } }
        .onDisappear { readTask?.cancel();saveTask?.cancel();persist() }
        .refreshable { await load() }
        .sheet(isPresented: $composing, onDismiss: { persist() }) { replyComposer }
        .sheet(item:$preview) { FeedbackImagePreview(url:$0.url) }
        .confirmationDialog("确认结束此反馈？",isPresented:$closeConfirm,titleVisibility:.visible) { Button("确认结束") { Task { await send(action:"close") } } } message: { Text("结束后不能继续补充，可基于原问题创建新反馈。") }
    }
    private var replyComposer: some View {
        NavigationStack {
            SupportCanvas {
                SupportHeading(title: "再多告诉我们一点", subtitle: "补充操作步骤、遇到的问题或截图，帮助我们继续跟进。")
                VStack(alignment: .leading, spacing: 12) {
                    Text("补充说明").font(.headline)
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty { Text("可以说明问题出现的步骤和预期结果…").foregroundStyle(DiaryLibraryStyle.secondary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false) }
                        TextEditor(text: $text).scrollContentBackground(.hidden).frame(minHeight: 160).accessibilityLabel("补充说明")
                    }
                    Text("\(supportCharacterCount(text.trimmingCharacters(in: .whitespacesAndNewlines))) / 2000").font(.caption).foregroundStyle(DiaryLibraryStyle.secondary).frame(maxWidth: .infinity, alignment: .trailing)
                }.padding(16).feedbackPaperCard().disabled(busy)
                VStack(alignment: .leading, spacing: 12) {
                    Text("截图 · 选填").font(.headline)
                    FeedbackScreenshotGrid(photos: $photos, selection: $selectedPhotos, disabled: busy)
                    Text("最多 6 张，请留意截图中的私人信息。").font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                }
                if let replyError { FeedbackInlineNotice(message: replyError, symbol: "exclamationmark.circle") }
            }
            .navigationTitle("补充问题")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("暂存并关闭") { composing = false }.disabled(busy) } }
            .safeAreaInset(edge: .bottom) {
                Button { Task { await send() } } label: {
                    Text(importing ? "正在准备截图…" : busy ? "正在发送补充…" : "发送补充").frame(maxWidth: .infinity)
                }.buttonStyle(FeedbackPrimaryButtonStyle()).disabled(busy).padding(20).background(.regularMaterial)
            }
            .interactiveDismissDisabled(busy)
        }
    }
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { try? await Task.sleep(for: .milliseconds(350)); guard !Task.isCancelled else { return }; persist() }
    }
    private func persist() {
        guard draftLoaded else { return }
        if text.isEmpty && photos.isEmpty { HelpFeedbackService.shared.removeDraft(owner: owner, name: draftName); return }
        var d = FeedbackDraft();d.description = text;d.photos = photos
        do { try HelpFeedbackService.shared.save(d,owner:owner,name:draftName) } catch { self.error = "回复草稿保存失败：\(error.localizedDescription)" }
    }
    private func load(more: Bool = false) async {
        guard !loading, !more || cursor != nil else { return };loading = true;defer { loading = false }
        do {
            let t = try await HelpFeedbackService.shared.ticket(id,owner:owner)
            let p = try await HelpFeedbackService.shared.messages(id,owner:owner,afterSequence:messages.compactMap(\.sequence).max())
            ticket = t
            if more { let known = Set(messages.map(\.id));messages += p.results.filter { !known.contains($0.id) } }
            else {
                // Preserve the loaded history during periodic refresh, and update redacted messages.
                var byID = Dictionary(uniqueKeysWithValues:messages.map { ($0.id,$0) });for m in p.results { byID[m.id] = m }
                messages = byID.values.sorted { ($0.sequence ?? 0) < ($1.sequence ?? 0) }
            }
            cursor = p.next_cursor;error = nil
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    private func displayed(_ message: FeedbackMessage) {
        guard let sequence = message.sequence else { return };highestDisplayed = max(highestDisplayed,sequence)
        readTask?.cancel();let through = highestDisplayed
        readTask = Task { try? await Task.sleep(for:.milliseconds(250));guard !Task.isCancelled else { return };await HelpFeedbackService.shared.read(id,sequence:through,owner:owner) }
    }
    private func importPhotos(_ items: [PhotosPickerItem]) async {
        busy = true;importing = true;defer { busy = false;importing = false;selectedPhotos = [] }
        do { for item in items where photos.count < 6 { guard let data = try await item.loadTransferable(type:Data.self) else { throw HelpFailure("截图读取失败") };try HelpFeedbackService.shared.require(owner);photos.append(try HelpFeedbackService.shared.normalizePhoto(data)) };persist() }
        catch { replyError = error.localizedDescription }
    }
    private func send(action: String? = nil) async {
        guard let ticket, !busy else { return }
        if action == nil, let issue = FeedbackReplyValidation.issue(text: text, photoCount: photos.count) { replyError = issue; return }
        saveTask?.cancel();persist()
        busy = true;error = nil;replyError = nil;defer { busy = false }
        do {
            if action == nil { for i in photos.indices { photos[i] = try await HelpFeedbackService.shared.upload(photos[i],owner:owner);persist() } }
            self.ticket = try await HelpFeedbackService.shared.reply(ticket,text:action == "close" ? "" : text,photos:action == nil ? photos : [],owner:owner,action:action)
            if action == nil { text = "";photos = [];composing = false;HelpFeedbackService.shared.removeDraft(owner:owner,name:draftName) }
            await load();await HelpFeedbackService.shared.refreshUnread(owner:owner)
        } catch { let message = error.localizedDescription;await load();self.error = message;replyError = message;persist() }
    }
    private func openAttachment(_ id: String) async {
        do { preview = IdentifiableURL(url:try await HelpFeedbackService.shared.attachment(id,owner:owner)) }
        catch { self.error = error.localizedDescription }
    }
}

struct FeedbackDetailSummary: View {
    let ticket: FeedbackTicket
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FeedbackStatusBadge(ticket: ticket)
            Text(ticket.title).font(.title2.weight(.bold)).textSelection(.enabled)
            Text(ticket.statusExplanation).font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
            Divider().overlay(DiaryLibraryStyle.line)
            DisclosureGroup("反馈信息") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("提交于 " + supportDate(ticket.created_at)).font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                    Text(ticket.number).font(.caption.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Button(copied ? "已复制编号" : "复制反馈编号", systemImage: "doc.on.doc") { UIPasteboard.general.string = ticket.number; copied = true }.font(.caption).frame(minHeight: 44)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
            }.font(.subheadline)
        }.padding(20).feedbackPaperCard()
    }
}

struct FeedbackMessageRow: View {
    let message: FeedbackMessage
    let onAttachment: (FeedbackAttachment) -> Void
    private var staff: Bool { message.author_type == "staff" }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: staff ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    .foregroundStyle(DiaryLibraryStyle.accent).font(.title3)
                Text(staff ? "工作人员" : "我").font(.subheadline.weight(.semibold))
                Spacer()
            }
            if message.redacted { Text("这条消息已被隐藏").font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary) }
            else {
                if !message.body.isEmpty { Text(message.body).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                if !message.attachments.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], alignment: .leading, spacing: 8) {
                        ForEach(Array(message.attachments.enumerated()), id: \.element.id) { index, item in
                            Button { onAttachment(item) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "photo")
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("截图 \(index + 1)").font(.subheadline.weight(.medium))
                                        Text(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file)).font(.caption2)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.up.right").font(.caption)
                                }.padding(12).frame(minHeight: 52).background(DiaryLibraryStyle.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).foregroundStyle(DiaryLibraryStyle.accent)
                        }
                    }
                }
            }
            Text(supportDate(message.created_at)).font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).feedbackPaperCard()
            .padding(staff ? .trailing : .leading, 16)
    }
}
private struct FeedbackImagePreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { ScrollView([.horizontal,.vertical]) { AsyncImage(url:url) { phase in
            switch phase { case .empty: ProgressView();case .success(let image):image.resizable().scaledToFit().frame(maxWidth:1000,maxHeight:1600);case .failure:Text("截图暂不可用，请关闭后重新打开");@unknown default:EmptyView() }
        }.padding() }.navigationTitle("截图预览").toolbar { Button("完成") { dismiss() } } }
    }
}
