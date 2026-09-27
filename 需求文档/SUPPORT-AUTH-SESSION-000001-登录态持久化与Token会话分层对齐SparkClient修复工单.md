# SUPPORT-AUTH-SESSION-000001 登录态持久化与 Token / Session 分层对齐 SparkClient 修复工单

## 1. 工单背景

SupportClient 当前存在“登录后一段时间自动失效”的问题，而 SparkClient 可以长期保持登录态。

经过对比，关键差异不在登录页面，而在认证状态持久化架构：

1. SupportClient 当前 `UserSession` 同时保存账号资料和 access/refresh token。
2. SupportClient 冷启动恢复时，会从 `SessionSnapshotStore` 读取 `UserSession`，再把快照里的 token 写回 `AuthTokenProvider` / Keychain。
3. 如果运行期间 token refresh 成功，Keychain 中 token 已更新，但 `UserSession` 快照里的 token 没有同步更新。
4. 下次冷启动时，SupportClient 会用快照中的旧 token 覆盖 Keychain 中的新 token。
5. 旧 refresh token 再次用于 refresh 时，服务端返回 `token_not_valid`，App 被迫回到未登录态。

SparkClient 的方案不同：

1. `UserSession` 只保存账号资料，不保存 access token / refresh token。
2. token 只由 `AuthTokenProvider` 持有，并独立存储在 Keychain。
3. 冷启动恢复时，先从 `SessionSnapshotStore` 读取账号快照。
4. 再通过 `AuthTokenProvider.authorizationHeaderValue()` 触发 access token 有效性检查和必要 refresh。
5. token 有效后，再请求服务端当前 session，合并最新账号资料。
6. session 快照永远不会覆盖 Keychain token。

本工单要求 SupportClient 完整对齐 SparkClient 的认证持久化架构，解决登录态一段时间后自动失效的问题。

## 2. 工单编号

```text
SUPPORT-AUTH-SESSION-000001
```

## 3. 问题结论

### 3.1 SupportClient 当前问题代码

SupportClient 的 `UserSession` 当前包含 token：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Core/Networking/SupportAPIs.swift
```

当前结构：

```swift
struct UserSession: Codable, Equatable, Sendable {
    let accountID: Int64
    let userID: Int64
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let isPro: Bool
    let displayName: String?
    let email: String?
    let signInMethod: String?
    let signedInAt: Date?
}
```

SupportClient 冷启动恢复当前会把快照 token 写回 tokenProvider：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App/AppSessionStore.swift
```

当前逻辑：

```swift
if let session = await snapshotStore.load() {
    await tokenProvider.setTokens(session.authTokens)
    state = .signedIn(session)
}
```

并且：

```swift
extension UserSession {
    var authTokens: AuthTokens {
        AuthTokens(accessToken: accessToken, refreshToken: refreshToken, tokenType: tokenType)
    }
}
```

这会导致一个严重问题：

```text
refresh 成功后的新 token 在 Keychain
旧 token 仍留在 UserDefaults session snapshot
下次冷启动 snapshot 覆盖 Keychain
旧 refresh token 被再次使用
服务端返回 token_not_valid
```

### 3.2 SparkClient 正确结构

SparkClient 的 `UserSession` 不保存 token：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Domain/Entities/UserSession.swift
```

SparkClient 结构：

```swift
struct UserSession: Codable, Equatable, Sendable {
    let accountID: Int64
    let email: String
    let displayName: String
    let signedInAt: Date
    let signInMethod: SignInMethod
    let isPro: Bool
    let isNewUser: Bool
}
```

SparkClient 冷启动恢复不是直接信任本地快照，而是走：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/Auth/Infrastructure/DefaultAuthRepository.swift
```

关键流程：

```swift
_ = try await backend.tokenProvider().authorizationHeaderValue()
let remote = try await backend.auth.fetchCurrentSession()
let latestSession = mergeCurrentSession(remote, into: cachedSession)
try await snapshotStore.save(latestSession)
return latestSession
```

## 4. 目标

本工单目标：

