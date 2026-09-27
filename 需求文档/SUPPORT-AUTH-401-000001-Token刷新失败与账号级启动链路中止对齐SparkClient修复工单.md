# SUPPORT-AUTH-401-000001 Token 刷新失败与账号级启动链路中止对齐 SparkClient 修复工单

## 1. 工单背景

SupportClient 在已登录冷启动链路中出现连续 401：

1. `/api/v1/device/register/` 使用过期 access token 请求，服务端返回 `token_not_valid`。
2. 客户端触发 `/api/v1/auth/token/refresh/`。
3. refresh 接口继续返回 `token_not_valid`。
4. 客户端清理本地认证信息。
5. 但账号级启动链路没有立即中止，后续仍继续跑 AI prewarm、remote AI config、OSS STS prefetch。
6. `/api/v1/oss/sts/credentials/` 再次使用已失效/已清理的认证态触发 401 与 refresh。

本工单要求学习 SparkClient 已有解决方案，将 SupportClient 的 401、token refresh、认证失效通知、设备登记返回值、账号级 bootstrap 中止策略全部对齐。

## 2. 工单编号

```text
SUPPORT-AUTH-401-000001
```

## 3. 问题原始报文

以下报文来自现场日志，按用户提供内容保留关键请求/响应结构。

### 3.1 设备登记请求

```text
method=POST
url=/api/v1/device/register
requestId=3E4AA61D-3D7C-4DD3-86D9-8E61EA6D501C
headers={
  "Authorization": "Bearer ***",
  "Content-Type": "application/json",
  "X-Request-ID": "3E4AA61D-3D7C-4DD3-86D9-8E61EA6D501C"
}
body={
  "app_version": "1.0",
  "build_version": "1",
  "bundle_id": "cn.zhaodk.SupportClient",
  "bundle_identifier": "cn.zhaodk.SupportClient",
  "country_code": "CN",
  "device_id": "FFC6E375-1913-4883-8F43-4EE1B12B3CDE",
  "device_model": "iPhone",
  "device_model_name": "iPhone",
  "device_name": "iPhone",
  "is_simulator": false,
  "language_code": "zh",
  "notifications_enabled": false,
  "platform": "ios",
  "push_token": "***",
  "region_code": "CN",
  "screen_scale": 3,
  "screen_size": "428x926",
  "system_version": "26.5",
  "time_zone": "Asia/Shanghai",
  "user_id": 811
}
```

### 3.2 设备登记响应

```text
method=POST
url=/api/v1/device/register
requestId=3E4AA61D-3D7C-4DD3-86D9-8E61EA6D501C
status=401
cost=0.299s
headers={
  "Allow": "POST, OPTIONS",
  "Content-Type": "application/json",
  "Server": "daphne",
  "X-Request-Id": "3E4AA61D-3D7C-4DD3-86D9-8E61EA6D501C"
}
body={
  "code": 40102,
  "data": {
    "request_id": "3E4AA61D-3D7C-4DD3-86D9-8E61EA6D501C"
  },
  "msg": "token_not_valid"
}
```

### 3.3 Token Refresh 请求

```text
method=POST
url=/api/v1/auth/token/refresh
requestId=79A7C4D8-E783-42EE-8953-D941CCB3CDA0
headers={
  "Content-Type": "application/json",
  "X-Request-ID": "79A7C4D8-E783-42EE-8953-D941CCB3CDA0"
}
body={
  "bundle_id": "cn.zhaodk.SupportClient",
  "device_id": "FFC6E375-1913-4883-8F43-4EE1B12B3CDE",
  "refresh": "***",
  "refresh_token": "***"
}
```

### 3.4 Token Refresh 响应

```text
method=POST
url=/api/v1/auth/token/refresh
requestId=79A7C4D8-E783-42EE-8953-D941CCB3CDA0
status=401
cost=0.091s
headers={
  "Allow": "POST, OPTIONS",
  "Content-Type": "application/json",
  "Server": "daphne",
  "X-Request-Id": "79A7C4D8-E783-42EE-8953-D941CCB3CDA0"
}
body={
  "code": 40102,
  "data": {
    "request_id": "79A7C4D8-E783-42EE-8953-D941CCB3CDA0"
  },
  "msg": "token_not_valid"
}
```

