import SwiftUI
import ImageIO
import CryptoKit

nonisolated struct PreviewImageRequest: Sendable {
    let key: ResourceCacheKey
    var url: URL?
    var localURL: URL? = nil
    var resolveLocalURL: (@Sendable () async -> URL?)? = nil
    var maxPixelSize: Int = 1024
    var sha256: String? = nil
    var refreshURL: (@Sendable () async throws -> URL?)? = nil
}

/// Shared decoded-image cache and request coalescing. Disk IO and decoding run off the UI thread.
@MainActor
final class PreviewImagePipeline {
    static let shared = PreviewImagePipeline()
    private let memory = NSCache<NSString, UIImage>()
    private var pending: [String: Task<UIImage, Error>] = [:]
    private var dataRequests: [String: Task<Data, Error>] = [:]
    private var aliases: [String: PreviewImageRequest] = [:]
    private nonisolated(unsafe) var memoryWarning: NSObjectProtocol?
    private nonisolated(unsafe) var backgroundObserver: NSObjectProtocol?
    private(set) var owner: String = "signed-out"
    private(set) var memoryHits = 0
    private(set) var diskHits = 0
    private(set) var localHits = 0
    private(set) var networkBytes: Int64 = 0
    private let cache: ResourceCache
    private let session: URLSession

    init(cache: ResourceCache = .shared, session: URLSession? = nil) {
        self.cache = cache
        if let session { self.session = session }
        else { self.session = ResourceDownloadSession.shared }
        memory.totalCostLimit = 64 * 1024 * 1024
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { [cache] _ in
                Task.detached(priority: .utility) { cache.flushAccesses(); cache.maintain() }
            }
        memoryWarning = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.memory.removeAllObjects() }
            }
    }
    deinit {
        if let memoryWarning { NotificationCenter.default.removeObserver(memoryWarning) }
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
    }
    func activate(owner: String?) {
        let value = owner ?? "signed-out"
        guard self.owner != value else { return }
        cache.invalidateSession(scope: StoragePaths.scopeKey(self.owner))
        self.owner = value; memory.removeAllObjects(); aliases.removeAll()
        for task in pending.values { task.cancel() }; pending.removeAll()
        for task in dataRequests.values { task.cancel() }; dataRequests.removeAll()
    }
    func clearMemory() { memory.removeAllObjects() }
    func decoded(_ data: Data, request: PreviewImageRequest) async throws -> UIImage {
        if let image = cached(request) { return image }
        let id = memoryKey(request)
        let image = try await Task.detached { try Self.decode(data, pixels: request.maxPixelSize) }.value
        memory.setObject(image, forKey: id as NSString, cost: image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0)
        return image
    }
    func alias(_ url: String, request: PreviewImageRequest) {
        if aliases.count > 5000 { aliases.removeAll(keepingCapacity: true) }
        aliases[url] = request
    }
    func request(url: URL?, maxPixelSize: Int = 1024) -> PreviewImageRequest {
        let identity = url?.absoluteString ?? "missing"
        if var request = aliases[identity], request.key.scope == StoragePaths.scopeKey(owner) {
            request.maxPixelSize = maxPixelSize; return request
        }
        let key = ResourceCacheKey.account(owner, category: "images", identity: identity)
        return PreviewImageRequest(key: key, url: url, maxPixelSize: maxPixelSize)
    }
    private func memoryKey(_ request: PreviewImageRequest) -> String {
        request.key.id + ":\(request.maxPixelSize):" + cache.generation(for: request.key)
    }
    func cached(_ request: PreviewImageRequest) -> UIImage? { memory.object(forKey: memoryKey(request) as NSString) }
    func load(_ request: PreviewImageRequest) async throws -> UIImage {
        if let image = cached(request) {
            memoryHits += 1
            Task.detached { self.cache.touch(request.key) }
            return image
        }
        let id = memoryKey(request)
        let started = cache.generation(for: request.key)
        if let task = pending[id] {
            let image = try await task.value
            guard cache.generation(for: request.key) == started else { throw CancellationError() }
            return image
        }
        let task = Task<UIImage, Error> { [self] in
            let resolvedLocal = await request.resolveLocalURL?()
            if let url = request.localURL ?? resolvedLocal ?? (request.url?.isFileURL == true ? request.url : nil),
               let image = try? await Task.detached(operation: {
                   let lease = StorageActivity.shared.acquire(url); defer { withExtendedLifetime(lease) {} }
                   let data = try Data(contentsOf: url)
                   guard Self.valid(data, sha256: request.sha256) else { throw URLError(.badServerResponse) }
                   return try Self.decode(data, pixels: request.maxPixelSize)
               }).value {
                localHits += 1
                Task.detached { self.cache.touch(url: url) }
                return image
            }
            let data = try await bytes(request, generation: started)
            guard Self.valid(data, sha256: request.sha256) else { throw URLError(.badServerResponse) }
            do { return try await Task.detached { try Self.decode(data, pixels: request.maxPixelSize) }.value }
            catch { cache.remove(id: request.key.id); throw error }
        }
        pending[id] = task
        defer { pending[id] = nil }
        let image = try await task.value
        guard cache.generation(for: request.key) == started else { throw CancellationError() }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        memory.setObject(image, forKey: id as NSString, cost: cost)
        return image
    }
    /// Byte requests are keyed without the decode size: a 640 px card and a 2048 px reader
    /// still share one download, while keeping separate bounded decoded representations.
    private func bytes(_ request: PreviewImageRequest, generation: String) async throws -> Data {
        let id = request.key.id + ":" + generation
        if let pending = dataRequests[id] { return try await pending.value }
        let task = Task<Data, Error> { [self] in
            if let data = await Task.detached(operation: { self.cache.data(for: request.key) }).value {
                let valid = await Task.detached { Self.valid(data, sha256: request.sha256) && (try? Self.decode(data, pixels: 32)) != nil }.value
                if valid { diskHits += 1; return data }
                cache.remove(id: request.key.id)
            }
            guard var url = request.url, !url.isFileURL else { throw URLError(.fileDoesNotExist) }
            var result = try await session.data(from: url)
            if let response = result.1 as? HTTPURLResponse, [401, 403].contains(response.statusCode), let refresh = request.refreshURL {
                try Task.checkCancellation()
                guard let refreshed = try await refresh() else { throw URLError(.badURL) }
                url = refreshed; result = try await session.data(from: url)
            }
            guard let response = result.1 as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                  result.0.count <= 32 * 1024 * 1024, Self.valid(result.0, sha256: request.sha256) else { throw URLError(.badServerResponse) }
            let data = result.0
            _ = try await Task.detached { try Self.decode(data, pixels: 32) }.value
            try Task.checkCancellation()
            networkBytes += Int64(data.count)
            await Task.detached { self.cache.store(data, for: request.key, expectedGeneration: generation) }.value
            return data
        }
        dataRequests[id] = task
        defer { dataRequests[id] = nil }
        return try await task.value
    }
    nonisolated private static func valid(_ data: Data, sha256: String?) -> Bool {
        guard let sha256, !sha256.isEmpty else { return true }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == sha256.lowercased()
    }
    nonisolated static func decode(_ data: Data, pixels: Int) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, pixels)
              ] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
        return UIImage(cgImage: cg)
    }
}

