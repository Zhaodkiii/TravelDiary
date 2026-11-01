#if DEBUG
import SwiftUI
import UniformTypeIdentifiers

struct DiaryDebugImport: ViewModifier {
    let ownerID: String
    var showsButton = true
    let completed: () async -> Void
    @State private var choosing = false
    @State private var importing = false
    @State private var message: String?
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if showsButton {
                        Button { choosing = true } label: {
                            Label("Debug 导入", systemImage: "square.and.arrow.down").labelStyle(.titleAndIcon)
                        }.disabled(importing)
                    }
                }
            }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.zip, .folder], allowsMultipleSelection: false) { result in
                switch result {
                case .failure(let error): message = error.localizedDescription
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importing = true
                    Task {
                        defer { importing = false }
                        do {
                            let book = try await DiaryDocumentStore(ownerID: ownerID).debugImportBook(from: url)
                            DiaryReadingSources.cache.removeAllObjects()
                            await completed()
                            message = "已导入「\(book.title)」。同 ID 手帐已替换为所选文件版本。"
                        } catch { message = "导入失败：\(error.localizedDescription)" }
                    }
                }
            }
            .overlay {
                if importing { ProgressView("正在校验并导入手帐…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) }
            }
            .disabled(importing)
            .alert("Debug 导入", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("确定") { message = nil }
            } message: { Text(message ?? "") }
    }
}
#endif
