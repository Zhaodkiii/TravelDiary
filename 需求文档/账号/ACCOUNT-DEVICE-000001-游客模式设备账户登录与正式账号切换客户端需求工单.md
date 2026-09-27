# ACCOUNT-DEVICE-000001 游客模式设备账户登录与正式账号切换客户端需求工单

创建日期：2026-07-15  
状态：已确认（1A、2A、3A，可进入开发）  
关联模块：登录页、游客模式、AppSessionStore、MainTabCoordinatorView、SettingsView、账号切换  
优先级：P0  
需求类型：客户端认证 / 导航改造 / 设备账户 / 账号升级

## 0. 开发前决策状态

客户端与服务端共用以下 3 项决策，详细权衡见同编号服务端工单：

1. **设备凭证强度：1A 已确认**，`device_id + Keychain device_secret`，服务端存哈希，并预留 App Attest/DeviceCheck；禁止使用裸 device_id 作为唯一登录凭证。
2. **设备身份范围：2A 已确认**，按 `identity_scope + provider=device + device_id`；Health 与 MedicineBox 配置为同一 identity scope 时共享设备账户。
3. **正式身份属于其他用户时：3A 已确认**，切换到正式用户且保留原设备账户，不自动合并数据；用户以后仍可通过游客入口返回原设备账户。

三项决策均已确认。客户端 Keychain 设备凭证、登录接口鉴权字段、路由、账号切换和 identity scope 规则全部锁定，可进入开发。

## 1. 背景与目标体验

当前登录页的“游客模式”会导航到 `GuestChatView`，属于独立本地访客能力。目标改为：用户点击“游客模式”后，客户端立即使用安装设备凭证调用设备登录接口，获得真实 `UserSession` 和 token，然后像 Apple/手机号登录一样进入完整主应用。

对用户仍显示“游客模式”，但内部已是服务端已认证的设备账户。设备账户可以正常使用完整功能和云端数据；它没有可恢复的正式认证方式，因此设置页账号入口显示“未登录”，点击后以 sheet 打开正式登录页。正式登录成功后，服务端可能升级当前设备账户，也可能返回另一个已有账号，客户端必须分别处理。

## 2. 目标

1. 游客按钮不再进入 `GuestChatView`，改为执行设备账户登录。
2. 设备登录与 Apple、手机号登录复用 SessionSnapshot、token、设备注册、主应用启动流程。
3. `UserSession` 能明确表达 `.device` 和 `isDeviceAccount`。
4. 设备账户登录成功后直接进入完整 `MainTabCoordinatorView`。
5. 设置页设备账户显示“未登录”；点击时不进入账号管理页，而是 sheet 打开登录页。
6. 正式账户点击同一入口时，通过 AppRoute 跳转账号管理页；页面构建归 `MainTabCoordinatorView.routeDestination` 管理。
7. 正式认证升级同一 `accountID` 时原地刷新 session；认证命中其他 `accountID` 时执行现有完整账号切换流程。
8. 所有加载、失败、取消、重复点击、冷启动和离线场景有确定行为。

## 3. 非目标

1. 不保留 `GuestChatView` 作为新游客入口。
2. 不在本工单迁移旧 GuestChat 本地聊天记录到设备账户。
3. 不把设备账户的业务功能做阉割或只读限制。
4. 不在客户端合并两个账号的数据。
5. 不由客户端判断正式身份是否首次添加；只消费服务端 `account_resolution` 和返回的 `user_id`。
6. 不新增服务端当前未开放的 Google/邮箱登录 UI；未来接入时复用同一账户切换规则。

## 4. 当前代码与改造位置

