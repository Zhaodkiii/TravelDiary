import Foundation

struct DiaryAIStyle: Identifiable {
    let id: String
    let name: String
    let detail: String
    let rules: String
    var imageName: String { "AIStyle-" + (["editorial": "story", "headline": "lively", "notes": "vintage"][id] ?? id) }
}
enum DiaryAIStyleLibrary {
    static let styles: [DiaryAIStyle] = [
        .init(id: "editorial", name: "纸刊叙事", detail: "主标题 · 引题 · 照片旁注", rules: "安排主标题、引题、两处与照片对应的旁注和结语，约50至100字；标题大、正文轻，纸卡最多两种，保留照片主次与留白，不写无依据日期地名。"),
        .init(id: "headline", name: "大字主题", detail: "醒目短标题 · 手写补记", rules: "4至10字醒目短标题主动按语义断行，正文约标题字号一半；加引题、照片旁注和短结语，标题可用马善政，正文从可用字体中选清楚的手写体；少量强调色和手撕纸承托，不把每句话都做成大标题。"),
        .init(id: "notes", name: "旅行札记", detail: "记事段落 · 票根标签", rules: "主标题加2至3处照片记录、短结语，总量约60至110字；照片旁注写可见细节，标签短、段落轻。沿用默认blueTape或选已有牛皮纸、划线纸组合，同页最多两种纸卡，避免装饰压过照片。"),

        .init(id: "mountain", name: "山野手记", detail: "深绿手写 · 大小错落", rules: "主照片与小照片形成大小对比，深绿标题，手写短句，装饰依附照片边缘，不规则但有呼吸感。"),
        .init(id: "vintage", name: "复古票根", detail: "暖纸色 · 旅行记事", rules: "暖棕文字，标签式旁注，轻微叠贴和倾斜，保留旅行记事感。"),
        .init(id: "minimal", name: "清爽留白", detail: "少装饰 · 明确主次", rules: "留出大面积空白，明确一张主照片，文字简洁，少量装饰，不平均分配所有照片。"),
        .init(id: "gentle", name: "温柔日常", detail: "柔和配色 · 细腻短句", rules: "柔和暖色、圆润手写，轻量纸片和少量旋转，温暖克制。"),
        .init(id: "lively", name: "活力出游", detail: "轻快倾斜 · 尺寸对比", rules: "明显但不夸张的大小对比，轻微倾斜，明快文字，保留留白和阅读顺序。"),
        .init(id: "story", name: "照片故事", detail: "主照片 · 纪实旁注", rules: "主照片突出人物，局部旁注连接照片，少装饰，叙事文字不虚构日期人物和经历。")
    ]
    static func brief(_ name: String) -> String {
        if name == "保持当前风格" { return "延续现有字体、配色、装饰与背景；不强行改变主题。" }
        if name == "自动匹配" { return styles.map { "\($0.name)：\($0.rules)" }.joined(separator: "\n") + "\n选择适合当前图片的风格，在总结中说明。" }
        return styles.first { $0.name == name }?.rules ?? "延续现有风格"
    }
}

