import SwiftUI

private struct FeedbackRelatedRecord: Identifiable {
    let id: String
    let title: String
    let subtitle: String
}

struct FeedbackRelatedPicker: View {
    let owner: String
    let select: (String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind = "order"
    @State private var values: [FeedbackRelatedRecord] = []
    @State private var error: String?
    @State private var next = 0
    @State private var hasMore = true
    @State private var busy = false
    @State private var generation = UUID()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("关联相关记录，方便我们更快了解情况。")
                        .font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
                    Picker("记录类型", selection: $kind) { Text("印制订单").tag("order"); Text("专属定制").tag("customization") }.pickerStyle(.segmented)
                    ForEach(values) { value in
                        Button { select(kind, value.id, value.title); dismiss() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: kind == "order" ? "shippingbox" : "sparkles").foregroundStyle(DiaryLibraryStyle.accent)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(value.title).font(.body.weight(.medium)).multilineTextAlignment(.leading)
                                    Text(value.subtitle).font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                                }
                                Spacer(); Image(systemName: "plus.circle").foregroundStyle(DiaryLibraryStyle.accent)
                            }.frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).padding(16).feedbackPaperCard()
                        }.buttonStyle(.plain)
                    }
                    if let error { FeedbackInlineNotice(message: error, symbol: "wifi.exclamationmark", actionTitle: "重试") { Task { await load() } } }
                    if busy { ProgressView("正在加载…").frame(maxWidth: .infinity) }
                    else if values.isEmpty && error == nil { ContentUnavailableView("暂无可关联记录", systemImage: "tray", description: Text("不关联记录也可以直接提交反馈。")) }
                    if hasMore && !busy && error == nil { Button("加载更多") { Task { await load() } }.frame(maxWidth: .infinity) }
                }.padding(20)
            }
            .background(DiaryLibraryStyle.background).foregroundStyle(DiaryLibraryStyle.ink)
            .navigationTitle("选择关联记录").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("取消") { dismiss() } } }
            .task(id: kind) { generation = UUID(); values = []; next = kind == "order" ? 0 : 1; hasMore = true; await load() }
        }.tint(DiaryLibraryStyle.accent)
    }
    private func load() async {
        let stamp = generation
        let selected = kind
        busy = true; error = nil
        defer { if generation == stamp { busy = false } }
        do {
            let records: [FeedbackRelatedRecord]
            let following: Int?
            if selected == "order" {
                let page = try await PrintOrderService.shared.orders(owner: owner, offset: next)
                records = page.results.map { .init(id: $0.id, title: $0.title.isEmpty ? "未命名手帐订单" : $0.title, subtitle: $0.statusText) }
                following = page.next_offset
            } else {
                let page = try await CustomizationService.shared.list(owner: owner, page: next)
                records = page.results.map { .init(id: $0.id, title: $0.title.isEmpty ? "未命名定制" : $0.title, subtitle: "专属手帐定制") }
                following = page.next_page
            }
            guard stamp == generation else { return }
            values += records
            hasMore = following != nil
            if let following { next = following }
        } catch is CancellationError { }
        catch { if stamp == generation { self.error = error.localizedDescription } }
    }
}