| 文件 | 当前状态 | 本工单要求 |
|---|---|---|
| `SparkClient/Projects/Features/Auth/Presentation/LoginView.swift:68-74,212-223` | 游客按钮 push `.guest` 并展示 GuestChatView | 改为直接调用 `signInWithDevice()`；移除 `.guest` 路由 |
| `SparkClient/Projects/Features/Auth/Presentation/LoginViewModel.swift` | 仅 Apple、Phone 登录；只要当前 signedIn 就预先启动账号切换 | 增加设备登录；正式登录完成后按返回 accountID/resolution 决定原地升级或账号切换 |
| `SparkClient/Projects/Features/Auth/Domain/AuthRepository.swift` | 无设备登录能力 | 增加 `signInWithDevice()` |
| `SparkClient/Projects/Features/Auth/Infrastructure/DefaultAuthRepository.swift` | 已读取 Keychain device ID 并保存正式登录 session | 增加设备凭证登录和统一 session 映射 |
| `SparkClient/Projects/Core/Domain/Entities/UserSession.swift:3-15` | SignInMethod 仅 apple、phone | 增加 device；补齐服务端已有/规划的 email、google 兼容解码；增加 `isDeviceAccount` |
| `SparkClient/Projects/Features/Settings/Presentation/SettingsView.swift:12-25` | 直接构建 AccountManagementView，右侧显示 displayName/email | 改为无页面构建职责的账号入口；设备账户显示“未登录” |
| `SparkClient/Projects/App/Sources/App/AppRouteStore.swift:6-43` | 无 accountManagement route | 增加 `.accountManagement` 并归 settings tab |
| `SparkClient/Projects/App/Sources/App/MainTabCoordinatorView.swift:83-93,117-158` | Settings 根页由 coordinator 构建，但 routeDestination 无账号管理 | 正式账户路由到账号管理；设备账户在 coordinator 层 present 登录 sheet |
| `SparkClient/Projects/App/Sources/App/Architecture/AccountSessionRuntime.swift` | 已有账号切换挂起、提交/回滚能力 | 只在 accountID 真正变化时使用；同账号升级不得误清数据 |

用户引用的 `Client sub-project/MedicineBox/.../SettingsView.swift:14-23` 与当前 `SparkClient` 中对应文件内容一致，本工单实际落点以 `SparkClient` 为准。

## 5. 用户状态模型

客户端必须区分“认证状态”和“账户类型”：

| AppSessionStore | UserSession.isDeviceAccount | UI 含义 |
|---|---:|---|
| `.signedOut` | 不适用 | 真正未登录，展示全屏 LoginView |
| `.signedIn` | `true` | 设备账户，完整使用应用；设置页文案显示“未登录” |
| `.signedIn` | `false` | 至少有一种正式认证身份的普通账户 |

不可把设备账户写入 `.signedOut`，否则所有依赖 token、账户级缓存和 MainTab 的逻辑都会错误地退回登录页或 guest namespace。

### 5.1 UserSession 建议字段

```swift
enum SignInMethod: String, Codable, Sendable {
    case device
    case apple
    case google
    case phone
    case email
}

let isDeviceAccount: Bool
```

`isDeviceAccount` 以服务端字段为准，不能仅根据 `signInMethod == .device` 永久推断，因为“最近一次登录方式”和“当前是否仍只有设备身份”是不同概念。

为兼容旧快照，解码缺少 `isDeviceAccount` 时默认 false；服务端 session 刷新成功后覆盖本地值。

## 6. 游客按钮设备登录流程

### 6.1 主流程

```text
用户同意隐私条款
-> 点击“游客模式”
-> LoginViewModel 进入 loading，禁用所有登录按钮
-> 从 Keychain 读取或创建设备 ID 与 device secret
-> POST /api/v1/auth/device/login/
-> 保存 access/refresh token
-> 构建并持久化 UserSession(signInMethod=device, isDeviceAccount=true)
-> 激活账户级运行时与设备注册
-> AppSessionStore.setAuthenticated(session)
-> AppCoordinatorView 自动进入完整 MainTabCoordinatorView
```

设备登录不 push 新页面，不展示 `GuestChatView`，成功后也不要求用户再次点击“进入应用”。

### 6.2 交互规则

1. 保留现有隐私协议前置校验；未同意时点击游客模式仍打开协议 sheet。
2. 登录进行中展示现有全屏 ProgressView，所有 Apple、Phone、Guest 按钮不可重复点击。
3. 防止双击产生并发请求；ViewModel 同一时刻只允许一个认证任务。
4. 用户离开页面或 App 进入后台时，不清除已成功写入的 token；未完成请求可取消，但下次点击必须可幂等重试。
5. 成功提示可以省略，优先直接进入应用；失败使用统一通知组件。
6. 设备账户完成正式身份升级并退出后，再次点击游客模式时继续使用原安装 device ID；服务端会为该设备创建新的游客账户，客户端不得自行轮换 device ID。
7. 设备凭证失效时不得静默轮换并创建新账号；需按服务端错误码提示并记录诊断。

### 6.3 冷启动

设备账户与普通账户一致：优先恢复 SessionSnapshot 和 refresh token，再请求当前 session。恢复成功直接进入 MainTab；明确 401 才清除 session 回到登录页。临时网络失败沿用现有缓存 session 降级策略。

