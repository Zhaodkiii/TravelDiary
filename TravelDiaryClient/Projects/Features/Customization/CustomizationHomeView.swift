import SwiftUI

struct CustomizationHomeView: View {
    let owner: String
    @ObservedObject private var service = CustomizationService.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var rows: [CustomRequestRow] = []
    @State private var error: String?
    @State private var creating = false
    @State private var loading = false
    @State private var loaded = false
    @State private var nextPage: Int?
    @State private var showingSettings = false
    @State private var showHistory = false
    private var attention: [CustomRequestRow] { rows.filter { CustomizationFormRules.needsAttention($0.status) } }
    private var remaining: [CustomRequestRow] {
        rows.filter { !CustomizationFormRules.needsAttention($0.status) && (showHistory || !CustomizationFormRules.isHistory($0.status)) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                introduction
                if let error {
                    DiaryLibraryNotice(message: error) { Task { await load() } }
                }
                if let problem = service.routeError { DiaryLibraryNotice(message: problem) }
                if !loaded && loading { ProgressView("正在读取定制记录…").frame(maxWidth: .infinity).padding(.vertical, 32) }
                if !attention.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("等你处理").font(.headline)
                        ForEach(attention) { row in requestCard(row, prominent: true) }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    ViewThatFits(in: .horizontal) {
                        HStack { Text("我的定制").font(.headline); Spacer(); historyToggle }
                        VStack(alignment: .leading) { Text("我的定制").font(.headline); historyToggle }
                    }
                    if loaded && rows.isEmpty && error == nil {
                        ContentUnavailableView("开始记录你的故事", systemImage: "book.closed",
                            description: Text("选几张照片，告诉我们想留下的回忆。"))
                    } else if loaded && remaining.isEmpty && attention.isEmpty && error == nil {
                        Text("暂无进行中的定制，可查看历史记录。").font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
                    }
                    ForEach(remaining) { row in requestCard(row) }
                    if let nextPage {
                        DiaryPaginationFooter(token: String(nextPage), loading: loading, error: error) { await load(page: nextPage) }
                    }
                }
                Label("资料仅用于本次制作与交付，默认不公开。", systemImage: "lock")
                    .font(.footnote).foregroundStyle(DiaryLibraryStyle.secondary)
            }
            .frame(maxWidth: 640, alignment: .leading).padding(20).frame(maxWidth: .infinity)
        }
        .background(DiaryLibraryStyle.background).foregroundStyle(DiaryLibraryStyle.ink).tint(DiaryLibraryStyle.accent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: { Image(systemName: "bell").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("定制提醒设置")
            }
        }
        .sheet(isPresented: $showingSettings) { CustomizationNotificationSettingsView(owner: owner) }
        .refreshable { await load() }
        .task {
            await load()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
                if scenePhase == .active && rows.contains(where: { !CustomizationFormRules.isHistory($0.status) }) { await load() }
            }
        }
        .onChange(of: service.refreshSequence) { _, _ in Task { await load() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load() } } }
    }
    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("照片 · 故事 · 专属手帐", systemImage: "sparkles").font(.subheadline).foregroundStyle(DiaryLibraryStyle.accent)
            Text("把值得珍藏的瞬间，\n做成一本手帐。").font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text("选好照片，讲讲故事，由制作方为你排版。成品可加入书架，继续编辑。")
                .font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
            Button { Task { await create() } } label: {
                HStack { if creating { ProgressView() }; Text(creating ? "正在创建草稿…" : "开始我的定制") }
                    .frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(creating)
        }
    }
    private var historyToggle: some View {
        DiaryLibraryChip(title: "包含历史", selected: showHistory, compact: true) { showHistory.toggle() }
    }
    private func requestCard(_ row: CustomRequestRow, prominent: Bool = false) -> some View {
        NavigationLink(value: CustomizationRoute(id: row.id)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: row.status == "draft" ? "square.and.pencil" : "book.closed")
                        .foregroundStyle(DiaryLibraryStyle.accent).frame(width: 40, height: 48)
                        .background(DiaryLibraryStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.title.isEmpty ? "未命名草稿" : row.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                        Text(customizationStatus(row.status)).font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if row.unread {
                        Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(DiaryLibraryStyle.accent)
                            .accessibilityLabel("有未读更新")
                    }
                }
                HStack {
                    Text(CustomizationFormRules.actionTitle(for: row.status))
                    Spacer()
                    Image(systemName: "arrow.right")
                }.font(.subheadline.weight(.medium)).foregroundStyle(DiaryLibraryStyle.accent).frame(minHeight: 32)
            }.padding(16).background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .leading) {
                    if prominent { Capsule().fill(DiaryLibraryStyle.accent).frame(width: 3).padding(.vertical, 18) }
                }
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
    }
    private func load(page: Int = 1) async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        do {
            let result = try await service.list(owner: owner, page: page)
            try Task.checkCancellation()
            if page == 1 { rows = result.results }
            else {
                var ids = Set(rows.map(\.id))
                rows += result.results.filter { ids.insert($0.id).inserted }
            }
            nextPage = result.next_page == page ? nil : result.next_page; error = nil; loaded = true
            await service.refreshUnread(owner: owner)
        } catch is CancellationError { }
        catch { self.error = "定制记录暂时无法刷新：" + error.localizedDescription; loaded = true }
    }
    private func create() async {
        guard !creating else { return }
        creating = true; defer { creating = false }
        do { let value = try await service.create(owner: owner); service.routeID = value.id }
        catch { self.error = error.localizedDescription }
    }
}
