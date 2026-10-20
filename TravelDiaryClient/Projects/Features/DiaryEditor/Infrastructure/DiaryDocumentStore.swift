import Foundation
import UIKit
import ImageIO
import CryptoKit
import PencilKit

nonisolated enum DiaryEditorError: String, LocalizedError {
    case invalidImage, invalidDocument, unsupportedVersion, missingResource, exportFailed, staleObject, pageConflict, invalidName
    /// 在失败现场记录日志并返回原错误，保留现有 throw / catch 语义。
    /// 默认参数由调用位置生成，能区分同一错误在不同 guard 中的来源。
    @discardableResult
    func logged(file: String = #fileID, function: String = #function, line: Int = #line) -> Self {
        SupportLogger.log(level: .error, module: .diaryEditor,
                          message: "code=\(rawValue) reason=\(errorDescription ?? rawValue) source=\(file):\(line) function=\(function)")
        return self
    }

    var errorDescription: String? {
        switch self {
        case .invalidImage: "无法读取这张照片，请重新选择。"
        case .invalidDocument: "手帐文件损坏，无法恢复。"
        case .unsupportedVersion: "这份手帐的格式不受当前编辑器支持。"
        case .missingResource: "手帐素材缺失，暂时无法打开。"
        case .exportFailed: "图片导出失败，请重试。"
        case .invalidName: "手帐名称需要 1～60 个字符。"
        case .pageConflict: "这一页的版本已经变化，请保留当前页面并重新打开，避免覆盖其他修改。"
        case .staleObject: "上一级内容已改变，请重新打开对象编辑。"
        }
    }
}

