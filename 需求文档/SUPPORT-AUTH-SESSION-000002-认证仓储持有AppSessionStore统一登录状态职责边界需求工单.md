# SUPPORT-AUTH-SESSION-000002 认证仓储持有 AppSessionStore 统一登录状态职责边界需求工单

## 1. 工单背景

当前 `SupportClient` 的认证实现已经把 token 与 session 快照做了分层，但登录成功后的“内存 UI 登录态切换”职责仍然分散：

```text
DefaultAuthRepository
├─ 调用后端登录接口
├─ 保存 token
├─ 构造 UserSession
└─ 保存 SessionSnapshotStore

LoginViewModel
└─ 调用 sessionStore.setAuthenticated(session)
```

也就是说，仓储负责持久化，ViewModel 负责切换 UI 登录态。

用户期望的效果是：登录、验证码登录、Apple 登录、登出等认证行为的效果保持一致。要做到这一点，需要统一职责边界：让 `DefaultAuthRepository` 持有 `AppSessionStore`，并在登录/退出时直接修改内存登录态。

目标职责边界：

```text
DefaultAuthRepository
├─ 调用后端登录接口
├─ 保存 token
├─ 构造 UserSession
├─ 保存 SessionSnapshotStore
└─ 调用 AppSessionStore 设置 signedIn / signedOut

LoginViewModel
└─ 只负责 UI 事件、loading、错误提示、成功提示
```

## 2. 工单编号

```text
SUPPORT-AUTH-SESSION-000002
```

## 3. 当前代码现状

### 3.1 当前仓储位置

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App/AuthFeature.swift:26-360
```

当前 `DefaultAuthRepository`：

```swift
struct DefaultAuthRepository: AuthRepository {
    let backend: SupportBackend
    let snapshotStore: SessionSnapshotStore
    private let logger: Logger
}
```

当前登录后只保存快照：

```swift
await snapshotStore.save(session)
return session
```

### 3.2 当前 UI 状态切换位置

当前 `LoginViewModel` 在登录成功后切换内存状态：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App/AuthFeature.swift:398-400
```

```swift
let session = try await repository.signInWithApple(payload: payload)
sessionStore.setAuthenticated(session)
```

手机号 OTP 登录同理：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App/AuthFeature.swift:428-430
```

```swift
let session = try await repository.verifyPhoneOTP(...)
sessionStore.setAuthenticated(session)
```

### 3.3 当前装配位置

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App/AppContainer.swift:142-155
```

当前装配顺序：

```swift
let snapshotStore = SessionSnapshotStore(tokenProvider: tokenProvider, logger: logger)
let authRepository = DefaultAuthRepository(
    backend: backend,
    snapshotStore: snapshotStore,
    logger: logger
)
let sessionStore = AppSessionStore(
    restoreSessionUseCase: RestoreSessionUseCase(authRepository: authRepository),
    snapshotStore: snapshotStore,
    tokenProvider: tokenProvider,
    logger: logger
)
```

这里存在依赖方向问题：如果 `DefaultAuthRepository` 要持有 `AppSessionStore`，当前一次性构造方式需要调整，避免循环依赖。

## 4. 问题结论

当前职责分散会导致以下风险：

1. 不同登录入口可能忘记调用 `sessionStore.setAuthenticated(session)`。
2. 仓储返回 session 后，如果 UI 层在后续逻辑中失败，可能出现“token 和快照已保存，但内存仍未登录”的不一致。
3. 登出逻辑分散时，可能出现“本地 token/snapshot 清了，但 UI 状态未及时回 signedOut”的不一致。
4. `AuthRepository` 的语义不完整：登录方法返回成功并不等价于 App 已进入登录态。
5. 后续新增登录方式时，需要重复记住“repository 返回后还要 setAuthenticated”，容易漏。

因此，本工单要求把“认证结果落地后的内存状态切换”收敛到 `DefaultAuthRepository` 内部。

## 5. 目标方案

### 5.1 目标职责边界

`DefaultAuthRepository` 负责：

1. 组装登录请求。
2. 调用后端登录 / OTP 校验 / Apple 登录接口。
3. 确保 token 已写入 token store。
4. 构造无 token 的 `UserSession`。
5. 保存 `SessionSnapshotStore`。
6. 校验快照保存结果。
7. 调用 `AppSessionStore.setAuthenticated(session)`。
8. 登出时调用后端 logout。
9. 登出时清理 token 与 snapshot。
10. 登出时调用 `AppSessionStore.signOut()` 或等价 signedOut 切换。

`LoginViewModel` 负责：

1. 收集用户输入。
2. 处理 Apple credential payload。
3. 调用 repository。
4. 控制 loading。
5. 展示成功/失败通知。
6. 不再直接修改 `AppSessionStore` 登录态。

### 5.2 目标仓储结构

目标结构：

```swift
struct DefaultAuthRepository: AuthRepository {
    let backend: SupportBackend
    let snapshotStore: SessionSnapshotStore
    let sessionStore: AppSessionStore
    private let logger: Logger
}
```

