import Foundation

protocol AISettingsRepository: Sendable {
    /// - Parameter ownerAccountID: 登录引导等场景传入当前会话账号，保证与 `UserSession` 一致；`nil` 时从 `SessionSnapshotStore` 解析。
    /// 目录数据以该账号本地 Core Data 为准；bundle 种子仅在首次初始化时写入一次。
    func loadSnapshot(ownerAccountID: Int64?) async -> AISettingsSnapshot
    func save(snapshot: AISettingsSnapshot) async throws
    /// 与 `loadSnapshot(ownerAccountID:)` 对称的保存入口；`nil` 时由仓储解析当前会话。
    func save(snapshot: AISettingsSnapshot, ownerAccountID: Int64?) async throws
    /// 单条更新模型目录（按 `id` upsert）。
    func saveModel(_ model: AllModels) async throws
    /// 单条更新场景绑定（按 `id` upsert）。
    func saveScenarioBinding(_ binding: AIScenarioModelBinding, ownerAccountID: Int64?) async throws
    /// 删除场景绑定（按 `id`）。
    func deleteScenarioBinding(id: UUID, ownerAccountID: Int64?) async throws
    /// 单条更新厂商配置（按 `id` upsert）。
    func saveProvider(_ provider: APIKeys) async throws
    /// 单条更新联网搜索厂商配置（按 `id` upsert）。
    func saveSearchKey(_ searchKey: SearchKeys, ownerAccountID: Int64?) async throws
    /// 删除联网搜索厂商配置（按 `id`）。
    func deleteSearchKeys(ids: [UUID], ownerAccountID: Int64?) async throws
    /// 更新搜索工具轻量偏好，持久化到账号级偏好载荷。
    func saveSearchToolPreferences(_ preferences: AISearchToolPreferences, revision: SearchRuntimeConfigRevision, searchKeys: [SearchKeys]?, ownerAccountID: Int64?) async throws
    /// 更新当前账号的提示词库（按列表顺序写入 `position`）。
    func savePromptRepo(_ promptRepo: [PromptRepo], ownerAccountID: Int64?) async throws
}

extension AISettingsRepository {
    func loadSnapshot() async -> AISettingsSnapshot {
        await loadSnapshot(ownerAccountID: nil)
    }

    func save(snapshot: AISettingsSnapshot) async throws {
        try await save(snapshot: snapshot, ownerAccountID: nil)
    }
}
