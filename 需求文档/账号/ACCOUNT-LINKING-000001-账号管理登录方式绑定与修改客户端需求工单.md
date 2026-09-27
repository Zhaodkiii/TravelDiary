# ACCOUNT-LINKING-000001 账号管理登录方式绑定与修改客户端需求工单

创建日期：2026-07-15  
关联模块：账号管理页、登录方式管理、手机号 OTP、邮箱 OTP、Apple 登录、账号安全验证  
优先级：P0  
需求类型：客户端账号管理 / 登录方式绑定 / 登录方式修改

## 1. 背景

当前账号管理页已有账号信息展示与注销前安全认证能力：

```text
SparkClient/SparkClient/Projects/Features/AccountManagement/Presentation/AccountManagementView.swift:63-98
SparkClient/SparkClient/Projects/Features/AccountManagement/Presentation/Components/AccountManagementComponents.swift:69-143
```

现需要扩展账号管理页，支持展示邮箱、手机号、Apple 三种登录方式，并提供绑定和修改流程。

用户操作必须遵循安全流程：

```text
先使用已绑定的认证方式完成安全认证
认证通过后进入目标登录方式绑定或修改页面
目标手机号/邮箱/Apple 验证通过后提交服务端登记
服务端写入或更新 SocialIdentity
```

## 2. 目标

1. 账号管理页展示邮箱、手机号、Apple 登录方式的绑定状态。
2. 未绑定方式展示“绑定”入口。
3. 已绑定手机号、邮箱展示“修改”入口。
4. Apple 已绑定时只展示状态，不提供修改入口；未绑定时支持绑定。
5. 绑定或修改前必须先完成已有登录方式认证。
6. 目标方式验证通过后调用服务端绑定或修改接口。
7. 服务端返回“已绑定其他用户”时，客户端明确提示用户不能继续。
8. 客户端传真实 `bundle_id`，登录方式状态以服务端按 `ACCOUNT_IDENTITY_SCOPE_ALIASES` 解析后的结果为准。

## 3. 非目标

1. 本工单不调整登录页主登录流程。
2. 本工单不实现账号合并。
3. 本工单不支持 Apple ID 修改。
4. 本工单不允许用户解绑最后一种登录方式。
5. 本工单不处理客服申诉流程，只展示服务端错误提示。

## 4. 当前客户端状态

### 4.1 当前账号信息展示

`AccountManagementView.accountInfoSection` 当前展示：

1. account_id
2. 当前 contact
3. signInMethod
4. signInTime

不足：

1. 只能展示当前登录方式。
2. 不能展示多登录方式绑定状态。
3. 没有绑定/修改入口。

### 4.2 当前安全认证组件

`VerificationMethodCard` 已支持选择：

```text
apple
phone
email
```

这部分可以复用为绑定/修改流程的第一步。

### 4.3 当前 ViewModel

`AccountManagementViewModel.availableVerificationChannels` 当前基于 `profile.signInMethod` 推断可认证方式。

绑定/修改后，需要改为基于服务端返回的 `identities` 列表生成可认证方式，而不是只看当前登录方式。

## 5. 页面设计

详细 plain text UI 线框见：

```text
SparkClient/需求文档/账号/ACCOUNT-LINKING-000001-账号管理登录方式UI线框.md
```

### 5.1 登录方式区块

在账号管理页新增区块：

```text
登录方式
```

每一行展示：

| 字段 | 说明 |
|---|---|
| 图标 | 手机号、邮箱、Apple |
| 标题 | 手机号、邮箱、Apple |
| 状态 | 已绑定时展示掩码值；未绑定时展示“未绑定” |
| 操作 | 未绑定展示“绑定”；手机号/邮箱已绑定展示“修改”；Apple 已绑定无修改入口 |

建议展示：

| 登录方式 | 未绑定 | 已绑定 |
|---|---|---|
| 手机号 | 绑定 | `+86138****00` + 修改 |
| 邮箱 | 绑定 | `ab***c@example.com` + 修改 |
| Apple | 绑定 | Apple ID 已绑定 |

