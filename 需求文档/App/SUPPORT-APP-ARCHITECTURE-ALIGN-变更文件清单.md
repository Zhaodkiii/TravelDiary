# SUPPORT-APP-ARCHITECTURE-ALIGN 变更文件清单

在 SupportClient 建立与 Spark 同路径的 `Projects/App/Sources/App/Architecture/`，迁入启动协调文件，落地 DependencyScope / StorageRegistry / AccountSessionRuntime / RouteCoordinator 与最小 Assembly 骨架；Lifecycle / AppContainer 走统一账号运行时清理。不迁医疗 / Chat / Knowledge。

## 验收

- **BUILD SUCCEEDED**：`xcodebuild -scheme SupportClient -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.5' -configuration Debug build`
- 存在 `Projects/App/Sources/App/Architecture/`（与 Spark 相对路径对齐）
- 登出 / 401 / 登录准备：经 `AccountSessionRuntime` → `StorageRegistry`
- `AppContainer.live()` 经 `AppAssembly` / `AuthAssembly` / `AIAssembly` / `NotificationAssembly` 组装

## 目标目录

```text
Projects/App/Sources/App/Architecture/
  DependencyScope.swift
  StorageRegistry.swift
  AccountSessionRuntime.swift
  AppLifecycleCoordinator.swift
  SignedInSessionPreparationRegistry.swift
  RouteCoordinator.swift
  AssemblyProducts.swift
  FeatureAssemblies.swift
```

## 变更列表

| 标记 | 路径 |
| --- | --- |
| [A] | `Projects/App/Sources/App/Architecture/DependencyScope.swift` |
| [A] | `Projects/App/Sources/App/Architecture/StorageRegistry.swift` |
| [A] | `Projects/App/Sources/App/Architecture/AccountSessionRuntime.swift` |
| [A] | `Projects/App/Sources/App/Architecture/RouteCoordinator.swift` |
| [A] | `Projects/App/Sources/App/Architecture/AssemblyProducts.swift` |
| [A] | `Projects/App/Sources/App/Architecture/FeatureAssemblies.swift` |
| [A] | `需求文档/App/SUPPORT-APP-ARCHITECTURE-ALIGN-变更文件清单.md` |
| [M] | `Projects/App/Sources/App/Architecture/AppLifecycleCoordinator.swift`（自 `Sources/App/` 迁入并改走 Runtime） |
| [M] | `Projects/App/Sources/App/Architecture/SignedInSessionPreparationRegistry.swift`（自 `Sources/App/` 迁入） |
| [M] | `Projects/App/Sources/App/AppContainer.swift` |
| [D] | `Projects/App/Sources/App/AppLifecycleCoordinator.swift`（原平铺路径） |
| [D] | `Projects/App/Sources/App/SignedInSessionPreparationRegistry.swift`（原平铺路径） |
| [D] | `AppContainer` 内嵌 `AppRouteCoordinator` / 私有 `AccountScopedCache`（改由 Architecture 提供） |

## 手改说明

- **StorageRegistry**：`support.*` key；条目含 CoreData / AI prefs / Keychain / FileCache / OSS / 内存运行时；无 Chat/Member/Medical。
- **AccountSessionRuntime**：仅 storage + AI 缓存 + VM 清理；实现 `LoginAccountSwitchHandling`。
- **RouteCoordinator**：鉴权失效系统事件；`typealias AppRouteCoordinator = RouteCoordinator`。
- **Assembly**：Infra / Auth / AI / Notification 四域 `makeCore`；无 Medical/Home/Chat/Knowledge。
