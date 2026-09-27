import Foundation
import Vision
/// OCR 识别请求的控制选项
struct OCRRequestOptions: Sendable {
    var preferMedicalPreset: Bool   // 是否优先使用医疗专用预设（针对病历、报告优化）
    var applyPreprocess: Bool       // 是否应用图像预处理（如纠偏、去噪、增强对比度）
    var correctMedicalTerms: Bool   // 是否开启医疗术语后处理纠错
    var topCandidatesCount: Int     // 识别候选结果的数量（Vision 引擎会返回多个可能的词，此处取前几个）
    var useTiling: Bool             // 是否启用分块识别（针对超长单据或高分辨率大图）

    /// 医疗场景默认配置：开启全量优化，保证最高准确率
    nonisolated(unsafe) static let medicalDefault = OCRRequestOptions(
        preferMedicalPreset: true,
        applyPreprocess: true,
        correctMedicalTerms: true,
        topCandidatesCount: 3,
        useTiling: false
    )

    /// 快速预览配置：关闭耗时优化，用于实时扫描或低延迟需求
    nonisolated(unsafe) static let fastPreview = OCRRequestOptions(
        preferMedicalPreset: false,
        applyPreprocess: false,
        correctMedicalTerms: false,
        topCandidatesCount: 1,
        useTiling: false
    )
}

/// 识别语言选择策略
enum OCRLanguageStrategy: Sendable, Equatable, Codable {
    case system             // 自动根据设备当前的系统语言决定
    case codes([String])    // 指定特定的语言代码列表（如 ["zh-Hans", "en-US"]）

    /// 解析出最终传给识别引擎的语言代码数组
    nonisolated func resolvedCodes() -> [String] {
        switch self {
        case .system:
            return OCRLanguageStrategy.systemPreferredVisionCodes()
        case let .codes(codes):
            return OCRLanguageStrategy.normalizeVisionCodes(codes)
        }
    }

    /// 获取系统首选语言并映射到 Apple Vision 引擎支持的代码
    nonisolated private static func systemPreferredVisionCodes() -> [String] {
        let raw = Locale.preferredLanguages
        var out: [String] = []
        for lang in raw {
            // 将 iOS 的语言 ID 映射为标准 Vision 代码
            if lang.hasPrefix("zh-Hans") { out.append("zh-Hans"); continue } // 简体中文
            if lang.hasPrefix("zh-Hant") { out.append("zh-Hant"); continue } // 繁体中文
            if lang.hasPrefix("en") { out.append("en-US"); continue }      // 英语
            if lang.hasPrefix("ja") { out.append("ja-JP"); continue }      // 日语
            if lang.hasPrefix("ko") { out.append("ko-KR"); continue }      // 韩语
            out.append(lang)
        }
        return normalizeVisionCodes(out)
    }

    /// 去重、去空格并过滤空字符串
    nonisolated private static func normalizeVisionCodes(_ codes: [String]) -> [String] {
        var seen = Set<String>()
        return codes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }
}

/// OCR 全局持久化配置
struct OCRConfiguration: Sendable, Equatable, Codable {
    var language: OCRLanguageStrategy           // 识别语言策略
    var recognitionLevelRaw: String             // 内部存储的识别精度级别（"accurate" 或 "fast"）
    var useLanguageCorrection: Bool             // 是否使用 Vision 自带的语言校正功能
    var pdfRenderScale: CGFloat                 // PDF 转图片识别时的渲染缩放倍数（越高越清晰但越慢）
    var thumbnailMaxSide: CGFloat               // 预处理缩略图的最大边长
    var enableAliyunOCR: Bool                   // 是否启用阿里云 OCR（备选引擎）
    var enableLocalServerOCR: Bool              // 是否启用局域网/专用服务器 OCR
    var localServerBaseURL: String              // 本地服务器 API 地址
    var localServerTimeoutMs: Int               // 本地服务器请求超时时间
    var localServerAuthToken: String?           // 本地服务器鉴权令牌
    init(
        language: OCRLanguageStrategy = .system,
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
        useLanguageCorrection: Bool = false,
        pdfRenderScale: CGFloat = 2.0,
        thumbnailMaxSide: CGFloat = 1600,
        enableAliyunOCR: Bool = false,
        enableLocalServerOCR: Bool = false,
        localServerBaseURL: String = "",
        localServerTimeoutMs: Int = 10_000,
        localServerAuthToken: String? = nil
    ) {
        self.language = language
        self.recognitionLevelRaw = OCRConfiguration.encodeRecognitionLevel(recognitionLevel)
        self.useLanguageCorrection = useLanguageCorrection
        self.pdfRenderScale = pdfRenderScale
        self.thumbnailMaxSide = thumbnailMaxSide
        self.enableAliyunOCR = enableAliyunOCR
        self.enableLocalServerOCR = enableLocalServerOCR
        self.localServerBaseURL = localServerBaseURL
        self.localServerTimeoutMs = localServerTimeoutMs
        self.localServerAuthToken = localServerAuthToken
    }

