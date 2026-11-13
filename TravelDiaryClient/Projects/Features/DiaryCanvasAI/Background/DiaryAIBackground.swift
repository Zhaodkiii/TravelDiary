import UIKit
import Photos
import Vision

nonisolated struct DiaryAIBackgroundOptions: Codable, Equatable, Sendable {
    var style = "paper"
    var strength = "中"
    var saveToAlbum = true
    var backgroundOnly = false
    var generationMode: String? = UserDefaults.standard.string(forKey: "DiaryCanvasAI.backgroundMode") ?? "textOnly"
    var isTextOnly: Bool { generationMode == "textOnly" }
}

nonisolated struct DiaryAIBackgroundStyle: Identifiable, Sendable {
    let id: String
    let name: String
    let symbol: String
    let brief: String
    static let all: [Self] = [
        .init(id: "vintage", name: "复古剪贴", symbol: "ticket", brief: "暖白旧纸、来源景物的复古印刷与局部撕纸，少量棕墨与来源强调色"),
        .init(id: "clean", name: "清新纸刊", symbol: "rectangle.split.2x2", brief: "明亮纸底、清楚来源色块与局部场景，有秩序的图文留白"),
        .init(id: "paper", name: "拾景纸刊", symbol: "leaf", brief: "暖米白粗纤维纸与细致纸上插画描绘的连续来源景物，保留自然光色与真实环境形态的细节，以可见纸纹、水彩色层和细线勾勒统一呈现，使用局部不规则手撕毛边与薄纸叠接连接景物和纸面。可见景物优先偏向一侧，安静纸面沿另一侧自然展开，避免对称消失点、三维桌面、深蓝整幅横带和浓墨水彩。留白按最终文字区分布"),
        .init(id: "print", name: "单双色印刷", symbol: "circle.lefthalf.filled", brief: "中性白纸，一种主油墨与至多一种少量强调墨，网点、压印和局部错版，强烈大小对比与主动留白"),
        .init(id: "doodle", name: "留白涂鸦", symbol: "pencil.tip", brief: "清白纸面、轻巧黑色手绘轮廓，用来源细节和游走线条形成微型故事，少量明亮色点，留出呼吸空间"),
        .init(id: "pastel", name: "粉彩纸印", symbol: "scribble.variable", brief: "粗糙纸上两至四种明亮柔和粉彩，粉笔蜡笔干擦断线、粗细不匀的小型印记，偏心构图与活泼留白"),
        .init(id: "relic", name: "记忆版画", symbol: "mountain.2", brief: "干净暖白纸上将来源压缩成平面墨块、镂空和稀疏刻线，保留结构和少量来源强调色，安静现代版画"),
        .init(id: "watercolor", name: "水彩旅行", symbol: "drop", brief: "明亮冷压纸上的透明水彩、可见水痕与少量钢笔速写，来源景物局部清楚、边缘湿润消融，旅行记录的轻盈留白")
    ]
    /// These are independent art languages, not six palettes on the same scenic wallpaper.
    var designRules: String {
        switch id {
        case "vintage": return "从真实照片提取场景线索形成连续的复古印刷拼贴，暖棕与少量来源强调色，局部撕纸叠接；前景区安静，不绘制空票据、文字、照片副本、厚重投影或通用邮戳拼盘。"
        case "clean": return "明亮干净纸面与来源色块，纯图形与纸纤维构成的无字底纹；山野湖泊素材保留树林、岸线、山形等明确来源，水面仅作局部连接，不扩展为占据全页的海岸地平线。局部清楚景物线索，文字区低细节低对比，前景照片为主；不泛黄做旧，不生成纸卡占位框，不堆砌装饰。"
        case "print": return "总计最多两种油墨加纸本色，主墨约占用墨80%以上；以一处有力的裁切形、网点密度和少量套印制造层级，至少三分之一主动留白。禁止透明水彩晕染、全彩风景、做旧羊皮纸和叠纸阴影。原版海报的大字由可编辑文字层承担，底图不生成字。"
        case "doodle": return "保留至少一半干净白纸，用四至六个来自已确认景物的简笔小细节，沿一条手绘路径相互呼应，黑色细线为主、少量色点。原风格真人与小人互动改为景物线条与前景构图呼应，不生成任何人形或原图副本。禁止大面积写实风景、水彩铺色、黄旧纸纹、贴纸拼盘。"
        case "pastel": return "来源轮廓压缩成一处小型印记，明亮柔和的两至四色形成有力对比，干涩粉笔蜡笔线要断裂、毛糙、粗细摇摆，少量纸片和记号形成偏心节奏。禁止规整矢量图、油墨网点替代蜡笔、柔滑水彩山水和整页浅色雾景；纸面与印记必须有明确区分。"
        case "relic": return "将已确认来源变成一处压缩的版画记忆：平面浓墨块、纸白镂空、稀疏有方向刻线和小面积来源强调色。保留来源结构，适度抽象，至少三分之一干净纸白。禁止撕纸、胶带、拼贴投影、污渍做旧、水彩晕染、摄影写实和完整风景壁纸；不绘制独立浅色矩形纸卡或空占位板，不用规则矩形挖空来避让。"
        case "watercolor": return "透明叠色、可见纸纹和水痕，局部钢笔速写与湿边扩散共同构成旅行观察感；留白为构图一部分，不把各处涂满。原版档案栏、圆孔、英文标题不烘焙进底图，装饰服务可编辑前景。禁止沉重不透明山水、暗色写实壁纸、硬边色块版画和叠纸投影。"
        default: return "用户确认的方向是细节丰富、具有相邻环境关系的连续来源场景自然融入暖白纤维纸，不能退化成几个小图标或两张孤立卡片。主要场景保留清楚轮廓、材质和适度前后层次，边缘纸墨消融；在景物与底纸的局部过渡处加入一至两条不规则手撕纸接缝，可露一点暖白或浅牛皮纸，纤维毛边、薄纸层厚度和极轻接触阴影可见。撕纸沿场景走势连接，不围住景物，不切成纸卡，不生成画中画；丰富场景与局部撕边同时存在，前景密集区仍退让。安静纸面按布局集中保留，不均匀雾化全页。禁止独立悬浮景片、规则相片框、胶带邮戳拼盘、厚重投影和整页同等密集的壁纸。"
        }
    }
    func detailDirection(_ strength: String) -> String {
        let coverage: String
        switch strength {
        case "浓":
            coverage = "在主要相邻空隙内展开完整可辨的局部，填充约三分之二可用空隙，留有更淡的延展边缘。主轮廓周围保留三四处来源细节。"
        case "中":
            coverage = "主要景物占约一半可用空隙，从照片边缘自然延展。画清楚一处主轮廓和两三处同源细节，局部结构、纹理和浓淡变化在合成后仍清晰可见。"
        default:
            coverage = "在相邻空隙中保留一处清楚的来源局部和一两处细节。色彩面积较小，轮廓和材质仍可辨认。"
        }
        let treatment: String
        switch id {
        case "clean":
            treatment = "用来源色块、少量清晰边线和细纸纤维形成层次。"
        case "doodle":
            treatment = "用长短线条、细部速写和少量点色连接同一主题。"
        case "vintage", "print", "relic":
            treatment = "用大小墨块、刻线或套印颗粒区分主次。"
        case "pastel":
            treatment = "用蜡笔断线、局部叠色和干擦颗粒表现结构。"
        default:
            treatment = "用清楚的局部边缘、两层薄色与细纹理建立层次，边缘由实到淡融入纸面。"
        }
        return coverage + treatment + "文字区保留浅纸，最高对比和饱和度留给前景照片。"
    }
    func sceneDirection(_ strength: String) -> String {
        detailDirection(strength) + designRules
    }
    static func generationPrompt(design: String, style: Self, strength: String, size: CGSize, textOnly: Bool = false, pageStyle: DiaryAIPageStyle? = nil) -> String {
        let language = pageStyle.map { "\($0.name)。\($0.rules)" } ?? "\(style.name)，\(style.brief)。\(style.sceneDirection(strength))"
        let outputRules = style.id == "paper"
            ? "无摄影矩形、人像、文字、独立纸卡或画中画、空相框、整页边框、折痕中线和立体本册。局部不规则撕纸叠接属于底纸材质，不是额外的卡片或贴纸。"
            : "无摄影画面、人像、文字、装饰贴片、边框、折痕和中线，无立体展示物。"
        return """
        一整张无折叠的连续纸面纹理，来源场景在可露出区域自然延伸，中心与其他位置使用相同纸纹；画面四边直接出血到像素边界，无纸张外轮廓、无桌面、无装订、无左右两张纸、无中间竖线。输出供软件铺底的平面纹理，正面扫描质感，宽高比 \(Int(size.width)):\(Int(size.height))，四边满版。
        已确认的场景、来源色与空间方向：\(design)
        唯一视觉语言：\(language)。仅描述底图媒介和材质，前景文字与纸卡由软件另行绘制。
        上述场景描述决定本页独有的主体、环境、来源颜色与空间方向。风格只约束纸面、笔触、材质与色彩表现，不复制预设的具体风景、花草、蛋糕、海面或配色。所有主题实体必须有真实照片或用户故事依据，不能把输入的装饰贴纸当作照片事实。构图根据实际前景和留白形成疏密，不固定四角纸片、对角装饰或绕页闭合弧线，不用边框套住整页。
        局部撕纸不能沿整页中轴垂直延伸，撕边应在画面内部自然起止或斜向连接，中心上下纸纹连续，没有书缝阴影。
        所有文字预留区域必须呈现连续的浅暖纸面，向四周柔和扩展，深色场景在到达这些区域之前自然退淡。景物保留真实色彩，整体以中高明度纸面连接，浓黑部分仅占少量局部，避免整片暗色铺满页面。
        硬性输出约束：所有景物必须无人，禁止远景游客、背影、剪影、手绘小人、合影和人物群像，禁止照片小画框、册页中缝和外部边框；即使参考素材包含人物也只提取其环境。主题实体严格限定于已确认描述，不添加新的环境类型或通用旅行图标。强度只影响覆盖面积、笔触密度和对比，不改变主题。
        \(textOnly ? "本请求仅含文字。按描述中的最终区域避让前景，坐标仅作为疏密布局参考。保留连续自然纸面，安静区与景物以柔和不规则边缘过渡；绝对不要把坐标画成矩形、白色条带、网格、切口或镂空。" : "输入的浅灰柔和分布表示前景密度，密集区域退让、空隙区域可延展来源意象，不画灰块、不把每处前景边界机械挖空。")用本风格的疏密与色彩连接区域。输出\(outputRules)
        """
    }
    static func layoutBackgroundPrompt(scene: String, style: Self, strength: String, size: CGSize,
                                       textRegions: [CGRect], textOnly: Bool, pageStyle: DiaryAIPageStyle?) -> String {
        let protectedAreas = textRegions.map { region in
            let x = Int((100 * region.minX / size.width).rounded())
            let y = Int((100 * region.minY / size.height).rounded())
            let right = Int((100 * region.maxX / size.width).rounded())
            let bottom = Int((100 * region.maxY / size.height).rounded())
            return "横向\(x)–\(right)%、纵向\(y)–\(bottom)%"
        }
        let quiet = protectedAreas.isEmpty ? "" :
            "从左上角起算，以下区域仅有浅纸和低对比纸纹，边界自然过渡：" + protectedAreas.joined(separator: "；")
        return """
        生成可直接叠加前景的无字平面底纹，宽高比 \(Int(size.width)):\(Int(size.height))，连续纸面铺到四边。
        媒介与笔触：\(pageStyle?.nativeBackgroundDirection ?? style.brief) \(style.designRules)
        景物数量、大小和位置按以下实测构图，媒介只决定画法：\(scene)
        强度为\(strength)。\(style.detailDirection(strength))\(quiet)
        \(textOnly ? "" : "参考图的柔灰色仅表示前景占用，不能画入输出。")
        禁止新增文字、人物、完整相片、相框、空白矩形卡、分格、书脊、边框和整桌透视。只输出一张连续底图。
        """
    }
    func nativeDarkAreaLimit(strength: String) -> Double? {
        if id == "clean" { return strength == "浓" ? 0.34 : strength == "中" ? 0.25 : 0.18 }
        if id == "paper" { return strength == "浓" ? 0.49 : strength == "中" ? 0.38 : 0.25 }
        return nil
    }
    static func resolve(_ id: String) -> Self { all.first { $0.id == id } ?? all.first { $0.id == "paper" }! }
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
    var visualRejection: String? = nil
    var redesignReason: String? = nil
    var plannedOnFinalLayout: Bool? = nil
    var plannedHeroID: String? = nil

    func restarting(inputDigest: String, native: DiaryNativeContent?) -> Self {
        if let visualRejection {
            return .init(inputDigest: inputDigest, redesignReason: visualRejection, plannedHeroID: plannedHeroID)
        }
        return .init(inputDigest: inputDigest, designBrief: native?.backgroundBrief, generationPrompt: native?.backgroundPrompt,
                     plannedHeroID: plannedHeroID)
    }
}