/// 根画布和内层对象使用同一文件协议。每次先写完整对象图，再原子发布提交指针。
/// 后台串行队列拥有全部文件操作；新协议不包含旧照片分组的兼容/迁移分支。
nonisolated final class DiaryDocumentStore: Sendable {
    nonisolated struct Loaded: Sendable {
        let document: DiaryDocument
        let images: [UUID: UIImage]
    }
    nonisolated struct Draft: Sendable {
        let loaded: Loaded
        let baseRevision: Int
    }
    private nonisolated struct Pointer: Codable, Sendable {
        let manifestPath: String
        var baseRevision: Int? = nil
    }
    private nonisolated struct ObjectReference: Codable, Sendable {
        let id: UUID
        let path: String
        let drawingPath: String
    }
    private nonisolated struct Manifest: Codable, Sendable {
        let format: String
        let schemaVersion: Int
        let documentID: UUID
        let title: String
        let rootContentID: UUID
        let assets: [String: DiaryAsset]
        let objects: [ObjectReference]
        var bookID: UUID? = nil
    }
    /// 收藏与最近使用按账号保存，跨本共享。
    let stickerPreferenceKey: String
    let ownerID: String
    private let root: URL
    private let libraryRoot: URL
    private let bookID: UUID?
    /// 所有 Store 共用串行发布队列，同一本不能由多个独立队列覆盖目录。
    private static let fileQueue = DispatchQueue(label: "TravelDiary.DiaryStorage", qos: .userInitiated)
    private var queue: DispatchQueue { Self.fileQueue }
    private nonisolated final class RevisionState: @unchecked Sendable {
        // 只允许 fileQueue 访问，保存时检查本会话打开的基线。
        var values: [UUID: UUID] = [:]
    }
    private let opened = RevisionState()

    init(ownerID: String, baseDirectory: URL? = nil, bookID: UUID? = nil) {
        self.ownerID = ownerID
        let scope = Data(ownerID.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        stickerPreferenceKey = "diary.stickers." + scope
        let scopeRoot = (baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("Diaries", isDirectory: true).appendingPathComponent(scope, isDirectory: true)
        let booksRoot = scopeRoot.appendingPathComponent("books", isDirectory: true)
        libraryRoot = booksRoot
        self.bookID = bookID
        root = bookID.map { booksRoot.appendingPathComponent($0.uuidString, isDirectory: true) } ?? scopeRoot
    }
    private func run<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try operation() }) }
        }
    }
    /// 裁剪读取源文件，不能使用编辑器的 1800 像素缓存。
    func loadOriginalImage(_ asset: DiaryAsset, documentID: UUID) async throws -> UIImage {
        try await run {
            let data = try Data(contentsOf: self.resolve(asset.path, in: self.assetDirectory(documentID)))
            return try Self.decode(data, maximumDimension: Int(ceil(max(asset.pixelSize.width, asset.pixelSize.height))))
        }
    }

    /// 在替换资源前读取原素材；模板导入和已有作品都走同一个识别入口。
    func photoSlot(for layer: DiaryLayer, document: DiaryDocument) async throws -> DiaryPhotoSlot {
        try await run { try self.readPhotoSlot(for: layer, document: document) }
    }

    private func readPhotoSlot(for layer: DiaryLayer, document: DiaryDocument) throws -> DiaryPhotoSlot {
        if let slot = layer.photoSlot { return slot }
        if let placement = layer.photoPlacement {
            return DiaryPhotoSlot.rectangle(placement, size: layer.size, maskAssetID: nil)
        }
        guard let id = layer.assetID, let asset = document.assets[id] else { throw DiaryEditorError.missingResource.logged() }
        // 已替换的普通照片不再从用户新照片提取轮廓。
        if layer.photoFill != true {
            let image = try Self.decode(Data(contentsOf: resolve(asset.path, in: assetDirectory(document.id))), maximumDimension: 1800)
            if let slot = DiaryPhotoSlotDetector.detect(image, maskAssetID: id) { return slot }
            if let placement = DiaryPhotoPlacementDetector.detect(image) {
                return DiaryPhotoSlot.rectangle(placement, size: layer.size, maskAssetID: id)
            }
        }
        return DiaryPhotoSlot(corners: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)], maskAssetID: nil)
    }

    func importImage(_ data: Data, documentID: UUID) async throws -> (DiaryAsset, UIImage) {
        try await run { try self.writeImportedImage(data, documentID: documentID) }
    }

    private func writeImportedImage(_ data: Data, documentID: UUID) throws -> (DiaryAsset, UIImage) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw DiaryEditorError.invalidImage.logged()
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swapsAxes = (5...8).contains(orientation)
        let size = CGSize(width: swapsAxes ? height.doubleValue : width.doubleValue,
                          height: swapsAxes ? width.doubleValue : height.doubleValue)
        guard size.width > 0, size.height > 0 else { throw DiaryEditorError.invalidImage.logged() }
        let image = try Self.decode(data, maximumDimension: 1800)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let hex = Array(digest.prefix(32))
        let stableID = [String(hex[0..<8]), String(hex[8..<12]), String(hex[12..<16]), String(hex[16..<20]), String(hex[20..<32])].joined(separator: "-")
        let id = UUID(uuidString: stableID)!
        // 保留选择器提供的源字节；预览和导出解码时统一处理 EXIF，不覆盖源照片。
        let asset = DiaryAsset(id: id, path: "assets/\(id.uuidString).image", pixelSize: size)
        let url = assetDirectory(documentID).appendingPathComponent(asset.path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
        return (asset, image)
    }

    /// 将应用内预设素材复制到手帐本自己的资源目录，之后页面不再依赖 Bundle 路径。
    func importTemplateAsset(_ data: Data, documentID: UUID, assetID: UUID) async throws -> DiaryAsset {
        try await run {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                  width.doubleValue > 0, height.doubleValue > 0,
                  CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 64
                  ] as CFDictionary) != nil else { throw DiaryEditorError.invalidImage.logged() }
            let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            let swapsAxes = (5...8).contains(orientation)
            let size = CGSize(width: swapsAxes ? height.doubleValue : width.doubleValue,
                              height: swapsAxes ? width.doubleValue : height.doubleValue)
            let asset = DiaryAsset(id: assetID, path: "assets/\(assetID.uuidString).image", pixelSize: size)
            let url = self.assetDirectory(documentID).appendingPathComponent(asset.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
            return asset
        }
    }


    func save(_ document: DiaryDocument) async throws {
        try await run {
            guard document.bookID == self.bookID else { throw DiaryEditorError.invalidDocument.logged() }
            let directory = self.directory(document.id)
            let path = try self.writeSnapshot(document, prefix: "revisions", directory: directory)
            if let bookID = self.bookID {
                var book = try self.readBook(bookID)
                guard document.root.referenceSize == book.defaultPageSize else { throw DiaryEditorError.invalidDocument.logged() }
                let revision = UUID(uuidString: path.split(separator: "/")[1].description)!
                if let index = book.pages.firstIndex(where: { $0.id == document.id }) {
                    guard self.opened.values[document.id] == book.pages[index].revisionID else { throw DiaryEditorError.pageConflict.logged() }
                    book.pages[index].revisionID = revision
                    book.pages[index].updatedAt = Date()
                } else {
                    guard self.opened.values[document.id] == nil,
                          !book.trashedPages.contains(where: { $0.id == document.id }) else { throw DiaryEditorError.pageConflict.logged() }
                    book.pages.append(DiaryPageEntry(id: document.id, title: "", revisionID: revision, size: document.root.referenceSize))
                }
                try self.publish(book)
                self.opened.values[document.id] = revision
            } else {
                let current = directory.appendingPathComponent("CURRENT.json")
                if let previous = try? Data(contentsOf: current) {
                    try previous.write(to: directory.appendingPathComponent("PREVIOUS.json"), options: .atomic)
                }
                try JSONEncoder().encode(Pointer(manifestPath: path)).write(to: current, options: .atomic)
            }
        }
    }

    /// 所有页快照写好之后，一次发布整本目录；中途失败不会出现只替换一半的手帐。
    func savePhotoReplacementBatch(_ documents: [DiaryDocument], expected: DiaryBook) async throws {
        try await run {
            guard let bookID = self.bookID, expected.id == bookID else { throw DiaryEditorError.invalidDocument }
            var book = try self.readBook(bookID)
            guard book.catalogRevision == expected.catalogRevision else { throw DiaryEditorError.pageConflict }
            var revisions: [UUID: UUID] = [:]
            for document in documents {
                guard let index = book.pages.firstIndex(where: { $0.id == document.id }),
                      document.root.referenceSize == book.defaultPageSize else { throw DiaryEditorError.pageConflict }
                let path = try self.writeSnapshot(document, prefix: "revisions", directory: self.directory(document.id))
                let revision = UUID(uuidString: String(path.split(separator: "/")[1]))!
                book.pages[index].revisionID = revision
                book.pages[index].updatedAt = Date()
                revisions[document.id] = revision
            }
            try self.publish(book)
            for (id, revision) in revisions { self.opened.values[id] = revision }
        }
    }

    func load(_ id: UUID) async throws -> Loaded {
        try await run {
            let directory = self.directory(id)
            let path: String
            if let bookID = self.bookID {
                let book = try self.readBook(bookID)
                guard let page = book.pages.first(where: { $0.id == id }) else { throw DiaryEditorError.missingResource.logged() }
                path = "revisions/\(page.revisionID.uuidString)/manifest.json"
                self.opened.values[id] = page.revisionID
            } else {
                let pointer = try self.readPointer(directory.appendingPathComponent("CURRENT.json"))
                path = pointer.manifestPath
            }
            let document = try self.readSnapshot(path, directory: directory, documentID: id)
            return Loaded(document: document, images: try self.readImages(document, dimension: 1800, editorPlan: DiaryEditorImageSizing.plan(document, contentID: document.rootContentID, longestEdge: 1200)))
        }
    }
    func latestID() async throws -> UUID? {
        try await run {
            guard let data = try? Data(contentsOf: self.root.appendingPathComponent("latest.txt")),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return UUID(uuidString: text)
        }
    }
    func exportImages(for document: DiaryDocument) async throws -> [UUID: UIImage] {
        try await run { try self.readImages(document, dimension: 4000) }
    }

    /// 草稿使用与正式作品相同的快照格式，但不会修改主作品 CURRENT。
    func saveDraft(_ document: DiaryDocument, contentID: UUID, baseRevision: Int) async throws {
        try await run {
            let directory = self.directory(document.id)
            let prefix = "drafts/\(contentID.uuidString)"
            let path = try self.writeSnapshot(document, prefix: prefix, directory: directory)
            let pointer = Pointer(manifestPath: path, baseRevision: baseRevision)
            try JSONEncoder().encode(pointer).write(to: directory.appendingPathComponent(prefix + "/CURRENT.json"), options: .atomic)
        }
    }
    func loadDraft(contentID: UUID, documentID: UUID) async throws -> Draft? {
        try await run {
            let directory = self.directory(documentID)
            let url = directory.appendingPathComponent("drafts/\(contentID.uuidString)/CURRENT.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let pointer = try self.readPointer(url)
            let document = try self.readSnapshot(pointer.manifestPath, directory: directory, documentID: documentID)
            guard let base = pointer.baseRevision, document.objects[contentID] != nil else { throw DiaryEditorError.invalidDocument.logged() }
            return Draft(loaded: Loaded(document: document, images: try self.readImages(document, dimension: 1800, editorPlan: DiaryEditorImageSizing.plan(document, contentID: document.rootContentID, longestEdge: 1200))), baseRevision: base)
        }
    }
    func discardDraft(contentID: UUID, documentID: UUID) async throws {
        try await run {
            // 仅移除发布指针。未被引用的草稿快照可稍后统一回收，避免与正在读取的任务冲突。
            let url = self.directory(documentID).appendingPathComponent("drafts/\(contentID.uuidString)/CURRENT.json")
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }

    private func writeSnapshot(_ document: DiaryDocument, prefix: String, directory: URL) throws -> String {
        guard document.bookID == bookID else { throw DiaryEditorError.invalidDocument.logged() }
        let reachable = try Self.validate(document)
        let usedAssets = Set(reachable.flatMap { document.objects[$0]?.layers.flatMap(\.referencedAssetIDs) ?? [] })
        for id in usedAssets {
            guard let asset = document.assets[id],
                  FileManager.default.fileExists(atPath: try resolve(asset.path, in: assetDirectory(document.id)).path) else {
                throw DiaryEditorError.missingResource.logged()
            }
        }
        let relative = prefix + "/" + UUID().uuidString
        let folder = directory.appendingPathComponent(relative + "/objects", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var refs: [ObjectReference] = []
        for id in reachable.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let content = document.objects[id] else { throw DiaryEditorError.invalidDocument.logged() }
            let name = id.uuidString
            try encoder.encode(content).write(to: folder.appendingPathComponent(name + ".json"), options: .atomic)
            try content.drawing.write(to: folder.appendingPathComponent(name + ".drawing"), options: .atomic)
            refs.append(ObjectReference(id: id, path: relative + "/objects/" + name + ".json", drawingPath: relative + "/objects/" + name + ".drawing"))
        }
        let assets = Dictionary(uniqueKeysWithValues: document.assets.map { ($0.key.uuidString, $0.value) })
        let manifest = Manifest(format: "TravelDiary.SmartCanvas", schemaVersion: 1, documentID: document.id,
                                title: document.title, rootContentID: document.rootContentID, assets: assets, objects: refs, bookID: bookID)
        let path = relative + "/manifest.json"
        try encoder.encode(manifest).write(to: directory.appendingPathComponent(path), options: .atomic)
        return path
    }

    private func readPointer(_ url: URL) throws -> Pointer { try JSONDecoder().decode(Pointer.self, from: Data(contentsOf: url)) }
    private func readSnapshot(_ path: String, directory: URL, documentID: UUID) throws -> DiaryDocument {
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(Manifest.self, from: Data(contentsOf: resolve(path, in: directory)))
        guard manifest.format == "TravelDiary.SmartCanvas", manifest.schemaVersion == 1 else { throw DiaryEditorError.unsupportedVersion.logged() }
        guard manifest.documentID == documentID, manifest.bookID == bookID else { throw DiaryEditorError.invalidDocument.logged() }
        var contents: [UUID: DiaryObjectContent] = [:]
        for ref in manifest.objects {
            var content = try decoder.decode(DiaryObjectContent.self, from: Data(contentsOf: resolve(ref.path, in: directory)))
            guard content.id == ref.id, contents[ref.id] == nil else { throw DiaryEditorError.invalidDocument.logged() }
            content.drawing = try Data(contentsOf: resolve(ref.drawingPath, in: directory))
            if !content.drawing.isEmpty { _ = try PKDrawing(data: content.drawing) }
            contents[content.id] = content
        }
        var assets: [UUID: DiaryAsset] = [:]
        for (key, asset) in manifest.assets {
            guard UUID(uuidString: key) == asset.id else { throw DiaryEditorError.invalidDocument.logged() }
            assets[asset.id] = asset
        }
        let document = DiaryDocument(id: documentID, title: manifest.title, rootContentID: manifest.rootContentID, assets: assets, objects: contents, bookID: bookID)
        _ = try Self.validate(document)
        return document
    }
    private func readImages(_ document: DiaryDocument, dimension: Int, editorPlan: [UUID: Int]? = nil) throws -> [UUID: UIImage] {
        var result: [UUID: UIImage] = [:]
        let used = Set(document.objects.values.flatMap { $0.layers.flatMap(\.referencedAssetIDs) })
        for id in used {
            guard let asset = document.assets[id] else { throw DiaryEditorError.missingResource.logged() }
            result[id] = try Self.decode(Data(contentsOf: resolve(asset.path, in: assetDirectory(document.id))), maximumDimension: editorPlan?[id] ?? dimension)
        }
        return result
    }
    /// 已在后台队列解码，回到主线程只替换引用。计划按像素桶稳定，避免缩放抖动反复加载。
    func editorImages(for document: DiaryDocument, plan: [UUID: Int], existing: [UUID: UIImage]) async throws -> [UUID: UIImage] {
        try await run {
            var result: [UUID: UIImage] = [:]
            for (id, dimension) in plan {
                guard let asset = document.assets[id] else { continue }
                let expected = min(CGFloat(dimension), max(asset.pixelSize.width, asset.pixelSize.height))
                if let image = existing[id], let cg = image.cgImage,
                   abs(CGFloat(max(cg.width, cg.height)) - expected) <= max(2, expected * 0.15) {
                    result[id] = image
                } else {
                    result[id] = try Self.decode(Data(contentsOf: self.resolve(asset.path, in: self.assetDirectory(document.id))), maximumDimension: dimension)
                }
            }
            return result
        }
    }
    private func directory(_ id: UUID) -> URL {
        let parent = bookID == nil ? root : root.appendingPathComponent("pages", isDirectory: true)
        return parent.appendingPathComponent(id.uuidString, isDirectory: true)
    }
    private func assetDirectory(_ id: UUID) -> URL { bookID == nil ? directory(id) : root }
    private func resolve(_ path: String, in directory: URL) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw DiaryEditorError.invalidDocument.logged() }
        return directory.appendingPathComponent(path)
    }
    private static func decode(_ data: Data, maximumDimension: Int) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw DiaryEditorError.invalidImage.logged() }
        return UIImage(cgImage: image)
    }

    /// 任意层级共用同一校验：禁止循环引用与共享可变内容；32 层仅为文件安全上限。
    @discardableResult
    static func validate(_ document: DiaryDocument) throws -> Set<UUID> {
        var visited = Set<UUID>()
        var nodeIDs = Set<UUID>()
        func validateColor(_ color: DiaryColor?) throws {
            guard let color else { return }
            guard [color.red, color.green, color.blue, color.alpha].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw DiaryEditorError.invalidDocument.logged() }
        }
        func visit(_ id: UUID, depth: Int) throws {
            guard depth <= 32, visited.insert(id).inserted, let content = document.objects[id], content.id == id,
                  content.revision > 0, content.layers.count <= 200,
                  [.canvas, .photo, .text, .sticker].contains(content.role),
                  [content.referenceSize.width, content.referenceSize.height].allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 10000 }) else {
                throw DiaryEditorError.invalidDocument.logged()
            }
            try validateColor(content.background)
            if let primaryID = content.primaryLayerID {
                guard content.layers.contains(where: { $0.id == primaryID && $0.kind == content.role }) else { throw DiaryEditorError.invalidDocument.logged() }
            } else if content.role != .canvas { throw DiaryEditorError.invalidDocument.logged() }
            for node in content.layers {
                let numbers = [node.size.width, node.size.height, node.transform.position.x, node.transform.position.y,
                               node.transform.pivot.x, node.transform.pivot.y, node.transform.scale,
                               node.transform.rotationDegrees, node.crop.zoom, node.crop.offset.x, node.crop.offset.y, node.fontSize]
                guard nodeIDs.insert(node.id).inserted, numbers.allSatisfy(\.isFinite), node.size.width > 0,
                      node.size.height > 0, (0.05...20).contains(node.transform.scale),
                      (1...10).contains(node.crop.zoom), (1...300).contains(node.fontSize) else { throw DiaryEditorError.invalidDocument.logged() }
                guard [node.transform.stretchX, node.transform.stretchY].allSatisfy({ $0.isFinite && (0.05...20).contains($0) }) else {
                    throw DiaryEditorError.invalidDocument.logged()
                }
                if let slot = node.photoSlot {
                    guard slot.isValid, slot.maskAssetID.map({ document.assets[$0] != nil }) ?? true else {
                        throw DiaryEditorError.invalidDocument.logged()
                    }
                }
                if let placement = node.photoPlacement {
                    guard [placement.center.x, placement.center.y, placement.size.width, placement.size.height,
                           placement.radians].allSatisfy(\.isFinite),
                          placement.size.width > 0, placement.size.height > 0 else { throw DiaryEditorError.invalidDocument }
                }
                if let rect = node.displayBounds {
                    guard [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite),
                          rect.width > 0, rect.height > 0 else { throw DiaryEditorError.invalidDocument.logged() }
                }
                if let font = node.font {
                    guard !font.id.isEmpty, font.id.count <= 200, !font.version.isEmpty,
                          font.version.count <= 100 else { throw DiaryEditorError.invalidDocument }
                }
                if let crop = node.photoCrop {
                    guard node.kind == .photo, crop.parameters.isValid,
                          document.assets[crop.originalAssetID] != nil,
                          [crop.originalSize.width, crop.originalSize.height].allSatisfy({ $0.isFinite && $0 > 0 }),
                          [crop.originalPivot.x, crop.originalPivot.y, crop.originalCrop.zoom,
                           crop.originalCrop.offset.x, crop.originalCrop.offset.y].allSatisfy(\.isFinite),
                          (1...10).contains(crop.originalCrop.zoom) else { throw DiaryEditorError.invalidDocument.logged() }
                }
                switch node.kind {
                case .object:
                    guard let child = node.contentID else { throw DiaryEditorError.invalidDocument.logged() }
                    try visit(child, depth: depth + 1)
                case .photo, .sticker:
                    guard let assetID = node.assetID, let asset = document.assets[assetID],
                          [asset.pixelSize.width, asset.pixelSize.height].allSatisfy({ $0.isFinite && $0 > 0 }) else { throw DiaryEditorError.missingResource.logged() }
                case .frame:
                    guard let target = node.frameTargetID, content.layers.contains(where: { $0.id == target && $0.kind == .photo }),
                          let width = node.frameWidth, width.isFinite, (1...100).contains(width) else { throw DiaryEditorError.invalidDocument.logged() }
                    try validateColor(node.frameColor)
                case .text: break
                case .canvas: throw DiaryEditorError.invalidDocument.logged()
                }
            }
        }
        try visit(document.rootContentID, depth: 0)
        return visited
    }
}

