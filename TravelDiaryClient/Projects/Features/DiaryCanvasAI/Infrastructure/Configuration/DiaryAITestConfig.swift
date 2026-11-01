import Foundation

/// Deliberately isolated test-only transport configuration. Never persisted in tasks or works.
enum DiaryAITestConfig {
    static let endpoint = URL(string: "https://ark.cn-beijing.volces.com/api/v3/responses")!
    static let model = "glm-5-3-flash-260828"
    // 测试密钥由运行环境注入，避免凭据进入 Git 仓库。
    static let apiKey = ProcessInfo.processInfo.environment["DIARY_AI_API_KEY"] ?? ""
}