## 7. 设置页账户入口

### 7.1 展示

设置页账户行保留现有标题和图标：

| 账户状态 | 右侧文案 | 点击行为 |
|---|---|---|
| 设备账户 | `未登录` | sheet 打开正式登录页面 |
| 正式账户 | displayName；为空时显示 email/phone 掩码 | AppRoute 跳转账号管理页 |

“未登录”是产品展示文案，不代表 `AppSessionStore.signedOut`。建议新增明确本地化 key，例如 `settings.account.device_not_linked`，不要复用会影响认证逻辑的状态字符串。

### 7.2 SettingsView 职责

`SettingsView` 不再直接构建 `AccountManagementView`。推荐接收轻量动作：

```text
onAccountEntryTap()
```

或接收 coordinator 可观察的路由意图。点击后由 `MainTabCoordinatorView` 根据最新 session 决定 route 或 sheet，避免 SettingsView 持有 LoginViewModel、账号切换器和页面依赖。

### 7.3 正式账户导航

在 `AppRoute` 增加：

```swift
case accountManagement
```

规则：

1. `rootTab = .settings`。
2. `isRootDestination = false`。
3. `MainTabCoordinatorView.routeDestination` 构建 `AccountManagementView(viewModel:session:)`。
4. 重复点击不重复压栈；账号切换或登出时由现有 route graph reset 清空。

### 7.4 设备账户登录 sheet

由 `MainTabCoordinatorView` 持有 `@State` 展示状态，并通过 Auth assembly 创建独立、生命周期稳定的 `LoginViewModel`。sheet 内复用 LoginView 的 Apple/Phone 流程，但必须使用“账户升级模式”：

1. 隐藏“游客模式”按钮，避免 sheet 内递归设备登录。
2. 保留隐私协议状态和 Apple/Phone 登录能力。
3. 支持关闭；关闭不改变当前设备账户。
4. 登录成功后自动 dismiss。
5. sheet 被手势关闭时，若登录任务正在进行，必须明确禁止关闭或安全取消，避免账号切换事务停在 suspended 状态。

推荐给 `LoginView` 增加场景参数，而不是复制一套页面：

```text
mode = primarySignIn | upgradeDeviceAccount
```

## 8. 正式登录后的客户端分流

服务端响应必须包含 `user_id`、`is_device_account` 和 `account_resolution`。客户端记录发起登录前的 `currentAccountID`，完成认证后执行以下矩阵：

| 服务端结果 | user_id 对比 | 客户端处理 |
|---|---|---|
| `device_account_upgraded` | 相同 | 不执行账户切换清理；更新 token、SessionSnapshot、UserSession；关闭 sheet；刷新账号资料和 identities |
| `existing_identity_login` | 不同 | 执行现有 `beginLoginAccountSwitch` -> 保存新 session -> `endLoginAccountSwitch(commit:true)` -> 重建账户级依赖和路由 |
| `formal_account_created` | 通常不同或无旧账号 | 按普通新账号登录/切换流程 |
| 任意失败或用户取消 | 不变 | `endLoginAccountSwitch(commit:false)`（仅在确实 begin 后）；保留设备账户及当前页面 |

### 8.1 修正当前切换时机

当前 `LoginViewModel` 在请求前只要发现 `.signedIn` 就调用 `beginLoginAccountSwitch`。设备账户升级可能返回相同 accountID，若提前清理，会造成无必要的缓存重置和页面跳转。

推荐实现：

1. 请求前只记录旧 accountID，并暂停会产生写入冲突的任务；不要立即执行不可逆清理。
2. 登录响应后比较新旧 accountID。
3. 相同 ID 走“凭证升级”，仅刷新 session 和账户资料。
4. 不同 ID 才调用完整账号切换。
5. 若现有 runtime 强制要求请求前 suspend，则把 suspend 与 reset 分离：先可回滚暂停，响应后再 commit 到目标 accountID。

### 8.2 Token 与快照一致性

认证仓储必须以同一响应原子完成以下逻辑：

```text
后端 token 已保存
-> UserSession 快照保存成功
-> 运行时切换/升级完成
-> AppSessionStore 发布新 session
```

任一阶段失败必须避免“token 属于 U2、内存 session 仍是 U1”。至少记录旧/新 accountID、resolution 和 request ID；日志不得记录 token。

