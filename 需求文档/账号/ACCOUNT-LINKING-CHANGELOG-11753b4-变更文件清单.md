# SparkClient 11753b4 变更文件清单

> **提交**: `11753b4`  
> **标题**: feat(account): 账号管理登录方式绑定、修改与身份验证  
> **范围**: `fdde4a1..11753b4`  
> **统计**: 28 个文件，+5502 / -69 行  
> **删除**: 无

---

## 新增（15）

### 网络层

| 文件路径 |
| --- |
| `SparkClient/Projects/Core/Networking/API/Account/AccountIdentityAPI.swift` |

### UI 组件

| 文件路径 |
| --- |
| `SparkClient/Projects/Core/UI/EmailAddress/EmailAddressInputView.swift` |
| `SparkClient/Projects/Core/UI/EmailAddress/EmailAddressNormalizer.swift` |

### 账号管理 - Application（UseCase）

| 文件路径 |
| --- |
| `SparkClient/Projects/Features/AccountManagement/Application/BindAccountIdentityUseCase.swift` |
| `SparkClient/Projects/Features/AccountManagement/Application/ChangeAccountIdentityUseCase.swift` |
| `SparkClient/Projects/Features/AccountManagement/Application/LoadAccountIdentitiesUseCase.swift` |
| `SparkClient/Projects/Features/AccountManagement/Application/RequestIdentityVerificationUseCase.swift` |
| `SparkClient/Projects/Features/AccountManagement/Application/VerifyIdentityVerificationUseCase.swift` |

### 账号管理 - Domain

| 文件路径 |
| --- |
| `SparkClient/Projects/Features/AccountManagement/Domain/AccountIdentityModels.swift` |

### 测试

| 文件路径 |
| --- |
| `SparkClient/Tests/AccountManagement/EmailAddressNormalizerTests.swift` |
| `SparkClient/Tests/AccountManagement/PhoneNumberNormalizerTests.swift` |

### 需求文档

| 文件路径 |
| --- |
| `需求文档/账号/ACCOUNT-EMAIL-INPUT-000001-账号管理邮箱输入与邮箱后缀选择需求工单.md` |
| `需求文档/账号/ACCOUNT-LINKING-000001-账号管理登录方式UI线框.md` |
| `需求文档/账号/ACCOUNT-PHONE-INPUT-000001-账号管理手机号输入与验证码号码锁定需求工单.md` |

---

## 修改（13）

### App 层

| 文件路径 | 变更量 |
| --- | --- |
| `SparkClient/Projects/App/Sources/App/AppContainer.swift` | +21 |

### 本地化

| 文件路径 | 变更量 |
| --- | --- |
| `SparkClient/Projects/App/Resources/en.lproj/Localizable.strings` | +55 |
| `SparkClient/Projects/App/Resources/zh-Hans.lproj/Localizable.strings` | +55 |

### 网络层

| 文件路径 | 变更量 |
| --- | --- |
| `SparkClient/Projects/Core/Networking/API/Auth/OTPAPI.swift` | +7 / -1 |
| `SparkClient/Projects/Core/Networking/Backend.swift` | +3 |
| `SparkClient/Projects/Core/Networking/Logging/NetworkOperationBusinessPurpose.swift` | +5 |

### UI 组件

| 文件路径 | 变更量 |
| --- | --- |
| `SparkClient/Projects/Core/UI/PhoneNumber/PhoneNumberInputView.swift` | +74 |

### 账号管理

| 文件路径 | 变更量 |
| --- | --- |
| `SparkClient/Projects/Features/AccountManagement/Domain/AccountManagementRepository.swift` | +32 |
| `SparkClient/Projects/Features/AccountManagement/Infrastructure/DefaultAccountManagementRepository.swift` | +182 |
| `SparkClient/Projects/Features/AccountManagement/Presentation/AccountManagementView.swift` | +230 |
| `SparkClient/Projects/Features/AccountManagement/Presentation/AccountManagementViewModel.swift` | +768 |
| `SparkClient/Projects/Features/AccountManagement/Presentation/Components/AccountManagementComponents.swift` | +275 |

### 认证

