import SwiftUI

struct HelpCenterScreen: View {
    let owner: String
    @ObservedObject private var service = HelpFeedbackService.shared
    @State private var categories: [HelpCategory] = []
    @State private var articles: [HelpArticle] = []
    @State private var config: HelpServiceConfig?
    @State private var query = ""
    @State private var category = ""
    @State private var cursor: String?
    @State private var loading = false
    @State private var error: String?
    @State private var offline = false
    @State private var generation = UUID()
    @State private var loadedFilter = ""
    var body: some View {
        SupportCanvas {
            SupportHeading(title: "我们在这里，听你说", subtitle: "查找使用方法，或把遇到的问题告诉我们。")
            VStack(spacing: 0) {
                NavigationLink { FeedbackFormScreen(owner: owner) } label: {
                    SupportNavigationRow(title: "提交反馈", symbol: "square.and.pencil", detail: "问题、建议与印制咨询")
                }
                Divider().overlay(DiaryLibraryStyle.line).padding(.leading, 69)
                NavigationLink { FeedbackListScreen(owner: owner) } label: {
                    SupportNavigationRow(title: "我的反馈", symbol: "bubble.left.and.bubble.right", detail: "查看进度与回复", badge: service.unread > 0 ? "新回复 \(min(service.unread, 99))" : "")
                }
            }.buttonStyle(.plain).feedbackPaperCard()
            if let config {
                VStack(alignment: .leading, spacing: 8) {
                    if !config.accepting { FeedbackInlineNotice(message: config.pause_message, symbol: "clock") }
                    if !config.service_hours.isEmpty { Label("服务时间 · " + config.service_hours, systemImage: "clock").font(.caption).foregroundStyle(DiaryLibraryStyle.secondary) }
                    if !config.contact.isEmpty { Text(config.contact).font(.caption).textSelection(.enabled) }
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                Text("寻找答案").font(.headline)
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(DiaryLibraryStyle.secondary)
                    TextField("搜索帮助内容", text: $query).submitLabel(.search)
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("清除搜索") }
                }.padding(14).feedbackPaperCard()
                if !categories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            categoryButton("全部", code: "")
                            ForEach(categories) { categoryButton($0.name, code: $0.code) }
                        }
                    }
                }
                if offline { FeedbackInlineNotice(message: "正在显示离线帮助内容，联网后可刷新。", symbol: "wifi.slash") }
                if let error { FeedbackInlineNotice(message: error, symbol: "exclamationmark.circle", actionTitle: "重新加载", action: { Task { await load() } }) }
                ForEach(articles) { article in
                    NavigationLink { HelpArticleScreen(article: article, owner: owner) } label: {
                        SupportNavigationRow(title: article.title, symbol: "doc.text", detail: article.summary)
                            .feedbackPaperCard()
                    }.buttonStyle(.plain)
                }
                if loading { ProgressView("正在查找答案…").frame(maxWidth: .infinity).padding() }
                else if articles.isEmpty && error == nil {
                    SupportEmptyState(symbol: "book.closed", title: query.isEmpty && category.isEmpty ? "帮助内容正在整理" : "没有找到相关答案", message: "你可以直接提交反馈，我们会在反馈详情中回复。")
                    NavigationLink { FeedbackFormScreen(owner: owner) } label: { Text("向我们提问").frame(maxWidth: .infinity) }.buttonStyle(FeedbackPrimaryButtonStyle())
                }
                if let cursor { DiaryPaginationFooter(token: query + "|" + category + "|" + cursor, loading: loading, error: error) { await load(more: true) } }
            }
        }
        .navigationTitle("帮助与反馈")
        .toolbar(.hidden, for: .tabBar)
        .task(id:query+"|"+category) { if !query.isEmpty { try? await Task.sleep(for:.milliseconds(300)) }; guard !Task.isCancelled else { return };await load() }
        .task { config = try? await service.config(); await service.refreshUnread(owner:owner) }
        .refreshable { await load(); await service.refreshUnread(owner:owner) }
    }
    private func categoryButton(_ title: String, code: String) -> some View {
        Button { category = code } label: {
            Text(title).font(.subheadline.weight(category == code ? .semibold : .regular))
                .padding(.horizontal, 16).frame(minHeight: 44)
                .foregroundStyle(category == code ? DiaryLibraryStyle.accent : DiaryLibraryStyle.secondary)
                .background(category == code ? DiaryLibraryStyle.accent.opacity(0.10) : DiaryLibraryStyle.surface, in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(category == code ? .isSelected : [])
    }
    private func load(more: Bool = false) async {
        let previousCursor = more ? cursor : nil
        if more { guard !loading, cursor != nil, loadedFilter == query + "|" + category else { return } }
        let filter = query + "|" + category
        if !more && loadedFilter != filter { articles = []; cursor = nil; offline = false; loadedFilter = filter }
        let stamp = UUID();generation = stamp;loading = true;error = nil
        defer { if stamp == generation { loading = false } }
        do {
            let values = try await service.articles(query:query,category:category,cursor:more ? cursor : nil)
            let cats = more ? categories : ((try? await service.categories()) ?? categories)
            guard stamp == generation, filter == query + "|" + category else { return }
            categories = cats; articles = more ? articles.appendingUnique(values.results) : values.results;cursor = values.next_cursor == previousCursor ? nil : values.next_cursor;offline = false
            if query.isEmpty && category.isEmpty { service.cache(articles,name:"articles");service.cache(cats,name:"categories");service.cache(Date(),name:"cached-at") }
        } catch is CancellationError { }
        catch {
            guard stamp == generation, filter == query + "|" + category else { return };self.error = error.localizedDescription; if !more { cursor = nil }
            if articles.isEmpty && query.isEmpty && category.isEmpty { articles = service.cached([HelpArticle].self,name:"articles") ?? [];categories = service.cached([HelpCategory].self,name:"categories") ?? [];offline = !articles.isEmpty }
        }
    }
}

struct HelpArticleScreen: View {
    let article: HelpArticle; let owner: String
    @State private var value: HelpArticle?
    @State private var error: String?
    @State private var offline = false
    @State private var unavailable = false
    var body: some View {
        SupportCanvas {
            if unavailable {
                SupportEmptyState(symbol: "doc.questionmark", title: "文章暂不可用", message: "这篇帮助内容已下线，或不适用于当前版本。")
                Button("重新加载") { Task { await load() } }
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    Text((value ?? article).title).font(.title2.bold())
                    if let updated = (value ?? article).updated_at { Text("更新于 " + supportDate(updated)).font(.caption).foregroundStyle(DiaryLibraryStyle.secondary) }
                    if offline { FeedbackInlineNotice(message: "正在显示离线内容，可能不是最新版本。", symbol: "wifi.slash") }
                    HelpArticleBody(text: (value ?? article).body).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(20).feedbackPaperCard()
                if let error { FeedbackInlineNotice(message: error, symbol: "exclamationmark.circle", actionTitle: "重试", action: { Task { await load() } }) }
            }
            NavigationLink { FeedbackFormScreen(owner: owner, articleID: article.id) } label: { Text("仍有问题，提交反馈").frame(maxWidth: .infinity) }.buttonStyle(FeedbackPrimaryButtonStyle())
        }.navigationTitle("帮助详情").toolbar(.hidden, for: .tabBar).task { await load() }
    }
    private func load() async {
        do { value = try await HelpFeedbackService.shared.article(article.id);offline = false;unavailable = false;error = nil;HelpFeedbackService.shared.cache(value,name:"article-"+article.id) }
        catch {
            // A server response explicitly invalidating the article must never fall back to a published cache.
            let invalid: Bool
            if case SupportNetworkError.http(let status, _, _) = error { invalid = status == 404 || status == 410 } else { invalid = false }
            if invalid { unavailable = true;value = nil;HelpFeedbackService.shared.removeCachedArticle(article.id) }
            else { value = HelpFeedbackService.shared.cached(HelpArticle.self,name:"article-"+article.id) ?? article;offline = true;self.error = error.localizedDescription }
        }
    }
}

struct FeedbackListScreen: View {
    let owner: String
    @State private var rows: [FeedbackTicket] = []
    @State private var status = ""
    @State private var cursor: String?
    @State private var paginationStatus = ""
    @State private var busy = false
    @State private var error: String?
    @State private var generation = UUID()
    var body: some View {
        SupportCanvas {
            SupportHeading(title: "每一条反馈，都有回音", subtitle: "在这里查看处理进度，继续补充问题。")
            Picker("反馈范围", selection: $status) { Text("全部").tag(""); Text("进行中").tag("active"); Text("已结束").tag("closed") }.pickerStyle(.segmented)
            if let error { FeedbackInlineNotice(message: error, symbol: "exclamationmark.circle", actionTitle: "重新加载", action: { Task { await load() } }) }
            LazyVStack(spacing: 12) {
                ForEach(rows) { ticket in
                    NavigationLink { FeedbackDetailScreen(id: ticket.id, owner: owner) } label: { FeedbackTicketCard(ticket: ticket) }.buttonStyle(.plain)
                }
            }
            if busy { ProgressView("正在加载反馈…").frame(maxWidth: .infinity) }
            else if rows.isEmpty && error == nil {
                SupportEmptyState(symbol: "bubble.left.and.bubble.right", title: status.isEmpty ? "还没有反馈" : status == "active" ? "暂无进行中的反馈" : "暂无已结束的反馈", message: "问题、想法或建议，都可以告诉我们。提交后可在这里查看回复。")
            }
            if let cursor { DiaryPaginationFooter(token: status + "|" + cursor, loading: busy, error: error) { await load(more: true) } }
            NavigationLink { FeedbackFormScreen(owner: owner) } label: { Label("提交新反馈", systemImage: "square.and.pencil").frame(maxWidth: .infinity) }.buttonStyle(FeedbackPrimaryButtonStyle())
        }.navigationTitle("我的反馈").toolbar(.hidden, for: .tabBar)
            .task(id: status) { rows = []; cursor = nil; await load() }.refreshable { await load() }
    }
    private func load(more: Bool = false) async {
        let previousCursor = more ? cursor : nil
        let activeStatus = status
        if more { guard !busy, cursor != nil, paginationStatus == status else { return } }
        else { paginationStatus = status }
        let stamp = UUID();generation = stamp;busy = true;error = nil
        defer { if stamp == generation { busy = false } }
        do { let p = try await HelpFeedbackService.shared.tickets(owner:owner,status:status,cursor:more ? cursor : nil);guard stamp == generation, activeStatus == status else { return };rows = more ? rows.appendingUnique(p.results) : p.results;cursor = p.next_cursor == previousCursor ? nil : p.next_cursor }
        catch is CancellationError { }
        catch { if stamp == generation { self.error = error.localizedDescription } }
    }
}

func supportDate(_ value: String) -> String {
    let formatter = ISO8601DateFormatter();formatter.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
    let date = formatter.date(from:value) ?? ISO8601DateFormatter().date(from:value)
    return date?.formatted(date:.abbreviated,time:.shortened) ?? value
}

struct AppVersionScreen: View {
    @State private var copied = false
    var body: some View {
        SupportCanvas {
            SupportEmptyState(symbol: "book.closed", title: "TravelDiary", message: "把旅途留在手帐里")
            VStack(spacing: 16) {
                LabeledContent("版本", value: AppVersionInformation.version)
                Divider().overlay(DiaryLibraryStyle.line)
                LabeledContent("构建号", value: AppVersionInformation.build)
                Divider().overlay(DiaryLibraryStyle.line)
                LabeledContent("系统", value: "iOS " + AppleDeviceInfo.systemVersion)
            }.font(.subheadline).padding(20).feedbackPaperCard()
            Button { UIPasteboard.general.string = AppVersionInformation.copiedText; copied = true } label: {
                Label(copied ? "已复制版本信息" : "复制版本信息", systemImage: copied ? "checkmark" : "doc.on.doc").frame(maxWidth: .infinity)
            }.buttonStyle(FeedbackPrimaryButtonStyle())
        }.navigationTitle("版本信息").toolbar(.hidden, for: .tabBar)
    }
}

private struct HelpArticleBody: View {
    let text: String
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            ForEach(HelpBodyBlock.parse(text)) { block in
                switch block {
                case .text(_,let value):
                    Text((try? AttributedString(markdown:value,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(value)).textSelection(.enabled)
                case .image(_,let id,let alt):HelpArticleImage(id:id,alt:alt)
                }
            }
        }.environment(\.openURL,OpenURLAction { url in url.scheme == "https" && url.host != nil ? .systemAction : .discarded })
    }
}
private struct HelpArticleImage: View {
    let id: String;let alt: String
    @State private var url: URL?
    @State private var error: String?
    var body: some View {
        VStack(alignment:.leading) {
            if let url { AsyncImage(url:url) { phase in switch phase { case .success(let image):image.resizable().scaledToFit();case .failure:Text("图片暂不可用");case .empty:ProgressView();@unknown default:EmptyView() } }.accessibilityLabel(alt.isEmpty ? "帮助示意图" : alt) }
            if let error { Text(error).font(.caption);Button("重试图片") { Task { await load() } } }
            if !alt.isEmpty { Text(alt).font(.caption).foregroundStyle(.secondary) }
        }.task { await load() }
    }
    private func load() async {
        struct Link:Decodable {let url:String}
        do {
            let link:Link = try await HelpFeedbackService.shared.request("help/images/\(id)/url/?version=\(AppVersionInformation.version)")
            guard let u=URL(string:link.url),u.scheme=="https",u.host?.hasSuffix(".aliyuncs.com")==true else {throw HelpFailure("图片地址不可用")}
            url=u;error=nil
        } catch { self.error="图片加载失败，联网后可重试" }
    }
}
