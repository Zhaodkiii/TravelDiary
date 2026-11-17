# iOS 1.6（10）发布记录

构建内容：游客可直接进入 Pro 购买页，设备账号允许计费初始化与年付赠券预留，恢复提示指向 Apple 账户；设置页展示游客会员状态。

本地验证：26 项后端测试通过，Debug 模拟器构建通过。

Release 归档：`/tmp/TravelDiary-GuestPurchase-1.6-10.xcarchive`
归档日志：`/tmp/guest-release-archive.log`

## 提审前依赖

- 部署 SparkService 的 billing/identity.py 与 print_orders/campaigns.py 改动。
- 解决审核账号无法登录的 2.1 问题并验证。
- 完成跨设备恢复、登录已有账号的权益衔接与沙盒真实购买验证。

归档成功。构建 1.6（10）已上传 App Store Connect，上传进程退出码为 0，详细回执见 `/tmp/guest-release-upload.log`。

尚未替换审核构建、重新提交或正式发布。
