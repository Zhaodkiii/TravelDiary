# 首次用户引导

引导前三屏使用 Assets.xcassets 中的 OnboardingSpread0、OnboardingSpread1、OnboardingSpread2 本地跨页图片，分别展示洱海湖岸、喜洲古镇和周城扎染。资源随 App 打包，直接读取，无需下载。

第四屏展示六种制作风格，选择后通过现有制作入口继续。旧雨崩分层资源包、分层加载器和专用素材生成脚本已移除。

以下为历史启动与交接验证记录，其中旧版分层引导描述不再代表当前实现。

## 本次验证

- iPhone 17 Pro / iOS 26.1 模拟器 Debug 应用构建成功，完整跨页在模拟器中正常展示。
- DiaryOnboardingTests 四项测试通过。仓库原测试目标存在其他网络认证等测试的编译错误，运行时通过 EXCLUDED_SOURCE_FILE_NAMES 临时排除无关测试，并在命令行补齐支付宝 SDK 测试链接所需的 CoreTelephony / SystemConfiguration / resolv；未改动项目的测试配置及无关测试。

2026-11-03 更新：引导期间预先完成启动流程；主页面保持同一视图实例。首次书架读取结束（包括可恢复的读盘错误）上报就绪，避免完成后闪现“正在整理书架”。

异步预登录更新验证：Debug 构建成功，DiaryOnboardingTests 共 8 项通过（使用上述隔离测试命令）。模拟器确认引导期间启动认证，并验证了完成引导后登录失败时直接进入带错误提示的登录页；本次模拟器设备登录未成功，成功进入主页的端到端路径待可用登录环境验收。主页交接逻辑等待账号准备及首次书架读取就绪，原主页视图不重建。


## 2026-11-06 默认首页变更后的交接修复

现象：日志已到“Prepared signed-in account / 账号运行时准备完成”，引导仍一直显示“正在准备主页”。原因是默认 selectedTab 已改为 travelCapture，但 homeReadyAccountID 仅由 diaryEditor 书架的首读回调设置。TabView 按需加载，未选中的书架不会出现，因此引导等待永远无法满足。

TravelCaptureHomeView 现在也在首次 reload 和待处理照片恢复结束后报告就绪；根协调器只接收当前显示页的首读回调。书架页仍保留首读回调。任务被取消时不上报；首读失败时现有错误入口也可交接。新增“当前首页首读完成”和“入口就绪”日志，便于区分认证与页面加载。

新增集成回归测试 defaultCaptureTabFinishesHandoffBehindGuideWithoutOpeningShelf：在引导覆盖下挂载实际 SupportMainCoordinatorView，保持默认随记标签，验证主页就绪可以满足已请求结束的引导交接；该测试不依赖访问书架。

本次验证：iPhone 17 Pro / iOS 26.1 模拟器 Debug 构建成功，隔离运行 DiaryOnboardingTests 共 9 项全部通过。真实主页回归测试日志已出现 `当前首页首读完成 tab=travelCapture`，在不选择手帐标签的情况下完成交接判定。测试使用本地空书库和测试账号模型，不依赖真实登录网络；不代表真机网络登录的端到端验收。
