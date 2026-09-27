# ACCOUNT-EMAIL-INPUT-000001 账号管理邮箱输入与邮箱后缀选择需求工单

## 1. 背景

账号管理里的邮箱绑定、邮箱修改流程，目前目标邮箱输入仍是普通 `TextField`。

当前输入方式能完成基础录入，但没有针对邮箱场景做优化：

- 用户需要完整输入邮箱地址。
- 常见邮箱后缀没有快捷选择。
- 粘贴完整邮箱后，不能自动拆分用户名和后缀。
- 发验证码后，邮箱目标缺少明确锁定态。
- 邮箱大小写、空格、中文符号、重复 `@` 等输入异常没有统一处理。

本工单要求把邮箱输入升级为“前缀输入 + 后缀选择/自定义”的专用组件，体验向主流邮箱注册/登录输入框看齐。

## 2. 工单目标

1. 账号管理绑定邮箱、修改邮箱页使用专用邮箱输入框。
2. 输入框前半部分录入邮箱用户名，后半部分通过 `Menu` 选择主流邮箱后缀。
3. 用户可以选择“自定义后缀”，手动录入非主流邮箱域名。
4. 用户粘贴完整邮箱时，自动解析用户名和后缀。
5. 自动处理大小写、首尾空格、中文 `＠`、多余空格等常见输入问题。
6. 点击获取邮箱验证码成功后，锁定发码邮箱，验证码提交必须使用发码时冻结的邮箱。
7. 邮箱绑定/修改的目标邮箱统一输出规范化后的 lowercase email。

## 3. 适用范围

客户端范围：

- 账号管理邮箱绑定。
- 账号管理邮箱修改。
- 账号管理目标邮箱验证码发送。
- 账号管理目标邮箱验证码校验。

不在本工单范围：

- 服务端邮箱唯一性检查。
- `SocialIdentity(provider=email)` 服务端绑定/修改规则。
- 邮箱登录页整体重构。
- 完整邮箱 DNS/MX 校验。
- 企业邮箱复杂规则校验。

## 4. 当前关键代码

账号管理当前待改位置：

- `SparkClient/SparkClient/Projects/Features/AccountManagement/Presentation/Components/AccountManagementComponents.swift`
  - `IdentityTargetInputCard`
  - 当前 `.email` 分支是普通 `TextField`
- `SparkClient/SparkClient/Projects/Features/AccountManagement/Presentation/AccountManagementView.swift`
  - `.enteringTarget`
  - `.targetOTP`
- `SparkClient/SparkClient/Projects/Features/AccountManagement/Presentation/AccountManagementViewModel.swift`
  - `identityTargetInput`
  - `canRequestIdentityTargetOTP`
  - `requestTargetOTP()`
  - `submitIdentityTargetOTPIfReady()`
  - `identityTargetOTPDisplayValue`
  - `clearIdentityFlowInputs(...)`
- `SparkClient/SparkClient/Projects/Features/AccountManagement/Domain/AccountIdentityModels.swift`
  - `AccountIdentityTargetSnapshot.email(String)`
  - `AccountIdentityBindProof.email(...)`
- `SparkClient/SparkClient/Projects/Features/AccountManagement/Infrastructure/DefaultAccountManagementRepository.swift`
  - `requestTargetOTP(provider:target:operation:session:)`

相关工单：

- `SparkClient/需求文档/账号/ACCOUNT-LINKING-000001-账号管理登录方式绑定与修改客户端需求工单.md`
- `SparkClient/需求文档/账号/ACCOUNT-PHONE-INPUT-000001-账号管理手机号输入与验证码号码锁定需求工单.md`

## 5. 现状问题

### 5.1 邮箱输入成本高

用户绑定或修改邮箱时，需要完整输入：

```text
username@qq.com
username@163.com
username@gmail.com
```

常见后缀重复输入成本高，移动端键盘下切换符号输入也容易出错。

### 5.2 粘贴完整邮箱没有结构化处理

用户直接粘贴完整邮箱时，理想行为应是：

```text
粘贴：hua@qq.com

用户名输入框：hua
后缀选择器：@qq.com
最终邮箱：hua@qq.com
```

