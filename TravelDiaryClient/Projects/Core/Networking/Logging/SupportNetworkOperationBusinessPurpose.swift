import Foundation

/// 将 `Operation.name` + 请求路径/查询解析为简短中文业务说明，供网络日志阅读。
enum SupportNetworkOperationBusinessPurpose: Sendable {
    static func describe(_ operation: some SupportNetworkOperation) -> String {
        let name = operation.name
        let path = operation.request.path
        let query = operation.request.queryItems ?? []

        if let exact = exactOperationDescriptions[name] {
            return exact
        }

        if name.hasPrefix("Medical.Query.") {
            return medicalQueryPurpose(path: path)
        }

        if name.hasPrefix("Medical.Resource.") {
            return medicalResourcePurpose(operationName: name, path: path, query: query)
        }

        if name.hasPrefix("Medical.Workflow.") {
            return "医疗工作流：\(path)"
        }

        if name.hasPrefix("Chat.Sync.") {
            return chatSyncPurpose(operationName: name)
        }

        if name.hasPrefix("Auth.") || name.hasPrefix("OTP.") {
            return authPurpose(operationName: name)
        }

        if name.hasPrefix("Device.") {
            return devicePurpose(operationName: name)
        }

        if name.hasPrefix("File.") {
            return filePurpose(operationName: name)
        }

        return "网络请求 operation=\(name)"
    }

    // MARK: - 精确匹配（与 API 中 `name:` 一致）

    private static let exactOperationDescriptions: [String: String] = [
        "AIConfig.Bootstrap": "拉取 AI 多场景模型与网关配置（bootstrap，含客户端版本与平台）",
        "AIConfig.TrialStatus": "查询 AI 试用资格与剩余额度",
        "AIConfig.TrialApply": "申请或确认 AI 试用",
        "AIConfig.ProviderConnectionTest": "探测上游模型供应商连通性（连接测试）",
        "OSS.STS": "获取阿里云 OSS 临时访问凭证（直传/下载）",
        "OCR.STS": "获取 OCR 服务临时凭证或配置",
        "Auth.CurrentSession": "鉴权：拉取当前账号最新会话（含 Pro 状态）",
        "Device.Register": "设备域：上送安装 device_id 与全量终端画像（bundle、系统、机型、时区语言、可选推送与 JWT）",
        "Device.RegisterTrusted": "设备域：登记可信设备（兼容旧 operation 名，同全量登记）",
        "Deactivation.GetStatus": "查询账号注销进度",
        "Deactivation.Request": "发起账号注销申请",
        "Deactivation.Cancel": "取消账号注销申请",
        "AccountIdentity.List": "拉取账号登录方式绑定状态",
        "AccountIdentity.VerificationRequest": "请求登录方式绑定/修改再认证",
        "AccountIdentity.VerificationVerify": "完成再认证并换取 verification ticket",
        "AccountIdentity.Bind": "绑定新登录方式",
        "AccountIdentity.Change": "修改手机号或邮箱登录方式",
        "CombinedMedical.Create": "组合创建病历、检查/处方等医疗单据（一次提交）"
    ]

    // MARK: - Medical.Query.*

    private static func medicalQueryPurpose(path: String) -> String {
        if path.contains("/members/"), path.hasSuffix("/complete-data/") {
            return "加载指定成员的医疗数据汇总（单接口：病例/报告/处方与附件）"
        }
        if path.contains("/members/") {
            return "医疗查询：\(path)"
        }
        return "医疗查询：\(path)"
    }

    // MARK: - Medical.Resource.*

    private static func medicalResourcePurpose(operationName: String, path: String, query: [URLQueryItem]) -> String {
        let kind = query.first { $0.name == "kind" }?.value
        let memberID = query.first { $0.name == "member_id" }?.value
        let memberNote = memberID.map { " memberId=\($0)" } ?? ""

        let kindPhrase: String
        if let kind {
            kindPhrase = resourceKindChinese[kind] ?? "资源 kind=\(kind)"
        } else {
            kindPhrase = "医疗资源"
        }

        let method: String
        if operationName.contains(".GET.") {
            method = "拉取"
        } else if operationName.contains(".POST.") {
            method = "新建"
        } else if operationName.contains(".PATCH.") {
            method = "更新"
        } else if operationName.contains(".PUT.") {
            method = "全量替换"
        } else if operationName.contains(".DELETE.") {
            method = "删除"
        } else {
            method = "请求"
        }

        if isMedicalResourceCollectionPath(path) {
            return "\(method)\(kindPhrase)列表\(memberNote)"
        }
        return "\(method)\(kindPhrase)详情/写入（单条资源）\(memberNote)"
    }

    /// `GET /api/v1/medical/resources/` 为列表；`/resources/<id>/` 为单条。
    private static func isMedicalResourceCollectionPath(_ path: String) -> Bool {
        let parts = path.split(separator: "/").filter { $0.isEmpty == false }.map(String.init)
        guard let r = parts.lastIndex(of: "resources") else { return false }
        if r + 1 >= parts.count { return true }
        return Int(parts[r + 1]) == nil
    }

    private static let resourceKindChinese: [String: String] = [
        "members": "就诊成员列表",
        "cases": "病历主档",
        "symptoms": "症状记录",
        "visits": "就诊记录",
        "surgeries": "手术记录",
        "follow-ups": "随访记录",
        "health-exam-reports": "体检报告",
        "examination-reports": "检查/检验报告",
        "med-exam-details": "体检/检查明细项",
        "prescription-batches": "处方批次",
        "medications": "用药信息",
        "medication-taken-records": "服药打卡记录"
    ]

    // MARK: - Chat

    private static func chatSyncPurpose(operationName: String) -> String {
        switch operationName {
        case "Chat.Sync.ThreadHead":
            return "聊天：拉取会话线程头与最近状态（打开会话）"
        case "Chat.Sync.Push":
            return "聊天：上送本地待发消息（outbox）"
        case "Chat.Sync.Pull":
            return "聊天：按游标增量拉取消息"
        default:
            return "聊天同步：\(operationName)"
        }
    }

    // MARK: - Auth / OTP

    private static func authPurpose(operationName: String) -> String {
        switch operationName {
        case "Auth.Login": return "登录：账号密码或通用登录"
        case "Auth.AppleLogin": return "登录：Sign in with Apple"
        case "Auth.CurrentSession": return "鉴权：拉取当前账号最新会话（含 Pro 状态）"
        case "Auth.Refresh": return "鉴权：刷新访问令牌"
        case "OTP.RequestEmail": return "OTP：请求邮箱验证码"
        case "OTP.VerifyEmail": return "OTP：校验邮箱验证码"
        default: return "鉴权：\(operationName)"
        }
    }

    // MARK: - Device

    private static func devicePurpose(operationName: String) -> String {
        "设备域：\(operationName)"
    }

    // MARK: - File

    private static func filePurpose(operationName: String) -> String {
        switch operationName {
        case "File.List": return "文件：按业务维度列出已登记文件"
        case "File.UpdateBinding": return "文件：更新文件与业务单据绑定关系"
        case "File.Register": return "文件：登记客户端直传后的元数据"
        case "File.DownloadURL": return "文件：生成带时效的下载 URL"
        default: return "文件：\(operationName)"
        }
    }
}
