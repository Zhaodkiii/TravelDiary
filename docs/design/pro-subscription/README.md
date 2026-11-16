# 寻寻仔 Pro 原生订阅页

已用 SwiftUI 取代 RevenueCatUI PaywallView。RevenueCat 继续提供 membership Offering、实时本地化价格、购买及恢复；服务端确认权益。未订阅用户直接查看作品、权益和套餐；已订阅用户查看有效期与管理订阅入口。设置中的 Pro 入口已开放，销售仍受服务端开关控制。

## 页面与素材

- 主视觉：Assets.xcassets/ProSubscriptionHero.imageset/hero.png。通过内置 image_gen 生成，以用户提供的 IMG_6698.JPG 装订原片为参考，清理桌面杂物，生成暖白背景的成品陈列图。此图是生成的宣传效果图。
- 装订实拍：Assets.xcassets/ProPrintedBook.imageset/book.jpg，直接复制用户的 IMG_6695 2.JPG，保持原片；仅在有效赠礼存在时展示。
- 完整生成提示词见 image-prompt.txt；原始生成文件保留在 Codex generated_images 中，项目使用的文件已复制进资源目录。
- 使用项目暖白、深棕、砖红配色；主视觉和真实样书分区展示，底部固定订阅按钮，套餐选择、自动续订说明与恢复购买可用。
- 价格示例仅在 DEBUG 的 ProSubscriptionPreview 中出现，正式界面全部读取商店商品；年费节省比例按真实月价×12计算，向下取整，币种不一致时不展示优惠比例。
- 权益文案依赖服务端 ai_production_included 与 member_content_count；不承诺无限制作、所有素材或免费印制。年费赠礼仅在生产钱包、指定年费套餐和有效活动匹配时展示；购买前预留，取消时释放。

## 后台配置

已在用户指定的 localhost:6018 后台发布活动 3「寻寻仔 Pro 年费开通礼」：

- 年费 SKU：cn.zhaodk.TravelDiary.member.yearly
- 首次付费赠标准装订抵扣券；覆盖 20 页，最高抵扣 ¥88，适用于所有已开放印制规格；运费另计。
- 2026-11-16 00:00 至 2099-12-31 23:59（北京时间），9999 名额。
- 到账有效天数沿用 30 天；当前后端发券逻辑取活动截止日与到账后有效天数的较晚值，因此该活动券的实际有效期至少到 2099 年活动截止日。
- 活动列表已显示「进行中」，证据为 campaign-published.jpg。没有在另一个生产域名重复创建活动。
- AnnualOffer 接口新增 included_pages、valid_days、ends_at，以便客户端解释赠礼范围；该服务端代码需与客户端一起发布，现有客户端字段兼容旧接口。

## 验证与预览

DEBUG 可带 --preview-pro-subscription 启动独立设计预览，不进行交易；附加 --preview-pro-plans 查看套餐及赠礼，附加 --preview-pro-monthly 选中月付。所有示例均标注不可交易。

真实 Apple 支付、生产赠券到账仍需正式账号与商店环境联调，当前未执行真实扣款。本次不涉及发布 App 或部署后端。

验证记录：iOS 模拟器构建通过；新增 3 项 ProSubscriptionTests 全部通过（实际价格的节省计算、币种不一致不展示优惠、抵扣券不承诺免费印制）。现有 iOS 完整测试工程因其他模块的旧接口与类型错误无法编译，本次通过命令行临时排除无关测试源码并补充测试链接所需系统框架运行新增用例，没有修改既有测试或工程配置。Django 印制模块 85 项测试通过，另新增的年费赠礼展示接口测试 1 项通过。模拟器检查了首屏、月付选择与按钮文案联动、赠礼实拍和深色模式，截图保存在本目录。深色模式的主按钮保持深砖红底与白字，以确保文字清晰。

参考原则：Apple 的清晰周期与收费信息；Bear 的具体权益和简洁套餐；Day One 对记录体验与纸质成品的表达。参考官方资料：

- https://developer.apple.com/app-store/subscriptions/
- https://bear.app/faq/features-and-price-of-bear-pro/
- https://dayoneapp.com/plans/
- https://www.revenuecat.com/docs/getting-started/displaying-products
- https://www.revenuecat.com/docs/getting-started/making-purchases
