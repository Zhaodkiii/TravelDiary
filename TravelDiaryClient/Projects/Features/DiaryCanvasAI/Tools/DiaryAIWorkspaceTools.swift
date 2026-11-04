import Foundation
import CoreGraphics

enum DiaryAIWorkspaceTools {
    static func normalized(_ call: DiaryAIToolCall) -> DiaryAIToolCall {
        guard var raw = try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any],
              let point = raw["center"] as? [NSNumber], point.count == 2,
              point.allSatisfy({ $0.doubleValue.isFinite }) else { return call }
        raw["center"] = ["x": point[0], "y": point[1]]
        guard let bytes = try? JSONSerialization.data(withJSONObject: raw) else { return call }
        var value = call; value.arguments = String(decoding: bytes, as: UTF8.self); return value
    }

    static let operationNames = ["place_layer": "setPlacement", "set_photo_crop": "setPhotoCrop", "set_photo_frame": "setFrameStyle", "create_text": "createText", "update_text": "updateText", "attach_decoration": "setPlacement", "set_decoration_visibility": "setDecorationVisibility"]
    static let descriptions: [String: String] = [
        "report_photo_orientations": "仅检查原照片像素的正立方向；逐张返回objectID和最终绝对纠正角度，不修改构图。",
        "plan_composition": "仅用于整体规划。summary 用80～160字说明主照片、分区和文字留白；重新排版可同时提供regions指定照片与文字预留区域（设计单位）。不输出图层JSON或文件。调用一次即可。",
        "get_workspace": "查询当前工作版本、可处理图层和状态。初始输入已包含上下文，只有信息缺失或版本冲突时调用。只读。",
        "get_canvas_image": "查看最新已提交画布。commit_batch已返回相同预览时无需重复调用。只读。",
        "inspect_layers": "仅当本批素材细节看不清时补图；objectIDs最多8个，使用本批L编号或UUID。每批最多两次。只读。",
        "list_fonts": "查询真实可用fontID。上下文已给出字体时直接使用，不要重复查询。只读。",
        "list_frame_styles": "查询可用相框名称。已知名称可直接set_photo_frame，无需先查询。只读。",
        "place_layer": "暂存一个本批图层的位置、等比尺寸和角度。照片与相框整体移动。center为画布设计单位视觉中心，width是目标可见边界宽度，提供maxHeight时等比缩小以同时满足宽高上限，angle为绝对角度。不会裁剪照片；commit_batch后显示。",
        "attach_decoration": "暂存本批贴纸的绝对位置、可见宽度和角度，适合放在照片边角。使用画布设计单位，不支持自动锚定或父子绑定。commit_batch后显示。",
        "set_photo_crop": "仅在允许取景时暂存照片内部放大和偏移；cropZoom为1～3，cropX/Y是照片本地坐标偏移，不是画布位置。保留原图和外层位置。特殊槽位不支持时保留原取景。",
        "set_photo_frame": "仅在允许相框调整时暂存一个真实样式名称；客户端生成相框并保持绑定，不返回相框图片或资源JSON。",
        "create_text": "仅在允许新增文字时创建一段可编辑文字。提供稳定clientObjectKey、正文、可用fontID、字号、文本框宽度和视觉中心；可选颜色和纸张。客户端测量换行和高度，不输出字形或文件。commit_batch后显示。",
        "update_text": "修改本批已有文字，只传需要改的字段；保留原文时省略text。width为本地文本框宽度；center为画布视觉中心。只换字体不必重发正文。commit_batch后显示。",
        "set_decoration_visibility": "仅在允许隐藏装饰时暂存本批贴纸可见性，不能隐藏照片、文字或锁定内容。",
        "commit_batch": "一次提交所有已暂存操作，先校验再整体生效。summary只写一句操作概述，不含JSON。成功返回新版本和最新画布；失败保留暂存操作；按错误修订对应对象，同key的create_text替换暂存文字。仅整批重做时rollback_batch。不要重复提交。",
        "rollback_batch": "丢弃当前尚未提交的操作，之后可重新调用单项工具；不能撤回已提交批次，已提交回退由用户操作。",
        "validate_layout": "读取当前校验状态，不执行排版。commit_batch已返回校验结果时通常无需调用。",
        "request_batch_revision": "看过已提交画布后，仅指出本批需要修复的objectIDs与reason；客户端安排局部修复，最多两轮。不得与commit_batch同轮调用。",
        "finish_batch": "仅在commit_batch成功且下一轮看到最新画布后调用，结束本批。不得与首次提交同轮调用。"
    ]
    static let fieldDescriptions: [String: String] = [
        "objectID": "本批图层的L编号（如L2）或真实UUID，禁止猜测。",
        "objectIDs": "待补图的本批L编号或UUID数组，最多8个。",
        "expectedVersion": "当前工作版本整数。提交前各操作使用同一版本；提交成功后使用返回的新版本。",
        "center": "画布设计单位的视觉中心{x,y}；不是屏幕像素、左上角或0～1比例。",
        "width": "place_layer/attach_decoration为目标可见边界宽度，指定maxHeight时可能等比缩小；文字工具为本地文本框宽度，单位均为设计单位。",
        "angle": "绝对顺时针角度（度），0为不旋转；不是增量。",
        "text": "要写入的最终正文，禁止代码、图层JSON或说明文字。update_text不改正文时省略。",
        "fontID": "从上下文fonts取真实id，不是字体名称或文件路径。",
        "fontSize": "字号12～300，客户端负责真实测量和换行。",
        "clientObjectKey": "本批新增文字的稳定短名，例如caption-1；修复时复用，同批不可重复创建。",
        "color": "六位十六进制颜色，如#355A49。",
        "paper": "文字承托样式ID：none无、torn撕纸、tape胶带、note便签；warmHeart暖纸爱心、blueTape蓝胶带纸卡、pinkWish粉色心愿、titleParchment层叠标题纸、lavenderStrip薰衣草纸条、pinkHeart粉纸手绘心、botanicalLine植物划线卡、coralUnderline珊瑚划线纸、kraftStrip牛皮纸条。客户端按文字自适应，不另建贴纸；省略保留原样。",
        "summary": "简短自然语言概述，不输出操作数组或文件内容。",
        "maxHeight": "可选最终可见高度上限。客户端在旋转、换框后等比缩小以同时满足width和maxHeight；不得拉伸。",
        "reason": "具体视觉问题，如照片遮挡人物、标题区被占用；不要笼统说优化。",
        "cropZoom": "内部取景放大1～3，1保留基础取景。",
        "cropX": "照片本地水平偏移，正值向右，不改变外层位置。",
        "cropY": "照片本地垂直偏移，正值向下，不改变外层位置。",
        "visible": "装饰是否显示，false仅用于授权隐藏。",
        "frameStyle": "真实目录中的相框名称。"
    ]
    static func validateTextEvidence(_ raw: [String: Any], request: DiaryAIRequest) throws {
        guard request.design != nil, let text = raw["text"] as? String else { return }
        let supplied = request.instruction + " " + request.customScene + " " + (request.creationBrief?.confirmedFacts ?? "")
        if let brief = request.creationBrief {
            if !brief.displaysLocation, !brief.location.isEmpty, text.contains(brief.location) { throw DiaryAIError.invalid("地点仅供理解，不得写入成品。请只修改这段文字。") }
            let forbidden = brief.forbidden.components(separatedBy: CharacterSet(charactersIn: "，,；;\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if forbidden.contains(where: text.contains) { throw DiaryAIError.invalid("文字包含用户禁止的内容，请修改此段。") }
        }
        let claims = ["姐姐", "妹妹", "弟弟", "哥哥", "爸爸", "妈妈", "父亲", "母亲", "外婆", "奶奶", "爷爷", "满月", "百日", "周岁", "敬茶", "迎亲", "换装", "结婚周年", "先上山", "再环山", "最后看海"]
        if let claim = claims.first(where: { text.contains($0) && !supplied.contains($0) }) {
            throw DiaryAIError.invalid("文案包含用户未确认的事实“\(claim)”。保留位置和样式，只把此段改成照片可见细节或明确祝愿，不推断亲属、年龄或事件先后。")
        }
    }
    static var schemas: [[String: Any]] {
        let string: [String: Any] = ["type": "string"]
        let number: [String: Any] = ["type": "number"]
        var definitions: [(String, [String: Any], [String])] = [
            ("plan_composition", ["heroID": string, "summary": string, "regions": ["type": "array", "maxItems": 20, "items": ["type": "object", "additionalProperties": false, "properties": ["role": ["type": "string", "enum": ["photo", "text"]], "objectID": string, "rotation": ["type": "number", "enum": [-90, 0, 90, 180]], "x": number, "y": number, "width": number, "height": number], "required": ["role", "rotation", "x", "y", "width", "height"]]]], ["summary"]),
            ("report_photo_orientations", ["rotations": ["type": "array", "items": ["type": "object", "additionalProperties": false, "properties": ["objectID": string, "angle": ["type": "number", "enum": [-90, 0, 90, 180]]], "required": ["objectID", "angle"]]]], ["rotations"]),
            ("request_batch_revision", ["objectIDs": ["type": "array", "items": string, "minItems": 1, "maxItems": DiaryAIWorkspace.maximumBatchLayers], "reason": string], ["objectIDs", "reason"]),
            ("get_workspace", [:], []), ("get_canvas_image", [:], []), ("list_fonts", [:], []),
            ("list_frame_styles", [:], []),
            ("inspect_layers", ["objectIDs": ["type": "array", "items": string, "maxItems": DiaryAIWorkspace.maximumBatchLayers]], ["objectIDs"]),
            ("commit_batch", ["summary": string], ["summary"]),
            ("rollback_batch", [:], []), ("validate_layout", [:], []), ("finish_batch", ["backgroundBrief": string, "backgroundPrompt": string], [])
        ]
        for name in operationNames.keys.sorted() {
            var fields: [String: Any] = [:], required: [String] = []
            if name == "create_text" { fields["clientObjectKey"] = string; required.append("clientObjectKey") }
            else { fields["objectID"] = string; required.append("objectID") }
            switch name {
            case "place_layer", "attach_decoration":
                fields["center"] = ["type": "object", "properties": ["x": number, "y": number], "required": ["x", "y"], "additionalProperties": false]
                fields["width"] = number; fields["maxHeight"] = number; fields["angle"] = number; required += ["center", "width", "angle"]
            case "create_text", "update_text":
                fields["textRole"] = ["type": "string", "enum": ["title", "lead", "caption", "body", "closing"]]
                fields["sourceIDs"] = ["type": "array", "items": string, "maxItems": 8]
                for key in ["text", "fontID", "color", "paper"] { fields[key] = string }
                for key in ["fontSize", "width", "angle"] { fields[key] = number }
                fields["center"] = ["type": "object", "properties": ["x": number, "y": number], "required": ["x", "y"], "additionalProperties": false]
                if name == "create_text" { required += ["text", "fontID", "fontSize", "width", "center"] }
            case "set_photo_crop":
                for key in ["cropZoom", "cropX", "cropY"] { fields[key] = number; required.append(key) }
            case "set_photo_frame": fields["frameStyle"] = ["type": "string", "enum": ["手撕纸", "简洁纸边", "拍立得"]]; required.append("frameStyle")
            default: fields["visible"] = ["type": "boolean"]; required.append("visible")
            }
            definitions.append((name, fields, required))
        }
        return definitions.map { name, fields, required in
            var properties = fields; properties["expectedVersion"] = ["type": "integer", "minimum": 0]
            for key in Array(properties.keys) {
                if var field = properties[key] as? [String: Any] {
                    field["description"] = fieldDescriptions[key]
                    if key == "paper" { field["enum"] = DiaryTextPaper.Kind.allCases.map(\.rawValue) }
                    if key == "summary" { field["maxLength"] = name == "plan_composition" ? 240 : 100 }
                    if key == "fontSize" { field["minimum"] = 12; field["maximum"] = 300 }
                    if key == "cropZoom" { field["minimum"] = 1; field["maximum"] = 3 }
                    properties[key] = field
                }
            }
            return ["type": "function", "name": name, "description": descriptions[name] ?? name,
                    "parameters": ["type": "object", "properties": properties, "required": required + ["expectedVersion"], "additionalProperties": false]]
        }
    }
    static func parse(_ call: DiaryAIToolCall, version: Int, context: DiaryAIContext) throws -> DiaryAIOperation? {
        guard var raw = try JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any],
              raw.removeValue(forKey: "expectedVersion") as? Int == version else { throw DiaryAIError.invalid("工作版本不匹配，请先 get_workspace") }
        guard let type = operationNames[call.name] else { return nil }
        if let reference = raw["objectID"] as? String {
            guard let object = context.objects.first(where: { $0.shortID == reference || $0.id.uuidString.caseInsensitiveCompare(reference) == .orderedSame }) else { throw DiaryAIError.invalid("本批图层编号不存在") }
            raw["objectID"] = object.id.uuidString
        }
        raw.removeValue(forKey: "sourceIDs")
        raw["type"] = type; raw["operationID"] = call.id
        if type == "setPlacement" {
            guard let idText = raw["objectID"] as? String, let id = UUID(uuidString: idText),
                  let object = context.objects.first(where: { $0.id == id }), let width = raw["width"] as? Double,
                  width.isFinite, width > 0, object.bounds.width > 0 else { throw DiaryAIError.invalid("图层或可见宽度无效") }
            guard let center = raw["center"] as? [String: Any], let x = center["x"] as? Double, let y = center["y"] as? Double, x.isFinite, y.isFinite else { throw DiaryAIError.invalid("center必须包含有限数字x、y，本项未暂存") }
            let requestedAngle = raw["angle"] as? Double ?? object.angle
            guard requestedAngle.isFinite, abs(requestedAngle) <= 3600 else { throw DiaryAIError.invalid("angle必须为合理的有限角度，本项未暂存") }
            // Absolute rotations such as 270 degrees are equivalent to -90, not a reason for a paid repair round.
            let wrapped = requestedAngle.truncatingRemainder(dividingBy: 360)
            let angle = wrapped > 180 ? wrapped - 360 : wrapped < -180 ? wrapped + 360 : wrapped
            guard x >= 0, y >= 0, x <= context.size.width, y <= context.size.height else { throw DiaryAIError.invalid("center在画布外。保留原素材；不允许通过移出画布隐藏贴纸，应贴近照片组边缘。") }
            let scale = object.scale * width / object.bounds.width
            guard (0.05...20).contains(scale) else { throw DiaryAIError.invalid("宽度导致无效缩放。不能把素材缩成零来隐藏；保持可见大小并摆放到照片组边缘。") }
            raw["angle"] = angle
            raw["scale"] = scale
        }
        let envelope: [String: Any] = ["contextID": context.id.uuidString, "plan": ["schemaVersion": 1, "contextID": context.id.uuidString, "baseDigest": context.digest, "summary": "工具操作", "operations": [raw]]]
        return try DiaryAIDraftController.decodeArguments(String(decoding: JSONSerialization.data(withJSONObject: envelope), as: UTF8.self)).plan?.operations.first
    }
}
