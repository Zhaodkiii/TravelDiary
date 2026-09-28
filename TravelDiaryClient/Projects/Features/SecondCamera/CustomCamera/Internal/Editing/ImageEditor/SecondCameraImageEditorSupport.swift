//
// Signal Camera - ImageEditor support types
//

import UIKit

public struct SecondCameraEditorOrderedDictionary<Key: Hashable, Value> {
    private var storage: [(Key, Value)] = []

    public init() {}

    public subscript(key: Key) -> Value? {
        get { storage.first { $0.0 == key }?.1 }
        set {
            if let newValue {
                if let index = storage.firstIndex(where: { $0.0 == key }) {
                    storage[index] = (key, newValue)
                } else {
                    storage.append((key, newValue))
                }
            } else {
                storage.removeAll { $0.0 == key }
            }
        }
    }

    public var count: Int { storage.count }
    public var orderedKeys: [Key] { storage.map(\.0) }
    public var orderedValues: [Value] { storage.map(\.1) }

    public mutating func append(key: Key, value: Value) {
        storage.append((key, value))
    }

    public mutating func replace(key: Key, value: Value) {
        if let index = storage.firstIndex(where: { $0.0 == key }) {
            storage[index] = (key, value)
        } else {
            storage.append((key, value))
        }
    }

    public mutating func remove(key: Key) {
        storage.removeAll { $0.0 == key }
    }
}

public struct SecondCameraInstalledStickerMetadata {
    private let data: Data

    public init(data: Data) {
        self.data = data
    }

    public func readStickerData() throws -> Data { data }
}

public enum SecondCameraStickerManager {
    public static func stickerImage(for stickerInfo: SecondCameraStickerInfo, width: CGFloat) -> UIImage? {
        guard let image = SecondCameraDefaultStickerStore.shared.image(for: stickerInfo) else { return nil }
        guard width > 0, image.size.width > width else { return image }
        let scale = width / image.size.width
        let targetSize = CGSize(width: width, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    public static func installedStickerMetadataWithSneakyTransaction(stickerInfo: SecondCameraStickerInfo) -> SecondCameraInstalledStickerMetadata? {
        SecondCameraDefaultStickerStore.shared.metadata(for: stickerInfo)
    }
}