当前普通 `TextField` 无法区分用户名和后缀，也无法让后续 UI 明确展示后缀状态。

### 5.3 获取验证码后缺少邮箱快照锁定

邮箱 OTP 和手机号 OTP 一样，验证码与目标邮箱强绑定。

如果发码后还能修改输入框，可能出现：

- 验证码发送给 A 邮箱。
- 提交绑定/修改时使用 B 邮箱。
- 服务端校验失败或用户感知混乱。

因此邮箱发码成功后也必须锁定目标邮箱快照。

## 6. 产品要求

### 6.1 邮箱输入框结构

邮箱输入框采用“用户名 + 后缀选择”的组合输入：

```text
┌───────────────────┬──────────────┐
│ username          │ @qq.com   v  │
└───────────────────┴──────────────┘
```

要求：

- 左侧输入邮箱用户名 local-part。
- 右侧展示后缀选择 `Menu`。
- 后缀选项包含主流邮箱后缀。
- 支持自定义后缀。
- 最终提交邮箱由 `localPart + selectedDomain` 组合。
- 输入框键盘使用 `emailAddress`。
- 禁止自动大写。
- 禁止自动纠错。
- 支持 `textContentType(.emailAddress)`。

### 6.2 主流邮箱后缀

默认后缀列表建议：

```text
@qq.com
@163.com
@126.com
@gmail.com
@outlook.com
@hotmail.com
@icloud.com
@foxmail.com
@sina.com
@yeah.net
```

排序建议：

1. 国内用户默认优先 `@qq.com`、`@163.com`、`@126.com`、`@foxmail.com`。
2. 非国内用户默认优先 `@gmail.com`、`@outlook.com`、`@hotmail.com`、`@icloud.com`。
3. 使用 `SparkSystemInfo.shared.mostLikelyCountryCode` 做默认排序即可，不做复杂推荐系统。

### 6.3 自定义后缀

`Menu` 里必须提供“自定义后缀”：

```swift
Menu {
    Button("@qq.com") { ... }
    Button("@163.com") { ... }
    Button("@gmail.com") { ... }
    Divider()
    Button("自定义后缀") { ... }
}
```

选择“自定义后缀”后：

- 右侧区域变成可输入后缀。
- 用户可以输入 `company.com` 或 `@company.com`。
- 客户端统一规范化为 `@company.com`。
- 自定义后缀可以临时加入当前页后缀显示。
- 不要求持久化用户自定义后缀历史。

自定义后缀输入 UI：

```text
┌───────────────────┬──────────────────┐
│ username          │ @ company.com    │
└───────────────────┴──────────────────┘
```

### 6.4 粘贴完整邮箱自动解析

用户在用户名输入框粘贴完整邮箱时：

```text
hua@qq.com
hua@163.com
hua@gmail.com
hua@company.com
```

客户端需要自动拆分：

```text
localPart = "hua"
domain = "@qq.com"
normalizedEmail = "hua@qq.com"
```

规则：

1. 如果粘贴内容包含一个 `@` 或中文 `＠`，尝试解析为完整邮箱。
2. `@` 前作为 local-part。
3. `@` 后作为 domain。
4. domain 命中主流后缀列表时，自动选中该后缀。
5. domain 未命中主流后缀列表时，切换为自定义后缀模式并填入该 domain。
6. 解析成功后，左侧输入框只展示 local-part。
7. 最终提交邮箱使用规范化完整邮箱。

示例：

| 用户粘贴 | local-part | 后缀状态 | 最终邮箱 |
| --- | --- | --- | --- |
| `hua@qq.com` | `hua` | 选中 `@qq.com` | `hua@qq.com` |
| `hua@163.com` | `hua` | 选中 `@163.com` | `hua@163.com` |
| `hua@gmail.com` | `hua` | 选中 `@gmail.com` | `hua@gmail.com` |
| `hua@company.com` | `hua` | 自定义 `@company.com` | `hua@company.com` |
| ` Hua＠QQ.COM ` | `hua` | 选中 `@qq.com` | `hua@qq.com` |

### 6.5 用户手动输入完整邮箱

如果用户不是粘贴，而是手动输入到包含 `@`：

```text
hua@qq.com
```

