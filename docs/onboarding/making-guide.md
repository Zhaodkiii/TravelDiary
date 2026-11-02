# 首次用户制作引导

以「旅行随记 9」第一页「雨崩，慢一点」为内置演示，按收集 → 背景 → 照片 → 贴纸 → 文字推进。每次点击只推进一个阶段，已完成内容保留。背景采用 12 行交替笔刷遮罩逐步揭示原有背景图，不冒充原作者的真实笔画录制。

入口在 ContentView：新安装且没有消费过首次游客入口时，在创建 AppCoordinatorView 之前展示。完成或跳过使用安装级 UserDefaults 标记 diary.onboarding.completed.v1；中途退出不标记完成。已有用户不强制展示。设置 → 通用 → 重看制作引导可随时打开，关闭不更改首次标记，也不创建书本或示例记录。

动画期间主按钮不可点击；可以直接看本步效果，随时跳过或回退。重播只重置当前阶段，task 随步骤/重播/关闭取消。减少动态效果时直接呈现阶段完成状态。应用返回前台会重播尚未完成的步骤。

资源位于 DiaryOnboarding.bundle，仅含第一页、13 个对象、19 张限边 1600 像素的离线素材。使用 DiaryPageRenderer 渲染透明分层，保留原图层顺序、照片裁切、撕纸边框与字体样式，不改动源文件。可用 scripts/prepare_onboarding_sample.py 从导出的书重新准备资源（需要 Pillow）。

Debug 启动参数 `-diary-onboarding` 可强制展示，用于模拟器验收。正常启动仍遵循首次规则。测试 DiaryOnboardingTests 覆盖首次资格、中断后资格、完成持久化、已有用户及内置素材渲染分组。

## 本次验证

- iPhone 17 Pro / iOS 26.1 模拟器 Debug 应用构建成功，完整跨页在模拟器中正常展示。
- DiaryOnboardingTests 四项测试通过。仓库原测试目标存在其他网络认证等测试的编译错误，运行时通过 EXCLUDED_SOURCE_FILE_NAMES 临时排除无关测试，并在命令行补齐支付宝 SDK 测试链接所需的 CoreTelephony / SystemConfiguration / resolv；未改动项目的测试配置及无关测试。
