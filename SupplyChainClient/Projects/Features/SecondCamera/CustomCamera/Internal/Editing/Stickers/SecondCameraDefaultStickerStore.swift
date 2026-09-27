import UIKit

struct SecondCameraStickerItem: Identifiable, Hashable {
    let id: String
    let displayName: String
    let resourceName: String
    let fileExtension: String
}

struct SecondCameraStickerPack {
    let id: String
    let title: String
    let author: String?
    let stickers: [SecondCameraStickerItem]
}

private struct SecondCameraEditorPackManifest: Decodable {
    struct Item: Decodable {
        let id: String
        let name: String
        let file: String
    }

    let id: String
    let title: String
    let author: String?
    let items: [Item]
}

@MainActor
final class SecondCameraDefaultStickerStore: @unchecked Sendable {

    static let shared = SecondCameraDefaultStickerStore()

    private(set) var packs: [SecondCameraStickerPack] = []
    private var imageCache: [String: UIImage] = [:]

    private init() {
        loadPacks()
    }

    func stickerInfo(for item: SecondCameraStickerItem, packId: String) -> SecondCameraStickerInfo {
        SecondCameraStickerInfo(packId: packId, stickerId: item.id)
    }

    func image(for stickerInfo: SecondCameraStickerInfo) -> UIImage? {
        let key = stickerInfo.asKey()
        if let cached = imageCache[key] {
            return cached
        }
        guard let item = findItem(stickerInfo: stickerInfo) else { return nil }
        guard let image = loadImage(named: item.resourceName) else { return nil }
        imageCache[key] = image
        return image
    }

    func metadata(for stickerInfo: SecondCameraStickerInfo) -> SecondCameraInstalledStickerMetadata? {
        guard let image = image(for: stickerInfo),
              let data = image.pngData() else {
            return nil
        }
        return SecondCameraInstalledStickerMetadata(data: data)
    }

    private func findItem(stickerInfo: SecondCameraStickerInfo) -> SecondCameraStickerItem? {
        for pack in packs where pack.id == stickerInfo.packId {
            return pack.stickers.first { $0.id == stickerInfo.stickerId }
        }
        return nil
    }

    private func loadPacks() {
        guard let url = bundle.url(forResource: "second_camera_pack", withExtension: "json", subdirectory: "SecondCameraStickers/default") else {
            packs = builtInPack()
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let manifest = try JSONDecoder().decode(SecondCameraEditorPackManifest.self, from: data)
            let stickers = manifest.items.map { item in
                let base = (item.file as NSString).deletingPathExtension
                let ext = (item.file as NSString).pathExtension
                return SecondCameraStickerItem(
                    id: item.id,
                    displayName: item.name,
                    resourceName: base,
                    fileExtension: ext.isEmpty ? "png" : ext,
                )
            }
            packs = [SecondCameraStickerPack(id: manifest.id, title: manifest.title, author: manifest.author, stickers: stickers)]
        } catch {
            packs = builtInPack()
        }
    }

    private func builtInPack() -> [SecondCameraStickerPack] {
        let stickers = (1...6).map { index in
            SecondCameraStickerItem(
                id: "builtin_\(index)",
                displayName: "Sticker \(index)",
                resourceName: "second_camera_sticker_\(String(format: "%03d", index))",
                fileExtension: "png",
            )
        }
        return [SecondCameraStickerPack(id: "second-camera-default", title: SecondCameraEditorL10n.Editor.sticker, author: "SecondCamera", stickers: stickers)]
    }

    private var bundle: Bundle { .main }

    private func loadImage(named name: String) -> UIImage? {
        if let image = UIImage(named: name) {
            return image
        }
        if let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "SecondCameraStickers/default"),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            return image
        }
        return renderPlaceholder(index: name)
    }

    private func renderPlaceholder(index: String) -> UIImage? {
        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.clear.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let hash = abs(index.hashValue)
            let hue = CGFloat(hash % 360) / 360.0
            UIColor(hue: hue, saturation: 0.55, brightness: 0.95, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 28, y: 28, width: 200, height: 200))
        }
    }
}
