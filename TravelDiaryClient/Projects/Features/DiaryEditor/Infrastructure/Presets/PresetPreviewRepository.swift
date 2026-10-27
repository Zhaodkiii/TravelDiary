import Foundation

/// Persist page identities separately from expiring URLs so warm/offline browsing needs no API call.
@MainActor
final class PresetPreviewRepository {
    static let shared = PresetPreviewRepository()
    private var values: [String: RemotePresetBrowse] = [:]
    private func key(_ book: RemotePresetBook, ownerID: String) -> ResourceCacheKey {
        .account(ownerID, category: "preset-index", identity: "\(book.id):\(book.version)")
    }
    func memoryCached(_ book: RemotePresetBook, ownerID: String) -> RemotePresetBrowse? { values[key(book, ownerID: ownerID).id] }
    func cached(_ book: RemotePresetBook, ownerID: String) async -> RemotePresetBrowse? {
        let key = key(book, ownerID: ownerID)
        if let value = values[key.id] { return value }
        guard let data = await Task.detached(operation: { ResourceCache.shared.data(for: key) }).value,
              let value = try? JSONDecoder().decode(RemotePresetBrowse.self, from: data) else { return nil }
        values[key.id] = value; registerAliases(value, book: book, ownerID: ownerID)
        return value
    }
    func remember(_ browse: RemotePresetBrowse, book: RemotePresetBook, ownerID: String) {
        let key = key(book, ownerID: ownerID)
        if values.count >= 128 { values.removeAll(keepingCapacity: true) }
        values[key.id] = browse
        registerAliases(browse, book: book, ownerID: ownerID)
        let generation = ResourceCache.shared.generation(for: key)
        Task.detached {
            if let data = try? JSONEncoder().encode(browse) { ResourceCache.shared.store(data, for: key, expectedGeneration: generation) }
        }
    }
    func reset() { values.removeAll() }
    func registerSearch(_ entries: [PresetSearchEntry], ownerID: String) {
        guard PreviewImagePipeline.shared.owner == ownerID else { return }
        for entry in entries {
            for (index, assets) in entry.previews.enumerated() {
                let id: String? = entry.entity_type == "book" ? nil : (entry.page_ids.indices.contains(index) ? entry.page_ids[index] : nil)
                for (kind, asset) in assets {
                    var image = request(book: entry.book, ownerID: ownerID, pageID: id, url: URL(string: asset.url), large: kind == "largePath")
                    if !asset.sha256.isEmpty { image.sha256 = asset.sha256 }
                    PreviewImagePipeline.shared.alias(asset.url, request: image)
                }
            }
        }
    }
    func pageKey(book: RemotePresetBook, ownerID: String, pageID: String?, large: Bool = false) -> ResourceCacheKey {
        .account(ownerID, category: "preset-images", identity: "\(book.id):\(book.version):\(pageID ?? "cover"):\(large ? "large" : "thumbnail")")
    }
    private func registerAliases(_ browse: RemotePresetBrowse, book: RemotePresetBook, ownerID: String) {
        guard PreviewImagePipeline.shared.owner == ownerID else { return }
        for page in browse.pages {
            let id: String? = page.id == browse.cover_page_id ? nil : page.id
            PreviewImagePipeline.shared.alias(page.thumbnail_url, request: request(book: book, ownerID: ownerID, pageID: id, url: URL(string: page.thumbnail_url)))
            PreviewImagePipeline.shared.alias(page.preview_url, request: request(book: book, ownerID: ownerID, pageID: page.id, url: URL(string: page.preview_url), large: true))
        }
        PreviewImagePipeline.shared.alias(book.cover_url, request: request(book: book, ownerID: ownerID, url: URL(string: book.cover_url)))
    }
    func request(book: RemotePresetBook, ownerID: String, pageID: String? = nil, url: URL?, large: Bool = false, pixels: Int = 640) -> PreviewImageRequest {
        PreviewImageRequest(key: pageKey(book: book, ownerID: ownerID, pageID: pageID, large: large), url: url,
            resolveLocalURL: {
                await PresetPreviewRepository.shared.localURL(book: book, ownerID: ownerID, pageID: pageID, large: large)
            }, maxPixelSize: pixels, refreshURL: {
                guard await PreviewImagePipeline.shared.owner == ownerID else { throw CancellationError() }
                let browse = try await PresetDownloadManager.shared.browse(book, ownerID: ownerID, forceRefresh: true)
                let id = pageID ?? browse.cover_page_id
                guard let page = browse.pages.first(where: { $0.id == id }) else { return nil }
                return URL(string: large ? page.preview_url : page.thumbnail_url)
            })
    }
    private func localURL(book: RemotePresetBook, ownerID: String, pageID: String?, large: Bool) async -> URL? {
        let manager = PresetDownloadManager.shared
        await manager.waitUntilRestored()
        // Never activate an old account from a late image task.
        guard PreviewImagePipeline.shared.owner == ownerID else { return nil }
        let packages = manager.previewPackages(book: book, ownerID: ownerID)
        return await Task.detached {
            for package in packages {
                let id = pageID ?? package.manifest.coverPageID
                guard let reference = package.manifest.pages.first(where: { $0.id == id }),
                      let page = try? package.read(PresetPage.self, reference.path),
                      let url = try? package.url(large ? page.preview.largePath : page.preview.thumbnailPath),
                      FileManager.default.fileExists(atPath: url.path) else { continue }
                return url
            }
            return nil
        }.value
    }
}