### 3.5 OSS STS 后续请求

```text
method=GET
url=/api/v1/oss/sts/credentials
requestId=7FE95948-57F0-4F0E-B91C-EEC6E3EBEFB0
headers={
  "Authorization": "Bearer ***",
  "X-Request-ID": "7FE95948-57F0-4F0E-B91C-EEC6E3EBEFB0"
}
body=
```

### 3.6 OSS STS 后续响应

```text
method=GET
url=/api/v1/oss/sts/credentials
requestId=7FE95948-57F0-4F0E-B91C-EEC6E3EBEFB0
status=401
cost=0.074s
body={
  "code": -1,
  "data": {
    "request_id": "7FE95948-57F0-4F0E-B91C-EEC6E3EBEFB0"
  },
  "msg": {
    "code": "token_not_valid",
    "detail": "Given token not valid for any token type",
    "messages": [
      {
        "message": "Token is expired",
        "token_class": "***",
        "token_type": "***"
      }
    ]
  }
}
```

## 4. 现象与影响

### 4.1 现象

1. 冷启动恢复本地 session 后，设备登记先失败。
2. refresh token 已被服务端判定无效。
3. 客户端清理本地 token 后，没有立即把会话状态切到 signed out。
4. 账号级 bootstrap 仍继续执行。
5. OSS STS prefetch 再次触发 401 与 refresh。
6. 日志出现重复“刷新令牌失败，已清理本地认证信息”。

### 4.2 用户影响

1. 用户可能短时间看到已登录态，但账号级能力不可用。
2. 设备登记失败后仍继续跑 AI/OSS，产生无意义请求。
3. 后端日志出现重复 401，影响排查。

## 5. 初步根因

### 5.1 AuthTokenProvider 行为过于粗糙

SupportClient 当前文件：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Core/Networking/SupportNetwork.swift
```

当前 `AuthTokenProvider.forceRefreshTokens()` 行为：

1. refresh 非 2xx 直接抛 `SupportNetworkError.refreshFailed`。
2. 没有解析后端错误体。
3. 没有区分“明确鉴权失效”和“临时不可用”。
4. 没有像 SparkClient 一样在明确鉴权失效时统一发 `AuthSessionInvalidation`。
5. 没有保存 access token 过期时间，无法在请求前主动刷新。

### 5.2 NetworkEngine 只发了弱通知

SupportClient 当前：

```swift
NotificationCenter.default.post(name: .supportAuthInvalidated, object: nil)
```

问题：

1. 通知没有携带 statusCode/backendCode/message/source。
2. App 层没有像 SparkClient `RouteCoordinator` 一样集中接管。
3. 设备登记链路无法根据通知结果返回 `.authSessionInvalidated`。

### 5.3 DeviceRegistrationCoordinator 没有返回明确结果

SupportClient 当前：

```swift
func registerSignedInDevice(session: UserSession, reason: DeviceRegistrationReason) async
```

问题：

1. 返回 `Void`，调用方不知道成功、可重试失败、还是鉴权失效。
2. 捕获 error 后只打日志，不把错误传回 `AppLifecycleCoordinator`。
3. `AppLifecycleCoordinator` 因此继续执行 `appBootstrapper.bootstrapAccountIfNeeded`。

### 5.4 AppLifecycleCoordinator 缺少中止保护

SupportClient 当前账号级准备顺序：

1. activate user runtime。
2. signedIn device registration。
3. bootstrapIfNeeded。

问题：

1. 设备登记失败后仍继续 bootstrap。
2. 认证失效后没有检查 `sessionStore.state` 是否已经 signed out。
3. 没有 SparkClient 的 `registrationOutcome.allowsAccountBootstrap` 保护。
4. 没有 `rollbackPreparingIfNeeded`，失败后可能把准备状态卡住。

## 6. SparkClient 参考方案

### 6.1 参考文件

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Networking/AuthTokenProvider.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Networking/SparkNetworkEngine.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Networking/SparkNetworkModels.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Sources/App/Architecture/RouteCoordinator.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Sources/App/Architecture/AppLifecycleCoordinator.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Device/Application/DeviceRegistrationCoordinator.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Device/Application/DeviceRegistrationRequestOutcome.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Tests/Networking/SparkNetworkEngineTests.swift
```

