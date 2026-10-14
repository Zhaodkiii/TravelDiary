import Foundation
import PencilKit
import CoreGraphics
import CryptoKit

/// 制作端与客户端共用的显式 JSON 协议，不依赖 CGPoint 的默认数组编码。
nonisolated struct PresetSize: Codable, Sendable {
    let width: Double
    let height: Double
    var cg: CGSize { CGSize(width: width, height: height) }
}
nonisolated struct PresetPoint: Codable, Sendable {
    let x: Double
    let y: Double
    var cg: CGPoint { CGPoint(x: x, y: y) }
}
nonisolated struct PresetTransform: Decodable, Sendable {
    let position: PresetPoint
    let pivot: PresetPoint
    let scale: Double
    let rotationDegrees: Double
    let stretch: PresetSize?
    var value: DiaryTransform { DiaryTransform(position: position.cg, pivot: pivot.cg, scale: scale, rotationDegrees: rotationDegrees, stretch: stretch?.cg) }
}
nonisolated struct PresetNode: Decodable, Sendable {
    let id: String
    let name: String
    let kind: DiaryLayer.Kind
    let size: PresetSize
    let transform: PresetTransform
    let visible: Bool
    let locked: Bool
    let contentID: String?
    let assetID: String?
    let text: String?
    let fontSize: Double?
    let font: DiaryFontReference?
    let frameTargetID: String?
    let frameColor: DiaryColor?
    let frameWidth: Double?
    let crop: Crop?
    let blendMode: DiaryBlendMode?
    nonisolated struct Crop: Decodable, Sendable { let zoom: Double; let offset: PresetPoint }
}
nonisolated struct PresetContent: Decodable, Sendable {
    let id: String
    let role: DiaryLayer.Kind
    let primaryLayerID: String?
    let referenceSize: PresetSize
    let background: DiaryColor?
    let layers: [PresetNode]
    let drawingPath: String?
}
nonisolated struct PresetPage: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let size: PresetSize
    let rootContentID: String
    let preview: Preview
    nonisolated struct Preview: Decodable, Sendable { let thumbnailPath: String; let largePath: String }
}
nonisolated struct PresetManifest: Decodable, Sendable {
    let format: String
    let schemaVersion: Int
    let layerSchemaVersion: Int
    let templateBookID: String
    let packageVersion: Int
    let title: String
    let seriesID: String
    let sortOrder: Int?
    let tags: [String]?
    let pageSize: PresetSize
    let coverPageID: String
    let pages: [PageReference]
    let objectTable: [String: String]
    let assetTable: [String: Asset]
    let requiredCapabilities: [String]
    let requiredFonts: [DiaryFontReference]?
    let files: [FileRecord]
    nonisolated struct PageReference: Decodable, Sendable { let id: String; let title: String; let path: String }
    nonisolated struct Asset: Decodable, Sendable { let id: String; let path: String; let pixelSize: PresetSize; let sha256: String; let byteCount: Int }
    nonisolated struct FileRecord: Decodable, Sendable { let path: String; let byteCount: Int; let sha256: String }
}
nonisolated struct DiaryPresetSeries: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let directory: String
    let sortOrder: Int
}
nonisolated struct DiaryPresetPackage: Identifiable, Sendable {
    let root: URL
    let manifest: PresetManifest
    var id: String { manifest.templateBookID }
    var pages: [PresetPage] {
        get throws { try manifest.pages.map { try read(PresetPage.self, $0.path) } }
    }
    func url(_ path: String) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.split(separator: "/").contains("..") else { throw DiaryEditorError.invalidDocument.logged() }
        let result = root.appendingPathComponent(path).resolvingSymlinksInPath()
        guard result.path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { throw DiaryEditorError.invalidDocument.logged() }
        return result
    }
    func read<T: Decodable>(_ type: T.Type, _ path: String) throws -> T {
        log("read.begin file=\(path) type=\(String(describing: type))", level: .debug)
        do {
            let data = try Data(contentsOf: url(path))
            let value = try JSONDecoder().decode(type, from: data)
            log("read.complete file=\(path) bytes=\(data.count)", level: .debug)
            return value
        } catch {
            log("read.failed file=\(path) error=\(String(reflecting: error))", level: .error)
            throw error
        }
    }
    /// 包、页面、对象和文件都携带上下文，不记录用户照片或文本的实际内容。
    func log(_ message: String, level: LogLevel = .info) {
        SupportLogger.log(level: level, module: .diaryEditor,
                          message: "preset=\(id) version=\(manifest.packageVersion) package=\(root.lastPathComponent) \(message)")
    }
    private func invalid(_ reason: String) -> DiaryEditorError {
        log("validate.failed reason=\(reason)", level: .error)
        return .invalidDocument
    }
    /// 导入前检查完整文件索引；浏览只读小型清单，原图不在主线程提前解码。
    func validate() throws {
        let started = Date()
        log("validate.begin pages=\(manifest.pages.count) objects=\(manifest.objectTable.count) assets=\(manifest.assetTable.count) files=\(manifest.files.count)")
        guard manifest.format == "TravelDiary.PresetBook", manifest.schemaVersion == 1,
              manifest.layerSchemaVersion == 1, manifest.packageVersion > 0,
              !manifest.pages.isEmpty, manifest.pages.count <= 100,
              Set(manifest.pages.map(\.id)).count == manifest.pages.count,
              manifest.pages.contains(where: { $0.id == manifest.coverPageID }),
              Set(manifest.requiredCapabilities).isSubset(of: ["image", "object", "text", "frame", "drawing"]),
              manifest.files.count <= 10000 else {
            log("validate.failed reason=manifest format=\(manifest.format) schema=\(manifest.schemaVersion) layerSchema=\(manifest.layerSchemaVersion) pages=\(manifest.pages.count) capabilities=\(manifest.requiredCapabilities)", level: .error)
            throw DiaryEditorError.unsupportedVersion.logged()
        }
        let paths = Set(manifest.files.map(\.path))
        guard paths.count == manifest.files.count else { throw invalid("文件索引包含重复路径") }
        var total = 0
        for (index, file) in manifest.files.enumerated() {
            guard file.byteCount >= 0, file.byteCount <= 100_000_000 else {
                throw invalid("单文件大小超限 file=\(file.path) bytes=\(file.byteCount) limit=100000000")
            }
            // 整包不设总大小上限；逐文件校验，实际导入仍检查设备可用空间。
            total += file.byteCount
            log("validate.file.begin index=\(index + 1) file=\(file.path) expectedBytes=\(file.byteCount)", level: .debug)
            do {
                let data = try Data(contentsOf: url(file.path), options: .mappedIfSafe)
                guard data.count == file.byteCount else {
                    throw invalid("文件大小不匹配 file=\(file.path) expected=\(file.byteCount) actual=\(data.count)")
                }
                let actualHash = Self.hash(data)
                guard actualHash == file.sha256 else {
                    throw invalid("SHA256 不匹配 file=\(file.path) expected=\(file.sha256) actual=\(actualHash)")
                }
                log("validate.file.complete file=\(file.path) bytes=\(data.count) sha256=\(actualHash)", level: .debug)
            } catch {
                log("validate.file.failed file=\(file.path) error=\(String(reflecting: error))", level: .error)
                throw error
            }
            if (index + 1) % 100 == 0 || index + 1 == manifest.files.count {
                log("validate.progress files=\(index + 1)/\(manifest.files.count) bytes=\(total)")
            }
        }
        for page in try pages {
            guard page.size.cg == manifest.pageSize.cg, manifest.objectTable[page.rootContentID] != nil,
                  paths.contains(page.preview.thumbnailPath), paths.contains(page.preview.largePath) else {
                throw invalid("页面尺寸、根对象或预览引用无效 page=\(page.id) root=\(page.rootContentID) size=\(page.size.width)x\(page.size.height)")
            }
            log("validate.page.complete page=\(page.id) root=\(page.rootContentID) thumbnail=\(page.preview.thumbnailPath) preview=\(page.preview.largePath)")
        }
        for ref in manifest.pages { guard paths.contains(ref.path) else { throw invalid("页面未列入索引 page=\(ref.id) file=\(ref.path)") } }
        for path in manifest.objectTable.values { guard paths.contains(path) else { throw invalid("对象未列入索引 file=\(path)") } }
        for (id, asset) in manifest.assetTable {
            guard asset.id == id, paths.contains(asset.path), asset.pixelSize.width > 0, asset.pixelSize.height > 0,
                  asset.pixelSize.width * asset.pixelSize.height <= 100_000_000,
                  manifest.files.contains(where: { $0.path == asset.path && $0.sha256 == asset.sha256 && $0.byteCount == asset.byteCount }) else {
                throw invalid("素材索引、尺寸或摘要无效 asset=\(id) file=\(asset.path)")
            }
        }
        log("validate.complete bytes=\(total) duration=\(Date().timeIntervalSince(started))s")
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// 每页分别实例化对象，复用图片但绝不共享可变内容；跨本纸张适配保留局部坐标。
    func instantiate(_ page: PresetPage, bookID: UUID, targetSize: CGSize, assetIDs: [String: UUID]) throws -> DiaryDocument {
        log("instantiate.begin page=\(page.id) root=\(page.rootContentID) targetSize=\(targetSize)")
        var document = DiaryDocument()
        document.title = page.title; document.bookID = bookID; document.objects = [:]
        var seen = Set<String>()
        func visit(_ id: String, depth: Int) throws -> UUID {
            guard depth <= 30, seen.insert(id).inserted, let path = manifest.objectTable[id] else { throw DiaryEditorError.invalidDocument.logged() }
            let source = try read(PresetContent.self, path)
            guard source.id == id else { throw DiaryEditorError.invalidDocument.logged() }
            var content = DiaryObjectContent(role: source.role, referenceSize: source.referenceSize.cg, background: source.background, layers: [])
            guard Set(source.layers.map(\.id)).count == source.layers.count else { throw DiaryEditorError.invalidDocument.logged() }
            let ids = Dictionary(uniqueKeysWithValues: source.layers.map { ($0.id, UUID()) })
            content.primaryLayerID = source.primaryLayerID.flatMap { ids[$0] }
            if source.primaryLayerID != nil && content.primaryLayerID == nil { throw DiaryEditorError.invalidDocument.logged() }
            for node in source.layers {
                var layer = DiaryLayer(id: ids[node.id]!, name: node.name, kind: node.kind, transform: node.transform.value, size: node.size.cg,
                                       text: node.text ?? "", fontSize: node.fontSize ?? 36, visible: node.visible, locked: node.locked)
                layer.font = node.font
                layer.blendMode = node.blendMode
                if let assetID = node.assetID {
                    guard let uuid = assetIDs[assetID], let asset = manifest.assetTable[assetID] else { throw DiaryEditorError.missingResource.logged() }
                    layer.assetID = uuid
                    document.assets[uuid] = DiaryAsset(id: uuid, path: "assets/\(uuid.uuidString).image", pixelSize: asset.pixelSize.cg)
                }
                if let child = node.contentID { layer.contentID = try visit(child, depth: depth + 1) }
                if let target = node.frameTargetID {
                    guard let mapped = ids[target] else { throw DiaryEditorError.invalidDocument.logged() }
                    layer.frameTargetID = mapped
                }
                layer.frameColor = node.frameColor; layer.frameWidth = node.frameWidth.map { CGFloat($0) }
                if let crop = node.crop { layer.crop = DiaryCrop(zoom: crop.zoom, offset: crop.offset.cg) }
                content.layers.append(layer)
            }
            if let drawing = source.drawingPath {
                guard manifest.files.contains(where: { $0.path == drawing }) else { throw DiaryEditorError.invalidDocument.logged() }
                content.drawing = try Data(contentsOf: url(drawing))
            }
            document.objects[content.id] = content
            return content.id
        }
        let sourceRoot = try visit(page.rootContentID, depth: 0)
        guard document.objects[sourceRoot]?.referenceSize == page.size.cg else { throw DiaryEditorError.invalidDocument.logged() }
        document.rootContentID = sourceRoot
        if targetSize != page.size.cg {
            let scale = min(targetSize.width / page.size.width, targetSize.height / page.size.height)
            let position = CGPoint(x: (targetSize.width - page.size.width * scale) / 2, y: (targetSize.height - page.size.height * scale) / 2)
            // 纸张适配只变换根图层的外部坐标，不把整页包装成单层智能对象。
            // 子对象保持自己的原始坐标、尺寸和分层，仍能独立打开编辑。
            var root = document.objects[sourceRoot]!
            root.referenceSize = targetSize
            for index in root.layers.indices {
                let original = root.layers[index].transform
                root.layers[index].transform.position = CGPoint(
                    x: position.x + original.position.x * scale,
                    y: position.y + original.position.y * scale)
                root.layers[index].transform.scale = original.scale * scale
            }
            // 顶层绘画也需要使用同一纸张变换，避免和图层错位。
            if !root.drawing.isEmpty {
                let drawing = try PKDrawing(data: root.drawing)
                let transform = CGAffineTransform(translationX: position.x, y: position.y)
                    .scaledBy(x: scale, y: scale)
                root.drawing = drawing.transformed(using: transform).dataRepresentation()
            }
            document.objects[sourceRoot] = root
        }
        try DiaryDocumentStore.validate(document)
        log("instantiate.complete page=\(page.id) rootLayers=\(document.root.layers.count) objects=\(document.objects.count) assets=\(document.assets.count)")
        return document
    }
}

