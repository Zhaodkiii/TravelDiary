import Foundation

@MainActor final class DiarySeedreamBackgroundProvider: DiaryAIBackgroundProvider {
    weak var productionLog: DiaryAIProductionLog?
    static let model = "doubao-seedream-5-0-flash-260915"
    static let endpoint = URL(string: "https://ark.cn-beijing.volces.com/api/v3/images/generations")!
    private let session: URLSession
    init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 360
        self.session = session ?? URLSession(configuration: config)
    }
    static func body(reference: Data, prompt: String) -> [String: Any] {
        ["model": model, "prompt": prompt, "image": "data:image/jpeg;base64,\(reference.base64EncodedString())",
         "response_format": "url", "size": "2K", "stream": false, "watermark": true]
    }
    private func post(_ body: [String: Any], to url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(DiaryAITestConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        productionLog?.record("request", ["endpoint": url.absoluteString])
        if let bytes = request.httpBody { productionLog?.data("request-body", bytes) }
        let (data, response) = try await session.data(for: request)
        productionLog?.record("response-status", ["status": (response as? HTTPURLResponse)?.statusCode ?? 0, "headers": (response as? HTTPURLResponse)?.allHeaderFields.reduce(into: [String: String]()) { $0[String(describing: $1.key)] = String(describing: $1.value) } ?? [:]])
        productionLog?.data("response-body", data)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw DiaryAIError.invalid("背景服务未返回有效响应") }
        guard (200..<300).contains(http.statusCode) else {
            // Provider payloads may echo input URLs or private data; expose only the status.
            throw DiaryAIError.invalid("背景服务请求失败（HTTP \(http.statusCode)）。已保留排版；重试生成可能再次计费。")
        }
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
        你是旅行手帐背景设计师。先看这张去掉旧背景的真实排版参考图，再设计照片背后的底纸。照片内容和实际布局是依据，不要只套风格名或通用风景。
        1. 提炼照片共同主题和情绪，区分画面确实出现的景物与用户提供的地点。照片无法证明具体地名、季节或日期时不推断。多种场景以主照片和共同色彩统一，不把全部景点堆进一页。
        2. 提取2至4个来源线索（只从本页可见内容提取，不套用通用旅行景物），明确从哪一个图层及其可见内容得出；选1至2个作为主要场景骨架，保留能辨认来源的结构与环境关系，不只输出泛用装饰。不要复制人物、整张照片、矩形相框或已有贴纸。
        3. 按实际坐标辨认主照片、照片组合、文字区和空隙，具体说明背景意象落在哪里、向哪里延展，如何顺着照片中的轮廓或视线形成呼应。不能把照片内部的地平线当成整页同一条线。
        4. 设计一处局部有细节的场景区、一段连接不同素材组合的过渡区和必要的安静区，避免整页均匀淡化。主照片周围适度退让，但不机械空出所有边界；已经确认的主题轮廓可从其相邻空隙自然延展，用方向、色块与远近关系连接内容。照片内部地平线不强行对齐。文字附近保持可读性，中央不放竞争主角。允许完整可辨认的绘画景物，禁止摄影矩形与人物副本。不要使用跨页、书页、书脊等实体书描述，这是一张连续的平面图案。四周不要机械围框。
        5. 从照片取2至4种克制背景色，与指定纸张和风格统一；照片原色不修改。照片颜色冲突时用共同中性色统筹，主照片色作少量强调。
        6. 风格只决定笔触、纸纹和印刷语言，主题决定画什么，现有布局决定画在哪里。纸墨消融、局部来源意象与疏密节奏用于连接环境，避免照片像放在无关壁纸上。已有贴纸较多则进一步减少背景装饰。不能移动任何前景或生成文字。
        7. 先建立主题证据，再写最终提示词：brief 中列出确认意象和排除意象。backdropPrompt 的每个实体必须出自确认意象，不能在压缩改写时新增景物。古城夜游应延续可见屋檐、街巷结构与灯光节奏；没有山、水证据就不加山脊、水岸、森林、缓坡。室内聚会延续可见空间、餐桌材质和庆祝线索，不自动改成户外旅行。示例是条件说明，不是所有页面的素材清单。
        8. 输出前核对 brief 与 backdropPrompt：主题、时段、地点类型和主要意象必须一致。轻强度只降低背景对比与覆盖面积，不抹掉主题特征。装饰贴纸不是照片事实，不能因为有缆车贴纸便推断山地场景。
        仅调用 background_design，brief 用250至450个汉字给出可执行的设计说明，包含“主题依据；来源线索；配色；分区与呼应；留白避让”。另填 backdropPrompt：150至300字，只描述最终底纹画面里应该存在的景物、材质、颜色、位置和留白，用绝对分区描述，如左上、下方三分之一。不能包含“照片、拍立得、人物、相框、贴纸、书、手帐、跨页”等词，不描述参考图本身，不提源素材编号，不写否定词清单。所有照片周边的相对位置要转为画面绝对位置。图像模型只看这段纯正向描述。不要返回图层JSON、文件、长篇思考或候选方案。看不清时少画，不编造。
        本页配置与图层边界：
        \(context)
        """
        let result = try await post([
            "model": DiaryAITestConfig.model, "stream": false, "store": false,
            "input": [["role": "user", "content": [["type": "input_text", "text": instructions], ["type": "input_image", "image_url": "data:image/jpeg;base64,\(reference.base64EncodedString())"]]]],
            "tools": [["type": "function", "name": "background_design", "description": "根据照片主题和真实布局给出一份简短的纯背景设计说明", "parameters": ["type": "object", "properties": ["brief": ["type": "string"], "backdropPrompt": ["type": "string"]], "required": ["brief", "backdropPrompt"], "additionalProperties": false]]],
            "tool_choice": "required", "thinking": ["type": "disabled"], "max_output_tokens": 4096
        ], to: DiaryAITestConfig.endpoint)
        try Self.requireComplete(result)
        guard result["status"] as? String == "completed", let output = result["output"] as? [[String: Any]],
              let call = output.first(where: { $0["type"] as? String == "function_call" && $0["name"] as? String == "background_design" }),
              let arguments = call["arguments"] as? String,
              let object = try JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              let brief = object["brief"] as? String, !brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, brief.count <= 1500,
              let backdrop = object["backdropPrompt"] as? String, !backdrop.isEmpty, backdrop.count <= 800 else {
            throw DiaryAIError.invalid("照片主题与布局分析未完成，尚未发起背景生图，可重试分析。")
        }
        return .init(brief: brief, prompt: backdrop)
    }
    /// Only rewrite known spatial-reference phrases, never strip arbitrary object words from art directions.
    static func preparePrompt(_ original: String) throws -> String {
        var text = original
        for (source, target) in [
            ("照片群下方", "预留区域下方"), ("照片群上方", "预留区域上方"), ("照片群", "预留区域"), ("照片群之后", "空白区"), ("照片群后方", "空白区"),
            ("在照片后方", "的空白处"), ("照片后方", "空白区域"),
            ("照片边缘外", "区域边缘外"), ("照片周围", "预留区域周围"),
            ("照片旁边", "预留区外侧"), ("照片上方", "预留区上方"),
            ("照片下方", "预留区下方"), ("照片右侧", "预留区右侧"), ("照片左侧", "预留区左侧")
        ] { text = text.replacingOccurrences(of: source, with: target) }
        let banned = ["照片", "拍立得", "人物", "相框", "贴纸", "书", "手帐", "跨页"].filter(text.contains)
        guard banned.isEmpty else {
            throw DiaryAIError.invalid("主题分析已完成，生图提示词校验未通过：包含\(banned.joined(separator: "、"))。分析结果已保留，尚未调用生图；可重新生成以重做分析。")
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 800 else { throw DiaryAIError.invalid("生图提示词为空或超长，分析结果已保留。") }
        return text
    }
    func repairPrompt(_ text: String) async throws -> String {
        let result = try await post([
            "model": DiaryAITestConfig.model, "stream": false, "store": false,
            "input": [["role": "user", "content": [["type": "input_text", "text": "仅修正文案，不重新分析图片。把以下背景描述中的素材相对位置改为绝对画面分区（左上、中部、右下等），保留已确认场景、色彩和风格，不增加任何新景物；不需要思考过程，直接填写工具参数。删除照片、拍立得、人物、相框、贴纸、书、手帐、跨页等词及其实体描绘，只描述纯背景景物。不要否定词清单。只调用repair_background_prompt，text不超过800字。原描述：" + text]]]],
            "tools": [["type": "function", "name": "repair_background_prompt", "description": "仅修复生图文案", "parameters": ["type": "object", "properties": ["text": ["type": "string"]], "required": ["text"], "additionalProperties": false]]], "tool_choice": "required", "thinking": ["type": "disabled"], "max_output_tokens": 2048
        ], to: DiaryAITestConfig.endpoint)
        try Self.requireComplete(result)
        guard result["status"] as? String == "completed", let output = result["output"] as? [[String: Any]], let call = output.first(where: { $0["name"] as? String == "repair_background_prompt" }),
              let args = call["arguments"] as? String, let data = args.data(using: .utf8),
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any], let repaired = value["text"] as? String else { throw DiaryAIError.invalid("背景文案修正失败，尚未发起生图") }
        return try Self.preparePrompt(repaired)
    }
    func generate(reference: Data, prompt: String) async throws -> URL {
        let object = try await post(Self.body(reference: reference, prompt: prompt), to: Self.endpoint)
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
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              response.url?.scheme == "https" else { throw DiaryAIError.invalid("背景下载失败，可重试下载而不重新生图") }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 40_000_000 else { throw DiaryAIError.invalid("背景文件大小超出限制") }
        let bytes = try Data(contentsOf: file)
        productionLog?.record("download", ["file": productionLog?.attachment(bytes, ext: "png") ?? "", "bytes": bytes.count])
        return bytes
    }
    func validate(reference: Data, background: Data) async throws {
        let prompt = "图1是手帐前景布局参考，图2是待验收纯背景。检查图2是否复制了图1的照片矩形、相框、人物面孔、贴纸或正文，是否含照片占位框、棋盘格、界面、额外标题、实体书脊中缝、书页折角或外部边缘。先核对主题一致性：区分实拍照片与装饰贴纸；图2的主导环境、时段和实体应来自图1的真实照片，不能把古城夜游改成无依据的山林水岸，也不能把室内聚会改成户外旅行。主导场景无依据或与照片冲突时拒绝；抽象纸纹、低对比色块不视为新场景。纸张、来自实际照片的绘画景物、局部丰富景物与来源装饰允许；不能仅因景物丰富、颜色鲜明或不够空白而拒绝，服务水印允许。文字区域应保留可读空间，主体图层应有承托；背景允许场景化，不能包含重复照片的完整海报。只调用 report_background：通过才 accept=true；不确定或发现前景残留则 false；reason 简短中文。不要输出图片数据或长文。"
        let result = try await post([
            "model": DiaryAITestConfig.model, "stream": false, "store": false,
            "input": [["role": "user", "content": [
                ["type": "input_text", "text": prompt],
                ["type": "input_image", "image_url": "data:image/jpeg;base64,\(reference.base64EncodedString())"],
                ["type": "input_image", "image_url": "data:image/jpeg;base64,\(try DiaryAIBackgroundImaging.jpeg(background).base64EncodedString())"]
            ]]],
            "tools": [["type": "function", "name": "report_background", "description": "报告纯背景质量检查结果", "parameters": [
                "type": "object", "properties": ["accept": ["type": "boolean"], "reason": ["type": "string"]],
                "required": ["accept", "reason"], "additionalProperties": false]]],
            "tool_choice": "required", "thinking": ["type": "disabled"], "max_output_tokens": 2048
        ], to: DiaryAITestConfig.endpoint)
        guard result["status"] as? String == "completed",
              let output = result["output"] as? [[String: Any]],
              let call = output.first(where: { $0["type"] as? String == "function_call" && $0["name"] as? String == "report_background" }),
              let arguments = call["arguments"] as? String,
              let report = try JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any],
              let accepted = report["accept"] as? Bool else { throw DiaryAIError.invalid("背景视觉检查未完成，结果已保留，请重试检查。") }
        guard accepted else { throw DiaryAIError.invalid("背景未通过视觉检查：\((report["reason"] as? String ?? "可能包含重复前景").prefix(200))。已保留排版，可重新生成背景。") }
    }
}
