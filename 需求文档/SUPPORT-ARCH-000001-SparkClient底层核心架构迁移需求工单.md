# SUPPORT-ARCH-000001：SparkClient 底层核心架构迁移到 SupportClient 需求工单

> 范围说明：本文用于指导将 `SparkClient` 的底层通用架构迁移到 `SupportClient`。本文只描述需求、边界、实施拆分、涉及目录、验收标准和风险，不代表代码已实现。迁移目标是让 `SupportClient` 快速具备新应用可复用的底座能力，同时避免把 SparkClient 的医疗、AI、聊天等业务复杂度一次性带入新项目。

## 0. 工单索引

| 工单号 | 工单名 | 状态 | 范围 |
| --- | --- | --- | --- |
| `SUPPORT-ARCH-000001` | 底层核心架构迁移总工单 | 新需求/待实现 | Foundation、Networking、App 组合根、文件缓存、OSS、CoreData 存储策略 |
| `SUPPORT-FOUNDATION-000001` | Foundation 工具层复用 | 新需求/待实现 | 日志、原子封装、Keychain、系统信息、网络状态、JSON/JWT/请求 ID 工具 |
| `SUPPORT-NETWORK-000001` | 网络底座核心能力迁移 | 新需求/待实现 | Transport、Request/Response、Engine、AuthTokenProvider、Retry、SerialGate、ETag、DeviceCache、APIResponseDecoder |
| `SUPPORT-APP-000001` | App 组合根骨架搭建 | 新需求/待实现 | SupportAppContainer、SupportAppEnvironment、SupportBootstrapper、生命周期和依赖装配边界 |
| `SUPPORT-APP-STARTUP-000001` | App 根视图与启动协调流程复制 | 新需求/待实现 | NotificationHostView、AppCoordinatorView、AppLifecycleCoordinator、AppSessionStore、登录态分流、启动网络门控 |
| `SUPPORT-RESOURCES-000001` | Resources 与本地化迁移 | 新需求/待实现 | Assets、本地化 strings、Prompts、ToolPrompts、L10n |
| `SUPPORT-FILE-000001` | 文件缓存与 OSS 上传能力迁移 | 新需求/待实现 | FileCacheManager、FileStorageModels、FileTransferService、OSSManager、STS 配置、账号隔离 |
| `SUPPORT-SERVICE-000001` | 服务端 accounts/file_manager/ai_config 复用约束 | 新需求/待实现 | 后台管理系统继续使用 SparkService；用户、登录、设备、文件、OSS、AI 配置不新建服务端模块 |
| `SUPPORT-AUTH-000001` | 登录模块完整复制 | 新需求/待实现 | 登录 UI、登录数据模型、AuthRepository、Auth API、Token 保存、会话恢复、登出 |
| `SUPPORT-DEVICE-000001` | 设备登记模块完整复制 | 新需求/待实现 | 设备信息采集、Device API、匿名/已登录登记、APNs token、通知授权状态、设备会话校验 |
| `SUPPORT-AI-BASE-000001` | AI 基础底座完整保留 | 新需求/待实现 | AISettings 初始化种子、AIConfigCenter、AIRuntimeConfigStore、AIScenario、RemoteBundle、本地模型、Pro 模型、运行网关 |
| `SUPPORT-AISETTINGS-000001` | AI 设置 Feature 整体复制 | 新需求/待实现 | AI 设置 UI、Provider/APIKey、模型管理、场景绑定、试用期、AITrial、首登初始化 |
| `SUPPORT-STORAGE-000001` | CoreData 本地存储底座接入 | 新需求/待实现 | SupportClient.xcdatamodeld、CoreDataStack、存储目录、账号切换清理策略 |
| `SUPPORT-QA-000001` | 迁移验收与回归检查 | 新需求/待实现 | 编译、启动、网络请求、Token 刷新、缓存读写、OSS 上传、CoreData 初始化 |

## 1. 背景

### 1.1 当前现状

`SupportClient` 当前已经从模板工程演进到 CoreData 本地存储形态，项目内存在：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/SupportClient.xcdatamodeld
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Persistence.swift
```

`SupportClient` 仍缺少以下新应用底层能力：

1. 统一日志系统。
2. 可复用网络请求引擎。
3. 认证 Token 存储与刷新。
4. 请求串行化、重试、ETag 缓存、设备缓存。
5. App 级组合根和依赖装配边界。
6. 文件缓存与 OSS 直传能力。
7. 账号级存储隔离和退出清理策略。

`SparkClient` 已经具备较完整的底层架构，核心目录为：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Foundation
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Networking
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/FileStorage
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/OSS
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Database
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Sources/App
```

### 1.2 迁移原则

本次迁移只迁底层可复用能力，不迁 SparkClient 的产品业务。

必须迁移：

1. Foundation 工具层。
2. 网络底座的核心功能。
3. App 组合根骨架设计。
4. 文件缓存。
5. OSS 相关上传能力，使用与 SparkClient 相同的机制。
6. CoreData 本地存储底座，适配 SupportClient 已有模型。
7. 登录模块，包含 UI、数据模型、仓储、用例、接口调用和会话状态。
8. 设备登记模块，包含 UI/权限触发点、设备数据模型、接口调用、匿名与登录态登记。
9. AI 基础底座，包含初始化种子、本地模型、Pro 模型、场景配置、运行时配置中心。
10. AISettings Feature，包含设置 UI、模型管理、APIKey 管理、试用期入口与状态。
11. App 根视图包装、启动协调、登录态分流、通知 Host 和本地化 Resources。

不应直接迁移：

1. 医疗业务 Feature。
2. 聊天业务 Feature。
3. 知识库业务 Feature。
4. 营养业务 Feature。
5. SparkClient 专属启动、通知、路由中的医疗/聊天逻辑。

必须迁移但需要改造应用场景的模块：

1. AI 基础底座。
2. AISettings Feature。
3. AI 试用期相关状态和通知。
4. `AIScenario` / `AIScenarioRemoteBundlesCollection` 中 SparkClient 医疗、营养、知识库等场景要改造成 SupportClient 自己的应用场景。

必须复用的服务端模块：

```text
/Users/hua/Downloads/Reference/SparkService/accounts
/Users/hua/Downloads/Reference/SparkService/file_manager
/Users/hua/Downloads/Reference/SparkService/ai_config
```

说明：

1. SupportClient 的用户、登录、Token、设备登记、设备会话、OTP、Apple 登录，全部使用 `SparkService/accounts` 同一套后端。
2. SupportClient 的文件登记、文件列表、业务绑定、下载 URL、OSS STS，全部使用 `SparkService/file_manager` 同一套后端。
3. SupportClient 的 AI bootstrap、Pro 模型配置、试用期状态、试用申请、Provider 连接测试，全部使用 `SparkService/ai_config` 同一套后端。
4. 后台管理系统继续使用 `/Users/hua/Downloads/Reference/SparkService`，不为 SupportClient 新建独立后台。
5. OSS 使用同一套服务端 STS、bucket、endpoint 和权限策略；客户端只改 object key 前缀和 App 侧命名。

### 1.3 最终目标

迁移完成后，`SupportClient` 应具备以下能力：

1. 新应用启动时通过 `SupportAppContainer` 统一装配基础设施。
2. 任意业务模块可以通过统一网络底座声明 API 请求。
3. 登录态、Token、设备 ID、请求 ID、日志、缓存、文件上传有统一实现。
4. 本地 CoreData 使用 `SupportClient.xcdatamodeld`，不依赖 SparkClient 的模型文件。
5. OSS 上传使用 SparkClient 同源能力，但命名、路径、bucket object prefix 要改成 SupportClient 语义。
6. 后续新增 Feature 时，按 `View -> ViewModel -> UseCase -> Repository/API -> Core` 的依赖方向接入。

## 2. 总体架构目标

### 2.1 推荐目录结构

在 `SupportClient/SupportClient` 下建立如下结构：

```text
SupportClient/
  App/
    SupportClientApp.swift
    SupportAppContainer.swift
    SupportAppEnvironment.swift
    SupportBootstrapper.swift
    Architecture/
      DependencyScope.swift
      StorageRegistry.swift
      AssemblyProducts.swift
      FeatureAssemblies.swift
  Projects/
    Foundation/
      Extensions/
      Networking/
      Security/
      Utilities/
    Core/
      Database/
      FileStorage/
      Networking/
      OSS/
      UI/
    Features/
      Auth/
      Settings/
      Home/
```

说明：

1. `Projects/Foundation` 放无业务依赖的通用工具。
2. `Projects/Core` 放跨业务可复用基础设施。
3. `Projects/Features` 放具体产品功能。
4. `App` 放应用组合根、环境配置、启动协调和生命周期。

### 2.1.1 源码落位规则（已确认）

所有需要参与 `SupportClient` App target 编译的迁移代码，必须放入：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient
```

本工单涉及的通用源码目录统一落位为：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Core
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Foundation
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Features/AISettings
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Resources
```

不得把可编译源码放在工程根目录的以下位置：

```text
/Users/hua/Downloads/Reference/SupportClient/App
/Users/hua/Downloads/Reference/SupportClient/Core
/Users/hua/Downloads/Reference/SupportClient/Foundation
```

原因：

1. `SupportClient.xcodeproj` 的 target 源码根目录是 `SupportClient/SupportClient`。
2. Xcode 16 文件系统同步分组会从源码根目录识别新增文件。
3. 工程根目录只保留 `.xcodeproj`、Git 元数据、需求文档和非 target 产物。
4. 后续迁移、复制、脚本化生成新 App 时，必须以 target 源码根目录作为模板根。

如果不希望一次性调整全部目录，也可以先采用较轻量结构：

```text
SupportClient/
  Foundation/
  Core/
  App/
  Features/
```

但无论采用哪种目录，依赖方向必须一致：

```text
App -> Features -> Core -> Foundation
```

禁止：

```text
Foundation -> Core
Core -> Features
Features -> App
```

### 2.2 命名规则

迁移时必须处理 SparkClient 命名残留。

需要改名：

| SparkClient 名称 | SupportClient 推荐名称 |
| --- | --- |
| `SparkLogger` | `SupportLogger` 或 `AppLogger` |
| `SparkKeychain` | `SupportKeychain` 或 `AppKeychain` |
| `SparkSystemInfo` | `SupportSystemInfo` 或 `AppSystemInfo` |
| `SparkNetworkEngine` | `SupportNetworkEngine` 或 `AppNetworkEngine` |
| `SparkNetworkRequest` | `SupportNetworkRequest` 或 `AppNetworkRequest` |
| `SparkNetworkTransport` | `SupportNetworkTransport` 或 `AppNetworkTransport` |
| `SparkBackendConfiguration` | `SupportBackendConfiguration` |
| `Backend` | `SupportBackend` |
| `SparkOSSConfigurationStore` | `SupportOSSConfigurationStore` |
| `SparkClient.FileCache` | `SupportClient.FileCache` |
| `SparkClient.DeviceCache` | `SupportClient.DeviceCache` |
| `SparkClient.Auth` | `SupportClient.Auth` |

可暂时保留但后续建议重命名：

1. `LogLevel`
2. `Logger`
3. `ConsoleLogger`
4. `RetryPolicy`
5. `NetworkStrategy`
6. `AuthTokenProvider`

### 2.3 非目标

本工单不要求一次性实现以下内容：

1. 完整登录页面。
2. 完整账号系统。
3. 医疗资料同步。
4. Chat 同步。
5. AI 模型配置。
6. 知识库向量检索。
7. 推送通知全链路。
8. SparkClient 的所有 UI 组件迁移。

## 3. 工单 `SUPPORT-FOUNDATION-000001`：Foundation 工具层复用

### 3.1 目标

将 SparkClient 中与业务无关的基础工具迁移到 SupportClient，作为所有 Core 和 Feature 的底层依赖。

源目录：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Foundation
```

目标目录：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Foundation
```

### 3.2 迁移文件清单

优先迁移：

```text
Projects/Foundation/Utilities/Atomic.swift
Projects/Foundation/Utilities/AtomicFileWriter.swift
Projects/Foundation/Utilities/JSONPayloadFormatting.swift
Projects/Foundation/Utilities/JWTExpParser.swift
Projects/Foundation/Utilities/LogModule.swift
Projects/Foundation/Utilities/Logger.swift
Projects/Foundation/Utilities/RequestIdGenerator.swift
Projects/Foundation/Utilities/SparkSystemInfo.swift
Projects/Foundation/Security/SparkKeychain.swift
Projects/Foundation/Networking/NetworkPathMonitor.swift
Projects/Foundation/Extensions/Codable+Extensions.swift
```

按需迁移：

```text
Projects/Foundation/Utilities/DeviceModel/AppleDeviceModel.generated.swift
```

### 3.3 改造要求

#### 3.3.1 日志模块

`LogModule` 需要从 SparkClient 业务模块改成 SupportClient 通用模块。

推荐模块：

```swift
enum LogModule: String, Sendable, CaseIterable {
    case network = "NETWORK"
    case auth = "AUTH"
    case cache = "CACHE"
    case oss = "OSS"
    case database = "DATABASE"
    case storage = "STORAGE"
    case app = "APP"
    case general = "GENERAL"
}
```

从 SparkClient 带来的以下模块不要作为默认模块保留：

```text
medical
aiConfig
home
camera
nutrition
push
```

如果后续业务需要，再由具体 Feature 扩展或新增。

#### 3.3.2 Logger subsystem

`Logger.swift` 中默认 subsystem 不能继续使用：

```text
SparkClient
SparkClient.Debug
SparkClient.Staging
```

需要改为：

```text
SupportClient
SupportClient.Debug
SupportClient.Staging
```

#### 3.3.3 Keychain

`SparkKeychain.swift` 当前存在 HealthClient 兼容逻辑：

