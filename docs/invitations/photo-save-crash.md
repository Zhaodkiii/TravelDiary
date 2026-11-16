# 邀请海报保存闪退修复

用户栈：Photos transaction.high → savePoster closure → swift_task_checkIsolatedSwift → dispatch_assert_queue_fail。

根因：项目 SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor；savePoster 为 @MainActor。原 performChanges 闭包继承了主线程隔离，但 Photos 在后台事务队列执行闭包，运行时执行器检查失败。不是可被 catch 捕获的 Photos 错误，也不是相册权限说明缺失（Debug/Release 配置均有 NSPhotoLibraryAddUsageDescription）。

修复：主线程读取 UIImage 并编码 PNG；调用 nonisolated InvitationPhotoWriter.savePNG(Data)。在非隔离上下文构造显式 @Sendable changes 闭包，仅捕获可发送的 Data，使用 PHAssetCreationRequest.addResource 写入 PNG。闭包内不访问 View、UIImage 或 @State。授权、busy/notice 更新保持在 MainActor，只有 Photos 完成后才显示保存成功。编码失败、拒绝授权及写入失败均保留提示。

验证：使用 -default-isolation MainActor 将写入函数编译成 SIL，函数与 Photos 回调均标为 Isolation: nonisolated，未生成 checkExpectedExecutor/checkIsolated 检查。完整 iOS Simulator 构建另行验证。未调用真实相册写入；仍需安装新包，分别验证允许保存、拒绝权限和连续点击保存。