1. SupportClient `UserSession` 与 SparkClient 一样，只保存账号资料，不保存 token。
2. access token / refresh token / tokenType / expiresAt 只归 `AuthTokenProvider` 管理。
3. `SessionSnapshotStore` 不再保存 token。
4. 冷启动恢复不再用 snapshot token 覆盖 Keychain。
5. 冷启动恢复必须先验证/刷新 token，再拉取服务端当前 session。
6. token refresh 成功后，只更新 Keychain，不需要同步写 `UserSession`。
7. 旧版本已保存的含 token 快照需要兼容迁移，不能让用户大面积掉登录。
8. 与 `SUPPORT-AUTH-401-000001` 的鉴权失效处理保持一致。

## 5. 非目标

本工单不处理：

1. 不修改登录页面 UI。
2. 不修改日志脱敏策略。
3. 不修改 OSS / OCR。
4. 不修改 AI Core Data 持久化。
5. 不改变服务端 token 策略。
6. 不把 refresh token 写入 UserDefaults。

## 6. 参考文件

### 6.1 SupportClient 当前相关文件

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Core/Networking/SupportAPIs.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Core/Networking/SupportNetwork.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App/AppSessionStore.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App/AuthFeature.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App/AppContainer.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App/AppLifecycleCoordinator.swift
```

### 6.2 SparkClient 参考文件

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Domain/Entities/UserSession.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Networking/AuthTokenProvider.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Networking/API/Auth/AuthAPI.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/Auth/Infrastructure/DefaultAuthRepository.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Features/Auth/Infrastructure/SessionSnapshotStore.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Sources/App/AppSessionStore.swift
```

## 7. 目标架构

### 7.1 Token 存储职责

`AuthTokenProvider` 负责：

1. 保存 access token。
2. 保存 refresh token。
3. 保存 tokenType。
4. 保存 access token expiresAt。
5. 请求前判断 access token 是否即将过期。
6. 自动 refresh。
7. refresh 并发去重。
8. refresh 明确失败时清理 Keychain 并触发认证失效。

### 7.2 Session 快照职责

`SessionSnapshotStore` 只负责保存：

1. `accountID`
2. `userID`
3. `isPro`
4. `displayName`
5. `email`
6. `signInMethod`
7. `signedInAt`
8. `isNewUser`，如 SupportClient 后端有该字段

禁止保存：

1. `accessToken`
2. `refreshToken`
3. `tokenType`
4. `expiresAt`

### 7.3 AppSessionStore 职责

`AppSessionStore` 只负责：

1. 保存 UI 层会话状态。
2. 调用认证仓储恢复 session。
3. 设置 `.signedIn(UserSession)` 或 `.signedOut`。
4. 登录成功后切换 signedIn。
5. 登出后切换 signedOut。

`AppSessionStore` 不应该：

1. 直接从 `UserSession` 提取 token。
2. 在冷启动时调用 `tokenProvider.setTokens(session.authTokens)`。
3. 自己决定 token 是否有效。

## 8. 详细修复要求

### 8.1 拆分 UserSession 与 Token

SupportClient `UserSession` 必须移除：

```swift
let accessToken: String
let refreshToken: String
let tokenType: String
```

目标结构建议：

```swift
struct UserSession: Codable, Equatable, Sendable {
    let accountID: Int64
    let userID: Int64
    let isPro: Bool
    let displayName: String?
    let email: String?
    let signInMethod: String?
    let signedInAt: Date?
}
```

要求：

1. 结构尽量对齐 SparkClient。
2. SupportClient 可保留 `userID`，因为当前接口和设备登记使用。
3. 不再提供 `session.authTokens`。
4. 不再允许从 session 快照恢复 token。

### 8.2 新增登录响应 DTO

因为 `UserSession` 不再保存 token，SupportClient 需要新增登录响应 DTO。

建议：

```swift
struct AuthenticatedUserContext: Decodable, Sendable {
    let userID: Int64
    let accountID: Int64
    let email: String?
    let displayName: String?
    let isPro: Bool
    let isNewUser: Bool?
    let tokens: AuthTokens
}
```

或拆分成：

```swift
struct LoginResult: Decodable {
    let userID: Int64
    let accountID: Int64?
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int?
    let tokenType: String
    let email: String?
    let displayName: String?
    let isPro: Bool?
}
```

要求：