```text
service = com.dreamhealth.healthclient
account = device_unique_id
```

SupportClient 需要明确是否沿用同一个设备 ID。

本工单推荐：

1. 如果 SupportClient 必须和 SparkClient/HealthClient 共用设备身份，则保留旧 service，但类名改成 `SupportKeychain`，并在注释中明确原因。
2. 如果 SupportClient 是独立新应用，则改为：

```text
service = com.dreamhua.supportclient
account = device_unique_id
```

默认建议采用独立 service，除非服务端明确要求跨 App 识别同一设备。

#### 3.3.4 Codable 扩展

`Codable+Extensions.swift` 中存在面向医疗和聊天的编码策略。

迁移时需要拆分：

必须保留：

1. `JSONDecoder.default`
2. `JSONEncoder.default`
3. 通用 ISO8601 日期编解码

暂不迁移：

1. `medicalAPI`
2. `chatRemote`
3. `ChatMessageBlockCodec`
4. 依赖 `ChatMessageBlock` / `ChatMessageBlockRowSnapshot` 的内容

### 3.4 验收标准

1. SupportClient 可以编译通过。
2. Foundation 层不 import `CoreData`、`SwiftUI`、业务 Feature。
3. Foundation 层不依赖 SparkClient 专属模型。
4. 日志输出 subsystem 为 `SupportClient`。
5. Keychain service 已按目标策略确认并实现。
6. `rg "SparkClient" SupportClient/SupportClient/Projects/Foundation` 不应出现未解释的残留。

## 4. 工单 `SUPPORT-NETWORK-000001`：网络底座核心能力迁移

### 4.1 目标

迁移 SparkClient 网络底座的核心能力，并确保 SupportClient 后续所有接口都基于统一网络引擎实现。

源目录：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Networking
```

目标目录：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Core/Networking
```

### 4.2 必须保留的核心能力

网络底座迁移后必须保留以下能力：

1. `URLSession` 传输抽象，可替换 mock transport。
2. 统一 Request/Response 模型。
3. JSON body 编码。
4. raw body 上传。
5. 请求级超时。
6. 请求 ID 注入。
7. Authorization header 注入。
8. Access token 过期前自动刷新。
9. 401 后强制刷新 token 并重试。
10. Token 刷新并发去重。
11. HTTP 429/5xx 重试。
12. `Retry-After` 支持。
13. 可配置退避间隔。
14. 请求串行门控。
15. 请求优先级。
16. ETag 条件请求。
17. 304 本地 body 合并。
18. 设备缓存。
19. 网络日志脱敏。
20. 后端统一响应 `{ code, msg, data }` 解码。
21. 直接响应体解码。
22. 后端错误映射。
23. 鉴权失效通知机制。

### 4.3 迁移文件清单

必须迁移：

```text
Projects/Core/Networking/SparkNetworkTransport.swift
Projects/Core/Networking/SparkNetworkModels.swift
Projects/Core/Networking/SparkNetworkEngine.swift
Projects/Core/Networking/SparkBackendConfiguration.swift
Projects/Core/Networking/AuthTokenProvider.swift
Projects/Core/Networking/RetryLayer.swift
Projects/Core/Networking/SerialRequestGate.swift
Projects/Core/Networking/ETagStore.swift
Projects/Core/Networking/BackendErrorLocalizer.swift
Projects/Core/Networking/API/Common/APIResponseDecoder.swift
Projects/Core/Networking/Caching/DeviceCache.swift
Projects/Core/Networking/Logging/SparkNetworkingStrings.swift
```

按需迁移：

```text
Projects/Core/Networking/Operations/SparkNetworkOperation.swift
Projects/Core/Networking/Caching/SparkCallbackCache.swift
Projects/Core/Networking/WebSocket/SparkWebSocketClient.swift
Projects/Core/Networking/Logging/NetworkOperationBusinessPurpose.swift
```

必须迁移并改名适配的 API 分组：

```text
Projects/Core/Networking/API/Auth
Projects/Core/Networking/API/Device
Projects/Core/Networking/API/File
Projects/Core/Networking/API/OSS
Projects/Core/Networking/API/AI/AIConfigAPI.swift
```

对应 SupportClient 目标：

```text
SupportAuthAPI
SupportOTPAPI
SupportDeviceAPI
SupportFileAPI
SupportOSSAPI
SupportAIConfigAPI
```

暂不直接迁移：

```text
Projects/Core/Networking/Backend.swift
Projects/Core/Networking/API/AI/ChatRemoteAPI.swift
Projects/Core/Networking/API/Medical
Projects/Core/Networking/API/Version
Projects/Features/Nutrition/Infrastructure/NutritionAPI.swift
```

说明：`Backend.swift` 不直接迁移，因为它聚合了 SparkClient 的医疗、聊天、营养等业务 API。SupportClient 需要新建自己的 `SupportBackend`，但 Auth、Device、File、OSS、AIConfig API 必须完整接入 SparkService 现有接口。

### 4.4 SupportBackend 设计

SupportClient 应新增：

```swift
final class SupportBackend {
    let baseURL: URL
    let configuration: SupportBackendConfiguration
    let auth: SupportAuthAPI
    let otp: SupportOTPAPI
    let device: SupportDeviceAPI
    let files: SupportFileAPI
    let oss: SupportOSSAPI
    let aiConfig: SupportAIConfigAPI
}
```

首期 `SupportBackend` 至少必须包含 `auth`、`otp`、`device`、`files`、`oss`、`aiConfig`，不能只保留空网络壳。

### 4.5 Token 刷新接口适配

SparkClient 当前刷新路径：

```text
/api/v1/auth/token/refresh/
```

SupportClient 需要确认是否复用同一服务端。如果复用，可以保留路径；如果不复用，需要通过 `SupportBackendConfiguration` 或 `SupportAuthConfiguration` 注入。

推荐改造：

```swift
struct AuthEndpointConfiguration: Sendable {
    let refreshPath: String
}
```

不要把刷新路径硬编码在 `AuthTokenProvider` 内部，除非 SupportClient 与 SparkClient 服务端完全一致。

### 4.6 设备信息字段

Token refresh payload 当前包含：

```json
{
  "refresh": "...",
  "refresh_token": "...",
  "device_id": "...",
  "bundle_id": "..."
}
```

SupportClient 必须保留：

1. `refresh`
2. `refresh_token`
3. `device_id`
4. `bundle_id`

原因：

1. 兼容 SimpleJWT 风格字段。
2. 兼容网关或账户服务字段。
3. 支持服务端单设备或设备绑定策略。

### 4.7 网络日志脱敏要求

日志中必须脱敏：

1. `Authorization`
2. `token`
3. `refresh_token`
4. `access_token`
5. `x-api-key`
6. `api-key`

不得在生产环境输出完整 token。

### 4.8 验收标准

1. `SupportNetworkEngine.send` 可以发起普通 GET/POST 请求。
2. `SupportNetworkEngine.sendRaw` 可以返回原始 data 和 HTTPURLResponse。
3. 401 时可以触发 token refresh。
4. 多个并发请求同时遇到 token 过期时，只发起一次 refresh。
5. 429/5xx 按策略重试。
6. ETag 请求能写入缓存，并在 304 时合并本地 body。
7. 日志中 Authorization 已脱敏。
8. 网络底座不依赖医疗、AI、聊天、营养类型。
9. `rg "SparkMedical|SparkAI|ChatRemote|Nutrition|Medical" SupportClient/SupportClient/Projects/Core/Networking` 不应出现底座级依赖。

## 5. 工单 `SUPPORT-APP-000001`：App 组合根骨架搭建

### 5.1 目标

借鉴 SparkClient 的 `AppContainer` 和 Assembly 机制，在 SupportClient 中建立更轻量的组合根。

源参考：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Sources/App/AppContainer.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Sources/App/AppBootstrapper.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Sources/App/AppEnvironment.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Sources/App/Architecture
```

目标：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App
```

必须保持通用启动骨架尽量与 SparkClient 一致。SupportClient 后续可以根据不同业务替换已登录后的主页面，但不能破坏：

1. 根视图通知 Host 包装。
2. 网络状态门控。
3. 会话恢复。
4. 登录页 ViewModel 缓存。
5. 已登录账号准备。
6. 设备登记。
7. 账号 runtime 激活。
8. AppEnvironment 统一环境管理。

### 5.2 设计要求

SupportClient 组合根要解决以下问题：

1. App 启动只创建一次基础设施。
2. View 不直接创建网络、数据库、文件、OSS 对象。
3. Feature 的 ViewModel 由 Container 或 Feature Assembly 创建。
4. 环境配置集中在 `SupportAppEnvironment`。
5. 日志级别由环境统一配置。
6. CoreData、Backend、FileCache、OSS、StorageRegistry 在同一处装配。

### 5.3 推荐核心对象

#### 5.3.1 SupportAppEnvironment

职责：

1. 区分 debug、staging、production。
2. 提供 `apiBaseURL`。
3. 提供 `siteBaseURL`。
4. 提供 `logLevel`。
5. 提供 `subsystem`。
6. 提供 OSS 相关默认配置，或声明由后端 STS 返回。
7. 提供隐私政策 URL。
8. 提供服务条款 URL。
9. 提供后续业务需要的 public web/share web/base web URL。

示例：

```swift
enum SupportAppEnvironment: String, CaseIterable, Sendable {
    case debug
    case staging
    case production

    static let current: SupportAppEnvironment = {
        #if DEBUG
        .debug
        #elseif STAGING
        .staging
        #else
        .production
        #endif
    }()
}
```

迁移要求：

1. 从 SparkClient `AppEnvironment` 复制结构。
2. subsystem 必须改为 `SupportClient` / `SupportClient.Debug` / `SupportClient.Staging`。
3. debug/staging/production 的 baseURL 必须集中配置，禁止业务代码散落 `#if DEBUG`。
4. `apiBaseURL` 首期指向 SparkService。
5. `privacyPolicyURL` / `termsOfServiceURL` 由 `siteBaseURL` 统一生成。
6. SparkClient 的 `shareWebBaseURL` 如果业务暂不需要，可保留字段但改成 SupportClient 语义。
7. SparkClient 的 `ocrConfiguration` 如未迁 OCR，可暂不暴露；如迁 AI/文件 OCR，则按 SupportClient 命名保留。

#### 5.3.2 SupportAppContainer

职责：

1. 持有 `CoreDataStack`。
2. 持有 `SupportBackend`。
3. 持有 `Logger`。
4. 持有 `FileCacheManager`。
5. 持有 `FileTransferService`。
6. 持有 `SupportOSSConfigurationStore`。
7. 持有 `StorageRegistry`。
8. 提供 ViewModel 工厂。

最小字段建议：

```swift
@MainActor
final class SupportAppContainer {
    let coreDataStack: CoreDataStack
    let backend: SupportBackend
    let logger: Logger
    let fileCacheManager: FileCacheManager
    let fileTransferService: FileTransferService
    let ossConfigurationStore: SupportOSSConfigurationStore
    let storageRegistry: StorageRegistry
    let bootstrapper: SupportBootstrapper
}
```

#### 5.3.3 SupportBootstrapper

职责：

1. 执行一次性启动准备。
2. 预热远程配置。
3. 预取 OSS STS。
4. 初始化缓存目录。
5. 根据登录态切换账号上下文。

初期可以只保留：

```swift
@MainActor
final class SupportBootstrapper {
    func bootstrapAppLaunchIfNeeded() async
    func bootstrapIfNeeded(for accountID: Int64) async
    func reset() async
}
```

### 5.4 不能直接照搬的内容

SparkClient 的以下内容暂不直接迁移：

1. `AIAssembly`
2. `MedicalAssembly`
3. `ChatAssembly`
4. `NotificationAssembly` 中的远程推送医疗路由逻辑
5. `MainTabCoordinatorView` 中的医疗、知识库、聊天 Tab
6. `LaunchIntentCoordinator` 中的医疗文档导入逻辑
7. `ExternalMedicalDocumentImportCoordinator`
8. `HomeLaunchIntentConsumer`

### 5.5 验收标准

1. `SupportClientApp` 使用 `SupportAppContainer.live()` 创建依赖。
2. App 首屏不直接 new 网络、文件、OSS、CoreData 基础设施。
3. `SupportAppEnvironment.current` 可切换不同 baseURL 和 log level。
4. Container 初始化顺序清晰，无循环依赖。
5. `SupportAppContainer.preview` 或测试替代方案可用。
6. 组合根不依赖 SparkClient 的 Feature 类型。

## 6. 工单 `SUPPORT-APP-STARTUP-000001`：App 根视图与启动协调流程复制

### 6.1 目标

SupportClient 需要复制 SparkClient 的 App 根视图包装和启动协调流程。该部分属于通用 App 底座，不是业务页面。

