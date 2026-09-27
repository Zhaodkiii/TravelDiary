# SUPPORT-AI-CORE-DATA-000001：AI 设置 CoreData 持久化与初始化流程对齐 SparkClient 需求工单

| 字段 | 内容 |
| --- | --- |
| 工单编号 | `SUPPORT-AI-CORE-DATA-000001` |
| 工单类型 | 架构迁移 / 数据持久化 / AISettings 底座补齐 |
| 创建日期 | 2026-07-08 |
| 目标项目 | `/Users/hua/Downloads/Reference/SupportClient` |
| 参考项目 | `/Users/hua/Downloads/Reference/SparkClient` |
| 优先级 | P0 |
| 当前状态 | 新建 / 待实现 |
| 关联总工单 | `SUPPORT-ARCH-000001` |
| 关键目标 | 将 SparkClient 的 AI 相关 Core Data 实体结构迁入 SupportClient，并将 AISettings 仓储从 `AIRuntimeConfigStore` 临时存储切换为账号级 Core Data 持久化 |

## 1. 背景说明

当前 `SupportClient` 已经迁入了部分 AISettings 页面、AISettings seed loader、AI runtime 配置模型、AI 设置页入口、模型管理、API Key 管理、默认模型选择等功能。但是本地数据库层尚未与 `SparkClient` 对齐。

当前事实：

1. `SupportClient` 的 Core Data 模型仍是模板态。

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/SupportClient.xcdatamodeld/SupportClient.xcdatamodel/contents
```

当前仅包含：

```text
Item(timestamp)
```

2. `SparkClient` 的 Core Data 模型已经包含完整 AI 相关实体。

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Resources/SparkClient.xcdatamodeld/SparkClient.xcdatamodel/contents
```

其中 AI 相关实体包含：

```text
AIModelEntity
AIProviderEntity
AISearchProviderEntity
AIScenarioBundleCacheEntity
AIScenarioModelBindingEntity
AISettingsSeedStateEntity
AISmallTaskEntity
PromptRepoEntity
MemoryRecordEntity
```

3. `SupportClient` 的 AISettings 当前还没有真正使用 Core Data。

当前 `SupportClient` 的 `DefaultAISettingsRepository` 仍然只是包了一层 `AIRuntimeConfigStore`：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Features/AISettings/Infrastructure/DefaultAISettingsRepository.swift
```

当前行为：

```swift
func loadSnapshot(ownerAccountID: Int64?) async -> AISettingsSnapshot {
    await store.load().settingsSnapshot
}

func save(snapshot: AISettingsSnapshot, ownerAccountID: Int64?) async throws {
    _ = await store.apply(seed: snapshot)
}
```

这意味着：

1. AI provider、model、scenario binding、small task、prompt repo 等目录数据没有写入 Core Data。
2. 当前数据持久化不是账号隔离的 Core Data 持久化。
3. 首次登录 seed 初始化流程与 SparkClient 不一致。
4. App 重装、账号切换、不同账号 AI 配置隔离、AI 设置后续扩展都存在风险。

本工单要求把这部分补齐，并做到与 `SparkClient` 内 AI 设置初始化相关流程完全一致。

## 2. 总目标

完成后，`SupportClient` 必须具备与 `SparkClient` 一致的 AISettings 本地持久化能力：

1. `SupportClient.xcdatamodeld` 内具备 SparkClient AISettings 所需 Core Data 实体。
2. `DefaultAISettingsRepository` 使用 `CoreDataStack` 读写账号级 AISettings 数据。
3. `AISettings/APIKeys.json`、`AISettings/AllModels.json`、场景绑定 seed 仅在账号首次初始化时灌入 Core Data。
4. 后续用户修改 API Key、模型、模型启用状态、默认模型、small task、prompt repo 等数据时，写入 Core Data 或账号级偏好载荷。
5. `AIRuntimeConfigStore` 继续保留为运行时配置缓存/运行时快照能力，但不再承担 AISettings 主存储职责。
6. 首次登录、冷启动、账号切换、AI 设置页打开、试用状态刷新、远程配置刷新流程均与 SparkClient 行为一致。

## 3. 非目标

本工单不要求迁移 SparkClient 的全部业务数据库实体。

明确不在本工单范围内：

1. Chat 全量数据实体：`ChatMessageEntity`、`ChatThreadEntity`、`ChatMessageBlockEntity` 等。
2. Knowledge 全量实体：`KnowledgeDocumentEntity`、`KnowledgeChunkEntity` 等。
3. 医疗业务实体：`ExaminationReportEntity` 等。
4. SparkClient 专属医疗、营养、聊天业务 UI。
5. 后台服务端接口改造。

本工单只处理 AISettings 初始化与持久化所需实体和仓储。

## 4. 参考文件

### 4.1 SparkClient 参考文件

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Resources/SparkClient.xcdatamodeld/SparkClient.xcdatamodel/contents
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Infrastructure/DefaultAISettingsRepository.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Domain/AISettingsRepository.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Domain/AISettingsSnapshot.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Domain/AISettingsSeedLoader.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsViewModel.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/AISettings/APIKeys.json
/Users/hua/Downloads/Reference/SparkClient/SparkClient/AISettings/AllModels.json
```

### 4.2 SupportClient 目标文件

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/SupportClient.xcdatamodeld/SupportClient.xcdatamodel/contents
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Core/Database/CoreDataStack.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Features/AISettings/Infrastructure/DefaultAISettingsRepository.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Features/AISettings/Application/LoadAISettingsUseCase.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Features/AISettings/Application/SaveAISettingsUseCase.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Features/AISettings/AISettingsStore.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App/AppContainer.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/AISettings/APIKeys.json
/Users/hua/Downloads/Reference/SupportClient/SupportClient/AISettings/AllModels.json
```

## 5. 当前问题拆解

### 5.1 数据库 schema 不一致

`SupportClient.xcdatamodeld` 当前只有模板实体：

```text
Item
  timestamp: Date?
