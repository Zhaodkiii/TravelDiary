import Foundation

nonisolated struct PersonalSticker: Decodable, Identifiable {
    let id: String
    let imageObjectKey: String
    let createdAt: String
    let url: URL
}
nonisolated struct PersonalStickerPage: Decodable { let items: [PersonalSticker]; let next: Int? }
nonisolated struct PersonalStickerUpload: Decodable {
    let imageObjectKey: String
    let url: URL
    let headers: [String: String]
    let token: String
}

@MainActor
enum PersonalStickerService {
    static func request<T: Decodable>(_ path: String, body: [String: String]? = nil) async throws -> T {
        let catalog = MaterialCatalogRepository.shared
        guard let engine = catalog.engine else { throw URLError(.userAuthenticationRequired) }
        let owner = catalog.owner
        let request = SupportNetworkRequest(method: body == nil ? .get : .post,
            path: "/api/v1/materials/personal/" + path,
            body: body.map { .json(AnyEncodable($0)) } ?? .none,
            strategy: NetworkStrategy(requiresAuth: true))
        let response = try await engine.sendRaw(request)
        guard owner == catalog.owner else { throw CancellationError() }
        let result = try JSONDecoder().decode(T.self, from: response.data)
        if body != nil && path == "stickers/" { CatalogResponseCache.shared.invalidate(owner: owner, domain: "personal-stickers") }
        return result
    }
    static func list(offset: Int = 0, forceRefresh: Bool = false, onCached: ((PersonalStickerPage) -> Void)? = nil) async throws -> PersonalStickerPage {
        let catalog = MaterialCatalogRepository.shared
        guard let engine = catalog.engine else { throw URLError(.userAuthenticationRequired) }
        let owner = catalog.owner
        let data = try await CatalogResponseCache.shared.load(owner: owner, domain: "personal-stickers",
            path: engine.serviceBaseURL.absoluteString + "/materials/personal/stickers/?offset=\(offset)", forceRefresh: forceRefresh,
            onCached: { data in
                guard catalog.owner == owner, let page = try? JSONDecoder().decode(PersonalStickerPage.self, from: data) else { return }
                onCached?(page)
            }) {
                let response = try await engine.sendRaw(SupportNetworkRequest(method: .get,
                    path: "/api/v1/materials/personal/stickers/", queryItems: [.init(name: "offset", value: String(offset))],
                    strategy: NetworkStrategy(requiresAuth: true)))
                guard owner == catalog.owner else { throw CancellationError() }
                _ = try JSONDecoder().decode(PersonalStickerPage.self, from: response.data)
                return response.data
            }
        guard owner == catalog.owner else { throw CancellationError() }
        return try JSONDecoder().decode(PersonalStickerPage.self, from: data)
    }
    static func imageRequest(_ sticker: PersonalSticker) -> PreviewImageRequest {
        let owner = MaterialCatalogRepository.shared.owner
        return PreviewImageRequest(key: .account(owner, category: "personal-sticker-images",
            identity: sticker.id + ":" + sticker.imageObjectKey), url: sticker.url, maxPixelSize: 384,
            validateURL: { $0.scheme == "https" && $0.host?.hasSuffix(".aliyuncs.com") == true }, maximumBytes: 10 * 1024 * 1024,
            refreshURL: { try await refreshedURL(sticker, owner: owner) })
    }
    private static func refreshedURL(_ sticker: PersonalSticker, owner: String) async throws -> URL {
        var offset = 0
        var seen: Set<Int> = []
        while seen.insert(offset).inserted {
            try Task.checkCancellation()
            guard MaterialCatalogRepository.shared.owner == owner else { throw CancellationError() }
            let page = try await list(offset: offset, forceRefresh: true)
            if let current = page.items.first(where: { $0.id == sticker.id && $0.imageObjectKey == sticker.imageObjectKey }) { return current.url }
            guard let next = page.next else { break }
            offset = next
        }
        throw URLError(.fileDoesNotExist)
    }
    static func delete(_ sticker: PersonalSticker) async throws {
        let catalog = MaterialCatalogRepository.shared
        guard let engine = catalog.engine else { throw URLError(.userAuthenticationRequired) }
        let owner = catalog.owner
        _ = try await engine.sendRaw(SupportNetworkRequest(method: .delete,
            path: "/api/v1/materials/personal/stickers/\(sticker.id)/", strategy: NetworkStrategy(requiresAuth: true)))
        guard owner == catalog.owner else { throw CancellationError() }
        CatalogResponseCache.shared.invalidate(owner: owner, domain: "personal-stickers")
        ResourceCache.shared.clear(scope: StoragePaths.scopeKey(owner), category: "personal-sticker-images")
    }
    static func image(_ sticker: PersonalSticker) async throws -> Data {
        let request = imageRequest(sticker)
        let generation = ResourceCache.shared.generation(for: request.key)
        if let data = await Task.detached(operation: { ResourceCache.shared.data(for: request.key) }).value { return data }
        try validate(sticker.url)
        let start = ProcessInfo.processInfo.systemUptime
        var (data, response) = try await ResourceDownloadSession.shared.data(from: sticker.url)
        if let http = response as? HTTPURLResponse, [401, 403].contains(http.statusCode) {
            guard let url = try await request.refreshURL?() else { throw URLError(.badURL) }
            try validate(url)
            ResourceLoadMetrics.shared.record(request.key, "image.download.retry-response", bytes: data.count)
            (data, response) = try await ResourceDownloadSession.shared.data(from: url)
        }
        ResourceLoadMetrics.shared.record(request.key, "image.download", since: start, bytes: data.count)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= 10 * 1024 * 1024 else { throw URLError(.badServerResponse) }
        guard ResourceCache.shared.generation(for: request.key) == generation else { throw CancellationError() }
        _ = await Task.detached { [data] in ResourceCache.shared.store(data, for: request.key, expectedGeneration: generation) }.value
        return data
    }
    static func validate(_ url: URL) throws {
        guard url.scheme == "https", url.host?.hasSuffix(".aliyuncs.com") == true else { throw URLError(.badURL) }
    }
    static func upload(_ data: Data, plan: PersonalStickerUpload) async throws {
        try validate(plan.url)
        var request = URLRequest(url: plan.url); request.httpMethod = "PUT"; request.timeoutInterval = 60
        for (key, value) in plan.headers { request.setValue(value, forHTTPHeaderField: key) }
        let (_, response) = try await URLSession.shared.upload(for: request, from: data)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) || response.statusCode == 409 else { throw URLError(.cannotWriteToFile) }
    }
}
