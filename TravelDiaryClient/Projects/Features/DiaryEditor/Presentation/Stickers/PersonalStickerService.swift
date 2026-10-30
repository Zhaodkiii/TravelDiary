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
        return try JSONDecoder().decode(T.self, from: response.data)
    }
    static func list(offset: Int = 0) async throws -> PersonalStickerPage {
        let catalog = MaterialCatalogRepository.shared
        guard let engine = catalog.engine else { throw URLError(.userAuthenticationRequired) }
        let owner = catalog.owner
        let response = try await engine.sendRaw(SupportNetworkRequest(method: .get,
            path: "/api/v1/materials/personal/stickers/", queryItems: [.init(name: "offset", value: String(offset))],
            strategy: NetworkStrategy(requiresAuth: true)))
        guard owner == catalog.owner else { throw CancellationError() }
        return try JSONDecoder().decode(PersonalStickerPage.self, from: response.data)
    }
    static func delete(_ sticker: PersonalSticker) async throws {
        guard let engine = MaterialCatalogRepository.shared.engine else { throw URLError(.userAuthenticationRequired) }
        _ = try await engine.sendRaw(SupportNetworkRequest(method: .delete,
            path: "/api/v1/materials/personal/stickers/\(sticker.id)/", strategy: NetworkStrategy(requiresAuth: true)))
    }
    static func image(_ sticker: PersonalSticker) async throws -> Data {
        try validate(sticker.url)
        let (data, response) = try await URLSession.shared.data(from: sticker.url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= 10 * 1024 * 1024 else { throw URLError(.badServerResponse) }
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
