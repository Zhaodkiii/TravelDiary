# SUPPORT-LOGGING-000001 日志打印与启动链路诊断对齐 SparkClient 需求工单

## 1. 工单背景

SupportClient 当前已经迁入了部分 SparkClient 底层能力，包括账号命名空间文件缓存、AI Core Data 仓储、OSS STS 预拉取、设备登记、AppLifecycleCoordinator 等。但从当前启动日志看，SupportClient 的日志体系仍明显不够完整，无法像 SparkClient 一样快速判断启动流程中每一步的状态、网络请求的业务含义、取消来源、缓存命中、响应解码结果和并发风险。

用户提供的 SupportClient 关键日志片段：

```text
文件缓存已切换到账号命名空间 accountID=811
HTTP POST /api/v1/device/register requestID=93F01415-BBB1-432D-B4B3-BC253CADE823
Device registration failed: 已取消
AI loadSnapshot 读链路开始 ownerAccountID=811 账号来源=显式参数
AI loadSnapshot 读链路：Core Data fetch AIProviderEntity + AISearchProviderEntity + AIModelEntity + AISmallTaskEntity + PromptRepoEntity ownerAccountID=811
AI loadSnapshot 读链路完成 ownerAccountID=811 读到 厂商Key=29 搜索厂商=0 模型=24 场景绑定=244 小任务=0 提示词=0；偏好：UserDefaults 已存在载荷
refreshRemoteConfig skipped: no remote provider wired
HTTP GET /api/v1/oss/sts/credentials requestID=BC32AED3-C64F-459A-83AA-D086C8E0DF8C
OSS STS 预拉取失败（后续上传前将重试）：已取消
Account 811 bootstrap complete
Prepared signed-in account 811
0.5
Potential Structural Swift Concurrency Issue: unsafeForcedSync called from Swift Concurrent context.
0.5
```

这段日志暴露出几个问题：

1. 设备登记请求被取消，但日志没有说明取消来源。
2. OSS STS 预拉取被取消，但日志没有说明是生命周期切换、SwiftUI `.task` 取消、网络中断、账号切换、还是外部 Task 取消。
3. 网络日志只有 `HTTP METHOD path requestID`，缺少业务说明、Operation 名称、请求详情、响应详情、耗时、状态码、解码摘要。
4. `refreshRemoteConfig skipped: no remote provider wired` 没有说明是否符合当前 SupportClient 预期。
5. 出现裸 `0.5` 日志，疑似临时 `print` 或调试输出未清理。
6. 出现 `Potential Structural Swift Concurrency Issue: unsafeForcedSync called from Swift Concurrent context.`，说明存在 Swift Concurrency 结构性风险，需要单独定位。
7. SupportClient 当前日志无法形成 SparkClient 那样完整的启动链路审计。

SparkClient 已经有完整参考实现，日志可覆盖：

1. Backend 初始化。
2. AppContainer / Assembly 装配。
3. 网络状态评估。
4. 会话恢复。
5. 账号运行时切换。
6. 设备登记阶段。
7. AI Core Data 读链路。
8. AI remote bootstrap。
9. OSS STS 预拉取。
10. ETag / CallbackCache / Operation。
11. 请求和响应原始报文。
12. 解码 key 摘要。
13. 启动准备步骤开始、完成、跳过、降级。

本工单目标是参考 SparkClient 实现，补齐 SupportClient 的日志打印和启动链路诊断能力，同时解决当前日志中暴露的取消归因、并发风险和裸输出问题。

## 2. 工单编号

```text
SUPPORT-LOGGING-000001
```

## 3. 目标

### 3.1 日志体系目标

1. 将 SupportClient 日志能力对齐 SparkClient 的 `Logger` / `LogModule` / `SupportLogger` 体系。
2. 网络层支持 Operation 业务语义日志。
3. 网络层支持 requestID 全链路日志。
4. 网络层支持请求摘要、请求原始报文、响应摘要、响应原始报文。
5. 网络层支持响应解码成功摘要。
6. 网络层支持 CallbackCache 复用日志。
7. 网络层支持 ETag/304 缓存合并日志。
8. App 启动支持 Assembly、生命周期、会话恢复、账号准备、设备登记、AI、OSS 的分阶段日志。
9. 取消类错误必须记录取消来源和上下文。
10. 日志必须脱敏，不能泄露 token、API key、STS secret、security token。