### 5.2 操作入口规则

| 状态 | 手机号 | 邮箱 | Apple |
|---|---|---|---|
| 未绑定 | 显示绑定 | 显示绑定 | 显示绑定 |
| 已绑定 | 显示修改 | 显示修改 | 不显示修改 |
| 当前账号只有一种登录方式 | 允许绑定新方式 | 允许绑定新方式 | 允许绑定 Apple |

客户端不自行判断目标是否已被其他用户绑定，最终以服务端结果为准。

### 5.3 Apple 登录响应邮箱展示规则

Apple 登录响应中可能包含 `email` 字段，但客户端不能把它理解为“邮箱登录方式已绑定”。

规则：

1. 账号管理页邮箱绑定状态必须来自 `GET /api/v1/accounts/identities/` 的 `provider=email` 状态。
2. Apple 登录响应中的 `email` 只能作为当前账号展示邮箱使用，且以服务端返回值为准。
3. 如果用户原本已有账号邮箱，服务端不会因为 Apple token 携带新 email 而覆盖；客户端不做本地覆盖。
4. Apple 登录成功后，如需刷新账号管理页，必须重新拉取登录方式列表或账号 profile。
5. Apple ID 已绑定不等于邮箱已绑定；邮箱仍需走邮箱绑定流程。
6. Django `User.email` 是资料邮箱；邮箱登录绑定只看 `SocialIdentity(provider=email)`。
7. Apple 登录携带的 email 即使展示在资料邮箱位置，也不能让“邮箱登录方式”显示为已绑定。

## 6. 绑定流程

### 6.1 流程总览

```text
用户点击“绑定手机号/邮箱/Apple”
-> 选择并完成已有方式安全认证
-> 服务端返回 verification_ticket
-> 进入目标方式验证页面
-> 目标方式验证通过
-> 调用绑定接口
-> 刷新账号登录方式列表
```

### 6.2 第一步：已有方式认证

客户端展示 `VerificationMethodCard`，认证方式来自服务端返回的已绑定 identities。

规则：

1. 如果已有手机号，允许短信 OTP 认证。
2. 如果已有邮箱，允许邮箱 OTP 认证。
3. 如果已有 Apple，允许 Apple 再认证。
4. 如果当前用户没有任何可认证方式，不能进入绑定流程，展示错误。

认证完成后，客户端保存：

```text
verification_ticket
```

该 ticket 只用于当前绑定流程。

### 6.3 第二步：目标方式验证

按目标方式进入不同页面：

| 目标方式 | 页面内容 |
|---|---|
| 手机号 | 手机号输入、发送验证码、验证码输入 |
| 邮箱 | 邮箱输入、发送验证码、验证码输入 |
| Apple | Sign in with Apple 按钮 |

目标验证通过后，客户端调用：

```text
POST /api/v1/accounts/identities/bind/
```

### 6.4 绑定成功

成功后：

1. 关闭流程弹层。
2. 清空本地验证码、ticket、输入值。
3. 调用登录方式列表接口刷新数据。
4. 如服务端返回新的 `UserSession` 或 profile，更新本地 session 快照。
5. 展示成功提示。

## 7. 修改流程

### 7.1 支持范围

本期只支持：

```text
手机号修改
邮箱修改
```

不支持：

```text
Apple 修改
```

### 7.2 流程总览

```text
用户点击“修改手机号/邮箱”
-> 先选择并验证已有方式
-> 服务端返回 verification_ticket
-> 进入新手机号/新邮箱输入页面
-> 发送并验证新目标 OTP
-> 调用修改接口
-> 刷新账号登录方式列表
```

### 7.3 旧方式认证

旧方式认证不一定必须使用“正在修改的方式”。用户可以使用任一已绑定方式完成安全认证。

例：

1. 修改手机号时，可以先用 Apple 认证。
2. 修改邮箱时，可以先用手机号 OTP 认证。
3. 如果服务端要求必须验证原手机号/原邮箱，则客户端按服务端返回的 `allowed_verification_providers` 展示。