## 9. 设备账户资料与账号管理

1. 设备账户不进入 `AccountManagementView`，因此不展示注销、登录方式绑定/修改等普通账号管理操作。
2. 升级同一账户成功后，再次点击设置账户行应进入 AccountManagementView，且能看到新增正式身份。
3. 若升级到其他已有账户，账号管理页展示目标账户资料；原设备账户数据不混入。
4. displayName/email 为空时，设备账户设置行固定显示“未登录”，其他页面不得显示伪造邮箱或 `Apple User`。

## 10. 异常与边界场景

| 场景 | 要求 |
|---|---|
| 设备登录网络失败 | 保持登录页，可重试，不创建本地假 session |
| 服务端已建号但响应丢失 | 重试命中同一 device identity，返回同一账户 |
| 用户在设备账户 sheet 取消 Apple 登录 | 关闭 Apple 授权，不关闭当前设备会话，不重置缓存 |
| OTP 错误/过期 | 停留登录 sheet，允许按现有规则重试 |
| 正式身份升级同一账户 | 原地更新，不清除该账户缓存和当前业务数据 |
| 正式身份属于其他账户 | 切换账户，清理/隔离旧账户运行态，不合并数据 |
| 切换提交失败 | 回滚至原设备账户；若 token 已被覆盖，必须恢复或强制重新设备登录，不能保持分裂状态 |
| 升级成功后 sheet 未自动关闭 | 监听 accountID/isDeviceAccount 变化兜底关闭 |
| 升级后用户退出并再次点游客模式 | 使用同一 device ID 登录；服务端创建新的游客账户，客户端进入该新账户的完整应用 |
| 新游客账户再次点游客模式 | 返回同一新游客账户，不重复建号 |
| Keychain device ID 丢失 | 视为新安装；提示原游客数据可能无法恢复 |
| 多窗口/重复 sheet | 全局只允许一个认证流程；第二入口聚焦已有 sheet |

## 11. 文案与可访问性

新增中英文 key 至少包括：

```text
settings.account.device_not_linked = 未登录
auth.device.login_failed
auth.device.credential_invalid
auth.device.data_recovery_warning
auth.device.upgrade_success
auth.device.new_guest_created
```

“游客模式”入口需补充可访问性说明：“使用此设备快速进入完整应用”。设备账户首次进入后应在合适位置解释：数据已关联本设备，绑定 Apple/手机号等方式后可降低丢失风险。

不得把设备 ID、accountID、服务端错误堆栈展示给普通用户；诊断信息写入日志并关联 request ID。

## 12. 埋点与监控

建议事件：

```text
guest_device_login_tapped
guest_device_login_succeeded
guest_device_login_failed
device_account_upgrade_sheet_opened
device_account_upgrade_cancelled
device_account_upgraded_same_user
device_account_switched_existing_user
device_account_recreated_after_upgrade
```

属性只包含 bundle、App 版本、resolution、错误码和匿名化 account/device 哈希，不上传原始 device secret、手机号、邮箱或 token。

## 13. 验收标准

- [ ] 登录页点击游客模式不再进入 GuestChatView，而是创建/登录设备账户。
- [ ] 设备登录成功直接进入完整 MainTab，首页、聊天、科普、设置等功能均可正常调用鉴权 API。
- [ ] 冷启动和 token refresh 能恢复同一设备账户。
- [ ] 设备账户设置行显示“未登录”，点击以 sheet 打开登录页。
- [ ] sheet 不显示游客按钮，取消后仍停留设备账户。
- [ ] 正式账户设置行通过 AppRoute 进入账号管理页，SettingsView 不直接构建目标页。
- [ ] 同一设备账户首次添加 Apple/Phone/Email/Google 时，若服务端返回同 accountID，客户端不执行账号缓存清理。
- [ ] 正式身份属于其他用户时，客户端完整执行账号切换，缓存、路由、任务和设备注册均切至新账户。
- [ ] 失败和取消不会留下 suspended runtime、错误 token 或错配 SessionSnapshot。
- [ ] 原设备账户升级并退出后，再次点击游客模式会使用同一 device ID 创建新的游客账户，且无法访问原账户数据。
- [ ] VoiceOver 能读出账号状态、游客入口目的和登录 sheet 关闭按钮。
- [ ] iOS 15/16 兼容导航容器下 route 与 sheet 均正常，无重复压栈或空白页。

## 14. 客户端测试清单