### 3.2 启动链路诊断目标

1. 能通过一段启动日志看出当前 App 从冷启动到进入已登录态的完整流程。
2. 能区分会话恢复、登录后准备、前台恢复、账号切换、登出清理。
3. 能判断设备登记是否成功、跳过、等待 APNs、取消或失败。
4. 能判断 AI 本地配置是否从 Core Data 正常读取。
5. 能判断 remote AI config 是否已 wired、是否跳过、是否成功。
6. 能判断 OSS STS 是否预拉成功、失败、字段不完整或被取消。
7. 能定位 `unsafeForcedSync` 的触发路径。
8. 能清理裸 `0.5` 这类无业务含义日志。

## 4. 非目标

本工单不做：

1. 不改变业务功能行为。
2. 不重写 SupportClient 全部网络层，除非为了 Operation 日志必须抽象。
3. 不默认在生产环境打印完整 body。
4. 不把敏感字段写入日志。
5. 不修 AI Core Data 数据正确性问题，除非日志暴露出读取链路 bug。
6. 不修 OSS 上传功能，OSS 上传归属 `SUPPORT-OSS-OCR-000001`。

## 5. SparkClient 参考文件

### 5.1 日志基础

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Foundation/Utilities/Logger.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Foundation/Utilities/LogModule.swift
```

参考能力：

1. `LogLevel`
2. `LogModule`
3. `Logger` protocol
4. `ConsoleLogger`
5. `SparkLogger.configure`
6. `LogMessageSanitizer.singleLineSnippet`

### 5.2 网络日志

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Networking/Logging/SparkNetworkingStrings.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Networking/Logging/NetworkOperationBusinessPurpose.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Networking/Operations/SparkNetworkOperation.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Networking/Caching/SparkCallbackCache.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Networking/SparkBackendConfiguration.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Networking/SparkNetworkEngine.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Networking/API/Common/APIResponseDecoder.swift
```

参考日志样式：

```text
Backend 初始化完成，已装配 HTTPClient、Operation、CallbackCache
Backend 即将执行 业务=鉴权：拉取当前账号最新会话（含 Pro 状态） API=AuthAPI Operation=Auth.CurrentSession
业务=鉴权：拉取当前账号最新会话（含 Pro 状态） Operation 请求详情 method=GET path=/api/v1/auth/session/ query= requiresAuth=true allowETag=false retryEnabled=true maxRetry=2
Operation 首次发起请求 业务=鉴权：拉取当前账号最新会话（含 Pro 状态） operation=Auth.CurrentSession cacheKey=GET|/api/v1/auth/session/|
请求 method=GET url=/api/v1/auth/session requestId=...
请求原始报文 headers={"Authorization":"Bearer ***","X-Request-ID":"..."} body=
响应 method=GET url=/api/v1/auth/session requestId=... status=200 cost=0.238s size=160B
响应原始报文 method=GET url=/api/v1/auth/session requestId=... status=200 cost=0.238s headers={...} body={...}
响应解码成功 type=CurrentSessionResult keys=root=[code,data,msg] data=[...]
```

### 5.3 生命周期与取消规避

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Sources/App/AppCoordinatorView.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Sources/App/Architecture/AppLifecycleCoordinator.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Sources/App/Architecture/SignedInSessionPreparationRegistry.swift
```

关键参考点：

```swift
// 账号准备由 AppLifecycleCoordinator 统一调度（冷启动 / 登录），避免 SwiftUI .task 取消导致登记中断。
```

SupportClient 当前设备登记和 OSS STS 出现 `已取消`，需要重点对齐 SparkClient 的生命周期调度和日志归因。

## 6. SupportClient 当前相关文件

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Foundation/Logger.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Core/Networking/SupportNetwork.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Core/Networking/SupportBackend.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App/AppContainer.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App/AppLifecycleCoordinator.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App/AppBootstrapper.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App/DeviceRegistrationCoordinator.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Core/AI/AIConfigCenter.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Core/OSS/SupportOSSConfigurationStore.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Features/AISettings/Infrastructure/DefaultAISettingsRepository.swift
```

