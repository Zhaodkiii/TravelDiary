# SUPPORT-NOTIFICATION-ALIGN 变更文件清单

以 SparkClient 应用内通知底层为准，将 Models / Client / Store / Queue / Delivery / Inbox / Metrics / Host 对齐到 SupportClient；删除薄 stub；在 AppContainer / ContentView 接线。不迁 APNs / 医疗推送业务。

## 验收

- **BUILD SUCCEEDED**：`xcodebuild -scheme SupportClient -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.5' -configuration Debug build`
- 目录与 Spark 通知底层相对路径一致（Support Host 落在 `App/Notification/`）
- 登录成功/失败走 Queue → Delivery → Toast/Banner
- Host 支持 Toast + Banner（Alert 能力就位）
- 仓库无旧 stub：`App/NotificationHostView.swift` 单体、`NotificationStoreClient`
- 保留 `Core/Notification/PushAdapter.swift`（仅 UN 授权 stub）

## 变更列表

| 标记 | 路径 |
| --- | --- |
| [A] | `SupportClient/Projects/Core/Notification/Domain/NotificationModels.swift` |
| [A] | `SupportClient/Projects/Core/Notification/Application/NotificationClient.swift` |
| [A] | `SupportClient/Projects/Core/Notification/Application/NotificationStore.swift` |
| [A] | `SupportClient/Projects/Core/Notification/Application/PublishNotificationUseCase.swift` |
| [A] | `SupportClient/Projects/Core/Notification/Application/NotificationDeliveryCoordinator.swift` |
| [A] | `SupportClient/Projects/Core/Notification/Infrastructure/NotificationQueue.swift` |
| [A] | `SupportClient/Projects/Core/Notification/Infrastructure/NotificationInboxStore.swift` |
| [A] | `SupportClient/Projects/Core/Notification/Infrastructure/NotificationMetricsStore.swift` |
| [A] | `SupportClient/App/Notification/NotificationHostView.swift` |
| [A] | `SupportClient/App/Notification/NotificationFullScreenCover.swift` |
| [A] | `需求文档/通知/SUPPORT-NOTIFICATION-ALIGN-变更文件清单.md` |
| [D] | `SupportClient/App/NotificationHostView.swift` |
| [D] | `SupportClient/App/NotificationClient.swift` |
| [M] | `SupportClient/App/AppContainer.swift` |
| [M] | `SupportClient/ContentView.swift` |
| [M] | `SupportClient/Resources/zh-Hans.lproj/Localizable.strings` |
| [M] | `SupportClient/Resources/en.lproj/Localizable.strings` |

## 手改说明

- **AppContainer**：装配 `NotificationStore` → `Metrics` / `Inbox` → `Queue` → `Delivery` → `PublishUseCase` → `DefaultNotificationClient`；启动时 `delivery.startIfNeeded()`；注入 `LoginViewModel` 与 `AppContentDependencies.notificationClient`。
- **ContentView**：继续用 `NotificationHostView(store:)` 包裹；深链改为 `notificationClient.info(..., source: "deeplink")`。
- **日志**：`.push` → `.notification`；Inbox 持久化失败改用 `SupportLogger`。
- **本地化**：新增 Host 所需 `common.notice`（未覆盖医疗 `notification.health_resource_changed.*`）。
