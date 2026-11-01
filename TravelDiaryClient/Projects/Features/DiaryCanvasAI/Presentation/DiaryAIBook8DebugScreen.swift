#if DEBUG
import SwiftUI

/// Opt-in integration entry. Never starts paid AI requests automatically.
struct DiaryAIBook8DebugScreen: View {
    @State private var session: DiaryEditorSession?
    @State private var error: String?
    var body: some View {
        Group {
            if let session { DiaryEditorScreen(session: session) }
            else if let error { ContentUnavailableView("测试数据加载失败", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else { ProgressView("正在导入旅行随记 8…") }
        }.task {
            guard session == nil, error == nil else { return }
            do {
                let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DiaryAIRealDataDebug")
                let owner = "book8-debug"
                let importer = DiaryDocumentStore(ownerID: owner, baseDirectory: root)
                let book = try await importer.debugImportBook(from: URL(fileURLWithPath: "/tmp/traveldiary-book8-fixture.zip"))
                let store = DiaryDocumentStore(ownerID: owner, baseDirectory: root, bookID: book.id)
                guard let page = book.pages.first(where: { $0.id.uuidString == "E7377B9C-4F4B-4943-B1F4-460568CB6748" }) else { throw DiaryAIError.invalid("找不到对应测试页") }
                let source = try await store.load(page.id)
                session = DiaryEditorSession(document: source.document, images: source.images, store: store)
            } catch { self.error = error.localizedDescription }
        }
    }
}
#endif
