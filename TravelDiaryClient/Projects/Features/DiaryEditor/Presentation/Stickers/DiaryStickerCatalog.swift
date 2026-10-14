import UIKit

/// 稳定 ID 用于收藏和最近使用；资源只在用户选中后复制进手帐。
struct DiaryStickerItem: Identifiable {
    let id: String
    let title: String
    let category: String
    let symbol: String?
    let resource: String?
    let color: UIColor

    func image() -> UIImage? {
        if let resource {
            if let url = Bundle.main.url(forResource: resource, withExtension: "png", subdirectory: "SecondCameraStickers/default")
                ?? Bundle.main.url(forResource: resource, withExtension: "png") {
                return UIImage(contentsOfFile: url.path)
            }
            return UIImage(named: resource)
        }
        guard let symbol, let image = UIImage(systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 240, weight: .regular)) else { return nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 320, height: 320), format: format).image { _ in
            let ratio = min(280 / image.size.width, 280 / image.size.height)
            let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
            image.withTintColor(color, renderingMode: .alwaysOriginal).draw(in:
                CGRect(x: (320 - size.width) / 2, y: (320 - size.height) / 2, width: size.width, height: size.height))
        }
    }
}

/// 本地目录集中维护；后续云端目录可映射到同一选择与导入流程。
enum DiaryStickerCatalog {
    static let categories = ["全部", "最近", "收藏", "形状", "旅行", "自然", "庆祝", "内置贴纸"]
    static var items: [DiaryStickerItem] {
        let groups: [(String, UIColor, [(String, String)])] = [
            ("形状", .systemPink, [("爱心", "heart.fill"), ("星星", "star.fill"), ("圆形", "circle.fill"),
                ("方形", "square.fill"), ("三角形", "triangle.fill"), ("菱形", "diamond.fill"), ("对话气泡", "bubble.left.fill")]),
            ("旅行", .systemBlue, [("飞机", "airplane"), ("汽车", "car.fill"), ("帐篷", "tent.fill"),
                ("山峰", "mountain.2.fill"), ("地图", "map.fill"), ("相机", "camera.fill"), ("行李箱", "suitcase.fill")]),
            ("自然", .systemGreen, [("太阳", "sun.max.fill"), ("月亮", "moon.fill"), ("云朵", "cloud.fill"),
                ("树叶", "leaf.fill"), ("树木", "tree.fill"), ("雪花", "snowflake")]),
            ("庆祝", .systemOrange, [("礼物", "gift.fill"), ("气球", "balloon.fill"), ("彩纸", "party.popper.fill"),
                ("生日蛋糕", "birthday.cake.fill"), ("闪光", "sparkles"), ("笑脸", "face.smiling.fill")])
        ]
        return groups.flatMap { category, color, entries in
            entries.map { title, symbol in
                DiaryStickerItem(id: "symbol.\(symbol)", title: title, category: category, symbol: symbol, resource: nil, color: color)
            }
        } + (1...6).map { index in
            DiaryStickerItem(id: "builtin.\(index)", title: "趣味贴纸 \(index)", category: "内置贴纸", symbol: nil,
                             resource: String(format: "second_camera_sticker_%03d", index), color: .clear)
        }
    }
}
