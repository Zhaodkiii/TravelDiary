# 微信分享兼容性修复（2026-11-16）

截图显示微信系统分享扩展提示“不支持此类型内容”。当时入口为 SwiftUI ShareLink(URL, SharePreview(Image))；代码没有创建微信网页消息。可以确认故障在系统分享接收阶段，具体被微信拒绝的 NSItemProvider 表示没有真机日志，不能断言是某个 UTI 或图片尺寸。网页 Open Graph 不能改变该接收协议。

用户确认尚未申请微信开放平台 AppID / Universal Link。本地构建产物中的两个对应值为空。因此当前默认使用 UIActivityViewController，且 activityItems 只有一个 String（简短文案 + HTTPS 邀请链接），不传 Transferable URL、图片预览、多项混合数据。保留图片海报和复制链接入口。此模式不承诺带自定义封面的微信网页卡片。

预备的原生路径只有 isConfigured 为真才显示：WXWebpageObject.webpageUrl + WXMediaMessage + SendMessageToWXReq，bText=false，scene=WXSceneSession。复用项目原有 SDK 注册及 URL/Universal Link 回调，避免两个 delegate 抢占。分享回调与支付回调分流，取消或失败提示可见；WXApi.send completion 只代表请求交接，绝不改变奖励/邀请成功状态。缩略图按比例缩放并 JPEG 压缩至严格小于 32 KB。

## 资料核对与限制

已进行实时网络检索并尝试访问微信官方文档，官方网页本次返回无法读取，未把第三方转载视为最新规范。没有证据支持宣称已确认 2026 年最新 SDK 版本，也未无依据升级 SDK。

官方入口：
- https://developers.weixin.qq.com/doc/oplatform/Mobile_App/Share_and_Favorites/iOS.html
- https://developers.weixin.qq.com/doc/oplatform/Mobile_App/Access_Guide/iOS.html

本次可直接核验的腾讯一手资料是项目内 SDK Headers：
`Vendor/WeChat/WechatOpenSDK.xcframework/ios-arm64/WechatOpenSDK.framework/Headers/WXApiObject.h`：标题 512 字节、描述 1 KB、thumbData 64 KB、webpageUrl 非空且不超过 10 KB。实现选择更保守的 32 KB 缩略图。`WXApi.h` 说明注册及 delegate 回调契约。

原生卡片后续启用需要在微信开放平台申请并审核移动应用、正确配置 Bundle ID / AppID / Universal Link 与网站关联文件，再向构建注入 WECHAT_APP_ID / WECHAT_UNIVERSAL_LINK。不得仅填一个猜测域名。当前配置为空时不显示专用微信入口。

## 验收

线上邀请链接请求返回 HTTP 200。未发送任何微信消息；没有真机微信实测，不能宣称已解决所有客户端版本的兼容性。新 App 安装后应验证：系统文案分享至微信、接收方点链接、海报扫码、取消分享。原生路径配置后另测：封面/标题、取消/失败回调、Universal Link 返回及支付回归。
