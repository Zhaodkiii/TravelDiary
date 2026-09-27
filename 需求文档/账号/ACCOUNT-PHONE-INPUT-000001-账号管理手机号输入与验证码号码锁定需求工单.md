# ACCOUNT-PHONE-INPUT-000001 账号管理手机号输入与验证码号码锁定需求工单

## 1. 背景

账号管理里的手机号绑定、手机号修改流程，目标手机号输入当前仍以普通字符串 `identityTargetInput` 为主。

登录流程已经具备更完整的手机号输入体验：

- 支持选择国家/地区区号。
- 支持用户粘贴完整国际手机号后自动识别区号。
- 支持处理 `+861538...`、`00861538...`、`861538...` 等输入。
- 获取验证码后，避免自动改写手机号，防止验证码发送号码和验证号码不一致。

账号管理的手机号绑定/修改必须复用同一套能力，避免同一 App 内不同入口对手机号的处理不一致。

## 2. 工单目标

1. 账号管理手机号绑定、手机号修改页的输入框支持区号选择。
2. 账号管理手机号绑定、手机号修改页支持粘贴完整国际手机号并自动识别区号。
3. 提交“获取短信验证码”成功后，当前手机号输入框内的手机号不能再变化。
4. 验证码校验、绑定、修改提交时，必须使用发码时冻结的 E.164 手机号。
5. 手机号输入、规范化、展示规则与登录流程保持一致。

## 3. 适用范围

客户端范围：

- 账号管理手机号绑定。
- 账号管理手机号修改。
- 账号管理手机号目标验证码发送。
- 账号管理手机号目标验证码校验。

不在本工单范围：

- 服务端手机号唯一性逻辑。
- `SocialIdentity` 绑定、修改接口规则。
- Apple / 邮箱绑定输入框。
- 手机号区号完整国家库扩展。

## 4. 当前关键代码

登录流程参考实现：

- `SparkClient/SparkClient/Projects/Features/Auth/Presentation/LoginConductor.swift`
  - `PhoneLoginView.formPad`
  - `applyAutoRegionAndStripPrefixIfNeeded(_:)`
  - `requestOTP()`
  - `OTPVerifyView`

公共手机号能力：

- `SparkClient/SparkClient/Projects/Core/UI/PhoneNumber/PhoneNumberInputView.swift`
- `SparkClient/SparkClient/Projects/Core/UI/PhoneNumber/PhoneNumberNormalizer.swift`
- `SparkClient/SparkClient/Projects/Foundation/Utilities/SparkSystemInfo.swift`
  - `defaultRegions`

账号管理当前待改位置：

- `SparkClient/SparkClient/Projects/Features/AccountManagement/Presentation/AccountManagementView.swift`
  - `IdentityTargetInputCard`
  - `.enteringTarget`
  - `.targetOTP`
- `SparkClient/SparkClient/Projects/Features/AccountManagement/Presentation/AccountManagementViewModel.swift`
  - `identityTargetInput`
  - `requestTargetOTP()`
  - `submitIdentityTargetOTPIfReady()`
  - `backToIdentityTargetInput()`
  - `clearIdentityFlowInputs(...)`
- `SparkClient/SparkClient/Projects/Features/AccountManagement/Domain/AccountIdentityModels.swift`
  - `AccountIdentityFlowState.targetOTP(...)`
  - `AccountIdentityBindProof.phone(...)`
- `SparkClient/SparkClient/Projects/Features/AccountManagement/Infrastructure/DefaultAccountManagementRepository.swift`
  - `requestTargetOTP(provider:target:operation:session:)`

## 5. 现状问题

### 5.1 手机号输入能力不一致

登录流程内已经支持区号选择和国际手机号粘贴处理，但账号管理绑定/修改手机号流程没有明确复用该能力。

用户可能在登录页能输入 `+861538...`，但在账号管理里需要手动删除区号或被重复拼接区号。

### 5.2 发码号码和验证号码可能不一致

当前账号管理流程：

1. `requestTargetOTP()` 使用当前 `identityTargetInput` 请求短信验证码。
2. 进入 `.targetOTP` 后，页面仍通过 `viewModel.identityTargetInput` 展示目标手机号。
3. `submitIdentityTargetOTPIfReady()` 再次读取当前 `identityTargetInput` 作为提交目标。

如果输入值在发码后被修改、被自动格式化、被系统自动填充影响，可能出现：

- 验证码发给 A 手机号。
- 提交绑定/修改时使用 B 手机号。
- 服务端验证码校验失败或错误绑定。