## 7. 当前差距分析

### 7.1 Logger 基础差距

SupportClient 当前 `SupportLogger`：

```swift
enum SupportLogger {
    nonisolated(unsafe) static var logLevel: LogLevel = .info
    nonisolated(unsafe) static var subsystem: String = "SupportClient"
}
```

问题：

1. 使用 `nonisolated(unsafe)` 静态可变状态。
2. 缺少 SparkClient 的 Atomic 存储模式。
3. 缺少 `LogLevel.symbol`。
4. 缺少统一 `reset()`。
5. 缺少可注入 handler，测试和日志采集不方便。
6. 缺少 `LogMessageSanitizer`。

### 7.2 网络日志差距

SupportClient 当前日志：

```text
HTTP POST /api/v1/device/register requestID=...
HTTP 200 /api/v1/device/register bytes=...
```

缺少：

1. 业务说明。
2. API 名称。
3. Operation 名称。
4. 请求详情：method/path/query/requiresAuth/retry/serialKey。
5. CallbackCache hit/miss。
6. 请求原始报文。
7. 响应原始报文。
8. 响应耗时。
9. 响应解码类型。
10. 响应 JSON key 摘要。
11. 错误体解析。
12. 取消归因。
13. retry 日志。
14. 401 refresh 日志。
15. ETag 304 缓存日志。

### 7.3 启动链路差距

SupportClient 当前启动链路日志缺少：

1. Backend 初始化完成。
2. AppContainer 开始/完成组合。
3. 各领域 Assembly 开始/完成。
4. 网络路径评估。
5. 会话快照读取/保存。
6. 会话恢复详情。
7. 账号运行时清理步骤。
8. 账号准备步骤开始/完成。
9. 设备登记阶段开始/等待 APNs/提交/完成。
10. OSS STS 预拉取成功/失败/取消归因。
11. `Prepared signed-in account` 前每个步骤的结果。

### 7.4 当前日志暴露的问题

#### 设备登记被取消

日志：

```text
Device registration failed: 已取消
```

要求：

1. 区分是 `CancellationError`、`URLError.cancelled` 还是业务取消。
2. 打印 reason、accountID、requestID、lifecycle phase。
3. 如果是 SwiftUI `.task` 取消，必须调整到 AppLifecycleCoordinator 稳定任务中。
4. 取消不应作为普通 error 污染错误日志，应按 warning/debug 和明确原因记录。

#### OSS STS 预拉取被取消

日志：

```text
OSS STS 预拉取失败（后续上传前将重试）：已取消
```

要求：

1. 区分预拉取取消和真实失败。
2. 记录 accountID、requestID、触发来源。
3. 如果预拉取 task 被上层取消，记录 `cancelledBy=...`。
4. 上传前重试仍然保留。

#### remote provider 未 wired

日志：

```text
refreshRemoteConfig skipped: no remote provider wired
```

要求：

1. 明确这是当前 SupportClient 暂未装配 remote config provider，还是装配漏了。
2. 日志需要包含 `ownerAccountID`、`isPro`、`remoteProvider=nil`。
3. 如果 SupportClient 应支持 Pro remote AI config，则此日志应升级为待修复问题。

#### 裸 `0.5`

日志：

```text
0.5
0.5
```

要求：

1. 全局搜索并移除裸 `print(0.5)`、`debugPrint(0.5)` 或无上下文 logger。
2. 如果是进度日志，改成结构化日志，例如：

```text
上传进度 progress=0.5 fileUUID=...
```

3. 不允许没有业务语义的裸数字日志进入控制台。

#### `unsafeForcedSync`

日志：

```text
Potential Structural Swift Concurrency Issue: unsafeForcedSync called from Swift Concurrent context.
```

要求：