1. 登录 API 解码时必须拿到 token。
2. 登录 API 成功后立即 `tokenProvider.setTokens(tokens)`。
3. `UserSession` 只由账号资料构造。
4. `SessionSnapshotStore.save(session)` 保存不含 token 的 session。
5. `expiresIn` 优先用于计算 `expiresAt`。
6. 如果没有 `expiresIn`，从 access JWT 的 `exp` 解析 `expiresAt`。

### 8.3 登录流程对齐 SparkClient

SparkClient 登录流程：

1. 调用登录接口。
2. 解码登录响应。
3. 构造 `AuthTokens`。
4. `backend.tokenProvider().setTokens(tokens)`。
5. 构造不含 token 的 `UserSession`。
6. 保存 `SessionSnapshotStore`。
7. `AppSessionStore` 切换 `.signedIn(session)`。

SupportClient 必须对齐。

涉及方法：

```text
SupportAuthAPI.appleLogin
SupportAuthAPI.passwordLogin
SupportOTPAPI.verifyPhoneOTP
DefaultAuthRepository.signInWithApple
DefaultAuthRepository.signInWithPassword
DefaultAuthRepository.verifyPhoneOTP
AppSessionStore.signIn
```

要求：

1. `SupportAuthAPI` 不再直接返回含 token 的 `UserSession`。
2. 认证仓储负责把登录响应拆成 `AuthTokens + UserSession`。
3. `AppSessionStore.signIn(_:)` 不再接触 token。

### 8.4 冷启动恢复流程对齐 SparkClient

新增 `RestoreSessionUseCase` 或在 `DefaultAuthRepository` 中实现：

```swift
func restoreSession() async -> UserSession?
```

流程必须对齐 SparkClient：

1. 从 `SessionSnapshotStore` 读取 cached session。
2. 如果没有 cached session：
   - 不直接判定 Keychain。
   - 可打诊断日志：如果 Keychain 有 token 但无 session，说明状态分裂。
   - 返回 nil。
3. 如果有 cached session：
   - 调用 `backend.tokenProvider().authorizationHeaderValue()`。
   - 该调用会主动 refresh 即将过期的 access token。
4. 如果 refresh 临时失败：
   - 保留 cached session。
   - 不清 token。
   - 返回 cached session。
5. 如果 refresh 明确失败：
   - 清理 token。
   - 清理 session snapshot。
   - 发认证失效通知。
   - 返回 nil。
6. token 有效后，请求：

```text
GET /api/v1/auth/session/
```

7. 将服务端最新 session 与 cached session 合并。
8. 保存最新 session snapshot。
9. 返回 latest session。

### 8.5 AppSessionStore 改造

SupportClient 当前 `AppSessionStore` 直接依赖 `SessionSnapshotStore + AuthTokenProvider`。

目标对齐 SparkClient：

```swift
final class AppSessionStore: ObservableObject {
    private let restoreSessionUseCase: RestoreSessionUseCase
}
```

最小改造也必须满足：

1. `restoreIfNeeded()` 不再 `tokenProvider.setTokens(session.authTokens)`。
2. `restoreIfNeeded()` 走 `restoreSession()`。
3. `signIn(_:)` 只保存 session snapshot 并切换 state。
4. `signOut()` 清理 snapshot 和 token。
5. 诊断：恢复后检查内存 session 与 snapshot 是否一致。

### 8.6 旧快照兼容迁移

SupportClient 用户本地可能已经保存了含 token 的 `support.session.snapshot.v1`。

必须兼容：

1. 新版 `UserSession` 解码旧快照时忽略 token 字段。
2. 首次启动时，如果旧快照中含 token，而 Keychain 中缺 token，可以临时迁移 token 到 Keychain 一次。
3. 如果 Keychain 已有 token，则不得用旧快照 token 覆盖 Keychain。
4. 迁移完成后重写 session snapshot，移除 token 字段。
5. 新 snapshot 版本建议升级为：

```text
support.session.snapshot.v2
```

或继续使用 v1 但写入无 token 数据。推荐 v2，便于清理和回滚。

旧快照迁移伪代码：