/// Orthogonal, versioned choices. Legacy requests keep their original style rules.
nonisolated enum DiaryAILayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, hero, story, headline, collage, editorial
    var id: String { rawValue }
    var name: String { switch self {
    case .automatic: "自动推荐"; case .hero: "主照突出"; case .story: "旅行故事"
    case .headline: "大字主题"; case .collage: "随手拼贴"; case .editorial: "纸刊记录"
    } }
    var detail: String { switch self {
    case .automatic: "按照片数量与内容安排主次"
    case .hero: "一张主照，其余照片围绕它展开"
    case .story: "照片分组，旁注串起旅程"
    case .headline: "醒目短标题，照片围绕主题展开"
    case .collage: "大小错落、轻微倾斜与叠贴"
    case .editorial: "清楚分栏，照片与记事相互呼应"
    } }
    var rules: String { switch self {
    case .automatic: "从主照突出、旅行故事、大字主题、随手拼贴、纸刊记录中确定一种构图，在共同构图中写明，后续不得各自改选。"
    case .hero: "选一张主体清楚的主照，面积约辅助照片的1.6至2.4倍；其余照片成组，保留全部原照片。标题、1至2处旁注和可选结语，不平均铺排。"
    case .story: "按照片可见内容组织2至3组，形成阅读路径，主标题、引题、与照片绑定的旁注和可选结语；不凭照片编造时间先后。"
    case .headline: "先分配醒目4至10字标题区域，语义断行，标题字号约正文2.8至3.5倍，优先选择有清晰粗细与笔力的字形；标题实际宽度约占所在单页可用宽度70%至85%，保证它成为第一阅读重心；照片仍须清晰，正文2至3处，不让背景占据标题区。"
    case .collage: "一张主照与若干辅助照片形成非对称组，轻微旋转和有限边缘叠贴；避免人脸重叠，标题与2至3条短注穿插，不做等大网格。四张竖照时禁止四张近等宽横向排成单行；主照可见面积至少为最小辅助照的1.6倍，辅助照上下错位形成两个相互呼应的照片组。"
    case .editorial: "按阅读顺序组织图文分栏，明确主标题、引题、照片旁注和短记事段落；相邻照片有主次，主照按原始比例等比放入规划区域后，可见面积仍应是全页最大；为竖主照预留足够高度，不以区域面积代替照片可见面积。基线有秩序，不把每句话都包成大纸卡。"
    } }
}

nonisolated enum DiaryAIPageStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case scenic, illustrated, vintage, clean, playful, gentle
    var id: String { rawValue }
    var name: String { switch self {
    case .scenic: "实景融纸"; case .illustrated: "手绘旅行"; case .vintage: "复古剪贴"
    case .clean: "清新纸刊"; case .playful: "活力涂鸦"; case .gentle: "温柔纪念"
    } }
    var detail: String { switch self {
    case .scenic: "来源场景融入纤维纸，局部手撕边"
    case .illustrated: "手绘景物、旅行旁注与轻盈纸面"
    case .vintage: "暖纸、票根与复古墨色"
    case .clean: "明亮纸面、清楚色块与有序文字"
    case .playful: "轻快线条、圈画与少量鲜明色"
    case .gentle: "柔和场景、暖色纸纹与纪念短句"
    } }
    var backgroundID: String { switch self {
    case .scenic: "paper"; case .illustrated, .gentle: "watercolor"
    case .vintage: "vintage"; case .clean: "clean"; case .playful: "doodle"
    } }
    var rules: String { switch self {
    case .scenic: "来源场景以细致纸上插画质感融入暖白纤维纸，局部撕纸连接；保持实体形态清楚、色彩自然，避免摄影感三维桌面、浓黑横带或巨大透视空间；深绿或来源墨色，主标题可用马善政，正文轻；纸卡titleParchment或kraftStrip，旁注可none，不生成孤立风景卡片。"
    case .illustrated: "以照片内已确认建筑、植物、山水作透明水彩与钢笔手绘；墨色标题、清楚手写正文，botanicalLine或coralUnderline少量承托，来源场景互相连接。保留一处轮廓清晰、颜色有层次的来源环境插画，集中在一侧并从纸边延伸，占可见画面约四分之一至三分之一；背景主要建筑或景物的可见体量小于主照片组，避免背景把同一建筑放大成全页最大重心；文字预留区轻淡，其余可露出的环境保持清晰，避免全页漂白和大块无主题淡色。"
    case .vintage: "暖纸和来源场景的复古印刷拼贴，深棕主墨与少量来源强调色；kraftStrip或titleParchment票根式文字，照片浅暖边框，避免蓝色胶带与现代荧光色。暖赭、旧纸棕和少量暗红形成统一色调；背景景物以细小复古印刷纹理托住照片，避免巨大餐具、单个食物或重色块与大标题争夺重心。"
    case .clean: "明亮纸面与来源色块，少量场景延展；清楚字号层级、深色墨与单一强调色，coralUnderline或none，照片边框简洁，不做泛黄旧纸。"
    case .playful: "白纸上来源景物的小型涂鸦、黑色线条与少量明亮色点；标题有力度，短注轻快，pinkHeart或coralUnderline点题，不以重复贴纸填满。用有力度、粗细变化的手绘线条和少量鲜明色面形成活力感，强调色从本页照片中提取，原色太暗时仅提高其明度与饱和度。根据照片组的方向和真实可露出空隙决定线条、局部纸片和记号位置；不固定蓝橙配色、角落纸片、星形或绕页弧线，不做四角边框或完整围边。线条与来源中的道路、波纹、器物轮廓等可见细节呼应，既清楚又有疏密。"
    case .gentle: "暖白纸、柔和来源场景、低对比水彩；温暖棕墨与柔和强调色，warmHeart或pinkWish承托短句，主标题与正文有层级，避免每张照片都加装饰。暖米白纸面占至少六成，照片的主要颜色转为低饱和柔和色层，局部薄纸或轻细纹理承托记忆感。配色、意象和位置根据本页照片决定，不固定粉色对角纸边、蕾丝圈和植物；只有照片含植物时才延展相应植物，没有时使用已确认的器物、建筑局部或环境轮廓。低饱和来源色仅在局部自然延伸，避免大色块贯穿全页。"
    } }
}