也应触发同样解析逻辑。

触发时机：

- `onChange(of: localPart)`
- 当输入内容包含 `@` 或 `＠` 时尝试解析。

### 6.6 邮箱规范化

客户端输出给接口前做轻量规范化：

1. 去除首尾空格和换行。
2. 中文 `＠` 替换为英文 `@`。
3. domain 转小写。
4. local-part 默认转小写。
5. 移除 email 中间的普通空格。
6. 自定义后缀如果缺少 `@`，自动补齐。

说明：

- RFC 允许 local-part 大小写敏感，但现实邮箱服务基本不区分大小写。为了登录身份一致性，本项目客户端统一转小写。
- 服务端仍必须做同样规范化，客户端规范化只用于体验和减少错误。

### 6.7 获取验证码后锁定邮箱

邮箱验证码发送成功后：

- local-part 输入框不可编辑。
- 后缀 `Menu` 不可点击。
- 自定义后缀输入框不可编辑。
- 自动解析逻辑停止。
- 验证码页面展示发码时冻结的邮箱。
- 重新发送验证码使用同一个冻结邮箱。
- 验证码提交、绑定、修改提交必须使用冻结邮箱。

锁定原因：

```text
邮箱验证码和目标邮箱是一组强绑定上下文。
发码后的任何输入变化都不能影响验证码校验目标。
```

### 6.8 返回修改邮箱

验证码页点击返回：

- 清空当前 `otpID`。
- 清空冻结邮箱快照。
- 清空验证码输入。
- 回到邮箱输入页。
- 邮箱输入框恢复可编辑。
- 可以保留用户之前输入的 local-part 和 suffix，便于修正。
- 再次获取验证码时必须重新冻结邮箱。

## 7. 推荐体验细节

### 7.1 主流邮箱输入框体验对齐

向主流好用邮箱输入框看齐，需要具备以下体验：

- 用户输入 `@` 后自动理解为完整邮箱。
- 后缀区域明确可点，不让用户猜测是否能选择。
- 常见后缀一键切换，不需要删除重输。
- 自定义域名入口清晰，不把企业邮箱用户卡死。
- 错误提示尽量靠近输入框。
- 邮箱不合法时，获取验证码按钮置灰。
- 用户输入完整邮箱后，不重复展示 `@qq.com@qq.com`。
- 用户输入后缀大小写时，自动统一为小写。
- 输入 `hua@` 时提示“请选择或输入邮箱后缀”。
- 输入 `@qq.com` 时提示“请输入邮箱用户名”。

### 7.2 后缀推荐交互

建议 `Menu` 显示：

```text
@qq.com
@163.com
@126.com
@gmail.com
@outlook.com
@hotmail.com
@icloud.com
@foxmail.com
自定义后缀...
```

如果用户 local-part 中已经输入 `hua@gm`：

- 可解析为 local-part `hua`。
- 后缀输入进入自定义模式 `@gm`。
- 不做强制补全为 `@gmail.com`。

原因：避免误改用户输入。可在后续版本增加“你是否想输入 @gmail.com”的建议。

### 7.3 错误提示

错误提示示例：

| 场景 | 提示 |
| --- | --- |
| local-part 为空 | 请输入邮箱用户名 |
| 后缀为空 | 请选择或输入邮箱后缀 |
| 后缀不包含 `.` | 邮箱后缀格式不正确 |
| 邮箱包含多个 `@` | 邮箱格式不正确 |
| 邮箱过长 | 邮箱长度过长 |
| 发码失败 | 验证码发送失败，请稍后重试 |
| 邮箱已被绑定 | 该邮箱已绑定其他账号，无法绑定 |

## 8. 技术方案

### 8.1 新增 EmailAddressInputModel

建议新增路径：

```text
SparkClient/SparkClient/Projects/Core/UI/EmailAddress/EmailAddressInputView.swift
SparkClient/SparkClient/Projects/Core/UI/EmailAddress/EmailAddressNormalizer.swift
```

模型：

```swift
struct EmailAddressInputModel: Equatable, Sendable {
    var localPart: String = ""
    var selectedDomain: String = "@qq.com"
    var customDomain: String = ""
    var isCustomDomain: Bool = false
    var normalizedEmail: String = ""
    var isValid: Bool = false
    var validationMessage: String?
}
```