默认推荐：允许任一已绑定方式认证，提高可用性。

### 7.4 新方式验证

新手机号或新邮箱必须完成 OTP 验证。

修改接口：

```text
POST /api/v1/accounts/identities/change/
```

成功后刷新列表。

## 8. 状态机建议

当前 `AccountDeactivationFlowState` 是注销专用。建议新增账号身份管理专用状态，不继续复用注销状态名。

建议：

```swift
enum AccountIdentityFlowState: Equatable {
    case idle
    case choosingReauth(operation: AccountIdentityOperation)
    case reauthOTP(operation: AccountIdentityOperation, channel: AccountVerificationChannel, otpID: String)
    case reauthApple(operation: AccountIdentityOperation)
    case enteringTarget(operation: AccountIdentityOperation, ticket: String)
    case targetOTP(operation: AccountIdentityOperation, ticket: String, otpID: String)
    case submitting
    case completed
    case failed(String)
}
```

操作类型：

```swift
enum AccountIdentityOperation: Equatable {
    case bind(provider: AccountIdentityProvider)
    case change(provider: AccountIdentityProvider)
}
```

登录方式模型：

```swift
enum AccountIdentityProvider: String, Equatable, Sendable {
    case phone
    case email
    case apple
}
```

## 9. 数据模型建议

服务端返回的登录方式列表映射为：

```swift
struct AccountIdentityStatus: Equatable, Sendable {
    let provider: AccountIdentityProvider
    let bound: Bool
    let maskedValue: String
    let modifiable: Bool
    let bindable: Bool
}
```

接口顶层建议保留真实 bundle 与服务端身份作用域：

```swift
struct AccountIdentityList: Equatable, Sendable {
    let accountID: Int64
    let bundleID: String
    let identityScope: String
    let identities: [AccountIdentityStatus]
}
```

账号 profile 建议扩展：

```swift
struct AccountProfile {
    ...
    let identities: [AccountIdentityStatus]
}
```

如果服务端将登录方式列表做成独立接口，客户端也可以将它作为单独 ViewModel 状态维护。

## 10. 接口依赖

客户端依赖服务端提供：

| 接口 | 用途 |
|---|---|
| `GET /api/v1/accounts/identities/` | 获取登录方式状态 |
| `POST /api/v1/accounts/identity-verification/request/` | 请求已有方式再认证 |
| `POST /api/v1/accounts/identity-verification/verify/` | 完成再认证，获取 ticket |
| `POST /api/v1/accounts/identities/bind/` | 绑定新登录方式 |
| `POST /api/v1/accounts/identities/change/` | 修改手机号或邮箱 |

客户端需要继续传：

```text
bundle_id
device_id
```

要求：

1. `bundle_id` 必须使用客户端真实 `Bundle.main.bundleIdentifier`。
2. 客户端不自行实现 `ACCOUNT_IDENTITY_SCOPE_ALIASES` 映射。
3. 服务端响应中的 `identity_scope` 仅用于展示、调试和日志排查。
4. 登录方式绑定状态以服务端返回为准；例如 `cn.Zhaodk.Health` 和 `cn.Zhaodk.MedicineBox` 如果被服务端配置为同一 scope，客户端在两个 App 内应展示同一套账号绑定状态。

## 11. 错误处理

| 服务端 msg | 客户端提示 |
|---|---|
| `identity_already_bound_to_active_user` | 该登录方式已绑定其他账号，无法绑定或修改 |
| `verification_ticket_expired` | 验证已过期，请重新验证 |
| `verification_ticket_used` | 验证已失效，请重新验证 |
| `target_otp_invalid` | 验证码错误，请重新输入 |
| `target_otp_expired` | 验证码已过期，请重新获取 |
| `apple_identity_change_not_supported` | Apple 登录暂不支持修改 |
| `last_identity_cannot_be_removed` | 请至少保留一种可用登录方式 |

