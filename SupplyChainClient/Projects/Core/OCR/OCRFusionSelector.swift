import Foundation

/// OCR 融合选择器
/// 核心功能：从多个OCR引擎的识别结果中，通过评分算法选出最优的识别文本
enum OCRFusionSelector {
    
    /// 选择最优的OCR识别结果
    /// - Parameters:
    ///   - outputs: 多个OCR引擎输出的原始识别结果数组
    ///   - corrector: 医学术语校正器，用于修正OCR识别错误
    ///   - applyCorrection: 是否启用医学术语自动校正
    /// - Returns: 融合后的最终OCR识别结果（包含最优文本、选用引擎、所有原始结果）
    nonisolated static func selectBest(outputs: [OCRTextOutput], corrector: SparkMedicalTermsCorrector?, applyCorrection: Bool) -> OCRRecognition {
        // 1. 对所有OCR结果进行标准化处理（校正文本/保留原文）
        let normalizedOutputs = outputs.map { output in
            let text: String
            // 开启校正且存在校正器 → 执行医学术语校正
            if applyCorrection, let corrector {
                text = corrector.correct(output.text)
            } else {
                // 不校正 → 直接使用原始识别文本
                text = output.text
            }
            // 生成标准化后的OCR输出对象
            return OCRTextOutput(engine: output.engine, text: text, confidence: output.confidence, elapsedMs: output.elapsedMs)
        }

        // 2. 根据自定义评分规则，选出得分最高的OCR结果（无结果时返回空默认值）
        let best = normalizedOutputs.max { lhs, rhs in
            score(for: lhs) < score(for: rhs)
        } ?? OCRTextOutput(engine: "none", text: "", confidence: nil, elapsedMs: nil)

        // 3. 封装并返回最终识别结果
        return OCRRecognition(text: best.text, selectedEngine: best.engine, outputs: normalizedOutputs)
    }

    // MARK: - 私有评分方法
    
    /// 为单个OCR结果计算综合得分（分数越高越优质）
    /// 评分维度：置信度 + 文本有效长度 + 数字密度 + 医学术语匹配度
    /// - Parameter output: 待评分的OCR输出
    /// - Returns: 综合评分（总分100分）
    nonisolated private static func score(for output: OCRTextOutput) -> Double {
        let text = output.text
        // 空文本直接0分
        guard !text.isEmpty else { return 0 }

        // 计算核心评分因子
        let nonWhitespaceCount = text.replacingOccurrences(of: "\\s", with: "", options: .regularExpression).count  // 非空白字符数
        let numberCount = text.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count  // 数字字符数量
        // 医学关键词命中数量（医疗报告专用关键词）
        let medicalTermHits = ["MRI", "CT", "血常规", "mmol/L", "T1WI", "T2WI", "DWI", "AFP", "CEA"].reduce(0) { acc, term in
            acc + (text.localizedCaseInsensitiveContains(term) ? 1 : 0)
        }

        // 四大评分维度（权重分配：总分100）
        let confidencePart = (output.confidence ?? 0.6) * 40       // 引擎置信度：40分（无值默认0.6）
        let textLengthPart = min(Double(nonWhitespaceCount), 1200) / 1200 * 30  // 有效文本长度：30分（上限1200字符）
        let numberDensityPart = min(Double(numberCount), 80) / 80 * 10         // 数字密度：10分（上限80个数字）
        let medicalPart = min(Double(medicalTermHits), 10) / 10 * 20           // 医学术语匹配：20分（上限10个关键词）

        // 汇总总分
        return confidencePart + textLengthPart + numberDensityPart + medicalPart
    }
}