说明：

- `localPart`：邮箱 `@` 前面的部分。
- `selectedDomain`：主流后缀，例如 `@qq.com`。
- `customDomain`：自定义后缀，例如 `@company.com`。
- `isCustomDomain`：是否处于自定义后缀模式。
- `normalizedEmail`：最终提交邮箱。
- `isValid`：是否满足发码基础格式。

### 8.2 新增 EmailAddressNormalizer

建议能力：

```swift
enum EmailAddressNormalizer {
    struct Parsed: Equatable, Sendable {
        let localPart: String
        let domain: String
        let normalizedEmail: String
        let isKnownDomain: Bool
    }

    static func normalize(localPart: String, domain: String) -> String
    static func parseFullEmail(_ raw: String, knownDomains: [String]) -> Parsed?
    static func normalizeDomain(_ raw: String) -> String
    static func validate(localPart: String, domain: String) -> ValidationResult
}
```

基础实现规则：

```swift
static func normalizeDomain(_ raw: String) -> String {
    let trimmed = raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "＠", with: "@")
        .lowercased()

    if trimmed.isEmpty { return "" }
    return trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
}
```

完整邮箱解析：

```swift
static func parseFullEmail(_ raw: String, knownDomains: [String]) -> Parsed? {
    let compact = raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "＠", with: "@")
        .replacingOccurrences(of: " ", with: "")
        .lowercased()

    let parts = compact.split(separator: "@", omittingEmptySubsequences: false)
    guard parts.count == 2 else { return nil }
    guard parts[0].isEmpty == false, parts[1].isEmpty == false else { return nil }

    let local = String(parts[0])
    let domain = "@\(parts[1])"
    return Parsed(
        localPart: local,
        domain: domain,
        normalizedEmail: "\(local)\(domain)",
        isKnownDomain: knownDomains.contains(domain)
    )
}
```

### 8.3 新增 EmailAddressInputView

组件接口：

```swift
struct EmailAddressInputView: View {
    @Binding var model: EmailAddressInputModel
    var knownDomains: [String] = DefaultEmailDomains.ordered
    var isLocked: Bool = false
}
```

组件职责：

- 渲染 local-part 输入。
- 渲染后缀选择 `Menu`。
- 支持自定义后缀输入。
- 监听 local-part 中的完整邮箱粘贴。
- 输出 `normalizedEmail` 和 `isValid`。
- 锁定时禁止输入和后缀切换。

### 8.4 主流邮箱后缀列表

建议新增：

```swift
enum DefaultEmailDomains {
    static let mainlandChina: [String] = [
        "@qq.com",
        "@163.com",
        "@126.com",
        "@foxmail.com",
        "@sina.com",
        "@yeah.net",
        "@icloud.com",
        "@outlook.com",
        "@hotmail.com",
        "@gmail.com"
    ]

    static let global: [String] = [
        "@gmail.com",
        "@outlook.com",
        "@hotmail.com",
        "@icloud.com",
        "@qq.com",
        "@163.com",
        "@126.com",
        "@foxmail.com",
        "@sina.com",
        "@yeah.net"
    ]

    static var ordered: [String] {
        SparkSystemInfo.shared.isMostLikelyMainlandChina ? mainlandChina : global
    }
}
```

### 8.5 ViewModel 状态改造

当前：

```swift
@Published var identityTargetInput = ""
```

建议新增：

```swift
@Published var identityTargetInput = ""
@Published var identityTargetEmailInput = EmailAddressInputModel()
@Published private(set) var lockedIdentityTargetEmail: LockedEmailTarget?
```

新增：

```swift
struct LockedEmailTarget: Equatable, Sendable {
    let email: String
    let displayValue: String
}
```

说明：

- `identityTargetInput` 可逐步退役，或保留给兼容旧逻辑。
- 邮箱 provider 使用 `identityTargetEmailInput.normalizedEmail`。
- 发码成功后写入 `lockedIdentityTargetEmail`。
- OTP 提交使用锁定邮箱，不回读输入框。

### 8.6 FlowState 目标快照

如果手机号工单已调整为：

