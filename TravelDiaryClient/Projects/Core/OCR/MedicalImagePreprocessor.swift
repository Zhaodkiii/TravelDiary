import CoreImage
import UIKit

/// SparkMedicalImagePreprocessor 是一个专门用于医疗单据图像预处理的工具类。
/// 它通过调整对比度、降噪和锐化，使模糊或光线不佳的病历照片变得更易于识别。
final class SparkMedicalImagePreprocessor {
    
    /// 预处理配置参数
    struct Config: Sendable {
        var contrastFactor: Double = 1.1      // 对比度系数（1.0 为原始值）
        var brightnessFactor: Double = 0.02   // 亮度偏移（稍微增加亮度有助于区分纸张和文字）
        var sharpnessFactor: Double = 0.3    // 锐化强度
        var enableNoiseReduction: Bool = true // 是否开启降噪（去除拍照时的噪点）
        var enhanceEdges: Bool = false        // 是否增强边缘（默认关闭，仅在文本极度模糊时开启）

        /// 预设的平衡配置：适用于大多数清晰度的单据
        nonisolated(unsafe) static let balanced = Config()
    }

    /// 单例模式：全局共享预处理器实例
    nonisolated(unsafe) static let shared = SparkMedicalImagePreprocessor()

    /// CIContext 是 Core Image 的渲染上下文
    /// 渲染 CIImage 时需要它来生成最终的位图数据
    private let context: CIContext

    nonisolated init() {
        // 优先尝试使用 Metal (GPU) 进行加速渲染，如果不可用则回退到默认设置 (CPU)
        if let device = MTLCreateSystemDefaultDevice() {
            self.context = CIContext(mtlDevice: device)
        } else {
            self.context = CIContext()
        }
    }

    /// 核心预处理流程：执行一系列图像滤镜。
    /// - Parameters:
    ///   - image: 原始 UIImage
    ///   - config: 预处理配置
    /// - Returns: 处理后的 UIImage
    nonisolated func preprocess(_ image: UIImage, config: Config = .balanced) -> UIImage {
        // 1. 将 UIImage 转换为 CIImage（Core Image 的图像表达形式，不立即渲染）
        guard let ciImage = CIImage(image: image) else { return image }

        // 2. 灰度化：医疗文档通常不需要颜色信息，黑白更利于 OCR
        var output = applyGrayscale(ciImage)
        
        // 3. 降噪：去除背景杂色，减少干扰
        if config.enableNoiseReduction {
            output = applyNoiseReduction(output)
        }
        
        // 4. 颜色控制：增加对比度和亮度。让白色的纸更白，黑色的字更黑
        output = applyContrastAndBrightness(output, contrast: config.contrastFactor, brightness: config.brightnessFactor)
        
        // 5. 边缘增强（可选）：强化字体的笔画边缘
        if config.enhanceEdges {
            output = applyEdgeEnhancement(output)
        }
        
        // 6. 钝化蒙版锐化：通过对比度差异使整体文字线条更锐利
        output = applySharpen(output, intensity: config.sharpnessFactor)

        // 7. 渲染输出：将滤镜链执行完毕，生成 CGImage，最后转回 UIImage
        // extent 代表图像的实际边界，确保滤镜处理整个画面
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return image }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - 滤镜细节实现

    /// 将图像转换为黑白单色 (Mono)
    nonisolated private func applyGrayscale(_ image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIPhotoEffectMono") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        return filter.outputImage ?? image
    }

    /// 降噪滤镜：减少像素间的突变感
    nonisolated private func applyNoiseReduction(_ image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CINoiseReduction") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(0.02, forKey: "inputNoiseLevel") // 噪点级别，过高会导致文字模糊
        filter.setValue(0.4, forKey: kCIInputSharpnessKey) // 保持一定的锐度
        return filter.outputImage ?? image
    }

    /// 颜色控制：调整对比度、亮度和饱和度
    nonisolated private func applyContrastAndBrightness(_ image: CIImage, contrast: Double, brightness: Double) -> CIImage {
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(contrast, forKey: kCIInputContrastKey)   // 增强明暗对比
        filter.setValue(brightness, forKey: kCIInputBrightnessKey) // 调整亮度
        filter.setValue(0.0, forKey: kCIInputSaturationKey)     // 强制将饱和度设为 0 (双重黑白保障)
        return filter.outputImage ?? image
    }

    /// 亮度锐化：增强明度通道的锐利度，不产生色彩伪影
    nonisolated private func applyEdgeEnhancement(_ image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CISharpenLuminance") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(0.4, forKey: kCIInputSharpnessKey)
        return filter.outputImage ?? image
    }

    /// 钝化蒙版 (Unsharp Mask)：通过模糊图像的副本并计算差异来增强边缘
    nonisolated private func applySharpen(_ image: CIImage, intensity: Double) -> CIImage {
        guard let filter = CIFilter(name: "CIUnsharpMask") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(2.5, forKey: kCIInputRadiusKey)    // 影响半径
        filter.setValue(intensity, forKey: kCIInputIntensityKey) // 锐化强度
        return filter.outputImage ?? image
    }
}