源参考：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Sources/ContentView.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Sources/App/AppCoordinatorView.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Sources/App/AppSessionStore.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Sources/App/Architecture/AppLifecycleCoordinator.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Sources/App/Notification/NotificationHostView.swift
```

### 6.2 根视图包装必须一致

SupportClient `ContentView` 必须复制以下结构：

```swift
NotificationHostView(store: dependencies.notificationStore) {
    AppCoordinatorView(dependencies: dependencies.coordinator)
}
```

要求：

1. `NotificationHostView` 作为所有页面外层 Host。
2. `AppCoordinatorView` 只负责根状态切换，不直接写业务页面逻辑。
3. `ContentView` 的依赖使用 `AppContentDependencies` 或 SupportClient 同名等价结构。
4. 系统事件路由、通知 dashboard refresh、deep link 接收可以按 SupportClient 业务裁剪，但入口结构保持一致。

### 6.3 AppCoordinatorView 流程必须一致

SupportClient 需要复制 `AppCoordinatorView` 的状态机：

```text
loading -> signedOut -> signedIn
```

必须保留：

1. `NetworkPathMonitor`。
2. `AppLaunchScreenView`。
3. 网络未评估时显示启动页。
4. 网络不可用时显示 `NetworkGateView` 或 SupportClient 等价网络门控页。
5. `AppLifecycleCoordinator.bootstrapLaunchAfterNetworkEvaluation(...)`。
6. `SignedOutAuthCoordinatorView`。
7. signedIn 后等待 `preparedAccountID == session.accountID`。
8. 账号未准备完成时显示启动页。
9. `versionUpdateCoordinator.checkOnLaunchIfNeeded(force: true)` 或 SupportClient 等价版本检查。

### 6.4 登录页 ViewModel 缓存必须一致

SparkClient 中 `SignedOutAuthCoordinatorView` 使用：

```swift
@StateObject private var viewModel: LoginViewModel
_viewModel = StateObject(wrappedValue: facades.auth.makeLoginViewModel())
```

SupportClient 必须保持这一策略。

原因：

1. 避免 `AppCoordinatorView.body` 重算导致重复创建 LoginViewModel。
2. 避免验证码倒计时、输入内容、登录中状态丢失。
3. 避免登录请求重复触发。
4. 保持 `AppSessionStore` 登录缓存和 UI 生命周期一致。

验收：

1. 断网/联网切换不会重置登录输入。
2. 验证码倒计时不会因 body 重算重置。
3. 登录成功后 `AppSessionStore` 进入 signedIn，根视图自动切换。
4. 登出后 `SignedOutAuthCoordinatorView` 重新创建干净 LoginViewModel。

### 6.5 signedIn 后页面可按业务替换

SparkClient 在 `AppCoordinatorView` 的 signedIn 分支中进入：

```text
OnboardingFlowView
MainTabCoordinatorView
```

SupportClient 后续会根据不同业务生成不同主页面或设置页面，因此此区域允许替换。

要求：

1. signedOut 登录流程必须保持一致。
2. `AppSessionStore`、`AppLifecycleCoordinator`、账号准备流程必须保持一致。
3. signedIn 后业务页面可以替换为 SupportClient 的设置页、主 Tab、工作台或业务首页。
4. 替换点只能在 `preparedAccountID == session.accountID` 之后。
5. 业务页面必须从 `SupportAppContainer` / facades 获取依赖，不能绕过组合根直接 new 底层服务。

推荐占位：

```swift
SupportMainCoordinatorView(
    session: session,
    dependencies: mainDependencies
)
```

如果首期只有设置页：

```swift
SupportSettingsRootView(
    session: session,
    aiSettingsViewModel: mainDependencies.aiSettingsViewModel,
    accountManagementViewModel: mainDependencies.accountManagementViewModel
)
```

### 6.6 AppLifecycleCoordinator 启动流程

SupportClient 需要参考 SparkClient，尽量保持通用启动流程一致：

```text
网络路径评估
  -> 网络可用
    -> sessionStore.restoreIfNeeded()
    -> appBootstrapper.bootstrapAppLaunchIfNeeded()
    -> signedIn: enqueueSignedInPreparation(...)
    -> signedOut: registerDeviceForSignedOutLaunchIfNeeded()
```

已登录账号准备流程：

```text
activateUser(accountID)
onboarding/业务初始化 activate
signedInDeviceRegistration
appBootstrapper.bootstrapIfNeeded(for: session)
AISettings 初始化与 AIConfigCenter prewarm
文件/OSS runtime 账号上下文切换
preparedAccountID = session.accountID
```

必须保留的原则：

1. 账号级准备由 `AppLifecycleCoordinator` 统一调度。
2. 不通过 SwiftUI 页面 `.task` 直接触发账号级准备。
3. 设备登记失败且鉴权失效时，中止账号级引导。
4. 服务器 401 鉴权失效时强制回到 signedOut。
5. signedOut 状态只清理一次，避免重复 reset。
6. 前台恢复时先检查设备登记，再执行业务同步。

### 6.7 AppSessionStore 登录缓存

SupportClient `AppSessionStore` 必须与 SparkClient 行为一致：

1. `State.loading`。
2. `State.signedOut`。
3. `State.signedIn(UserSession)`。
4. 冷启动只执行一次 `restoreIfNeeded()`。
5. 登录成功调用 `setAuthenticated(_:)`。
6. 登出或鉴权失效调用 `setSignedOut()`。
7. 使用 `SessionSnapshotStore` 验证内存 session 与持久化快照一致。

登录缓存要求：

1. Token 存 Keychain/AuthTokenProvider。
2. UserSession 快照存 SessionSnapshotStore。
3. AppSessionStore 只暴露 UI 所需状态，不暴露 token 刷新细节。
4. 会话恢复成功后必须触发账号准备。
5. 会话恢复失败后必须进入 signedOut。

### 6.8 验收标准

1. `ContentView` 使用 `NotificationHostView -> AppCoordinatorView` 结构。
2. App 冷启动显示启动页。
3. 网络不可用时显示网络门控页。
4. 网络恢复后继续启动流程。
5. 未登录进入登录页。
6. 登录页 ViewModel 不因 body 重算重复创建。
7. 登录成功进入 signedIn。
8. signedIn 但账号未准备完成时显示启动页。
9. 账号准备完成后进入 SupportClient 主业务页或设置页。
10. 登出后回到登录页并清理账号 runtime。
11. 服务端鉴权失效后强制回登录态。

## 7. 工单 `SUPPORT-RESOURCES-000001`：Resources 与本地化迁移

### 7.1 目标

迁移 SparkClient 的 Resources 本地化机制和通用资源结构，让 SupportClient 的登录、设置、AISettings、通知、启动页等底层页面可以直接复用本地化能力。

源参考：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Resources
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Sources/App/L10n.swift
```

### 7.2 必须迁移的本地化文件

```text
Projects/App/Resources/en.lproj/Localizable.strings
Projects/App/Resources/en.lproj/Prompts.strings
Projects/App/Resources/en.lproj/ToolPrompts.strings
Projects/App/Resources/zh-Hans.lproj/Localizable.strings
Projects/App/Resources/zh-Hans.lproj/Prompts.strings
Projects/App/Resources/zh-Hans.lproj/ToolPrompts.strings
Projects/App/Resources/zh-Hant.lproj/Prompts.strings
Projects/App/Resources/zh-Hant.lproj/ToolPrompts.strings
```

要求：

1. 登录、AISettings、通知、启动页相关 key 必须保留。
2. SparkClient 医疗、营养、知识库、聊天专属 key 可保留但不作为 SupportClient 首期必需项。
3. 如果删除业务 key，必须确认没有被迁移 UI 引用。
4. `Prompts.strings`、`ToolPrompts.strings` 与 AI 底座一起保留，便于后续 AI 业务快速接入。

### 7.3 L10n 工具

必须迁移：

```text
Projects/App/Sources/App/L10n.swift
```

要求：

1. 保持 `L10n.text(...)`。
2. 保持 `L10n.format(...)`。
3. 保持 zh-Hans、zh-Hant、en fallback 顺序。
4. 不在 UI 层散落 `NSLocalizedString`。
5. 新增文案必须进入对应 `.strings` 文件。

### 7.4 Assets 资源

必须保留或按 SupportClient 替换：

1. `Assets.xcassets/AccentColor.colorset`。
2. `Assets.xcassets/AppIcon.appiconset`。
3. AI provider 图标资源，如果 AISettings 页面继续展示 provider icon。
4. 通用颜色资源。

允许替换：

1. AppIcon。
2. 品牌色。
3. SparkClient 产品专属图片。

### 7.5 验收标准

1. SupportClient target 包含 `.lproj` 本地化文件。
2. `L10n.text` 能读取中文简体、繁体、英文。
3. 登录页无裸 key。
4. AISettings 页面无裸 key。
5. Notification 文案无裸 key。
6. 缺失 key 可 fallback，不崩溃。


## 8. 工单 `SUPPORT-FILE-000001`：文件缓存与 OSS 上传能力迁移

### 8.1 目标

迁移 SparkClient 文件缓存和 OSS 上传能力，SupportClient 使用相同 OSS 机制，支持后续文件上传、图片上传、附件上传等能力。

服务端文件系统必须使用同一套 SparkService：

```text
/Users/hua/Downloads/Reference/SparkService/file_manager
```

本工单不新增 SupportClient 专属文件服务，不新增 SupportClient 专属 OSS STS 服务。

源目录：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/FileStorage
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/OSS
```

目标目录：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Core/FileStorage
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Core/OSS
```

### 8.2 文件缓存迁移范围

必须迁移：

```text
Projects/Core/FileStorage/FileCacheManager.swift
Projects/Core/FileStorage/FileStorageModels.swift
```

需要改造：

1. 缓存根目录从 `SparkClient.FileCache` 改为 `SupportClient.FileCache`。
2. 账号命名空间保留：

```text
guest
account-<accountID>
```

3. 文件名清洗逻辑必须保留。
4. MD5 校验能力必须保留。
5. 统计缓存占用能力必须保留。
6. 清理单文件和全量缓存能力必须保留。

### 8.3 OSS 迁移范围

必须迁移：

```text
Projects/Core/OSS/AliyunOSSRuntimeConfig.swift
Projects/Core/OSS/FileUtilities.swift
Projects/Core/OSS/OSSClient.swift
Projects/Core/OSS/OSSConfiguration.swift
Projects/Core/OSS/OSSManager.swift
Projects/Core/OSS/SparkOSSConfigurationStore.swift
```

