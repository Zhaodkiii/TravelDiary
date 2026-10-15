# 云端预设资源与 iOS 加载需求

版本：v1.2；日期：2026-10-15；状态：方案需求，待分阶段实施。

本文承接 [预设手帐系统总需求](./README.md) 与 [统一资源包与加载协议](./01-统一资源包与加载协议.md)。目标是将随 iOS 包发布的预设资源迁到阿里云 OSS，支持在线浏览、逐页预览、添加单页和整本添加；用户添加后的内容仍是设备上的原生可编辑手帐。

> 最新实施规格见 [后台页面管理与 OSS 直传下载技术方案](./04-后台页面管理与OSS直传下载技术方案.md)：后台增删页/排序、云侧校验、资源不经过 ECS、统一下载管理器与暂停续传均为首期要求。

## 1. 现状与设计结论

当前客户端从 `DiaryPresets.bundle` 发现系列和 `.diarypreset` 包，解析 `package.json`、页面 JSON、对象 JSON、图片、绘画数据和预览图。统一包格式已有文件大小和 SHA-256；导入器会校验资源、重建 UUID、拷贝依赖并原子发布本地作品。单页/整本导入和恢复已有本地实现，云端接入应替换资源来源，不另造编辑格式。

目前扫描到雨崩 36 页/553 个素材/约 226.68 MB，苏州 21 页/301 个素材/约 153.11 MB，咖啡工坊 2 页/15 个素材/约 47.02 MB。这是 manifest 文件字节和，不是压缩后的网络流量。素材总量说明：浏览预览与下载可编辑资源必须分开，单页只下载该页依赖，不应下载整本。