客户端不展示服务端原始手机号、邮箱或 Apple `sub`。
客户端不使用 Apple credential payload 中的邮箱直接改写本地账号邮箱。

## 12. 安全与体验细节

1. 弹层关闭时必须清理 OTP、ticket、目标输入。
2. 切换目标登录方式时必须清空上一次 OTP。
3. ticket 过期后必须回到第一步安全认证。
4. 发送验证码按钮需要倒计时。
5. 绑定或修改提交中禁用按钮，防止重复提交。
6. 进入后台再回来时，如果 ticket 已经过期，提示重新认证。
7. 服务端返回冲突时，保留当前页面，允许用户更换目标手机号或邮箱。
8. Apple 授权取消时，不算失败，只返回上一层。

## 13. 已确认决策

### 13.1 邮箱纳入 SocialIdentity

已确认采用方案 A：服务端新增 `SocialIdentity.Provider.EMAIL`，邮箱登录、绑定、修改统一走 SocialIdentity。

客户端实现要求：

1. 邮箱绑定状态以服务端登录方式列表中的 `provider=email` 为准。
2. `auth_user.email` 或 Apple 登录响应 `email` 不能单独表示邮箱登录方式已绑定。
3. 邮箱绑定和修改都走邮箱 OTP + 服务端绑定/修改接口。
4. 邮箱绑定或修改成功后，服务端会同步更新 Django `User.email`，客户端刷新 profile 后展示新资料邮箱。
5. 未绑定 `provider=email` 时，即使 profile 中存在 email，登录方式区块仍显示邮箱“未绑定”。

### 13.2 修改手机号/邮箱时是否必须验证旧同类方式

可选方案：

| 方案 | 内容 | 建议 |
|---|---|---|
| A，推荐 | 任一已绑定方式认证通过即可修改 | 可用性好，符合“已有认证方式”描述 |
| B | 修改手机号必须先验证旧手机号，修改邮箱必须先验证旧邮箱 | 安全感更强，但旧手机号/邮箱不可用时无法修改 |
| C | 高风险账号要求验证两种方式 | 复杂度高，后续风控再做 |

### 13.3 Apple 是否允许解绑

已确认采用方案 A：本期 Apple 只支持绑定，不支持修改或解绑。

客户端实现要求：

1. Apple 未绑定时展示“绑定”入口。
2. Apple 已绑定时只展示“已绑定”状态。
3. 不展示 Apple 修改入口。
4. 不展示 Apple 解绑入口。
5. 如果服务端返回 `apple_identity_change_not_supported`，展示“Apple 登录暂不支持修改”。

## 14. 验收标准

1. 账号管理页展示手机号、邮箱、Apple 三种登录方式。
2. 未绑定方式展示绑定入口。
3. 已绑定手机号、邮箱展示修改入口。
4. 已绑定 Apple 不展示修改入口。
5. 点击绑定或修改后，必须先完成已有方式安全认证。
6. 安全认证通过后，进入目标方式验证页面。
7. 目标验证通过后，客户端调用服务端绑定或修改接口。
8. 绑定或修改成功后，账号管理页刷新并展示最新状态。
9. 目标已绑定其他 active 用户时，客户端展示明确错误。
10. 取消流程、验证码错误、ticket 过期、Apple 授权取消都有可恢复路径。
11. Apple 登录返回 email 时，账号管理页邮箱绑定状态仍以登录方式列表接口为准，不误显示为邮箱已绑定。
12. 用户已有邮箱时，Apple 登录返回不同 email 后，客户端不在本地覆盖已有邮箱展示。
13. Health 与 MedicineBox 被服务端配置为共享 scope 时，两个 App 的账号管理页展示同一套手机号、邮箱、Apple 绑定状态。
14. profile 存在资料邮箱但 identities 中 `provider=email.bound=false` 时，登录方式区块必须显示邮箱未绑定。
15. 用户主动绑定或修改邮箱成功后，资料邮箱展示与邮箱登录方式掩码值同步刷新。

## 15. 代码改动清单与实现方案

