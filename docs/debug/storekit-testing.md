# 正常 App 流程中的本地 StoreKit 测试

Xcode 选择 TravelDiary Scheme，Debug Run 默认绑定根目录 TravelDiary.storekit。
正常进入 App → 我的 → 寻寻仔 Pro → 选择月付/年付 → 订阅。
不再使用独立测试页面或 --test-storekit 启动参数。

本地商品：月付 cn.zhaodk.TravelDiary.member.monthly（¥18 / 月）；年付 cn.zhaodk.TravelDiary.member.yearly（¥128 / 年）。同等级、无试用。价格仅用于本地测试。

DEBUG 下 Scheme 使用 --local-storekit 明确选择本地购买（不会切换页面），未设置时再检查 AppTransaction.environment == xcode。进入本地模式后，会员链路使用 StoreKit Product / Transaction，购买和恢复更新现有会员模型；不会调用生产会员初始化，也不向服务器发送本地凭证。
真实沙盒和 Release 使用原 RevenueCat + 后端验证。测试完整沙盒链路时将 Run → Options → StoreKit Configuration 改成 None，并关闭 Run → Arguments 中的 --local-storekit。

购买成功、恢复、交易更新、重进页面或 App 回到前台会读取当前有效交易。测试页不再存在。
可通过 Xcode → Debug → StoreKit → Manage Transactions 管理交易、退款与续订。
本地会员状态不授予服务器 AI 额度、内容授权或赠券；页面标明本地测试。服务器功能需要真实沙盒联调。

测试建议：取消付款不变为会员；完成月付/年付后进入“我的 Pro”；重启后恢复显示；退款或到期后回到可购买状态；正式 Release 不包含本地交易处理代码。