extension DiaryDocumentStore {
    /// 书架只扫描小型目录文件，不读取各页图层和照片。
    nonisolated func listBooks() async throws -> [DiaryBook] {
        try await run {
            guard FileManager.default.fileExists(atPath: self.libraryRoot.path) else { return [] }
            return try FileManager.default.contentsOfDirectory(at: self.libraryRoot, includingPropertiesForKeys: nil)
                .filter { UUID(uuidString: $0.lastPathComponent) != nil }
                .map { try self.readBook(UUID(uuidString: $0.lastPathComponent)!) }
                .sorted { $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt }
        }
    }
    /// 书架允许局部恢复；其他调用者继续使用严格的 listBooks() 事务语义。
    nonisolated struct ShelfSnapshot: Sendable {
        let books: [DiaryBook]
        let unreadableIDs: [UUID]
    }
    nonisolated func loadShelf() async throws -> ShelfSnapshot {
        try await run {
            guard FileManager.default.fileExists(atPath: self.libraryRoot.path) else {
                return ShelfSnapshot(books: [], unreadableIDs: [])
            }
            let urls = try FileManager.default.contentsOfDirectory(at: self.libraryRoot, includingPropertiesForKeys: nil)
            var books: [DiaryBook] = [], failures: [UUID] = []
            for url in urls {
                guard let id = UUID(uuidString: url.lastPathComponent) else { continue }
                do { books.append(try self.readBook(id)) } catch { failures.append(id) }
            }
            return ShelfSnapshot(books: DiaryShelfSort.updated.apply(to: books, search: ""), unreadableIDs: failures)
        }
    }
    /// 删除当前账号下整本手帐，包括页面、回收站和独立素材。
    nonisolated func deleteBook(_ id: UUID) async throws {
        try await run {
            let directory = self.libraryRoot.appendingPathComponent(id.uuidString, isDirectory: true)
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
    }
    nonisolated func createBook(title: String, preset: DiaryPagePreset = .a5) async throws -> DiaryBook {
        try await run {
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 60 else { throw DiaryEditorError.invalidName.logged() }
            var book = DiaryBook(title: name)
            book.defaultPageSize = preset.size
            return try self.publish(book)
        }
    }
    nonisolated func loadBook() async throws -> DiaryBook {
        try await run {
            guard let id = self.bookID else { throw DiaryEditorError.invalidDocument.logged() }
            return try self.readBook(id)
        }
    }
    nonisolated func renameBook(_ title: String) async throws {
        try await mutateBook { book in
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 60 else { throw DiaryEditorError.invalidName.logged() }
            book.title = name
        }
    }
    nonisolated func setCover(_ id: UUID?) async throws {
        try await mutateBook { book in
            guard id == nil || book.pages.contains(where: { $0.id == id }) else { throw DiaryEditorError.invalidDocument.logged() }
            book.coverPageID = id
        }
    }
    nonisolated func setShell(_ id: UUID?) async throws {
        try await mutateBook { book in
            guard id == nil || book.pages.contains(where: { $0.id == id }) else { throw DiaryEditorError.invalidDocument.logged() }
            book.shellPageID = id
        }
    }
    nonisolated func movePage(_ id: UUID, forward: Bool) async throws {
        try await mutateBook { book in
            guard let index = book.pages.firstIndex(where: { $0.id == id }) else { throw DiaryEditorError.invalidDocument.logged() }
            let target = index + (forward ? 1 : -1)
            guard book.pages.indices.contains(target) else { return }
            book.pages.swapAt(index, target)
        }
    }
    /// 一次原子发布完整顺序；拖动期间目录变化时拒绝覆盖新增、删除或其他排序。
    nonisolated func reorderPages(_ ids: [UUID], expectedRevision: UUID) async throws {
        try await mutateBook { book in
            guard book.catalogRevision == expectedRevision else { throw DiaryEditorError.pageConflict }
            guard ids.count == book.pages.count, Set(ids).count == ids.count,
                  Set(ids) == Set(book.pages.map(\.id)) else { throw DiaryEditorError.invalidDocument }
            let entries = Dictionary(uniqueKeysWithValues: book.pages.map { ($0.id, $0) })
            book.pages = ids.compactMap { entries[$0] }
        }
    }
    /// 软删除只移动目录引用，资源与完整图层仍保留，供用户恢复。
    nonisolated func trashPage(_ id: UUID) async throws {
        try await mutateBook { book in
            guard let index = book.pages.firstIndex(where: { $0.id == id }) else { throw DiaryEditorError.invalidDocument.logged() }
            book.trashedPages.append(DiaryTrashedPage(entry: book.pages.remove(at: index), originalIndex: index))
            if book.coverPageID == id { book.coverPageID = nil }
            if book.shellPageID == id { book.shellPageID = nil }
        }
    }
    nonisolated func restorePage(_ id: UUID) async throws {
        try await mutateBook { book in
            guard let index = book.trashedPages.firstIndex(where: { $0.id == id }) else { throw DiaryEditorError.invalidDocument.logged() }
            let record = book.trashedPages.remove(at: index)
            book.pages.insert(record.entry, at: min(record.originalIndex, book.pages.count))
        }
    }
    private nonisolated func mutateBook(_ change: @escaping @Sendable (inout DiaryBook) throws -> Void) async throws {
        try await run {
            guard let id = self.bookID else { throw DiaryEditorError.invalidDocument.logged() }
            var book = try self.readBook(id)
            let before = book
            try change(&book)
            guard book != before else { return }
            try self.publish(book)
        }
    }
    private nonisolated func readBook(_ id: UUID) throws -> DiaryBook {
        let url = libraryRoot.appendingPathComponent(id.uuidString).appendingPathComponent("book.json")
        let book = try JSONDecoder().decode(DiaryBook.self, from: Data(contentsOf: url))
        guard book.id == id, book.format == "TravelDiary.Book", book.schemaVersion == 1,
              Set(book.pages.map(\.id)).count == book.pages.count,
              Set(book.pages.map(\.id)).isDisjoint(with: book.trashedPages.map(\.id)),
              book.defaultPageSize.width.isFinite, book.defaultPageSize.height.isFinite,
              book.defaultPageSize.width > 0, book.defaultPageSize.height > 0 else { throw DiaryEditorError.invalidDocument.logged() }
        return book
    }
    /// 先写完整页快照，再在同一串行队列原子发布本目录。预览失败不会回滚已提交页面。
    @discardableResult
    private nonisolated func publish(_ value: DiaryBook) throws -> DiaryBook {
        var book = value
        book.updatedAt = Date(); book.catalogRevision = UUID()
        let directory = libraryRoot.appendingPathComponent(book.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("book.json")
        if let old = try? Data(contentsOf: url) {
            try old.write(to: directory.appendingPathComponent("book.previous.json"), options: .atomic)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(book).write(to: url, options: .atomic)
        return book
    }

    /// 预览读取不改变编辑会话的保存基线；浏览一本不会抢占某页编辑状态。
    nonisolated func loadPreviewSource(_ page: DiaryPageEntry, large: Bool) async throws -> Loaded {
        try await run {
            let path = "revisions/\(page.revisionID.uuidString)/manifest.json"
            let doc = try self.readSnapshot(path, directory: self.directory(page.id), documentID: page.id)
            return Loaded(document: doc, images: try self.readImages(doc, dimension: large ? 1800 : 480))
        }
    }
    /// 导出使用目录捕获的不可变页版本，不改变正在编辑页面的保存基线。
    func loadPDFSource(_ page: DiaryPageEntry) async throws -> Loaded {
        try await run {
            let path = "revisions/\(page.revisionID.uuidString)/manifest.json"
            let document = try self.readSnapshot(path, directory: self.directory(page.id), documentID: page.id)
            let size = document.root.referenceSize
            let plan = DiaryEditorImageSizing.plan(document, contentID: document.rootContentID,
                longestEdge: max(size.width, size.height), maximumDimension: 4000, pixelBudget: 96 * 1024 * 1024 / 4)
            return Loaded(document: document, images: try self.readImages(document, dimension: 4000, editorPlan: plan))
        }
    }
    nonisolated func cachedPreview(_ page: DiaryPageEntry, large: Bool) async throws -> Data? {
        try await run { try? Data(contentsOf: self.previewURL(page, large: large)) }
    }
    nonisolated func cachePreview(_ data: Data, page: DiaryPageEntry, large: Bool) async throws {
        try await run {
            let url = self.previewURL(page, large: large)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
    }
    nonisolated var previewScope: String { root.path }
    private nonisolated func previewURL(_ page: DiaryPageEntry, large: Bool) -> URL {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let scope = libraryRoot.deletingLastPathComponent().lastPathComponent
        return cache.appendingPathComponent("DiaryPreviews/\(scope)/\(bookID?.uuidString ?? "single")/\(page.id)/\(page.revisionID)/v2-light-ink-\(large ? 1800 : 480).png")
    }
}

extension DiaryDocumentStore {
    /// 完整准备页面后一次发布目录。新本以目录移动发布，旧本以 book.json 原子写发布。
    /// operationID 由一次用户意图产生，错误重试沿用；已发布操作直接返回原结果。
    func importPreset(_ package: DiaryPresetPackage, pageIDs: [String], title: String,
                      operationID: UUID, replacementPhotos: [URL] = [], replacementFill: DiaryPhotoSlot.Fill = .cover, hiddenCategories: Set<DiaryLayerSemanticKind> = [], afterPageID: UUID? = nil, expectedRevision: UUID? = nil,
                      progress: @escaping @Sendable (String) -> Void = { _ in },
                      cancellation: DiaryPresetCancellation? = nil) async throws -> DiaryBook {
        try await run {
            let destinationID = self.bookID ?? operationID
            if let existing = try? self.readBook(destinationID), existing.presetImports?[operationID.uuidString] != nil { return existing }
            progress("正在校验预设资源…")
            try cancellation?.check()
            try package.validate()
            let all = try package.pages
            guard !pageIDs.isEmpty, Set(pageIDs).count == pageIDs.count else { throw DiaryEditorError.invalidDocument.logged() }
            let selected = try pageIDs.map { id -> PresetPage in
                guard let page = all.first(where: { $0.id == id }) else { throw DiaryEditorError.invalidDocument.logged() }
                return page
            }
            try FileManager.default.createDirectory(at: self.libraryRoot, withIntermediateDirectories: true)
            let available = (try? self.libraryRoot.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
            let required = Int64(package.manifest.files.reduce(0) { $0 + $1.byteCount }) * 2 + 20_000_000
            if let available, available < required { throw CocoaError(.fileWriteOutOfSpace) }
            let journalURL = self.libraryRoot.appendingPathComponent(".import-\(operationID.uuidString).json")
            // 重试清理未发布的孤立页；已提交请求在函数入口已返回，不会删除有效数据。
            if let bytes = try? Data(contentsOf: journalURL), let journal = try? JSONDecoder().decode(PresetImportJournal.self, from: bytes), journal.destinationID == destinationID {
                let published = try? self.readBook(destinationID)
                let pageIDs = Set((published?.pages.map(\.id) ?? []) + (published?.trashedPages.map(\.id) ?? []))
                for pageID in journal.pageIDs where !pageIDs.contains(pageID) {
                    try? FileManager.default.removeItem(at: self.libraryRoot.appendingPathComponent("\(destinationID)/pages/\(pageID)"))
                }
                // 资源为本次新 UUID，日志在发布前持久化；未发布的资源不可能被其他页面引用。
                for id in journal.assetIDs { try? FileManager.default.removeItem(at: self.libraryRoot.appendingPathComponent("\(destinationID)/assets/\(id).image")) }
            }
            var journal = PresetImportJournal(destinationID: destinationID, stage: "staging", pageIDs: [], assetIDs: [])
            func log(_ stage: String) throws {
                journal.stage = stage
                try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
            }
            try log("validated")
            let isNew = self.bookID == nil
            var book: DiaryBook
            if isNew {
                guard !FileManager.default.fileExists(atPath: self.libraryRoot.appendingPathComponent(destinationID.uuidString).path) else { throw DiaryEditorError.pageConflict.logged() }
                let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, name.count <= 60 else { throw DiaryEditorError.invalidName.logged() }
                book = DiaryBook(title: name); book.id = destinationID; book.defaultPageSize = package.manifest.pageSize.cg
            } else {
                book = try self.readBook(destinationID)
                if let expectedRevision, expectedRevision != book.catalogRevision { throw DiaryEditorError.pageConflict.logged() }
            }
            if let afterPageID, !book.pages.contains(where: { $0.id == afterPageID }) { throw DiaryEditorError.pageConflict.logged() }
            // 暂存不使用 UUID 本目录名，因此书架扫描永远不会看到半成品。
            let staging = self.libraryRoot.appendingPathComponent(".import-\(operationID.uuidString)")
            try? FileManager.default.removeItem(at: staging)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            let target = DiaryDocumentStore(ownerID: "preset-staging", baseDirectory: staging, bookID: destinationID)
            let assetIDs = Dictionary(uniqueKeysWithValues: package.manifest.assetTable.keys.map { ($0, UUID()) })
            var copied = Set<UUID>(); var entries: [DiaryPageEntry] = []
            var photoIndex = 0
            for (index, page) in selected.enumerated() {
                try cancellation?.check()
                progress("正在准备第 \(index + 1) / \(selected.count) 页…")
                var document = try package.instantiate(page, bookID: destinationID, targetSize: book.defaultPageSize, assetIDs: assetIDs)
                    .excludingPresetCategories(hiddenCategories)
                for (key, source) in package.manifest.assetTable {
                    guard let id = assetIDs[key], document.assets[id] != nil, copied.insert(id).inserted else { continue }
                    let data = try Data(contentsOf: package.url(source.path))
                    // 不信任声明的尺寸；真实解码成功后才允许发布。
                    guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                          let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
                          (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue == source.pixelSize.width,
                          (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue == source.pixelSize.height else { throw DiaryEditorError.invalidImage.logged() }
                    _ = try Self.decode(data, maximumDimension: 64)
                    let url = target.root.appendingPathComponent("assets/\(id.uuidString).image")
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: url, options: .atomic)
                }
                for layer in document.replaceablePhotos() where photoIndex < replacementPhotos.count {
                    let data = try Data(contentsOf: replacementPhotos[photoIndex])
                    var slot = try target.readPhotoSlot(for: layer, document: document)
                    slot.fill = replacementFill
                    let (asset, _) = try target.writeImportedImage(data, documentID: document.id)
                    document.replacePhoto(layer.id, with: asset, slot: slot)
                    copied.insert(asset.id)
                    photoIndex += 1
                }
                let path = try target.writeSnapshot(document, prefix: "revisions", directory: target.directory(document.id))
                let revision = UUID(uuidString: String(path.split(separator: "/")[1]))!
                var entry = DiaryPageEntry(id: document.id, title: page.title, revisionID: revision, size: book.defaultPageSize)
                entry.presetSource = DiaryPresetSource(bookID: package.id, pageID: page.id, version: package.manifest.packageVersion)
                entries.append(entry)
            }
            guard photoIndex == replacementPhotos.count else { throw DiaryEditorError.invalidDocument.logged() }
            for unit in package.manifest.readingUnits ?? [] where unit.kind == "spread" && unit.pageIDs.count == 2 {
                let indexes = unit.pageIDs.compactMap { source in entries.firstIndex { $0.presetSource?.pageID == source } }
                if indexes.count == 2 {
                    let pairID = UUID()
                    for (side, index) in indexes.enumerated() {
                        entries[index].presetSpreadID = pairID
                        entries[index].presetSpreadSide = side == 0 ? "left" : "right"
                    }
                }
            }
            let insertion = afterPageID.flatMap { id in book.pages.firstIndex { $0.id == id }.map { $0 + 1 } } ?? book.pages.count
            book.pages.insert(contentsOf: entries, at: insertion)
            if isNew {
                book.coverPageID = entries.first(where: { $0.presetSource?.pageID == package.manifest.coverPageID })?.id ?? entries.first?.id
                if let shellID = package.manifest.shellPageID {
                    book.shellPageID = entries.first(where: { $0.presetSource?.pageID == shellID })?.id
                }
            }
            if book.presetImports == nil { book.presetImports = [:] }
            book.presetImports?[operationID.uuidString] = entries.map(\.id)
            journal.pageIDs = entries.map(\.id); journal.assetIDs = Array(copied)
            try cancellation?.check()
            try log("publishing")
            progress("正在保存手帐…")
            if isNew {
                let prepared = try target.publish(book)
                try FileManager.default.moveItem(at: target.root, to: self.libraryRoot.appendingPathComponent(destinationID.uuidString))
                try? FileManager.default.removeItem(at: journalURL)
                return prepared
            }
            // 素材与页目录均为新 UUID，不覆盖已有资源。异常留下的孤立文件不被目录引用。
            var moved: [URL] = []
            do {
                for name in ["assets", "pages"] {
                    let from = target.root.appendingPathComponent(name)
                    let to = self.root.appendingPathComponent(name)
                    try FileManager.default.createDirectory(at: to, withIntermediateDirectories: true)
                    for item in (try? FileManager.default.contentsOfDirectory(at: from, includingPropertiesForKeys: nil)) ?? [] {
                        let dest = to.appendingPathComponent(item.lastPathComponent)
                        try FileManager.default.moveItem(at: item, to: dest); moved.append(dest)
                    }
                }
                let result = try self.publish(book)
                try? FileManager.default.removeItem(at: journalURL)
                return result
            } catch {
                for item in moved { try? FileManager.default.removeItem(at: item) }
                throw error
            }
        }
    }
}

private nonisolated struct PresetImportJournal: Codable {
    let destinationID: UUID
    var stage: String
    var pageIDs: [UUID]
    var assetIDs: [UUID]
}

extension DiaryDocumentStore {
    /// 在发布队列中复制印制来源，删除原书、清理素材或继续编辑均不会影响本次导出。
    func freezeForPrinting(_ book: DiaryBook, at base: URL) async throws -> DiaryDocumentStore {
        let target = DiaryDocumentStore(ownerID: ownerID, baseDirectory: base, bookID: book.id)
        try await run {
            let current = try self.readBook(book.id)
            guard current.catalogRevision == book.catalogRevision else { throw DiaryEditorError.pageConflict }
            try FileManager.default.createDirectory(at: target.root.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: self.root, to: target.root)
        }
        return target
    }
}