1. LoginViewModel：设备登录成功、失败、双击、取消，以及升级退出后创建新游客账户。
2. Session 映射：device/email/google 新枚举、旧快照兼容、`isDeviceAccount` 缺省值。
3. SettingsView：设备账户显示与 tap action；正式账户显示与 route action。
4. MainTabCoordinator：`.accountManagement` destination、登录 sheet 生命周期、重复展示保护。
5. AccountSessionRuntime：同 accountID 升级不 reset；不同 accountID commit；失败 rollback。
6. 集成测试：设备建号 -> 完整应用 -> 设置登录 -> 同账号升级。
7. 集成测试：设备 U1 -> 登录已属于 U2 的手机号/Apple -> 切换 U2 -> 退出 -> 点击游客入口仍返回 U1。
8. 回归：普通未登录 Apple/Phone 登录、账号管理登录方式绑定、登出、冷启动、token refresh。

## 15. 发布顺序与回滚

1. 服务端先发布模型、device login 和统一 account_resolution，默认 feature flag 关闭。
2. 客户端发布后按 bundle 和版本灰度开放游客设备登录。
3. 先验证建号幂等、同账号升级和跨账号切换，再扩大流量。
4. 回滚时关闭客户端入口或服务端 flag；已创建的设备账户和正式账户数据必须保留。
5. 若发现 token/session 账号错配、错误合并或重复建号，立即停止灰度。

## 16. 关联工单

1. `SparkService/需求文档/账号/ACCOUNT-DEVICE-000001-设备游客账户与正式认证升级服务端需求及详细设计工单.md`
2. `SparkClient/需求文档/账号/ACCOUNT-LINKING-000001-账号管理登录方式绑定与修改客户端需求工单.md`
3. `SparkClient/需求文档/启动/应用登录启动需求文档.md`

## 17. 客户端详细实现方案

### 17.1 目标架构

| 层级 | 职责 | 改造点 |
|---|---|---|
| `LoginView` | 协议确认、按钮、Apple/Phone 输入、sheet | 游客按钮直接调用设备登录 |
| `LoginViewModel` | 登录任务、错误映射、session 提交 | 增加 device login 和账号分流 |
| Auth UseCase | 表达登录业务动作 | 新增 `SignInWithDeviceUseCase` |
| `AuthRepository` | 读取设备凭证、调用 API、映射 session | 增加 `signInWithDevice()` |
| `SparkAuthAPI` | 请求和响应解码 | 增加 `/auth/device/login/` |
| `AppSessionStore` | 发布 signedIn/signedOut | 设备账户必须保持 signedIn |
| `AccountSessionRuntime` | 账户 namespace、缓存、任务和路由切换 | 区分同账号升级与跨账号切换 |

`SettingsView` 不得直接调用登录 API、创建 LoginViewModel 或构建 AccountManagementView；这些职责由 `MainTabCoordinatorView` 和 AppContainer 负责。

### 17.2 逐文件改造清单

| 文件 | 改造内容 |
|---|---|
| `Projects/Foundation/Security/SparkKeychain.swift` | 增加 `device_secret` 生成、读取、保存和轮换 |
| `Projects/Core/Domain/Entities/UserSession.swift` | 增加 `.device/.google/.email` 和 `isDeviceAccount` |
| `Projects/Core/Networking/API/Auth/AuthAPI.swift` | 增加设备登录请求、响应和 `account_resolution` |
| `Projects/Core/Networking/AuthTokenProvider.swift` | 保持 token/refresh；刷新请求继续携带 device_id |
| `Projects/Features/Auth/Domain/AuthRepository.swift` | 增加 `signInWithDevice()` |
| `Projects/Features/Auth/Application/SignInWithDeviceUseCase.swift` | 新增设备登录 use case |
| `Projects/Features/Auth/Infrastructure/DefaultAuthRepository.swift` | 读取凭证、调用 API、映射 UserSession |
| `Projects/Features/Auth/Presentation/LoginViewModel.swift` | 设备登录、同账号升级、跨账号切换分流 |
| `Projects/Features/Auth/Presentation/LoginView.swift` | 游客按钮改为设备登录；升级 sheet 隐藏游客按钮 |
| `Projects/Features/Auth/Presentation/AuthUserFacingErrorMapper.swift` | 增加设备错误映射 |
| `Projects/App/Sources/App/AppRouteStore.swift` | 增加 `.accountManagement` |
| `Projects/App/Sources/App/MainTabCoordinatorView.swift` | 账户入口、账号管理 destination、升级 sheet |
| `Projects/Features/Settings/Presentation/SettingsView.swift` | 移除直接构建 AccountManagementView，改为 action 回调 |
| `Projects/App/Sources/App/AppContainer.swift` | 注入设备 use case 和升级模式 LoginViewModel |
| `Projects/App/Sources/App/Architecture/AccountSessionRuntime.swift` | 区分 same-account update 与 cross-account switch |
| `Projects/App/Sources/App/Architecture/StorageRegistry.swift` | 明确账户 namespace 清理和切换边界 |
| `Projects/App/Resources/*/Localizable.strings` | 新增设备账户文案 |

