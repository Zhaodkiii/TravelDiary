# 目录与预览缓存规则

适用入口：字体集市/我的字体、贴纸目录和详情、模板/相册目录、模板搜索/词库、帮助配置/分类/文章。

## 公共实现

- `CatalogResponseCache`：账号 + 业务域 + 服务地址 + 标准化查询（包含排序、筛选、分页）组成键；字体额外隔离 Billing Session。
- `ResourceCache`：统一磁盘预算、LRU、账号隔离及清理代次。目录信封包含响应体和验证时间，5 分钟内直接返回；最多保留 7 天用于展示和断网回退。
- 页面通过 `onCached` 先显示缓存；过期时等待后台刷新结果更新页面。字体/贴纸首页已接入，模板延用 `PresetLibraryCatalogCache` 首屏展示。其他读取调用仍可等待刷新结果。
- 下拉刷新传入 `forceRefresh`，跳过新鲜期，但仍合并正在进行的同键请求。共享任务不随单个调用者取消；取消的调用者不能提交结果。
- 获取成功并解码验证后才写入；HTTP 权限错误、服务端错误、解码失败不使用旧缓存掩盖。仅连接类错误允许回退。
- 收藏、字体获取、购买/会员状态变化使对应账号目录失效。清缓存或切换会话后，旧请求不能回填。

## ETag

客户端保留过期 validator 和完整响应体；需要刷新时带 `If-None-Match`。304 合并响应体并更新时间；缓存体丢失则不发送条件请求。Authorization 和 Billing Session 都参与键，`no-store` 不写 ETag。

SparkService `CatalogConditionalGetMiddleware` 对明确列出的 GET 目录提供弱 ETag，先执行鉴权、可见性和业务视图，再比较。只忽略 OSS 临时签名及图片签名过期时间，业务内容、价格、权益、版本仍参与摘要。10 分钟窗口轮换，以早于 15 分钟签名有效期强制补充新地址；客户端新鲜期仍为 5 分钟。已有 ETag 的模板 browse 保留原行为。

贴纸分页复用同窗口内相同账号、筛选和行版本的快照、游标，使响应在无内容变动时可命中 304。每页仍重新校验可见性。

## 图片

统一 `PreviewImagePipeline` 复用解码内存缓存、磁盘与并发下载。贴纸按 SHA256；字体按账号、字体 ID、版本、图片资源 ID。字体签名过期且磁盘无图时请求详情刷新 URL，保持同一版本校验。

## 实时接口

钱包、订单、会员同步、权益确认、未读数、消息、反馈工单、定制状态、上传/下载授权保持实时。AI 配置已有 ETag，沿用其专用更新机制。缓存仅用于浏览，真正购买与使用仍走服务端权益校验。

## 验证与发布

客户端 `CatalogResponseCacheTests` 与 `ResourceCacheTests`；服务端 `common.test_catalog_cache` 与 `material_library.tests_catalog`。
服务端改动位于 SparkService 仓库，部署后目录 304 才生效；客户端 TTL/图片缓存可独立生效。本次未部署线上。

## 分页快照生命周期

素材 schema=2 的快照与游标使用 `material_pagination` 缓存别名（Django RedisCache），配置 `MATERIAL_PAGINATION_REDIS_URL`，默认 `redis://127.0.0.1:6379/2`，独立键前缀 `traveldiary:material-pagination:v2`；所有 worker/实例必须连接同一 Redis，Redis 不可用时不退回本进程内存。测试环境显式使用隔离的 LocMemCache。

服务端签名和快照有效期为 1800 秒。410 的 `msg` 返回 `{code, message}`：`CURSOR_EXPIRED`（签名过期/无效）、`SNAPSHOT_MISSING`（快照不存在）、`CONTENT_UNAVAILABLE`（内容不可用）。每页继续校验账号、过滤条件及内容可见性。

客户端展示缓存与游标时效独立：继续翻页前解析 Django 签名的公开时间戳（不替代服务端验签），超过 25 分钟或格式无效立即重建分页。410 分页错误清理该账号素材目录缓存并使旧请求失效。首页、包详情、编辑器选择器及收藏包遍历最多重建一次：清除旧 cursor，强制获取第一页，成功后整体替换列表。原图仍保持原缓存。明确的 `CONTENT_UNAVAILABLE` 不触发重试；兼容旧服务端的字符串 410，仅在分页请求中执行恢复。

部署需更新服务端配置并重启服务；现存旧游标会通过一次恢复自动切换到 Redis 快照。Redis 应具备覆盖快照 TTL 的容量与运行保障；提前驱逐/重启导致的快照缺失由客户端有限恢复处理。