### 5.3 目标手机号缺少冻结态

流程状态里只记录 `otpID`，没有记录发码时的手机号快照。

`.targetOTP(AccountIdentityOperation, ticket: String, otpID: String)` 不足以表达“验证码对应的目标手机号”。

## 6. 产品要求

### 6.1 账号管理手机号输入框

手机号绑定/修改时，目标输入框必须展示为：

```text
+-------------------------------+
| 🇨🇳 +86 v | 15385056020        |
+-------------------------------+
```

要求：

- 左侧为国家/地区选择器。
- 右侧为手机号输入框。
- 默认区号优先使用 `SparkSystemInfo.shared.mostLikelyCountryCode`。
- 无法推断时默认中国大陆 `+86`。
- 键盘使用 `phonePad`。
- 键盘工具栏提供“完成”按钮。

### 6.2 粘贴完整国际手机号

当用户输入或粘贴以下格式时，客户端需要自动处理：

```text
+8615385056020
008615385056020
8615385056020
+86 153 8505 6020
+86-153-8505-6020
(+86)15385056020
```

处理规则：

1. 清理空格、横杠、括号。
2. 识别 `+` 国际前缀。
3. 识别 `00` 国际前缀。
4. 识别无 `+` 但以支持区号开头的号码，例如 `861538...`。
5. 使用最长区号优先匹配，避免 `+886` 被误判为 `+88` 或 `+86`。
6. 自动切换区号选择器。
7. 输入框内只保留去掉区号后的 national number。
8. 对外提交统一使用 E.164，例如 `+8615385056020`。

### 6.3 获取验证码后锁定手机号

用户点击“获取验证码”并请求成功后：

- 手机号输入框不可编辑。
- 区号选择器不可点击。
- 自动识别/自动改写逻辑停止。
- 输入框显示发码时的 national number。
- OTP 页面展示发码时的 masked phone。
- 验证码校验提交必须使用发码时冻结的 E.164。
- 返回修改手机号时，应清空旧 OTP 状态，并允许用户重新编辑和重新获取验证码。

锁定原因：

```text
验证码和手机号是一组强绑定上下文。
发码后的任何输入变化都不能影响验证码校验目标。
```

### 6.4 重新发送验证码

重新发送验证码时：

- 使用同一个冻结手机号 E.164。
- 不允许从输入框重新读取手机号。
- 倒计时结束后仍保持手机号锁定。
- 用户必须返回上一步才能换手机号。

### 6.5 返回上一步

在验证码输入页点击返回：

- 清空当前 `otpID`。
- 清空冻结手机号。
- 清空验证码输入。
- 回到手机号输入页。
- 手机号输入框恢复可编辑。
- 可保留用户之前输入的手机号，便于修正；但再次获取验证码时必须重新冻结。

## 7. 技术方案

### 7.1 新增目标手机号输入状态

在账号管理 ViewModel 中新增独立手机号输入模型，不再只用 `identityTargetInput` 承载所有 provider：

```swift
@Published var identityTargetInput = ""
@Published var identityTargetPhoneInput = PhoneNumberInputModel()
@Published private(set) var lockedIdentityTargetPhone: LockedPhoneTarget?
```

建议新增：

```swift
struct LockedPhoneTarget: Equatable, Sendable {
    let countryCode: String
    let nationalNumber: String
    let e164: String
    let displayValue: String
}
```

说明：

- `identityTargetInput` 继续用于邮箱。
- `identityTargetPhoneInput` 用于手机号绑定/修改。
- `lockedIdentityTargetPhone` 是短信验证码发码成功后的手机号快照。
- 绑定/修改提交时，手机号 provider 必须使用 `lockedIdentityTargetPhone.e164`。

### 7.2 调整 FlowState，保存目标快照

当前：

```swift
case targetOTP(AccountIdentityOperation, ticket: String, otpID: String)
```

建议调整为：

```swift
case targetOTP(
    AccountIdentityOperation,
    ticket: String,
    otpID: String,
    target: AccountIdentityTargetSnapshot
)
```

新增：

```swift
enum AccountIdentityTargetSnapshot: Equatable, Sendable {
    case phone(LockedPhoneTarget)
    case email(String)
}
```

这样验证码页和提交逻辑都从状态快照读取目标，不再回读输入框。

### 7.3 改造 requestTargetOTP()

手机号 provider：