需要同步迁移 Objective-C SDK：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Core/Utilities/Objective-C/AliyunOSSSDK
```

阿里云 SDK 必须保持与 SparkClient 相同的引用方式：

1. 使用同一套 Objective-C SDK 源码引用方式。
2. 使用 Bridging Header 暴露给 Swift。
3. `.h` / `.m` 文件加入 SupportClient target。
4. 不改 OSS SDK 内部类名。
5. 不通过新的 Swift Package、CocoaPods 或手动二次封装替换现有接入方式，除非后续单独开迁移工单。
6. SupportClient 的 `OSSManager`、`OSSClientWrapper`、`OSSCredentials`、`OSSRuntimeConfiguring` 与 SparkClient 的调用链保持一致。

同时需要确认 SupportClient 是否已有 Bridging Header。如果没有，需要新增：

```text
SupportClient-Bridging-Header.h
```

并在 Xcode Build Settings 中配置：

```text
Objective-C Bridging Header
```

### 8.4 FileTransferService 迁移要求

`FileTransferService.swift` 可以迁移，但必须改造依赖：

当前依赖：

```text
SparkFileAPI
SparkOSSAPI
SparkOSSConfigurationStore
OSSClientWrapper
OSSManager
```

SupportClient 应改为：

```text
SupportFileAPI
SupportOSSAPI
SupportOSSConfigurationStore
OSSClientWrapper
OSSManager
```

如果 SupportClient 暂时没有文件服务接口，允许先迁移 OSS 基础层，不启用 `FileTransferService`。

但一旦启用文件上传闭环，必须对齐 SparkService `file_manager` 现有接口：

```text
GET    /api/v1/oss/sts/credentials/
POST   /api/v1/files/register/
GET    /api/v1/files/
POST   /api/v1/files/business/update/
GET    /api/v1/files/<file_id>/download-url/
DELETE /api/v1/files/<file_id>/
```

文件登记请求必须包含：

```json
{
  "file_uuid": "...",
  "original_name": "...",
  "file_size": 123,
  "mime_type": "application/octet-stream",
  "file_path": "",
  "object_key": "SupportClient/20260706/...",
  "storage_type": "oss",
  "business_type": "support.ticket.attachment",
  "business_id": "",
  "is_public": false,
  "file_md5": "..."
}
```

字段约束来自：

```text
SparkService/file_manager/serializers.py
SparkService/file_manager/models.py
```

### 8.5 OSS object key 规则

SparkClient 当前 object prefix 存在：

```text
SparkClient/<yyyyMMdd>
```

SupportClient 必须改为：

```text
SupportClient/<yyyyMMdd>
```

如服务端已有统一业务前缀，则以服务端 STS 或文件初始化接口返回值为准。

### 8.6 STS 凭证策略

必须保留：

1. STS 预取。
2. STS 过期自动刷新。
3. 账号切换后清理运行时凭证。
4. 登出后清理运行时凭证。
5. OSSManager 通过 credentialsProvider 懒加载最新凭证。

STS 接口统一使用：

```text
GET /api/v1/oss/sts/credentials/
```

如后续 OCR 也要复用，使用：

```text
GET /api/v1/oss/ocr/sts/credentials/
```

### 8.7 验收标准

1. 未登录时文件缓存写入 `guest` 命名空间。
2. 登录后文件缓存写入 `account-<accountID>` 命名空间。
3. 登出后回到 `guest` 命名空间。
4. OSS STS 获取成功后可以上传测试文件。
5. STS 过期后可以自动刷新。
6. object key 不再出现 `SparkClient/` 前缀。
7. 文件上传完成后会调用 `/api/v1/files/register/` 登记到 SparkService `ManagedFile`。
8. 后台 `file_manager` admin 可以看到 SupportClient 上传文件。
9. `business_type` 使用 `support.*` 前缀，不使用 SparkClient 医疗/聊天业务类型。
10. `rg "SparkClient.FileCache|SparkClient/" SupportClient/SupportClient/Projects/Core/FileStorage SupportClient/SupportClient/Projects/Core/OSS` 不应出现未改造残留。

## 9. 工单 `SUPPORT-SERVICE-000001`：服务端 accounts/file_manager/ai_config 复用约束

### 9.1 目标

SupportClient 不新建独立用户服务、文件服务、OSS 服务、AI 配置服务和后台管理系统。所有相关能力统一复用 SparkService 现有模块。

服务端根目录：

```text
/Users/hua/Downloads/Reference/SparkService
```

必须复用：

```text
/Users/hua/Downloads/Reference/SparkService/accounts
/Users/hua/Downloads/Reference/SparkService/file_manager
/Users/hua/Downloads/Reference/SparkService/ai_config
```

### 9.2 服务端模块边界

#### 7.2.1 accounts 用户模块

`accounts` 继续作为 SupportClient 的唯一用户模块，覆盖：

1. 密码登录。
2. Apple 登录。
3. 当前会话查询。
4. 登出。
5. Email OTP。
6. Phone OTP。
7. Token refresh。
8. 设备登记。
9. 单账号单设备会话。
10. 账号注销。
11. Django Admin 用户管理、设备管理、登录审计。

现有后端入口：

```text
SparkService/accounts/urls.py
SparkService/accounts/auth/views.py
SparkService/accounts/auth/serializers.py
SparkService/accounts/device/views.py
SparkService/accounts/device/serializers.py
SparkService/accounts/services/login_service.py
SparkService/accounts/services/device_service.py
SparkService/accounts/services/device_session_service.py
SparkService/accounts/models.py
SparkService/accounts/admin.py
```

#### 7.2.2 file_manager 文件系统

`file_manager` 继续作为 SupportClient 的唯一文件系统，覆盖：

1. OSS STS 获取。
2. OCR STS 获取。
3. 文件上传后登记。
4. 文件列表。
5. 文件业务绑定。
6. 文件下载 URL。
7. 文件软删除。
8. 后台文件管理。

现有后端入口：

```text
SparkService/file_manager/urls.py
SparkService/file_manager/oss_urls.py
SparkService/file_manager/views.py
SparkService/file_manager/serializers.py
SparkService/file_manager/models.py
SparkService/file_manager/business_relations.py
SparkService/file_manager/business_access.py
SparkService/file_manager/oss_sts_views.py
SparkService/file_manager/sts_utils.py
SparkService/file_manager/admin.py
```

#### 7.2.3 ai_config AI 配置模块

`ai_config` 继续作为 SupportClient 的 AI 配置服务，覆盖：

1. AI bootstrap 配置。
2. Pro 场景模型配置。
3. 试用期状态。
4. 试用期申请。
5. Provider 连接测试。
6. 后台 AI Provider、模型目录、场景绑定、试用策略管理。

现有后端入口：

```text
SparkService/ai_config/urls.py
SparkService/ai_config/views.py
SparkService/ai_config/models.py
SparkService/ai_config/services.py
SparkService/ai_config/defaults.py
SparkService/ai_config/admin.py
```

### 9.3 服务端接口路径

SupportClient 客户端必须对齐以下现有接口路径。

Auth：

| 能力 | 方法 | 路径 | 后端实现 |
| --- | --- | --- | --- |
| 密码登录 | `POST` | `/api/v1/auth/password/login/` | `accounts.auth.views.PasswordLoginView` |
| Apple 登录 | `POST` | `/api/v1/auth/apple/login/` | `accounts.auth.views.AppleLoginView` |
| 当前会话 | `GET` | `/api/v1/auth/session/` | `accounts.auth.views.CurrentSessionView` |
| 登出 | `POST` | `/api/v1/auth/logout/` | `accounts.auth.views.LogoutView` |
| Token 刷新 | `POST` | `/api/v1/auth/token/refresh/` | `accounts.auth.views.TokenRefreshView` |
| Email OTP 请求 | `POST` | `/api/v1/otp/email/request/` | `accounts.otp.views.EmailOTPRequestView` |
| Email OTP 验证 | `POST` | `/api/v1/otp/email/verify/` | `accounts.otp.views.EmailOTPVerifyView` |
| Phone OTP 请求 | `POST` | `/api/v1/otp/phone/request/` | `accounts.otp.views.PhoneOTPRequestView` |
| Phone OTP 验证 | `POST` | `/api/v1/otp/phone/verify/` | `accounts.otp.views.PhoneOTPVerifyView` |
| 设备登记 | `POST` | `/api/v1/device/register/` | `accounts.device.views.DeviceRegisterView` |

File/OSS：

| 能力 | 方法 | 路径 | 后端实现 |
| --- | --- | --- | --- |
| OSS STS | `GET` | `/api/v1/oss/sts/credentials/` | `file_manager.oss_sts_views.STSCredentialsAPIView` |
| OCR STS | `GET` | `/api/v1/oss/ocr/sts/credentials/` | `file_manager.oss_sts_views.OCRSTSCredentialsAPIView` |
| 文件列表 | `GET` | `/api/v1/files/` | `file_manager.views.ManagedFileListView` |
| 文件登记 | `POST` | `/api/v1/files/register/` | `file_manager.views.FileRegistrationView` |
| 文件业务绑定 | `POST` | `/api/v1/files/business/update/` | `file_manager.views.ManagedFileBusinessUpdateView` |
| 下载 URL | `GET` | `/api/v1/files/<file_id>/download-url/` | `file_manager.views.ManagedFileDownloadURLView` |
| 删除文件 | `DELETE` | `/api/v1/files/<file_id>/` | `file_manager.views.ManagedFileDeleteView` |

AI Config：

| 能力 | 方法 | 路径 | 后端实现 |
| --- | --- | --- | --- |
| AI bootstrap | `GET` | `/api/v1/ai/config/bootstrap/` | `ai_config.views.AIBootstrapConfigView` |
| 试用期状态 | `GET` | `/api/v1/ai/trial/status/` | `ai_config.views.TrialStatusView` |
| 试用期申请 | `POST` | `/api/v1/ai/trial/apply/` | `ai_config.views.TrialApplyView` |
| Provider 连接测试 | `POST` | `/api/v1/ai/providers/test-connection/` | `ai_config.views.AIProviderConnectionTestView` |

### 9.4 后台管理系统约束

后台管理系统继续使用 SparkService。

要求：

1. SupportClient 不创建新的 Django Admin。
2. SupportClient 用户必须进入 `accounts` 的同一套用户表和设备表。
3. SupportClient 文件必须进入 `file_manager` 的同一套文件表和业务关系表。
4. SupportClient AI 配置必须进入 `ai_config` 的同一套 Provider、模型目录、场景绑定、试用期管理。
5. 后台可按 `bundle_id`、`bundle_identifier`、`platform`、`business_type`、AI 场景 key 区分来源。
6. 如需 SupportClient 专属筛选，只在 SparkService admin 中增加筛选项，不复制 admin 模块。

### 9.5 数据隔离与复用策略

SupportClient 与 SparkClient 共用服务端模块，但客户端侧要保证来源可区分。

必须上传：

1. `bundle_id`
2. `bundle_identifier`
3. `device_id`
4. `platform`
5. `app_version`
6. `build_version`
7. `business_type`

推荐 SupportClient 的业务文件类型命名：

```text
support.<domain>.<resource>
```

示例：

```text
support.feedback.attachment
support.ticket.attachment
support.profile.avatar
```

禁止使用 SparkClient 医疗业务类型，例如：

```text
medical_document
health_exam_report
nutrition_record
chat_attachment
```

### 9.6 验收标准

1. 服务端不新增 SupportClient 专属 `accounts` app。
2. 服务端不新增 SupportClient 专属 `file_manager` app。
3. SupportClient 登录接口调用 SparkService 现有路径。
4. SupportClient 设备登记调用 SparkService 现有路径。
5. SupportClient 文件上传登记调用 SparkService 现有路径。
6. SupportClient OSS STS 调用 SparkService 现有路径。
7. SupportClient AI bootstrap、试用期、Provider 测试调用 SparkService 现有路径。
8. 后台能在同一套 admin 中看到 SupportClient 用户、设备、文件、AI 配置/试用期记录。
9. 后台能通过 bundle、business_type 或 AI 场景 key 区分 SupportClient 数据来源。

## 10. 工单 `SUPPORT-AUTH-000001`：登录模块完整复制

### 10.1 目标

将 SparkClient 登录模块完整复制到 SupportClient，包括 UI、数据模型、调用接口、会话状态、Token 保存与恢复。服务端使用 SparkService `accounts` 同一套模块。

源客户端参考：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/Auth
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Sources/App/AppSessionStore.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Networking/API/Auth
```

服务端复用：

```text
/Users/hua/Downloads/Reference/SparkService/accounts
```

### 10.2 客户端迁移范围

必须迁移并适配：

```text
Projects/Features/Auth/Domain/AuthRepository.swift
Projects/Features/Auth/Infrastructure/DefaultAuthRepository.swift
Projects/Features/Auth/Infrastructure/SessionSnapshotStore.swift
Projects/Features/Auth/Application/RestoreSessionUseCase.swift
Projects/Features/Auth/Application/SignInWithAppleUseCase.swift
Projects/Features/Auth/Application/RequestPhoneOTPUseCase.swift
Projects/Features/Auth/Application/SignInWithPhoneOTPUseCase.swift
Projects/Features/Auth/Application/SignOutUseCase.swift
Projects/Features/Auth/Presentation/LoginView.swift
Projects/Features/Auth/Presentation/LoginViewModel.swift
Projects/Features/Auth/Presentation/LoginConductor.swift
Projects/Features/Auth/Presentation/VerificationCodeField.swift
Projects/Features/Auth/Presentation/AuthUserFacingErrorMapper.swift
Projects/Features/Auth/Presentation/LoginLegalAgreementNote.swift
Projects/Features/Auth/Presentation/OutlinedButtonStyle.swift
```

必须新增或适配：

```text
SupportClient/SupportClient/Projects/Core/Networking/API/Auth/SupportAuthAPI.swift
SupportClient/SupportClient/Projects/Core/Networking/API/Auth/SupportOTPAPI.swift
SupportClient/SupportClient/App/AppSessionStore.swift
```

### 10.3 登录 UI 要求

SupportClient 登录 UI 需要具备：

1. Apple 登录按钮。
2. 手机号验证码登录。
3. 验证码发送按钮。
4. 验证码倒计时。
5. 登录中 loading 状态。
6. 错误提示。
7. 登录成功后进入主应用。
8. 隐私政策和服务条款入口。
9. 未勾选协议时禁止登录或提示。
10. 适配 iOS 16 回部署风险，避免在 `ObservableObject` / SwiftUI `View` 上存储 `async closure`。

如 SupportClient 后续需要密码登录，可在 UI 上增加账号密码入口；首期必须保证 Apple 登录和手机 OTP 与 SparkClient 对齐。

### 10.4 客户端数据模型

必须具备：

```swift
struct UserSession: Codable, Equatable, Sendable {
    let accountID: Int64
    let userID: Int64
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let isPro: Bool
}
```

字段可按 SparkService 返回扩展，但必须保留：

1. 用户 ID。
2. access token。
3. refresh token。
4. token type。
5. 账号状态字段。
6. Pro/会员字段，如服务端返回。

Token 存储要求：

1. access/refresh 写入 `AuthTokenProvider`。
2. session 快照写入 `SessionSnapshotStore`。
3. 登出时清理 token。
4. 账号切换时清理账号级 runtime。

### 10.5 接口请求体

Apple 登录请求体必须对齐：

```json
{
  "identity_token": "...",
  "authorization_code": "...",
  "nonce": "...",
  "user": "...",
  "email": "...",
  "full_name": "...",
  "bundle_id": "...",
  "device_id": "..."
}
```

Phone OTP 请求体必须对齐：

```json
{
  "phone_number": "...",
  "provider_uid": "...",
  "bundle_id": "...",
  "device_id": "..."
}
```

Phone OTP 验证请求体必须对齐：

```json
{
  "otp_id": "...",
  "phone_number": "...",
  "code": "...",
  "bundle_id": "...",
  "device_id": "..."
}
```

Token refresh 请求体必须对齐：

```json
{
  "refresh": "...",
  "refresh_token": "...",
  "bundle_id": "...",
  "device_id": "..."
}
```

### 10.6 会话恢复

App 冷启动时必须执行：

1. 从 Keychain/AuthTokenProvider 恢复 token。
2. 从 `SessionSnapshotStore` 恢复本地 session。
3. 网络可用时请求 `/api/v1/auth/session/` 校验当前会话。
4. 会话有效则进入 signedIn。
5. 会话无效则清理 token 并进入 signedOut。

### 10.7 登出

登出必须执行：

1. 调用 `/api/v1/auth/logout/`。
2. 清理 access/refresh token。
3. 清理 session snapshot。
4. 清理账号级 ViewModel/缓存。
5. 调用 `StorageRegistry.prepareForSignOut()`。
6. 文件缓存切回 guest。
7. OSS runtime credentials 清理。

### 10.8 验收标准

1. Apple 登录成功后拿到 token 并进入 signedIn。
2. 手机号验证码登录成功后拿到 token 并进入 signedIn。
3. Token refresh 可用。
4. 冷启动可恢复会话。
5. token 失效后进入 signedOut。
6. 登出后 token 和 session 快照被清空。
7. 登录请求包含 `bundle_id` 和 `device_id`。
8. 后台 `accounts` 能看到用户、登录审计、设备会话记录。

## 11. 工单 `SUPPORT-DEVICE-000001`：设备登记模块完整复制

### 11.1 目标

将 SparkClient 设备登记模块完整复制到 SupportClient，包括设备数据模型、系统信息采集、接口调用、匿名登记、登录态登记、通知状态更新和 APNs token 上报。服务端使用 SparkService `accounts.device` 同一套模块。

