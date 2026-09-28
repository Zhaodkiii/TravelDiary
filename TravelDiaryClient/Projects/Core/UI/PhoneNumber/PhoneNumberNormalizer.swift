import Foundation

/// 全局通用的手机号格式化工具类
///
/// 核心目标：将各种不规则的用户输入，统一格式化为后端安全的 E.164 标准号码（如：`+8615385056020`）
/// 支持处理的输入格式：
/// - 包含 +86、0086、86 等国家码前缀
/// - 包含空格、横杠、括号等分隔符
/// - UI 界面选择的默认国家区号（如 +86）
///
/// 注意：本工具不依赖第三方库（如 libphonenumber），专注解决项目中最常见的格式问题（重复国家码、混合格式）
enum PhoneNumberNormalizer {
    
    /// 格式化后的手机号结果结构体
    /// Equatable：可比较是否相等；Sendable：支持跨线程安全使用
    struct Normalized: Equatable, Sendable {
        /// E.164 标准格式号码（尽力格式化），非空时一定以 + 开头
        let e164: String
        /// 去除前缀、仅保留纯数字的版本（尽力格式化）
        let digits: String
        /// 纯数字的国内号码（尽力格式化；未知地区时可能仍包含国家码）
        let nationalDigits: String
    }

    /// 根据用户输入自动识别到的区号和去除区号后的本地号码
    struct DetectedRegionNumber: Equatable, Sendable {
        let dial: String
        let nationalDigits: String
    }

    /// 将原始手机号 格式化为 E.164 标准格式
    /// - Parameters:
    ///   - rawInput: 用户原始输入的手机号字符串
    ///   - defaultDial: 默认国家区号（如 +86）
    /// - Returns: 格式化后的手机号结果
    static func normalize(rawInput: String, defaultDial: String) -> Normalized {
        // 1. 基础清理：去除首尾空白和换行符
        let compact = compactPhoneInput(rawInput)
        
        // 提取默认区号的纯数字（如 +86 → 86）
        let dialDigits = defaultDial.filter(\.isNumber)
        // 提取用户输入的纯数字
        let digitsOnly = compact.filter(\.isNumber)

        // MARK: - 核心格式化逻辑
        
        // 情况1：号码以 00 开头 → 转换为 + （国际前缀）
        if compact.hasPrefix("00") {
            let after00 = String(compact.dropFirst(2))
            let e164 = "+" + after00.filter(\.isNumber)
            let digits = e164.dropFirst().filter(\.isNumber)
            return Normalized(
                e164: e164,
                digits: digits,
                nationalDigits: nationalDigits(from: digits, defaultDial: defaultDial)
            )
        }

        // 情况2：号码以 + 开头 → 直接保留 + 和纯数字
        if compact.hasPrefix("+") {
            let e164 = "+" + String(compact.dropFirst()).filter(\.isNumber)
            let digits = e164.dropFirst().filter(\.isNumber)
            return Normalized(
                e164: e164,
                digits: digits,
                nationalDigits: nationalDigits(from: digits, defaultDial: defaultDial)
            )
        }

        // 情况3：号码已经包含国家码数字（如 86153xxxxxxx）
        // 判断条件：区号非空 + 输入以区号开头 + 号码长度足够长
        if dialDigits.isEmpty == false,
           digitsOnly.hasPrefix(dialDigits),
           digitsOnly.count > max(11, dialDigits.count + 6) {
            let e164 = "+" + digitsOnly
            // 去掉国家码，保留国内号码
            let national = String(digitsOnly.dropFirst(dialDigits.count))
            return Normalized(e164: e164, digits: digitsOnly, nationalDigits: national)
        }

        // 情况4：普通本地号码 → 直接拼接默认国家码
        let prefixedDigits = dialDigits + digitsOnly
        let e164 = "+" + prefixedDigits
        return Normalized(e164: e164, digits: prefixedDigits, nationalDigits: digitsOnly)
    }

    /// 尝试从完整国际手机号中识别区号，并返回去除区号后的本地号码。
    ///
    /// 支持 `+861538...`、`00861538...`、`861538...` 等格式。
    /// 使用最长区号优先匹配，避免 `+86` 被误判成 `+8` 这类短前缀。
    static func detectRegionNumber(rawInput: String, supportedDials: [String]) -> DetectedRegionNumber? {
        let compact = compactPhoneInput(rawInput)
        guard compact.isEmpty == false else { return nil }

        let digitsAfterPrefix: String
        if compact.hasPrefix("00") {
            digitsAfterPrefix = String(compact.dropFirst(2)).filter(\.isNumber)
        } else if compact.hasPrefix("+") {
            digitsAfterPrefix = String(compact.dropFirst()).filter(\.isNumber)
        } else {
            digitsAfterPrefix = compact.filter(\.isNumber)
        }
        guard digitsAfterPrefix.isEmpty == false else { return nil }

        guard let dial = bestMatchingDial(in: digitsAfterPrefix, supportedDials: supportedDials) else {
            return nil
        }

        let dialDigits = dial.filter(\.isNumber)
        guard digitsAfterPrefix.count > max(11, dialDigits.count + 6) else { return nil }

        return DetectedRegionNumber(
            dial: dial,
            nationalDigits: String(digitsAfterPrefix.dropFirst(dialDigits.count))
        )
    }

    private static func compactPhoneInput(_ rawInput: String) -> String {
        rawInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
    }

    private static func bestMatchingDial(in digits: String, supportedDials: [String]) -> String? {
        supportedDials
            .filter { $0.filter(\.isNumber).isEmpty == false }
            .sorted { $0.filter(\.isNumber).count > $1.filter(\.isNumber).count }
            .first { digits.hasPrefix($0.filter(\.isNumber)) }
    }

    private static func nationalDigits(from digits: String, defaultDial: String) -> String {
        guard let dial = bestMatchingDial(in: digits, supportedDials: [defaultDial]) else {
            return digits
        }

        let dialDigits = dial.filter(\.isNumber)
        guard digits.count > max(11, dialDigits.count + 6) else { return digits }
        return String(digits.dropFirst(dialDigits.count))
    }
}