```swift
func requestTargetOTP() async {
    guard case .enteringTarget(let operation, let ticket) = identityFlowState else { return }

    switch operation.targetProvider {
    case .phone:
        let phone = identityTargetPhoneInput
        guard phone.isValid, phone.e164.isEmpty == false else { return }

        let locked = LockedPhoneTarget(
            countryCode: phone.countryCode,
            nationalNumber: phone.nationalNumber,
            e164: phone.e164,
            displayValue: "\(phone.countryCode) \(phone.nationalNumber)"
        )

        let context = try await requestTargetOTP(
            provider: .phone,
            target: locked.e164,
            operation: operation
        )
        lockedIdentityTargetPhone = locked
        identityFlowState = .targetOTP(operation, ticket: ticket, otpID: context.otpID, target: .phone(locked))

    case .email:
        let target = identityTargetInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard target.isEmpty == false else { return }
        let context = try await requestTargetOTP(provider: .email, target: target, operation: operation)
        identityFlowState = .targetOTP(operation, ticket: ticket, otpID: context.otpID, target: .email(target))

    case .apple:
        return
    }
}
```

关键点：

- 手机号请求短信验证码前，先生成 `locked`。
- 短信验证码请求成功后进入 `.targetOTP(... target: .phone(locked))`。
- 如果请求失败，不锁定手机号。

### 7.4 改造 submitIdentityTargetOTPIfReady()

手机号 provider 不再读取 `identityTargetInput`：

```swift
func submitIdentityTargetOTPIfReady() {
    guard identityTargetOTPCode.count == 6 else { return }
    guard case .targetOTP(let operation, let ticket, let otpID, let target) = identityFlowState else { return }

    Task {
        switch operation {
        case .bind(let provider):
            switch (provider, target) {
            case (.phone, .phone(let phone)):
                let proof = AccountIdentityBindProof.phone(
                    target: phone.e164,
                    otpID: otpID,
                    code: identityTargetOTPCode
                )
                await submitBindOrChange(operation: operation, ticket: ticket, bindProof: proof)

            case (.email, .email(let email)):
                let proof = AccountIdentityBindProof.email(
                    target: email,
                    otpID: otpID,
                    code: identityTargetOTPCode
                )
                await submitBindOrChange(operation: operation, ticket: ticket, bindProof: proof)

            default:
                return
            }

        case .change(let provider):
            switch (provider, target) {
            case (.phone, .phone(let phone)):
                await submitBindOrChange(
                    operation: operation,
                    ticket: ticket,
                    changeTarget: phone.e164,
                    changeOtpID: otpID,
                    changeCode: identityTargetOTPCode,
                    provider: .phone
                )

            case (.email, .email(let email)):
                await submitBindOrChange(
                    operation: operation,
                    ticket: ticket,
                    changeTarget: email,
                    changeOtpID: otpID,
                    changeCode: identityTargetOTPCode,
                    provider: .email
                )

            default:
                return
            }
        }
    }
}
```

### 7.5 改造 UI

`IdentityTargetInputCard` 根据 provider 分支：

```swift
switch provider {
case .phone:
    PhoneNumberInputView(
        model: $viewModel.identityTargetPhoneInput,
        isLocked: viewModel.lockedIdentityTargetPhone != nil
    )

case .email:
    TextField(..., text: $viewModel.identityTargetInput)

case .apple:
    EmptyView()
}
```

如果当前 `PhoneNumberInputView` 不支持锁定，需要扩展参数：

```swift
struct PhoneNumberInputView: View {
    @Binding var model: PhoneNumberInputModel
    var regions: [PhoneRegion] = defaultRegions
    var isLocked: Bool = false
}
```

锁定时：

- `TextField.disabled(true)`
- `Menu.disabled(true)`
- `onChange` 内不执行自动改写。
- UI 可显示锁定说明：“验证码已发送，手机号暂不可修改”。

### 7.6 PhoneNumberInputView 需要补齐自动识别能力

当前 `PhoneNumberInputView.recompute()` 只调用 `PhoneNumberNormalizer.normalize(...)`，但没有像登录页一样调用 `detectRegionNumber(...)` 后自动切换区号、剥离 national number。

需要补齐：

```swift
@State private var isApplyingAutoRegion = false

private func applyAutoRegionAndStripPrefixIfNeeded(_ raw: String) {
    guard isLocked == false else { return }
    guard isApplyingAutoRegion == false else { return }

    let detected = PhoneNumberNormalizer.detectRegionNumber(
        rawInput: raw,
        supportedDials: regions.map(\.dial)
    )
    guard let detected,
          let region = regions.first(where: { $0.dial == detected.dial }) else {
        recompute()
        return
    }

    isApplyingAutoRegion = true
    chosenRegion = region
    model.rawInput = detected.nationalDigits
    recompute()
    isApplyingAutoRegion = false
}
```

