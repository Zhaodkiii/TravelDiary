import Foundation
import UIKit
import ImageIO

nonisolated enum DiaryEditorError: LocalizedError {
    case invalidImage, invalidDocument, unsupportedVersion, missingResource, exportFailed
    var errorDescription: String? {
        switch self {
        case .invalidImage: "无法读取这张照片，请重新选择。"
        case .invalidDocument: "手帐文件损坏或版本不受支持。"
        case .unsupportedVersion: "这份手帐由更新版本创建，请升级应用后打开。"
        case .missingResource: "手帐素材缺失，暂时无法打开。"
        case .exportFailed: "图片导出失败，请重试。"
        }
    }
}

/// 文件操作集中在后台串行队列，避免在主线程解码大图或写入照片。
/// 每次保存发布一个完整修订，最后原子更新 CURRENT，旧修订保留用于恢复。
nonisolated final class DiaryDocumentStore: Sendable {
    nonisolated struct Loaded: Sendable {
        let document: DiaryDocument
        let drawing: Data
        let images: [UUID: UIImage]
    }
    private nonisolated struct Pointer: Codable, Sendable { let manifestPath: String }
    private nonisolated struct Manifest: Codable, Sendable {
        let schemaVersion: Int
        let documentID: UUID
        let title: String
        let assets: [UUID: DiaryAsset]
        let pagePath: String
        let drawingPath: String
    }
    private let root: URL
    private let queue = DispatchQueue(label: "TravelDiary.DiaryStorage", qos: .userInitiated)

    init(ownerID: String, baseDirectory: URL? = nil) {
        let scope = Data(ownerID.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
        root = (baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("Diaries", isDirectory: true)
            .appendingPathComponent(scope, isDirectory: true)
    }

    private func run<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try operation() }) }
        }
    }

    func importImage(_ data: Data, documentID: UUID) async throws -> (DiaryAsset, UIImage) {
        try await run {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
                throw DiaryEditorError.invalidImage
            }
            let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            let swapsAxes = (5...8).contains(orientation)
            let size = CGSize(width: swapsAxes ? height.doubleValue : width.doubleValue,
                              height: swapsAxes ? width.doubleValue : height.doubleValue)
            guard size.width > 0, size.height > 0 else { throw DiaryEditorError.invalidImage }
            let image = try Self.decode(data, maximumDimension: 1800)
            let id = UUID()
            // 保留选择器提供的源字节；预览和导出解码时统一处理 EXIF，不覆盖源照片。
            let asset = DiaryAsset(id: id, path: "assets/\(id.uuidString).image", pixelSize: size)
            let url = self.directory(documentID).appendingPathComponent(asset.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return (asset, image)
        }
    }

    func save(_ document: DiaryDocument, drawing: Data) async throws {
        try await run {
            try Self.validate(document)
            let directory = self.directory(document.id)
            let revision = "revisions/\(UUID().uuidString)"
            let folder = directory.appendingPathComponent(revision, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let manifest = Manifest(schemaVersion: 1, documentID: document.id, title: document.title,
                                    assets: document.assets, pagePath: "\(revision)/page.json",
                                    drawingPath: "\(revision)/page.drawing")
            try encoder.encode(document.page).write(to: folder.appendingPathComponent("page.json"), options: .atomic)
            try drawing.write(to: folder.appendingPathComponent("page.drawing"), options: .atomic)
            try encoder.encode(manifest).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
            let currentURL = directory.appendingPathComponent("CURRENT.json")
            if let old = try? Data(contentsOf: currentURL) {
                try old.write(to: directory.appendingPathComponent("PREVIOUS.json"), options: .atomic)
            }
            let pointer = Pointer(manifestPath: "\(revision)/manifest.json")
            try encoder.encode(pointer).write(to: currentURL, options: .atomic)
            // 单独记录最近作品，不影响文档本身的提交一致性。
            try? Data(document.id.uuidString.utf8).write(to: self.root.appendingPathComponent("latest.txt"), options: .atomic)
        }
    }

    func latestID() async throws -> UUID? {
        try await run {
            guard let data = try? Data(contentsOf: self.root.appendingPathComponent("latest.txt")),
                  let string = String(data: data, encoding: .utf8) else { return nil }
            return UUID(uuidString: string)
        }
    }

    func load(_ id: UUID) async throws -> Loaded {
        try await run {
            let directory = self.directory(id)
            let decoder = JSONDecoder()
            // 回退仅限明确保留的前一提交指针，不扫描未提交的修订目录。
            func read(_ pointerName: String) throws -> (DiaryDocument, Data) {
                let pointer = try decoder.decode(Pointer.self, from: Data(contentsOf: directory.appendingPathComponent(pointerName)))
                let manifest = try decoder.decode(Manifest.self, from: Data(contentsOf: try self.resolve(pointer.manifestPath, in: directory)))
                guard manifest.schemaVersion == 1 else { throw DiaryEditorError.unsupportedVersion }
                guard manifest.documentID == id else { throw DiaryEditorError.invalidDocument }
                let page = try decoder.decode(DiaryPage.self, from: Data(contentsOf: try self.resolve(manifest.pagePath, in: directory)))
                let document = DiaryDocument(id: id, title: manifest.title, page: page, assets: manifest.assets)
                try Self.validate(document)
                return (document, try Data(contentsOf: self.resolve(manifest.drawingPath, in: directory)))
            }
            let pair: (DiaryDocument, Data)
            do { pair = try read("CURRENT.json") }
            catch DiaryEditorError.unsupportedVersion { throw DiaryEditorError.unsupportedVersion }
            catch { pair = try read("PREVIOUS.json") }
            var images: [UUID: UIImage] = [:]
            for asset in pair.0.assets.values {
                let url = try self.resolve(asset.path, in: directory)
                images[asset.id] = try Self.decode(Data(contentsOf: url), maximumDimension: 1800)
            }
            return Loaded(document: pair.0, drawing: pair.1, images: images)
        }
    }

    func exportImages(for document: DiaryDocument) async throws -> [UUID: UIImage] {
        try await run {
            var images: [UUID: UIImage] = [:]
            for asset in document.assets.values {
                let url = try self.resolve(asset.path, in: self.directory(document.id))
                images[asset.id] = try Self.decode(Data(contentsOf: url), maximumDimension: 4000)
            }
            return images
        }
    }

    private func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func resolve(_ path: String, in directory: URL) throws -> URL {
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw DiaryEditorError.invalidDocument }
        return directory.appendingPathComponent(path)
    }

    private static func decode(_ data: Data, maximumDimension: Int) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw DiaryEditorError.invalidImage }
        return UIImage(cgImage: image)
    }

    private static func validate(_ document: DiaryDocument) throws {
        guard document.page.size.width == 1000, document.page.size.height == 1400 else { throw DiaryEditorError.invalidDocument }
        var ids = Set<UUID>()
        func visit(_ nodes: [DiaryLayer], depth: Int) throws {
            guard depth <= 1, nodes.count <= 200 else { throw DiaryEditorError.invalidDocument }
            for node in nodes {
                let numbers = [node.size.width, node.size.height, node.transform.position.x, node.transform.position.y,
                               node.transform.pivot.x, node.transform.pivot.y, node.transform.scale,
                               node.transform.rotationDegrees, node.crop.zoom, node.crop.offset.x, node.crop.offset.y, node.fontSize]
                guard ids.insert(node.id).inserted, numbers.allSatisfy(\.isFinite), node.size.width > 0,
                      node.size.height > 0, node.transform.scale >= 0.05, node.transform.scale <= 20,
                      node.crop.zoom >= 1, node.crop.zoom <= 10, node.fontSize > 0, node.fontSize <= 300 else {
                    throw DiaryEditorError.invalidDocument
                }
                if node.kind == .group {
                    guard node.children.filter({ $0.kind == .photo }).count == 1 else { throw DiaryEditorError.invalidDocument }
                    try visit(node.children, depth: depth + 1)
                } else if !node.children.isEmpty { throw DiaryEditorError.invalidDocument }
                if node.kind == .photo || node.kind == .sticker {
                    guard let assetID = node.assetID, let asset = document.assets[assetID],
                          asset.pixelSize.width.isFinite, asset.pixelSize.height.isFinite,
                          asset.pixelSize.width > 0, asset.pixelSize.height > 0 else { throw DiaryEditorError.missingResource }
                }
            }
        }
        try visit(document.page.layers, depth: 0)
    }
}