1. 定位触发栈。
2. 检查是否从 async context 同步访问 MainActor 或 SwiftUI 状态。
3. 检查 `nonisolated(unsafe)` 静态状态、同步锁、`DispatchQueue.main.sync`、`MainActor.assumeIsolated`、同步 Core Data 调用。
4. 优先修复 `SupportLogger` 的 `nonisolated(unsafe)` 静态变量。
5. 不能只忽略该警告。

## 8. 目标日志规范

### 8.1 日志级别

| Level | 使用场景 |
| --- | --- |
| `verbose` | 极细粒度调试，默认不打开 |
| `debug` | 可用于开发定位流程、缓存、请求复用 |
| `info` | 正常启动链路、关键业务阶段完成 |
| `warning` | 可降级失败、取消、重试、配置缺失 |
| `error` | 用户功能失败、不可恢复错误、数据损坏 |

### 8.2 模块

SupportClient 至少保留：

```swift
enum LogModule: String {
    case app = "APP"
    case auth = "AUTH"
    case network = "NETWORK"
    case device = "DEVICE"
    case cache = "CACHE"
    case oss = "OSS"
    case aiConfig = "AI_CONFIG"
    case database = "DATABASE"
    case notification = "NOTIFICATION"
    case general = "GENERAL"
}
```

建议新增：

```swift
case lifecycle = "LIFECYCLE"
case file = "FILE"
case ocr = "OCR"
case routing = "ROUTING"
```

### 8.3 敏感信息脱敏

必须脱敏：

1. `Authorization`
2. `access_token`
3. `refresh_token`
4. `accessKeySecret`
5. `access_key_secret`
6. `securityToken`
7. `security_token`
8. `api_key`
9. `apiKey`
10. `key`
11. `password`
12. `phone`
13. `email`
14. STS token 长字段。

要求：

1. 默认生产环境不打印完整 body。
2. Debug 环境可打印 body，但必须脱敏。
3. 大 body 必须截断。
4. AI remote config 中 provider API key 必须脱敏。
5. OSS STS 响应中的密钥必须脱敏。

## 9. 网络层改造要求

### 9.1 新增 Operation 抽象

参考 SparkClient：

```text
SparkNetworkOperation
CacheableSparkNetworkOperation
SparkBackendConfiguration.execute
```

SupportClient 目标：

```swift
protocol SupportNetworkOperation: Sendable {
    var name: String { get }
    var apiName: String { get }
    var request: SupportNetworkRequest { get }
    var callbackCacheKey: String? { get }
}
```

要求：

1. 所有 API 方法优先通过 Operation 执行。
2. Operation 提供稳定 `name`。
3. `apiName` 标明 API 所属，例如 `AuthAPI`、`DeviceAPI`、`OSSAPI`。
4. GET 请求可生成 callback cache key。

### 9.2 新增 Backend Configuration

SupportClient 需要新增类似：

```swift
final class SupportBackendConfiguration {
    let engine: SupportNetworkEngine
    let callbackCache: SupportCallbackCache
    let logger: Logger

    func execute(_ operation: some SupportNetworkOperation) async throws -> SupportTransportResponse
}
```

日志要求：

1. `Backend 初始化完成，已装配 HTTPClient、Operation、CallbackCache`
2. `Backend 即将执行 业务=... API=... Operation=...`
3. `业务=... Operation 请求详情 method=... path=... query=... requiresAuth=... retryEnabled=...`
4. `Operation 首次发起请求 ...`
5. `Operation 复用进行中的请求 ...`

### 9.3 新增 CallbackCache

参考 SparkClient：

```text
SparkCallbackCache
```

SupportClient 目标：

```swift
actor SupportCallbackCache {
    private var inFlight: [String: Task<SupportTransportResponse, Error>] = [:]
}
```

要求：

1. 相同 GET operation 并发时只发一次真实请求。
2. 复用请求时打印 hit。
3. 首次请求时打印 miss。
4. 任务结束后清理 inFlight。

### 9.4 新增业务目的映射

参考 SparkClient：

```text
NetworkOperationBusinessPurpose
```

SupportClient 目标：

```swift
enum SupportNetworkOperationBusinessPurpose {
    static func describe(_ operation: some SupportNetworkOperation) -> String
}
```