```

`SparkClient.xcdatamodeld` 已包含 AISettings 所需实体和字段。

如果不迁移 schema，后续无法实现：

1. 账号级 provider/API Key 持久化。
2. 账号级模型目录持久化。
3. 场景默认模型绑定持久化。
4. small task 本地持久化。
5. PromptRepo 本地持久化。
6. seed 是否已灌库的状态判断。

### 5.2 仓储层职责不一致

`SparkClient` 的 `DefaultAISettingsRepository` 职责：

1. 使用 `CoreDataStack` 读写 AISettings 目录数据。
2. 使用 `SessionSnapshotStore` 或显式 `ownerAccountID` 获取当前账号。
3. 首次加载某账号时，通过 `AISettingsSeedStateEntity` 判断是否需要灌 seed。
4. 从 bundle 读取 seed 数据并写入 Core Data。
5. 使用 UserDefaults 保存轻量偏好载荷。
6. 支持模型、provider、search key、scenario binding、prompt repo 等单条 upsert。

`SupportClient` 当前仓储职责：

1. 从 `AIRuntimeConfigStore` 读取快照。
2. 将 snapshot 作为 seed 写回 runtime store。
3. 没有 Core Data 读写。
4. 没有账号级 seed 状态。
5. 没有单条实体 upsert。

### 5.3 初始化流程不一致

`SparkClient` 流程：

```text
用户登录
  → AppContainer 创建账号级 AISettingsViewModel
  → AISettingsViewModel.load()
  → LoadAISettingsUseCase.execute(ownerAccountID)
  → DefaultAISettingsRepository.loadSnapshot(ownerAccountID)
  → ensureSeedDataIfNeeded(ownerAccountID)
  → 首次账号：读取 AISettings/*.json 并写入 Core Data
  → 读取 Core Data 目录数据
  → 读取 UserDefaults 偏好 payload
  → 返回完整 AISettingsSnapshot
  → AIConfigCenter / runtime cache 基于 snapshot 建立运行时配置
```

`SupportClient` 当前流程：

```text
AISettingsStore.load()
  → runtimeStore.load()
  → 如果 empty，runtimeStore.apply(seed: AISettingsSnapshot.seeded())
```

当前流程没有：

1. 账号级 `ownerAccountID`。
2. Core Data seed 状态。
3. Core Data 目录读写。
4. UserDefaults 账号级偏好 payload。
5. 与 SparkClient 一致的首次登录初始化语义。

## 6. 目标数据库实体

必须将以下 AI 相关实体迁入 `SupportClient.xcdatamodeld`。

### 6.1 `AIProviderEntity`

用途：保存账号级 AI provider / API Key 配置。

字段要求：

| 字段 | 类型 | 默认值/可选 | 说明 |
| --- | --- | --- | --- |
| `id` | UUID | 必填 | provider 记录唯一 ID |
| `ownerAccountID` | Integer 64 | 默认 `0` | 账号隔离 |
| `providerID` | String | 默认 `""` | 标准化 provider 标识 |
| `name` | String | 默认 `""` | provider 名称 |
| `company` | String | 默认 `""` | 公司标识 |
| `key` | String | 默认 `""` | API Key |
| `requestURL` | String | 默认 `""` | 请求地址 |
| `help` | String | 默认 `""` | 帮助说明 |
| `from` | String | 默认 `system` | 来源 |
| `privacyPolicyURL` | String | 默认 `""` | 隐私协议链接 |
| `privacyPolicyAccepted` | Boolean | 默认 `NO` | 是否接受隐私协议 |
| `privacyPolicyAcceptedAt` | Date | 可选 | 接受时间 |
| `isEnabled` | Boolean | 默认 `YES` | 是否启用 |
| `source` | String | 默认 `system` | 系统/自定义/Pro |
| `timestamp` | Date | 必填 | 更新时间 |

映射 domain model：

```text
APIKeys
```

### 6.2 `AIModelEntity`

用途：保存账号级模型目录。

字段要求：

| 字段 | 类型 | 默认值/可选 | 说明 |
| --- | --- | --- | --- |
| `id` | UUID | 必填 | 模型记录 ID |
| `ownerAccountID` | Integer 64 | 默认 `0` | 账号隔离 |
| `name` | String | 默认 `""` | 模型调用名 |
| `displayName` | String | 默认 `""` | UI 展示名 |
| `identity` | String | 默认 `model` | model / agent |
| `position` | Integer 32 | 默认 `0` | 排序 |
| `providerID` | String | 默认 `""` | provider 标识 |
| `company` | String | 默认 `""` | 公司 |
| `price` | Integer 32 | 默认 `0` | 价格等级 |
| `isEnabled` | Boolean | 默认 `YES` | 是否启用 |
| `supportsSearch` | Boolean | 默认 `NO` | 是否支持搜索 |
| `supportsTextGen` | Boolean | 默认 `YES` | 是否支持文本 |
| `supportsMultimodal` | Boolean | 默认 `NO` | 是否支持多模态 |
| `supportsReasoning` | Boolean | 默认 `NO` | 是否支持推理 |
| `supportReasoningChange` | Boolean | 默认 `NO` | 是否支持推理开关 |
| `supportsImageGen` | Boolean | 默认 `NO` | 是否支持图片生成 |
| `supportsVoiceGen` | Boolean | 默认 `NO` | 是否支持语音生成 |
| `supportsToolUse` | Boolean | 默认 `NO` | 是否支持工具调用 |
| `systemProvision` | String | 默认 `""` | 系统预置 prompt |
| `icon` | String | 默认 `""` | icon 名称 |
| `briefDescription` | String | 默认 `""` | 简介 |
| `characterDesign` | String | 默认 `""` | 角色设定 |
| `aiToolScenariosData` | Binary | 可选 | 工具场景数组 JSON |
| `relatedTaskCodesData` | Binary | 可选 | 关联任务 code 数组 JSON |
| `baseModelName` | String | 可选 | agent / derivative 基座模型 |
| `localFilename` | String | 可选 | 本地模型文件名 |
| `source` | String | 默认 `system` | 系统/自定义/Pro |
| `timestamp` | Date | 必填 | 更新时间 |

映射 domain model：

```text
AllModels
```

### 6.3 `AIScenarioModelBindingEntity`

用途：保存场景到模型的绑定关系。

字段要求：

| 字段 | 类型 | 默认值/可选 | 说明 |
| --- | --- | --- | --- |
| `id` | UUID | 必填 | 绑定 ID |
| `ownerAccountID` | Integer 64 | 默认 `0` | 账号隔离 |
| `scenario` | String | 默认 `chat` | AI 场景 |
| `identity` | String | 默认 `model` | model / agent |
| `modelID` | UUID | 必填 | 绑定的模型 ID |
| `temperature` | Double | 默认 `0.2` | 温度 |
| `maxTokens` | Integer 32 | 必填 | 最大 token |
| `position` | Integer 32 | 默认 `0` | 排序 |
| `isDefault` | Boolean | 默认 `NO` | 是否默认 |
| `isActive` | Boolean | 默认 `YES` | 是否启用 |
| `systemProvision` | String | 默认 `""` | 场景系统 prompt |
| `briefDescription` | String | 默认 `""` | 简介 |
| `aiToolScenariosData` | Binary | 可选 | 工具场景数组 JSON |
| `relatedTaskCodesData` | Binary | 可选 | 关联任务 code 数组 JSON |
| `createdAt` | Date | 必填 | 创建时间 |
| `updatedAt` | Date | 必填 | 更新时间 |

映射 domain model：

```text
AIScenarioModelBinding
```

### 6.4 `AISearchProviderEntity`

用途：保存联网搜索 provider 配置。

字段要求：

| 字段 | 类型 | 默认值/可选 | 说明 |
| --- | --- | --- | --- |
| `id` | UUID | 必填 | 搜索 provider ID |
| `ownerAccountID` | Integer 64 | 默认 `0` | 账号隔离 |
| `name` | String | 默认 `""` | 名称 |
| `company` | String | 默认 `""` | 公司 |
| `key` | String | 默认 `""` | API Key |
| `requestURL` | String | 默认 `""` | 请求地址 |
| `isUsing` | Boolean | 默认 `NO` | 是否使用 |
| `searchClass` | String | 默认 `web` | 搜索类型 |
| `help` | String | 默认 `""` | 帮助 |
| `source` | String | 默认 `system` | 来源 |
| `authType` | String | 默认 `bearer` | 鉴权方式 |
| `priority` | Integer 32 | 默认 `0` | 优先级 |
| `enabledScopesData` | Binary | 可选 | 启用 scope |
| `revision` | Integer 32 | 默认 `1` | 配置修订号 |
| `timestamp` | Date | 必填 | 更新时间 |

映射 domain model：

```text
SearchKeys
```

### 6.5 `AISmallTaskEntity`

用途：保存本地 small task。

字段要求：

| 字段 | 类型 | 默认值/可选 | 说明 |
| --- | --- | --- | --- |
| `id` | Integer 64 | 默认 `0` | small task 原始 ID |
| `ownerAccountID` | Integer 64 | 默认 `0` | 账号隔离 |
| `code` | String | 默认 `""` | 唯一 code |
| `name` | String | 默认 `""` | 名称 |
| `brief` | String | 默认 `""` | 简介 |
| `prompt` | String | 默认 `""` | prompt |
| `icon` | String | 默认 `""` | icon |
| `source` | String | 默认 `Local` | 来源 |
| `toolListData` | Binary | 可选 | 工具列表 JSON |
| `timestamp` | Date | 必填 | 更新时间 |

映射 domain model：

```text
SmallTask
```

### 6.6 `PromptRepoEntity`

用途：保存提示词库。

字段要求：

| 字段 | 类型 | 默认值/可选 | 说明 |
| --- | --- | --- | --- |
| `id` | UUID | 必填 | prompt ID |
| `ownerAccountID` | Integer 64 | 默认 `0` | 账号隔离 |
| `title` | String | 默认 `""` | 标题 |
| `content` | String | 默认 `""` | 内容 |
| `isSystem` | Boolean | 默认 `YES` | 是否系统 prompt |
| `localizationKey` | String | 可选 | 本地化 key |
| `position` | Integer 32 | 默认 `0` | 排序 |
| `timestamp` | Date | 必填 | 更新时间 |

映射 domain model：

```text
PromptRepo
```

### 6.7 `AISettingsSeedStateEntity`

用途：标记某个账号是否已经完成 AISettings 首次灌库。

字段要求：

| 字段 | 类型 | 默认值/可选 | 说明 |
| --- | --- | --- | --- |
| `ownerAccountID` | Integer 64 | 默认 `0` | 账号隔离 |
| `catalogVersion` | Integer 32 | 默认 `0` | seed catalog 版本 |
| `updatedAt` | Date | 必填 | 更新时间 |

关键要求：

1. 不允许每次启动都重灌 seed。
2. `catalogVersion` 只用于排查，不直接触发强制覆盖用户数据。
3. 只要该账号存在 `AISettingsSeedStateEntity`，就说明已经完成首次灌库。

### 6.8 `AIScenarioBundleCacheEntity`

用途：缓存账号级远程场景 bundle payload。

字段要求：

| 字段 | 类型 | 默认值/可选 | 说明 |
| --- | --- | --- | --- |
| `ownerAccountID` | Integer 64 | 默认 `0` | 账号隔离 |
| `payloadData` | Binary | 可选 | 编码后的 remote bundle collection |
| `updatedAt` | Date | 必填 | 更新时间 |

说明：

1. SparkClient 当前仓储注释说明 Pro 场景 bundle 等运行时数据不全部在此主仓储持久化。
2. SupportClient 是否启用该缓存由实现时结合 `AIRuntimeConfigStore` 和 `AIConfigCenter` 决定。
3. 如果保留实体，必须确保不会与 runtime remote config 的数据来源冲突。

### 6.9 `MemoryRecordEntity`

用途：保存 AI 记忆档案。

字段要求：

| 字段 | 类型 | 默认值/可选 | 说明 |
| --- | --- | --- | --- |
| `id` | UUID | 必填 | 记忆 ID |
| `ownerAccountID` | Integer 64 | 默认 `0` | 账号隔离 |
| `title` | String | 默认 `""` | 标题 |
| `content` | String | 默认 `""` | 内容 |
| `pinned` | Boolean | 默认 `NO` | 是否置顶 |
| `createdAt` | Date | 必填 | 创建时间 |
| `updatedAt` | Date | 必填 | 更新时间 |

说明：

1. 若 SupportClient 当前 AI 设置页尚未开放 MemoryArchive 页面，实体仍建议先迁入。
2. 后续迁移 SparkClient 的 Personalization / Memory 页面时可直接复用。

## 7. 仓储层目标设计

### 7.1 `AISettingsRepository` 协议对齐

`SupportClient` 当前协议过窄。

目标协议需要对齐 SparkClient：

```swift
protocol AISettingsRepository: Sendable {
    func loadSnapshot(ownerAccountID: Int64?) async -> AISettingsSnapshot
    func save(snapshot: AISettingsSnapshot) async throws
    func save(snapshot: AISettingsSnapshot, ownerAccountID: Int64?) async throws

    func saveModel(_ model: AllModels) async throws
    func saveScenarioBinding(_ binding: AIScenarioModelBinding, ownerAccountID: Int64?) async throws
    func deleteScenarioBinding(id: UUID, ownerAccountID: Int64?) async throws

    func saveProvider(_ provider: APIKeys) async throws
    func saveSearchKey(_ searchKey: SearchKeys, ownerAccountID: Int64?) async throws
    func deleteSearchKeys(ids: [UUID], ownerAccountID: Int64?) async throws

    func saveSearchToolPreferences(
        _ preferences: AISearchToolPreferences,
        revision: SearchRuntimeConfigRevision,
        searchKeys: [SearchKeys]?,
        ownerAccountID: Int64?
    ) async throws

    func savePromptRepo(_ promptRepo: [PromptRepo], ownerAccountID: Int64?) async throws
}
```

如果 SupportClient 现阶段缺少部分 UI 功能，也要保留协议能力，方便后续迁移完整 Spark AISettings 页面。

### 7.2 `DefaultAISettingsRepository` 构造参数

目标构造：

```swift
final class DefaultAISettingsRepository: AISettingsRepository, @unchecked Sendable {
    init(
        coreDataStack: CoreDataStack,
        snapshotStore: SessionSnapshotStore = SessionSnapshotStore(),
        defaults: UserDefaults = .standard,
        logger: Logger = ConsoleLogger()
    )
}
```

必须移除将 `AIRuntimeConfigStore` 当主存储的设计。

当前：

```swift
struct DefaultAISettingsRepository: AISettingsRepository {
    let store: AIRuntimeConfigStore
}
```

目标：

```swift
final class DefaultAISettingsRepository: AISettingsRepository, @unchecked Sendable {
    private let coreDataStack: CoreDataStack
    private let snapshotStore: SessionSnapshotStore
    private let defaults: UserDefaults
    private let logger: Logger
}
```

### 7.3 存储职责划分

Core Data 存储：

1. `apiKeys` → `AIProviderEntity`
2. `allModels` → `AIModelEntity`
3. `scenarioBindings` → `AIScenarioModelBindingEntity`
4. `smallTasks` → `AISmallTaskEntity`
5. `searchKeys` → `AISearchProviderEntity`
6. `promptRepo` → `PromptRepoEntity`
7. `seedState` → `AISettingsSeedStateEntity`
8. `memoryArchive` → `MemoryRecordEntity`，如果迁移 MemoryArchive 页面。

UserDefaults 存储：

1. `AISettingsSnapshot.PreferencesPayload`
2. `scenarioModelSources`
3. `trial`
4. `searchToolPreferences`
5. `searchConfigRevision`
6. 其他轻量偏好字段。

运行时缓存：

1. `AIRuntimeConfigStore` 继续保存运行时可快速读取的 `AIRuntimeConfiguration`。
2. `AIConfigCenter` 如果迁入，负责基于 repository snapshot 构建 runtime cache。
3. Runtime cache 不能替代 Core Data 主存储。

## 8. 首次登录初始化流程

### 8.1 触发时机

必须覆盖：

1. 首次登录成功后。
2. App 冷启动恢复已登录会话后。
3. 打开 AISettings 页面前。
4. `AIConfigCenter` 或运行时解析默认模型前。

### 8.2 输入来源

Seed 来源：

```text
SupportClient/SupportClient/AISettings/APIKeys.json
SupportClient/SupportClient/AISettings/AllModels.json
SupportClient/SupportClient/Projects/Features/AISettings/Domain/AISettingsSeedLoader.swift
```

### 8.3 判断是否需要灌库

逻辑必须与 SparkClient 一致：

```text
fetch AISettingsSeedStateEntity where ownerAccountID == currentAccountID
  if nil:
    needs first init
  else:
    already initialized
```

禁止使用以下方式作为唯一判断：

1. Core Data 中 provider 行是否为空。
2. Core Data 中 model 行是否为空。
3. UserDefaults 是否有 runtime config。
4. `AIRuntimeConfigStore` 是否 empty。

原因：

1. 用户可能手动删除全部 provider 或模型。
2. runtime config 可能被清理。
3. UserDefaults 与 Core Data 不具备同等一致性语义。

### 8.4 首次灌库内容

首次账号需要写入：

1. `AIProviderEntity`：来自 `APIKeys.json`。
2. `AIModelEntity`：来自 `AllModels.json`。
3. `AIScenarioModelBindingEntity`：来自 `AISettingsSeedCatalog.getScenarioBindings(for:)`。
4. `AISearchProviderEntity`：如 SupportClient 保留搜索能力，则来自 seed catalog。
5. `AISmallTaskEntity`：默认可为空，除非 SupportClient 迁入 small task seed。
6. `PromptRepoEntity`：默认可为空，除非 SupportClient 迁入 prompt repo seed。
7. `AISettingsSeedStateEntity`：写入 `ownerAccountID`、`catalogVersion`、`updatedAt`。
8. UserDefaults：写入 `AISettingsSnapshot.PreferencesPayload` 默认 payload。

### 8.5 灌库失败策略

必须做到：

1. 如果 `AllModels.json` 为空或解码失败，不写入 `AISettingsSeedStateEntity`。
2. 如果部分实体写入失败，事务回滚。
3. 下次进入时仍然可以重试首次灌库。
4. 错误必须进入 logger，不允许静默失败。

## 9. 账号隔离要求

所有 AISettings 持久化数据必须带 `ownerAccountID`。

必须覆盖：

1. provider
2. model
3. search provider
4. scenario binding
5. small task
6. prompt repo
7. memory record
8. seed state
9. scenario bundle cache
10. UserDefaults preferences payload key

UserDefaults key 格式建议对齐 SparkClient：

```swift
"spark.ai.prefs.payload.\(accountID)"
```

或在 SupportClient 中使用同等语义命名：

```swift
"support.ai.prefs.payload.\(accountID)"
```

要求：

1. 账号 A 的 API Key 不得出现在账号 B。
2. 账号 A 的默认模型选择不影响账号 B。
3. 登出不强制删除本地账号 AI 配置，除非用户明确清理本地数据。
4. 切换账号后必须按新账号 `ownerAccountID` load snapshot。

## 10. AISettingsStore / ViewModel 改造要求

`SupportClient` 当前 `AISettingsViewModel` 是：

```swift
typealias AISettingsViewModel = AISettingsStore
```

`AISettingsStore` 当前直接持有：

```swift
private let runtimeStore: AIRuntimeConfigStore
```

目标改造：

1. `AISettingsStore` 不再直接从 `AIRuntimeConfigStore` 加载主 snapshot。
2. `AISettingsStore` 通过 `LoadAISettingsUseCase` / `SaveAISettingsUseCase` 读写 repository。
3. `AISettingsStore` 可以继续维护 `AIRuntimeConfiguration`，但该配置来自 repository snapshot 重建。
4. 所有 `setProviderEnabledAndPersist`、`setModelEnabledAndPersist`、`upsertProviderAndPersist`、`upsertModelAndPersist`、`deleteModelAndPersist` 等操作必须最终落到 Core Data。
5. 修改后立即持久化的行为要和 SparkClient 保持一致。

建议目标形态：

```swift
@MainActor
final class AISettingsStore: ObservableObject {
    @Published private(set) var configuration: AIRuntimeConfiguration = .empty
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?

    private let loadUseCase: LoadAISettingsUseCase
    private let saveUseCase: SaveAISettingsUseCase
    private let api: SupportAIConfigAPI
    private let runtimeStore: AIRuntimeConfigStore
    private let notificationStore: NotificationStore
    private let ownerAccountIDForLoad: Int64?
}
```

如果保持现有 `AISettingsStore` 命名，也必须补齐 SparkClient `AISettingsViewModel` 的核心行为：

1. `load()`
2. `loadIfNeeded()`
3. `save()`
4. `persistSnapshotNow()`
5. `refreshProviderRuntimeConfiguration()`
6. `submitTrialApplication()`
7. provider 立即保存
8. model 立即保存
9. small task 立即保存
10. scenario preference 修改立即保存或按 Spark 行为保存

## 11. AppContainer 装配要求

当前 `SupportClient` 装配：

```swift
let aiRuntimeStore = AIRuntimeConfigStore()
let aiSettingsStore = AISettingsStore(
    api: backend.aiConfig,
    runtimeStore: aiRuntimeStore,
    notificationStore: notificationStore
)
```

目标装配：

```swift
let aiSettingsRepository = DefaultAISettingsRepository(
    coreDataStack: coreDataStack,
    snapshotStore: snapshotStore,
    logger: logger
)

let aiSettingsStore = AISettingsStore(
    loadUseCase: LoadAISettingsUseCase(repository: aiSettingsRepository),
    saveUseCase: SaveAISettingsUseCase(repository: aiSettingsRepository),
    api: backend.aiConfig,
    runtimeStore: aiRuntimeStore,
    notificationStore: notificationStore,
    ownerAccountIDForLoad: session.accountID 或通过 lifecycle/main coordinator 注入
)
```

要求：

1. `AppContainer` 必须持有同一个 `CoreDataStack.shared`。
2. `DefaultAISettingsRepository` 必须与 `AppSessionStore` / `SessionSnapshotStore` 使用同一套账号来源。
3. 首次登录后必须能显式传入 `session.accountID`，避免 session snapshot 写入时序导致首登灌库读不到账号。
4. 账号切换后必须重建或刷新账号级 `AISettingsStore`。

## 12. 数据读写映射要求

### 12.1 Provider upsert

输入：

```text
APIKeys
```

写入：

```text
AIProviderEntity
```

匹配条件：

```text
ownerAccountID == currentAccountID AND id == provider.id
```

行为：

1. 存在则更新全部字段。
2. 不存在则插入。
3. 保存隐私协议接受状态。
4. 保存 `providerID`，不得只存 `company`。

### 12.2 Model upsert

输入：

```text
AllModels
```

写入：

```text
AIModelEntity
```

匹配条件：

```text
ownerAccountID == currentAccountID AND id == model.id
```

行为：

1. 所有能力字段必须完整保存。
2. `aiToolScenarios`、`relatedTaskCodes` 使用 JSON 编码后写入 Binary 字段。
3. 本地模型 `localFilename` 必须保存。
4. agent / base model 信息必须保存。

### 12.3 Scenario binding upsert

输入：

```text
AIScenarioModelBinding
```

写入：

```text
AIScenarioModelBindingEntity
```

要求：

1. 同一账号、同一 scenario、同一 identity 下，只允许一个 `isDefault == true`。
2. 保存默认绑定时，需要清理其他默认绑定。
3. 删除模型时，要删除关联 binding。

### 12.4 Search provider upsert

输入：

```text
SearchKeys
```

写入：

```text
AISearchProviderEntity
```

要求：

1. 支持 `authType`、`priority`、`enabledScopesData`、`revision`。
2. 如果 SupportClient 当前 UI 未开放搜索配置，也要保留数据读写能力。

### 12.5 Small task upsert

输入：

```text
SmallTask
```

写入：

```text
AISmallTaskEntity
```

匹配建议：

```text
ownerAccountID == currentAccountID AND code == task.code
```

要求：

1. 用户编辑 small task 后必须持久化。
2. 删除 small task 后必须从 Core Data 删除。
3. tool list 使用 JSON Binary 保存。

### 12.6 Prompt repo upsert

输入：

```text
PromptRepo
```

写入：

```text
PromptRepoEntity
```

要求：

1. 按列表顺序写入 `position`。
2. 支持系统 prompt 和自定义 prompt。
3. 支持本地化 key。

## 13. Runtime 配置重建要求

本工单不是删除 `AIRuntimeConfigStore`。

正确关系：

```text
Core Data / UserDefaults
  → AISettingsSnapshot
  → AIRuntimeConfiguration
  → AIRuntimeConfigStore runtime cache
```

要求：

1. `AIRuntimeConfigStore` 作为运行时缓存，不作为 AISettings 主存储。
2. 每次 repository 保存后，必须刷新 runtime configuration。
3. `selectedModelIDs`、`remoteBundles`、`trial`、`settingsSnapshot` 必须来自最新 snapshot。
4. 本地 key 模型和 trial/pro 模型选择逻辑必须保持现有 AIModelPreferences 页面行为。
5. `AIConfigCenter` 如果迁移到 SupportClient，要按 SparkClient 的 `currentSnapshot`、`reloadLocalSnapshot`、`rebuildRuntimeCache` 思路实现。

## 14. 远程配置与试用流程

必须保持：

1. `refreshProviderRuntimeConfiguration()` 先刷新远程配置，再重新加载本地 snapshot。
2. 试用申请提交后更新 trial pending 状态。
3. 收到试用结果通知后刷新 provider runtime configuration。
4. trial/pro bundle 不覆盖本地 API Key 模式配置。
5. 本地模型、本地 key provider、pro/trial provider 三类来源必须共存。

## 15. 迁移步骤建议

### 阶段 1：数据库 schema 补齐

任务：

1. 编辑 `SupportClient.xcdatamodeld/SupportClient.xcdatamodel/contents`。
2. 新增 AI 相关实体。
3. 保留现有 `Item`，除非确认模板实体已无用途。
4. 确保所有实体 `codeGenerationType="class"`。
5. 确保 `sourceLanguage="Swift"`。
6. 运行 Xcode / xcodebuild 验证模型可编译。

验收：

1. `rg '<entity name="AIProviderEntity"' SupportClient.xcdatamodeld` 能命中。
2. `rg '<entity name="AIModelEntity"' SupportClient.xcdatamodeld` 能命中。
3. `xcodebuild` 通过。

### 阶段 2：仓储协议补齐

任务：

1. 将 `AISettingsRepository` 协议从 `DefaultAISettingsRepository.swift` 中独立出来或保持现状但补齐方法。
2. 对齐 SparkClient 协议方法。
3. 更新 `LoadAISettingsUseCase`、`SaveAISettingsUseCase` 调用。
4. 保持现有 UI 调用兼容。

验收：

1. 所有 AISettings 页面仍可编译。
2. provider/model/small task 操作有 repository 保存入口。

### 阶段 3：Core Data repository 实现

任务：

1. 将 `DefaultAISettingsRepository` 改为 `final class`。
2. 注入 `CoreDataStack`、`SessionSnapshotStore`、`UserDefaults`、`Logger`。
3. 实现 `ensureSeedDataIfNeeded(ownerAccountID:)`。
4. 实现 `loadSnapshotFromStore(ownerAccountID:)`。
5. 实现 `persist(snapshot:ownerAccountID:)`。
6. 实现 provider/model/scenario binding/search/small task/prompt repo 的 fetch/upsert/delete。
7. 实现 JSON Binary 编码解码工具。
8. 实现 UserDefaults preferences payload 读写。

验收：

1. 首次登录后 Core Data 内出现 AI provider/model/binding/seed state 数据。
2. 第二次启动不重复灌 seed。
3. 修改 API Key 后重启仍保留。
4. 修改模型启用状态后重启仍保留。

### 阶段 4：AISettingsStore 接入 repository

任务：

1. `AISettingsStore` 构造参数加入 `LoadAISettingsUseCase`、`SaveAISettingsUseCase`。
2. `load()` 改为从 use case 加载 snapshot。
3. `loadIfNeeded()` 基于是否已加载，而不是 `configuration == .empty`。
4. 每次保存后调用 runtime rebuild。
5. 所有 `*AndPersist` 方法最终调用 repository 保存。
6. 保留 `SupportAIConfigAPI` 的远程刷新/试用申请功能。

验收：

1. AISettings 页面打开时加载 Core Data snapshot。
2. provider/model/small task 修改后立即落库。
3. runtime configuration 与页面展示一致。

### 阶段 5：AppContainer 注入账号级依赖

任务：

1. `AppContainer` 创建 `DefaultAISettingsRepository(coreDataStack:snapshotStore:)`。
2. 创建 use cases。
3. 创建 `AISettingsStore` 时注入 use cases。
4. 登录后进入主页面时确保 `ownerAccountID` 可传入 AISettingsStore 或 repository 能读取当前 session snapshot。
5. 账号切换时重建或刷新 AISettingsStore。

验收：

1. 首次登录立即能看到 seed 模型和 provider。
2. App 冷启动恢复会话后能看到同一账号数据。
3. 切换账号后看到的是另一个账号的数据。

### 阶段 6：回归 AI 设置初始化流程

任务：

1. 清空 App 数据后首次登录。
2. 打开设置 → AI 场景配置。
3. 检查 provider 列表。
4. 检查 models 列表。
5. 检查默认模型配置。
6. 修改 API Key。
7. 修改模型启用状态。
8. 新增自定义 provider。
9. 新增自定义 model。
10. 新建 small task。
11. 重启 App。
12. 验证所有修改保留。

验收：

1. 所有操作都可跨重启保留。
2. 无重复 seed 数据。
3. 无跨账号串数据。
4. AI 设置页没有 runtime store 回退导致的旧数据覆盖。

## 16. 测试要求

### 16.1 编译测试

必须运行：

```bash
xcodebuild \
  -project /Users/hua/Downloads/Reference/SupportClient/SupportClient.xcodeproj \
  -scheme SupportClient \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build
```

要求：

1. `BUILD SUCCEEDED`。
2. 不新增 Core Data model 编译错误。
3. 不新增 AISettings 相关 Swift 编译错误。

### 16.2 单元测试建议

建议新增 repository 测试，至少覆盖：

1. `loadSnapshot` 首次账号自动 seed。
2. 第二次 `loadSnapshot` 不重复 seed。
3. `save(snapshot:)` 后重新加载结果一致。
4. `saveProvider` 单条 upsert。
5. `saveModel` 单条 upsert。
6. `saveScenarioBinding` 默认绑定互斥。
7. `deleteScenarioBinding` 删除成功。
8. `saveSearchKey` / `deleteSearchKeys`。
9. `savePromptRepo` 顺序保存。
10. 账号 A / 账号 B 数据隔离。

### 16.3 手动验收

必须执行：

1. 清空模拟器 App 数据。
2. 登录账号 A。
3. 打开 AI 设置。
4. 确认默认 provider/model 已出现。
5. 写入一个 provider API Key。
6. 关闭 App 并重启。
7. 确认 API Key 仍存在。
8. 新增一个自定义模型。
9. 重启后确认模型仍存在。
10. 登出账号 A。
11. 登录账号 B。
12. 确认账号 B 不显示账号 A 的自定义模型/API Key。
13. 再登录账号 A。
14. 确认账号 A 数据恢复。

## 17. 风险与处理策略

### 17.1 Core Data 模型直接替换风险

风险：

`SupportClient.xcdatamodeld` 当前已有 `Item`，如果直接删除，可能影响模板预览或已有存储。

策略：

1. 首次实现先保留 `Item`。
2. 后续确认无引用再清理。

### 17.2 Seed 重复灌库风险

风险：

如果用 provider/model 是否为空判断 seed，会导致用户清空目录后被系统重新灌入默认数据。

策略：

必须使用 `AISettingsSeedStateEntity` 判断。

### 17.3 RuntimeStore 覆盖 Core Data 风险

风险：

如果 Core Data 加载后又被 `AIRuntimeConfigStore.load()` 的旧快照覆盖，会出现用户修改丢失。

策略：

1. Core Data 是主存储。
2. RuntimeStore 只接收最新 snapshot 重建。
3. `AISettingsStore.load()` 不再以 RuntimeStore 为第一数据源。

### 17.4 账号来源时序风险

风险：

首次登录后 session snapshot 尚未写入，repository 读取不到 accountID。

策略：

1. 登录主流程显式传入 `session.accountID`。
2. repository 保留 `SessionSnapshotStore` 作为 fallback。

### 17.5 JSON Binary 编码兼容风险

风险：

`aiToolScenariosData`、`relatedTaskCodesData`、`toolListData` 编码失败会导致数组丢失。

策略：

1. 使用统一 JSONEncoder/JSONDecoder。
2. 解码失败返回空数组并记录 warning。
3. 不因为单个 Binary 字段失败导致整个 snapshot 加载失败。

## 18. 验收标准

本工单完成必须满足：

1. `SupportClient.xcdatamodeld` 包含 SparkClient AISettings 所需实体。
2. `DefaultAISettingsRepository` 使用 Core Data，不再使用 `AIRuntimeConfigStore` 作为主存储。
3. 首次登录自动 seed provider/model/scenario binding。
4. 每个账号只 seed 一次。
5. API Key 修改可跨重启保留。
6. 模型启用/禁用可跨重启保留。
7. 自定义 provider/model 可跨重启保留。
8. small task 可跨重启保留。
9. 默认模型选择可跨重启保留。
10. 账号 A 与账号 B AI 配置隔离。
11. 试用状态刷新不覆盖本地 provider/model 设置。
12. `AIRuntimeConfigStore` 只作为 runtime cache。
13. `xcodebuild` 通过。
14. AI 设置页面无明显回归。
15. 文档更新 `SUPPORT-ARCH-000001` 中相关状态或补充链接到本工单。

## 19. 完成后建议更新的文档

完成实现后，需要更新：

```text
/Users/hua/Downloads/Reference/SupportClient/需求文档/SUPPORT-ARCH-000001-SparkClient底层核心架构迁移需求工单.md
```

建议新增状态说明：

```text
SUPPORT-AI-CORE-DATA-000001 已完成：
- AI Core Data 实体已迁入 SupportClient.xcdatamodeld
- AISettingsRepository 已切换为 Core Data 主存储
- 首次登录 seed / 账号隔离 / runtime cache 重建已对齐 SparkClient
```

## 20. 实施检查清单

### 数据库

- [ ] `AIProviderEntity` 已加入 SupportClient.xcdatamodeld
- [ ] `AIModelEntity` 已加入 SupportClient.xcdatamodeld
- [ ] `AIScenarioModelBindingEntity` 已加入 SupportClient.xcdatamodeld
- [ ] `AISearchProviderEntity` 已加入 SupportClient.xcdatamodeld
- [ ] `AISmallTaskEntity` 已加入 SupportClient.xcdatamodeld
- [ ] `PromptRepoEntity` 已加入 SupportClient.xcdatamodeld
- [ ] `AISettingsSeedStateEntity` 已加入 SupportClient.xcdatamodeld
- [ ] `AIScenarioBundleCacheEntity` 已按需加入 SupportClient.xcdatamodeld
- [ ] `MemoryRecordEntity` 已按需加入 SupportClient.xcdatamodeld

### 仓储

- [ ] `AISettingsRepository` 协议已对齐 SparkClient
- [ ] `DefaultAISettingsRepository` 已注入 `CoreDataStack`
- [ ] `DefaultAISettingsRepository` 已注入 `SessionSnapshotStore`
- [ ] `ensureSeedDataIfNeeded` 已实现
- [ ] `loadSnapshotFromStore` 已实现
- [ ] `persist(snapshot:)` 已实现
- [ ] provider fetch/upsert/delete 已实现
- [ ] model fetch/upsert/delete 已实现
- [ ] scenario binding fetch/upsert/delete 已实现
- [ ] search provider fetch/upsert/delete 已实现
- [ ] small task fetch/upsert/delete 已实现
- [ ] prompt repo fetch/upsert/delete 已实现
- [ ] preferences payload UserDefaults 读写已实现

### 初始化

- [ ] 首次登录会触发 AI seed
- [ ] 冷启动恢复会话会加载账号级 AI snapshot
- [ ] seed 状态通过 `AISettingsSeedStateEntity` 判断
- [ ] seed 失败不会写入 seed state
- [ ] 第二次启动不会重复灌 seed

### Runtime

- [ ] Core Data snapshot 可以重建 `AIRuntimeConfiguration`
- [ ] 保存 AI 设置后 runtime cache 更新
- [ ] 本地 API Key 模式可用
- [ ] Pro/trial 模式可用
- [ ] 默认模型选择可用

### 验收

- [ ] `xcodebuild` 通过
- [ ] 修改 provider API Key 后重启仍存在
- [ ] 修改模型启用状态后重启仍存在
- [ ] 新增 provider 后重启仍存在
- [ ] 新增 model 后重启仍存在
- [ ] 新增 small task 后重启仍存在
- [ ] 账号隔离验证通过
- [ ] AI 设置页面无崩溃
- [ ] 文档已更新

## 21. 追加范围：AI 设置模块场景配置与子模块完整对齐 SparkClient

本追加范围用于补齐 `SUPPORT-AI-CORE-DATA-000001` 的 UI/交互/子模块部分。前 1-20 章主要约束 Core Data 实体、仓储持久化、seed、runtime cache 重建；本章要求继续对比 SparkClient 的 AI 设置模块，将模型密钥、模型、默认模型、场景配置、小任务、个性化等设置入口和子页面完整对齐。

目标不是只让 SupportClient 能保存 AI 配置，而是让 SupportClient 的 AI 设置模块在结构、页面、交互、状态持久化、初始化流程上都具备和 SparkClient 同等级能力。代码层面优先直接复制 SparkClient 已验证实现，再做 SupportClient 场景枚举、业务文案、依赖注入的最小适配。

### 21.1 本次追加的参考目录

SparkClient 参考目录：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings
```

SupportClient 目标目录：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Features/AISettings
```

要求：

1. SupportClient 的 `Projects/Features/AISettings` 目录层级应尽量与 SparkClient 保持一致。
2. SparkClient 中已经存在且与 AI 设置基础能力相关的文件，SupportClient 不应继续用简化版替代。
3. 除 SupportClient 专属场景枚举、业务文案、App 依赖注入差异外，其余功能代码优先直接复制。
4. 复制后必须保证本地化 key、图片资源、图标资源、Core Data 实体、repository 方法、view model 方法同步补齐。

### 21.2 当前已发现的目录差异

SupportClient 当前缺少或明显简化的 SparkClient 文件如下：

```text
Application/AISettingsMutationService.swift
Application/AISettingsPromptToolingProviding.swift
Application/AITrialNotifications.swift
Domain/AISettingsRepository.swift
Domain/AISettingsSeedCatalog.swift
Domain/AISettingsSnapshot+Presentation.swift
Infrastructure/ClientModelCapabilityProbeService.swift
Infrastructure/ProviderModelCatalogService.swift
Presentation/Models/AddOnlineModelSheet.swift
Presentation/Models/Components/ModelIconPickerSheet.swift
Presentation/Models/Components/PromptInputEditorView.swift
Presentation/Models/EditSparkModelSheet.swift
Presentation/Models/LocalModelDownloadSheet.swift
Presentation/Models/ModelScenarioBindingsEditorView.swift
Presentation/Models/ModelsAdvancedEditorView.swift
Presentation/Models/ModelsSettingsAgentSheet.swift
Presentation/Models/ModelsSettingsMainRow.swift
Presentation/Models/ModelsSettingsTypes.swift
Presentation/Personalization/MemoryArchiveSettingsView.swift
Presentation/Personalization/PromptRepoSettingsView.swift
Presentation/Personalization/TranslationDicSettingsView.swift
Presentation/Preferences/AIScenarioConfigEditorView.swift
Presentation/Preferences/AISearchToolSettingsView.swift
Presentation/Preferences/ScenarioModelPreferencesViewModel.swift
Presentation/Providers/ProviderSettingsEditorView.swift
Presentation/Root/SmallTaskEditorView.swift
```

结论：

1. SupportClient 现在的 AI 设置不是 SparkClient 的完整迁移版。
2. SupportClient 目前存在若干简化页面，例如 `AIModelPreferencesView`、`ModelsSettingsView`、`APIKeysSettingsView`。
3. 简化版页面会阻断 Core Data 持久化后的完整验收，因为很多字段没有入口可编辑。
4. 后续实现必须把这些缺失文件纳入本工单范围。

### 21.3 模型密钥模块对齐要求

SparkClient 参考文件：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Providers/APIKeysSettingsView.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Providers/ProviderSettingsEditorView.swift
```

SupportClient 当前问题：

1. `APIKeysSettingsView` 已有列表、开关、新增入口，但实现和 SparkClient 不完全一致。
2. Provider 编辑页在 SupportClient 内有内联实现或简化实现，未完全使用 SparkClient 的独立 `ProviderSettingsEditorView.swift`。
3. Provider models 管理、隐私政策 sheet、provider 级模型列表、API Key 校验、provider 开关与模型可见性联动需要继续核对。
4. Provider 公司图标、公司名本地化、provider 排序、隐藏本地 provider 逻辑需要与 SparkClient 一致。

必须实现：

1. 直接迁移 SparkClient 的 `ProviderSettingsEditorView.swift`。
2. `APIKeysSettingsView` 优先用 SparkClient 版本覆盖 SupportClient 简化版。
3. 保留 `AITrialSettingsView` 在 provider 列表顶部的显示逻辑。
4. `ProviderSettingsEditorView` 必须支持：
   - API Key 编辑。
   - requestURL 编辑。
   - provider 启用/停用。
   - provider 关联模型展示。
   - provider models 管理入口。
   - privacy policy sheet。
   - 自定义 provider 新增。
   - 自定义 provider 删除。
5. 以下 sheet 必须完整保留：

```swift
.sheet(item: $presentedSheet) { sheet in
    switch sheet {
    case .manageModels:
        ModelManagementView(provider: provider, viewModel: viewModel)
    case .privacyPolicy(let url):
        ProviderPrivacyPolicyWebSheet(url: url)
    }
}
```

6. `ModelManagementView` 与 `ProviderPrivacyPolicyWebSheet` 必须和 SparkClient 行为一致。
7. Provider 开关关闭后，对应 provider 下的服务模型在模型页应按 SparkClient 规则隐藏或不可用。
8. Provider API Key 写入后，必须立即持久化到 Core Data，并触发 runtime cache 重建。

验收：

1. 新增 provider 后，退出 App 再打开仍存在。
2. 编辑 API Key 后，退出 App 再打开仍存在。
3. 关闭 provider 后，模型列表可见性与 SparkClient 一致。
4. provider 管理模型 sheet 可以打开、编辑、保存。
5. privacy policy sheet 可以打开链接。

### 21.4 模型模块对齐要求

SparkClient 参考文件：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Models/ModelsSettingsView.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Models/AddOnlineModelSheet.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Models/EditSparkModelSheet.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Models/LocalModelDownloadSheet.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Models/ModelManagementView.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Models/ModelScenarioBindingsEditorView.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Models/ModelsAdvancedEditorView.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Models/ModelsSettingsAgentSheet.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Models/ModelsSettingsMainRow.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Models/ModelsSettingsTypes.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Models/Components/ModelIconCatalog.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Models/Components/ModelIconPickerSheet.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Models/Components/PromptInputEditorView.swift
```

SupportClient 当前问题：

1. `ModelsSettingsView` 是简化版。
2. 缺少 SparkClient 的 `trialChatModelsSection` 试用模型开关区。
3. 缺少基于 provider API Key 的模型可见性过滤。
4. 缺少添加在线模型 sheet。
5. 缺少本地模型下载 sheet。
6. 缺少智能体创建/编辑 sheet。
7. 缺少高级模型编辑页。
8. 缺少模型行独立组件 `ModelsSettingsMainRow`。
9. 缺少模型场景绑定编辑 `ModelScenarioBindingsEditorView`。
10. 缺少图标选择器和 prompt 输入编辑器。

必须实现：

1. 优先复制 SparkClient 的 `ModelsSettingsView.swift` 覆盖 SupportClient 简化版。
2. 补齐所有 `Presentation/Models` 子文件，除非确认 SupportClient 暂无对应业务依赖且主流程完全不引用。
3. 模型列表必须支持：
   - `all` / `model` / `agent` 分段。
   - 搜索。
   - 排序编辑。
   - 重置排序。
   - 试用模型开关。
   - 在线模型新增。
   - 本地模型新增/下载。
   - 智能体新增/编辑。
   - 高级编辑。
   - 行内启用/停用。
   - 自定义模型删除。
4. 模型启用逻辑必须与 SparkClient 一致：
   - 本地模型可按本地能力判断启用。
   - 服务模型必须有可用 provider/API Key 才可正常启用。
   - provider 未配置密钥时，服务模型不应在主列表中作为可用模型误导用户。
   - trial 模型状态必须受 `trialChatPickerDisabledModelNames` 控制。
5. 模型保存后必须写入 Core Data 的 `AIModelEntity`。
6. 模型排序变更必须持久化 `position`。
7. 模型删除时必须同步清理关联的 scenario binding。
8. 智能体模型必须保留：
   - baseModelName。
   - systemPrompt。
   - iconSymbol。
   - aiScenarios。
   - aiToolScenarios。
   - relatedTaskCodes。
   - toolList。
   - identity。
   - source。
9. 所有数组字段必须使用与 SparkClient 一致的 JSON/Binary 编码策略。

验收：

1. 模型页 UI 与 SparkClient 一致。
2. 新增在线模型后重启仍存在。
3. 新增本地模型后重启仍存在。
4. 新增智能体后重启仍存在。
5. 拖拽排序后重启顺序仍一致。
6. 删除自定义模型后关联场景绑定不残留。
7. provider 没有 API Key 时，服务模型启用逻辑与 SparkClient 一致。

### 21.5 默认模型与场景配置对齐要求

SparkClient 参考文件：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Preferences/AIModelPreferencesView.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Preferences/ScenarioModelPreferencesViewModel.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Preferences/AIScenarioConfigEditorView.swift
```

SupportClient 当前问题：

1. `AIModelPreferencesView` 仍直接依赖 `AISettingsViewModel`，不是 SparkClient 的 `ScenarioModelPreferencesViewModel` 架构。
2. 缺少 `ScenarioModelPreferencesViewModel.swift`。
3. 缺少 `AIScenarioConfigEditorView.swift`。
4. 默认模型页面和底层场景绑定编辑页面职责没有分清。
5. 本地模型与 Pro/trial 模型选择逻辑需要继续对齐。
6. SupportClient 中 `AIScenario` 包含 Support 专属场景，但页面结构仍应沿用 SparkClient。

必须实现：

1. 复制 SparkClient 的 `ScenarioModelPreferencesViewModel.swift`。
2. 复制 SparkClient 的 `AIModelPreferencesView.swift`，并将入口改为：

```swift
AIModelPreferencesView(
    viewModel: viewModel.makeScenarioModelPreferencesViewModel()
)
```

3. `AISettingsViewModel` 必须补齐 `makeScenarioModelPreferencesViewModel()`。
4. 复制 SparkClient 的 `AIScenarioConfigEditorView.swift`。
5. `AIModelPreferencesView` 负责用户常用默认模型选择：
   - 按 `AIScenario.allCases` 分组。
   - 支持搜索。
   - 展示场景说明和图标。
   - 支持本地密钥模型与 Pro/trial 模型来源切换。
   - 支持每个场景选择默认模型。
6. `AIScenarioConfigEditorView` 负责更底层的场景绑定配置：
   - 按场景展示本地 bundle。
   - 支持选择场景默认模型。
   - 展示 endpoint/model/API Key 脱敏。
   - 支持 temperature。
   - 支持 maxTokens。
   - 写入 `AIScenarioModelBindingEntity`。
7. 默认模型来源 `scenarioModelSources` 应继续作为 Preferences Payload 持久化到 UserDefaults。
8. 场景默认模型名、绑定参数、启用状态应进入 Core Data 或 SparkClient 一致的偏好存储位置。
9. `AIScenarioRemoteBundlesCollection` 的构建必须以 Core Data snapshot 为源，不允许只读 `AIRuntimeConfigStore`。

验收：

1. 每个场景都能选择本地密钥模型或 Pro/trial 模型。
2. 默认模型选择后立即生效。
3. 默认模型选择后重启仍存在。
4. temperature/maxTokens 修改后重启仍存在。
5. Support 专属场景出现在默认模型页和场景配置页。
6. SparkClient 已有场景页面能力在 SupportClient 中没有缺项。

### 21.6 小任务模块对齐要求

SparkClient 参考文件：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Root/SmallTasksSettingsView.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Root/SmallTaskEditorView.swift
```

SupportClient 当前问题：

1. 已有 `SmallTasksSettingsView.swift`，但缺少 `SmallTaskEditorView.swift`。
2. 小任务编辑、新增、删除、排序、关联模型、关联场景、试用期/本地能力联动需要继续核对。
3. `AISmallTaskEntity` 持久化后，UI 必须能完整编辑实体字段。

必须实现：

1. 复制 SparkClient 的 `SmallTaskEditorView.swift`。
2. `SmallTasksSettingsView.swift` 优先与 SparkClient 对齐。
3. 小任务必须支持：
   - 新增。
   - 编辑。
   - 删除。
   - 启用/禁用。
   - 排序。
   - 绑定模型或关联任务编码。
   - 保存 prompt/说明/参数。
4. 小任务保存后必须写入 Core Data 的 `AISmallTaskEntity`。
5. 智能体关联小任务时，必须读取同一份 `effectiveSmallTasks`。

验收：

1. 新增小任务后重启仍存在。
2. 编辑小任务后重启仍存在。
3. 删除小任务后，智能体关联关系按 SparkClient 规则处理。
4. 小任务列表和编辑页面 UI 与 SparkClient 一致。

### 21.7 个性化与工具模块对齐要求

SparkClient 参考文件：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Personalization/PromptRepoSettingsView.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Personalization/MemoryArchiveSettingsView.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Personalization/TranslationDicSettingsView.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Preferences/AISearchToolSettingsView.swift
```

SupportClient 当前问题：

1. `Presentation/Personalization` 目录目前基本为空。
2. `PromptRepoEntity`、`MemoryRecordEntity` 已在数据库迁移范围内，但缺少对应设置入口和页面。
3. 搜索工具设置页未迁移。
4. SparkClient 的 `AISettingsView` 中部分个性化入口可能暂时注释，但代码仍是基础能力的一部分。

必须实现：

1. 复制 SparkClient 的个性化页面代码。
2. 复制 `AISearchToolSettingsView.swift`。
3. 是否在 `AISettingsView` 首页展示入口，应跟随 SparkClient 当前策略：
   - SparkClient 当前隐藏的入口，SupportClient 可以同样隐藏。
   - 代码必须迁移，方便后续业务打开。
4. Prompt repo 必须接入 Core Data 的 `PromptRepoEntity`。
5. Memory archive 必须接入 Core Data 的 `MemoryRecordEntity`。
6. Translation dictionary 若 SparkClient 当前是本地偏好结构，SupportClient 保持一致。
7. Search tool preferences 必须接入 repository 的偏好读写逻辑。

验收：

1. 相关页面能编译通过。
2. 打开入口后 UI 与 SparkClient 一致。
3. Prompt repo 修改后可持久化。
4. Search provider/key/preferences 修改后可持久化。

### 21.8 AISettings 根页面对齐要求

SparkClient 参考文件：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Presentation/Root/AISettingsView.swift
```

SupportClient 当前问题：

1. SupportClient 的 `AISettingsView` 使用 `NavigationLink`，SparkClient 使用项目通用 `MainNavigationLink`。
2. SupportClient 额外显示 `providers` section，SparkClient 当前 provider/trial 入口主要在 API Keys 页内。
3. SupportClient 默认模型入口传入的是 `AISettingsViewModel`，SparkClient 传入的是 `ScenarioModelPreferencesViewModel`。
4. SparkClient 中工具、个性化部分有注释策略，SupportClient 需要明确是否完全跟随。

必须实现：

1. `AISettingsView` 根页面结构优先复制 SparkClient。
2. Section 至少包括：
   - 模型密钥。
   - 模型。
   - 默认模型配置。
   - 小任务。
3. `AITrialSettingsView` 不应在根页面重复成为独立 section，除非 SparkClient 后续也改为这样。
4. 默认模型入口必须改用 `makeScenarioModelPreferencesViewModel()`。
5. `MainNavigationLink`、隐藏 TabBar、导航标题、错误弹窗策略与 SparkClient 保持一致。
6. 文案必须使用相同本地化 key。

验收：

1. 根页面入口与 SparkClient 一致。
2. 点击每个入口进入的页面结构与 SparkClient 一致。
3. 不出现 SupportClient 简化版独有入口破坏整体结构。

### 21.9 Application 层对齐要求

SparkClient 参考文件：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Application/AISettingsMutationService.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Application/AISettingsPromptToolingProviding.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Application/AITrialNotifications.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Application/LoadAISettingsUseCase.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Application/SaveAISettingsUseCase.swift
```

必须实现：

1. 复制缺失的 Application 层服务。
2. `AISettingsViewModel` 不应继续堆叠所有 mutation 逻辑。
3. 模型、provider、小任务、prompt repo、scenario binding 等写操作应尽量通过 SparkClient 相同服务封装。
4. 试用期相关通知与刷新逻辑必须保持一致。
5. Prompt tooling provider 必须为智能体编辑、prompt 输入、工具列表提供相同能力。

验收：

1. `AISettingsViewModel` 的公开方法与 SparkClient 对齐。
2. UI 页面调用的方法在 SupportClient 中均存在。
3. mutation 后统一触发 repository 持久化与 runtime cache 重建。

### 21.10 Domain 与 Infrastructure 层对齐要求

SparkClient 参考文件：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Domain/AISettingsRepository.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Domain/AISettingsSeedCatalog.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Domain/AISettingsSnapshot+Presentation.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Infrastructure/ClientModelCapabilityProbeService.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings/Infrastructure/ProviderModelCatalogService.swift
```

必须实现：

1. 复制 `AISettingsRepository.swift` 协议，作为 `DefaultAISettingsRepository` 的正式接口。
2. 复制 `AISettingsSeedCatalog.swift`，禁止散落 seed 逻辑。
3. 复制 `AISettingsSnapshot+Presentation.swift`，避免 presentation helper 在 ViewModel/View 中重复实现。
4. 复制 `ClientModelCapabilityProbeService.swift`。
5. 复制 `ProviderModelCatalogService.swift`。
6. SupportClient 专属场景只允许在 `AIScenario`、seed 数据、文案中适配，不应改坏通用模型设置架构。

验收：

1. seed catalog 统一生成 provider/model/scenario binding。
2. provider model catalog 能为 Provider 管理模型页提供数据。
3. capability probe 能被模型页或本地模型页调用。
4. presentation helper 与 SparkClient 结果一致。

### 21.11 本地化与资源对齐要求

必须补齐与 AI 设置相关的本地化：

1. `ai_settings.*`
2. `settings.ai_scenarios`
3. `settings.ai_scenarios.subtitle`
4. `company_*`
5. provider 编辑页相关 key。
6. 模型页相关 key。
7. 默认模型/场景配置相关 key。
8. 小任务相关 key。
9. prompt repo、memory archive、translation dictionary、search tool 相关 key。

公司名本地化必须至少包含：

```text
company_AI302
company_AIHUBMIX
company_ANTHROPIC
company_CHERRY_IN
company_DEEPSEEK
company_DOUBAO
company_GITEE
company_GOOGLE
company_HUNYUAN
company_IFLOW
company_KIMI
company_LAN
company_LOCAL
company_LONGCAT
company_MIMO
company_MINIMAX
company_MODELSCOPE
company_N1N
company_OPENAI
company_OPENROUTER
company_PERPLEXITY
company_POE
company_QWEN
company_SILICONCLOUD
company_STEP
company_WENXIN
company_XAI
company_YI
company_ZHIPUAI
```

资源要求：

1. provider/company icon 映射必须与 SparkClient 一致。
2. `companyIconName(for:)` 所依赖的图片资源必须存在。
3. 模型图标选择器所依赖的 symbol/icon catalog 必须存在。
4. 缺失资源不得降级成纯系统图标，除非 SparkClient 本身也是这样。

验收：

1. 中文本地化无 key 直出。
2. 英文本地化无 key 直出。
3. Provider 图标与 SparkClient 一致。
4. 模型图标选择器可正常显示。

### 21.12 与 Core Data 工单主线的关系

本章追加内容不是独立 UI 优化，而是 Core Data 持久化主线的必要组成。

原因：

1. Core Data 实体迁入后，必须有页面可以完整读写这些实体。
2. 如果只迁数据库，不迁 `ProviderSettingsEditorView`、`ModelsSettingsView`、`AIScenarioConfigEditorView`、`SmallTaskEditorView`，很多字段无法通过 UI 验收。
3. 如果只迁 UI，不迁 repository，则页面操作无法跨重启保留。
4. 因此本工单验收必须同时覆盖数据层与设置模块。

实现顺序建议：

1. 先复制缺失 Domain/Application/Infrastructure 文件。
2. 再复制缺失 Presentation 子模块。
3. 再调整 `AISettingsViewModel` 公开 API 与 SparkClient 对齐。
4. 再接入 Core Data repository。
5. 最后修本地化、资源、编译错误。

### 21.13 追加验收清单

#### 页面结构

- [ ] `AISettingsView` 根页面结构与 SparkClient 一致
- [ ] `APIKeysSettingsView` 与 SparkClient 一致
- [ ] `ProviderSettingsEditorView` 已迁移
- [ ] `ProviderPrivacyPolicyWebSheet` 可用
- [ ] `ModelManagementView` 可用
- [ ] `ModelsSettingsView` 与 SparkClient 一致
- [ ] `AddOnlineModelSheet` 已迁移
- [ ] `EditSparkModelSheet` 已迁移
- [ ] `LocalModelDownloadSheet` 已迁移
- [ ] `ModelsSettingsAgentSheet` 已迁移
- [ ] `ModelsAdvancedEditorView` 已迁移
- [ ] `ModelScenarioBindingsEditorView` 已迁移
- [ ] `AIModelPreferencesView` 已改为 SparkClient 架构
- [ ] `ScenarioModelPreferencesViewModel` 已迁移
- [ ] `AIScenarioConfigEditorView` 已迁移
- [ ] `SmallTaskEditorView` 已迁移
- [ ] `PromptRepoSettingsView` 已迁移
- [ ] `MemoryArchiveSettingsView` 已迁移
- [ ] `TranslationDicSettingsView` 已迁移
- [ ] `AISearchToolSettingsView` 已迁移

#### 功能行为

- [ ] Provider 新增/编辑/删除/开关与 SparkClient 一致
- [ ] API Key 保存后跨重启保留
- [ ] Provider models 管理 sheet 行为一致
- [ ] privacy policy sheet 行为一致
- [ ] 模型新增/编辑/删除/开关与 SparkClient 一致
- [ ] 模型排序与重置排序一致
- [ ] 试用模型开关一致
- [ ] 本地模型与服务模型可见性规则一致
- [ ] 智能体新增/编辑/保存一致
- [ ] 默认模型来源切换一致
- [ ] 默认模型选择跨重启保留
- [ ] 场景配置 temperature/maxTokens 跨重启保留
- [ ] 小任务新增/编辑/删除/排序跨重启保留
- [ ] Prompt repo 持久化一致
- [ ] Search tool preferences 持久化一致

#### 数据与初始化

- [ ] AI seed catalog 与 SparkClient 一致
- [ ] 首次登录 seed 后页面展示与 SparkClient 一致
- [ ] Core Data snapshot 能完整驱动所有设置页
- [ ] 保存任意设置后 runtime cache 重建
- [ ] 账号隔离后不同账号设置互不污染
- [ ] Remote/pro/trial 配置刷新不覆盖本地 Core Data 设置

#### 本地化与资源

- [ ] AI 设置相关本地化 key 已补齐
- [ ] provider company 本地化 key 已补齐
- [ ] 模型页本地化 key 已补齐
- [ ] 默认模型/场景配置本地化 key 已补齐
- [ ] 小任务本地化 key 已补齐
- [ ] 个性化/搜索工具本地化 key 已补齐
- [ ] company icon 资源已补齐
- [ ] 模型图标选择资源已补齐

#### 编译与回归

- [ ] `xcodebuild` 通过
- [ ] AI 设置根页面可以正常进入
- [ ] 所有 AI 设置子页面可以正常进入
- [ ] 所有 sheet 可以正常弹出和关闭
- [ ] 无明显 UI 空白、崩溃、key 直出
- [ ] 与 SparkClient 对比截图无明显结构差异