```swift
case targetOTP(
    AccountIdentityOperation,
    ticket: String,
    otpID: String,
    target: AccountIdentityTargetSnapshot
)
```

则邮箱继续复用：

```swift
enum AccountIdentityTargetSnapshot: Equatable, Sendable {
    case phone(LockedPhoneTarget)
    case email(LockedEmailTarget)
}
```

如果当前仍是：

```swift
case email(String)
```

建议升级为：

```swift
case email(LockedEmailTarget)
```

最低要求：

- `targetOTP` 状态内必须保存发码时邮箱。
- 重新发送和提交验证码不能重新读取输入框。

### 8.7 canRequestIdentityTargetOTP

邮箱 provider：

```swift
case .email:
    return identityTargetEmailInput.isValid
```

不再用：

```swift
identityTargetInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
```

原因：

- 非空不等于邮箱合法。
- 后缀选择和自定义后缀需要组合后判断。

### 8.8 requestTargetOTP()

邮箱 provider：

```swift
case .email:
    let email = identityTargetEmailInput.normalizedEmail
    guard identityTargetEmailInput.isValid, email.isEmpty == false else { return }

    do {
        let context = try await requestTargetOTP(
            provider: .email,
            target: email,
            operation: operation
        )
        let locked = LockedEmailTarget(email: email, displayValue: email)
        lockedIdentityTargetEmail = locked
        identityFlowState = .targetOTP(
            operation,
            ticket: ticket,
            otpID: context.otpID,
            target: .email(locked)
        )
        startIdentityCountdown(seconds: min(max(context.expiresIn, 30), 120))
    } catch {
        lockedIdentityTargetEmail = nil
        handleIdentityOperationError(error, operation: operation, ticket: ticket)
    }
```

### 8.9 submitIdentityTargetOTPIfReady()

邮箱 provider 不再读取当前输入框：

```swift
case (.email, .email(let emailTarget)):
    let proof = AccountIdentityBindProof.email(
        target: emailTarget.email,
        otpID: otpID,
        code: identityTargetOTPCode
    )
```

修改邮箱：

```swift
case (.email, .email(let emailTarget)):
    await submitBindOrChange(
        operation: operation,
        ticket: ticket,
        changeTarget: emailTarget.email,
        changeOtpID: otpID,
        changeCode: identityTargetOTPCode,
        provider: .email
    )
```

## 9. UI 线框

### 9.1 绑定邮箱

```text
┌────────────────────────────────────────┐
│ 绑定邮箱                                │
│ 请输入要绑定到当前账号的邮箱。           │
│                                        │
│ 邮箱                                    │
│ ┌───────────────────┬──────────────┐   │
│ │ username          │ @qq.com   v  │   │
│ └───────────────────┴──────────────┘   │
│                                        │
│ [ 获取邮箱验证码 ]                      │
│                                        │
│ 返回                                    │
└────────────────────────────────────────┘
```

### 9.2 后缀选择

```text
┌───────────────────┬──────────────┐
│ username          │ @qq.com   v  │
└───────────────────┴──────────────┘

Menu
────────────────
@qq.com
@163.com
@126.com
@gmail.com
@outlook.com
@hotmail.com
@icloud.com
@foxmail.com
────────────────
自定义后缀...
```

### 9.3 自定义后缀

```text
┌────────────────────────────────────────┐
│ 绑定邮箱                                │
│                                        │
│ 邮箱                                    │
│ ┌───────────────────┬────────────────┐ │
│ │ hua               │ @company.com   │ │
│ └───────────────────┴────────────────┘ │
│                                        │
│ [ 获取邮箱验证码 ]                      │
└────────────────────────────────────────┘
```

### 9.4 粘贴完整邮箱

用户粘贴：

```text
hua@qq.com
```

界面自动变为：

```text
┌───────────────────┬──────────────┐
│ hua               │ @qq.com   v  │
└───────────────────┴──────────────┘
```

提交给接口：

```text
hua@qq.com
```

### 9.5 验证码已发送，邮箱锁定