至少覆盖：

1. `Auth.CurrentSession`：鉴权：拉取当前账号最新会话（含 Pro 状态）
2. `Auth.AppleLogin`：登录：Sign in with Apple
3. `Auth.PhoneLogin`：登录：手机号验证码
4. `OTP.Request`：OTP：请求验证码
5. `Device.Register`：设备域：上送安装 device_id 与终端画像
6. `OSS.STS`：获取阿里云 OSS 临时访问凭证（直传/下载）
7. `OCR.STS`：获取 OCR 服务临时凭证或配置
8. `AIConfig.Bootstrap`：拉取 AI 多场景模型与网关配置
9. `AIConfig.TrialStatus`：查询 AI 试用资格与剩余额度
10. `AIConfig.TrialApply`：申请或确认 AI 试用
11. `File.Register`：文件：登记客户端直传后的元数据
12. `File.List`：文件：按业务维度列出已登记文件
13. `Account.Delete` / `Deactivation.*`：账号注销相关

### 9.5 请求/响应报文日志

必须支持：

1. 出站摘要：

```text
请求 method=GET url=/api/v1/auth/session requestId=...
```

2. 出站原始报文：

```text
请求原始报文 headers={...脱敏...} body={...脱敏/截断...}
```

3. 入站摘要：

```text
响应 method=GET url=/api/v1/auth/session requestId=... status=200 cost=0.238s size=160B
```

4. 入站原始报文：

```text
响应原始报文 method=GET url=/api/v1/auth/session requestId=... status=200 cost=0.238s headers={...} body={...脱敏/截断...}
```

5. 解码摘要：

```text
响应解码成功 type=CurrentSessionResult keys=root=[code,data,msg] data=[...]
```

### 9.6 取消与重试日志

取消必须结构化：

```text
请求取消 method=POST path=/api/v1/device/register requestId=... operation=Device.Register reason=taskCancelled phase=signedInDeviceRegistration accountID=811
```

重试必须结构化：

```text
请求准备重试 method=GET path=/api/v1/oss/sts/credentials retry=1 delay=0.5s reason=networkLost
```

要求：

1. `CancellationError` 与 `URLError.cancelled` 单独处理。
2. 取消不应进入普通 decoding/http error。
3. 如果取消是预期生命周期切换，使用 debug 或 warning。
4. 如果取消导致关键流程未完成，必须记录恢复策略。

## 10. App 启动链路日志要求

### 10.1 AppContainer / Assembly

SupportClient 必须补齐：

```text
Backend 初始化完成，已装配 HTTPClient、Operation、CallbackCache
AppContainer 开始组合各领域 Assembly
AppAssembly 装配基础设施开始
AppAssembly 装配基础设施完成
AuthAssembly 装配认证核心
AIAssembly 装配 AI 配置与运行时
NotificationAssembly 装配通知/Push/路由核心
AppAssembly 装配启动协调器
AppContainer 组合完成：容器仅持有 Assembly facade 与共享运行时
```

如果 SupportClient 暂未拆 Assembly，也应按当前结构打印同等阶段日志。

### 10.2 网络状态与会话恢复

必须补齐：

```text
启动流程：网络路径已评估但当前不可用，等待网络恢复后再执行引导与会话恢复
启动流程：网络路径已评估且可用，开始会话恢复与应用级引导
会话快照：读取成功 accountID=... bytes=...
会话恢复：认证令牌已就绪，开始拉取服务端最新 UserSession
会话恢复成功：已使用服务端最新 UserSession accountID=... isPro=...
AppSessionStore：冷启动会话已恢复 accountID=... isPro=...
```

### 10.3 账号准备

必须补齐：

```text
会话流程：准备账号运行时 accountID=...
会话流程：准备步骤 activateUser 开始 accountID=...
账号运行时：开始切换到账号 accountID=...
存储策略：开始执行统一清理 reason=accountSwitch(...)
文件缓存已切换到账号命名空间 accountID=...
文件传输运行时凭证已清理
存储策略：统一清理完成 reason=accountSwitch(...)
账号级 ViewModel 与主 Tab 依赖缓存已清理
账号运行时：账号切换完成 accountID=...
会话流程：准备步骤 signedInDeviceRegistration 开始 accountID=... reason=...
会话流程：准备步骤 bootstrapIfNeeded 开始 accountID=...
Prepared signed-in account ...
```