源客户端参考：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Device
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Networking/API/Device
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Sources/App/Architecture/AppLifecycleCoordinator.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Sources/App/SparkApplicationDelegate.swift
```

服务端复用：

```text
/Users/hua/Downloads/Reference/SparkService/accounts/device
/Users/hua/Downloads/Reference/SparkService/accounts/services/device_service.py
/Users/hua/Downloads/Reference/SparkService/accounts/services/device_session_service.py
```

### 11.2 客户端迁移范围

必须迁移或重建：

1. `DeviceRegistrationRequest` 数据模型。
2. `DeviceRegistrationCoordinator`。
3. `SupportDeviceAPI`。
4. `SparkSystemInfo` 对应的 Support 版本。
5. APNs token 暂存和上报桥接。
6. 通知授权状态读取。
7. 冷启动匿名设备登记。
8. 登录后已认证设备登记。
9. 前台恢复时设备状态补登记。

### 11.3 设备登记请求体

必须对齐 `accounts/device/serializers.py`：

```json
{
  "device_id": "...",
  "user_id": 123,
  "push_token": "...",
  "notifications_enabled": true,
  "app_version": "...",
  "build_version": "...",
  "bundle_identifier": "...",
  "bundle_id": "...",
  "platform": "ios",
  "system_version": "...",
  "device_model": "...",
  "device_model_name": "...",
  "device_name": "...",
  "screen_size": "...",
  "screen_scale": 3,
  "time_zone": "...",
  "language_code": "...",
  "region_code": "...",
  "country_code": "...",
  "is_simulator": false
}
```

必填：

1. `device_id`

强烈建议始终上报：

1. `bundle_id`
2. `bundle_identifier`
3. `platform`
4. `app_version`
5. `build_version`
6. `system_version`
7. `device_model`
8. `device_model_name`
9. `time_zone`
10. `language_code`
11. `region_code`
12. `country_code`

### 11.4 调用时机

必须覆盖以下时机：

1. App 冷启动，未登录时匿名登记。
2. App 冷启动，已登录恢复后认证登记。
3. 登录成功后立即认证登记。
4. APNs token 获取或变化后登记。
5. 通知授权状态变化后登记。
6. App 前台恢复时按去重策略补登记。
7. 登出后允许匿名登记或 revoked 用户行更新。

### 11.5 鉴权规则

服务端 `DeviceRegisterView` 的规则必须在客户端侧遵守：

1. 无 `Authorization`：走匿名登记，可携带 `user_id` 辅助定位上次登录用户。
2. 有 `Authorization`：必须是有效 JWT + 有效设备会话。
3. 有 `Authorization` 但 token 无效时，服务端返回 401，客户端不得降级成匿名登记。
4. 已登录登记必须携带当前 `bundle_id` 和 `device_id`，用于服务端校验设备会话。

### 11.6 单设备登录策略

SupportClient 必须兼容 SparkService 当前单设备会话策略：

1. 同一用户同一时间最多一个 active device session。
2. 新设备登录会使旧 session 失效。
3. refresh token 内包含设备会话 claims。
4. 设备不匹配时 refresh 失败。
5. 旧设备收到 401 后必须清理本地 token 并退出登录态。

### 11.7 UI 与用户提示

设备登记本身不需要独立页面，但 UI 层必须覆盖相关提示：

1. 登录态过期提示。
2. 账号已在其他设备登录提示。
3. 通知权限关闭时的温和提示。
4. APNs token 获取失败不阻塞登录。
5. 设备登记失败不阻塞基础启动，但必须记录日志。

### 11.8 验收标准

1. 未登录冷启动会调用 `/api/v1/device/register/`。
2. 登录成功后会携带 Authorization 调用 `/api/v1/device/register/`。
3. APNs token 更新后会重新登记。
4. 通知授权状态变化后会重新登记。
5. 后台 `TrustedDevice` 能看到 SupportClient 的设备记录。
6. 后台 `AccountDeviceSession` 能看到登录设备会话。
7. 旧设备 token 失效时，客户端能退出登录态。
8. 设备登记请求包含完整系统信息。

## 12. 工单 `SUPPORT-AI-BASE-000001`：AI 基础底座完整保留

### 12.1 目标

SupportClient 需要完整保留 SparkClient 的 AI 基础底座，方便新 App 快速接入新的 AI 业务。AI 底座不是可选增强项，而是新应用通用基础能力之一。

必须覆盖：

1. AISettings 初始化种子。
2. 首次登录后的 AI 配置初始化。
3. 本地模型管理。
4. Pro 模型加载。
5. 远程模型配置加载。
6. 场景模型绑定。
7. `AIScenarioRemoteBundle`。
8. `AIScenario`。
9. `AIScenarioRemoteBundlesCollection`。
10. `AIConfigCenter`。
11. `AIRuntimeConfigStore`。
12. `AIRuntimeStore`。
13. `AIRuntimeService`。
14. OpenAI 兼容云端网关。
15. 本地 GGUF 网关。

### 12.2 源目录

必须迁移：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/AISettings/APIKeys.json
/Users/hua/Downloads/Reference/SparkClient/SparkClient/AISettings/AllModels.json
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/AI
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/AIRuntime
```

目标目录建议：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/AISettings/APIKeys.json
/Users/hua/Downloads/Reference/SupportClient/SupportClient/AISettings/AllModels.json
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Core/AI
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Core/AIRuntime
```

### 12.3 必须迁移的 Core/AI 文件

```text
Projects/Core/AI/AIClientFactory.swift
Projects/Core/AI/AIConfigCenter.swift
Projects/Core/AI/AIConfigModels.swift
Projects/Core/AI/AILocalScenarioBundleBuilder.swift
Projects/Core/AI/AIRemoteSettings.swift
Projects/Core/AI/AIRuntimeConfigAssembler.swift
Projects/Core/AI/AIRuntimeConfigStore.swift
Projects/Core/AI/AIRuntimeStore.swift
Projects/Core/AI/AIScenario.swift
Projects/Core/AI/AISettingsRuntimeCapabilities.swift
Projects/Core/AI/CompanyIconNameMapper.swift
Projects/Core/AI/LocalModelService.swift
Projects/Core/AI/ScenarioPolicyResolver.swift
Projects/Core/AI/SmallTask.swift
```

### 12.4 必须迁移的 Core/AIRuntime 文件

至少迁移：

```text
Projects/Core/AIRuntime/AIImageCompressor.swift
Projects/Core/AIRuntime/AIPromptKeywords.swift
Projects/Core/AIRuntime/AIPromptL10n.swift
Projects/Core/AIRuntime/AIRuntimeCancellation.swift
Projects/Core/AIRuntime/AIRuntimeGateway.swift
Projects/Core/AIRuntime/AIRuntimeModels.swift
Projects/Core/AIRuntime/AIRuntimeOutputLog.swift
Projects/Core/AIRuntime/AIRuntimeRequestLogRedactor.swift
Projects/Core/AIRuntime/AIRuntimeService.swift
Projects/Core/AIRuntime/InteractionResult.swift
Projects/Core/AIRuntime/LocalGGUFTextGateway.swift
Projects/Core/AIRuntime/OpenAICompatibleTextGateway.swift
Projects/Core/AIRuntime/OpenAIReasoningPayload.swift
Projects/Core/AIRuntime/PromptLocalizer.swift
Projects/Core/AIRuntime/Search
```

可迁移但需要拆业务依赖：

```text
Projects/Core/AIRuntime/ChatOrchestrator.swift
Projects/Core/AIRuntime/ChatOrchestratorInferenceOptions.swift
Projects/Core/AIRuntime/ChatSystemPromptResolver.swift
Projects/Core/AIRuntime/ConsentPayloadBuilder.swift
Projects/Core/AIRuntime/ToolHub
```

处理原则：

1. AI 运行底座要保留。
2. 医疗、营养、知识库、聊天专属工具不要直接作为 SupportClient 默认工具启用。
3. `ToolHub` 可以保留框架，但具体 executor 要按 SupportClient 业务重新注册。

### 12.5 AIScenario 改造要求

`AIScenario` 是应用可变点。SparkClient 内存在医疗、营养、知识库、报告解读等场景，这些不应作为 SupportClient 默认场景照搬。

SupportClient 必须建立自己的场景集合，例如：

```swift
enum AIScenario: String, CaseIterable, Codable, Sendable {
    case chat
    case embedding
    case voice
    case optimizationText
    case optimizationVisual
    case contextFolding
    case router
    case modelConfig

    // SupportClient app-specific scenarios.
    case supportTicketAnalysis
    case supportReplyDraft
    case supportKnowledgeAnswer
}
```

要求：

1. 保留通用场景。
2. 删除或禁用 SparkClient 医疗/营养专属场景。
3. 为 SupportClient 自己的 AI 业务补充场景。
4. 每新增一个场景，必须在 `AIScenarioRemoteBundlesCollection` 中有明确字段或映射策略。
5. `AIScenarioRemoteBundle` 保持结构兼容，方便继续接服务端 Pro 配置。

### 12.6 AIScenarioRemoteBundlesCollection 要求

`AIScenarioRemoteBundlesCollection` 需要成为 SupportClient 的场景配置集合。

要求：

1. 保留 `chat`、`embedding`、`voice`、`optimizationText`、`optimizationVisual`、`contextFolding`、`router`、`modelConfig` 等通用字段。
2. 移除或不启用 SparkClient 医疗/营养/报告字段。
3. 增加 SupportClient 特有场景字段。
4. 本地默认配置和远程 Pro 配置都必须能组装成同一集合。
5. `ScenarioPolicyResolver` 继续负责按场景决定本地/远程/Pro 模型选择策略。

### 12.7 初始化存储和首次登录

首次登录后必须执行：

1. 从 bundle 读取 `AISettings/APIKeys.json`。
2. 从 bundle 读取 `AISettings/AllModels.json`。
3. 通过 `AISettingsSeedLoader` 生成初始 provider/model 数据。
4. 写入 `DefaultAISettingsRepository`。
5. 调用 `AIConfigCenter.prewarm(ownerAccountID:)`。
6. 如果用户具备 Pro 或试用资格，调用远程配置刷新。
7. 构建 `AIRuntimeConfigStore` 快照。
8. 对所有 SupportClient 启用的 `AIScenario` 做 resolve 校验。

要求：

1. 初始化按账号隔离。
2. 已初始化账号不重复覆盖用户设置。
3. 本地配置缺失时允许重新灌入默认数据。
4. 远程 Pro 配置刷新失败时降级使用本地配置。
5. 初始化失败必须写日志，不得静默吞掉。

### 12.8 本地模型与 Pro 模型

本地模型要求：

1. 保留 `LocalModelService`。
2. 保留本地 GGUF 加载能力。
3. 保留 `LocalGGUFTextGateway`。
4. 本地模型可作为 `AIScenarioRemoteBundle` 的候选模型。

Pro 模型要求：

1. 保留远程配置模型加载能力。
2. 保留 `AIRemoteSettingsPatch` 合并逻辑。
3. 保留 Pro 模型与本地模型的策略选择。
4. 支持服务端为不同 App 下发不同场景配置。

### 12.9 AI 服务端接口

SupportClient 需要接入 SparkService 现有 AI 配置接口，或在 SparkService 上按同一协议扩展 app-specific 场景。

客户端必须迁移并适配：

```text
Projects/Core/Networking/API/AI/AIConfigAPI.swift
```

SupportClient 目标：

```text
SupportAIConfigAPI
BackendAIRemoteConfigProvider
```

要求：

1. 复用同一套 wrapped response 解码。
2. 请求中必须带客户端版本、平台、bundle/app 标识。
3. 服务端返回的场景字段要能映射到 SupportClient 的 `AIScenarioRemoteBundlesCollection`。
4. 试用期状态和 Pro 配置要能进入 `AIConfigCenter`。

### 12.10 验收标准

1. `AISettings/APIKeys.json` 和 `AllModels.json` 已加入 SupportClient target。
2. 首次登录后能初始化本地 AI 设置。
3. `AIConfigCenter.prewarm(ownerAccountID:)` 可执行。
4. `AIRuntimeConfigStore` 有有效快照。
5. 每个 SupportClient 启用的 `AIScenario` 都能 resolve。
6. 本地模型服务可初始化。
7. Pro/试用远程配置可刷新。
8. 远程配置失败时能降级本地模型。
9. SparkClient 医疗/营养专属场景没有作为 SupportClient 默认必需项。

## 13. 工单 `SUPPORT-AISETTINGS-000001`：AI 设置 Feature 整体复制

### 13.1 目标

AISettings Feature 需要从 SparkClient 整体复制到 SupportClient，包括设置 UI、API Key 管理、模型管理、场景绑定、本地模型、Pro/试用期状态、Provider 连接测试和首登初始化入口。

源目录：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/AISettings
```