```text
┌────────────────────────────────────────┐
│ 验证邮箱                                │
│ 验证码已发送至 hua@qq.com               │
│                                        │
│ ┌────┬────┬────┬────┬────┬────┐       │
│ │ 1  │ 2  │ 3  │ 4  │ 5  │ 6  │       │
│ └────┴────┴────┴────┴────┴────┘       │
│                                        │
│ 52 秒后可重新发送                      │
│ 邮箱已锁定，如需修改请返回上一步。      │
│                                        │
│ [ 返回修改邮箱 ]                        │
└────────────────────────────────────────┘
```

## 10. 接口请求要求

### 10.1 请求目标邮箱验证码

```json
{
  "provider": "email",
  "target": "hua@qq.com",
  "scene": "identity_bind"
}
```

或：

```json
{
  "provider": "email",
  "target": "hua@qq.com",
  "scene": "identity_change"
}
```

### 10.2 提交绑定

```json
{
  "provider": "email",
  "verification_ticket": "...",
  "proof": {
    "type": "email",
    "target": "hua@qq.com",
    "otp_id": "...",
    "code": "123456"
  }
}
```

`proof.target` 必须等于发码请求时的 `target`。

### 10.3 提交修改

```json
{
  "provider": "email",
  "verification_ticket": "...",
  "new_target": "hua@qq.com",
  "new_otp_id": "...",
  "new_code": "123456"
}
```

`new_target` 必须等于发码请求时的 `target`。

## 11. 校验规则

客户端做轻量校验，不替代服务端校验。

基础合法条件：

- local-part 非空。
- domain 非空。
- domain 以 `@` 开头。
- domain 包含 `.`。
- 完整邮箱只包含一个 `@`。
- 完整邮箱长度不超过 254。
- local-part 长度不超过 64。
- domain 中不包含空格。

不做复杂校验：

- 不校验 MX 记录。
- 不校验邮箱是否真实存在。
- 不完整实现 RFC 5322。
- 不支持引号 local-part，例如 `"name"@example.com`。

## 12. 错误处理

| 场景 | 客户端处理 |
| --- | --- |
| local-part 为空 | 获取验证码按钮置灰，提示请输入邮箱用户名 |
| 后缀为空 | 获取验证码按钮置灰，提示请选择或输入邮箱后缀 |
| 后缀无 `.` | 获取验证码按钮置灰，提示邮箱后缀格式不正确 |
| 多个 `@` | 不拆分，提示邮箱格式不正确 |
| 发码失败 | 不锁定邮箱，保留输入页 |
| 发码成功 | 锁定邮箱，进入验证码页 |
| 验证码错误 | 保持验证码页，邮箱继续锁定 |
| 验证码过期 | 保持验证码页，允许重新发送到同一冻结邮箱 |
| 用户要换邮箱 | 必须返回输入页重新获取验证码 |

## 13. 验收标准

1. 账号管理绑定邮箱页展示“用户名 + 后缀选择”的组合邮箱输入框。
2. 账号管理修改邮箱页展示“用户名 + 后缀选择”的组合邮箱输入框。
3. 后缀 `Menu` 包含主流邮箱后缀。
4. 后缀 `Menu` 包含“自定义后缀”入口。
5. 用户可以输入自定义后缀 `company.com`，客户端规范化为 `@company.com`。
6. 粘贴 `hua@qq.com` 后，local-part 显示 `hua`，后缀选中 `@qq.com`。
7. 粘贴 `hua@company.com` 后，local-part 显示 `hua`，后缀进入自定义 `@company.com`。
8. 粘贴 ` Hua＠QQ.COM ` 后，最终邮箱为 `hua@qq.com`。
9. 输入不合法邮箱时，获取验证码按钮不可点击。
10. 点击获取验证码成功后，邮箱输入框不可编辑。
11. 点击获取验证码成功后，后缀 `Menu` 不可点击。
12. 验证码页展示的邮箱来自发码时冻结快照。
13. 验证码提交时使用发码时冻结的邮箱，不重新读取输入框。
14. 重新发送验证码使用同一个冻结邮箱。
15. 返回输入页后可以修改邮箱，但必须重新获取验证码。
16. 手机号绑定/修改流程不受邮箱输入组件影响。
17. Apple 绑定流程不受邮箱输入组件影响。

## 14. 测试用例

