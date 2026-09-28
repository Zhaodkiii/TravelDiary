import Foundation
import UIKit

/// OCR 编排器：负责协调多个 OCR 引擎，并对识别结果进行预处理、融合与校正。
/// 使用 Actor 确保多线程环境下的状态安全。
actor OCROrchestrator {
    private let config: OCRConfiguration       // 全局 OCR 配置（如开关、API 密钥等）
    private let visionEngine: OCRTextEngine     // iOS 原生 Vision 引擎（本地，免费，快）
    private let aliyunEngine: OCRTextEngine?    // 阿里云远程引擎（精准，收费）
    private let localServerEngine: OCRTextEngine? // 企业内部/本地服务器引擎
    private let logger: Logger                  // 日志记录

    init(
        config: OCRConfiguration,
        visionEngine: OCRTextEngine? = nil,
        aliyunEngine: OCRTextEngine? = nil,
        localServerEngine: OCRTextEngine? = nil,
        logger: Logger = ConsoleLogger()
    ) {
        self.config = config
        self.visionEngine = visionEngine ?? VisionOCREngine()
        self.aliyunEngine = aliyunEngine
        self.localServerEngine = localServerEngine
        self.logger = logger
    }

    // MARK: - 单张图片识别入口

    /// 识别 UIImage 对象
    func recognize(image: UIImage, options: OCRRequestOptions? = nil) async throws -> OCRRecognition {
        let options = options ?? OCRRequestOptions.medicalDefault
        // 将 UIImage 转换为高画质的 JPEG Data
        guard let imageData = image.jpegData(compressionQuality: 0.98) else {
            throw OCRError.invalidImage
        }
        return try await recognize(imageData: imageData, options: options)
    }

    /// 核心识别逻辑：驱动多引擎并发执行
    func recognize(imageData: Data, options: OCRRequestOptions? = nil) async throws -> OCRRecognition {
        let options = options ?? OCRRequestOptions.medicalDefault
        guard let rawImage = UIImage(data: imageData) else {
            throw OCRError.invalidImage
        }

        // 1. 图像预处理：如果开启，会进行纠偏、降噪、锐化等操作（针对医疗单据优化）
        let workingImage: UIImage
        if options.applyPreprocess {
            workingImage = SparkMedicalImagePreprocessor.shared.preprocess(rawImage)
        } else {
            workingImage = rawImage
        }

        let workingData = workingImage.jpegData(compressionQuality: 0.98) ?? imageData
        let hints = OCRRecognitionHints.from(configuration: config, topCandidatesCount: options.topCandidatesCount)

        // 2. 并发执行多引擎任务 (Structured Concurrency)
        // 使用 async let 同时启动多个识别任务，互不阻塞
        
        // 任务 A: 原生 Vision 识别 (通常必选)
        async let visionTask: OCRTextOutput? = try? await visionEngine.recognize(imageData: workingData, hints: hints)
        
        // 任务 B: 阿里云识别 (依赖配置开关)
        async let aliyunTask: OCRTextOutput? = {
            guard config.enableAliyunOCR, let aliyunEngine else { return nil }
            return try? await aliyunEngine.recognize(imageData: imageData, hints: hints)
        }()
        
        // 任务 C: 本地服务器识别
        async let localTask: OCRTextOutput? = {
            guard config.enableLocalServerOCR, let localServerEngine else { return nil }
            return try? await localServerEngine.recognize(imageData: imageData, hints: hints)
        }()

        // 3. 等待所有任务完成并收集结果
        var outputs: [OCRTextOutput] = []
        if let vision = await visionTask { outputs.append(vision) }
        if let aliyun = await aliyunTask { outputs.append(aliyun) }
        if let local = await localTask { outputs.append(local) }

        guard !outputs.isEmpty else {
            throw OCRError.response("no_ocr_engine_output")
        }

        // 4. 结果决策与融合 (OCR Fusion)
        // 通过 OCRFusionSelector 对比多份识别结果，结合医疗词库校正，选出最准确的一份
        let best = OCRFusionSelector.selectBest(
            outputs: outputs,
            corrector: SparkMedicalTermsCorrector.shared,
            applyCorrection: options.correctMedicalTerms
        )

        logger.info(
            "OCR完成 selectedEngine=\(best.selectedEngine) engines=\(outputs.map { $0.engine }.joined(separator: ",")) textLen=\(best.text.count)",
            module: .aiConfig
        )

        return best
    }

    // MARK: - 文档与多任务识别

    /// 识别本地文档（如 PDF）
    func recognize(document url: URL, options: OCRRequestOptions? = nil) async throws -> OCRRecognition {
        let options = options ?? OCRRequestOptions.medicalDefault
        let extractor = OCRDocumentExtractor(config: config)
        // 将文档拆分为图片帧并调用当前 orchestrator 进行识别
        return try await extractor.extractText(from: url, orchestrator: self, options: options)
    }

    /// 批量识别图片和文档，并提供进度回调
    /// - Parameters:
    ///   - images: 图片数组
    ///   - documents: 文档 URL 数组
    ///   - progress: 进度闭包 (0.0 ~ 1.0)
    func recognize(
        images: [UIImage],
        documents: [URL],
        options: OCRRequestOptions? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> OCRRecognition {
        let options = options ?? OCRRequestOptions.medicalDefault
        var results: [OCRRecognition] = []
        let total = max(1, images.count + documents.count)
        var done = 0

        // 处理所有图片
        for image in images {
            let result = try await recognize(image: image, options: options)
            results.append(result)
            done += 1
            progress?(Double(done) / Double(total))
        }

        // 处理所有文档
        for url in documents {
            let result = try await recognize(document: url, options: options)
            results.append(result)
            done += 1
            progress?(Double(done) / Double(total))
        }

        // 将所有识别到的文本按换行符拼接
        let mergedText = results.map(\.text).joined(separator: "\n")
        let mergedOutputs = results.flatMap(\.outputs)
        let selectedEngine = results.last?.selectedEngine ?? "vision"

        return OCRRecognition(text: mergedText, selectedEngine: selectedEngine, outputs: mergedOutputs)
    }
}