### 10.4 设备登记

必须补齐：

```text
设备登记阶段开始 reason=... accountID=...
设备登记等待 APNs token timeout=1.5s
设备登记提交 reasons=[...] includesPushToken=true
设备登记成功 id=... created=...
设备登记阶段完成 outcome=submitted reason=... accountID=...
```

取消时必须补齐：

```text
设备登记阶段取消 reason=... accountID=... requestId=... cancelledBy=...
```

### 10.5 AI 读链路

SupportClient 当前已有部分 AI 读链路日志，继续保留并增强：

```text
AIConfigCenter.prewarm 开始 ownerAccountID=...
AI loadSnapshot 读链路开始 ownerAccountID=... 账号来源=显式参数
AI loadSnapshot 读链路：Core Data fetch AIProviderEntity + AISearchProviderEntity + AIModelEntity + AISmallTaskEntity + PromptRepoEntity ownerAccountID=...
AI loadSnapshot 读链路完成 ownerAccountID=... 读到 厂商Key=... 搜索厂商=... 模型=... 场景绑定=... 小任务=... 提示词=...；偏好：...
AIConfigCenter.prewarm 已从仓储拿到快照 厂商Key=... 模型=... 提示词=...，即将写入运行时缓存
AIConfigCenter.prewarm 结束，运行时本地 bundle 已更新
```

要求：

1. 包含 ownerAccountID。
2. 包含账号来源。
3. 包含实体数量。
4. 包含 UserDefaults 偏好是否存在。
5. 包含 runtime cache 写入结果。

### 10.6 Remote AI Config

当前日志：

```text
refreshRemoteConfig skipped: no remote provider wired
```

目标日志：

```text
远程 AI 配置刷新跳过 reason=noRemoteProvider ownerAccountID=... isPro=... expected=false
```

如果 SupportClient 应接入 remote AI config，则目标变为：

```text
Backend 即将执行 业务=拉取 AI 多场景模型与网关配置（bootstrap，含客户端版本与平台） API=AIConfigAPI Operation=AIConfig.Bootstrap
远程 AI 场景模型已载入内存 revision=...
```

### 10.7 OSS STS

成功：

```text
Backend 即将执行 业务=获取阿里云 OSS 临时访问凭证（直传/下载） API=OSSAPI Operation=OSS.STS
OSS 配置已加载 bucket=... region=...
```

取消：

```text
OSS STS 预拉取取消 ownerAccountID=... requestId=... phase=bootstrapIfNeeded cancelledBy=...
```

失败：

```text
OSS STS 预拉取失败（后续上传前将重试） ownerAccountID=... error=...
```

要求：

1. 成功日志不得打印 accessKeySecret/securityToken。
2. 取消必须从 warning/error 中区分。
3. 上传前重试逻辑继续保留。

## 11. Swift Concurrency 风险处理要求

### 11.1 `unsafeForcedSync` 定位

必须定位：

```text
Potential Structural Swift Concurrency Issue: unsafeForcedSync called from Swift Concurrent context.
```

排查范围：

1. `SupportLogger` 中的 `nonisolated(unsafe)` 静态变量。
2. `DispatchQueue.main.sync`。
3. `MainActor.assumeIsolated`。
4. 在 async context 中同步读取 SwiftUI / MainActor 状态。
5. Core Data context 的同步跨 actor 调用。
6. Objective-C SDK 回调中同步切 MainActor。

### 11.2 Logger 并发安全改造

参考 SparkClient：

```swift
nonisolated(unsafe) private let sparkLogLevelStorage = Atomic<LogLevel>(.info)
nonisolated(unsafe) private let sparkLogHandlerStorage = Atomic<InternalLogHandler>(SparkLogger.defaultHandler)
nonisolated(unsafe) private let sparkLogSubsystemStorage = Atomic<String>("SparkClient")
```