| 文件路径 | 变更量 |
| --- | --- |
| `SparkClient/Projects/Features/Auth/Presentation/LoginConductor.swift` | +9 |

### 需求文档

| 文件路径 | 变更量 |
| --- | --- |
| `需求文档/账号/ACCOUNT-LINKING-000001-账号管理登录方式绑定与修改客户端需求工单.md` | +370 |

---

## 删除（0）

本版本无删除文件。

---

## 完整路径列表（按字母序）

```
SparkClient/Projects/App/Resources/en.lproj/Localizable.strings                          [M]
SparkClient/Projects/App/Resources/zh-Hans.lproj/Localizable.strings                     [M]
SparkClient/Projects/App/Sources/App/AppContainer.swift                                  [M]
SparkClient/Projects/Core/Networking/API/Account/AccountIdentityAPI.swift                [A]
SparkClient/Projects/Core/Networking/API/Auth/OTPAPI.swift                                 [M]
SparkClient/Projects/Core/Networking/Backend.swift                                       [M]
SparkClient/Projects/Core/Networking/Logging/NetworkOperationBusinessPurpose.swift         [M]
SparkClient/Projects/Core/UI/EmailAddress/EmailAddressInputView.swift                    [A]
SparkClient/Projects/Core/UI/EmailAddress/EmailAddressNormalizer.swift                   [A]
SparkClient/Projects/Core/UI/PhoneNumber/PhoneNumberInputView.swift                      [M]
SparkClient/Projects/Features/AccountManagement/Application/BindAccountIdentityUseCase.swift       [A]
SparkClient/Projects/Features/AccountManagement/Application/ChangeAccountIdentityUseCase.swift     [A]
SparkClient/Projects/Features/AccountManagement/Application/LoadAccountIdentitiesUseCase.swift     [A]
SparkClient/Projects/Features/AccountManagement/Application/RequestIdentityVerificationUseCase.swift [A]
SparkClient/Projects/Features/AccountManagement/Application/VerifyIdentityVerificationUseCase.swift  [A]
SparkClient/Projects/Features/AccountManagement/Domain/AccountIdentityModels.swift               [A]
SparkClient/Projects/Features/AccountManagement/Domain/AccountManagementRepository.swift           [M]
SparkClient/Projects/Features/AccountManagement/Infrastructure/DefaultAccountManagementRepository.swift [M]
SparkClient/Projects/Features/AccountManagement/Presentation/AccountManagementView.swift          [M]
SparkClient/Projects/Features/AccountManagement/Presentation/AccountManagementViewModel.swift    [M]
SparkClient/Projects/Features/AccountManagement/Presentation/Components/AccountManagementComponents.swift [M]
SparkClient/Projects/Features/Auth/Presentation/LoginConductor.swift                     [M]
SparkClient/Tests/AccountManagement/EmailAddressNormalizerTests.swift                     [A]
SparkClient/Tests/AccountManagement/PhoneNumberNormalizerTests.swift                     [A]
需求文档/账号/ACCOUNT-EMAIL-INPUT-000001-账号管理邮箱输入与邮箱后缀选择需求工单.md          [A]
需求文档/账号/ACCOUNT-LINKING-000001-账号管理登录方式UI线框.md                            [A]
需求文档/账号/ACCOUNT-LINKING-000001-账号管理登录方式绑定与修改客户端需求工单.md            [M]
需求文档/账号/ACCOUNT-PHONE-INPUT-000001-账号管理手机号输入与验证码号码锁定需求工单.md        [A]
```

---

## 功能摘要

| 模块 | 说明 |
| --- | --- |
| AccountIdentity API | 身份列表、绑定、换绑、验证请求与确认 |
| UseCase 层 | 5 个用例封装账号身份操作流程 |
| ViewModel / View | 账号管理页重构，支持手机号/邮箱绑定与换绑 |
| 输入组件 | 邮箱输入（含后缀选择）、手机号输入（含验证码号码锁定） |
| 测试 | 邮箱与手机号规范化单元测试 |
| 需求文档 | UI 线框、邮箱/手机号输入、客户端绑定需求工单 |
