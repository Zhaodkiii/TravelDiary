import Foundation
import CryptoKit

/// Only known rebuildable formats are adopted. Upload staging, downloads and unknown files stay out.
nonisolated enum LegacyCacheMigration {
    static func run(cache: ResourceCache) {
        let paths = cache.paths, fm = FileManager.default
        for (name, category) in [("MaterialThumbnails", "material-thumbnails"), ("MaterialImages", "material-images")] {
            let root = paths.cache(name)
            for url in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
                let hash = url.lastPathComponent
                guard hash.count == 64, hash.allSatisfy(\.isHexDigit),
                      let data = try? Data(contentsOf: url),
                      SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == hash else { continue }
                cache.register(url, for: ResourceCacheKey(scope: "shared", category: category, identity: hash))
            }
        }
        let accounts = (try? fm.contentsOfDirectory(at: paths.cacheAccounts, includingPropertiesForKeys: nil)) ?? []
        for root in accounts {
            let scope = root.lastPathComponent
            guard scope.count == 64, scope.allSatisfy(\.isHexDigit),
                  let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { continue }
            for case let url as URL in enumerator {
                guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { enumerator.skipDescendants(); continue }
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let relative = String(url.path.dropFirst(root.path.count + 1))
                if relative.hasPrefix("Catalog/"), url.pathExtension == "json" {
                    cache.register(url, for: ResourceCacheKey(scope: scope, category: "catalog", identity: relative))
                } else if relative.hasPrefix("MaterialCatalog/"), url.lastPathComponent.count == 64 {
                    cache.register(url, for: ResourceCacheKey(scope: scope, category: "material-catalog", identity: relative))
                } else if relative.hasPrefix("Previews/"), canRebuildPreview(url, scope: scope, paths: paths) {
                    cache.register(url, for: ResourceCacheKey(scope: scope, category: "diary-previews", identity: url.path))
                } else if relative.hasPrefix("MarkdownRemoteImages/"), url.deletingPathExtension().lastPathComponent.count == 64 {
                    cache.register(url, for: ResourceCacheKey(scope: scope, category: "markdown-images", identity: relative))
                }
            }
        }
        // These legacy public image files have no URL sidecar. Adopt for quota accounting without
        // inventing URL identities; newly visited images use the scoped provider.
        for url in (try? fm.contentsOfDirectory(at: paths.cache("MarkdownRemoteImages"), includingPropertiesForKeys: nil)) ?? []
            where url.deletingPathExtension().lastPathComponent.count == 64 {
            cache.register(url, for: ResourceCacheKey(scope: "shared", category: "markdown-images", identity: url.lastPathComponent))
        }
        if paths.cacheRoot == StoragePaths.system.cacheRoot {
            for name in ["NetworkResponses", "ETagResponses"] {
                let base = paths.cache(name)
                for url in (try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? [] where url.lastPathComponent.hasSuffix(".meta.json") {
                    let id = String(url.lastPathComponent.dropLast(".meta.json".count))
                    guard id.count == 64, id.allSatisfy(\.isHexDigit) else { continue }
                    _ = ResourceETagCache(baseDirectory: base).read(id)
                }
            }
        }
        cache.maintain()
    }

    static func canRebuildPreview(_ url: URL, scope: String, paths: StoragePaths) -> Bool {
        let root = paths.cacheAccounts.appendingPathComponent(scope).appendingPathComponent("Previews")
        guard StoragePaths.contains(url, in: root), url.pathExtension == "png" else { return false }
        let relative = String(url.path.dropFirst(root.path.count + 1)).split(separator: "/").map(String.init)
        guard relative.count == 4, let bookID = UUID(uuidString: relative[0]), let pageID = UUID(uuidString: relative[1]),
              UUID(uuidString: relative[2]) != nil else { return false }
        let bookRoot = paths.accounts.appendingPathComponent(scope).appendingPathComponent("Diaries/books").appendingPathComponent(bookID.uuidString)
        guard let data = try? Data(contentsOf: bookRoot.appendingPathComponent("book.json")),
              let book = try? JSONDecoder().decode(DiaryBook.self, from: data), book.id == bookID,
              book.pages.contains(where: { $0.id == pageID }) || book.trashedPages.contains(where: { $0.id == pageID }),
              let pageRoot = try? StoragePaths.resolve("pages/" + pageID.uuidString, within: bookRoot),
              let manifestURL = try? StoragePaths.resolve("revisions/" + relative[2] + "/manifest.json", within: pageRoot),
              let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              manifest["format"] as? String == "TravelDiary.SmartCanvas", manifest["documentID"] as? String == pageID.uuidString,
              let assets = manifest["assets"] as? [String: [String: Any]],
              let objects = manifest["objects"] as? [[String: Any]], !objects.isEmpty else { return false }
        for asset in assets.values {
            guard let path = asset["path"] as? String, let file = try? StoragePaths.resolve(path, within: bookRoot), FileManager.default.fileExists(atPath: file.path) else { return false }
        }
        for object in objects {
            for key in ["path", "drawingPath"] {
                guard let path = object[key] as? String, let file = try? StoragePaths.resolve(path, within: pageRoot), FileManager.default.fileExists(atPath: file.path) else { return false }
            }
        }
        return true
    }
}