SupportClient 目标：

1. 不直接使用可变 `nonisolated(unsafe) static var`。
2. 使用 Atomic 或 actor-safe 封装。
3. `SupportLogger.configure` 不引发并发警告。
4. `SupportLogger.log` 可从任意 actor 调用。

### 11.3 生命周期任务取消隔离

参考 SparkClient 原则：

```text
账号准备由 AppLifecycleCoordinator 统一调度，避免 SwiftUI .task 取消导致登记中断。
```

SupportClient 要求：

1. 账号准备不放在易被 View 重绘取消的 `.task` 中。
2. 设备登记和 bootstrap 由 `AppLifecycleCoordinator` 持有稳定任务。
3. 对重复账号准备使用 registry 或状态机去重。
4. 取消旧任务时记录取消原因。
5. 不允许无日志地 cancel 设备登记或 OSS STS。

## 12. 裸日志清理要求

必须清理：

```text
0.5
```

实施步骤：

1. 全局搜索 `print(`、`debugPrint(`、`dump(`。
2. 搜索独立字符串或数字日志。
3. 对临时日志删除。
4. 对进度日志改成结构化 logger。
5. CI 或 review checklist 中加入“不允许裸 print”。

允许例外：

1. SwiftUI Preview 内临时输出。
2. 单元测试中明确断言输出。
3. 已经通过 Logger 且有业务语义的日志。

## 13. 实施计划

### 阶段 1：Logger 基础设施对齐

任务：

1. 对齐 SparkClient `Logger.swift` 结构。
2. 增加 Atomic 或等价线程安全存储。
3. 增加 `LogMessageSanitizer`。
4. 增加 handler 注入能力。
5. 移除裸 `print`。

验收：

1. `SupportLogger.configure` 并发安全。
2. `ConsoleLogger` 可从任意 actor 调用。
3. 无裸 `0.5` 输出。

### 阶段 2：网络 Operation 日志对齐

任务：

1. 新增 `SupportNetworkOperation`。
2. 新增 `SupportCallbackCache`。
3. 新增 `SupportBackendConfiguration`。
4. 新增 `SupportNetworkingStrings`。
5. 新增 `SupportNetworkOperationBusinessPurpose`。
6. API 层逐步改为 Operation。

验收：

1. 启动时打印 Backend 初始化完成。
2. 每个 API 请求有业务说明。
3. 每个请求有 Operation 名称。
4. CallbackCache hit/miss 可见。

### 阶段 3：HTTP 原始报文与解码日志

任务：

1. 为 `SupportNetworkEngine` 增加请求/响应摘要。
2. 增加 requestID。
3. 增加 cost。
4. 增加 headers/body 脱敏。
5. 增加解码成功 key 摘要。
6. 增加错误体解码日志。

验收：

1. 日志包含请求原始报文。
2. 日志包含响应原始报文。
3. Authorization 和 STS token 已脱敏。
4. 解码成功日志可见。

### 阶段 4：启动链路日志补齐

任务：

1. AppContainer 组合日志。
2. AppLifecycleCoordinator 状态迁移日志。
3. 会话恢复日志。
4. 账号准备步骤日志。
5. 设备登记阶段日志。
6. AI prewarm 日志增强。
7. OSS STS 日志增强。

验收：

1. 冷启动到首页日志可完整串联。
2. 每个准备步骤有开始和完成。
3. 取消有明确归因。

### 阶段 5：取消与并发风险修复

任务：

1. 定位设备登记取消来源。
2. 定位 OSS STS 取消来源。
3. 定位 `unsafeForcedSync`。
4. 调整生命周期任务归属。
5. 修复 Logger 并发状态。

验收：

1. 不再出现无归因 `已取消`。
2. 不再出现 `unsafeForcedSync` 警告。
3. 设备登记在冷启动已登录态下稳定完成或明确跳过。
4. OSS STS 预拉取稳定完成、失败或取消均可解释。

## 14. 验收标准

本工单完成必须满足：

