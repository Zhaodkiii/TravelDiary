import SwiftUI

/// 专用路由避免与页面、素材等其他 UUID 跳转混淆。
struct DiaryBookRoute: Hashable {
    let bookID: UUID
}

/// 根导航栈根据 ID 读取最新目录，不依赖书架子页面的加载状态。
struct DiaryBookDestination: View {
    let ownerID: String
    let bookID: UUID
    @State private var book: DiaryBook?
    @State private var error: String?
    @State private var retry = 0
    @State private var showingList = false

    var body: some View {
        Group {
            if let book {
                if book.pages.isEmpty {
                    DiaryBookScreen(ownerID: ownerID, book: book)
                } else {
                    DiaryPhysicalBookScreen(
                        book: book,
                        store: DiaryDocumentStore(ownerID: ownerID, bookID: bookID),
                        onShowList: { showingList = true }
                    )
                }
            } else if let error {
                ContentUnavailableView {
                    Label("手帐暂不可用", systemImage: "book.closed")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") { retry += 1 }
                }
            } else {
                ProgressView("正在打开手帐…")
            }
        }
        .navigationDestination(isPresented: $showingList) {
            DiaryBookPageListDestination(ownerID: ownerID, bookID: bookID)
        }
        .task(id: retry) {
            error = nil
            do {
                let loaded = try await DiaryDocumentStore(ownerID: ownerID, bookID: bookID).loadBook()
                try Task.checkCancellation()
                book = loaded
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}

/// A pushed page loads its own current catalog and uses the enclosing native stack.
private struct DiaryBookPageListDestination: View {
    let ownerID: String
    let bookID: UUID
    @State private var book: DiaryBook?
    @State private var message: String?
    @State private var retry = 0

    var body: some View {
        Group {
            if let book {
                DiaryBookScreen(ownerID: ownerID, book: book)
            } else if let message {
                ContentUnavailableView {
                    Label("无法打开页面列表", systemImage: "list.bullet")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") { retry += 1 }
                }
            } else {
                ProgressView("正在打开页面列表…")
            }
        }
        .navigationTitle("页面列表")
        .task(id: retry) {
            message = nil
            do {
                let loaded = try await DiaryDocumentStore(ownerID: ownerID, bookID: bookID).loadBook()
                try Task.checkCancellation()
                book = loaded
            } catch is CancellationError { }
            catch { message = error.localizedDescription }
        }
    }
}
