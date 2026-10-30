import Foundation

extension DiaryPhotoFrameCatalog {
    enum Style: String { case lightPaper, botanical }
    static func select(for sizes: [CGSize], style: Style = .lightPaper) -> [Item] {
        sizes.enumerated().map { index, size in
            generated(seed: index + 1, ratio: Double(size.width / max(1, size.height)))
        }
    }
}
