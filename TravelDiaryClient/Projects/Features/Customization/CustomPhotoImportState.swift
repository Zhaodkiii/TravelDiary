import Foundation
import Combine

/// Keeps photo import feedback independent of the periodically refreshed request detail.
@MainActor
final class CustomPhotoImportState: ObservableObject {
    @Published private(set) var isImporting = false
    @Published private(set) var message: String?
    @Published private(set) var error: String?
    @Published var showError = false

    func report(_ failure: Error, stage: String) {
        error = failure.localizedDescription
        showError = true
        let diagnostic = failure as NSError
        ConsoleLogger().warning("定制照片失败 stage=\(stage) domain=\(diagnostic.domain) code=\(diagnostic.code)", module: .file)
    }

    @discardableResult
    func add<Item>(_ items: [Item], load: @MainActor (Item) async throws -> Data?,
                   enqueue: @MainActor (Data) async throws -> Void) async -> Int {
        guard !items.isEmpty, !isImporting else { return 0 }
        isImporting = true
        error = nil
        showError = false
        defer { isImporting = false }
        ConsoleLogger().info("定制照片开始读取 count=\(items.count)", module: .file)
        var added = 0
        var failures = 0
        var firstError: String?
        for (index, item) in items.enumerated() {
            var stage = "load"
            do {
                try Task.checkCancellation()
                message = "正在读取照片 \(index + 1)/\(items.count)…"
                guard let bytes = try await load(item) else {
                    throw CustomFailure("无法读取所选照片，请确认照片已下载到本机后重试")
                }
                try Task.checkCancellation()
                stage = "enqueue"
                message = "正在处理照片 \(index + 1)/\(items.count)…"
                try await enqueue(bytes)
                added += 1
            } catch {
                if Task.isCancelled { break }
                failures += 1
                if firstError == nil { firstError = "第 \(index + 1) 张照片：\(error.localizedDescription)" }
                let diagnostic = error as NSError
                ConsoleLogger().warning("定制照片失败 stage=\(stage) index=\(index + 1) domain=\(diagnostic.domain) code=\(diagnostic.code)", module: .file)
            }
        }
        message = added > 0 ? "已添加 \(added) 张照片到上传队列，可在下方查看上传进度。" : nil
        if let firstError {
            error = "\(failures) 张照片添加失败。\(firstError)"
            showError = true
        }
        ConsoleLogger().info("定制照片读取结束 added=\(added) failed=\(failures)", module: .file)
        return added
    }
}