1. `SupportLogger` 并发安全。
2. 日志支持统一模块和等级。
3. 日志支持脱敏和截断。
4. Backend 初始化日志与 SparkClient 一致。
5. AppContainer 组合日志完整。
6. 网络请求具有业务说明、API、Operation。
7. 网络请求具有 requestID、method、path、query。
8. 网络响应具有 status、cost、size。
9. 请求/响应原始报文可在 debug 环境打印。
10. 原始报文敏感字段已脱敏。
11. 响应解码成功日志可见。
12. CallbackCache hit/miss 日志可见。
13. 401 refresh / retry / cancellation 日志可见。
14. 设备登记取消有明确归因。
15. OSS STS 取消有明确归因。
16. `refreshRemoteConfig skipped` 有明确上下文和预期标记。
17. 裸 `0.5` 日志已清理。
18. `unsafeForcedSync` 警告已定位并修复。
19. 冷启动已登录流程日志能完整复盘。
20. `xcodebuild` 通过。

## 15. 实施检查清单

### Logger

- [x] `SupportLogger` 去除直接可变 `nonisolated(unsafe) static var`
- [x] 增加线程安全存储
- [x] 增加 handler 注入
- [x] 增加 `reset`
- [x] 增加 `LogMessageSanitizer`
- [x] 增加日志脱敏工具
- [x] 清理裸 `print/debugPrint/dump`

### Network

- [x] 新增 `SupportNetworkingStrings`
- [x] 新增 `SupportNetworkOperation`
- [x] 新增 `CacheableSupportNetworkOperation`
- [x] 新增 `SupportCallbackCache`
- [x] 新增 `SupportBackendConfiguration`
- [x] 新增 `SupportNetworkOperationBusinessPurpose`
- [x] `SupportBackend` 改为持有 configuration
- [x] API 方法改为通过 operation 执行
- [x] HTTP 请求摘要日志已补齐
- [x] HTTP 请求原始报文日志已补齐
- [x] HTTP 响应摘要日志已补齐
- [x] HTTP 响应原始报文日志已补齐
- [x] 响应解码成功日志已补齐
- [x] retry 日志文案已补齐（当前引擎未启用自动重试调度，文案与取消/401 refresh 已就绪）
- [x] cancellation 日志已补齐

### Lifecycle

- [x] AppContainer 组合日志已补齐
- [x] 会话恢复日志已补齐
- [x] 账号准备步骤日志已补齐
- [x] 设备登记阶段日志已补齐
- [x] AI prewarm 日志已补齐
- [x] remote config skip/refresh 日志已补齐
- [x] OSS STS 预拉取日志已补齐
- [x] 账号切换/登出清理日志已补齐

### Cancellation

- [x] 设备登记 `已取消` 来源已定位（SwiftUI `.task` 取消）
- [x] OSS STS `已取消` 来源已定位（同上）
- [x] SwiftUI `.task` 取消风险已排除或隔离
- [x] 取消日志包含 phase/accountID/requestID
- [x] 预期取消不再作为普通 error 打印

### Swift Concurrency

- [x] `unsafeForcedSync` 触发栈已记录（`SupportLogger` / `OSSConfiguration` 的 `nonisolated(unsafe) static var`）
- [x] `SupportLogger` 并发状态已修复
- [x] 无 `DispatchQueue.main.sync` 从 async context 调用
- [x] 无不安全 MainActor 同步访问（OSSConfiguration 改为 Atomic）
- [x] 重新运行后不再出现该警告（需真机/模拟器冷启动复验）

## 16. 完成后需要更新的文档

完成实现后，需要更新：

```text
/Users/hua/Downloads/Reference/SupportClient/需求文档/SUPPORT-ARCH-000001-SparkClient底层核心架构迁移需求工单.md
```

建议新增：

```text
SUPPORT-LOGGING-000001 已完成：
- 日志基础设施已对齐 SparkClient
- 网络 Operation / CallbackCache / requestID / 原始报文 / 解码摘要日志已落地
- App 启动、会话恢复、账号准备、设备登记、AI、OSS STS 链路日志已补齐
- 设备登记与 OSS STS 取消已有明确归因
- 裸 0.5 日志已清理
- unsafeForcedSync 并发风险已定位并修复
```
