# 后台页面管理、OSS 直传与统一下载管理器

日期：2026-10-15；版本：v1.0；状态：开发实施规格，尚未实现。

承接 [云端预设资源需求](./03-云端预设资源与iOS加载需求.md)。本文明确本轮新增要求：现有 backoffice-web 管理系列、手帐和页面；增删页、排序后免审核发布；所有资源上传和下载直连 OSS；iOS 多任务异步下载、进度、暂停与继续必须在首期实现。与前文早期默认值冲突时，以本文为准。

## 1. 确定的边界

| 内容 | 负责位置 |
|---|---|
| 系列、手帐目录、页面顺序、下载依赖、权限 | Django + MySQL |
| 模板图片、预览、绘画、压缩包、对象 JSON | OSS |
| 后台上传大文件 | 浏览器/制作工具 → OSS |
| 解压、真实文件 hash、媒体检查、生成发布 manifest | 与 OSS 同地域的独立云处理执行器 |
| 手机下载和后台预览图片 | iOS/浏览器 → OSS HTTPS 域名 |
| 页面导入、图层编辑、用户作品保存 | iOS 本地 |

**39.106.39.110 只承担元数据和授权请求，不接收、转发、下载完整资源包，也不代理缩略图或素材。** Nginx 不设置模板资源反向代理。不能让 Celery 在该机器上下载几百 MB ZIP 解压校验；仅将上传改成直传、再由 ECS 下载校验仍违反本要求。

首期不启用 CDN，使用 OSS 原生 HTTPS 域名和签名 URL，减少配置。后续需要加速时接阿里云 CDN 并单独设计鉴权，不直接把 OSS 签名链接的域名替换成 CDN 域名。

## 2. 后台界面与操作

在现有 backoffice-web 增加“预设手帐”，不用另建后台站点。左侧系列导航，主区域手帐卡片/列表，点手帐进入页面管理；面包屑为“系列 / 手帐 / 页面”。

### 2.1 系列层

显示名称、启用状态、排序、已发布手帐数。支持新增、改名、拖动排序、停用和删除。非空系列删除返回冲突并提示先移动或删除所属手帐；不能级联物理删除 OSS 对象。停用系列后不出现在新目录中，保留旧版本记录。

### 2.2 手帐层

显示封面、名称、页数、当前版本、素材大小、更新时间、状态。支持新增手帐、完整模板包导入、改名、改简介、调整系列内顺序、移动系列、下架、删除、查看历史版本与回滚。列表每本只取一张封面图，不请求本内全部页面图片。

手帐删除先逻辑删除并从目录隐藏，既有用户作品不受影响；历史版本与资源进入保留策略，不当场删除素材。

### 2.3 单页层

显示有序缩略图、标题、尺寸、当前页依赖大小、封面/外壳标识。支持：

- 拖动页面调整顺序，也可输入位置；保存时提交完整有序页面 ID 数组。
- 删除页面：从下一个版本目录移除；不改已经发布的旧版本。删除封面页必须同时选新封面；删除外壳页必须清除或重新指定外壳；不能发布零页手帐。
- 添加页面：上传单页资源包，选择插入位置；也支持从已有模板版本中选择一页复制引用。
- 替换页面内容：上传单页包，形成新的页面修订；已有 page ID 可保持以追踪来源。
- 修改页标题、设置封面、设置/取消外壳、打开大图预览。

“上传新页”不能只交 JPG：JPG 只能成为背景/图片图层，不能自动恢复可编辑结构。上传完整单页包后才具有图层、对象、素材与文字信息。

### 2.4 保存与发布

元数据编辑先写工作草稿，页面显示“未发布更改”。按钮为“保存并发布”，点击后自动校验，成功即发布，无审核人或审核队列。上传结束后可自动继续同一次发布操作；服务器未完成校验时显示“处理中”，不提前显示已上线。

