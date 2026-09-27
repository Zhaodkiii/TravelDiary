import Foundation
import CryptoKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
struct MarkdownCachedRemoteImage {
    let sourceURL: URL
    let image: UIImage
    let fileURL: URL
    let displayName: String
    let mimeType: String?
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

    private let memoryCache = NSCache<NSURL, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        cacheDirectory = caches.appendingPathComponent("MarkdownRemoteImages", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func image(for url: URL) async throws -> MarkdownCachedRemoteImage {
        if let image = memoryCache.object(forKey: url as NSURL),
           let fileURL = existingFileURL(for: url) {
            return MarkdownCachedRemoteImage(
                sourceURL: url,
                image: image,
                fileURL: fileURL,
                displayName: displayName(for: url, fileURL: fileURL),
                mimeType: mimeType(for: fileURL.pathExtension)
            )
        }

        if let fileURL = existingFileURL(for: url),
           let image = UIImage(contentsOfFile: fileURL.path) {
            memoryCache.setObject(image, forKey: url as NSURL)
            return MarkdownCachedRemoteImage(
                sourceURL: url,
                image: image,
                fileURL: fileURL,
                displayName: displayName(for: url, fileURL: fileURL),
                mimeType: mimeType(for: fileURL.pathExtension)
            )
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let image = UIImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }

        let mimeType = (response as? HTTPURLResponse)?.mimeType
        let fileURL = cacheFileURL(for: url, mimeType: mimeType)
        try data.write(to: fileURL, options: [.atomic])
        memoryCache.setObject(image, forKey: url as NSURL)

        return MarkdownCachedRemoteImage(
            sourceURL: url,
            image: image,
            fileURL: fileURL,
            displayName: displayName(for: url, fileURL: fileURL),
            mimeType: mimeType ?? self.mimeType(for: fileURL.pathExtension)
        )
    }

    private func existingFileURL(for url: URL) -> URL? {
        let key = cacheKey(for: url)
        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }
        return files.first { $0.deletingPathExtension().lastPathComponent == key }
    }

    private func cacheFileURL(for url: URL, mimeType: String?) -> URL {
        cacheDirectory
            .appendingPathComponent(cacheKey(for: url))
            .appendingPathExtension(fileExtension(for: url, mimeType: mimeType))
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
