import Foundation

extension DiaryPhotoFrameCatalog {
    enum Style: String { case lightPaper, botanical }
    static func select(for sizes: [CGSize], style: Style = .lightPaper) -> [Item] {
        sizes.enumerated().map { index, size in
            // 默认导入：米色手撕纸，撕边 80%、边宽 4%、阴影 100%。
            generated(style: 0, roughness: 0.8, width: 0.04, shade: 1, color: 1,
                      seed: index + 1, ratio: Double(size.width / max(1, size.height)))
        }
    }
}