### 15.1 必改文件

| 文件 | 改动 |
|---|---|
| `SparkClient/Projects/Core/Networking/Backend.swift` | 新增 `let accountIdentity: SparkAccountIdentityAPI` 并在两个 init 中初始化 |
| `SparkClient/Projects/Core/Networking/API/Account/AccountIdentityAPI.swift` | 新增账号登录方式管理 API |
| `SparkClient/Projects/Features/AccountManagement/Domain/AccountDeactivationModels.swift` | 拆出或新增账号身份模型：provider、identity status、ticket、operation、flow state |
| `SparkClient/Projects/Features/AccountManagement/Domain/AccountManagementRepository.swift` | 扩展 identities、verification、bind、change 方法 |
| `SparkClient/Projects/Features/AccountManagement/Infrastructure/DefaultAccountManagementRepository.swift` | 对接 `backend.accountIdentity`，保留现有注销能力 |
| `SparkClient/Projects/Features/AccountManagement/Application/*` | 新增 `LoadAccountIdentitiesUseCase`、`RequestIdentityReauthUseCase`、`VerifyIdentityReauthUseCase`、`BindAccountIdentityUseCase`、`ChangeAccountIdentityUseCase` |
| `SparkClient/Projects/Features/AccountManagement/Presentation/AccountManagementViewModel.swift` | 新增登录方式列表加载、绑定/修改 flow state、ticket 管理、提交逻辑 |
| `SparkClient/Projects/Features/AccountManagement/Presentation/AccountManagementView.swift` | 新增登录方式 section，挂载绑定/修改入口和 overlay |
| `SparkClient/Projects/Features/AccountManagement/Presentation/Components/AccountManagementComponents.swift` | 复用认证卡片，新增登录方式行、目标输入卡片、绑定/修改提交卡片 |
| `SparkClient/Projects/App/Sources/App/AppContainer.swift` | 注入新增 use case 到 `AccountManagementViewModel` |
| `SparkClient/Projects/Core/Networking/BackendErrorLocalizer.swift` | 增加账号绑定相关错误本地化 |
| 本地化资源 | 新增账号绑定、修改、错误提示文案 |

### 15.2 新增 SparkAccountIdentityAPI

新增文件：

```text
SparkClient/SparkClient/Projects/Core/Networking/API/Account/AccountIdentityAPI.swift
```

结构与 `SparkDeactivationAPI`、`SparkOTPAPI` 保持一致：

```swift
struct SparkAccountIdentityAPI {
    let configuration: SparkBackendConfiguration

    func listIdentities(bundleId: String) async throws -> AccountIdentityListResult
    func requestVerification(_ request: IdentityVerificationRequest) async throws -> VerificationRequestResult
    func verifyAndIssueTicket(_ request: IdentityVerificationVerifyRequest) async throws -> VerificationTicketResult
    func bindIdentity(_ request: BindIdentityRequest) async throws -> AccountIdentityListResult
    func changeIdentity(_ request: ChangeIdentityRequest) async throws -> AccountIdentityListResult
}
```

接口路径：

```text
GET  /api/v1/accounts/identities/
POST /api/v1/accounts/identity-verification/request/
POST /api/v1/accounts/identity-verification/verify/
POST /api/v1/accounts/identities/bind/
POST /api/v1/accounts/identities/change/
```

网络策略：

1. 全部 `requiresAuth=true`。
2. `allowETag=false`。
3. `bind/change/verify` 使用非幂等请求，禁用自动重复提交。
4. `serialKey` 使用账号维度串行，例如 `account.identity.bind`、`account.identity.change`。
5. 所有请求都传真实 `bundle_id` 和 `device_id`。

### 15.3 Backend 挂载

修改：

```text
SparkClient/SparkClient/Projects/Core/Networking/Backend.swift
```

新增属性：

```swift
let accountIdentity: SparkAccountIdentityAPI
```

两个 init 都需要初始化：

```swift
self.accountIdentity = SparkAccountIdentityAPI(configuration: configuration)
```