/// 来源接口只负责找到本地包；未来下载来源可复用同一校验器和导入器。
nonisolated protocol DiaryPresetProviding: Sendable {
    func catalog() throws -> DiaryPresetCatalog
}
nonisolated struct DiaryPresetCatalog: Sendable {
    let series: [DiaryPresetSeries]
    let books: [DiaryPresetPackage]
    let issues: [String]
}
nonisolated struct BundleDiaryPresetProvider: DiaryPresetProviding {
    var root: URL? = Bundle.main.url(forResource: "DiaryPresets", withExtension: "bundle")
    func catalog() throws -> DiaryPresetCatalog {
        guard let root else { throw DiaryEditorError.missingResource.logged() }
        SupportLogger.log(level: .info, module: .diaryEditor, message: "preset.catalog.begin root=\(root.path)")
        let series = try JSONDecoder().decode([DiaryPresetSeries].self, from: Data(contentsOf: root.appendingPathComponent("series.json")))
        var books: [DiaryPresetPackage] = []; var issues: [String] = []
        for category in series {
            guard !category.directory.contains("/"), category.directory != ".." else { throw DiaryEditorError.invalidDocument.logged() }
            let folder = root.appendingPathComponent(category.directory)
            let children = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for url in children where url.pathExtension == "diarypreset" {
                do {
                    let manifest = try JSONDecoder().decode(PresetManifest.self, from: Data(contentsOf: url.appendingPathComponent("package.json")))
                    guard manifest.seriesID == category.id, manifest.schemaVersion == 1, manifest.layerSchemaVersion == 1,
                          manifest.format == "TravelDiary.PresetBook", !manifest.pages.isEmpty else { throw DiaryEditorError.invalidDocument.logged() }
                    let package = DiaryPresetPackage(root: url, manifest: manifest)
                    package.log("catalog.discovered series=\(category.id) pages=\(manifest.pages.count) assets=\(manifest.assetTable.count) files=\(manifest.files.count)")
                    books.append(package)
                } catch {
                    SupportLogger.log(level: .error, module: .diaryEditor, message: "preset.catalog.failed package=\(url.path) error=\(String(reflecting: error))")
                    issues.append("\(url.lastPathComponent)：\(error.localizedDescription)")
                }
            }
        }
        let duplicates = Set(Dictionary(grouping: books, by: \.id).filter { $0.value.count > 1 }.keys)
        issues += duplicates.map { "重复预设 ID：\($0)" }
        books.removeAll { duplicates.contains($0.id) }
        books.sort { ($0.manifest.sortOrder ?? 0, $0.id) < ($1.manifest.sortOrder ?? 0, $1.id) }
        SupportLogger.log(level: .info, module: .diaryEditor, message: "preset.catalog.complete books=\(books.count) series=\(series.count) issues=\(issues)")
        return DiaryPresetCatalog(series: series.sorted { $0.sortOrder < $1.sortOrder }, books: books, issues: issues)
    }
}