### 6.2 SparkClient AuthTokenProvider 关键点

SparkClient 已实现：

1. `refreshTokensDeDuplicated()`：并发 refresh 去重。
2. `performRefresh()`：refresh 失败时解析后端错误。
3. `isDefinitiveRefreshAuthFailure(_:)`：只在明确鉴权失效时清理 token。
4. `AuthSessionInvalidation.postIfNeeded(...)`：发出带上下文的认证失效通知。
5. `AuthTokenProviderError.refreshTemporarilyUnavailable`：临时失败不清理本地 token。
6. 保存 access token `expiresAt`，请求前可主动判断是否需要刷新。

### 6.3 SparkClient NetworkEngine 关键点

SparkClient 已实现：

1. 请求收到 401 后，调用 `authProvider.forceRefreshTokens()`。
2. refresh 失败后解析原始 401 的后端错误体。
3. 调用 `postAuthInvalidationIfNeeded(...)`。
4. 抛出 `SparkNetworkError.refreshFailed(backendError, error)`。
5. 不把所有非 2xx 都等同于最终登出；区分后端明确鉴权失败与临时失败。

### 6.4 SparkClient AuthSessionInvalidation 关键点

SparkClient 定义：

```swift
enum AuthSessionInvalidation {
    static let notificationName = Notification.Name("Spark.Auth.SessionInvalidatedByServer")

    static func shouldInvalidate(statusCode: Int, backendCode: Int?, message: String) -> Bool
    static func postIfNeeded(statusCode: Int, backendCode: Int?, message: String, source: String)
}
```

支持识别：

1. `token_not_valid`
2. `device_session_revoked`
3. `device_session_replaced`
4. `device_session_not_found`
5. `device_mismatch`
6. `authentication_failed`
7. `not_authenticated`
8. `invalid_token`
9. `token_expired`
10. `given token not valid`

### 6.5 SparkClient 生命周期关键点

SparkClient 在 `AppLifecycleCoordinator.runSignedInPreparation` 中：

1. 设备登记返回 `DeviceRegistrationRequestOutcome`。
2. `.authSessionInvalidated` 时中止账号级引导。
3. `.failedRetryable` 且重试用尽时中止账号级引导。
4. 只有 `.submitted` 或 `.skippedSameLaunchSubmission` 才允许继续 bootstrap。
5. 设备登记后再次检查 `sessionStore.state` 与 `isHandlingServerAuthInvalidation`。
6. bootstrap 后再次检查鉴权状态。

## 7. 修复目标

本工单要求 SupportClient 完全对齐 SparkClient 方案。

目标：

1. refresh 失败时解析后端原始错误体。
2. 明确鉴权失效时清理本地 token，并发送结构化认证失效通知。
3. 临时 refresh 失败时不误清 token。
4. 设备登记返回明确 outcome。
5. 账号级 bootstrap 在设备登记鉴权失效后立即中止。
6. 认证失效后统一回到 signed out/login。
7. 后续 AI/OSS/Home/Task 等账号级任务不得继续请求。
8. 增加测试覆盖 SparkClient 已有场景。

## 8. 详细修复要求

### 8.1 新增 SupportAuthSessionInvalidation

新增或迁移：

```swift
enum SupportAuthSessionInvalidation {
    static let notificationName = Notification.Name("Support.Auth.SessionInvalidatedByServer")

    static func shouldInvalidate(statusCode: Int, backendCode: Int?, message: String) -> Bool
    static func postIfNeeded(statusCode: Int, backendCode: Int?, message: String, source: String)
}
```

要求：

1. 逻辑与 SparkClient `AuthSessionInvalidation` 一致。
2. 通知 userInfo 必须包含：
   - `statusCode`
   - `backendCode`
   - `message`
   - `source`
3. 保留现有 `.supportAuthInvalidated` 时，需要统一桥接到新通知，不允许两个通知各走各的。
4. App 层只监听统一的新通知。

### 8.2 AuthTokenProvider 对齐 SparkClient

SupportClient 当前 `AuthTokenProvider` 必须改造：

