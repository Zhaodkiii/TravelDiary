import SwiftUI
import PDFKit

struct DiaryBookPDFPreview: View {
    let export: DiaryBookPDFExport
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if export.usedFallbackFonts {
                    Text("部分字体不可用，PDF 已使用替代字体。").font(.caption)
                        .foregroundStyle(.secondary).padding(8)
                }
                DiaryPDFView(url: export.url)
            }
            .navigationTitle("PDF · \(export.pageCount) 页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: export.url) { Label("分享或存储", systemImage: "square.and.arrow.up") }
                }
            }
        }
    }
}

private struct DiaryPDFView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        view.autoScales = true
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) { }
}