目标目录：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Features/AISettings
```

### 13.2 必须复制的文件

```text
Projects/Features/AISettings/Application
Projects/Features/AISettings/Domain
Projects/Features/AISettings/Infrastructure
Projects/Features/AISettings/Presentation
```

### 13.3 必须保留的功能

1. API Key 配置。
2. Provider 启用/禁用。
3. Provider 隐私政策确认。
4. Provider 连接测试。
5. 在线模型拉取。
6. 手动新增在线模型。
7. 本地模型管理。
8. 模型高级编辑。
9. 场景模型绑定。
10. `AIScenarioConfigEditorView`。
11. `ScenarioModelPreferencesViewModel`。
12. 小任务 `SmallTask` 配置。
13. Prompt 仓库入口。
14. 翻译字典入口。
15. 记忆设置入口如依赖未迁移，可先隐藏但保留结构。
16. AI 试用期状态展示。
17. AI 试用期申请/确认入口。
18. Pro 模型配置刷新。

### 13.4 试用期要求

必须迁移：

```text
Projects/Features/AISettings/Application/AITrialNotifications.swift
Projects/Features/AISettings/Presentation/Providers/AITrialSettingsView.swift
```

要求：

1. 设置页能展示试用期状态。
2. 用户可申请或确认 AI 试用。
3. 试用申请成功后刷新远程 AI 配置。
4. 收到试用结果通知后刷新 `AIConfigCenter`。
5. 试用期状态进入 AISettings snapshot。
6. 试用期能力不依赖 SparkClient 医疗场景。

### 13.5 AISettingsRepository 和存储

必须迁移：

```text
Projects/Features/AISettings/Domain/AISettingsRepository.swift
Projects/Features/AISettings/Infrastructure/DefaultAISettingsRepository.swift
Projects/Features/AISettings/Domain/AISettingsSeedLoader.swift
Projects/Features/AISettings/Domain/AISettingsSeedCatalog.swift
```

要求：

1. 使用 SupportClient 的 `CoreDataStack`。
2. 使用 SupportClient 的账号 session snapshot。
3. 按 `ownerAccountID` 隔离。
4. 不覆盖用户已经修改过的 provider/model/scenario 设置。
5. 支持从 `AISettings/APIKeys.json` 和 `AISettings/AllModels.json` 初始化。

### 13.6 UI 依赖处理

AISettings UI 可能依赖 SparkClient 的通用 UI 组件。

必须同步迁移或替换：

1. 表单组件。
2. Sheet 容器。
3. Safari WebView。
4. TextInput/PromptInput 相关组件。
5. 本地模型下载 Sheet 需要的文件选择或下载能力。

如果某个 UI 依赖属于 SparkClient 医疗/聊天专属，必须替换为 SupportClient 通用实现。

### 13.7 应用特有场景配置

AISettings UI 中所有展示 `AIScenario.allCases` 的地方，都必须展示 SupportClient 自己的场景集合。

要求：

1. `AIScenarioConfigEditorView` 不能展示已删除的医疗/营养场景。
2. 新增 SupportClient 场景必须可绑定模型。
3. 每个场景必须可以配置默认模型、温度、max token 等参数。
4. 设置保存后必须影响 `AIConfigCenter.resolve(for:)`。

### 13.8 验收标准

1. AI 设置入口可打开。
2. API Key 列表可展示默认 provider。
3. 可新增、编辑、隐藏 provider。
4. 可拉取 provider 模型列表。
5. 可编辑模型。
6. 可绑定 SupportClient 场景模型。
7. 可保存设置并重新加载。
8. 首次登录后默认 AISettings 已初始化。
9. 试用期页面可展示状态。
10. 试用期申请/确认后能刷新远程配置。
11. 所有 AISettings 页面不再强依赖医疗/营养/聊天业务页面。

## 14. 工单 `SUPPORT-STORAGE-000001`：CoreData 本地存储底座接入

### 14.1 目标

SupportClient 已经切换为 CoreData，本工单要求把 SparkClient 的 CoreData 底座思想迁移到 SupportClient，但必须使用 SupportClient 自己的模型文件。

当前模型：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/SupportClient.xcdatamodeld
```

参考实现：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Database/CoreDataStack.swift
```

### 14.2 CoreDataStack 要求

SupportClient 应提供：

```swift
final class CoreDataStack: @unchecked Sendable {
    static let shared: CoreDataStack
    static let preview: CoreDataStack
    var viewContext: NSManagedObjectContext { get }
    func performBackgroundTask<T: Sendable>(
        _ work: @escaping @Sendable (NSManagedObjectContext) throws -> T
    ) async throws -> T
}
```

初始化默认参数：

```swift
modelName: String = "SupportClient"
```

默认存储路径：

```text
Application Support/SupportClient/CoreData/SupportClient.sqlite
```

不能继续使用：

```text
Application Support/SparkClient/CoreData/SparkClient.sqlite
```

### 14.3 与现有 Persistence.swift 的关系

SupportClient 当前已有 `Persistence.swift`。迁移后需要二选一：

方案 A：保留 `PersistenceController`，但对齐 `CoreDataStack` 的能力。

方案 B：废弃 `PersistenceController`，统一使用 `CoreDataStack`。

推荐方案 B。

原因：

1. 与 SparkClient 底座一致。
2. 支持统一后台任务封装。
3. 便于组合根注入。
4. 便于后续账号级存储策略统一管理。

### 14.4 存储策略注册表

需要借鉴 SparkClient：

```text
Projects/App/Sources/App/Architecture/StorageRegistry.swift
```

SupportClient 应提供：

```swift
struct StorageRegistry {
    enum Backend {
        case coreData
        case userDefaults
        case keychain
        case fileSystem
        case memory
        case remote
    }
}
```

初期登记项：

1. CoreData。
2. UserDefaults。
3. Keychain device/token。
4. FileCache。
5. OSS runtime credentials。
6. Memory runtime。

### 14.5 账号隔离原则

CoreData 层必须为后续账号体系预留隔离方式。

可选策略：

1. 单 SQLite，多表带 `ownerAccountID` 字段过滤。
2. 每账号独立 SQLite。

推荐策略：

```text
单 SQLite + ownerAccountID 字段
```

原因：

1. 简化 CoreData 迁移。
2. 更适合轻量新应用快速启动。
3. 与 SparkClient 中部分仓库的账号过滤方式一致。

如果后续 SupportClient 数据有强隐私隔离要求，可以升级为每账号独立 SQLite。

### 14.6 验收标准

1. App 启动能加载 `SupportClient.xcdatamodeld`。
2. SQLite 写入路径包含 `SupportClient/CoreData`。
3. `performBackgroundTask` 可正常写入、保存、回滚。
4. `viewContext.automaticallyMergesChangesFromParent = true`。
5. 支持 preview/inMemory store。
6. App 不再同时保留两套互相竞争的 CoreData 入口。
7. `rg "SparkClient.sqlite|Application Support/SparkClient|modelName: String = \"SparkClient\"" SupportClient/SupportClient` 不应出现。

## 15. 工单 `SUPPORT-QA-000001`：迁移验收与回归检查

### 15.1 编译验收

必须通过：

1. Xcode Debug 编译。
2. Xcode Release 编译。
3. iOS Simulator 启动。
4. 真机启动，如果具备证书。

### 15.2 静态扫描

迁移完成后执行：

```bash
rg "SparkClient" /Users/hua/Downloads/Reference/SupportClient/SupportClient
rg "Medical|Nutrition|Knowledge" /Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Core
rg "SparkClient.sqlite|SparkClient.FileCache|SparkClient.DeviceCache" /Users/hua/Downloads/Reference/SupportClient/SupportClient
```

允许出现：

1. 注释中说明来源的 `SparkClient`。
2. 迁移文档中的 `SparkClient`。

不允许出现：

1. 运行时目录名残留。
2. Keychain service 残留，除非明确要求跨 App 共享。
3. OSS object key 残留。
4. CoreData modelName 残留。
5. SparkClient 医疗/营养/知识库场景残留为 SupportClient 默认必需项。

允许出现：

1. AISettings 模块。
2. Core/AI。
3. Core/AIRuntime。
4. 通用 `chat` AI 场景名称，但不能引入 SparkClient 聊天 Feature 依赖。

### 15.3 运行时验收

启动阶段：

1. App 能正常启动。
2. 日志 subsystem 为 `SupportClient`。
3. `SupportAppContainer.live()` 只初始化一次。
4. CoreData store 正常加载。
5. FileCache 目录可创建。
6. Device ID 可生成并持久化。

网络阶段：

1. 普通 GET 请求成功。
2. POST JSON 请求成功。
3. 后端 wrapped response 解码成功。
4. direct response 解码成功。
5. 401 能触发 refresh。
6. refresh 失败时能清理或保留 token，策略符合服务端错误码。
7. 429/5xx 能按策略重试。

文件阶段：

1. 文件缓存保存成功。
2. 文件名非法字符能被清理。
3. MD5 校验正确。
4. 缓存统计正确。
5. 清理缓存正确。
6. OSS 上传测试文件成功。
7. OSS SDK 使用与 SparkClient 相同的 Objective-C + Bridging Header 引用方式。

账号阶段：

1. 未登录使用 guest 文件缓存。
2. 登录后切换到 account 命名空间。
3. 登出后清理运行时 OSS 凭证。
4. 登出后回到 guest 文件缓存。

AI 阶段：

1. 首次登录后 AISettings 种子写入成功。
2. `AIConfigCenter.prewarm(ownerAccountID:)` 成功。
3. `AIRuntimeConfigStore` 有有效配置。
4. SupportClient 自有 `AIScenario` 可 resolve。
5. AI 试用期状态可加载。
6. Pro 模型配置可刷新。
7. 本地模型服务可初始化。
8. 远程配置失败时可降级到本地配置。

### 15.4 最小测试建议

建议补充以下测试：

1. `AuthTokenProviderTests`
2. `SupportNetworkEngineTests`
3. `RetryPolicyTests`
4. `SerialRequestGateTests`
5. `ETagStoreTests`
6. `FileCacheManagerTests`
7. `CoreDataStackTests`
8. `StorageRegistryTests`
9. `AISettingsSeedLoaderTests`
10. `AIConfigCenterTests`
11. `AIRuntimeConfigStoreTests`
12. `AIScenarioResolutionTests`

如果暂时不建测试 target，至少需要在开发环境做手工验证，并记录验证结果。

## 16. 风险与处理策略

### 16.1 SparkClient 业务耦合风险

风险：

直接复制网络目录可能带入医疗、AI、聊天 DTO，导致 SupportClient 底座变重。

处理：

1. 先复制核心引擎文件。
2. 再按编译错误补充最小依赖。
3. 凡是业务类型依赖，优先删除或替换为 SupportClient 自有类型。

### 16.2 OSS Objective-C SDK 接入风险

风险：

OSS SDK 依赖 Objective-C 文件和 Bridging Header，直接复制 Swift 文件会编译失败。

处理：

1. 同步复制 AliyunOSSSDK。
2. 建立 SupportClient Bridging Header。
3. 确认 `.m` 文件加入 Xcode target。
4. 确认 Build Phases 中 OSS Objective-C 源文件参与编译。
5. 不改变阿里云 SDK 的引用方式，保持与 SparkClient 一致，降低接入偏差。

### 16.3 CoreData 双入口风险

风险：

`Persistence.swift` 和 `CoreDataStack.swift` 同时存在，可能出现两个 persistent container。

处理：

1. 明确唯一 CoreData 入口。
2. 推荐使用 `CoreDataStack`。
3. `SupportClientApp` 只注入一个 `viewContext`。

### 16.4 Keychain service 变更风险

风险：

如果 SupportClient 服务端期望沿用 SparkClient/HealthClient 设备 ID，但客户端改成新 service，会导致设备身份变化。

处理：

1. 在实现前确认服务端设备身份策略。
2. 文档中记录选择。
3. 如果选择共用，注释必须解释原因。

### 16.5 命名大规模替换风险

风险：

直接全局替换 `Spark` 为 `Support` 可能破坏第三方 SDK 类名或注释。

处理：

1. 按模块重命名。
2. 每次重命名后编译。
3. 不替换 OSS SDK 内部类名。
4. 不替换服务端约定字段。

### 16.6 AI 场景误迁移风险

风险：

直接复制 `AIScenario` 和 `AIScenarioRemoteBundlesCollection` 会把 SparkClient 的医疗、营养、报告解读等场景带入 SupportClient，导致新 App 初始化时要求不存在的业务场景。

处理：

1. 保留 AI 底座结构。
2. 重写 SupportClient 的 `AIScenario` 场景集合。
3. 重写 `AIScenarioRemoteBundlesCollection` 字段或映射。
4. 首次登录预热时只 resolve SupportClient 启用场景。
5. AISettings UI 只展示 SupportClient 场景。

## 17. 推荐实施顺序

### 阶段一：Foundation

1. 创建 `Projects/Foundation` 目录。
2. 迁移日志、Atomic、JSON、JWT、RequestId、Keychain、SystemInfo、NetworkPathMonitor。
3. 完成命名清理。
4. 编译通过。

### 阶段二：Networking

1. 创建 `Projects/Core/Networking`。
2. 迁移 transport、models、engine、retry、serial gate、etag、device cache。
3. 新建 `SupportBackendConfiguration`。
4. 新建 `SupportBackend`。
5. 接入 `SupportAuthAPI`、`SupportOTPAPI`、`SupportDeviceAPI`、`SupportFileAPI`、`SupportOSSAPI`。
6. 编译通过。

### 阶段三：服务端接口对齐

1. 确认 SupportClient baseURL 指向 SparkService。
2. 对齐 `accounts` 登录、OTP、session、logout、device register 路径。
3. 对齐 `file_manager` files、register、business update、download-url、OSS STS 路径。
4. 对齐 `ai_config` bootstrap、trial、provider connection test 路径。
5. 确认后台 admin 可通过 bundle/business_type/AI 场景 key 区分 SupportClient 数据。

### 阶段四：登录模块

1. 迁移 Auth Domain/Application/Infrastructure/Presentation。
2. 接入 Apple 登录。
3. 接入手机号验证码登录。
4. 接入会话恢复。
5. 接入登出和账号级 runtime 清理。

### 阶段五：设备登记模块

1. 迁移设备信息采集。
2. 接入匿名设备登记。
3. 接入登录态设备登记。
4. 接入 APNs token 和通知授权状态上报。
5. 接入旧设备 401 退出策略。

### 阶段六：CoreData

1. 创建 `Projects/Core/Database/CoreDataStack.swift`。
2. 使用 `SupportClient.xcdatamodeld`。
3. 替换 `SupportClientApp` 中的 CoreData 注入。
4. 确认只有一个 CoreData container。

### 阶段七：AI 基础底座

1. 迁移 `AISettings/APIKeys.json` 和 `AllModels.json`。
2. 迁移 `Projects/Core/AI`。
3. 迁移 `Projects/Core/AIRuntime`。
4. 改造 `AIScenario` 为 SupportClient 自有场景。
5. 改造 `AIScenarioRemoteBundlesCollection`。
6. 接入 `SupportAIConfigAPI`。
7. 跑通 `AIConfigCenter.prewarm(ownerAccountID:)`。
8. 跑通本地配置和 Pro 配置降级链路。

### 阶段八：AISettings Feature

1. 整体复制 `Projects/Features/AISettings`。
2. 接入 AISettings 初始化存储。
3. 接入模型管理。
4. 接入 API Key 管理。
5. 接入场景绑定。
6. 接入 AI 试用期。
7. 隐藏或替换医疗/营养/知识库专属入口。

### 阶段九：文件缓存与 OSS

1. 迁移 `FileCacheManager`。
2. 改缓存目录名。
3. 迁移 OSS Swift 层。
4. 按 SparkClient 相同方式接入 Objective-C OSS SDK。
5. 接入 STS 获取。
6. 接入 `/api/v1/files/register/`。
7. 测试上传。

### 阶段十：Resources 与本地化

1. 迁移 `L10n.swift`。
2. 迁移 `Localizable.strings`。
3. 迁移 `Prompts.strings`。
4. 迁移 `ToolPrompts.strings`。
5. 迁移 AISettings 所需 provider 图标和通用 assets。
6. 替换 AppIcon 和品牌色为 SupportClient 语义。
7. 检查登录页、AISettings、通知 Host 无裸 key。

### 阶段十一：App 组合根

1. 创建 `SupportAppEnvironment`。
2. 创建 `SupportAppContainer`。
3. 创建 `SupportBootstrapper`。
4. 接入 `StorageRegistry`。
5. 接入 `AIAssembly` / `AISettings` 装配产物。
6. 登录后触发 AI 配置初始化和预热。
7. 让 `SupportClientApp` 使用组合根启动。

### 阶段十二：App 根视图与启动协调

1. 迁移 `NotificationHostView`。
2. 迁移 `ContentView` 的 `NotificationHostView -> AppCoordinatorView` 包装。
3. 迁移 `AppCoordinatorView` 状态机。
4. 迁移 `AppLifecycleCoordinator`。
5. 迁移 `AppSessionStore` 和 `SessionSnapshotStore` 配合方式。
6. 确保登录页 `LoginViewModel` 使用 `SignedOutAuthCoordinatorView` 缓存。
7. signedIn 后接入 SupportClient 主业务页或设置页。
8. 跑通冷启动、断网、恢复网络、登录、登出、401 失效回登录。

### 阶段十三：验收

1. 静态扫描。
2. 编译。
3. 启动。
4. 网络请求。
5. CoreData 写入。
6. 文件缓存。
7. OSS 上传。
8. AISettings 初始化。
9. AI 试用期。
10. Pro 模型远程配置。
11. 本地模型服务。
12. Resources 本地化。
13. NotificationHostView 根包装。
14. AppCoordinatorView 登录态分流。
15. AppEnvironment 环境切换。

## 18. 完成定义

本工单完成时，需要同时满足：

1. `SupportClient` 编译通过。
2. `SupportClient` 能正常启动。
3. Foundation 工具层可被 Core 和 Feature 引用。
4. 网络底座可以独立发起请求。
5. `SupportBackend` 已接入 `auth`、`otp`、`device`、`files`、`oss`、`aiConfig`。
6. Token refresh 机制已经接入 SparkService `/api/v1/auth/token/refresh/`。
7. Apple 登录和手机号验证码登录可调用 SparkService `accounts`。
8. 冷启动会话恢复可调用 SparkService `/api/v1/auth/session/`。
9. 登出可调用 SparkService `/api/v1/auth/logout/` 并清理本地运行时。
10. 设备登记可调用 SparkService `/api/v1/device/register/`。
11. 匿名设备登记、登录态设备登记、APNs token 上报、通知授权状态上报均已接入。
12. CoreData 使用 `SupportClient.xcdatamodeld`。
13. 文件缓存目录使用 `SupportClient.FileCache`。
14. OSS 使用 SupportClient object prefix。
15. 文件上传完成后登记到 SparkService `file_manager.ManagedFile`。
16. 后台管理系统继续使用 `/Users/hua/Downloads/Reference/SparkService`。
17. 后台能看到 SupportClient 用户、设备、登录审计、文件记录。
18. AISettings 初始化种子已加入 SupportClient target。
19. 首次登录后 AISettings 能初始化存储。
20. AIConfigCenter 能加载本地配置和 Pro 远程配置。
21. AIRuntimeConfigStore 有有效运行时快照。
22. SupportClient 自有 AIScenario 能完成模型绑定和 resolve。
23. AISettings Feature 已整体复制并可打开。
24. AI 试用期状态、申请/确认、结果刷新链路可用。
25. 本地模型服务保留。
26. 阿里云 OSS SDK 使用与 SparkClient 相同的 Objective-C + Bridging Header 引用方式。
27. `ContentView` 使用 `NotificationHostView(store:) { AppCoordinatorView(...) }` 根包装。
28. `AppCoordinatorView` 登录流程与 SparkClient 一致。
29. `SignedOutAuthCoordinatorView` 缓存 `LoginViewModel`。
30. `AppSessionStore` 登录缓存和会话恢复行为与 SparkClient 一致。
31. App 启动流程参考 SparkClient，网络门控、会话恢复、设备登记、账号准备均由生命周期协调器统一调度。
32. signedIn 后主业务页面可替换为 SupportClient 设置页/业务页，但替换点在 `preparedAccountID == session.accountID` 之后。
33. Resources 本地化文件和 `L10n` 已接入。
34. `SupportAppEnvironment` 统一管理 debug/staging/production、baseURL、siteURL、logLevel、subsystem。
35. App 组合根负责基础设施装配。
36. SparkClient 医疗、营养、知识库等业务 Feature 没有被误迁入底座。
37. 迁移残留扫描无阻塞问题。

## 19. 本轮实现记录（2026-07-06）

### 19.1 已落地源码目录

本轮实现已确认所有 target 源码均放在：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient
```

