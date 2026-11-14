import Foundation

@MainActor final class DiarySeedreamBackgroundProvider: DiaryAIBackgroundProvider {
    weak var productionLog: DiaryAIProductionLog?
    let runtime: DiaryAITaskRuntime
    private let session: URLSession
    init(session: URLSession? = nil, runtime: DiaryAITaskRuntime = DiaryAITaskRuntime()) {
        self.runtime = runtime
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 360
        self.session = session ?? URLSession(configuration: config, delegate: DiaryAIRejectRedirects.shared, delegateQueue: nil)
        runtime.register(self.session)
    }
    static func body(reference: Data, prompt: String) -> [String: Any] {
        var result: [String: Any] = ["prompt": prompt,
         "response_format": "url", "size": "2K", "stream": false, "watermark": false]
        if !reference.isEmpty { result["image"] = "data:image/jpeg;base64,\(reference.base64EncodedString())" }
        return result
    }
    private func post(_ input: [String: Any], scene name: String) async throws -> [String: Any] {
        let access = try await runtime.access(name)
        let apiKey = access.credential.secret
        productionLog?.registerSecret(apiKey)
        let url = access.scene.endpoint
        var body = input
        body["model"] = access.scene.modelId
        body.merge(access.scene.parameters.mapValues(\.foundation)) { _, new in new }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = Double(access.scene.limits.requestTimeoutSeconds)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        productionLog?.record("request", ["endpoint": url.absoluteString])
        if let bytes = request.httpBody { productionLog?.data("request-body", bytes) }
        let data = try await runtime.meteredResponse(scene: name, request: request) {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw DiaryAIError.invalid("背景服务未返回有效响应") }
            productionLog?.record("response-status", ["status": http.statusCode])
            guard (200..<300).contains(http.statusCode) else {
                throw DiaryAIServiceError.response(status: http.statusCode, code: http.value(forHTTPHeaderField: "x-error-code"), body: data)
            }
            return data
        }
        productionLog?.data("response-body", data)
        try Task.checkCancellation()
        try runtime.assertOwner()
        guard data.count <= 4_000_000, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["error"] == nil else { throw DiaryAIError.invalid("背景服务返回错误或无效数据") }
        return object
    }
    static func requireComplete(_ result: [String: Any]) throws {
        if result["status"] as? String == "incomplete" {
            let reason = (result["incomplete_details"] as? [String: Any])?["reason"] as? String
            throw DiaryAIError.invalid(reason == "length" ? "主题分析输出达到长度限制，尚未发起背景生图；已保留排版，可仅重试分析。" : "主题分析响应不完整，尚未发起背景生图，可重试分析。")
        }
    }
    func design(reference: Data, context: String) async throws -> DiaryAIBackgroundDesign {
        let instructions = """
        根据去掉旧背景的实际前景，为照片背后设计一张连续无字纸底。用户要求、来源证据和实测坐标优先。主体只从真实照片提取，贴纸和文字提供位置及叙事参考。
        已给定主照时按图层编号和边界识别，照片面积大小不能改变主照。先从主照和本页标题寻找最容易辨认的真实细节，把它改写成有位置的纸上轮廓、局部结构或色彩印记。若主照是合影、人物或特写，从关键物件提取可识别的局部轮廓和颜色。物件上有显著图案时，只以淡色印痕延续图案，完整的载体留在前景；优先在生图描述里只写被提取的图案、颜色和笔触，不写原载体的名称、外形、圆环或部件。背景中的局部印痕沿来源组边缘分散，保持低对比，避免居中徽章、完整器物、表带或完整静物。
        主照意象必须落在主照ID对应的一处实测相邻空隙，写出横纵百分比，不移至画面中央，文字及贴纸附近保留浅纸。有另一组明显不同的环境时，可在该照片自己的一处实测相邻空隙延续来源结构，以同一纸底和克制配色连接两处。最多两个意象组。每组用同一来源组织主体轮廓、两三处相邻细节和一层渐淡的纹理；例如山脊可带林坡、草叶和浅云层，幕墙可带几段长短不同的灯线和细碎反光。主照若只适合一组小印痕，让确有来源的相邻环境承担更丰富的结构。例子只用于说明层次，有素材依据才画。不在其他分区补第三个意象，不拼接成同一真实地点，不增加未见地标、时段或季节。
        使用指定风格的笔触、纸纹和印刷方式。画面从可见空隙逐渐融入纸底，标题与旁注区低对比。留白边缘自然，不能成为空卡、矩形挖空、整页透视或阴影。
        只调用 background_design。brief 用120至260字说明来源证据、实际位置和避让。primaryMotif 用25至100字单独交付必须出现在底图的第一意象，写明绝对画幅位置、形态、材质或色彩。backdropPrompt 用120至260字写清主意象的同源细节和纹理，补充可选第二意象、纸质和留白。写出细节依附的结构与笔触，避免只写颜色和气氛。后两项只写最终可见内容，使用绝对分区，不能出现照片、人物、相框、贴纸、标题文字、手帐、书页或图层编号，不写禁止词清单。工具会将 primaryMotif 放在生图提示最前面，不能在 brief 中有主题而在可画内容中省略。
        本页配置与图层边界：
        \(context)
        """
        let result = try await post([
            "stream": false, "store": false,
            "input": [["role": "user", "content": [["type": "input_text", "text": instructions], ["type": "input_image", "image_url": "data:image/jpeg;base64,\(reference.base64EncodedString())"]]]],
            "tools": [["type": "function", "name": "background_design", "description": "根据照片主题和真实布局给出一份简短的纯背景设计说明", "parameters": ["type": "object", "properties": ["brief": ["type": "string"], "primaryMotif": ["type": "string"], "backdropPrompt": ["type": "string"]], "required": ["brief", "primaryMotif", "backdropPrompt"], "additionalProperties": false]]],
            "tool_choice": "required", "thinking": ["type": "disabled"], "max_output_tokens": 4096
        ], scene: "diary.background.design")
        try Self.requireComplete(result)
        guard result["status"] as? String == "completed", let output = result["output"] as? [[String: Any]],
              let call = output.first(where: { $0["type"] as? String == "function_call" && $0["name"] as? String == "background_design" }),
              let arguments = call["arguments"] as? String,
              let object = try JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              let brief = object["brief"] as? String, !brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, brief.count <= 1500,
              let motif = object["primaryMotif"] as? String, !motif.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, motif.count <= 180,
              let backdrop = object["backdropPrompt"] as? String, !backdrop.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              motif.count + backdrop.count < 800 else {
            throw DiaryAIError.invalid("照片主题与布局分析未完成，尚未发起背景生图，可重试分析。")
        }
        return .init(brief: brief, prompt: motif + "。\n" + backdrop)
    }
    /// Only rewrite known spatial-reference phrases, never strip arbitrary object words from art directions.
    static func preparePrompt(_ original: String) throws -> String {
        var text = original
        for (source, target) in [
            ("照片之间", "预留区域之间"), ("照片间空隙", "预留区域间空隙"), ("照片间", "预留区域间"), ("照片内部地平线", "局部水平线"), ("文字与旁注区域", "安静区域"),
            ("照片密集区", "预留密集区"), ("照片组", "预留区域组"), ("照片下缘", "预留区域下缘"), ("照片上缘", "预留区域上缘"), ("文字周围", "安静区周围"),
            ("文字横带", "安静区域"), ("文字区", "安静区"), ("照片衬托", "柔和衬托"), ("照片位置", "预留位置"), ("照片区域", "预留区域"), ("手账底图", "平面底图"), ("书写", "记录"),
            ("照片群下方", "预留区域下方"), ("照片群上方", "预留区域上方"), ("照片群", "预留区域"), ("照片群之后", "空白区"), ("照片群后方", "空白区"),
            ("在照片后方", "的空白处"), ("照片后方", "空白区域"),
            ("照片边缘外", "区域边缘外"), ("照片周围", "预留区域周围"),
            ("照片旁边", "预留区外侧"), ("照片上方", "预留区上方"),
            ("照片下方", "预留区下方"), ("照片右侧", "预留区右侧"), ("照片左侧", "预留区左侧"),
            ("照片里的", "来源的"), ("照片中的", "来源的"), ("原照片的", "来源的"), ("原片的", "来源的")
        ] { text = text.replacingOccurrences(of: source, with: target) }
        // A model may append a negative list despite the positive-only contract.
        // Remove that prohibition sentence, never a positive subject description.
        text = text.replacingOccurrences(of: "(?:不出现|不包含|不得出现|禁止出现|不绘制|不画|不生成|不添加|避免出现|画面不含|画面没有)[^。；\\n]*[。；]?", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "无(?:任何)?(?:人物|人形)[^。；\\n]*[。；]?", with: "", options: .regularExpression)
        let banned = ["照片", "拍立得", "人物", "相框", "贴纸", "书页", "书脊", "立体书", "相册", "本册", "手帐", "跨页"].filter(text.contains)
        guard banned.isEmpty else {
            throw DiaryAIError.invalid("主题分析已完成，生图提示词校验未通过：包含\(banned.joined(separator: "、"))。分析结果已保留，尚未调用生图；可重新生成以重做分析。")
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 800 else { throw DiaryAIError.invalid("生图提示词为空或超长，分析结果已保留。") }
        return text
    }
    static func prepareNativeScene(_ original: String) throws -> String {
        let person = "(?:[一二两三四五六七八九十几数](?:个人|人(?:物|形|影|群)?|[名位](?:成人|儿童|小孩|男士|女士))|游客|行人|旅人|旅行者|徒步者|球员|运动员|观众|路人|人群|人形|人影|背影|人物|穿着|穿[深浅红蓝白黑黄绿橙]|背着|戴着)"
        let environment = original.components(separatedBy: CharacterSet(charactersIn: "。！？；\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.range(of: person, options: .regularExpression) == nil }
            .joined(separator: "。")
        let graphic = environment.replacingOccurrences(
            of: "(?:粗壮的|醒目的|清晰的)?([红蓝黄绿黑白橙紫]?色?)(?:大字(?:笔迹)?|字样|字迹|汉字|标语|字母)",
            with: "$1抽象色块", options: .regularExpression)
        let scene = graphic.replacingOccurrences(
            of: "(?:浅米黄|浅色|暖色)?(?:木纹|木质)?桌面(?:占满画面|铺满画面|铺满全页|占据整个画面)",
            with: "浅赭木纹仅作局部纸上印痕", options: .regularExpression)
        return try preparePrompt(scene)
    }
    func repairPrompt(_ text: String) async throws -> String {
        let result = try await post([
            "stream": false, "store": false,
            "input": [["role": "user", "content": [["type": "input_text", "text": "仅修正文案，不重新分析图片。把以下背景描述中的素材相对位置改为绝对画面分区（左上、中部、右下等），保留已有坐标或百分比、第一意象、色彩和风格，不移动已明确定位的意象，不增加任何新景物；不需要思考过程，直接填写工具参数。删除照片、拍立得、人物、相框、贴纸、书页、书脊、立体本册、手帐、跨页等词及其实体描绘；保留实际来源中的书架、书桌等环境物体，只描述纯背景景物。不要否定词清单。只调用repair_background_prompt，text不超过800字。原描述：" + text]]]],
            "tools": [["type": "function", "name": "repair_background_prompt", "description": "仅修复生图文案", "parameters": ["type": "object", "properties": ["text": ["type": "string"]], "required": ["text"], "additionalProperties": false]]], "tool_choice": "required", "thinking": ["type": "disabled"], "max_output_tokens": 2048
        ], scene: "diary.background.design")
        try Self.requireComplete(result)
        guard result["status"] as? String == "completed", let output = result["output"] as? [[String: Any]], let call = output.first(where: { $0["name"] as? String == "repair_background_prompt" }),
              let args = call["arguments"] as? String, let data = args.data(using: .utf8),
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any], let repaired = value["text"] as? String else { throw DiaryAIError.invalid("背景文案修正失败，尚未发起生图") }
        return try Self.preparePrompt(repaired)
    }
    func generate(reference: Data, prompt: String) async throws -> URL {
        let object = try await post(Self.body(reference: reference, prompt: prompt), scene: "diary.background.generate")
        guard let items = object["data"] as? [[String: Any]], items.count == 1,
              let value = items.first?["url"] as? String, let url = URL(string: value), url.scheme == "https", url.host != nil else {
            throw DiaryAIError.invalid("背景服务未返回单张可下载图片")
        }
        return url
    }
    func download(_ url: URL) async throws -> Data {
        guard url.scheme == "https" else { throw DiaryAIError.invalid("背景下载地址无效") }
        // No Authorization header is sent to the image host.
        let (file, response) = try await session.download(from: url)
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        try runtime.assertOwner()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              response.url?.scheme == "https" else { throw DiaryAIError.invalid("背景下载失败，可重试下载而不重新生图") }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 40_000_000 else { throw DiaryAIError.invalid("背景文件大小超出限制") }
        let bytes = try Data(contentsOf: file)
        productionLog?.record("download", ["file": productionLog?.attachment(bytes, ext: "png") ?? "", "bytes": bytes.count])
        return bytes
    }
    func validate(reference: Data, background: Data) async throws {
        try await validateImage(reference: reference, background: background, style: nil)
    }
    func validate(reference: Data, background: Data, style: DiaryAIBackgroundStyle) async throws {
        try await validateImage(reference: reference, background: background, style: style)
    }
    func validate(reference: Data, background: Data, style: DiaryAIBackgroundStyle,
                  design: DiaryAIBackgroundDesign, composite: Data) async throws {
        try await validateImage(reference: reference, background: background, style: style, design: design, composite: composite)
    }
    private func validateImage(reference: Data, background: Data, style: DiaryAIBackgroundStyle?,
                               design: DiaryAIBackgroundDesign? = nil, composite: Data? = nil) async throws {
        let styleCheck = style.map { "同时检查明显的媒介错配：目标风格是\($0.name)，\($0.brief)。\($0.designRules) 只因清楚可见的错配而拒绝，例如涂鸦变成满幅水彩、蜡笔变成光滑晕染、版画变成摄影风景；不要仅因主观喜好、精确留白百分比或微小印刷偏差拒绝。原Skill中的人形、标题、档案栏已为可编辑前景而移除，不能因缺少它们拒绝。reason指出实际可见证据。" } ?? ""
        let emptyCardCheck = "拒绝孤立的规则矩形空白纸卡、浅色占位板或照片空位，即使没有外框和文字；连续纸面明暗变化与有实际主题图案的印刷块不是占位板。"
        let prompt = styleCheck + emptyCardCheck + "图1是手帐前景布局参考，图2是待验收纯背景。图2禁止任何新增人形，包括小型远景游客、背影、剪影和手绘小人；不是只检查复制的人脸。发现明确人形必须拒绝。检查图2是否复制了图1的照片矩形、相框、人物面孔、贴纸或正文，是否含照片占位框、棋盘格、界面、额外标题、实体书脊中缝、书页折角或外部边缘。先核对主题一致性：区分实拍照片与装饰贴纸；图2的主导环境、时段和实体应来自图1的真实照片，不能把古城夜游改成无依据的山林水岸，也不能把室内聚会改成户外旅行。主导场景无依据或与照片冲突时拒绝；抽象纸纹、低对比色块不视为新场景。纸张、来自实际照片的绘画景物、局部丰富景物与来源装饰允许；不能仅因景物丰富、颜色鲜明或不够空白而拒绝，服务水印允许。文字区域应保留可读空间，主体图层应有承托；背景允许场景化，不能包含重复照片的完整海报。只调用 report_background：通过才 accept=true；不确定或发现前景残留则 false；reason 简短中文。不要输出图片数据或长文。"
        let layoutCheck = design.map {
            "\n图3是实测前景和候选底图的合成。以下是同一份生成要求：\($0.brief)；\($0.prompt)。" +
            "比较图1与图3，核对计划中的主要来源细节是否在指定空隙可见，照片主体是否仍最突出，实际标题和旁注是否可读。中、浓强度应看得到来源轮廓和局部细节；有足够的计划空隙而背景仅剩纸纹或零散色点时，指出缺少的内容。" +
            "同一泛化类别不足以证明主题贴合。检查是否把原定的局部图案扩大为完整器物、居中徽章或可与照片争夺焦点的高对比插画。只有可指出明确缺失、无依据的主题替换、明显脱离来源图组、明显遮盖或抢焦时拒绝，忽略微小位置和装饰差异。" +
            "人物和文字限制只适用于图2。"
        } ?? ""
        var input = [
            ["type": "input_text", "text": prompt + layoutCheck],
            ["type": "input_image", "image_url": "data:image/jpeg;base64,\(reference.base64EncodedString())"],
            ["type": "input_image", "image_url": "data:image/jpeg;base64,\(try DiaryAIBackgroundImaging.jpeg(background).base64EncodedString())"]
        ]
        if let composite {
            input.append(["type": "input_image", "image_url": "data:image/jpeg;base64,\(composite.base64EncodedString())"])
        }
        let result = try await post([
            "stream": false, "store": false,
            "input": [["role": "user", "content": input]],
            "tools": [["type": "function", "name": "report_background", "description": "报告纯背景质量检查结果", "parameters": [
                "type": "object", "properties": ["accept": ["type": "boolean"], "reason": ["type": "string"]],
                "required": ["accept", "reason"], "additionalProperties": false]]],
            "tool_choice": "required", "thinking": ["type": "disabled"], "max_output_tokens": 2048
        ], scene: "diary.background.review")
        guard result["status"] as? String == "completed",
              let output = result["output"] as? [[String: Any]],
              let call = output.first(where: { $0["type"] as? String == "function_call" && $0["name"] as? String == "report_background" }),
              let arguments = call["arguments"] as? String,
              let report = try JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              let accepted = report["accept"] as? Bool else { throw DiaryAIError.invalid("背景视觉检查未完成，结果已保留，请重试检查。") }
        guard accepted else {
            throw DiaryAIBackgroundVisualRejection(reason: String((report["reason"] as? String ?? "可能包含重复前景").prefix(200)))
        }
    }
}