struct CachedPreviewImage: View {
    let request: PreviewImageRequest
    var onImageSize: ((CGSize) -> Void)? = nil
    var onRetry: (() async -> Void)? = nil
    @State private var image: UIImage?
    @State private var displayedKey: String
    @State private var failed = false
    @State private var retry = 0

    init(request: PreviewImageRequest, onImageSize: ((CGSize) -> Void)? = nil, onRetry: (() async -> Void)? = nil) {
        self.request = request; self.onImageSize = onImageSize; self.onRetry = onRetry
        _image = State(initialValue: PreviewImagePipeline.shared.cached(request))
        _displayedKey = State(initialValue: request.key.id)
    }
    var body: some View {
        Group {
            if displayedKey == request.key.id, let image { Image(uiImage: image).resizable().scaledToFit() }
            else if failed {
                Button { Task { await onRetry?(); retry += 1 } } label: { Image(systemName: "arrow.clockwise").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("重试预览")
            } else { ProgressView().controlSize(.small) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: request.key.id + ":\(retry)") {
                if displayedKey != request.key.id { image = nil; displayedKey = request.key.id }
                failed = false
                do {
                    let loaded = try await PreviewImagePipeline.shared.load(request)
                    try Task.checkCancellation()
                    image = loaded; onImageSize?(loaded.size)
                } catch is CancellationError { }
                catch { if !Task.isCancelled { failed = true } }
            }
    }
}