或为了降低 actor/sendable 风险，也可以通过协议抽象：

```swift
@MainActor
protocol AuthSessionStateWriting: AnyObject {
    func setAuthenticated(_ session: UserSession)
    func signOut() async
}
```

然后：

```swift
struct DefaultAuthRepository: AuthRepository {
    let backend: SupportBackend
    let snapshotStore: SessionSnapshotStore
    let sessionStateWriter: AuthSessionStateWriting
    private let logger: Logger
}
```

本工单倾向直接持有 `AppSessionStore`，因为用户明确要求“让 `DefaultAuthRepository` 持有 `AppSessionStore` 并在登录/退出时直接改 UI 状态”。

### 5.3 登录流程目标

Apple 登录目标流程：

```text
LoginViewModel.signInWithApple
└─ repository.signInWithApple(payload)
   ├─ backend.auth.appleLogin
   ├─ token 写入 Keychain/tokenStore
   ├─ makeSession
   ├─ snapshotStore.save(session)
   ├─ verifySnapshotAfterSave
   ├─ sessionStore.setAuthenticated(session)
   └─ return session
```

手机号 OTP 登录目标流程：

```text
LoginViewModel.phoneLogin
└─ repository.verifyPhoneOTP
   ├─ backend.otp.verifyPhoneOTP
   ├─ token 写入 Keychain/tokenStore
   ├─ makeSession
   ├─ snapshotStore.save(session)
   ├─ verifySnapshotAfterSave
   ├─ sessionStore.setAuthenticated(session)
   └─ return session
```

密码登录目标流程：

```text
repository.signInWithPassword
├─ backend.auth.passwordLogin
├─ token 写入 Keychain/tokenStore
├─ makeSession
├─ snapshotStore.save(session)
├─ verifySnapshotAfterSave
├─ sessionStore.setAuthenticated(session)
└─ return session
```

### 5.4 登出流程目标

目标：

```text
repository.logout
├─ backend.auth.logout
├─ backend.tokenProvider().clearTokens
├─ snapshotStore.clear
├─ sessionStore.signOut 或 sessionStore.setSignedOut
└─ return
```

要求：

1. 服务端 logout 失败时仍继续清理本地状态。
2. 本地 token、snapshot、内存登录态必须一起回到 signedOut。
3. 不允许出现 token 已清但 UI 仍 signedIn 的状态。

## 6. 需要修改的代码位置

### 6.1 `AuthFeature.swift`

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App/AuthFeature.swift
```

需要调整：

1. `DefaultAuthRepository` 增加 `sessionStore: AppSessionStore`。
2. 初始化方法增加 `sessionStore` 参数。
3. `signInWithApple` 保存快照后调用 `await MainActor.run { sessionStore.setAuthenticated(session) }` 或等价 MainActor 调用。
4. `signInWithPassword` 保存快照后调用 `sessionStore.setAuthenticated(session)`。
5. `verifyPhoneOTP` 保存快照后调用 `sessionStore.setAuthenticated(session)`。
6. `logout` 清理本地状态后调用 `sessionStore.signOut()` 或等价方法。
7. `LoginViewModel.signInWithApple` 移除 `sessionStore.setAuthenticated(session)`。
8. `LoginViewModel.phoneLogin` 移除 `sessionStore.setAuthenticated(session)`。
9. 如密码登录 UI 后续存在，同样不得在 ViewModel 中重复设置 sessionStore。

### 6.2 `AppContainer.swift`

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App/AppContainer.swift
```

当前构造顺序会遇到 `authRepository` 和 `sessionStore` 相互依赖的问题，需要调整装配方式。

可选方案一：把 session restore 从 repository 中拆出，先构造 `AppSessionStore` 再构造 repository。

可选方案二：引入可延迟绑定的 session writer。

可选方案三：调整 `AppSessionStore` 构造参数，使其不需要在 init 时立刻持有 `RestoreSessionUseCase`，而是后置注入。

本工单要求选择一种清晰方式解决循环依赖，不允许通过隐式全局单例绕过依赖关系。

