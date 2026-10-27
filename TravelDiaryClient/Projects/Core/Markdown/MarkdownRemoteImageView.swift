import Foundation
import CryptoKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
nonisolated struct MarkdownCachedRemoteImage: Sendable {
    let sourceURL: URL
    let image: UIImage
    let fileURL: URL
    let displayName: String
    let mimeType: String?
    let storageLease: StorageActivity.Lease
}

struct MarkdownRemoteImageView: View {
    let url: URL
    let alt: String
    let maxHeight: CGFloat?
    let cornerRadius: CGFloat
    let style: MarkdownDocumentStyle
    let onPreview: (MarkdownCachedRemoteImage) async -> Void

    @State private var phase: Phase = .idle

    var body: some View {
        content
            .task(id: url) {
                await loadIfNeeded()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle, .loading:
            placeholder

        case .loaded(let cached):
            Image(uiImage: cached.image)
                .resizable()
                .scaledToFit()
                .ifLet(maxHeight) { view, height in
                    view.frame(maxHeight: height)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .onTapGesture {
                    Task {
                        await onPreview(cached)
                    }
                }

        case .failed:
            fallback
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if maxHeight == nil {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 96)
        } else {
            ProgressView()
                .controlSize(.mini)
        }
    }

    private var fallback: some View {
        Text(alt.isEmpty ? "Image" : alt)
            .font(.caption)
            .foregroundStyle(style.secondaryTextColor)
            .padding(maxHeight == nil ? 8 : 0)
            .background {
                if maxHeight == nil {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(style.tableBorderColor, lineWidth: 1)
                }
            }
    }

    private func loadIfNeeded() async {
        guard case .idle = phase else { return }
        phase = .loading

        do {
            phase = .loaded(try await MarkdownRemoteImageCache.shared.image(for: url))
        } catch {
            phase = .failed
        }
    }

    private enum Phase {
        case idle
        case loading
        case loaded(MarkdownCachedRemoteImage)
        case failed
    }
}

actor MarkdownRemoteImageCache {
    static let shared = MarkdownRemoteImageCache()

    private var pending: [String: Task<MarkdownCachedRemoteImage, Error>] = [:]
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    init() {
        cacheDirectory = StoragePaths.system.cache("MarkdownRemoteImages")
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func image(for url: URL) async throws -> MarkdownCachedRemoteImage {
        let owner = await PreviewImagePipeline.shared.owner
        let key = ResourceCacheKey.account(owner, category: "markdown-images", identity: url.absoluteString)
        if let task = pending[key.id] { return try await task.value }
        let task = Task { try await self.fetch(url, owner: owner, key: key) }
        pending[key.id] = task
        defer { pending[key.id] = nil }
        return try await task.value
    }

    private func fetch(_ url: URL, owner: String, key: ResourceCacheKey) async throws -> MarkdownCachedRemoteImage {
        let generation = ResourceCache.shared.generation(for: key)
        let directory = StoragePaths.system.cacheAccount(owner).appendingPathComponent("MarkdownRemoteImages")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var fileURL = files.first { $0.deletingPathExtension().lastPathComponent == cacheKey(for: url) }
        var data = fileURL.flatMap { try? Data(contentsOf: $0) }
        var type: String?
        if data == nil {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            let session = URLSession(configuration: configuration)
            defer { session.finishTasksAndInvalidate() }
            let result = try await session.data(for: request)
            guard let response = result.1 as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
            data = result.0; type = response.mimeType
            fileURL = directory.appendingPathComponent(cacheKey(for: url)).appendingPathExtension(fileExtension(for: url, mimeType: type))
        }
        guard let data, let fileURL else { throw URLError(.cannotDecodeContentData) }
        let request = PreviewImageRequest(key: key, url: url, maxPixelSize: 2048)
        let image = try await PreviewImagePipeline.shared.decoded(data, request: request)
        guard ResourceCache.shared.generation(for: key) == generation,
              await PreviewImagePipeline.shared.owner == owner else { throw CancellationError() }
        let lease = StorageActivity.shared.acquire(fileURL)
        if !fileManager.fileExists(atPath: fileURL.path) { try data.write(to: fileURL, options: .atomic) }
        ResourceCache.shared.register(fileURL, for: key)
        return MarkdownCachedRemoteImage(sourceURL: url, image: image, fileURL: fileURL,
            displayName: displayName(for: url, fileURL: fileURL), mimeType: type ?? mimeType(for: fileURL.pathExtension), storageLease: lease)
    }

    private func cacheKey(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func displayName(for url: URL, fileURL: URL) -> String {
        let originalName = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        if originalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return originalName
        }
        return fileURL.lastPathComponent
    }

    private func fileExtension(for url: URL, mimeType: String?) -> String {
        let sourceExtension = url.pathExtension.lowercased()
        if sourceExtension.isEmpty == false {
            return sourceExtension
        }

        switch mimeType?.lowercased() {
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/heic", "image/heif": return "heic"
        case "image/webp": return "webp"
        default: return "jpg"
        }
    }

    private func mimeType(for fileExtension: String) -> String? {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        case "heif": return "image/heif"
        case "webp": return "image/webp"
        default: return nil
        }
    }
}

private extension View {
    @ViewBuilder
    func ifLet<Value, Content: View>(
        _ value: Value?,
        transform: (Self, Value) -> Content
    ) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}
#endif
