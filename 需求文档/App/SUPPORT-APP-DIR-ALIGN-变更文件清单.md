# SUPPORT-APP-DIR-ALIGN 变更文件清单

将 SupportClient 已有 App 相关文件**仅做目录迁移**，对齐 SparkClient `Projects/App/{Presentation,Resources,Sources}` 相对路径。不拷入 Spark 业务资源（Prompts / ToolPrompts / zh-Hant / 医疗资源）。

## 目标结构

```text
SupportClient/Projects/App/
  Presentation/NetworkGateView.swift
  Resources/
    AISettings/{AllModels,APIKeys}.json
    Assets.xcassets/
    SupportClient.xcdatamodeld/
    en.lproj/
    zh-Hans.lproj/
  Sources/
    ContentView.swift
    SupportClientApp.swift
    App/
      App*.swift / Device* / SupportAppEnvironment / SignedIn*
      Notification/{NotificationHostView,NotificationFullScreenCover}.swift
```

根目录保留：`Info.plist`、`SupportClient.entitlements`。

## 验收

- **BUILD SUCCEEDED**：`xcodebuild -scheme SupportClient -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.5' -configuration Debug build`
- 旧路径已移除：根级 `App/`、`AISettings/`、`Resources/`、`Assets.xcassets`、`SupportClient.xcdatamodeld`、`ContentView.swift`、`SupportClientApp.swift`
- 未新增 Spark 独有 Prompts / ToolPrompts / zh-Hant

## 变更列表（均为移动）

| 标记 | 原路径 → 新路径 |
| --- | --- |
| [M] | `App/Presentation/NetworkGateView.swift` → `Projects/App/Presentation/NetworkGateView.swift` |
| [M] | `AISettings/*.json` → `Projects/App/Resources/AISettings/` |
| [M] | `Assets.xcassets/` → `Projects/App/Resources/Assets.xcassets/` |
| [M] | `SupportClient.xcdatamodeld/` → `Projects/App/Resources/SupportClient.xcdatamodeld/` |
| [M] | `Resources/en.lproj/` → `Projects/App/Resources/en.lproj/` |
| [M] | `Resources/zh-Hans.lproj/` → `Projects/App/Resources/zh-Hans.lproj/` |
| [M] | `App/*.swift` → `Projects/App/Sources/App/` |
| [M] | `App/Notification/` → `Projects/App/Sources/App/Notification/` |
| [M] | `ContentView.swift` → `Projects/App/Sources/ContentView.swift` |
| [M] | `SupportClientApp.swift` → `Projects/App/Sources/SupportClientApp.swift` |
| [A] | `需求文档/App/SUPPORT-APP-DIR-ALIGN-变更文件清单.md` |