### 6.3 `AppSessionStore.swift`

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App/AppSessionStore.swift
```

需要确认：

1. `setAuthenticated(_:)` 是否保持同步 `@MainActor` 方法。
2. `signOut()` 是否继续负责清 token + snapshot。
3. 如果 repository 已经清理 token + snapshot，再调用 `signOut()` 是否会重复清理。
4. 可考虑新增更精确的方法，例如：

```swift
func setSignedInAfterRepositorySignIn(_ session: UserSession)
func setSignedOutAfterRepositoryLogout()
```

但第一期可以复用现有 `setAuthenticated` 和 `signOut`，前提是不会造成职责重复或日志误导。

## 7. 关键设计约束

### 7.1 MainActor 约束

`AppSessionStore` 是 `@MainActor` 类型：

```swift
@MainActor
final class AppSessionStore: ObservableObject
```

`DefaultAuthRepository` 的方法不是 `@MainActor`，因此仓储中写 UI 状态时必须显式切到 MainActor。

要求：

1. 不在非 MainActor 上直接访问 `AppSessionStore` 隔离属性或方法。
2. 统一使用 `await MainActor.run { ... }` 或把相关方法标注为 `@MainActor`。
3. 避免把整个网络登录流程搬到 MainActor。

### 7.2 Sendable 约束

`AuthRepository` 当前声明为：

```swift
protocol AuthRepository: Sendable
```

`DefaultAuthRepository` 如果直接持有 `@MainActor AppSessionStore`，可能触发 Sendable / actor isolation 设计问题。

处理要求：

1. 实施前确认 Swift 编译器对 `@MainActor` class 存入 `Sendable` struct 的诊断。
2. 如直接持有导致并发诊断，应使用 `@MainActor` session writer 协议或将 `AuthRepository` 的 `Sendable` 约束重新评估。
3. 不应通过 `@unchecked Sendable` 粗暴掩盖问题，除非有明确隔离证明。

### 7.3 避免重复切状态

改造后，登录态切换只应发生在 repository 内部。

要求：

1. `LoginViewModel` 不再调用 `sessionStore.setAuthenticated(session)`。
2. 其他 UI 层登录入口也不再直接修改登录态。
3. 登出入口应调用 `repository.logout()`，而不是分别调用 backend logout 和 sessionStore.signOut。
4. `AppSessionStore.restoreIfNeeded()` 的冷启动恢复逻辑保持独立。

## 8. 验收标准

### 8.1 登录状态一致性

1. Apple 登录成功后，repository 返回前或返回时，`AppSessionStore.state` 已是 `.signedIn(session)`。
2. 手机号 OTP 登录成功后，`AppSessionStore.state` 已是 `.signedIn(session)`。
3. 密码登录成功后，`AppSessionStore.state` 已是 `.signedIn(session)`。
4. 所有登录方式行为一致，不依赖 ViewModel 再手动 set session。
5. 登录成功后 token、SessionSnapshot、内存登录态三者 accountID 一致。

### 8.2 登出一致性

1. 调用 `repository.logout()` 后，Keychain token 清空。
2. 调用 `repository.logout()` 后，SessionSnapshot 清空。
3. 调用 `repository.logout()` 后，`AppSessionStore.state` 为 `.signedOut`。
4. 服务端 logout 失败时，本地仍完成清理和 signedOut。

### 8.3 UI 层职责验收

1. `LoginViewModel.signInWithApple` 不再调用 `sessionStore.setAuthenticated(session)`。
2. `LoginViewModel.phoneLogin` 不再调用 `sessionStore.setAuthenticated(session)`。
3. UI 层仍可展示登录成功 toast，但不负责登录态切换。
4. 未来新增登录方式只需调用 repository，不需要手动写 sessionStore。

### 8.4 冷启动恢复验收

1. 冷启动恢复仍由 `AppSessionStore.restoreIfNeeded()` 触发。
2. `DefaultAuthRepository.restoreSession()` 仍负责 token 预热、当前 session 刷新和快照合并。
3. 本工单不破坏 `SUPPORT-AUTH-SESSION-000001` 已完成的 token/session 分层。

### 8.5 并发与日志验收

1. 不出现 MainActor 隔离编译错误。
2. 不出现 Sendable 诊断或使用不合理的 `@unchecked Sendable`。
3. 日志能看出登录流程中 snapshot 保存和 sessionStore signedIn 的先后关系。
4. 登录失败时不写入 snapshot，也不切换 signedIn。

## 9. 测试建议

需要补充或更新测试：

1. Apple 登录成功后 repository 会调用 sessionStore signedIn。
2. OTP 登录成功后 repository 会调用 sessionStore signedIn。
3. 密码登录成功后 repository 会调用 sessionStore signedIn。
4. 登录接口失败时 sessionStore 不切换。
5. snapshot 保存失败或不可读时记录错误，不应产生内存与持久化静默不一致。
6. logout 服务端失败时仍清本地并 signedOut。
7. ViewModel 登录成功后不再重复 setAuthenticated。

如当前 `AppSessionStore` 不方便 mock，可新增 `AuthSessionStateWriting` 协议做测试替身。

## 10. 与现有工单关系

本工单是 `SUPPORT-AUTH-SESSION-000001` 的后续职责边界修复。

`SUPPORT-AUTH-SESSION-000001` 处理：

1. token 与 UserSession 分离。
2. token 独立存 Keychain。
3. session snapshot 不覆盖 token。
4. 冷启动恢复时刷新当前 session。

`SUPPORT-AUTH-SESSION-000002` 处理：

1. 登录成功后内存 UI 状态由谁负责切换。
2. 登出后内存 UI 状态由谁负责切换。
3. 避免 ViewModel 和 Repository 分散管理登录态。
4. 让所有登录方式的“效果一致”。

## 11. 非目标

本工单不处理：

1. 登录 UI 样式调整。
2. 新增登录方式。
3. 修改服务端接口。
4. 修改 token refresh 策略。
5. 修改 OSS STS、AISettings、设备登记等登录后业务准备流程。

这些流程只需要依赖最终稳定的 `AppSessionStore.state`。

