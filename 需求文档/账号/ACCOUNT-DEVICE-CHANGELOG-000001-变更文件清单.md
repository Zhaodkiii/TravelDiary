# SparkClient ACCOUNT-DEVICE-000001 变更文件清单

> **工单**: ACCOUNT-DEVICE-000001 游客模式设备账户登录与正式账号切换  
> **状态**: 未提交（基于当前工作区 `git status` / `git diff`）  
> **统计**: 28 个文件，+622 / -275 行  
> **删除**: 无

---

## 新增（2）

### 认证 - Application（UseCase）

| 文件路径 | 行数 |
| --- | --- |
| `SparkClient/Projects/Features/Auth/Application/SignInWithDeviceUseCase.swift` | 9 |

### 需求文档

| 文件路径 | 行数 |
| --- | --- |
| `需求文档/账号/ACCOUNT-DEVICE-000001-游客模式设备账户登录与正式账号切换客户端需求工单.md` | 436 |

---

## 修改（26）

### App 层

| 文件路径 | 变更量 |
| --- | --- |
| `SparkClient/Projects/App/Sources/App/AppContainer.swift` | +6 / -1 |
| `SparkClient/Projects/App/Sources/App/AppCoordinatorView.swift` | +1 |
| `SparkClient/Projects/App/Sources/App/AppRouteStore.swift` | +3 / -2 |
| `SparkClient/Projects/App/Sources/App/MainTabCoordinatorView.swift` | +40 / -12 |
| `SparkClient/Projects/App/Sources/App/Architecture/AccountSessionRuntime.swift` | +15 / -6 |
| `SparkClient/Projects/App/Sources/App/Architecture/AssemblyProducts.swift` | +2 |
| `SparkClient/Projects/App/Sources/App/Architecture/FeatureAssemblies.swift` | +1 |

### 本地化

| 文件路径 | 变更量 |
| --- | --- |
| `SparkClient/Projects/App/Resources/en.lproj/Localizable.strings` | +8 / -2 |
| `SparkClient/Projects/App/Resources/zh-Hans.lproj/Localizable.strings` | +8 / -2 |

### 领域模型

| 文件路径 | 变更量 |
| --- | --- |
| `SparkClient/Projects/Core/Domain/Entities/UserSession.swift` | +31 / -2 |

### 网络层

| 文件路径 | 变更量 |
| --- | --- |
| `SparkClient/Projects/Core/Networking/API/Auth/AuthAPI.swift` | +141 / -22 |
| `SparkClient/Projects/Core/Networking/API/Auth/OTPAPI.swift` | +13 / -4 |

### 账号管理

| 文件路径 | 变更量 |
| --- | --- |
| `SparkClient/Projects/Features/AccountManagement/Domain/AccountDeactivationModels.swift` | +6 |
| `SparkClient/Projects/Features/AccountManagement/Presentation/AccountManagementView.swift` | -1 |
| `SparkClient/Projects/Features/AccountManagement/Presentation/AccountManagementViewModel.swift` | +7 / -87 |
| `SparkClient/Projects/Features/AccountManagement/Presentation/Components/AccountManagementComponents.swift` | -11 |

### 认证

| 文件路径 | 变更量 |
| --- | --- |
| `SparkClient/Projects/Features/Auth/Domain/AuthRepository.swift` | +1 |
| `SparkClient/Projects/Features/Auth/Infrastructure/DefaultAuthRepository.swift` | +77 / -12 |
| `SparkClient/Projects/Features/Auth/Presentation/AuthUserFacingErrorMapper.swift` | +26 |
| `SparkClient/Projects/Features/Auth/Presentation/LoginView.swift` | +20 / -14 |
| `SparkClient/Projects/Features/Auth/Presentation/LoginViewModel.swift` | +70 / -30 |

### 首页 / 成员

| 文件路径 | 变更量 |
| --- | --- |
| `SparkClient/Projects/Features/Home/Presentation/HomeView.swift` | +4 |
| `SparkClient/Projects/Features/Home/Presentation/Members/MemberSetup/MemberSetupFlowView.swift` | +7 / -3 |
| `SparkClient/Projects/Features/Home/Presentation/Members/MemberSetup/MemberSetupFlowViewModel.swift` | +28 |

### 设置

| 文件路径 | 变更量 |
| --- | --- |
| `SparkClient/Projects/Features/Settings/Presentation/SettingsView.swift` | +21 / -58 |

### 基础设施