`TextField.onChange` 调整为：

```swift
.onChange(of: model.rawInput) { newValue in
    applyAutoRegionAndStripPrefixIfNeeded(newValue)
}
```

注意：

- 必须防止递归触发。
- 锁定状态下不能改写输入。
- 区号选择变化时，如果未锁定才允许 `recompute()`。

### 7.7 登录页后续收敛建议

登录页当前仍在 `LoginConductor.swift` 内自行维护：

- `PhoneRegion`
- `chosenRegion`
- `phone`
- `applyAutoRegionAndStripPrefixIfNeeded(_:)`

建议后续把登录页也收敛为公共 `PhoneNumberInputView`。

本工单优先解决账号管理绑定/修改；登录页收敛可作为同工单附带优化，或另开小工单。

## 8. UI 线框

### 8.1 输入手机号

```text
┌────────────────────────────────────────┐
│ 绑定手机号                              │
│ 需要先验证新手机号，用于后续登录。       │
│                                        │
│ 手机号                                  │
│ ┌──────────┬─────────────────────────┐ │
│ │ 🇨🇳 +86⌄ │ 15385056020             │ │
│ └──────────┴─────────────────────────┘ │
│                                        │
│ [ 获取短信验证码 ]                      │
│                                        │
│ 返回                                   │
└────────────────────────────────────────┘
```

### 8.2 粘贴完整国际手机号后

用户粘贴：

```text
+8615385056020
```

界面自动变成：

```text
┌──────────┬─────────────────────────┐
│ 🇨🇳 +86⌄ │ 15385056020             │
└──────────┴─────────────────────────┘
```

提交给接口：

```text
+8615385056020
```

### 8.3 验证码已发送，手机号锁定

```text
┌────────────────────────────────────────┐
│ 输入验证码                              │
│ 验证码已发送至 +86 153****20           │
│                                        │
│ ┌────┬────┬────┬────┬────┬────┐       │
│ │ 1  │ 2  │ 3  │ 4  │ 5  │ 6  │       │
│ └────┴────┴────┴────┴────┴────┘       │
│                                        │
│ 52 秒后可重新发送                      │
│ 手机号已锁定，如需修改请返回上一步。    │
│                                        │
│ [ 返回修改手机号 ]                      │
└────────────────────────────────────────┘
```

### 8.4 返回修改手机号

```text
┌────────────────────────────────────────┐
│ 修改手机号                              │
│                                        │
│ ┌──────────┬─────────────────────────┐ │
│ │ 🇨🇳 +86⌄ │ 15385056020             │ │
│ └──────────┴─────────────────────────┘ │
│                                        │
│ [ 重新获取短信验证码 ]                  │
└────────────────────────────────────────┘
```

## 9. 接口请求要求

### 9.1 请求目标手机号验证码

账号管理手机号绑定/修改请求验证码时：

```json
{
  "provider": "phone",
  "target": "+8615385056020",
  "scene": "identity_bind"
}
```

或：

```json
{
  "provider": "phone",
  "target": "+8615385056020",
  "scene": "identity_change"
}
```

客户端必须传 E.164。

### 9.2 提交绑定

```json
{
  "provider": "phone",
  "verification_ticket": "...",
  "proof": {
    "type": "phone",
    "target": "+8615385056020",
    "otp_id": "...",
    "code": "123456"
  }
}
```

`proof.target` 必须等于发码请求时的 `target`。

### 9.3 提交修改

```json
{
  "provider": "phone",
  "verification_ticket": "...",
  "new_target": "+8615385056020",
  "new_otp_id": "...",
  "new_code": "123456"
}
```

`new_target` 必须等于发码请求时的 `target`。

## 10. 错误处理

| 场景 | 客户端处理 |
| --- | --- |
| 手机号为空 | 获取验证码按钮置灰 |
| 手机号过短 | 获取验证码按钮置灰或提示手机号格式不正确 |
| 无法识别区号 | 保持当前选择区号，按本地号码规范化 |
| 发码失败 | 不锁定手机号，保留输入页 |
| 发码成功 | 锁定手机号，进入验证码页 |
| 验证码错误 | 保持验证码页，手机号继续锁定 |
| 验证码过期 | 保持验证码页，允许重新发送到同一冻结手机号 |
| 用户要换手机号 | 必须返回输入页重新获取验证码 |