```swift
if let legacy = loadLegacySnapshotWithTokens() {
    if tokenProvider.currentTokens() == nil, legacy.hasTokens {
        await tokenProvider.setTokens(legacy.authTokens)
    }
    let sanitized = legacy.toUserSessionWithoutTokens()
    saveV2(sanitized)
    clearV1()
}
```

### 8.7 Current Session 合并规则

`SupportAuthAPI.currentSession()` 返回的字段可能与登录返回不完全一致。

合并规则：

1. `accountID` 以服务端最新为准，缺失时用 cached。
2. `userID` 以服务端最新为准，缺失时用 cached。
3. `isPro` 以服务端最新为准。
4. `displayName` 服务端为空时保留 cached。
5. `email` 服务端为空时保留 cached。
6. `signInMethod` 服务端为空时保留 cached。
7. `signedInAt` 使用 cached。
8. 不从 current session 响应中读取 token，除非后端明确返回并且该接口被定义为刷新 token 接口。

### 8.8 认证失效联动

本工单必须与 `SUPPORT-AUTH-401-000001` 保持一致：

1. refresh 明确失败时，走 `SupportAuthSessionInvalidation`。
2. App 层收到后回到 signedOut。
3. 清理 session snapshot。
4. 清理 Keychain token。
5. 清理设备登记已登录状态。
6. 中止账号级 bootstrap。

## 9. 需要关注的隐藏问题

### 9.1 Refresh Token Rotation

如果服务端启用了 refresh token rotation，refresh 成功会返回新的 refresh token。

SupportClient 当前如果把旧 refresh token 存在 session snapshot，会在下次冷启动把旧 refresh token 写回 Keychain。

修复后：

1. 新 refresh token 只写 Keychain。
2. session snapshot 不保存 refresh token。
3. 冷启动不会回滚 token。

### 9.2 UserDefaults 与 Keychain 状态分裂

可能出现：

1. 有 session snapshot，无 Keychain token。
2. 无 session snapshot，有 Keychain token。
3. session accountID 与 token subject 不一致。
4. Keychain token 是新 token，但 snapshot 中旧 token 覆盖它。

修复要求：

1. 有 session 无 token：恢复失败，清 session 或返回 signedOut。
2. 无 session 有 token：打诊断日志，不进入 signedIn。
3. accountID 不一致：清理并回登录态。
4. 任何情况下 snapshot 不再覆盖 Keychain。

### 9.3 多登录方式一致

以下登录方式都必须对齐：

1. Apple 登录。
2. 密码登录。
3. 手机号 OTP 登录。
4. 后续新增第三方登录。

不得出现某个登录方式仍返回含 token `UserSession`。

### 9.4 设备登记时序

冷启动恢复后设备登记依赖有效 access token。

修复后顺序必须是：

1. restore session。
2. tokenProvider 验证/刷新 token。
3. current session 成功或临时失败兜底。
4. App 进入 signedIn。
5. `AppLifecycleCoordinator` 触发 signed-in device registration。

不能：

1. 先进入 signedIn。
2. 再发现 token 无效。
3. 再连续触发 device register / OSS STS 401。

### 9.5 Pro / trial / AI 初始化

SupportClient 的 AI、OSS、设备登记都依赖 session。

修复后：

1. `isPro` 需要从 current session 刷新。
2. AI prewarm 使用最新 `accountID`。
3. remote AI config 依赖最新 `isPro`。
4. OSS STS prefetch 只在 token 有效后执行。

## 10. 测试要求

必须新增或补齐测试：

### 10.1 快照不覆盖 Keychain

场景：

1. Keychain 中是新 token R2。
2. 旧 v1 snapshot 中是旧 token R1。
3. 执行 restore。

期望：

1. Keychain 仍是 R2。
2. snapshot 被迁移为无 token v2。
3. 不使用 R1 发 refresh。

### 10.2 refresh rotation 后冷启动

场景：

1. 登录获得 refresh R1。
2. access 过期。
3. refresh 成功返回 refresh R2。
4. 退出 App。
5. 冷启动恢复。

期望：

1. 使用 R2。
2. 不再使用 R1。
3. 不出现 `token_not_valid`。

### 10.3 缺 Keychain token

场景：

1. session snapshot 存在。
2. Keychain token 不存在。

期望：