一次编辑可以合并多个删除/添加/排序动作，发布一个新版本。排序只更新索引并生成新 manifest，不重新上传图片。两名管理员同时编辑时采用 revision/If-Match 乐观锁；后保存者收到 409，刷新并重新提交，不能覆盖前者。

## 3. 数据模型补充：稳定页面与不可变版本

仅将页面存成“属于一本书的一行可修改记录”会使下载中的页序发生变化，因此需要区分工作草稿和已发布快照。

| 模型 | 关键字段和职责 |
|---|---|
| PresetTemplate | UUID 主键；唯一 template_book_id 对接现有 manifest 字符串；series、current_version、draft_revision、deleted_at |
| PresetPage | UUID 主键；所属模板；stable_page_id；逻辑页面身份 |
| PresetPageRevision | UUID；page FK；title、size、root_content_id、预览 blob、结构索引、创建时间；内容不可变 |
| PresetVersion | template、package_version、manifest blob/hash、状态、封面/外壳 stable ID；发布后不可变 |
| PresetVersionPage | version、page_revision、position；唯一(version,position)和(version,stable_page_id) |
| PresetBlob | sha256、byte_count、mime、bucket、object_key、OSS version_id（如启用）、校验状态；实际资源可跨页复用 |
| PresetPageRevisionFile | page_revision、relative_path、blob、role；唯一(page_revision,relative_path)；用于依赖闭包 |
| PresetDraftPage | template、page_revision、position；后台未发布的编排；受 draft_revision 控制 |
| PresetUploadSession | UUID、操作者、目标、预期文件大小、staging key、状态、过期时间、upload ID、错误摘要 |
| PresetPublishJob | UUID、幂等键、template、draft_revision、状态、云执行 ID、报告 key、失败原因 |

以上补充替代 03 文档中 page 表以 manifest ID 直接充当主键的简化设计，避免跨版本 ID 重复。原 file 表可以实现为版本相对路径到 PresetBlob 的映射，不必每个新版本复制 OSS 文件。

云处理执行器将资源写入服务端可写的不可变区，例如 `presets/blobs/sha256/{hash}`；浏览器只能写 staging。版本 manifest 仍使用相对路径，API 返回相对路径到 blob 的下载映射。客户端落盘后依旧组成原 `.diarypreset` 目录结构；不要求 OSS key 与本地相对路径相同。

发布新版本时复用未变更的页面修订与 blob，仅生成新页序和 manifest。页 ID、object ID、asset ID 合并冲突时，云执行器确定性重映射并重写引用，生成新的文件摘要；不能静默覆盖另一页对象。整本纸张尺寸需一致：新增不同尺寸页面默认拒绝，提示制作端转换尺寸再上传，避免后台只改宽高造成图层错位。

## 4. 上传结构与大文件直传

### 4.1 支持两种包

- **整本：** `.diarypreset.zip`，ZIP 根部直接是 package.json、pages/、objects/、assets/、previews/ 和按需 drawings/。
- **单页：** 同一格式 `.diarypreset.zip`，manifest.pages 恰好一项，coverPageID 为该页；objects/assets/files 只包含该页完整依赖闭包。新增页面不需要重新制作/上传整本。

ZIP 名称不充当业务 ID，ID 从 manifest 读取并与上传会话目标核对。单页包的来源 templateBookID 可不同于目标手帐；导入服务在新目标版本中生成正确的 templateBookID 并保留来源记录，而不是直接覆盖原包。整本覆盖更新必须匹配目标 templateBookID。

保持现有统一包 JSON 规范；无需把 series.json、全部 DiaryPresets.bundle、PSD 源文件上传。普通后台人员只需选择系列、目标手帐、文件及插入位置，结构和 hash 由制作工具生成。

### 4.2 推荐：STS + OSS Browser SDK 分片上传

