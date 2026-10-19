import SwiftUI

struct DiaryExportFormatPage: View {
    let book: DiaryBook
    let onSelectSpreads: () -> Void
    let onSelectPages: () -> Void
    let onSelectPDF: () -> Void
    let onSelectVideo: () -> Void
    let onSelectPrint: () -> Void
    private let ink = Color(red: 0.23, green: 0.36, blue: 0.31)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(book.title).font(.title2.bold())
            Text("把纸页里的风景，带到相册或分享给朋友。").foregroundStyle(.secondary)
            format("跨页拼图 · JPG", detail: "保留皮革外沿与装订环，每张组合 1–4 或 6 个跨页", icon: "book.pages") { onSelectSpreads() }
                .disabled(book.contentPages.isEmpty)
            format("单页图片 · JPG", detail: "自由选择页面，逐张保存清晰原稿", icon: "photo.on.rectangle") { onSelectPages() }
            format("翻页动画 · MP4", detail: "让手帐自动翻阅，保存为一段回忆视频", icon: "film") { onSelectVideo() }
                .disabled(book.contentPages.isEmpty)
            format("整本 PDF", detail: "按完整目录导出，便于阅读与存档", icon: "doc.richtext") { onSelectPDF() }
            Divider().padding(.vertical, 4)
            format("装订成册 · 寄到家", detail: "把完成的手帐印成一本，留住值得珍藏的回忆", icon: "shippingbox") { onSelectPrint() }
        }
    }
    private func format(_ title: String, detail: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.title2).frame(width: 48, height: 56).background(ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption)
            }.padding(16).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain)
    }
}