1. 新增 access token 过期时间存储。
2. 如果 login/refresh 响应无法直接给 `expiresAt`，从 JWT claims 解析 `exp`。
3. 增加 `shouldRefresh(tokens:)`，请求前提前刷新。
4. `forceRefreshTokens()` 内部保持并发去重。
5. refresh 非 2xx 时解析 `BackendError`。
6. 仅当 `BackendError` 明确为鉴权失效时：
   - 清理 token。
   - 发 `SupportAuthSessionInvalidation.postIfNeeded(...)`。
   - 抛出明确 refresh failed error。
7. 如果响应无法解析、网关异常、网络临时失败：
   - 不清理 token。
   - 抛出临时失败错误。
8. 保留 refresh payload：

```json
{
  "refresh": "...",
  "refresh_token": "...",
  "device_id": "...",
  "bundle_id": "..."
}
```

### 8.3 SupportNetworkEngine 对齐 SparkClient

`SupportNetworkEngine.sendRaw` 必须调整：

1. 401 时调用 `tokenProvider.forceRefreshTokens()`。
2. refresh 成功后重建原请求并重试一次。
3. refresh 失败时解析原始 401 的 response body。
4. 调用 `SupportAuthSessionInvalidation.postIfNeeded(...)`。
5. 抛出能携带 backendError 与 refreshError 的错误类型。
6. 防止 refresh 接口自身再次进入刷新流程。
7. 对同一请求避免无限 refresh retry。

### 8.4 DeviceRegistrationCoordinator 返回 outcome

迁移 SparkClient：

```text
DeviceRegistrationRequestOutcome
DeviceRegistrationBootstrapRetryPolicy
```

SupportClient 需要将：

```swift
func registerSignedInDevice(session: UserSession, reason: DeviceRegistrationReason) async
```

改为：

```swift
func requestRegisterWithLimitedRetry(
    reason: DeviceRegistrationReason,
    accountID: Int64?
) async -> DeviceRegistrationRequestOutcome
```

或至少提供同等能力。

要求：

1. 设备登记成功返回 `.submitted`。
2. 同启动周期重复提交返回 `.skippedSameLaunchSubmission`。
3. 网络临时失败返回 `.failedRetryable`。
4. 鉴权失效返回 `.authSessionInvalidated`。
5. 启动级原因最多重试 3 次。
6. 401/token_not_valid/device_session_* 不应继续重试业务登记，应立即返回 `.authSessionInvalidated`。

### 8.5 AppLifecycleCoordinator 中止账号级 bootstrap

SupportClient `AppLifecycleCoordinator.runSignedInPreparation` 必须改为 SparkClient 逻辑：

1. 先执行账号 runtime activate。
2. 执行 signed-in device registration。
3. 判断 registration outcome。
4. 如果 `.authSessionInvalidated`：
   - 打日志。
   - rollback preparing。
   - return。
5. 如果 `.failedRetryable`：
   - 打日志。
   - rollback preparing。
   - return。
6. 只有允许 bootstrap 时继续 AI/OSS 预热。
7. 设备登记后检查 `sessionStore.state` 是否仍 signedIn。
8. bootstrap 后再次检查 `sessionStore.state`。
9. 认证失效后不能继续 OSS STS prefetch。

### 8.6 RouteCoordinator 或等价 App 层处理

SupportClient 当前没有完整对齐 SparkClient `RouteCoordinator` 认证失效处理。

必须实现：

1. App 层监听 `SupportAuthSessionInvalidation.notificationName`。
2. 收到通知后只处理一次，避免多次 401 重复登出。
3. 调用 sessionStore 清理本地会话。
4. 清理账号运行时缓存。
5. 清理 OSS runtime credentials。
6. 清理设备登记已登录状态。
7. 跳回登录页。
8. 在处理期间设置 `isHandlingServerAuthInvalidation` 或等价状态，阻止前台同步/账号 bootstrap 继续跑。

## 9. 验收场景

### 9.1 refresh token 明确失效

前置：

1. 本地存在 signedIn session。
2. access token 已过期。
3. refresh token 服务端返回：

```json
{"code":40102,"msg":"token_not_valid","data":{"request_id":"test"}}
```

期望：

1. 设备登记收到 401。
2. refresh 被调用一次。
3. refresh 返回 401 后清理 token。
4. 发出 `SupportAuthSessionInvalidation`。
5. App 切到 signedOut。
6. 账号级 bootstrap 中止。
7. 不再请求 OSS STS。

