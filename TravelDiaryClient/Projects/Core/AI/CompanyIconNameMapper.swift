import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum CompanyIconNameMapper {
    static func imageName(for companyName: String) -> String {
        let normalized = companyName.uppercased()
        let isDarkMode = currentInterfaceStyleIsDark()

        switch normalized {
        case "HANLIN":
            return "hanlin"
        case "HANLIN_OPEN":
            return "hanlin"
        case "ZHIPUAI":
            return isDarkMode ? "zhipuai_dark" : "zhipuai"
        case "QWEN":
            return "qwen"
        case "DEEPSEEK":
            return "deepseek"
        case "SILICONCLOUD":
            return "siliconflow"
        case "GITHUB":
            return isDarkMode ? "github_dark" : "github"
        case "DOUBAO":
            return "doubao"
        case "KIMI":
            return isDarkMode ? "kimi_dark" : "kimi"
        case "OPENAI":
            return isDarkMode ? "openai_dark" : "openai"
        case "GOOGLE":
            return "google"
        case "GOOGLE_SEARCH":
            return "google_search"
        case "XAI":
            return isDarkMode ? "xai_dark" : "xai"
        case "ANTHROPIC":
            return "claude"
        case "LOCAL":
            return "assistant"
        case "MODELSCOPE":
            return "modelscope"
        case "LAN":
            return isDarkMode ? "lm_studio_dark" : "lm_studio"
        case "WENXIN":
            return "wenxin"
        case "YI":
            return isDarkMode ? "yi_dark" : "yi"
        case "HUNYUAN":
            return "hunyuan"
        case "STEP":
            return "step"
        case "BOCHAAI":
            return "bochaai"
        case "BING":
            return "bing"
        case "EXA":
            return "exa"
        case "TAVILY":
            return "tavily"
        case "LANGSEARCH":
            return "langsearch"
        case "TIANGONG":
            return "tiangong"
        case "SPARK":
            return "spark"
        case "PERPLEXITY":
            return "perplexity"
        case "OPENROUTER":
            return isDarkMode ? "openrouter_dark" : "openrouter"
        case "HANLINWEB":
            return "webreader"
        case "HANLINBAG":
            return "knowledge_bag"
        case "BRAVE":
            return "brave"
        case "JINA", "SEARXNG", "DUCKDUCKGO", "SERPER", "NONE":
            return "defaultIcon"
        case "SIRI":
            return "siri"
        case "GITEE":
            return isDarkMode ? "gitee_dark" : "gitee"
        case "APPLEMAP":
            return "applemap"
        case "AMAP":
            return "amap"
        case "BAIDUMAP":
            return "baidumap"
        case "GOOGLEMAP":
            return "googlemap"
        case "ARXIV":
            return "arxiv"
        case "QWEATHER":
            return isDarkMode ? "qweather_dark" : "qweather"
        case "OPENWEATHER":
            return "openweather"
        case "MINIMAX":
            return "minimax"
        case "CHERRY_IN":
            return "cherry"
        case "MIMO":
            return isDarkMode ? "mimo_dark" : "mimo"
        case "LONGCAT":
            return isDarkMode ? "longcat_dark" : "longcat"
        case "AI302":
            return "ai302"
        case "POE":
            return isDarkMode ? "poe_dark" : "poe"
        case "AIHUBMIX":
            return "aihubmix"
        case "IFLOW":
            return "iflow"
        case "N1N":
            return "n1n"
        default:
            return "defaultIcon"
        }
    }

    private static func currentInterfaceStyleIsDark() -> Bool {
#if canImport(UIKit)
        return UITraitCollection.current.userInterfaceStyle == .dark
#else
        return false
#endif
    }
}

func companyIconName(for companyName: String) -> String {
    CompanyIconNameMapper.imageName(for: companyName)
}