## 11. 验收标准

1. 账号管理绑定手机号页展示区号选择器。
2. 账号管理修改手机号页展示区号选择器。
3. 粘贴 `+8615385056020` 后，区号自动选中 `+86`，输入框变为 `15385056020`。
4. 粘贴 `008615385056020` 后，区号自动选中 `+86`，输入框变为 `15385056020`。
5. 粘贴 `8615385056020` 后，区号自动选中 `+86`，输入框变为 `15385056020`。
6. 点击获取验证码成功后，手机号输入框不可编辑。
7. 点击获取验证码成功后，区号选择器不可点击。
8. 验证码页展示的手机号来自发码时冻结快照。
9. 验证码提交时使用发码时冻结的 E.164，不重新读取输入框。
10. 重新发送验证码使用同一个冻结 E.164。
11. 返回输入页后可以修改手机号，但必须重新获取验证码。
12. 发码失败时不锁定手机号。
13. 邮箱绑定/修改流程不受手机号输入模型影响。
14. Apple 绑定流程不受手机号输入模型影响。

## 12. 测试用例

### 12.1 Normalizer 单元测试

| 输入 | 默认区号 | 期望区号 | 输入框展示 | E.164 |
| --- | --- | --- | --- | --- |
| `15385056020` | `+86` | `+86` | `15385056020` | `+8615385056020` |
| `+8615385056020` | `+86` | `+86` | `15385056020` | `+8615385056020` |
| `008615385056020` | `+86` | `+86` | `15385056020` | `+8615385056020` |
| `8615385056020` | `+86` | `+86` | `15385056020` | `+8615385056020` |
| `+85291234567` | `+86` | `+852` | `91234567` | `+85291234567` |

### 12.2 ViewModel 测试

1. `requestTargetOTP()` 对手机号 provider 使用 `identityTargetPhoneInput.e164`。
2. 发码成功后 `AccountIdentityFlowState.targetOTP` 内包含手机号快照。
3. 发码成功后修改 `identityTargetPhoneInput.rawInput` 不影响提交目标。
4. `submitIdentityTargetOTPIfReady()` 使用快照中的 `e164`。
5. `backToIdentityTargetInput()` 清空 `otpID` 和锁定快照。
6. 邮箱 provider 仍使用 `identityTargetInput`。

### 12.3 UI 测试

1. 手机号绑定页显示区号选择器。
2. 手机号修改页显示区号选择器。
3. 验证码发送成功后输入框禁用。
4. 验证码发送成功后区号菜单禁用。
5. 返回输入页后输入框恢复可编辑。

## 13. 实施顺序

1. 扩展 `PhoneNumberInputView`，支持 `isLocked` 和自动识别完整国际手机号。
2. 为 `PhoneNumberInputView` / `PhoneNumberNormalizer` 补充单元测试。
3. 在 `AccountManagementViewModel` 增加 `identityTargetPhoneInput` 和 `LockedPhoneTarget`。
4. 调整 `AccountIdentityFlowState.targetOTP`，保存目标快照。
5. 改造 `requestTargetOTP()` 和 `submitIdentityTargetOTPIfReady()`。
6. 改造 `AccountManagementView` / `IdentityTargetInputCard`，手机号 provider 使用 `PhoneNumberInputView`。
7. 补充本地化文案。
8. 回归邮箱、Apple 绑定流程。

## 14. 需要补充的本地化文案

建议新增：

```text
account_management.identity.phone.locked_hint = 验证码已发送，手机号暂不可修改
account_management.identity.phone.change_to_edit = 如需修改手机号，请返回上一步
account_management.identity.phone.invalid = 手机号格式不正确
account_management.identity.phone.country_picker = 选择国家或地区
```

## 15. 风险与注意事项

1. `PhoneNumberInputView` 当前定义在 Core UI，但 `PhoneRegion` 当前仍定义在 `LoginConductor.swift`。如果编译作用域存在问题，应把 `PhoneRegion` 移动到公共 Foundation/UI 模块，避免 Core UI 依赖登录页面文件。
2. 不要在验证码页重新 normalize 当前输入框内容。
3. 不要在发码成功后允许 `onChange` 自动剥离区号。
4. 不要把邮箱流程强行塞进手机号模型。
5. 登录流程和账号管理流程最终应共享同一个手机号输入组件，否则后续还会出现行为漂移。

