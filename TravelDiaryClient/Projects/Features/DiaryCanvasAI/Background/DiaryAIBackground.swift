import UIKit
import Photos

nonisolated struct DiaryAIBackgroundOptions: Codable, Equatable, Sendable {
    var style = "paper"
    var strength = "轻"
    var saveToAlbum = true
    var backgroundOnly = false
}

nonisolated struct DiaryAIBackgroundStyle: Identifiable, Sendable {
    let id: String
    let name: String
    let symbol: String
    let brief: String
    static let all: [Self] = [
        .init(id: "paper", name: "拾景纸刊", symbol: "leaf", brief: "暖白手工纸，细腻纤维，来源景物轮廓轻轻延展至留白，局部自然纸墨消融，不复制真实照片"),
        .init(id: "print", name: "单双色印刷", symbol: "circle.lefthalf.filled", brief: "中性纸底，一到两种来源油墨色，克制网点和局部套印，广阔安静留白"),
        .init(id: "doodle", name: "留白涂鸦", symbol: "pencil.tip", brief: "浅白纸底，少量细黑手绘线条，轻巧微型故事，避开照片和文字，不含品牌或标志"),
        .init(id: "pastel", name: "粉彩纸印", symbol: "scribble.variable", brief: "粉笔蜡笔断线，两至四种柔和来源颜色，细纸片质感，微小符号与大块留白"),
        .init(id: "relic", name: "记忆版画", symbol: "mountain.2", brief: "来源景物浓缩为克制墨块，灰绿深蓝和少量暖色，记忆轮廓，安静现代版画"),
        .init(id: "watercolor", name: "水彩旅行", symbol: "drop", brief: "冷压纸纹、轻透水彩、少量钢笔轮廓、景物边缘自然消融，开阔留白")
    ]
    static func sceneDirection(_ strength: String) -> String {
        switch strength {
        case "浓": return "允许一处较完整、局部细节丰富的来源场景，远近层次清楚；主要色块围绕前景组合，文字区域退让，避免整页同等强烈。"
        case "中": return "以一至两种可辨认的来源景物形成场景骨架，局部有细节，其余自然消融为纸面；连接照片组合，保留明确阅读路径。"
        default: return "用少量可辨认的来源轮廓和柔和色块呼应内容，局部有起伏，保留宽松纸面；避免均匀铺一层无主题的淡纹理。"
        }
    }
    static func resolve(_ id: String) -> Self { all.first { $0.id == id } ?? all[0] }
}

nonisolated struct DiaryAIBackgroundRecord: Codable, Sendable {
    var id = UUID()
    var inputDigest: String
    var designBrief: String?
    var generationPrompt: String?
    var remoteURL: URL?
    var filename: String?
    var verified = false
    var layerID: UUID?
    var albumState = "notSaved"
}

nonisolated struct DiaryAIBackgroundDesign: Sendable { var brief: String; var prompt: String }

@MainActor protocol DiaryAIBackgroundProvider {
    func design(reference: Data, context: String) async throws -> DiaryAIBackgroundDesign
    func generate(reference: Data, prompt: String) async throws -> URL
    func download(_ url: URL) async throws -> Data
    func validate(reference: Data, background: Data) async throws
}

extension DiaryAIBackgroundProvider {
    func design(reference: Data, context: String) async throws -> DiaryAIBackgroundDesign { .init(brief: context, prompt: "连续暖白纸面，淡色自然轮廓，仅在空白区域出现，大片留白。") }
}

@MainActor protocol DiaryAIBackgroundAlbumSaving {
    func save(_ data: Data) async throws
}

@MainActor struct DiaryAIBackgroundAlbum: DiaryAIBackgroundAlbumSaving {
    func save(_ data: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw DiaryAIError.invalid("背景已加入，未保存到相册：请在系统设置中允许添加照片。") }
        try Task.checkCancellation()
        try await PHPhotoLibrary.shared().performChanges(Self.changes(data))
    }
    nonisolated private static func changes(_ data: Data) -> @Sendable () -> Void {
        { PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil) }
    }
}