nonisolated struct DiaryAIDesignSelection: Codable, Equatable, Sendable {
    var layout: DiaryAILayout = .automatic
    var style: DiaryAIPageStyle = .scenic
    var version = 1
    var brief: String {
        "统一整页设计v\(version)：排版=\(layout.name)，风格=\(style.name)。\(layout.rules) \(style.rules) 用户明确指定及锁定内容优先于风格，风格优先于通用默认纸卡与字体。标题优先直接写在安静纸面，勿用大纸卡代替字形的视觉力量；正文横排每行约8至16字，旁注绑定sourceIDs，无事实依据只描述可见细节或明确祝愿。风格预设只定义笔触、纸张、色彩组织和媒介，不提供固定场景、物件、配色或角落位置。主题来源严格取role=photo的真实照片与用户明确故事，已有贴纸只用于前景摆放，不从泳圈、椰树等贴纸推断海边主题。同一风格的不同页面应有各自的来源意象、色彩与疏密组织，不重复四角模板。背景必须指定连接任务：来源线索从哪组照片延伸、沿哪组边缘连接、如何承托标题；主意象避开主照和标题，不另建竞争的视觉中心。贴纸各有主题/连接/固定/导读用途，不能仅按空白撒放；未授权隐藏时保留素材。规划一次确定主照ID、照片分组、阅读方向、文字角色与对应照片、来源场景、主墨色和强调色，并在共同构图中保持一致。照片数量自适应，不丢弃照片。背景重点在可露出区域丰富细节，文字区低对比，照片下面延续色彩纹理，不把预留区画成矩形空框；照片、文字、背景分支必须服从同一构图。标题按风格从已提供字体中选择：实景融纸与复古剪贴优先display.tsanger-heading（仓耳榜书），清新纸刊优先display.douyin-bold（抖音美好体），活力涂鸦优先display.zcool-kuaile（站酷快乐体）或display.smiley-sans（得意黑），温柔纪念与手绘旅行优先calligraphy.ma-shan-zheng。大字主题优先仓耳榜书、得意黑或抖音美好体，根据媒介选一种；新增展示字体仅用于4至10字短标题，正文继续使用清楚的文楷或小赖体。可选花园便签：gardenLavender薰衣草清单用于短清单，gardenStrawberry草莓便签用于温暖生活短记，gardenLily铃兰花笺用于温柔纪念，gardenLilyTag铃兰吊牌只用于短旁注，gardenClover三叶草标签和gardenBlueTicket蓝花票笺用于两三行短句。花园便签有较大插画边角，按客户端原生测量后的完整尺寸预留，文字不能盖住花叶与蝴蝶结。每页最多两种纸卡，禁止把全部正文都塞进装饰便签。最多两种字体、两种纸卡；文字数量按实际空间和角色确定，不能为了丰富反复写泛泛感想。"
    }
}