已新增/更新目录：

```text
SupportClient/App
SupportClient/Core/AI
SupportClient/Core/AIRuntime
SupportClient/Core/Database
SupportClient/Core/FileStorage
SupportClient/Core/Networking
SupportClient/Foundation
SupportClient/Projects/Features/AISettings
SupportClient/Resources
```

工程根目录下不再保留本轮迁移产生的 `App/Core/Foundation` 源码目录。

### 19.2 已实现能力

1. App 根入口已切换为组合根启动：`SupportClientApp -> AppContainer.live() -> ContentView(dependencies:)`。
2. `ContentView` 已使用要求的根包装：

```swift
NotificationHostView(store: dependencies.notificationStore) {
    AppCoordinatorView(dependencies: dependencies.coordinator)
}
```

3. 已实现 `SupportAppEnvironment`，统一管理 debug/staging/production、`apiBaseURL`、`siteBaseURL`、日志级别和 subsystem。
4. 已实现 Foundation 工具层：日志、Keychain、设备 ID、系统信息、请求 ID、JSON 编解码、本地化入口、网络状态监听。
5. 已实现网络底座：`SupportNetworkEngine`、`SupportNetworkRequest`、`SupportNetworkTransport`、`AuthTokenProvider`、401 token refresh、统一错误、wrapped response 解码。
6. 已实现 `SupportBackend` 聚合入口，包含 `auth`、`otp`、`device`、`files`、`oss`、`ocr`、`aiConfig`。
7. 已接入 SparkService accounts/file_manager/ai_config 对应接口路径。
8. 已实现登录模块基础闭环：密码登录、手机号 OTP 请求/校验、登出、`LoginViewModel`、`LoginView`、`SignedOutAuthCoordinatorView` 缓存 ViewModel。
9. 已实现 `AppSessionStore`、`SessionSnapshotStore`，登录态快照走 UserDefaults，Token 走 Keychain。
10. 已实现 `AppLifecycleCoordinator`：网络门控、冷启动恢复、匿名设备登记、登录态设备登记、账号准备态。
11. 已实现设备登记请求模型和 `DeviceRegistrationCoordinator`。
12. 已实现 CoreDataStack，继续使用 `SupportClient.xcdatamodeld`。
13. 已实现文件缓存、真实阿里云 OSS 上传、`FileTransferService`、STS 预拉/刷新与 file_manager 登记。
14. 已实现 AI 基础模型：`AIScenario`、`AIScenarioRemoteBundle`、`AIScenarioRemoteBundlesCollection`、`AIRuntimeConfiguration`。
15. 已实现 `AIRuntimeConfigStore`、`AIConfigCenter`、`AIRuntimeService`。
16. 已实现 AISettings 基础 Feature：本地初始化、远端 bootstrap、试用期申请、AI 设置页。
17. 已新增 `zh-Hans` 和 `en` 本地化资源。

### 19.3 当前边界

1. SUPPORT-OSS-OCR-000001 已完成：Aliyun OSS Objective-C SDK、OSS Core、OCR Core、登录后 STS 预拉、登出清理、Prompt OCR 接入均已落地；业务页附件上传可直接复用 `FileTransferService`。
2. AISettings 已完成可启动的底座版，不包含 SparkClient 完整 Provider/APIKey 管理 UI 的所有细节。
3. signedIn 后当前进入 `SupportMainCoordinatorView` 占位业务页和 AI 设置页，后续 SupportClient 业务主页或设置页应在该替换点接入。
4. APNs token 与通知授权状态字段已在设备模型保留，本轮未接真实推送注册回调。

### 19.4 编译验收

已执行：

```bash
xcodebuild -project /Users/hua/Downloads/Reference/SupportClient/SupportClient.xcodeproj -scheme SupportClient -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

结果：

```text
BUILD SUCCEEDED
```

### 21.5 AISettings 目录与页面结构对齐

已将 SupportClient 的 AISettings 功能整理为与 SparkClient 同层级的目录结构，保留可继续扩展的分层边界：

```text
SupportClient/SupportClient/Projects/Features/AISettings/
├── Application/
├── Domain/
├── Infrastructure/
└── Presentation/
    ├── Models/
    │   └── Components/
    ├── Personalization/
    ├── Preferences/
    ├── Providers/
    └── Root/
```

当前已落地的页面骨架包括：

1. `Presentation/Root/AISettingsView.swift`
2. `Presentation/Root/AISettingsViewModel.swift`
3. `Presentation/Providers/APIKeysSettingsView.swift`
4. `Presentation/Providers/AITrialSettingsView.swift`
5. `Presentation/Models/ModelsSettingsView.swift`
6. `Presentation/Preferences/AIModelPreferencesView.swift`
7. `Presentation/Root/SmallTasksSettingsView.swift`
8. `Presentation/Models/Components/ModelIconCatalog.swift`

对外入口已保持兼容：

1. `AppCoordinatorView` 仍可通过 `AISettingsView(store: dependencies.aiSettingsStore)` 进入。
2. `AISettingsStore` 补齐了 `snapshot`、`load()`、`submitTrialApplication()` 等页面骨架所需入口，便于后续继续按 SparkClient 方式扩展。

### 21.6 AISettings 页面 UI 与本地化对齐

本轮进一步补齐了 AISettings 相关页面的 UI 结构与文案键，目标是让 SupportClient 在页面体验上尽量贴近 SparkClient：

1. `APIKeysSettingsView` 已补成列表页 + 试用入口 + 新增服务商 + 编辑服务商 + 启用开关 + 删除手势。
2. `ModelsSettingsView` 已补成带搜索、分段筛选、编辑、启用开关、删除、拖拽排序的列表页。
3. `AIModelPreferencesView` 已补成按场景展示的模型配置页，支持来源切换与场景模型选择。
4. `SmallTasksSettingsView` 已补成可新建、编辑、删除的小任务列表页。
5. 对应的 `ai_settings.*` 本地化键已同步补入 `en.lproj` 和 `zh-Hans.lproj`。

### 21.7 本轮补充对齐

1. 服务商编辑页已补入该服务商下的模型列表，支持直接查看和切换模型启用状态。
2. 模型列表页启用逻辑已加上 API Key 校验，远程模型未配置有效服务商 Key 时不可直接开启。
3. `APIKeys.localizedDisplayName` 已切换为 `company_*` 本地化键，服务商名称与 SparkClient 保持同一套命名体系。
4. 默认模型配置页已支持「本地 / 试用(服务)」两种来源切换，并按来源解析对应的模型包。

### 21.6 账户管理页面对齐

已新增账户管理 feature，并挂接到 SupportClient 主应用导航中，整体结构与 SparkClient 的 `AccountManagement` 保持同层级拆分：

```text
SupportClient/SupportClient/Projects/Features/AccountManagement/
├── Application/
├── Domain/
├── Infrastructure/
└── Presentation/
    └── Components/
