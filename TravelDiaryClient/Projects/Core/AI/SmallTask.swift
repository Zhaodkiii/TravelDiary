import Foundation

/// 任务来源类型（本地 / 服务端）
enum TaskSource: String, Codable, Sendable {
    case local = "Local"    // 本地任务
    case service = "Service" // 服务端任务
}

/// 小任务模型（客户端核心数据结构）
/// 与后端 Django SmallTask 模型字段一一对应
nonisolated struct SmallTask: Codable, Identifiable, Equatable, Sendable {
    // MARK: - 模型属性
    /// 后端主键 id
    var id: Int
    
    /// 任务名称
    var name: String
    
    /// 唯一编码（用于路由，如 Local_1 / Service_2）
    var code: String
    
    /// 任务简介（短描述）
    var brief: String
    
    /// 完整任务规则 / Prompt
    var prompt: String
    
    /// 任务图标名称/URL
    var icon: String
    
    /// 调用工具列表
    var toolList: [String]

    /// 任务来源（本地/服务端）
    var source: TaskSource

    // MARK: - 便捷创建方法
    /// 快速创建【本地任务】（自动生成 code）
    nonisolated static func createLocalTask(
        id: Int,
        name: String,
        brief: String,
        prompt: String,
        icon: String,
        toolList: [String]
    ) -> SmallTask {
        SmallTask(
            id: id,
            name: name,
            code: "Local_\(id)", // 自动生成本地任务编码
            brief: brief,
            prompt: prompt,
            icon: icon,
            toolList: toolList,
            source: .local
        )
    }
}