### 15.4 Domain 模型

建议新增独立文件，避免继续把非注销模型塞进 `AccountDeactivationModels.swift`：

```text
SparkClient/SparkClient/Projects/Features/AccountManagement/Domain/AccountIdentityModels.swift
```

模型：

```swift
enum AccountIdentityProvider: String, Codable, Sendable {
    case phone
    case email
    case apple
}

struct AccountIdentityStatus: Equatable, Sendable {
    let provider: AccountIdentityProvider
    let bound: Bool
    let maskedValue: String
    let modifiable: Bool
    let bindable: Bool
}

struct AccountIdentityList: Equatable, Sendable {
    let accountID: Int64
    let bundleID: String
    let identityScope: String
    let identities: [AccountIdentityStatus]
}

enum AccountIdentityOperation: Equatable, Sendable {
    case bind(AccountIdentityProvider)
    case change(AccountIdentityProvider)
}
```

DTO 与 Domain 分离：

1. API Result 使用 `Decodable`，字段按 snake_case 映射。
2. Repository 负责转成 Domain 模型。
3. UI 不直接读取网络 DTO。

### 15.5 Repository 与 UseCase

修改：

```text
SparkClient/SparkClient/Projects/Features/AccountManagement/Domain/AccountManagementRepository.swift
```

新增方法：

```swift
func loadIdentities(session: UserSession?) async throws -> AccountIdentityList
func requestIdentityVerification(provider: AccountIdentityProvider, purpose: String, session: UserSession?) async throws -> AccountVerificationRequestContext
func verifyIdentityVerification(...) async throws -> VerificationTicket
func bindIdentity(...) async throws -> AccountIdentityList
func changeIdentity(...) async throws -> AccountIdentityList
```

`DefaultAccountManagementRepository` 实现：

1. `bundleId = Bundle.main.bundleIdentifier ?? "SparkClient"`。
2. `deviceId = SparkKeychain.getOrCreateDeviceID()`。
3. 不在客户端做 `ACCOUNT_IDENTITY_SCOPE_ALIASES` 映射。
4. 成功后返回服务端最新 identity list。

新增 use case 文件：

```text
LoadAccountIdentitiesUseCase.swift
RequestIdentityVerificationUseCase.swift
VerifyIdentityVerificationUseCase.swift
BindAccountIdentityUseCase.swift
ChangeAccountIdentityUseCase.swift
```

### 15.6 ViewModel 实现

修改：

```text
SparkClient/SparkClient/Projects/Features/AccountManagement/Presentation/AccountManagementViewModel.swift
```

新增状态：

```swift
@Published private(set) var identityList: AccountIdentityList?
@Published private(set) var identityFlowState: AccountIdentityFlowState = .idle
@Published var identityTargetInput = ""
@Published var identityTargetOTPCode = ""
```

加载：

1. `load(session:)` 继续加载 profile。
2. 同时调用 `loadIdentitiesUseCase`。
3. 绑定/修改成功后只刷新 identities；如服务端返回 profile/session 再同步更新。

状态机：

```swift
enum AccountIdentityFlowState: Equatable {
    case idle
    case choosingReauth(AccountIdentityOperation)
    case reauthOTP(AccountIdentityOperation, AccountVerificationChannel, otpID: String)
    case reauthApple(AccountIdentityOperation)
    case enteringTarget(AccountIdentityOperation, ticket: String)
    case targetOTP(AccountIdentityOperation, ticket: String, otpID: String)
    case submitting
    case completed
    case failed(String)
}
```

关键方法：

```swift
func beginBind(_ provider: AccountIdentityProvider)
func beginChange(_ provider: AccountIdentityProvider)
func requestReauth(_ channel: AccountVerificationChannel) async
func verifyReauthOTPIfReady()
func completeAppleReauth(...)
func requestTargetOTP() async
func submitBindOrChange() async
func cancelIdentityFlow()
```

注意：