```

核心实现内容：

1. 新增 `AccountManagementView`、`AccountManagementViewModel`、`AccountDeactivationFlowState`。
2. 新增 `AccountManagementRepository`、`DefaultAccountManagementRepository`，接入 `auth/session`、`otp/email`、`otp/phone`、`deactivation` 接口。
3. 新增账户页核心组件：`AccountProfileCard`、`VerificationMethodCard`、`OTPVerificationCard`、`AppleReauthCard`、`FinalDeleteConfirmationDialog`、`AccountFailureCard`。
4. 支持当前会话加载、退出登录确认、高危停用验证流、Apple 重新认证、邮箱/手机号验证码验证。
5. `SupportMainCoordinatorView` 已增加账户页入口，并保持和 AI 设置页相同的一级 tab 结构。

后端对接点：

1. `SupportBackend` 新增 `deactivation` API。
2. `SupportOTPAPI` 新增 `requestEmailOTP`。
3. `UserSession` 扩展了 `displayName`、`email`、`signInMethod`、`signedInAt`，用于承接 SparkService 当前会话返回的扩展字段。

## 20. 登录 UI 对齐实现记录（2026-07-06）

### 20.1 已对齐 SparkClient 的登录能力

本轮已将 `SupportClient` 登录页从临时表单式 UI 替换为 `SparkClient` 同款登录体验，涉及：

1. 主登录页视觉结构：渐变盾牌图标、标题、副标题、灰色 grouped 背景、居中 toolbar 标题。
2. Apple 登录入口：使用 `SignInWithAppleButton`，包含 nonce 生成、SHA256 nonce、identity token、authorization code、email、fullName、userIdentifier 组装。
3. 协议勾选逻辑：未同意时 Apple 登录按钮半透明并拦截点击，触发协议弹窗和 shake 动画。
4. 首次启动协议提示：使用 `@AppStorage("auth.login.initial_legal_prompt_accepted")` 保存已同意状态。
5. 协议弹窗：包含条款、隐私、权限说明、拒绝/同意按钮、Safari 内置网页打开。
6. 手机号登录入口：保持 SparkClient 的隐藏入口逻辑，连续点击盾牌图标 3 次后显示手机号登录按钮。
7. 手机号登录页：地区区号选择、粘贴国际号码自动识别区号、手机号输入、发送验证码。
8. OTP 校验页：6 位验证码格子输入、倒计时、重新发送、安全提示、验证并登录按钮。
9. 游客模式入口：保留 SparkClient 登录页同款入口，当前 SupportClient 使用轻量占位页承接。
10. 本地化 key：已补齐登录页、协议、手机号、OTP、地区列表、通知提示的 `zh-Hans` 和 `en` 文案。

### 20.2 已新增/调整文件

```text
SupportClient/SupportClient/App/AuthFeature.swift
SupportClient/SupportClient/App/PhoneLoginConductor.swift
SupportClient/SupportClient/Core/UI/AuthSupportUI.swift
SupportClient/SupportClient/Core/UI/PhoneNumberSupport.swift
SupportClient/SupportClient/Resources/zh-Hans.lproj/Localizable.strings
SupportClient/SupportClient/Resources/en.lproj/Localizable.strings
```

### 20.3 当前边界

1. 登录 UI/流程已按 SparkClient 对齐。
2. 密码登录底层接口仍保留在 `AuthRepository`，但不再出现在登录 UI 中。
3. 游客模式当前是 SupportClient 轻量占位页；若需要完全复制 SparkClient 的游客 AI 聊天，还需要继续迁移 `GuestChatView` 及其临时 AI 配置链路。
4. Apple 登录需要真机或具备 Apple Sign In 能力的运行环境进行端到端验证；本轮已完成编译链路和 payload 组装接入。

### 20.4 编译验收

已执行：

```bash
xcodebuild -project /Users/hua/Downloads/Reference/SupportClient/SupportClient.xcodeproj -scheme SupportClient -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

结果：

```text
BUILD SUCCEEDED
```

## 21. NetworkGate 与 AISettings 初始化/本地存储对齐记录（2026-07-06）

### 21.1 NetworkGateView 对齐

已将 `SupportClient` 无网络拦截页调整为 `SparkClient` 同款结构：

1. `NetworkGateView` 从 `AppCoordinatorView.swift` 内部拆出到独立目录：

```text
SupportClient/SupportClient/App/Presentation/NetworkGateView.swift
```

2. `AppCoordinatorView` 调用方式改为：

```swift
NetworkGateView(monitor: networkMonitor)
```

3. 页面结构与 SparkClient 一致：全屏系统背景、`wifi.slash` 大图标、标题/副标题、网络恢复提示、重新检查按钮、打开系统设置按钮、失败 alert。
4. 已补齐 `network.gate.*` 与 `common.ok` 本地化文案。

### 21.2 AISettings Seed Loader 对齐

已将 SparkClient 的 seed 资源复制到 SupportClient target 源码根：

```text
SupportClient/SupportClient/AISettings/APIKeys.json
SupportClient/SupportClient/AISettings/AllModels.json
```

已新增与 SparkClient 同款职责的 seed loader：

```text
SupportClient/SupportClient/Projects/Features/AISettings/Domain/AISettingsSeedLoader.swift
```

包含：

1. `AISettingsSeedLoader.loadAPIKeys(bundle:)`
2. `AISettingsSeedLoader.loadAllModels(bundle:)`
3. `AISettingsSeedLoader.loadScenarioBindings(bundle:)`
4. `AISettingsSeedCatalog`
5. `APIKeySeedRow`
6. `AllModelSeedRow`

SupportClient 对 SparkClient 医疗场景做了映射适配：

1. 医疗结构化/文档识别/病例类场景映射到 `support_ticket_analysis`。
2. 报告/解读类场景映射到 `support_knowledge_answer`。
3. 处方/用药/药盒类场景映射到 `support_reply_draft`。
4. 通用场景 `chat/optimization/context/router/modelConfig` 保留。

### 21.3 AI 本地存储数据结构对齐

已新增/调整 AI 本地存储模型，使结构形态与 SparkClient 一致：

```text
SupportClient/SupportClient/Projects/Features/AISettings/Domain/AISettingsDomainModels.swift
SupportClient/SupportClient/Projects/Features/AISettings/Domain/AISettingsSnapshot.swift
SupportClient/SupportClient/Core/AI/AIRuntimeModels.swift
SupportClient/SupportClient/Core/AIRuntime/AIRuntimeConfigStore.swift
```

核心变化：

1. 新增 `AISettingsSnapshot`，包含 `allModels`、`scenarioBindings`、`apiKeys`、`smallTasks`、`searchToolPreferences`、`searchConfigRevision`、`scenarioModelSources`、`trial`、`trialModelPolicy`、`searchKeys`、`toolKeys`、`promptRepo`、`memoryArchive`、`translationDic`。
2. 新增 `AISettingsSnapshot.seeded()`，首次本地初始化时从 `AISettings/APIKeys.json` 与 `AISettings/AllModels.json` 构建快照。
3. 新增 `AISettingsSnapshot.localScenarioBundles()`，按 SparkClient 的场景绑定方式生成本地 `AIScenarioRemoteBundlesCollection`。
4. `AIScenarioRemoteBundle` 已改为 SparkClient 同款 `defaultModelName + models` 结构，并支持 `resolveRow(preferredModelName:)`、`resolveConfig(preferredModelName:)`。
5. `AIScenarioRemoteBundlesCollection` 已从字典结构改为强字段结构，保留 SupportClient 自有场景字段。
6. `AIRuntimeConfiguration` 增加 `settingsSnapshot`，运行时缓存同时保留本地设置快照与场景 bundle。
7. `AIRuntimeConfigStore` 改为 MainActor 本地存储类，避免 Swift 默认 MainActor 隔离下的 Codable actor warning。

### 21.4 编译验收

已执行：

```bash
xcodebuild -project /Users/hua/Downloads/Reference/SupportClient/SupportClient.xcodeproj -scheme SupportClient -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

结果：

```text
BUILD SUCCEEDED
```

## 22. 后续拆分工单：AISettings CoreData 主存储对齐

已新增专项工单：

```text
/Users/hua/Downloads/Reference/SupportClient/需求文档/SUPPORT-AI-CORE-DATA-000001-AI设置CoreData持久化与初始化流程对齐SparkClient需求工单.md
```

该工单专门处理：

1. 将 SparkClient 的 AI 相关实体结构迁入 `SupportClient.xcdatamodeld`。
2. 将 AISettings 仓储层从 `AIRuntimeConfigStore` 临时存储切换为真正的 Core Data 账号级持久化。
3. 对齐 SparkClient 的首次登录 seed、账号隔离、Provider/Model/ScenarioBinding/SmallTask/PromptRepo 持久化、UserDefaults 偏好载荷、运行时缓存重建流程。
4. 明确 `AIRuntimeConfigStore` 后续只作为 runtime cache，不再作为 AISettings 主存储。

## 23. 后续拆分工单：OSS 文件上传与 OCR 底座迁移

专项工单：

```text
/Users/hua/Downloads/Reference/SupportClient/需求文档/SUPPORT-OSS-OCR-000001-OSS文件上传与OCR底座迁移对齐SparkClient需求工单.md
```

SUPPORT-OSS-OCR-000001 已完成：

1. Aliyun OSS Objective-C SDK 已按 SparkClient 引用方式迁入（Bridging Header + CoreTelephony / SystemConfiguration / libresolv）。
2. OSS Core 已迁入 `Projects/Core/OSS`，占位 `OSSClientWrapper` 已替换为真实 SDK 上传。
3. `FileTransferService` 已落地：本地缓存、MD5、STS 获取/刷新、真实 OSS 上传、file_manager 注册、下载、预签名 URL。
4. App 登录后预拉 OSS STS，登出/账号切换清理 runtime credentials。
5. OCR Core 已迁入 `Projects/Core/OCR`，Prompt 输入 OCR 已接入 `OCROrchestrator`。

## 24. 后续拆分工单：日志打印与启动链路诊断对齐

已新增专项工单：

```text
/Users/hua/Downloads/Reference/SupportClient/需求文档/SUPPORT-LOGGING-000001-日志打印与启动链路诊断对齐SparkClient需求工单.md
```

SUPPORT-LOGGING-000001 已完成：

1. 日志基础设施已对齐 SparkClient（`Atomic` 存储、`LogLevel.symbol`、handler 注入、`reset`、`LogMessageSanitizer`、模块扩展）。
2. 网络 Operation / CallbackCache / requestID / 原始报文 / 解码摘要日志已落地；API 经 `SupportBackendConfiguration.execute` 执行。
3. App 启动、会话恢复、账号准备、设备登记、AI prewarm、remote config、OSS STS 链路日志已补齐。
4. 设备登记与 OSS STS 取消已有明确归因；账号准备改由 `AppLifecycleCoordinator` + `SignedInSessionPreparationRegistry` 调度，避免 SwiftUI `.task` 取消。
5. 裸 `print` 已清理；上传进度改为结构化日志；`SupportLogger` / `OSSConfiguration` 的 `nonisolated(unsafe) static var` 已改为 Atomic，降低 `unsafeForcedSync` 风险。

## 25. 后续修复工单：Token 刷新失败与账号级启动链路中止

已新增专项修复工单：

```text
/Users/hua/Downloads/Reference/SupportClient/需求文档/SUPPORT-AUTH-401-000001-Token刷新失败与账号级启动链路中止对齐SparkClient修复工单.md
```

SUPPORT-AUTH-401-000001 已完成：

1. Token refresh 失败判定已对齐 SparkClient（解析 BackendError、明确鉴权失效才清 token、临时失败保留本地登录态）。
2. 明确鉴权失效会发统一 `SupportAuthSessionInvalidation` 通知，并由 `AppRouteCoordinator` / `AppLifecycleCoordinator` 回到登录态。
3. 设备登记返回 `DeviceRegistrationRequestOutcome`；鉴权失效或重试用尽会中止账号级 bootstrap。
4. refresh 401 后不再继续请求 OSS STS / AI prewarm。
5. 新增 `SupportClientTests`，覆盖 refresh 401、并发 refresh 去重、临时失败不清 token、bootstrap gate。

## 26. 快速修复工单：OSS STS bucket_name 字段兼容

已新增快速修复工单：

```text
/Users/hua/Downloads/Reference/SupportClient/需求文档/SUPPORT-OSS-STS-000001-OSS_STS_bucket_name字段兼容快速修复工单.md
```

该工单专门处理：

1. OSS STS 接口 200 成功，但 `SupportOSSConfigurationStore` 打印“字段不完整，未缓存”的问题。
2. 服务端返回 `bucket_name`，SupportClient 当前 `OSSCredentialsResponse` 只读取 `bucket` / `bucketName`，导致 bucket 为空。
3. 同步修复 `OCRSTSCredentialsResponse`，避免 OCR STS 后续出现同类问题。
4. 验收目标为登录后出现 `OSS 配置已加载 bucket=zhaodkdream region=cn-shanghai`，并且上传前配置刷新可正常返回 `AliyunOSSRuntimeConfig`。

## 27. 后续修复工单：登录态持久化与 Token / Session 分层

已新增专项修复工单：

```text
/Users/hua/Downloads/Reference/SupportClient/需求文档/SUPPORT-AUTH-SESSION-000001-登录态持久化与Token会话分层对齐SparkClient修复工单.md
```

该工单专门处理：

1. SupportClient 登录后一段时间自动失效，而 SparkClient 可长期保持登录态的问题。
2. 修复 `UserSession` 保存 access/refresh token，冷启动又用旧 snapshot token 覆盖 Keychain 新 token 的结构性问题。
3. 对齐 SparkClient：`UserSession` 只保存账号资料，token 只由 `AuthTokenProvider` / Keychain 管理。
4. 冷启动恢复先验证/刷新 token，再拉取 current session，最后更新无 token session snapshot。
5. 兼容迁移旧版含 token 的 session snapshot，避免旧 refresh token 回滚。

SUPPORT-AUTH-SESSION-000001 已完成：

1. `UserSession` 已移除 access/refresh token，`SessionSnapshotStore` 只保存账号资料（v2）。
2. `AuthTokenProvider` 独立持有 Keychain token 与 expiresAt；登录 API 解码后立即 `setTokens`。
3. 冷启动恢复先验证/刷新 token，再拉取 current session 并合并快照。
4. 旧含 token 的 v1 快照已兼容迁移，且不会覆盖 Keychain 中已有新 token。
5. 登录态长期保持逻辑已对齐 SparkClient；新增 `SupportAuthSessionPersistenceTests`。

### SUPPORT-NETWORK-CORE-000001

已完成：网络底层对齐 `Projects/Core/Networking`，含 ETag / Retry / SerialRequestGate / CallbackCache。