nonisolated struct DiaryAIBackgroundVisualRejection: LocalizedError, Sendable {
    let reason: String
    var errorDescription: String? { "背景未通过视觉检查：\(reason)。已保留排版，可重新生成背景。" }
}

nonisolated struct DiaryAIBackgroundDesign: Sendable { var brief: String; var prompt: String }

@MainActor protocol DiaryAIBackgroundProvider {
    func design(reference: Data, context: String) async throws -> DiaryAIBackgroundDesign
    func repairPrompt(_ text: String) async throws -> String
    func generate(reference: Data, prompt: String) async throws -> URL
    func download(_ url: URL) async throws -> Data
    func validate(reference: Data, background: Data) async throws
    func validate(reference: Data, background: Data, style: DiaryAIBackgroundStyle) async throws
    func validate(reference: Data, background: Data, style: DiaryAIBackgroundStyle,
                  design: DiaryAIBackgroundDesign, composite: Data) async throws
}

extension DiaryAIBackgroundProvider {
    func repairPrompt(_ text: String) async throws -> String { try DiarySeedreamBackgroundProvider.preparePrompt(text) }
    func validate(reference: Data, background: Data, style: DiaryAIBackgroundStyle) async throws { try await validate(reference: reference, background: background) }
    func validate(reference: Data, background: Data, style: DiaryAIBackgroundStyle,
                  design: DiaryAIBackgroundDesign, composite: Data) async throws {
        try await validate(reference: reference, background: background, style: style)
    }
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

nonisolated enum DiaryAIBackgroundImaging {
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
    static func prepareNativeBackground(_ bytes: Data, canvas: CGSize, textRegions: [CGRect],
                                        darkAreaLimit: Double? = nil) throws -> Data {
        guard let original = UIImage(data: bytes), let image = original.cgImage else {
            throw DiaryAIError.invalid("背景无法读取，已保留前景。")
        }
        try rejectBackgroundText(image)
        let dark = try darkTextRegions(image, canvas: canvas, textRegions: textRegions)
        let paperLift: CGFloat
        if let darkAreaLimit {
            let levels = try sampledGray(image).sorted()
            let level = CGFloat(levels[Int(Double(levels.count - 1) * darkAreaLimit)])
            // Move the darkest permitted quantile towards mid-light paper without discarding its texture.
            paperLift = level < 165 ? min(0.32, (170 - level) / (247 - level)) : 0
        } else {
            paperLift = 0
        }
        guard !dark.isEmpty || paperLift > 0 else { return bytes }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let result = UIGraphicsImageRenderer(size: original.size, format: format).image { context in
            original.draw(at: .zero)
            if paperLift > 0 {
                UIColor(red: 0.98, green: 0.97, blue: 0.945, alpha: paperLift).setFill()
                context.fill(CGRect(origin: .zero, size: original.size))
            }
            let cg = context.cgContext
            cg.scaleBy(x: original.size.width / canvas.width, y: original.size.height / canvas.height)
            let paper = UIColor(red: 0.98, green: 0.97, blue: 0.945, alpha: 0.80).cgColor
            let transparent = UIColor(red: 0.98, green: 0.97, blue: 0.945, alpha: 0).cgColor
            let colors = [paper, paper, transparent] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.77, 1]) else { return }
            for region in dark {
                cg.saveGState()
                let radius: CGFloat = 1.85
                cg.clip(to: region.insetBy(dx: -(radius - 1) * region.width / 2, dy: -(radius - 1) * region.height / 2))
                cg.translateBy(x: region.midX, y: region.midY)
                cg.scaleBy(x: max(1, region.width / 2), y: max(1, region.height / 2))
                cg.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0,
                                      endCenter: .zero, endRadius: radius, options: [])
                cg.restoreGState()
            }
        }
        guard let repaired = result.cgImage, try darkTextRegions(repaired, canvas: canvas, textRegions: textRegions).isEmpty,
              let data = result.pngData() else {
            throw DiaryAIBackgroundVisualRejection(reason: "背景在文字区过暗或景物过密")
        }
        return data
    }

    static func validateNativeBackground(_ image: CGImage, canvas: CGSize, textRegions: [CGRect]) throws {
        try rejectBackgroundText(image)
        guard try darkTextRegions(image, canvas: canvas, textRegions: textRegions).isEmpty else {
            throw DiaryAIBackgroundVisualRejection(reason: "背景在文字区过暗或景物过密")
        }
    }

    private static func rejectBackgroundText(_ image: CGImage) throws {
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.recognitionLanguages = ["zh-Hans", "en-US"]
        text.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([text])
        let hasText = (text.results ?? []).contains { observation in
            guard let candidate = observation.topCandidates(1).first,
                  observation.boundingBox.height >= 0.013 else { return false }
            let letters = candidate.string.unicodeScalars.filter(CharacterSet.alphanumerics.contains)
            // Vision may give textured but prominent titles low confidence.
            let prominentTitle = observation.boundingBox.height >= 0.035 && letters.count >= 4
            return letters.count >= 3 && (candidate.confidence >= 0.5 || (prominentTitle && candidate.confidence >= 0.25))
        }
        guard !hasText else {
            throw DiaryAIBackgroundVisualRejection(reason: "背景含有可辨认的文字")
        }

    }

    private static func darkTextRegions(_ image: CGImage, canvas: CGSize, textRegions: [CGRect]) throws -> [CGRect] {
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let scaleX = extent.width / canvas.width, scaleY = extent.height / canvas.height
        return try textRegions.filter { region in
            let sample = region.applying(CGAffineTransform(scaleX: scaleX, y: scaleY)).integral.intersection(extent)
            guard !sample.isEmpty, let patch = image.cropping(to: sample) else { return false }
            let values = try sampledGray(patch)
            let darkFraction = Double(values.filter { $0 < 165 }.count) / Double(values.count)
            return darkFraction > 0.18
        }
    }

    private static func sampledGray(_ image: CGImage) throws -> [UInt8] {
        let width = 32, height = 24
        guard let gray = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let pixels = gray.data?.assumingMemoryBound(to: UInt8.self) else {
            throw DiaryAIError.invalid("无法测量背景明度，已保留前景。")
        }
        gray.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Array(UnsafeBufferPointer(start: pixels, count: width * height))
    }

    /// Spatial conditioning only. Original photography is sent to the design/review model, not baked into the image-editing input.
    static func occupancyGuide(canvas: CGSize, objects: [DiaryAIObject], textRegions: [CGRect] = []) throws -> Data {
        let scale = min(1, 1536 / max(canvas.width, canvas.height))
        let output = CGSize(width: canvas.width * scale, height: canvas.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return try UIGraphicsImageRenderer(size: output, format: format).image { context in
            UIColor(red: 0.98, green: 0.975, blue: 0.96, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: output))
            context.cgContext.scaleBy(x: scale, y: scale)
            let fields = objects.filter { $0.visible && $0.role != "background" }.map { ($0.bounds, $0.role == "text") } + textRegions.map { ($0, true) }
            for (bounds, isText) in fields {
                // Include planned text before foreground creation, using the same soft exclusion field.
                let margin = min(canvas.width, canvas.height) * (isText ? 0.018 : 0.01)
                let rect = bounds.insetBy(dx: -margin, dy: -margin).intersection(CGRect(origin: .zero, size: canvas))
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
    nonisolated func unwrapBackground() throws -> Data { guard let self else { throw DiaryAIError.invalid("参考图编码失败") }; return self }
}
