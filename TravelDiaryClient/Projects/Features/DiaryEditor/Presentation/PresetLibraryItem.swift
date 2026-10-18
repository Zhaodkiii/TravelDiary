import Foundation
import Combine

/// 每本一张卡片；打开详情后保持该版本，避免在线刷新改变导入对象。
nonisolated struct PresetLibraryItem: Identifiable, Sendable {
    let id: String
    let local: DiaryPresetPackage?
    let remote: RemotePresetBook?
    var title: String { remote?.title ?? local?.manifest.title ?? "" }
    var series: String { remote?.series ?? local?.manifest.seriesID ?? "" }
    var version: Int { remote?.version ?? local?.manifest.packageVersion ?? 0 }
    var styles: [String] { remote?.style_tags ?? [] }
    var usages: [String] { remote?.usage_tags ?? [] }
    var tags: [String] { Array((styles + usages + (local?.manifest.tags ?? [])).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.prefix(2)) }
    var pageLabel: String {
        if let local {
            return "\(local.manifest.pages.filter { $0.id != local.manifest.shellPageID }.count) 页"
        }
        if let count = remote?.content_page_count { return "\(count) 页" }
        return "\(remote?.page_count ?? 0) 个资源页"
    }
    static func merge(local: [DiaryPresetPackage], remote: [RemotePresetBook], preferLocal: Bool = false) -> [Self] {
        var localByID: [String: DiaryPresetPackage] = [:]
        for package in local {
            if (localByID[package.id]?.manifest.packageVersion ?? -1) < package.manifest.packageVersion {
                localByID[package.id] = package
            }
        }
        var items: [Self] = [], used = Set<String>()
        for book in remote where used.insert(book.id).inserted {
            if preferLocal, let package = localByID[book.id] {
                items.append(Self(id: book.id, local: package, remote: nil))
                continue
            }
            let package = localByID[book.id].flatMap { $0.manifest.packageVersion == book.version ? $0 : nil }
            items.append(Self(id: book.id, local: package, remote: book))
        }
        for package in local where used.insert(package.id).inserted {
            items.append(Self(id: package.id, local: localByID[package.id], remote: nil))
        }
        return items
    }
    func matches(search: String, series: String, styles: Set<String>, usages: Set<String>) -> Bool {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return (query.isEmpty || title.localizedCaseInsensitiveContains(query))
            && (series.isEmpty || self.series == series)
            && (styles.isEmpty || !styles.isDisjoint(with: self.styles))
            && (usages.isEmpty || !usages.isDisjoint(with: self.usages))
    }
}

/// 系列顺序来自目录；过滤后为空的系列不占位，系列内保留服务端模板顺序。
nonisolated struct PresetLibrarySection: Identifiable, Sendable {
    let id: String
    let title: String
    let items: [PresetLibraryItem]

    static func scoped(_ items: [PresetLibraryItem], seriesID: String?) -> [PresetLibraryItem] {
        guard let seriesID else { return items }
        return items.filter { $0.series == seriesID }
    }

    static func group(_ items: [PresetLibraryItem], series: [RemotePresetCatalog.Series]) -> [Self] {
        let grouped = Dictionary(grouping: items, by: \.series)
        var seen = Set<String>(), result: [Self] = []
        for entry in series where seen.insert(entry.slug).inserted {
            if let books = grouped[entry.slug], !books.isEmpty {
                result.append(Self(id: entry.slug, title: entry.title, items: books))
            }
        }
        for item in items where seen.insert(item.series).inserted {
            result.append(Self(id: item.series, title: "更多模板", items: grouped[item.series] ?? []))
        }
        return result
    }
}

/// Resolve once per navigation presentation. Download/cache updates must not
/// replace the reader that owns an active import sheet.
@MainActor
final class PresetReaderPresentation: ObservableObject {
    enum Source {
        case local(DiaryPresetPackage)
        case remote(RemotePresetBook)
    }
    let source: Source?

    init(item: PresetLibraryItem, cachedPackage: DiaryPresetPackage?) {
        if let local = item.local ?? cachedPackage {
            source = .local(local)
        } else if let remote = item.remote {
            source = .remote(remote)
        } else {
            source = nil
        }
    }
}

/// 目录只是浏览提示；过期 URL 失败时由图片状态处理，不将它作为素材身份。
nonisolated enum PresetLibraryCatalogCache {
    private static func url(ownerID: String) -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let key = Data(ownerID.utf8).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("DiaryCatalog-\(key).json")
    }
    static func read(ownerID: String) -> RemotePresetCatalog? {
        guard let data = try? Data(contentsOf: url(ownerID: ownerID)) else { return nil }
        return try? JSONDecoder().decode(RemotePresetCatalog.self, from: data)
    }
    static func save(_ catalog: RemotePresetCatalog, ownerID: String) {
        guard let data = try? JSONEncoder().encode(catalog) else { return }
        try? data.write(to: url(ownerID: ownerID), options: .atomic)
    }
}