@MainActor enum DiaryAIBackgroundImaging {
    static func exactSize(_ canvas: CGSize, preferredLongEdge: Int = 1536) throws -> CGSize {
        guard canvas.width.isFinite, canvas.height.isFinite, canvas.width > 0, canvas.height > 0, canvas.width <= 100000, canvas.height <= 100000 else { throw DiaryAIError.invalid("画布尺寸无效") }
        let w = Int(canvas.width.rounded()), h = Int(canvas.height.rounded())
        guard canvas.width.isFinite, canvas.height.isFinite, w > 0, h > 0,
              abs(canvas.width - CGFloat(w)) < 0.0001, abs(canvas.height - CGFloat(h)) < 0.0001 else {
            throw DiaryAIError.invalid("背景生成需要整数画布尺寸，当前画幅无法精确匹配。")
        }
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let g = gcd(w, h), p = w / g, q = h / g
        let k = max(1, min(g, preferredLongEdge / max(p, q)))
        guard Double(p * k) * Double(q * k) <= 40_000_000 else { throw DiaryAIError.invalid("画布精确比例需要过大的背景，请先调整画布尺寸。") }
        return CGSize(width: p * k, height: q * k)
    }
    /// Fit the entire generated image, including its watermark. Small ratio differences use edge paper padding, never cropping or stretching.
    static func prepare(_ data: Data, canvas: CGSize) throws -> Data {
        guard data.count <= 40_000_000, let image = UIImage(data: data), let cg = image.cgImage,
              cg.width > 0, cg.height > 0, Double(cg.width) * Double(cg.height) <= 40_000_000 else { throw DiaryAIError.invalid("生成图片无效或超过资源限制") }
        let target = try exactSize(canvas)
        let ratioError = abs(log((image.size.width / image.size.height) / (target.width / target.height)))
        guard ratioError <= 0.08 else { throw DiaryAIError.invalid("生成图片比例与画布差异过大，已保留排版。可重新生成背景；不会拉伸或裁掉水印。") }
        let scale = min(target.width / image.size.width, target.height / image.size.height)
        let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let result = UIGraphicsImageRenderer(size: target, format: format).image { ctx in
            UIColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(x: (target.width - fitted.width) / 2, y: (target.height - fitted.height) / 2, width: fitted.width, height: fitted.height))
        }
        guard let bytes = result.pngData() else { throw DiaryAIError.invalid("背景编码失败") }
        return bytes
    }
    /// Spatial conditioning only. Original photography is sent to the design/review model, not baked into the image-editing input.
    static func occupancyGuide(canvas: CGSize, objects: [DiaryAIObject]) throws -> Data {
        let scale = min(1, 1536 / max(canvas.width, canvas.height))
        let output = CGSize(width: canvas.width * scale, height: canvas.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return try UIGraphicsImageRenderer(size: output, format: format).image { context in
            UIColor(red: 0.98, green: 0.975, blue: 0.96, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: output))
            context.cgContext.scaleBy(x: scale, y: scale)
            for object in objects where object.visible && object.role != "background" {
                // Bounds already include native transforms; use conservative exclusion margins for text and frames.
                let margin = min(canvas.width, canvas.height) * (object.role == "text" ? 0.018 : 0.01)
                let rect = object.bounds.insetBy(dx: -margin, dy: -margin).intersection(CGRect(origin: .zero, size: canvas))
                guard !rect.isNull else { continue }
                // Soft occupancy fields avoid teaching the image model to reproduce rectangular placeholders.
                let cg = context.cgContext
                cg.saveGState()
                cg.translateBy(x: rect.midX, y: rect.midY)
                cg.scaleBy(x: max(1, rect.width / 2), y: max(1, rect.height / 2))
                let colors = [UIColor(red: 0.94, green: 0.945, blue: 0.93, alpha: 1).cgColor,
                              UIColor(red: 0.98, green: 0.975, blue: 0.96, alpha: 0).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    cg.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0.3, endCenter: .zero, endRadius: 1.4, options: [])
                }
                cg.restoreGState()
            }
        }.jpegData(compressionQuality: 0.9).unwrapBackground()
    }
    static func jpeg(_ data: Data) throws -> Data {
        guard let image = UIImage(data: data) else { throw DiaryAIError.invalid("参考图无法读取") }
        let ratio = min(1, 1536 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return try UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(white: 0.97, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size)); image.draw(in: CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: 0.85).unwrapBackground()
    }
}
private extension Optional where Wrapped == Data {
    func unwrapBackground() throws -> Data { guard let self else { throw DiaryAIError.invalid("参考图编码失败") }; return self }
}