1. restore 返回 nil 或 signedOut。
2. 不进入 signedIn。
3. 不触发 signed-in device registration。

### 10.4 refresh 临时失败

场景：

1. session snapshot 存在。
2. token 即将过期。
3. refresh 接口 500。

期望：

1. 保留 cached session。
2. 不清 Keychain。
3. 不清 snapshot。
4. 后续可重试。

### 10.5 refresh 明确失败

场景：

1. session snapshot 存在。
2. refresh 返回 `token_not_valid`。

期望：

1. 清 Keychain。
2. 清 session snapshot。
3. 发 `SupportAuthSessionInvalidation`。
4. 返回 signedOut。
5. 不继续账号级 bootstrap。

### 10.6 登录响应拆分

场景：

1. password / Apple / OTP 登录成功。

期望：

1. token 写入 Keychain。
2. session snapshot 不包含 token。
3. state 进入 signedIn。
4. 冷启动后可恢复。

## 11. 实施步骤

1. 新增不含 token 的 `UserSession` 结构。
2. 新增登录响应 DTO，将 token 与 session 资料拆开。
3. 改造 `SupportAuthAPI.appleLogin/passwordLogin/currentSession`。
4. 改造 OTP 登录响应解析。
5. 改造 `DefaultAuthRepository`，对齐 SparkClient：
   - 登录时写 tokenProvider。
   - 登录时保存无 token session。
   - restore 时先验证 token，再 currentSession。
6. 改造 `AppSessionStore`：
   - 移除 tokenProvider.setTokens(session.authTokens)。
   - 通过 restore use case 恢复。
7. 改造 `SessionSnapshotStore`：
   - v2 快照。
   - 兼容旧 v1。
   - 迁移后清理 v1。
8. 删除 `UserSession.authTokens` 扩展。
9. 增加诊断日志：snapshot/token 分裂时明确输出。
10. 增加测试。
11. 执行 `xcodebuild`。

## 12. 验收标准

本工单完成必须满足：

1. `UserSession` 不再包含 access token / refresh token / tokenType。
2. `SessionSnapshotStore` 不再保存 token。
3. 冷启动不会从 session snapshot 写 token 到 Keychain。
4. token refresh 成功后的新 refresh token 不会被旧快照覆盖。
5. 冷启动恢复会先验证/刷新 token。
6. token 有效后会拉取 current session。
7. refresh 临时失败时保留本地登录态。
8. refresh 明确失败时清理 token 与 session。
9. 有 session 无 token 不进入 signedIn。
10. 无 session 有 token 不进入 signedIn，并输出诊断日志。
11. Apple / 密码 / OTP 登录都写入 Keychain token，并保存无 token session。
12. 设备登记只在 token 有效的 signedIn 状态后执行。
13. OSS STS prefetch 不会在无效 token 状态下执行。
14. 新增测试全部通过。
15. `xcodebuild` 通过。

## 13. 与其他工单关系

### 13.1 与 SUPPORT-AUTH-401-000001

`SUPPORT-AUTH-401-000001` 处理 refresh 失败后的认证失效通知和 bootstrap 中止。

本工单处理更底层的持久化问题：

```text
旧 session snapshot 不应覆盖新 Keychain token
```

两者必须同时成立。

### 13.2 与 SUPPORT-LOGGING-000001

本工单不处理日志脱敏。

### 13.3 与 SUPPORT-OSS-OCR-000001

OSS STS prefetch 依赖有效登录态。本工单完成后，OSS STS 只应在 session restore 确认可用后执行。

## 14. 完成后需要更新的文档

完成实现后，需要更新：

```text
/Users/hua/Downloads/Reference/SupportClient/需求文档/SUPPORT-ARCH-000001-SparkClient底层核心架构迁移需求工单.md
```

建议新增：

```text
SUPPORT-AUTH-SESSION-000001 已完成：
- UserSession 已移除 access/refresh token，SessionSnapshotStore 只保存账号资料
- AuthTokenProvider 独立持有 Keychain token 与 expiresAt
- 冷启动恢复先验证/刷新 token，再拉取 current session
- 旧含 token 快照已兼容迁移，且不会覆盖 Keychain 新 token
- 登录态长期保持逻辑已对齐 SparkClient
```
