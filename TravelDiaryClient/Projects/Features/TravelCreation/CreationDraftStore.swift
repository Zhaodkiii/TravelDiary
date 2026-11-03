import Foundation
import CryptoKit
import ImageIO

/// One manifest per account draft; original bytes are durable, thumbnails are rebuildable.
actor CreationDraftStore {
    let owner: String
    let root: URL
    init(owner: String, paths: StoragePaths = .system) {
        self.owner = owner
        root = paths.account(owner).appendingPathComponent("CreationDrafts", isDirectory: true)
    }
    nonisolated func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func list() throws -> [CreationDraft] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).compactMap { url in
            guard let bytes = try? Data(contentsOf: url.appendingPathComponent("manifest.json")),
                  let draft = try? JSONDecoder().decode(CreationDraft.self, from: bytes), draft.owner == owner else { return nil }
            return draft
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
    func save(_ draft: CreationDraft) throws {
        guard draft.owner == owner, draft.schemaVersion == 1 else { throw DiaryEditorError.invalidDocument }
        let folder = directory(draft.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(draft).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
    }
    func load(_ id: UUID) throws -> CreationDraft {
        let value = try JSONDecoder().decode(CreationDraft.self, from: Data(contentsOf: directory(id).appendingPathComponent("manifest.json")))
        guard value.owner == owner, value.schemaVersion == 1 else { throw DiaryEditorError.invalidDocument }
        return value
    }
    func add(_ bytes: Data, to draft: CreationDraft, name: String, sticker: Bool = false, material: DiaryMaterialSource? = nil) throws -> CreationDraft {
        guard draft.owner == owner, let source = CGImageSourceCreateWithData(bytes as CFData, nil), CGImageSourceGetCount(source) > 0 else { throw DiaryEditorError.invalidImage }
        guard draft.assets.filter({ $0.isSticker == sticker }).count < (sticker ? 12 : 30) else { throw DiaryAIError.invalid(sticker ? "最多保留 12 枚贴纸。" : "素材篮最多保留 30 张照片。") }
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard !draft.assets.contains(where: { $0.digest == hash && $0.isSticker == sticker }) else { throw DiaryAIError.invalid("这张素材已经在素材篮里。") }
        var next = draft
        let nameOnDisk = UUID().uuidString + ".image"
        let folder = directory(draft.id).appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try bytes.write(to: folder.appendingPathComponent(nameOnDisk), options: .atomic)
        next.assets.append(.init(filename: nameOnDisk, digest: hash, name: name, isSticker: sticker, material: material))
        next.updatedAt = Date()
        try save(next)
        return next
    }
    func data(_ asset: CreationAsset, draftID: UUID) throws -> Data {
        let folder = directory(draftID).appendingPathComponent("assets")
        return try Data(contentsOf: StoragePaths.resolve(asset.filename, within: folder))
    }
    func thumbnail(_ asset: CreationAsset, draftID: UUID) throws -> Data? {
        let bytes = try data(asset, draftID: draftID)
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 500] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
    func retainRemaining(_ draft: CreationDraft) throws {
        let remaining = draft.assets.filter { !$0.isSticker && !$0.included }
        guard !remaining.isEmpty, !FileManager.default.fileExists(atPath: directory(draft.remainingDraftID).appendingPathComponent("manifest.json").path) else { return }
        var next = CreationDraft(owner: owner, targetBookID: draft.targetBookID)
        next.id = draft.remainingDraftID
        next.design = draft.design
        let folder = directory(next.id).appendingPathComponent("assets")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for var asset in remaining {
            let bytes = try data(asset, draftID: draft.id)
            try bytes.write(to: StoragePaths.resolve(asset.filename, within: folder), options: .atomic)
            asset.included = true; next.assets.append(asset)
        }
        try save(next)
    }
    func remove(_ id: UUID) throws { try StorageActivity.shared.exclusively(directory(id)) { try FileManager.default.removeItem(at: directory(id)) } }
    func removeAsset(_ id: UUID, from draft: CreationDraft) throws -> CreationDraft {
        var next = draft
        let old = next.assets.first { $0.id == id }
        next.assets.removeAll { $0.id == id }
        if next.heroID == id { next.heroID = nil }
        try save(next)
        if let old { try? FileManager.default.removeItem(at: StoragePaths.resolve(old.filename, within: directory(draft.id).appendingPathComponent("assets"))) }
        return next
    }
}