    /// 将字符串包装回 Apple Vision 的枚举类型
    nonisolated var recognitionLevel: VNRequestTextRecognitionLevel {
        OCRConfiguration.decodeRecognitionLevel(recognitionLevelRaw)
    }

    nonisolated private static func encodeRecognitionLevel(_ level: VNRequestTextRecognitionLevel) -> String {
        level == .accurate ? "accurate" : "fast"
    }

    nonisolated private static func decodeRecognitionLevel(_ raw: String) -> VNRequestTextRecognitionLevel {
        raw == "fast" ? .fast : .accurate
    }
}
/// 传递给各级 OCR 引擎的提示信息（Hints）
struct OCRRecognitionHints: Sendable {
    let languages: [String]                      // 建议识别的语言
    let recognitionLevel: VNRequestTextRecognitionLevel // 识别精度级别
    let topCandidatesCount: Int                  // 获取的前 N 个结果
    let useLanguageCorrection: Bool               // 是否应用 Vision 词库修正

    /// 从全局配置中转换出针对单次任务的提示
    nonisolated static func from(configuration: OCRConfiguration, topCandidatesCount: Int) -> OCRRecognitionHints {
        OCRRecognitionHints(
            languages: configuration.language.resolvedCodes(),
            recognitionLevel: configuration.recognitionLevel,
            topCandidatesCount: max(1, topCandidatesCount),
            useLanguageCorrection: configuration.useLanguageCorrection
        )
    }
}

/// 单个 OCR 引擎输出的原始数据
struct OCRTextOutput: Sendable {
    let engine: String      // 引擎名称（如 "Vision", "Aliyun"）
    let text: String        // 识别出的全文文本
    let confidence: Double? // 整体置信度
    let elapsedMs: Int?     // 识别耗时（毫秒）
}

/// 最终返回给业务层的识别结果
struct OCRRecognition: Sendable {
    let text: String               // 最终采纳的文本
    let selectedEngine: String     // 最终选用的引擎
    let outputs: [OCRTextOutput]   // 所有参与竞选的引擎输出（用于调试或对比）
}

/// OCR 引擎必须遵循的协议（接口）
protocol OCRTextEngine: Sendable {
    var name: String { get }
    /// 输入图片数据和提示，异步返回识别出的文本
    func recognize(imageData: Data, hints: OCRRecognitionHints) async throws -> OCRTextOutput
}

/// 阿里云 OCR 凭证提供者：负责动态获取或刷新 STS Token
protocol OCRCredentialsProvider: Sendable {
    func fetchAliyunOCRCredentials() async throws -> OCRAliyunCredentials
}

/// 阿里云 AccessKey 信息模型
struct OCRAliyunCredentials: Sendable {
    let accessKeyId: String
    let accessKeySecret: String
    let securityToken: String? // 如果使用 STS 临时鉴权，则包含此 Token
}


enum OCRError: Error, Sendable {

    case invalidImage

    case invalidDocumentURL

    case engineUnavailable(String)

    case transport(String)

    case response(String)

}
