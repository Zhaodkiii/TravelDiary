# SUPPORT-AI-SETTINGS-ALIGN 变更文件清单

以 SparkClient `Projects/Core/AI` + AISettings Feature 目录为准，将 Support 的 AI 配置底座从简化版 `Core/AI` 对齐到完整栈；Feature 补独立 `AISettingsSeedCatalog`；保留 Support 专属 `support_*` 场景与医疗种子映射。不迁完整 AIRuntime / Chat / ToolHub。

## 验收

- **BUILD SUCCEEDED**：`xcodebuild -scheme SupportClient -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.5' -configuration Debug build`
- 存在 `Projects/Core/AI/*`（与 Spark 同相对文件集；`AIScenario` 为 Support 语义）
- 无旧薄 `Core/AI/AIConfigCenter` / 单体 `AIRuntimeModels`
- `AISettingsSeedCatalog.swift` 独立；`mapSeedScenario` 仍映射医疗 seed → support_*
- AppContainer：`AIRuntimeStore` + `AIRuntimeConfigStore` + `BackendAIRemoteConfigProvider` → 完整 `AIConfigCenter`

## 变更列表

| 标记 | 路径 |
| --- | --- |
| [A] | `SupportClient/Projects/Core/AI/AIClientFactory.swift` |
| [A] | `SupportClient/Projects/Core/AI/AIConfigCenter.swift` |
| [A] | `SupportClient/Projects/Core/AI/AIConfigModels.swift` |
| [A] | `SupportClient/Projects/Core/AI/AILocalScenarioBundleBuilder.swift` |
| [A] | `SupportClient/Projects/Core/AI/AIRemoteSettings.swift` |
| [A] | `SupportClient/Projects/Core/AI/AIRuntimeConfigAssembler.swift` |
| [A] | `SupportClient/Projects/Core/AI/AIRuntimeConfigStore.swift` |
| [A] | `SupportClient/Projects/Core/AI/AIRuntimeStore.swift` |
| [A] | `SupportClient/Projects/Core/AI/AIScenario.swift` |
| [A] | `SupportClient/Projects/Core/AI/AISettingsRuntimeCapabilities.swift` |
| [A] | `SupportClient/Projects/Core/AI/CompanyIconNameMapper.swift` |
| [A] | `SupportClient/Projects/Core/AI/LocalModelService.swift` |
| [A] | `SupportClient/Projects/Core/AI/ScenarioPolicyResolver.swift` |
| [A] | `SupportClient/Projects/Core/AI/SmallTask.swift` |
| [A] | `SupportClient/Projects/Core/Networking/API/AI/AIConfigAPI.swift` |
| [A] | `SupportClient/Projects/Core/Domain/Entities/ChatThreadImageDeliveryMode.swift` |
| [A] | `SupportClient/Projects/Foundation/Extensions/Codable+Extensions.swift` |
| [A] | `SupportClient/Projects/Features/AISettings/Domain/AISettingsSeedCatalog.swift` |
| [A] | `需求文档/AI设置/SUPPORT-AI-SETTINGS-ALIGN-变更文件清单.md` |
| [D] | `SupportClient/Core/AI/AIConfigCenter.swift` |
| [D] | `SupportClient/Core/AI/AIRuntimeModels.swift` |
| [D] | `SupportClient/Core/AI/AILocalScenarioBundleBuilder.swift` |
| [D] | `SupportClient/Core/AI/LocalModelService.swift` |
| [D] | `SupportClient/Core/AI/SmallTask.swift` |
| [D] | `SupportClient/Core/AI/CompanyIconNameMapper.swift` |
| [D] | `SupportClient/Core/AI/AIProviderAdapterRegistry.swift` |
| [D] | `SupportClient/Core/AI/ChatThreadImageDeliveryMode.swift` |
| [D] | `SupportClient/Core/AIRuntime/AIRuntimeConfigStore.swift` |
| [M] | `SupportClient/App/AppContainer.swift` |
| [M] | `SupportClient/App/AppLifecycleCoordinator.swift` |
| [M] | `SupportClient/Core/Networking/SupportAPIs.swift` |
| [M] | `SupportClient/Projects/Features/AISettings/Domain/AISettingsSeedLoader.swift` |
| [M] | `SupportClient/Projects/Features/AISettings/Domain/AISettingsDomainModels.swift` |

## 手改说明

- **AIScenario**：保留 `supportTicketAnalysis` / `supportReplyDraft` / `supportKnowledgeAnswer`，不迁入 Spark 医疗 case。
- **AIConfigModels**：场景 bundle 集合使用 Support 字段；`merge` 仅消费 `scenarioRemoteBundles`。
- **AIConfigAPI**：`SupportAIConfigAPI` + `BackendAIRemoteConfigProvider`；Pro bootstrap 兼容医疗 key → support 场景映射。
- **SeedLoader**：保留 `mapSeedScenario`；seed row 类型留在 Loader；Catalog 独立对齐 Spark。
- **未迁**：完整 `Projects/Core/AIRuntime`（Chat / ToolHub / GGUF 网关）。
