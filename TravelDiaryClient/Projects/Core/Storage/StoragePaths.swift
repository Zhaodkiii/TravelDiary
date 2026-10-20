import Foundation
import CryptoKit

/// Single directory layout for the development build. No legacy lookup or migration.
nonisolated struct StoragePaths: Sendable {
    let support: URL
    let caches: URL
    let temporary: URL

    init(support: URL, caches: URL, temporary: URL) {
        self.support = support.resolvingSymlinksInPath()
        self.caches = caches.resolvingSymlinksInPath()
        self.temporary = temporary.resolvingSymlinksInPath()
    }

    static let system = StoragePaths(
        support: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
        caches: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0],
        temporary: FileManager.default.temporaryDirectory)

    static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func scopeKey(_ owner: String) -> String { digest("account:" + owner) }
    var persistentRoot: URL { support.appendingPathComponent("TravelDiary", isDirectory: true) }
    var cacheRoot: URL { caches.appendingPathComponent("TravelDiary", isDirectory: true) }
    var temporaryRoot: URL { temporary.appendingPathComponent("TravelDiary", isDirectory: true) }
    var accounts: URL { persistentRoot.appendingPathComponent("Accounts", isDirectory: true) }
    var cacheAccounts: URL { cacheRoot.appendingPathComponent("Accounts", isDirectory: true) }
    func account(_ owner: String) -> URL { accounts.appendingPathComponent(Self.scopeKey(owner), isDirectory: true) }
    func cacheAccount(_ owner: String) -> URL { cacheAccounts.appendingPathComponent(Self.scopeKey(owner), isDirectory: true) }
    func diaryOwner(_ owner: String) -> URL { account(owner).appendingPathComponent("Diaries", isDirectory: true) }
    func books(_ owner: String) -> URL { diaryOwner(owner).appendingPathComponent("books", isDirectory: true) }
    func trash(_ owner: String) -> URL { account(owner).appendingPathComponent("Trash/books", isDirectory: true) }
    func previews(_ owner: String) -> URL { cacheAccount(owner).appendingPathComponent("Previews", isDirectory: true) }
    var downloads: URL { persistentRoot.appendingPathComponent("Shared/Downloads", isDirectory: true) }
    func printOrders(_ owner: String) -> URL { account(owner).appendingPathComponent("PrintOrders", isDirectory: true) }
    var fileCache: URL { cacheAccounts }
    var camera: URL { temporaryRoot.appendingPathComponent("Camera", isDirectory: true) }
    var workspaces: URL { temporaryRoot.appendingPathComponent("Tasks", isDirectory: true) }
    var control: URL { persistentRoot.appendingPathComponent("StorageControl", isDirectory: true) }
    func cache(_ name: String) -> URL { cacheRoot.appendingPathComponent("Shared", isDirectory: true).appendingPathComponent(name, isDirectory: true) }
    func persistent(_ name: String) -> URL { persistentRoot.appendingPathComponent("Shared", isDirectory: true).appendingPathComponent(name, isDirectory: true) }
    func catalog(_ owner: String) -> URL { cacheAccount(owner).appendingPathComponent("Catalog/catalog.json") }
    func business(_ name: String, owner: String) -> URL { account(owner).appendingPathComponent("BusinessData", isDirectory: true).appendingPathComponent(name, isDirectory: true) }

    /// Only use for generated identifiers or validated relative locators, never a user title.
    static func resolve(_ relative: String, within root: URL) throws -> URL {
        guard !relative.isEmpty, !relative.hasPrefix("/"),
              !relative.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty })
        else { throw StorageFailure.unsafePath }
        let result = root.appendingPathComponent(relative).standardizedFileURL
        guard contains(result, in: root), contains(result.resolvingSymlinksInPath(), in: root.standardizedFileURL) else {
            throw StorageFailure.unsafePath
        }
        return result
    }
    static func contains(_ url: URL, in root: URL) -> Bool {
        let path = url.standardizedFileURL.path, base = root.standardizedFileURL.path
        return path == base || path.hasPrefix(base + "/")
    }
}

nonisolated enum StorageFailure: LocalizedError {
    case unsafePath, accountChanged, inUse, stalePlan, insufficientSpace, conflict
    var errorDescription: String? {
        switch self {
        case .unsafePath: "资源路径无效，已保留原文件。"
        case .accountChanged: "账号已变化，请重新查看存储空间。"
        case .inUse: "资料正在编辑、导出或上传，请结束相关任务后重试。"
        case .stalePlan: "资源状态已变化，请刷新后重试。"
        case .insufficientSpace: "设备可用空间不足，请前往设置中的存储空间清理后重试。"
        case .conflict: "目标位置已存在资料，已保留双方内容，请检查后重试。"
        }
    }
}
