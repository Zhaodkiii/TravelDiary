# 「我的」与设置重构

日期：2026-11-16

## 信息架构

- 我的：账户与安全、Pro 状态卡、制作额度。
- 我的服务：印制订单、我的优惠券、邀请有礼。
- 应用设置：创作偏好、存储空间。
- 支持：帮助与反馈、关于寻寻仔。
- 开发版本：开发工具（仅 `#if DEBUG`）。
- 素材：浏览 / 我的；我的包含已下载模板与相册、我的贴纸、我的字体。

## 页面和流程

首页使用原生 insetGrouped 列表，统一品牌强调色、32pt 图标容器、小标题、自动换行。普通行最小内容高度 40pt，加上下内边距后至少 52pt；辅助说明行会自动增高。没有自定义底栏覆盖，继续使用共享 NavigationStack 和系统 TabView。

会员卡读取同账户的 BillingStore 状态：待同步优先，已取消续订仍有效、宽限期、到期等沿用 MembershipStatus 的真实文案与日期。查询失败显示重试，不伪装为免费账户或零额度。设备账户先进入既有登录升级流程。会员卡不承诺赠礼一定可领，价格、销售开关与资格仍由现有订阅页确认。

优惠券 → 选择可用券 → 选择本账户手帐 → 现有印制结算页（传入 preferredCouponID）。抵扣范围、金额、运费和券占用均由结算/服务端校验；过期、已使用和订单占用券不显示使用按钮。读券或读书架失败显示错误与重试，不作为空列表。

创作偏好保留自动保存、排版方式、制作动画开关及风格。沿用原 AppStorage 键，升级不重置用户选择。

字体存储移至存储空间，仍使用原 FontStorageScreen，不改变正在注册字体的删除保护。高级本机数据分类收进 DisclosureGroup，原有安全清理、恢复、最近删除规则不变。

制作引导移到帮助与反馈，继续使用现有引导组件。隐私政策、用户协议、版本信息移至关于页；登录和支付上下文的协议链接保持原流程。

## 开发与正式版本

开发工具包括钻石钱包测试、购买/已订阅页面预览、背景生成实验、动画照片对比。页面和动画对比组件都由 `#if DEBUG` 隔离。未使用的并行 AI 设置声明已删除。

预览启动参数：`--preview-personal-center`。预览复用实际 SettingsView，使用设备账户样例并跳过首页网络刷新，不读写真实订阅；仅 Debug 编译。预览中的其他占位 tab 不代表业务功能测试。

## 验证记录

- 最终 Debug 构建与 Release 构建均通过；相关回归测试 23 项通过。构建日志保存在 `/tmp/traveldiary-settings-debug.log`、`/tmp/traveldiary-settings-release.log`、`/tmp/traveldiary-settings-tests.log`（完整测试 target 的已知编译失败日志）。
- `light.png`、`dark.png`、`large-text.png` 为模拟器实际渲染截图（预览入口，非真实账户）。
- 本次不发布应用、不发起真实购买或印制订单。
- 已登录会员、真实券与结算联动仍需要使用对应账户在真机验收；预览不代替线上交易验证。

### 局部回归

会员、存储、帮助三个测试组共 23 项通过。命令使用 `-only-testing:TravelDiaryTests/ProSubscriptionTests`、`StorageManagementTests`、`HelpFeedbackTests`。

完整测试 target 在运行前被已有编译错误阻断：PresetBrowseTests、SupplyChainBracketLayoutTests、SupportAuthSessionInvalidationTests、SupportAuthSessionPersistenceTests、SupportNetworkCoreETagRetryGateTests、SupportNetworkEngineAuthTests、OSSCredentialsBucketNameDecodeTests、TelegramPhotoEditorRendererTests。

为运行相关测试，仅在此次命令通过 `EXCLUDED_SOURCE_FILE_NAMES` 排除其余测试源文件，并通过 `OTHER_LDFLAGS=$(inherited) -framework SystemConfiguration -framework CoreTelephony` 补齐测试 target 的支付宝 SDK 链接依赖。未修改测试文件、项目配置或断言。局部通过不代表全量测试通过。完整局部日志：`/tmp/traveldiary-settings-tests-focused.log`。

最终视觉检查：浅色、深色、最大辅助字号均已实际渲染检查。最大辅助字号下内容按行增高并滚动展示；当前截图为设备账户预览。真实账户的完整跳转与交易需要真机验收。
