# SUPPORT-ACCOUNT-ALIGN 变更文件清单

将 SupportClient 账户/登录底层目录与文件对齐到 SparkClient：拷入 Auth / Account API / UI / Keychain，删除不对齐单体，并在 Support 网络引擎与 App 装配处手改。

## 验收

- **BUILD SUCCEEDED**：`xcodebuild -scheme SupportClient -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.5' -configuration Debug build`
- 登录能力：Apple / 手机 OTP / 游客设备登录（`Features/Auth`）
- 设置：设备账户「未登录」→ 升级 sheet；正式账户 → AccountManagement
- 仓库中无 `AuthFeature.swift` / `PhoneNumberSupport.swift` / `PhoneLoginConductor.swift` / `AuthSupportUI.swift` / 错位 `SupportAccountIdentityAPI.swift`

## 变更列表

| 标记 | 路径 |
| --- | --- |
| [D] | `SupportClient/App/AuthFeature.swift` |
| [D] | `SupportClient/App/PhoneLoginConductor.swift` |
| [D] | `SupportClient/App/RestoreSessionUseCase.swift` |
| [D] | `SupportClient/Core/UI/AuthSupportUI.swift` |
| [D] | `SupportClient/Core/UI/PhoneNumberSupport.swift` |
| [A] | `SupportClient/App/NotificationClient.swift` |
| [A] | `SupportClient/Core/Networking/BackendErrorLocalizer.swift` |
| [A] | `SupportClient/Core/Networking/SupportDeviceCacheStub.swift` |
| [A] | `SupportClient/Projects/Core/Domain/Entities/UserSession.swift` |
| [A] | `SupportClient/Projects/Core/Networking/API/Account/AccountIdentityAPI.swift` |
| [A] | `SupportClient/Projects/Core/Networking/API/Account/DeactivationAPI.swift` |
| [A] | `SupportClient/Projects/Core/Networking/API/Auth/AuthAPI.swift` |
| [A] | `SupportClient/Projects/Core/Networking/API/Auth/OTPAPI.swift` |
| [A] | `SupportClient/Projects/Core/UI/EmailAddress/EmailAddressInputView.swift` |
| [A] | `SupportClient/Projects/Core/UI/EmailAddress/EmailAddressNormalizer.swift` |
| [A] | `SupportClient/Projects/Core/UI/Navigation/CompatibleNavigationContainer.swift` |
| [A] | `SupportClient/Projects/Core/UI/PhoneNumber/PhoneNumberInputView.swift` |
| [A] | `SupportClient/Projects/Core/UI/PhoneNumber/PhoneNumberNormalizer.swift` |
| [A] | `SupportClient/Projects/Core/UI/PhoneNumber/PhoneRegions.swift` |
| [A] | `SupportClient/Projects/Core/UI/Sheet/AdaptiveSheetContainer.swift` |
| [A] | `SupportClient/Projects/Core/UI/Web/SafariWebViewSheet.swift` |
| [A] | `SupportClient/Projects/Features/AccountManagement/Application/BindAccountIdentityUseCase.swift` |
| [A] | `SupportClient/Projects/Features/AccountManagement/Application/ChangeAccountIdentityUseCase.swift` |
| [A] | `SupportClient/Projects/Features/AccountManagement/Application/LoadAccountIdentitiesUseCase.swift` |
| [A] | `SupportClient/Projects/Features/AccountManagement/Application/RequestIdentityVerificationUseCase.swift` |
| [A] | `SupportClient/Projects/Features/AccountManagement/Application/VerifyIdentityVerificationUseCase.swift` |
| [A] | `SupportClient/Projects/Features/AccountManagement/Domain/AccountIdentityModels.swift` |
| [A] | `SupportClient/Projects/Features/Auth/Application/RequestPhoneOTPUseCase.swift` |
| [A] | `SupportClient/Projects/Features/Auth/Application/RestoreSessionUseCase.swift` |
| [A] | `SupportClient/Projects/Features/Auth/Application/SignInWithAppleUseCase.swift` |
| [A] | `SupportClient/Projects/Features/Auth/Application/SignInWithDeviceUseCase.swift` |
| [A] | `SupportClient/Projects/Features/Auth/Application/SignInWithPhoneOTPUseCase.swift` |
| [A] | `SupportClient/Projects/Features/Auth/Application/SignOutUseCase.swift` |
| [A] | `SupportClient/Projects/Features/Auth/Domain/AuthRepository.swift` |
| [A] | `SupportClient/Projects/Features/Auth/Infrastructure/DefaultAuthRepository.swift` |
| [A] | `SupportClient/Projects/Features/Auth/Infrastructure/SessionSnapshotStore.swift` |
| [A] | `SupportClient/Projects/Features/Auth/Presentation/AuthUserFacingErrorMapper.swift` |
| [A] | `SupportClient/Projects/Features/Auth/Presentation/LoginConductor.swift` |
| [A] | `SupportClient/Projects/Features/Auth/Presentation/LoginLegalAgreementNote.swift` |
| [A] | `SupportClient/Projects/Features/Auth/Presentation/LoginView.swift` |
| [A] | `SupportClient/Projects/Features/Auth/Presentation/LoginViewModel.swift` |
| [A] | `SupportClient/Projects/Features/Auth/Presentation/OutlinedButtonStyle.swift` |
| [A] | `SupportClient/Projects/Features/Auth/Presentation/VerificationCodeField.swift` |
| [A] | `SupportClient/Projects/Foundation/Security/SparkKeychain.swift` |
| [A] | `\351\234\200\346\261\202\346\226\207\346\241\243/\350\264\246\345\217\267/ACCOUNT-DEVICE-000001-\346\270\270\345\256\242\346\250\241\345\274\217\350\256\276\345\244\207\350\264\246\346\210\267\347\231\273\345\275\225\344\270\216\346\255\243\345\274\217\350\264\246\345\217\267\345\210\207\346\215\242\345\256\242\346\210\267\347\253\257\351\234\200\346\261\202\345\267\245\345\215\225.md` |
| [A] | `\351\234\200\346\261\202\346\226\207\346\241\243/\350\264\246\345\217\267/ACCOUNT-DEVICE-CHANGELOG-000001-\345\217\230\346\233\264\346\226\207\344\273\266\346\270\205\345\215\225.md` |
| [A] | `\351\234\200\346\261\202\346\226\207\346\241\243/\350\264\246\345\217\267/ACCOUNT-EMAIL-INPUT-000001-\350\264\246\345\217\267\347\256\241\347\220\206\351\202\256\347\256\261\350\276\223\345\205\245\344\270\216\351\202\256\347\256\261\345\220\216\347\274\200\351\200\211\346\213\251\351\234\200\346\261\202\345\267\245\345\215\225.md` |
| [A] | `\351\234\200\346\261\202\346\226\207\346\241\243/\350\264\246\345\217\267/ACCOUNT-LINKING-000001-\350\264\246\345\217\267\347\256\241\347\220\206\347\231\273\345\275\225\346\226\271\345\274\217UI\347\272\277\346\241\206.md` |
| [A] | `\351\234\200\346\261\202\346\226\207\346\241\243/\350\264\246\345\217\267/ACCOUNT-LINKING-000001-\350\264\246\345\217\267\347\256\241\347\220\206\347\231\273\345\275\225\346\226\271\345\274\217\347\273\221\345\256\232\344\270\216\344\277\256\346\224\271\345\256\242\346\210\267\347\253\257\351\234\200\346\261\202\345\267\245\345\215\225.md` |
| [A] | `\351\234\200\346\261\202\346\226\207\346\241\243/\350\264\246\345\217\267/ACCOUNT-LINKING-CHANGELOG-11753b4-\345\217\230\346\233\264\346\226\207\344\273\266\346\270\205\345\215\225.md` |
| [A] | `\351\234\200\346\261\202\346\226\207\346\241\243/\350\264\246\345\217\267/ACCOUNT-PHONE-INPUT-000001-\350\264\246\345\217\267\347\256\241\347\220\206\346\211\213\346\234\272\345\217\267\350\276\223\345\205\245\344\270\216\351\252\214\350\257\201\347\240\201\345\217\267\347\240\201\351\224\201\345\256\232\351\234\200\346\261\202\345\267\245\345\215\225.md` |
| [A] | `\351\234\200\346\261\202\346\226\207\346\241\243/\350\264\246\345\217\267/SUPPORT-ACCOUNT-ALIGN-\345\217\230\346\233\264\346\226\207\344\273\266\346\270\205\345\215\225.md` |
| [M] | `SupportClient/App/AppContainer.swift` |
| [M] | `SupportClient/App/AppCoordinatorView.swift` |
| [M] | `SupportClient/App/AppSessionStore.swift` |
| [M] | `SupportClient/App/SupportAppEnvironment.swift` |
| [M] | `SupportClient/Core/Networking/SupportAPIs.swift` |
| [M] | `SupportClient/Core/Networking/SupportBackend.swift` |
| [M] | `SupportClient/Foundation/Utilities.swift` |
| [M] | `SupportClient/Projects/Features/AccountManagement/Application/LoadAccountProfileUseCase.swift` |
| [M] | `SupportClient/Projects/Features/AccountManagement/Application/RequestAccountVerificationUseCase.swift` |
| [M] | `SupportClient/Projects/Features/AccountManagement/Application/SubmitAccountDeactivationUseCase.swift` |
| [M] | `SupportClient/Projects/Features/AccountManagement/Domain/AccountDeactivationModels.swift` |
| [M] | `SupportClient/Projects/Features/AccountManagement/Domain/AccountManagementRepository.swift` |
| [M] | `SupportClient/Projects/Features/AccountManagement/Infrastructure/DefaultAccountManagementRepository.swift` |
| [M] | `SupportClient/Projects/Features/AccountManagement/Presentation/AccountDeactivationFlowState.swift` |
| [M] | `SupportClient/Projects/Features/AccountManagement/Presentation/AccountManagementView.swift` |
| [M] | `SupportClient/Projects/Features/AccountManagement/Presentation/AccountManagementViewModel.swift` |
| [M] | `SupportClient/Projects/Features/AccountManagement/Presentation/Components/AccountManagementComponents.swift` |
| [M] | `SupportClient/Projects/Features/Settings/Presentation/SettingsView.swift` |
| [M] | `SupportClient/Resources/en.lproj/Localizable.strings` |
| [M] | `SupportClient/Resources/zh-Hans.lproj/Localizable.strings` |

标记：`[A]` 新增或从 Spark 拷入，`[D]` 删除不对齐文件，`[M]` 手改（网络引擎 / DI / 去 MemberContext / 本地化等）。