### 17.3 Keychain 设备凭证

当前 `SparkKeychain.swift:4-62` 只有安装级 `device_id`，并与 HealthClient 共用 service/account。新增独立 account：`device_login_secret`。

建议 API：`getOrCreateDeviceID()`、`getOrCreateDeviceSecret()`、`loadDeviceSecret()`、`replaceDeviceSecret()`、`deleteDeviceSecret()`。

实现规则：

1. `device_id` 保持现有 Keychain item，升级前后安装标识连续。
2. `device_secret` 使用 `SecRandomCopyBytes` 生成至少 32 bytes，Base64URL 编码。
3. 两者均使用 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`，不允许同步到其他设备。
4. secret 保存失败不能返回临时内存 secret 继续注册；应返回 `deviceCredentialUnavailable`。
5. 读取失败不能静默生成新 secret 覆盖旧身份，只有服务端明确要求轮换时才能替换。
6. 日志只输出 device_id 脱敏值和 secret 是否存在，不输出 secret。

### 17.4 Auth API 和 UserSession

当前 `SparkAuthAPI.LoginResult` 只有 token 字段。新增响应字段：`email`、`display_name`、`is_pro`、`is_new_user`、`sign_in_method`、`is_device_account`、`account_resolution`、`identity_scope`。

新增 API 方法：`loginWithDevice(bundleId:deviceId:deviceSecret:) async throws -> AuthenticatedUserContext`。

请求固定为 `POST /api/v1/auth/device/login/`，字段为真实 `bundle_id`、`device_id`、`device_secret`。API 层只请求和解码，不写 AppSessionStore；成功后保存 AuthTokenProvider token，并将 resolution 传给 Repository/ViewModel。

建议内部结果类型包含 `session`、`resolution`、`tokens`。`AccountResolution` 至少包含：`device_account_created`、`device_account_login`、`device_account_recreated`、`device_account_upgraded`、`formal_account_created`、`existing_identity_login`。

`UserSession.SignInMethod` 增加 `device/google/email` 和 `isDeviceAccount`。旧 SessionSnapshot 缺少字段时默认 false；服务端 session 刷新成功后覆盖旧快照。设备账户必须保持 `AppSessionStore.State.signedIn`，不能因为设置页显示“未登录”而退回 signedOut。

### 17.5 LoginViewModel 状态机

状态为：`idle -> authenticating -> authenticatedSameAccount/authenticatedOtherAccount -> failed/cancelled`。

设备登录必须有单任务保护：`guard isLoading == false else { return }`。登录完成后统一执行：记录 oldAccountID -> 读取 newAccountID/resolution -> 相同 accountID 更新 token、snapshot、AppSessionStore 且不 reset namespace -> 不同 accountID 执行 AccountSessionRuntime 完整切换 -> 失败时只回滚已 begin 的切换。

设备账户升级必须满足 `oldAccountID == newAccountID`、`resolution=device_account_upgraded`、旧 session 为设备账户、新 session 为正式账户。此时禁止执行账户缓存清理。

### 17.6 AccountSessionRuntime 切换边界

现有 `AccountSessionRuntime.swift` 已有 `beginLoginAccountSwitch/endLoginAccountSwitch`。begin 阶段只暂停可能跨账户写入的任务，不提前删除旧缓存；收到响应后比较 accountID；同一 accountID 恢复任务并更新 metadata；不同 accountID 才执行 StorageRegistry namespace 切换、依赖重建和 route graph reset。

commit 失败时必须恢复旧账户。不能出现 token 属于 U2、SessionSnapshot 仍是 U1 或文件缓存仍在 U1 namespace 的分裂状态。

### 17.7 LoginView 游客按钮与升级模式

现有 `LoginView.swift:212-220` 将游客按钮 push `.guest`，改为在同意协议后直接执行 `Task { await viewModel.signInWithDevice() }`，删除 `.guest` 路由和 GuestChatView 新入口。

增加 `LoginPresentationMode.primarySignIn/upgradeDeviceAccount`。升级模式下隐藏游客按钮，复用 Apple/Phone 登录；sheet 关闭时取消任务或阻止交互式 dismiss，避免切换流程停在 suspended 状态。

### 17.8 Settings 与 MainTabCoordinator

`SettingsView.swift:12-24` 改为接收 `onAccountEntryTap`，不再直接构建 AccountManagementView。设备账户右侧显示 `settings.account.device_not_linked`；正式账户显示 displayName/contact。

`MainTabCoordinatorView` 根据 session 分流：设备账户打开升级登录 sheet；正式账户调用 `routeStore.route(to: .accountManagement)`。`AppRouteStore` 中 `.accountManagement` 归属 `.settings` 且不是 root destination；`routeDestination` 负责构建 AccountManagementView。

升级 LoginViewModel 必须从 AppContainer/FeatureAssembly 创建，不能在 SwiftUI body 中重复初始化，确保 nonce、OTP 状态和账号切换任务稳定。

### 17.9 Token、快照和 UI 时序

严格执行：API 解码 -> AuthTokenProvider.setTokens -> 构建 UserSession -> SessionSnapshotStore.save -> 比较 accountID -> runtime update/switch commit -> AppSessionStore.setAuthenticated -> dismiss sheet/显示主应用。

如果 token 已保存但 snapshot 保存失败，不得直接发布新 session；应恢复旧 token 或进入明确错误态。AuthTokenProvider 的 refresh actor 去重逻辑保持不变。

### 17.10 生命周期矩阵

| 场景 | 服务端结果 | 客户端行为 |
|---|---|---|
| 首次游客登录 | U1/device | signedIn，进入完整 MainTab |
| 设备重复登录 | U1/device | same-account update，不建新用户 |
| U1 首次正式认证 | U1/formal | 更新同一 session，不清理 U1 数据 |
| 正式身份属于 U2 | U2/formal，U1/device 保留 | 完整切换到 U2 |
| U1 升级后退出再游客登录 | 新建 U3/device | 切换到 U3，U1 只能正式登录 |
| Keychain 丢失 | 新安装凭证 | 按服务端结果创建/恢复新设备账户 |

### 17.11 错误映射和测试

设备错误映射：`device_id_required`、`device_secret_required`、`device_credential_invalid`、`device_credential_locked`、`device_identity_conflict`、`device_login_store_unavailable`。用户提示不得暴露 device_id、accountID、provider_uid 或 token。

测试必须覆盖：Keychain secret 只创建一次且不写日志；设备 API 请求字段完整；游客按钮协议校验和双击去重；同账号升级不 reset；跨账号登录完整 commit；设备设置入口打开 sheet；正式设置入口进入 accountManagement；sheet 不显示游客按钮；冷启动 refresh 后设备账户仍 signedIn；Apple/Phone/账号管理绑定回归；iOS 15/16 导航回归。

## 18. 端到端时序和完成定义

首次游客登录：`LoginView -> LoginViewModel -> Keychain -> SparkAuthAPI -> Server 创建 U1/device -> 保存 token/Snapshot -> AppSessionStore.signedIn(U1) -> MainTabCoordinatorView`。

设备账户升级：`Settings -> MainTabCoordinatorView 升级 sheet -> Apple/Phone/Email -> Server 绑定 formal identity 到 U1 并删除 U1 device identity -> 返回相同 accountID -> 客户端只更新 token/session -> 关闭 sheet`。

正式身份属于其他用户：`U1 device -> 登录 U2 formal -> Server 保留 U1 device identity -> Client 收到不同 accountID -> AccountSessionRuntime 切换 U1/U2 -> StorageRegistry 切换 namespace -> RouteGraph reset -> 后续游客入口仍可返回 U1`。

完成定义：1A/2A/3A 在两端接口和测试中一致；裸 device_id 不能登录；secret 不落日志、不写 SocialIdentity；首次建号、重复登录、升级、跨账号登录、升级后新游客建号可验证；同账号升级不清理缓存；跨账号登录完整切换；iOS 15/16、冷启动、refresh、并发和事务回滚测试通过。