### 14.1 Normalizer 单元测试

| 输入 | 期望 local-part | 期望 domain | 期望 email |
| --- | --- | --- | --- |
| `hua@qq.com` | `hua` | `@qq.com` | `hua@qq.com` |
| `HUA@QQ.COM` | `hua` | `@qq.com` | `hua@qq.com` |
| ` Hua＠QQ.COM ` | `hua` | `@qq.com` | `hua@qq.com` |
| `hua@company.com` | `hua` | `@company.com` | `hua@company.com` |
| `hua@` | invalid | invalid | invalid |
| `@qq.com` | invalid | `@qq.com` | invalid |
| `hua@qq` | `hua` | `@qq` | invalid |
| `hua@qq.com@qq.com` | invalid | invalid | invalid |

### 14.2 ViewModel 测试

1. 邮箱 provider 的 `canRequestIdentityTargetOTP` 使用 `identityTargetEmailInput.isValid`。
2. `requestTargetOTP()` 对邮箱 provider 使用 `identityTargetEmailInput.normalizedEmail`。
3. 发码成功后 `AccountIdentityFlowState.targetOTP` 内包含邮箱快照。
4. 发码成功后修改 `identityTargetEmailInput` 不影响提交目标。
5. `submitIdentityTargetOTPIfReady()` 使用快照中的邮箱。
6. `backToIdentityTargetInput()` 清空邮箱锁定快照。
7. 手机号 provider 仍使用手机号输入模型。

### 14.3 UI 测试

1. 邮箱绑定页显示后缀 `Menu`。
2. 邮箱修改页显示后缀 `Menu`。
3. 选择自定义后缀后，后缀区域可输入。
4. 粘贴完整邮箱后，UI 自动拆分。
5. 验证码发送成功后输入框禁用。
6. 验证码发送成功后后缀菜单禁用。
7. 返回输入页后输入框恢复可编辑。

## 15. 实施顺序

1. 新增 `EmailAddressNormalizer`。
2. 新增 `EmailAddressInputModel`。
3. 新增 `EmailAddressInputView`。
4. 为邮箱解析、规范化、校验补充单元测试。
5. 在 `AccountManagementViewModel` 增加 `identityTargetEmailInput` 和 `LockedEmailTarget`。
6. 调整邮箱 provider 的 `canRequestIdentityTargetOTP`。
7. 改造 `requestTargetOTP()` 和 `submitIdentityTargetOTPIfReady()`，邮箱使用锁定快照。
8. 改造 `IdentityTargetInputCard`，邮箱 provider 使用 `EmailAddressInputView`。
9. 补充本地化文案。
10. 回归手机号、Apple 绑定流程。

## 16. 需要补充的本地化文案

建议新增：

```text
account_management.identity.email.local_placeholder = 邮箱用户名
account_management.identity.email.domain_picker = 选择邮箱后缀
account_management.identity.email.custom_domain = 自定义后缀
account_management.identity.email.custom_domain_placeholder = company.com
account_management.identity.email.invalid = 邮箱格式不正确
account_management.identity.email.local_required = 请输入邮箱用户名
account_management.identity.email.domain_required = 请选择或输入邮箱后缀
account_management.identity.email.domain_invalid = 邮箱后缀格式不正确
account_management.identity.email.locked_hint = 验证码已发送，邮箱暂不可修改
account_management.identity.email.change_to_edit = 如需修改邮箱，请返回上一步
```

## 17. 风险与注意事项

1. 不要把普通非空字符串当作邮箱合法条件。
2. 不要在验证码页重新读取输入框生成邮箱。
3. 不要在用户输入 `hua@qq.com` 后组合出 `hua@qq.com@qq.com`。
4. 不要强制用户只能选择主流后缀，企业邮箱必须可用。
5. 客户端规范化必须和服务端规范化方向一致，否则会出现客户端显示邮箱和服务端登记邮箱不一致。
6. 邮箱绑定状态仍然只看 `SocialIdentity(provider=email)`，不能因为资料邮箱 `User.email` 存在就显示邮箱已绑定。
7. Apple 登录携带的 email 不能自动填入邮箱登录绑定流程，除非用户主动进入绑定并确认。

