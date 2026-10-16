import SwiftUI

struct DiaryBookExportSheet: View {
    let book: DiaryBook
    let store: DiaryDocumentStore
    @Environment(\.dismiss) private var dismiss
    enum Route: Hashable {
        case singlePages, spreads, result

        var title: String {
            switch self {
            case .singlePages: "选择页面"
            case .spreads: "跨页拼图"
            case .result: "导出结果"
            }
        }
    }

    @State private var path: [Route] = []
    @State private var selected: Set<UUID> = []
    @State private var spreadCount = 1
    @State private var task: Task<Void, Never>?
    @State private var busy = false
    @State private var saving = false
    @State private var progress = 0
    @State private var total = 1
    @State private var result: DiaryBookImageExporter.Result?
    @State private var saved = false
    @State private var pdf: DiaryBookPDFExport?
    @State private var pdfDirectory: URL?
    @State private var message: String?
    private let ink = Color(red: 0.23, green: 0.36, blue: 0.31)

    var body: some View {
        NavigationStack(path: $path) {
            page(title: "选择导出格式") {
                DiaryExportFormatPage(book: book,
                    onSelectSpreads: { path.append(.spreads) },
                    onSelectPages: { path.append(.singlePages) },
                    onSelectPDF: startPDF)
            }
            .navigationDestination(for: Route.self) { route in
                page(title: route.title) {
                    switch route {
                    case .singlePages:
                        DiaryExportSinglePagePicker(book: book, store: store, selected: $selected)
                    case .spreads:
                        DiaryExportSpreadPage(book: book, store: store, spreadCount: $spreadCount)
                    case .result:
                        if let result {
                            DiaryExportResultPage(result: result, saved: saved, saving: saving,
                                                  busy: busy, onRetry: { save(result) })
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if route != .result && !busy {
                        Button {
                            startImageExport(route == .singlePages ? .pages(selected) : .spreads(spreadCount))
                        } label: {
                            Text(route == .singlePages ? "导出 \(selected.count) 页并保存相册" : "生成拼图并保存相册")
                                .font(.headline).frame(maxWidth: .infinity).padding(16)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(route == .singlePages && selected.isEmpty)
                        .padding().background(.regularMaterial)
                    }
                }
            }
        }
        .tint(ink)
        .sheet(item: $pdf, onDismiss: {
            if let pdfDirectory { try? FileManager.default.removeItem(at: pdfDirectory) }
            pdfDirectory = nil
        }) { DiaryBookPDFPreview(export: $0) }
        .alert("导出提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("知道了") { message = nil }
        } message: { Text(message ?? "") }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(busy)
        .onDisappear {
            task?.cancel()
            if let result { try? FileManager.default.removeItem(at: result.directory) }
            if let pdfDirectory { try? FileManager.default.removeItem(at: pdfDirectory) }
        }
    }

    // Only the sheet owns task/file lifetimes; pushing and popping pages keeps
    // selections and the completed export available until the next export.
    private func page<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content().frame(maxWidth: .infinity, alignment: .leading).padding(24)
                .disabled(busy && !saving)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(busy)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { dismiss() }.disabled(busy)
            }
        }
        .overlay {
            if busy && !saving {
                ZStack {
                    Color(uiColor: .systemGroupedBackground).opacity(0.96)
                    VStack(spacing: 20) {
                        ProgressView(value: Double(progress), total: Double(max(1, total)))
                        Text("正在整理旅途记忆 · \(progress)/\(total)")
                        Button("取消导出") { task?.cancel() }
                    }.padding(32)
                }
            }
        }
    }

    private func startImageExport(_ mode: DiaryBookImageExporter.Mode) {
        guard !busy else { return }
        if let result { try? FileManager.default.removeItem(at: result.directory) }
        result = nil; saved = false; progress = 0; total = 1
        busy = true
        task = Task { @MainActor in
            do {
                let output = try await DiaryBookImageExporter.export(book: book, store: store, mode: mode) { progress = $0; total = $1 }
                result = output
                saving = true
                path.append(.result)
                try await DiaryBookImageExporter.saveToPhotos(output.urls)
                saved = true
            } catch is CancellationError { }
            catch { message = error.localizedDescription }
            busy = false; saving = false
        }
    }
    private func save(_ result: DiaryBookImageExporter.Result) {
        busy = true; saving = true
        task = Task { @MainActor in
            defer { busy = false; saving = false }
            do { try await DiaryBookImageExporter.saveToPhotos(result.urls); saved = true }
            catch { message = error.localizedDescription }
        }
    }
    private func startPDF() {
        guard !busy else { return }
        progress = 0; total = 1
        busy = true
        task = Task { @MainActor in
            defer { busy = false }
            do {
                let output = try await DiaryBookPDFExporter.export(book: book, store: store) { progress = $0; total = $1 }
                pdfDirectory = output.url.deletingLastPathComponent()
                pdf = output
            } catch is CancellationError { }
            catch { message = error.localizedDescription }
        }
    }
}