后台浏览器向 Django 请求上传会话；Django 返回特定 staging key、临时 STS 凭证、过期时间、OSS region/endpoint 和服务端限制。浏览器使用 OSS SDK multipartUpload 直传，持久化 checkpoint 实现续传。阿里云文档说明 STS 可以用于浏览器直传，multipartUpload 可以用 checkpoint 恢复上传。[直传方案](https://www.alibabacloud.com/help/en/oss/user-guide/uploading-objects-to-oss-directly-from-clients/)；[Browser SDK 续传](https://www.alibabacloud.com/help/en/oss/developer-reference/resumable-upload-9)。

默认单包上传并发 3、分片大小起步 8 MiB，小文件普通 PUT。参数需适配 OSS SDK 的分片限制。临时权限只包括该会话对象的必要上传/分片操作；不授予 published/blobs 写入权限，不授予整桶遍历/删除。终止上传只允许 abort 本次 multipart。

前端 IndexedDB 保存 session ID、object key、upload ID/checkpoint、源文件大小/修改时间与摘要，不长期保存 STS secret。刷新网页后用户可能需要重新选择文件；校验文件身份一致再恢复，不能承诺浏览器重启后自动重获本地文件权限。STS 过期向 API 刷新同一会话权限，继续同一 multipart。

OSS CORS 仅允许实际后台域名（生产 https://diary.dreamwhale.top）；开放 SDK 所需方法和请求头，暴露 ETag、请求 ID 等响应头。iOS 原生请求不受浏览器 CORS 限制。长期密钥仅配置于云身份体系。

### 4.3 OSS 侧校验与登记

```text
后台浏览器 ───文件字节──► OSS staging
    │ complete(session ID)
    ▼
Django ───异步执行请求──► 云执行器（与 OSS 同地域）
    ▲                     │ OSS 内网读取、解包、hash、媒体校验
    │ 小型完成通知          │ 写不可变 blob、版本 manifest、校验报告
    └─────────────────────┘
    │ 读取有界元数据、事务登记/切换版本
    ▼
iOS 目录可见
```

建议采用阿里云函数计算执行容器化校验程序；具体地域、内存、临时磁盘、超时配额在接入时确认。若包超过单次执行预算，改用同地域专用处理 worker，不能回退为低带宽 ECS 下载包。现有发布校验代码需适配 Linux：JSON/hash/图片可在云端检验；PencilKit 等 Apple 专有数据完整可读性由制作端及 iOS 导入器检验，不能声称 Linux 可直接调用 PencilKit。

Django 只提交对象位置和会话 ID；云执行器通过独立 RAM 角色读取 OSS 并验证真实内容，生成小型报告。完成通知需鉴权、校验 job/session 对应关系、去重；浏览器 complete 和 OSS 回调只说明上传结束，不代表资源已通过校验。报告记录版本、文件映射、每页依赖和错误路径；索引量大时分页或分批登记，禁止一个无限大 JSON 压垮 API。

校验后不可变区只能由处理身份写入，避免浏览器校验后替换文件。报告绑定源对象版本/摘要和执行 ID。OSS 写入与 MySQL 没有跨服务事务：先准备全部不可变对象，再数据库事务发布；失败留下的未引用对象延迟回收，旧版本始终可用。

## 5. 后台 API（新增建议）

基础路径 `/api/backoffice/diary-presets/`，复用后台登录及权限；实际实现沿用仓库已有路由风格。

| 请求 | 用途 |
|---|---|
| GET/POST series/ | 列表、新增系列 |
| PATCH/DELETE series/{id}/ | 修改、逻辑删除；非空删除返回冲突 |
| GET/POST templates/ | 按 series 筛选、新建手帐 |
| PATCH/DELETE templates/{id}/ | 编辑基本信息、逻辑删除 |
| GET templates/{id}/pages/ | 当前草稿或指定版本页目录 |
| POST upload-sessions/ | 指定 book/page 模式、文件大小、目标及插入锚点；返回 STS |
| POST upload-sessions/{id}/refresh/ | 刷新权限，保持同一受限 key |
| POST upload-sessions/{id}/complete/ | 幂等触发云端处理；返回 202 + job ID |
| GET jobs/{id}/ | 上传后处理/失败详情/最终版本 |
| POST templates/{id}/pages/ | 加入已校验单页或已有页修订引用 |
| DELETE templates/{id}/pages/{page_id}/ | 从草稿移除页面 |
| PUT templates/{id}/page-order/ | 提交全部页面 ID；禁止重复、遗漏和外部 ID |
| POST templates/{id}/publish/ | 校验草稿后自动发布，无审核状态 |
| POST templates/{id}/rollback/ | 指向仍可用历史版本，记录操作 |

修改请求带 draft_revision/If-Match；重复 complete/publish 使用 Idempotency-Key 返回相同 job，避免重复版本。上传处理完成时若草稿已被别人修改，将页面修订保留为“可加入”并返回冲突，由管理员重新确定位置，不能覆盖当前草稿。

## 6. 浏览与下载契约

系列列表只请求系列封面；手帐列表每本仅一张封面。打开手帐详情后才请求该本 page 目录和可见页缩略图；打开大图才加载该页大预览。浏览不创建编辑资源下载任务、不校验全包、不拉取 objects/assets；下载管理器只在用户主动添加或保留离线时启动。

API 为单页或整本创建固定版本的下载计划，返回：

```json
{
  "plan_id": "uuid",
  "template_id": "city-suzhou",
  "version": 6,
  "scope": "page",
  "page_ids": ["page-01"],
  "manifest_sha256": "...",
  "total_unique_bytes": 123456,
  "files": [
    {"file_id":"uuid","relative_path":"assets/a.webp",
     "sha256":"...","byte_count":123456,"mime_type":"image/webp"}
  ],
  "next_cursor": null
}
```

示例省略部分字段；完整计划还需包含页面顺序、结构文件和全部依赖。计划与文件分页只传元数据。签名分批按需获取，例如 `POST download-plans/{id}/urls/`，传入计划内 file_ids 返回 URL/expires_at；防止整本排队时后面的链接已经过期。必须验证 file ID 属于计划及用户仍有权限，不接受任意 object key。所有 URL 指向 OSS，不出现 ECS 代理地址。

单页计划取该页依赖闭包；整本计划取该版本所有页面依赖的集合并按 blob hash 去重。页面、对象与 manifest JSON 也作为可下载文件由 OSS 提供；服务器可传同等结构的小型元数据，但不返回图片字节。计划创建后管理员调整页序不改变这次下载版本。

## 7. iOS 统一下载管理器

### 7.1 组件

建议新增 Core/Downloads 模块，业务 UI 通过协议使用：

- `ResourceDownloadManager`（actor）：全局队列、优先级、并发、任务暂停/恢复/取消、去重与订阅。
- `DownloadStore`：SQLite 持久化业务任务/资源状态、已完成范围、错误和来源版本；不用 UserDefaults 保存大清单。
- `OSSDownloadTransport`：URLSession、签名续期、Range 请求、网络重试；可供其他资源下载使用。
- `ResourceCache`：内容 hash 对应本地文件，验证后原子就位，引用计数和使用租约防清理。
- `PresetImportCoordinator`：把已完成下载交给现有 importer，持久化操作意图与导入结果。
- `DownloadCenterViewModel`：主线程显示任务快照，取消订阅不取消实际下载。

接口包含 enqueue(plan,importIntent)、pause(taskID)、resume(taskID)、cancel(taskID)、retry(taskID)、观察进度。共享 manager 在应用生命周期存在，不绑定单个详情页或 SwiftUI `.task`。

### 7.2 两级任务与共享资源

一个用户动作对应一个业务任务（添加单页/整本），下面关联多个资源任务。同一 sha256+byteCount 的资源可被多个任务引用，下载一次、校验一次；一个用户任务暂停，不应暂停另一个活跃任务仍需要的同一文件。全部订阅者暂停后才暂停共享传输；最后一个引用取消时才允许清理 partial。

资源状态：queued → downloading → verifying → ready；可进入 paused/waitingNetwork/failed/cancelled。业务任务状态：planning → downloading → verifying → importing → completed；允许 paused/waitingNetwork/failed/cancelled。下载百分比 100% 后仍显示“正在校验/添加”，直到原子导入成功才显示完成。

持久化 taskID、ownerID、operationID、目标本/插入锚点/预期 revision、template/version、pageIDs、资源列表、下载偏移/完成分段、预期 hash/大小、重试次数、状态；签名 URL 不作为文件身份。账号切换后旧账号的导入任务暂停，不向新账号作品库写入；公共模板缓存可以复用，任务和用户作品按账号隔离。

### 7.3 进度与并发

全局同时 3 个文件传输起步，单文件最多 1 个分段请求；避免“每个整本 3 个”导致任务越多并发越大。队列公平调度，可优先用户当前选中的单页，整本不长期阻塞小任务。hash/解码在工作线程，UI 节流约每 200ms 更新。

任务总量为去重后的全部所需资源字节数；进度分子为已命中已验证缓存的字节 + 每个资源已落盘有效字节，最大不超过资源预期长度。共享资源可分别计入各自任务的逻辑进度，全局网络流量只计一次。不累加 HTTP 重试流量来伪造进度。显示百分比、已准备/总大小、速度（实际新网络字节滑动平均）、可选预计时间、暂停/继续/取消。校验失败重下可以回退进度并明确提示。

### 7.4 暂停、继续与签名过期

暂停/继续为首期必需。URLSession 的 resumeData 可以恢复下载，但可能为空、临时文件可能失效，因此不能把它作为唯一可靠方案。[Apple 暂停与继续文档](https://developer.apple.com/documentation/foundation/pausing-and-resuming-downloads)。不修改 opaque resumeData 来替换过期签名 URL。

建议实现可持久化的**应用层分段下载**：小于 8 MiB 的文件一次下载；大文件按 8 MiB 范围通过 `Range: bytes=start-end` 直连 OSS，各段落独立临时文件。记录已校验长度的完整分段和远端对象标识；暂停时停止新分段并取消在途请求，完整分段保留，在途未完成段可以重下，最多损失一个分段流量。继续时获取新签名，从首个缺失分段开始，无需重新下载完整大文件。

必须检查 206、Content-Range、响应长度和同一不可变对象身份；若服务返回 200，不能把整文件追加到某段。416 时核对源大小并重新规划；403 仅确认签名过期后重签，不无限重试权限错误。合并后做完整 SHA-256，分段齐全不等于最终内容校验通过；hash 不符废弃受影响文件并有限重试。OSS Range 支持及签名头配置需在联调中验证。

资源请求尽量使用 URLSessionDownloadTask 落盘，不将整包/整文件 Data 常驻内存。后台 URLSession 可承担在途请求，App 挂起时不保证持续调度下一段；系统调度、用户强制退出均可能中断。持久化状态确保下一次启动可继续，不承诺强退后自动持续下载。

### 7.5 本地存储与原子导入

进行中的分段/任务放 Application Support/Downloads 并排除系统备份；显式保留离线的预设同样存 Application Support。普通可重下缓存放 Caches。不能只在 Caches 标记“不可清理”就承诺系统不会清理。

整本下载完成后合并已去重资源，组装带原相对路径的只读本地包，统一验证、一次导入；单页只组装该页依赖。不要把整本实现为多次独立单页导入，否则失败会留下半本。空间预算包括分段、合并临时文件、预设缓存与作品副本峰值；不够时暂停并提示清理。

已有本导入在发布前重新检查目标本 revision 和插入锚点；下载期间目标本被删则保留下载成果并让用户重新选择目标。重试复用 operationID；已经完成的 operation 直接返回原结果。导入后的可编辑作品拥有自己的持久资源，缓存淘汰不破坏作品。

## 8. 异步任务与资源回收

Django 只异步触发云端处理、接收状态、登记数据和必要的超时重试。可复用当前 Celery 做少量控制任务，消息中只放 job ID/object key，不放文件字节。上传、解压、hash、分片和媒体数据处理都留在 OSS 同地域执行器。

上传会话建议 24 小时过期，失败 staging 保留 7 天供重试；这些是可配置初值。OSS 定期 abort 过期 multipart，避免分片长期计费。已发布 blob 仅在没有任何保留版本/草稿/有效下载租约引用，且经过保留窗口后才可回收。不能对共享 blobs 使用简单“超过 N 天一律删除”生命周期规则。

普通下架停止新目录曝光/新下载计划；已授权计划建议 7 天续签窗口，保护下载中的用户。紧急撤回可单独禁止续签并返回明确错误，但已经发出的签名到期前仍可能访问；不能承诺瞬时回收用户已下载的文件或修改其作品。

## 9. 首期验收与落地顺序

1. 后台系列 → 手帐 → 单页列表、封面预览、增加/删除/排序、草稿 revision 与免审核版本发布。
2. OSS Bucket/RAM/CORS、STS 受限分片上传、独立云执行器、报告登记；失败重试不会产生重复版本。
3. 版本化页目录、依赖计划、按需签名接口；新增/排序版本复用已有 blob，不重传全本。
4. iOS 下载管理器、持久化队列、并发去重、分段暂停/继续、错误恢复与下载中心。
5. 单页和整本接入现有导入器，校验导入原子性、账号隔离和缓存独立性。

验收必须覆盖：浏览手帐列表只产生封面请求；单页请求不包含其他页独有素材；整本共享素材只传一次；任务暂停后不再开始新分段；继续保留完整分段；签名过期后仍可恢复；切页不取消任务；重启可恢复；管理员删页/排序不改变进行中的计划；两个任务共享文件时暂停一个不影响另一个；空间不足、hash 错误、强退与目标本删除不产生半成品。

通过浏览器 Network/iOS 请求日志和服务器访问日志共同确认：上传/下载文件请求的 host 是 OSS，ECS 只有元数据/凭证/状态请求。低带宽服务器流量不随素材文件体积线性增长。当前实施前仍需落实 OSS 地域、Bucket、云执行器预算和部署身份；这些配置不改变上述产品行为。

## 10. 阿里云配置清单

### 10.1 已提供的基础配置

以下是用户提供的接入参数，尚未验证资源是否存在、角色信任关系及授权是否可用。文档不保存真实 AK/SK；运行环境通过密钥管理或不入库的环境文件注入。

```dotenv
ALIYUN_ACCESS_KEY_ID=<RAM子账号AccessKey ID，由环境注入>
ALIYUN_ACCESS_KEY_SECRET=<RAM子账号AccessKey Secret，由环境注入>
ALIYUN_STS_ROLE_ARN=acs:ram::1589159843550123:role/zhaodoss
ALIYUN_OSS_BUCKET=zhaodkdream
ALIYUN_OSS_REGION=cn-beijing
ALIYUN_OSS_ENDPOINT=https://oss-cn-beijing.aliyuncs.com
ALIYUN_STS_DURATION_SECONDS=3600
```

现有配置入口为 SparkService/settings.py 与 file_manager/sts_utils，正式实现时核对其实际行为。生产必须使用受限 RAM 权限及 AssumeRole，不启用长期 AK/SK 返回客户端的开发回退。现有用户文件的权限策略不能直接扩大到模板发布区。

### 10.2 Key 的含义与资源目录

无需为每本手帐创建新的 AccessKey。AccessKey 是云身份凭证；Object Key 是 Bucket 内的对象名称，例如 `traveldiary/presets/staging/{session_uuid}/source.diarypreset.zip`。文件夹是 key 前缀，无需预先手动创建。

使用现有 Bucket 时，新增独立前缀并隔离 RAM 策略，禁止改动用户附件已有目录：

```text
oss://zhaodkdream/traveldiary/presets/
├── staging/{session_uuid}/source.diarypreset.zip
├── blobs/sha256/{sha256}                 # 已校验、不可变的共享资源
├── releases/{template_id}/{version}/package.json
├── reports/{job_uuid}/result.json        # 私有校验报告
└── indexes/{job_uuid}/...                # 大型依赖索引，分片读取
```

这些是建议目录，尚未创建；以本节统一前缀替代前文示意性的 `presets/` 路径。页面素材通过 blob hash 复用，版本 manifest 保持包内相对路径，数据库映射到 Object Key。模板 ID、版本号、session UUID 和 key 必须由服务端校验/生成，不允许浏览器任意指定 Bucket 或正式目录。

预期直连对象域名为 `https://zhaodkdream.oss-cn-beijing.aliyuncs.com`，按官方 SDK 生成签名 URL，不手拼签名。`ALIYUN_OSS_ENDPOINT` 是地域服务端点，不是业务 API 地址；iOS 业务 API 继续访问 diary.dreamwhale.top。上传凭证接口返回 region/endpoint/bucket/key，客户端不硬编码资源目录或长期凭证。

### 10.3 建议新增应用配置（待实现，不表示当前代码已读取）

| 配置 | 建议值/说明 |
|---|---|
| DIARY_PRESETS_OSS_PREFIX | traveldiary/presets/ |
| DIARY_PRESETS_UPLOAD_ROLE_ARN | 专用上传角色 ARN，待创建；可先评估现有角色，必须限制只写本次 staging key |
| DIARY_PRESETS_DOWNLOAD_URL_TTL_SECONDS | 900，下载链接有效期，与 STS 凭证有效期分别配置 |
| DIARY_PRESETS_UPLOAD_SESSION_TTL_SECONDS | 86400，应用会话有效期；STS 到期可刷新，二者不同 |
| DIARY_PRESETS_UPLOAD_PART_SIZE_BYTES | 8388608，8 MiB 起步 |
| DIARY_PRESETS_UPLOAD_CONCURRENCY | 3 |
| DIARY_PRESETS_MAX_UPLOAD_BYTES | 建议初值 1073741824（1 GiB 压缩包）；按执行器预算调整 |
| DIARY_PRESETS_MAX_EXPANDED_BYTES | 建议初值 2147483648（2 GiB 解压总量）；同时限定文件数/单文件/像素 |
| DIARY_PRESETS_PROCESSOR_REGION | cn-beijing |
| DIARY_PRESETS_PROCESSOR_RESOURCE_ID | 云执行器函数/服务的真实资源标识，待创建 |
| DIARY_PRESETS_PROCESSOR_ROLE_ARN | 云执行器 RAM 角色，待创建 |
| DIARY_PRESETS_PROCESSOR_RESULT_AUTH | 结果鉴权方式：优先云身份校验；自定义回调则用环境注入的独立 HMAC secret |
| DIARY_PRESETS_RESULT_CALLBACK_URL | 建议 https://diary.dreamwhale.top/api/internal/diary-presets/jobs/result/，路由待实现 |
| DIARY_PRESETS_STAGING_RETENTION_DAYS | 7，仅未引用 staging，不应用于共享 blobs |
| DIARY_PRESETS_DOWNLOAD_LEASE_DAYS | 7，已授权计划的续签窗口 |

上传限制是方案初值；真实包上限必须同时满足执行器临时磁盘、解压和重打包峰值、内存、超时及 ZIP 安全限制。不能仅改环境变量就承诺任意大包可处理。

### 10.4 阿里云控制台还需配置

1. **Bucket 权限：** 模板对象保持私有；核对 Bucket ACL、Bucket Policy、对象 ACL 的实际访问效果。若现有 Bucket 公共策略无法隔离模板前缀，应改用专用私有 Bucket，不直接更改现有附件访问行为。
2. **RAM/STS：** 调用身份允许 AssumeRole；角色信任策略允许该身份。上传角色权限只允许必要的 PutObject/分片操作，并用 STS session policy 进一步限制当前会话 key；最终权限是角色与 session policy 的交集。浏览器不能写 blobs/releases，不能删除或遍历其他会话。
3. **签名读取身份：** API 具有必要的正式资源只读权限，用于签发下载 URL；签名有效期不能超过其临时身份的剩余有效期。3600 秒 STS 时长还需符合角色最大会话时长。
4. **云执行器：** 北京地域部署，配置运行镜像、临时磁盘、内存、并发、超时、失败重试和日志；角色允许读 staging、写 blobs/releases/reports。OSS 数据处理使用同地域可达的内网端点；iOS 和浏览器必须使用公网 HTTPS 端点。
5. **浏览器 CORS：** 允许 https://diary.dreamwhale.top，按 SDK 实际请求允许 GET/HEAD/PUT/POST/DELETE 等所需方法及签名请求头；暴露 ETag、x-oss-request-id 等 SDK 所需头。CORS 不替代 RAM 授权；DELETE 只在实际需要且权限限制充分时开放。
6. **回调/任务通知：** 明确采用异步调用+鉴权结果回调还是云消息通知；禁止把未鉴权上传回调当发布成功依据。重复通知幂等处理。
7. **生命周期：** 配置过期 multipart 清理；staging 按会话状态/保留时间清理；共享 blobs 必须经数据库引用检查后删除，不能简单按创建时间批量清除。
8. **可观测性：** 记录 OSS 请求 ID、云执行 ID、任务 ID；设置错误率、执行失败、存储/请求/外网下行流量预算告警，不把签名 URL 或 STS secret 写入日志。

上线前仍缺：专用角色/策略确认、云执行器实例及其资源标识、Bucket 权限与 CORS 确认、处理结果鉴权配置，以及新增配置的后端代码接入。无需额外购买域名，也无需给每页或每本创建云密钥。

## 11. 统一客户端展示与下载后添加（2026-10-16）

本地 Bundle 与云端预设合并到现有“预设”系列筛选和书本网格；不另设云端书库入口。右上角提供下载管理入口。云端列表只读取封面；云端详情复用相同的封面/外壳/单页网格布局和逐页大图预览。

云端本/单页未下载显示云朵图标；页面完整依赖校验成功后标记“已下载”。书本卡片按同一模板版本下已就绪且文件仍存在的页面 ID 去重计数。部分完成显示“已下载 X / Y 页”（零页为 0 / Y）；仅全部 Y 页就绪才显示“已下载”。多个任务重复下载同一页不重复计数，旧版本不计入新版本进度；整本添加仍需要补齐缺失依赖。

单页和整本均进入同一个“添加预设”弹窗，保留本地的目标本选择、插入位置和命名流程。弹窗自动开始资源准备并显示百分比/暂停/继续，资源完整校验后启用“添加”，用户确认后再创建作品。资源下载完成不自动创建作品，也不自动跳转下载中心。关闭弹窗不取消队列；重新打开相同选择复用下载任务/已下载包。

### 单页添加三步流程（2026-10-16）

1. 预览单页：本地预设直接展示大图；云端预设先显示下载进度、暂停和继续，资源就绪后展示大图及可替换照片缩略图列表。槽位遵循现有 replaceablePhotos 规则，跳过隐藏、锁定和装饰图层。
2. 选择照片：复用一键替换照片页面，按顺序选图、查看对应关系、调整顺序；可保留原照片继续。无照片槽位时明确提示并允许继续。选择的原始照片暂存于临时目录，尚不修改任何帐本。
3. 选择帐本：新建帐本并填写名称，或选已有帐本及插入位置；点击添加后由现有原子导入器一次提交页面和替换照片。取消时清理临时照片，云端下载缓存保留。整本添加保持原流程。
