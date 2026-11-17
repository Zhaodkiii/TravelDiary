# 免注册购买改造（2026-11-17）

## 已实施

- 设置页的 Pro 入口、会员状态刷新对设备账号开放。
- BillingStore 使用已认证设备账号建立计费身份，移除正式账号要求。
- AI 额度页允许设备账号进入购买页。
- 后端 bootstrap 接受有效设备账号，保留 Apple 环境证明、会话归属及环境隔离。
- 年付赠礼预留及取消对设备账号开放，实体印制订单的收货流程不受影响。
- 恢复购买明确提示使用原购买的 Apple 账户。
- 原地升级为正式账号时复用已有 BillingIdentity，不重建 RC ID。

## 验证

后端命令（SparkService 目录）：

```
.venv/bin/python manage.py test billing.tests_routing billing.tests_membership print_orders.test_annual_offer --settings=SparkService.test_settings --noinput
```

覆盖游客身份重复初始化、失效账号拒绝、跨账号计费会话隔离、原地注册升级身份连续性、赠礼重复预留与取消，以及现有会员快照及回调逻辑。

验证结果：后端 26 项测试通过；iOS Debug 模拟器构建通过；两个仓库 diff 格式检查通过。尚未执行真实 Apple 付款。

## 发布前未完成项

这些代码改动不构成跨设备恢复已验证的证明，不能直接据此重新提审。

- 核实 RevenueCat 当前 Restore Behavior。此前为 Keep with original App User ID，新的设备账号将无法据此恢复旧身份的购买。不要仅为通过恢复测试直接修改生产策略。
- 当前 TRANSFER 回调仅失效双方会员缓存，不合并钱包、业务所有权或 AI 额度。多设备会员共享和额度连续性仍需订阅归属设计及实现。
- 登录已存在账号会切换 account_id，当前改动未迁移游客的购买、额度和券。原地绑定新身份与登录已有账号是不同场景。
- 年付回调已有交易 grant_key 去重；订阅转移后首购资格和赠券展示仍需跨账号验证。
- 使用真实沙盒月付、年付分别验证购买、解锁、取消、重启、退款、重装恢复和两设备恢复。
- 后端必须先部署开放设备计费与赠礼预留的接口，随后发布 iOS 新构建。
- 审核备注移除“必须登录 App 账号”的购买前置说明，补充游客购买路径与真实测试截图。

生产环境与 RevenueCat 配置未在本次修改。