| 文件路径 | 变更量 |
| --- | --- |
| `SparkClient/Projects/Foundation/Security/SparkKeychain.swift` | +86 / -6 |

---

## 删除（0）

本版本无删除文件（`GuestChatView` 相关入口逻辑被替换，但无文件从仓库移除）。

---

## 完整路径列表（按字母序）

```
SparkClient/Projects/App/Resources/en.lproj/Localizable.strings                          [M]
SparkClient/Projects/App/Resources/zh-Hans.lproj/Localizable.strings                     [M]
SparkClient/Projects/App/Sources/App/AppContainer.swift                                  [M]
SparkClient/Projects/App/Sources/App/AppCoordinatorView.swift                          [M]
SparkClient/Projects/App/Sources/App/AppRouteStore.swift                                 [M]
SparkClient/Projects/App/Sources/App/Architecture/AccountSessionRuntime.swift            [M]
SparkClient/Projects/App/Sources/App/Architecture/AssemblyProducts.swift                 [M]
SparkClient/Projects/App/Sources/App/Architecture/FeatureAssemblies.swift                [M]
SparkClient/Projects/App/Sources/App/MainTabCoordinatorView.swift                        [M]
SparkClient/Projects/Core/Domain/Entities/UserSession.swift                              [M]
SparkClient/Projects/Core/Networking/API/Auth/AuthAPI.swift                              [M]
SparkClient/Projects/Core/Networking/API/Auth/OTPAPI.swift                               [M]
SparkClient/Projects/Features/AccountManagement/Domain/AccountDeactivationModels.swift   [M]
SparkClient/Projects/Features/AccountManagement/Presentation/AccountManagementView.swift [M]
SparkClient/Projects/Features/AccountManagement/Presentation/AccountManagementViewModel.swift [M]
SparkClient/Projects/Features/AccountManagement/Presentation/Components/AccountManagementComponents.swift [M]
SparkClient/Projects/Features/Auth/Application/SignInWithDeviceUseCase.swift             [A]
SparkClient/Projects/Features/Auth/Domain/AuthRepository.swift                           [M]
SparkClient/Projects/Features/Auth/Infrastructure/DefaultAuthRepository.swift            [M]
SparkClient/Projects/Features/Auth/Presentation/AuthUserFacingErrorMapper.swift          [M]
SparkClient/Projects/Features/Auth/Presentation/LoginView.swift                          [M]
SparkClient/Projects/Features/Auth/Presentation/LoginViewModel.swift                     [M]
SparkClient/Projects/Features/Home/Presentation/HomeView.swift                           [M]
SparkClient/Projects/Features/Home/Presentation/Members/MemberSetup/MemberSetupFlowView.swift [M]
SparkClient/Projects/Features/Home/Presentation/Members/MemberSetup/MemberSetupFlowViewModel.swift [M]
SparkClient/Projects/Features/Settings/Presentation/SettingsView.swift                   [M]
SparkClient/Projects/Foundation/Security/SparkKeychain.swift                             [M]
需求文档/账号/ACCOUNT-DEVICE-000001-游客模式设备账户登录与正式账号切换客户端需求工单.md      [A]
```

---

## 功能摘要

| 模块 | 说明 |
| --- | --- |
| 设备登录 API | `AuthAPI` 新增 device sign-in；`SignInWithDeviceUseCase` 封装调用 |
| Keychain 凭证 | `SparkKeychain` 持久化 `device_id` + `device_secret` |
| UserSession | 新增 `.device` 提供方与 `isDeviceAccount` 标识 |
| 登录页 | 游客按钮改为设备账户登录，不再进入 `GuestChatView` |
| 设置页 | 设备账户显示「未登录」，点击 sheet 打开正式登录；正式账户跳转账号管理 |
| 路由 | `AppRouteStore` / `MainTabCoordinatorView` 支持账号管理路由 destination |
| 账号切换 | `AccountSessionRuntime` 处理升级同 accountID vs 切换其他 accountID |
| 成员建档 | `MemberSetupFlow` 适配设备账户场景 |
| 账号管理精简 | 移除设备账户专用入口逻辑，改由 Settings 统一分流 |

---

## 备注

- 本清单仅覆盖 **ACCOUNT-DEVICE-000001 游客模式** 相关未提交改动。
- 工作区另有未纳入本工单的未跟踪文件：`需求文档/账号/ACCOUNT-LINKING-CHANGELOG-11753b4-变更文件清单.md`（属 11753b4 账号绑定版本归档，非本工单范围）。