extension DiaryAIDesignSelection {
    /// Safe fallback preserves layout intent and never crosses a spread spine.
    func fallbackRegions(context: DiaryAIContext, allowsText: Bool) -> [DiaryAILayoutRegion] {
        let photos = context.objects.filter { $0.role == "photo" && $0.editable }
        let w = Double(context.size.width), h = Double(context.size.height)
        guard w > 0, h > 0, !photos.isEmpty else { return [] }
        let ranges: [(Double, Double)] = context.spineX.map { [(0, $0 - 24), ($0 + 24, w)] } ?? [(0, w)]
        var result: [DiaryAILayoutRegion] = []
        var offset = 0
        for (pageIndex, range) in ranges.enumerated() {
            let count = photos.count / ranges.count + (pageIndex < photos.count % ranges.count ? 1 : 0)
            let group = Array(photos.dropFirst(offset).prefix(count)); offset += count
            guard !group.isEmpty else { continue }
            let pageWidth = range.1 - range.0
            var x = range.0 + pageWidth * 0.06
            var width = pageWidth * 0.88
            var top = h * 0.06
            var height = h * 0.88
            if allowsText {
                if layout == .editorial || (layout == .story && pageIndex == 0) {
                    // Give the photo group a neighboring reading column.
                    let railWidth = width * 0.36
                    let railOnLeft = pageIndex > 0
                    let railX = railOnLeft ? x : x + width - railWidth
                    result.append(.init(role: "text", x: railX, y: h * 0.18, width: railWidth, height: h * 0.26))
                    result.append(.init(role: "text", x: railX, y: h * 0.51, width: railWidth, height: h * 0.32))
                    if railOnLeft { x += width * 0.40 }
                    width *= 0.60
                } else if layout == .collage || (layout != .headline && pageIndex > 0) {
                    height = h * 0.63
                    result.append(.init(role: "text", x: x + width * 0.08, y: h * 0.72, width: width * 0.84, height: h * 0.22))
                } else {
                    let band = h * (layout == .headline ? 0.26 : 0.18)
                    result.append(.init(role: "text", x: x, y: h * 0.04, width: width, height: band))
                    top = band + h * 0.07
                    height = h * 0.86 - top
                    result.append(.init(role: "text", x: x + width * 0.12, y: h * 0.88, width: width * 0.76, height: h * 0.08))
                }
            }
            let hero = [.hero, .story, .automatic, .collage].contains(layout) && group.count > 1
            let remaining = hero ? Array(group.dropFirst()) : group
            if hero {
                result.append(.init(role: "photo", objectID: group[0].id.uuidString, x: x, y: top, width: width * 0.59, height: height * (layout == .collage && group.count > 2 ? 0.78 : 1)))
            }
            let columns = hero ? 1 : (layout == .editorial ? 1 : (group.count == 1 ? 1 : 2))
            let rows = max(1, Int(ceil(Double(remaining.count) / Double(columns))))
            let areaX = hero ? x + width * 0.64 : x
            let areaWidth = hero ? width * 0.36 : width
            let cellW = areaWidth / Double(columns), cellH = height / Double(rows)
            for (index, photo) in remaining.enumerated() {
                let col = index % columns, row = index / columns
                let inset = layout == .collage && index % 2 == 1 ? 0.12 : 0.02
                result.append(.init(role: "photo", objectID: photo.id.uuidString,
                    x: areaX + Double(col) * cellW + cellW * inset,
                    y: top + Double(row) * cellH + cellH * (layout == .collage && index % 2 == 1 ? 0.10 : 0.02),
                    width: cellW * (1 - inset - 0.04), height: cellH * (layout == .collage && group.count > 1 ? 0.80 : 0.92)))
            }
        }
        return result
    }
}
