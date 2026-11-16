# 邀请体验改造记录

## 本次落地
- iOS：作品头图、活动规则折叠、奖励摘要、单条阶段进度、固定邀请入口、独立邀请记录、真实登记截止时间、奖励资产与到账记录。
- 分享：独立海报预览，链接分享、复制链接、海报分享和相册保存；拒绝权限时提供其他导出路径；不会把分享取消当作邀请成功。
- 海报：本地绘制文字与真实邀请 URL 二维码，品牌作品图与二维码分区；二维码保留白边。
- 服务端：在现有响应增加 remaining_slots、joined、records.expires_at 和登记成功 expires_at，兼容旧客户端，无数据库迁移。
- Web：成功后显示脱敏登记账号和真实截止时间；补充已安装 App 用户操作说明、装订额外费用和更易读的表单字号。
- 名额在首次生成邀请时锁定；已加入者不因名额满而失去邀请资格，服务端继续负责最终核验。
- 活动商业参数不改动；手机号/邮箱验证归因不改成未经验证的跨安装深链。

## 素材
最终使用 InvitationRealJournalHero / journal-real-v3，基于用户提供 IMG_6692.JPG、IMG_6696.JPG、IMG_7316.JPG 经 imagegen 生成的组合展示。非未经处理的商品实拍，界面标注实拍素材衍生展示。原有素材不覆盖。先前生成的独立灵感版本保留备用。

## 验证
服务端隔离 SQLite 测试：public_experience.tests_invitations + tests_invitation_otp，27项通过。
Web：npm run build 通过。
iOS：初次构建发现原有 DiaryEditorScreen.body 类型推断超时，将前段修饰器提取至 editorWithPrimaryPresentations；无交互逻辑变更。最终 arm64 iOS Simulator Debug 整包构建通过（BUILD SUCCEEDED）。

## 尚待真实环境验收
- 短信/邮件送达、正式账号跨 Web 与 App 验证、生产奖励发放与订单用券。
- 微信等渠道压缩后的扫码、相册授权与保存、VoiceOver及动态字体真机验收。
- 当前接口无好友昵称、具体不合格原因、可选作品公开授权模型；未编造数据或自动公开用户作品。
- 当前仍沿用订单页面用券，未增加未经接口支持的自动选券或虚构好友权益。
- 本次为本地源码实施，未部署线上或提交 App Store。