### 9.2 refresh 接口临时 500

前置：

1. access token 已过期。
2. refresh 接口返回 500 或无法解析 HTML。

期望：

1. 不清理本地 token。
2. 不发认证失效通知。
3. 当前请求失败为临时错误。
4. 用户仍保持本地登录态，后续可重试。

### 9.3 并发 401

前置：

1. 设备登记和 OSS STS 并发或近似并发触发 401。

期望：

1. refresh 只发起一次。
2. 其他请求等待同一个 refresh task。
3. 若 refresh 明确失败，只发一次认证失效处理。
4. 后续账号级任务中止。

### 9.4 设备登记失败但非鉴权

前置：

1. 设备登记网络超时或 5xx。

期望：

1. 按 SparkClient 策略有限重试。
2. 重试用尽后返回 `.failedRetryable`。
3. 账号级 bootstrap 中止，避免未登记设备继续进入账号级引导。
4. 不强制登出。

## 10. 测试要求

必须补齐单元测试或集成测试：

1. `testRefresh401PostsAuthInvalidationNotification`
2. `testConcurrent401TriggersSingleRefresh`
3. `testRefreshTemporaryFailureDoesNotClearTokens`
4. `testDeviceRegistrationAuthInvalidatedStopsBootstrap`
5. `testDeviceRegistrationRetryableFailureStopsBootstrapWithoutLogout`

参考 SparkClient：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Tests/Networking/SparkNetworkEngineTests.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Tests/Networking/AuthSessionInvalidationTests.swift
```

## 11. 实施步骤

1. 复制并适配 SparkClient `AuthSessionInvalidation`。
2. 补齐 SupportClient token model 的 `expiresAt`。
3. 复制并适配 SparkClient refresh error parsing。
4. 修改 `SupportNetworkEngine.sendRaw`。
5. 改造 `DeviceRegistrationCoordinator` 返回 outcome。
6. 改造 `AppLifecycleCoordinator.runSignedInPreparation` 中止逻辑。
7. 增加 App 层认证失效监听与处理。
8. 增加测试。
9. 执行 `xcodebuild`。

## 12. 风险与注意事项

### 12.1 不要把所有 401 都简单等同于登出

SparkClient 的经验是：refresh 失败后需要看后端错误体。明确鉴权失效才清理；临时错误保留本地 token。

### 12.2 不要在设备登记失败后继续 bootstrap

设备登记是账号级启动门槛之一。设备登记鉴权失败或重试用尽时，后续 AI/OSS/Home/Task 不应继续执行。

### 12.3 注意 refresh 请求路径

现场报文显示：

```text
url=/api/v1/auth/token/refresh
```

而代码请求 path 可能是：

```text
/api/v1/auth/token/refresh/
```

真实请求必须保留 trailing slash，避免 Django `APPEND_SLASH` 触发 301/方法变更风险。SparkClient 已在 `AuthTokenProvider.url(for:)` 中专门处理这个问题。

## 13. 验收标准

本工单完成必须满足：

1. [x] refresh 401 `token_not_valid` 会发统一认证失效通知。
2. [x] refresh 401 后 App 回到 signedOut/login。
3. [x] refresh 401 后设备登记返回 `.authSessionInvalidated`。
4. [x] refresh 401 后账号级 bootstrap 中止。
5. [x] refresh 401 后不会继续请求 OSS STS。
6. [x] refresh 临时失败不清理本地 token。
7. [x] 并发 401 只触发一次 refresh。
8. [x] 新增测试全部通过。
9. [x] `xcodebuild` 通过。

## 14. 完成后需要更新的文档

完成实现后，需要更新：

```text
/Users/hua/Downloads/Reference/SupportClient/需求文档/SUPPORT-ARCH-000001-SparkClient底层核心架构迁移需求工单.md
```

建议新增：

```text
SUPPORT-AUTH-401-000001 已完成：
- Token refresh 失败判定已对齐 SparkClient
- 明确鉴权失效会发统一认证失效通知并回到登录态
- 设备登记返回 outcome，鉴权失效/重试失败会中止账号级 bootstrap
- refresh 401 后不再继续请求 OSS STS
```
