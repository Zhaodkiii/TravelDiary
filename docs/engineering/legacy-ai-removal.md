# 旧 AI 模块移除

2026-11-01：按用户明确要求移除旧 AI 功能，新画布 AI 仍处于需求阶段。

删除 Features/AISettings、App/Resources/AISettings、Projects/Core/AI，以及专用于旧配置的 Core/AIRuntime 和 Networking/API/AI。
同步移除 AppContainer 装配、设置页 ViewModel 依赖、账号启动预热、账号切换缓存、后台接口属性、存储注册和专属多语言文案。
工程使用文件系统同步目录，删除文件自动退出构建与资源集合，无需新增工程排除规则。

保留 TravelDiary.xcdatamodeld 中旧实体的历史结构，以避免直接修改既有模型造成已安装数据库兼容风险；旧仓储已移除，不再读写这些配置。既有本地模型文件仍可由存储管理识别、手动清理。不在这次代码删除中清空设备用户数据。
OCR、认证、OSS、画布、照片和字体功能保持各自职责；OCR 日志使用已有 OCR 分类。
新方案见需求文档/AI画布排版/07-独立模块目录与替换边界.md。