1. 绑定/修改 flow 与注销 flow 分离，不复用 `AccountDeactivationFlowState`。
2. 任何 ticket 过期、接口失败、取消都清理目标输入和 OTP。
3. `availableVerificationChannels` 改为从 `identityList.identities where bound=true` 生成，不再只看 `profile.signInMethod`。

### 15.7 View 与组件实现

修改：

```text
SparkClient/SparkClient/Projects/Features/AccountManagement/Presentation/AccountManagementView.swift
```

新增 section：

```swift
private func identitySection(_ identities: AccountIdentityList) -> some View
```

UI 行：

```swift
AccountIdentityRow(
    provider: status.provider,
    bound: status.bound,
    maskedValue: status.maskedValue,
    bindable: status.bindable,
    modifiable: status.modifiable,
    onBind: { viewModel.beginBind(status.provider) },
    onChange: { viewModel.beginChange(status.provider) }
)
```

新增组件建议放在：

```text
SparkClient/SparkClient/Projects/Features/AccountManagement/Presentation/Components/AccountManagementComponents.swift
```

组件：

1. `AccountIdentityRow`
2. `IdentityTargetInputCard`
3. `IdentityTargetOTPCard`
4. `IdentityOperationResultCard`

复用现有：

1. `VerificationMethodCard`
2. `OTPVerificationCard`
3. `AppleReauthCard`

### 15.8 Apple 绑定实现细节

客户端 Apple 绑定和 Apple 再认证都使用 `SignInWithAppleButton`。

要求：

1. 再认证 Apple 时不请求 email/fullName scope。
2. 绑定 Apple 时也不依赖 email 作为邮箱绑定状态。
3. Apple 绑定成功后刷新 identities。
4. Apple 已绑定时不展示修改/解绑按钮。

### 15.9 错误本地化

修改：

```text
SparkClient/SparkClient/Projects/Core/Networking/BackendErrorLocalizer.swift
```

新增映射：

| msg | 文案 |
|---|---|
| `identity_already_bound_to_active_user` | 该登录方式已绑定其他账号，无法绑定或修改 |
| `verification_ticket_expired` | 验证已过期，请重新验证 |
| `verification_ticket_used` | 验证已失效，请重新验证 |
| `verification_ticket_invalid` | 验证无效，请重新验证 |
| `identity_not_bound` | 当前账号尚未绑定该登录方式 |
| `apple_identity_change_not_supported` | Apple 登录暂不支持修改 |

### 15.10 测试与联调

客户端至少覆盖：

1. Health 登录后绑定邮箱，MedicineBox 打开账号管理页展示同一邮箱已绑定。
2. 未绑定手机号点击绑定：旧方式认证 -> 新手机号 OTP -> 绑定成功。
3. 已绑定邮箱点击修改：旧方式认证 -> 新邮箱 OTP -> 修改成功。
4. Apple 已绑定只展示状态，不出现修改入口。
5. 服务端返回 `identity_already_bound_to_active_user` 时留在目标输入页。
6. ticket 过期后回到再认证步骤。
7. Apple 登录返回 email 但没有 `provider=email` 时，邮箱登录方式显示未绑定。
8. 邮箱绑定成功后，资料邮箱与登录方式邮箱同时刷新。

## 16. 建议拆分任务

| 任务 | 负责人 | 说明 |
|---|---|---|
| 登录方式列表 UI | iOS | 在账号管理页新增三类登录方式展示 |
| 身份管理状态机 | iOS | 新增绑定/修改专用 flow state |
| 再认证流程接入 | iOS | 复用手机号、邮箱、Apple 认证组件 |
| 目标方式绑定页面 | iOS | 手机号、邮箱、Apple 三类目标验证 |
| 修改手机号/邮箱页面 | iOS | 新目标输入、OTP、提交 |
| 接口 Repository / UseCase | iOS | 对接 identities、verification、bind、change |
| 本地化错误提示 | iOS | 覆盖冲突、过期、验证码错误 |
| 联调测试 | iOS + 后端 | 覆盖绑定、修改、冲突、注销用户释放 |