**建议新增 Django app：`diary_presets`，管理系列、模板版本、发布管理、目录 API 和下载签名；阿里云 OSS 保存所有二进制与 JSON 资源。** OSS Bucket 默认私有，API 在授权检查后签发短时只读 URL；iOS 不持有 OSS AccessKey。阿里云说明预签名 URL 有有效期，持有该链接者可在有效期内下载，因此客户端不能长期保存签名 URL。[阿里云 OSS 预签名下载说明](https://www.alibabacloud.com/help/en/oss/developer-reference/v2-presign-download)

## 2. 目标与首期边界

首期实现官方模板的后台免审核登记发布、在线目录、页面预览、依赖下载、完整校验、本地导入、离线缓存和版本管理。用户上传模板、收费/订阅、用户间分享、作品云同步、在线 PSD 解析和服务端编辑不在首期范围。预设是只读分发资源；用户添加后形成独立副本，后续修改不影响模板。

## 3. 架构和职责

```text
制作工具产出 .diarypreset
       │ 发布命令/后台：校验、上传、登记、直接发布
       ▼
Django diary_presets ──元数据/目录──► MySQL
       │ API 签发单对象短时 GET URL
       ▼
私有阿里云 OSS ◄────────────── iOS 下载预览和资源
                                    │ staging / 校验
                                    ▼
                         现有导入器 → 本地可编辑作品
```

- **OSS：** 存 manifest、页面/对象 JSON、素材、绘画、缩略图和大图预览。使用专用私有 Bucket 和 RAM 最小权限账号；API 只有必要的读取/签名权限，发布身份只写指定前缀。版本发布后不可原地覆盖。
- **Django app：** 关系型元数据、发布状态、操作记录；复用现有账号/JWT。只返回目录 JSON 和签名，不代理大文件流。首期在现有 web 服务中运行，不另建服务器或容器。
- **MySQL：** 存系列、模板、版本、页面目录、文件索引与发布状态，不存二进制。
- **iOS：** 新增 Remote Provider，与 `BundleDiaryPresetProvider` 共用包/导入协议。远端资源先落本地 staging，校验后复用 instantiate、UUID 重映射和现有事务导入。
- **file_manager：** 继续管理用户照片/附件；可复用 OSS 配置或签名工具，但不拿用户私有 `ManagedFile` 表来表达官方模板版本。

## 4. OSS 对象键和发布流程

建议 key：

```text
presets/v1/series/{series_id}/{template_id}/versions/{version}/package.json
presets/v1/series/{series_id}/{template_id}/versions/{version}/pages/{file}
presets/v1/series/{series_id}/{template_id}/versions/{version}/objects/{file}
presets/v1/series/{series_id}/{template_id}/versions/{version}/assets/{file}
presets/v1/series/{series_id}/{template_id}/versions/{version}/previews/{file}
```

包内相对路径映射到固定版本前缀。服务端不接受客户端指定任意 key。上传先到 `staging/{release_uuid}/`；发布工具检查 manifest/schema、文件数和大小、SHA-256、路径穿越、引用闭包、图片真实尺寸/格式、预览存在性。校验全部通过后，将资源写入不可变版本前缀并在数据库事务中登记为 `published`，客户端立即可见，不经过人工审核。任一步失败则保持 `failed` 或 `draft`，不更新模板当前版本指针，不出现在客户端目录。下架只隐藏目录，不立即删除 OSS 文件；回滚只切换当前版本指针。

版本资源可设长期 `immutable` 缓存；API 目录使用 ETag 和短新鲜期；预签名链接的缓存时间不得超过签名期限。日志要隐藏签名 URL query。发布工具首期可以是命令行；现有 backoffice-web 管理系列、模板、单页增删/排序、上下架与发布记录；Django admin 仅作为辅助管理入口。


### 模板上传包的目录结构

上传对象是一个完整的 `.diarypreset` 目录，实际通过 ZIP（建议扩展名 `.diarypreset.zip`）上传；由 OSS 同地域云执行器解压到隔离的 staging 目录，低带宽 ECS 不读取大包。不可只上传 `package.json`、PDF/预览图，或某几张素材图。客户端添加页面依赖图层 JSON、素材与绘画数据，缺少任一被引用文件都不能正常编辑。

推荐压缩包根目录直接包含下列项目，不额外套一层同名文件夹；解压后目录名可使用模板 slug：

```text
雨崩.diarypreset/
├── package.json                 # 必需：版本化资源包 manifest
├── pages/                       # 必需：每页一个 JSON
│   ├── page-{id}.json
│   └── ...
├── objects/                     # 必需：被页面/图层引用的对象 JSON
│   ├── {object-id}.json
│   └── ...
├── assets/                      # 有图片/贴纸时必需
│   ├── {content-hash}.webp
│   └── ...
├── drawings/                    # 有 PencilKit 涂鸦数据时必需
│   └── {drawing-id}.drawing
└── previews/                    # 必需：每页至少缩略图及大图
    ├── page-{id}-480.jpg
    ├── page-{id}-1800.jpg
    └── ...
```

目录和文件名以 `package.json` 的相对路径为准，实际文件名可以不同；`pages/objects/assets/drawings/previews` 是当前约定的分类目录。路径使用相对路径和 `/` 分隔，禁止绝对路径、盘符、反斜杠、空路径、`..` 和指向包外的符号链接。ZIP 解压后不得包含系统垃圾目录（`.DS_Store`、`__MACOSX`）、工程源文件、PSD 原稿、临时文件或无引用素材。PSD 等制作源文件应单独归档，不上传运行时资源包。

### `package.json` 必需字段

上传包必须是当前客户端支持的协议版本，结构遵循 [统一资源包与加载协议](./01-统一资源包与加载协议.md)。当前协议核心字段如下：

```json
{
  "format": "TravelDiary.PresetBook",
  "schemaVersion": 1,
  "layerSchemaVersion": 1,
  "templateBookID": "yubeng-travel-memoir",
  "packageVersion": 1,
  "title": "雨崩回忆录",
  "seriesID": "hiking",
  "sortOrder": 10,
  "tags": ["徒步", "云南"],
  "pageSize": { "width": 2185, "height": 3130 },
  "coverPageID": "page-cover-id",
  "shellPageID": null,
  "pages": [
    { "id": "page-cover-id", "title": "封面", "path": "pages/page-cover-id.json" }
  ],
  "objectTable": { "object-id": "objects/object-id.json" },
  "assetTable": {
    "asset-id": {
      "id": "asset-id",
      "path": "assets/asset-hash.webp",
      "mimeType": "image/webp",
      "pixelSize": { "width": 1200, "height": 1800 },
      "sha256": "<64位小写SHA-256>",
      "byteCount": 123456
    }
  },
  "requiredCapabilities": ["image", "object", "text"],
  "requiredFonts": [],
  "files": [
    { "path": "pages/page-cover-id.json", "byteCount": 1234, "sha256": "<64位小写SHA-256>" }
  ]
}
```

示例只展示字段形状，不能原样上传：实际 `pages` 必须包含所有页面；`objectTable` 和 `assetTable` 必须完整；`files` 必须逐一枚举包内所有运行时文件（不包含 `package.json` 本身，避免自引用摘要），每项 byteCount 和 SHA-256 必须与原始字节完全一致。Page 的 `preview.thumbnailPath`、`preview.largePath` 也必须指向已纳入 files 的预览图。`drawingPath`、各 layer 的 `contentID`/`assetID` 等引用必须最终可解析。封面 ID 必须存在于 pages；可选 shellPageID 也必须存在。

`templateBookID` 应在首次创建后保持稳定且全局唯一；同一模板更新时增加 `packageVersion`，不可把版本号重置或覆盖旧版本。`seriesID` 必须对应服务端已创建的系列 slug；服务端模板 ID 和当前版本关联以发布 API 路径/发布命令参数为准，并在登记时检查 manifest 的 ID/title/series/version 与元数据一致。`schemaVersion`、`layerSchemaVersion` 和 `requiredCapabilities` 必须在当前 iOS 支持范围内。

### 自动校验与免审核发布

发布操作不设置人工审核环节。仅具备 `diary_presets.publish` 权限的管理员/发布命令凭证可以执行；普通登录用户不能创建或发布官方模板。一次发布流程必须自动完成以下步骤：

1. **接收与隔离：** 限制上传压缩包大小；生成 release UUID；保存到私有 staging。禁止直接覆盖 published 对象。
2. **安全解包：** 防 ZIP Slip、绝对路径、符号链接逃逸、重复路径、超量文件/解压膨胀；拒绝不允许的扩展名和系统垃圾文件。
3. **协议校验：** JSON 能解析、必需字段和版本兼容；模板 ID/系列/版本与请求元数据一致；页数、文件数、单文件与总尺寸不超配置上限。
4. **完整性校验：** 每个 `files[]` 路径都存在、无多余/重复记录，真实字节数与 SHA-256 相符；manifest 外不得有运行时文件遗漏。
5. **引用闭包校验：** 每页、根对象、子对象、图片素材、绘画、预览均能沿引用找到；无循环/过深对象链、越界路径、悬空 ID；页 ID 唯一且封面/外壳存在。
6. **媒体校验：** 用实际解码器检查图片格式、尺寸和像素上限；预览可解码；MIME 与文件内容相符。无效绘画数据拒绝发布。
7. **计算下载索引：** 根据图层引用递归构建每页依赖闭包，计算单页依赖字节、整本大小、页数、素材数和预览键，写入 page_file/file 表。
8. **上传与核对：** 使用不可变 OSS 版本前缀上传；核对对象数量、Content-Length/ETag（ETag 不替代 SHA-256）；登记对象 key、hash 和发布人。
9. **原子发布：** 数据库事务写入版本、页、文件、依赖关系并切换模板 current_version。只有全部成功才设 `published` 并让目录 API 可见。失败时保持旧版本指针不动，记录失败原因并清理或保留隔离 staging 供排查。

发布可由 Django 管理后台触发，也可由受保护的管理命令调用同一发布服务。上传大包优先采用 API 创建 draft/upload session、服务端返回**限定 staging 前缀和对象名的短时上传凭证**、客户端/发布工具直传 OSS、最后调用 finalize；绝不把 RAM 长期密钥给浏览器或 iOS。对于当前 200MB 级资源包，避免经过 Django/Gunicorn 请求体中转。Finalize 只触发 OSS 同地域云执行器读取真实文件进行上述校验；ECS 接收经鉴权的结果和有界元数据，不读取资源大文件，也不信任上传端自行声称的摘要。

发布成功后用户端立即可见；若发现问题，管理员可下架版本或回滚 current_version。无审核不代表跳过自动校验、权限校验和可追溯发布记录。

## 5. 数据库设计

建议所有表均由 `diary_presets` app migrations 管理，关联字段、唯一约束和检索索引需要落地。

### `diary_preset_series`

`id`、唯一 `slug`（如 hiking）、`title`、`description`、`cover_object_key`、`sort_order`、`status(draft/published/archived)`、创建/更新时间。

### `diary_preset_template`

`id(UUID)`、`series_id`、系列内唯一 `slug`、`title/subtitle/description`、`cover_page_id`、`sort_order`、`tags`、`status`、`current_version_id`、创建/更新时间。

### `diary_preset_version`

`id(UUID)`、`template_id`、`package_version`（模板内递增，唯一约束 template+version）、`schema_version`、`layer_schema_version`、可选 `min_client_version`、`manifest_object_key/manifest_sha256`、`page_count/asset_count/total_bytes`、`page_size/required_capabilities`、`release_notes`、状态（`draft/validating/published/failed/withdrawn`）、`published_at/published_by_id`、创建时间。发布版本不可变；当前版本指针可以回滚。

### `diary_preset_page`

`id`（manifest page ID）、`version_id`、`title/sort_order/width/height/root_content_id`、缩略图与大图的 key/hash/大小、页面 JSON key、`dependency_bytes`。约束 `(version_id,id)` 唯一和 `(version_id,sort_order)` 唯一。

### `diary_preset_file`

`id`、`version_id`、唯一 `relative_path`、`role(manifest/page/object/asset/drawing/thumbnail/preview)`、服务端生成的 `object_key`、`byte_count/sha256/mime_type`、可选图片宽高。索引 `(version_id,role)`。

### `diary_preset_page_file`

关联 `page_id/file_id`，由发布时解析每页完整依赖闭包，供单页精准签发；共享素材可被多个页面引用。整本依赖为版本下所有文件。发布校验必须确认每个依赖存在且摘要与 manifest 一致。

### `diary_preset_release_audit`（建议）

`version_id/actor_id/action/result/detail_json/created_at`，记录校验、发布、下架、回滚；不记录密钥或签名 URL。

模板数据不复制进用户作品表。用户作品仍由 iOS 当前文件存储负责；未来作品同步另行设计。

## 6. API 需求

基础路径 `/api/v1/diary-presets/`，JSON UTF-8，沿用 JWT。支持稳定分页、ETag/`catalog_revision` 和 request ID。

- `GET /series/`：返回已发布系列、封面、小图、模板数量、排序、revision。
- `GET /series/{slug}/templates/?cursor=...`：返回模板 ID、标题/简介、封面缩略图、页数、当前版本、资源总大小、tags 和兼容信息。仅元数据和签名小图，不返回整本素材。
- `GET /templates/{id}/versions/{version}/`：详情页数据、页序/标题/尺寸、缩略与大图 URL、单页依赖大小、整本大小、能力/字体要求。默认当前版本，也能请求明确旧版本。
- `POST /templates/{id}/versions/{version}/download-manifest/`：基于所选范围生成下载清单。

请求例：`{"scope":"page","page_ids":["page-abc"],"purpose":"import"}`；整本用 `scope=book`。响应含 manifest 摘要、版本、总字节数、URL 过期时间，以及每文件的包内相对路径、短时 GET URL、大小、SHA-256、MIME。后端按发布时的依赖表确定文件；验证 page ID 属于该版本及用户有访问权。单页仅签发该页页面 JSON、递归对象、引用素材/绘画和所需预览；整本签发全包依赖。客户端提供一个 `selected_files` 集合供部分包校验，不能对局部包错误调用“要求每个全包文件都在场”的校验。

签名 URL 建议有效期 15 分钟、只读单对象；临近过期时重新签发。限制一次签发文件数量及总字节，较大清单分页或生成短时清单对象。首期必须支持暂停和继续；大文件采用应用层分段直连下载，完成分段持久化，签名过期重签后仅补缺失分段，详见 04 文档。预览缓存键使用 `template/version/page/size`，不使用签名 URL 作缓存身份。

## 7. iOS 加载与交互

### Provider 和本地缓存

新增 `RemoteDiaryPresetProvider` / `DiaryPresetRepository` 管理目录、版本、签名和缓存。状态包含 `remoteOnly/downloading(progress)/cached/unsupported/unavailable`。本地持久化目录缓存、包版本、校验结果、下载任务；建议路径 `Library/Caches/DiaryPresets/{templateID}/{version}/`，未完成资源放 `.staging-{operationID}`。系统可清除 Caches，缺失后重下；Documents 中已导入作品不属于缓存，绝不随预设缓存淘汰。显式“保留离线包”和在途任务需存 Application Support 并排除备份，不能只标记 Caches 而承诺系统不会清除。

### 浏览和预览

1. 页面打开先显示本地目录缓存，后台用 ETag 刷新；无缓存显示加载和重试。
2. 列表只加载目录、小缩略图；限制并发和解码内存。
3. 详情显示总页数/版本/单页与整本大小，按需加载页面元数据。
4. 全屏预览按当前页懒加载大图，不预下载全书素材。
5. 预览页操作携带 `templateID/version/pageID` 与现有 `targetBookID/afterPageID`，保留用户原先从哪本进入的上下文。

### 添加单页

1. 用户选择目标本/插入位置；从某本进入时默认目标本。
2. 请求所选 page 的下载 manifest，显示依赖大小和蜂窝流量确认。
3. 并发下载依赖到 staging，显示整体字节进度、取消；签名过期重新请求。
4. 验证大小、SHA-256、schema、引用闭包、图片尺寸/类型；拒绝绝对路径、`..`、越过根目录的符号链接。
5. 组装只包含所选页及依赖的只读 Package，复用现有实例化、纸张适配、素材 UUID 映射与 `DiaryDocumentStore.importPreset` 原子事务。若现有 validator 强制全包文件齐全，应抽象依赖闭包校验，让本地完整包/远端部分包共享规则。
6. 成功后只复制所选页可达的对象和素材到用户作品，记录 `presetSource(templateID,pageID,version)`；取消或错误不产生半页，沿用 operation ID 重试。

### 添加整本

1. 详情点“整本添加”，展示整本体积和空间/流量提示。
2. 下载完整包到 staging，检查可用磁盘空间，预留下载包、导入副本和余量。
3. 完整校验 manifest.files 的大小/hash 与所有引用后复用现有整本 importer：创建临时作品目录、准备所有页和素材，再目录 move 原子发布。
4. 设置封面/外壳页、保存来源版本。取消可清除 staging；崩溃后恢复或清理；operation 重试不应产生重复作品。

首期统一下载管理器必须支持多任务异步下载、暂停、继续与重启恢复。采用分段持久化和 URLSession，后台系统调度不承诺持续运行；详见 04 文档。若启用 background URLSession，持久化 task/operation ID，并用相同 session identifier 在启动时重新关联；Apple 文档支持后台下载任务及应用重启后恢复关联。[Apple 后台下载文档](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)

### 缓存和版本

新版本下载到新目录，不覆盖使用中的版本；操作期间 pin 住版本。缓存采用 LRU，只淘汰可重下资源，不删作品或用户保留的离线包。旧版本下架不删除已缓存或已导入的内容；新版本导入记录新版本来源。签名 URL 到期时重新请求。

## 8. 安全、错误与运维

- AccessKey 只在服务器安全配置或 RAM 角色，不放 iOS、数据库可读字段、日志和 git。
- 全程 HTTPS；对模板/版本/page 白名单校验、限速和响应大小限制。发布限制单文件、总大小、文件数、图片像素和 JSON 深度，拒绝压缩炸弹与路径穿越。
- SHA-256 校验完整性，不证明发布者身份；发布端还需限制发布权限，并将 manifest 摘要与发布人写入发布记录。
- 日志记用户 ID、模板/版本、字节、耗时和 request ID；不记签名 query、模板私钥或日记内容。
- 明确错误状态：离线、未登录、无权限、下架、schema 不兼容、签名过期、空间不足、取消、hash 不匹配、OSS 超时、导入并发冲突；允许重试的错误有重试入口。
- 运维监控目录/签名 API、OSS 403/404/5xx、发布失败和缺文件。生命周期清理需确认版本未被当前发布指针或运行中的用户操作引用。

## 9. Django app 与异步任务

首期新建 `diary_presets` app，复用当前 Django 服务和 backoffice-web。大包直传 OSS 后，由同地域云执行器异步完成解压、hash、媒体检查与发布索引生成。ECS 不下载资源；现有 Celery 如参与，仅承担触发、状态查询、超时重试等控制任务。详细任务与回收规则见 04 文档。

## 10. 分期和验收

**阶段 A：** Django app、模型/migration、admin、目录/签名 API、私有 OSS 与最小 RAM 权限、发布命令。用一个两页小包验证上传、自动校验、直接发布、签名下载、hash 和下架。

**阶段 B：** iOS Provider 抽象、远端目录/预览、ETag、缓存、离线展示和失败重试。确认滚动时没有整本素材请求。

**阶段 C：** 单页依赖下载和导入。验证只下载依赖闭包；URL 过期、断网、取消、空间不足、hash 错误、目标本并发修改均不产生半页；导入页能编辑、替换图像、重启重开，作品不依赖缓存。

**阶段 D：** 整本下载/原子发布、恢复和大包优化。校验页序、封面、外壳、对象关系、来源版本；真机测试约 227 MB 雨崩、153 MB 苏州的时长、磁盘峰值、耗电和后台行为，验收暂停续传并调优并发上限。

## 11. 初始产品默认值

| 项目 | 建议值 |
|---|---|
| 目录缓存 | ETag + 10 分钟新鲜期；离线显示上次成功结果 |
| 签名 URL | 15 分钟，仅 GET；过期重新签发 |
| 图片预览 | 约 480px 列表图；详情再取约 1800px 图 |
| 图片并发 | 起步 3 路，按真机内存/滚动表现调整 |
| 文件并发 | 全局起步 3 路；首期实现分段暂停续传 |
| 蜂窝网络 | 允许浏览；大包下载前显示大小并确认 |
| Bundle 迁移 | 云端首版仍保留常用/小型内置包兜底，稳定后分批移出 IPA |

## 12. 开发前需要产品定案

1. 官方模板是否所有登录用户免费，是否有会员可见模板（决定目录和签名授权规则）。
2. 预览图是否允许匿名访问；默认按私有资源处理。
3. 后台会话的调度体验需真机确认；暂停、继续与重启恢复已确定为首期要求，具体实现见 04 文档。
4. 整本蜂窝下载是否允许；默认允许但先显示容量确认。
5. 内置 Bundle 保留多久；建议云端稳定后再逐批移除，避免首个云端版本依赖网络导致预设空白。

这些取舍不改变现有 `.diarypreset` 格式，也不影响已经导入的本地作品。
