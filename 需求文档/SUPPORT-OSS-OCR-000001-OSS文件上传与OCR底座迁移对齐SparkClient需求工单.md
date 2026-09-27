# SUPPORT-OSS-OCR-000001 OSS 文件上传与 OCR 底座迁移对齐 SparkClient 需求工单

## 1. 工单背景

SupportClient 当前已经具备部分文件缓存、文件注册 API、Markdown 图片预览、AI 设置 prompt 输入 OCR 按钮等能力，但 OSS 与 OCR 底座还没有完整迁入。

当前 SupportClient 的 `Core/FileStorage/FileCacheManager.swift` 中存在临时版 `OSSClientWrapper`：

```swift
struct OSSClientWrapper: Sendable {
    func putObject(localFileURL: URL, objectKey: String, credentials: OSSCredentialsResponse) async throws {
        _ = try Data(contentsOf: localFileURL)
        _ = objectKey
        _ = credentials
    }
}
```

这个实现只读取了本地文件，并没有真正调用阿里云 OSS SDK 上传。因此 SupportClient 当前的“文件上传”流程还不是完整功能。

SparkClient 已经有一套可复用底座：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Core/Utilities/Objective-C
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/OSS
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/OCR
```

本工单目标是把 SparkClient 中已验证的 OSS SDK、OSS 运行时配置、通用文件上传流程、OCR 编排能力迁移到 SupportClient，并在应用启动和登录后完成 OSS 配置预取，使 SupportClient 后续任意业务都能直接复用统一文件上传与 OCR 能力。

## 2. 工单编号

```text
SUPPORT-OSS-OCR-000001
```

## 3. 目标

### 3.1 OSS 目标

1. 将 SparkClient 的阿里云 OSS Objective-C SDK 引用方式迁移到 SupportClient。
2. 将 SparkClient 的 `Projects/Core/OSS` 目录迁移到 SupportClient。
3. 将 SupportClient 当前占位版 OSS 上传替换为真实阿里云 OSS 上传。
4. 将 OSS STS 拉取、缓存、刷新、过期判断、运行时配置更新流程做成通用客户端底座。
5. 应用启动和登录后参考 SparkClient 预拉取 OSS 配置。
6. 文件上传前如 STS 不存在或临近过期，自动刷新。
7. 文件上传完成后继续调用 SupportService/SparkService 的 file_manager 文件注册接口。
8. 登出、账号切换时清理 STS snapshot 与 OSS runtime credentials，避免跨账号复用。

### 3.2 OCR 目标

1. 将 SparkClient 的 `Projects/Core/OCR` 迁移到 SupportClient。
2. 保留 Vision 本地 OCR、阿里云 OCR、本地服务 OCR 的多引擎编排架构。
3. 保留 OCR 图片预处理、OCR 结果融合、术语纠错、文档提取能力。
4. 接入 SupportClient 已有 prompt 输入 OCR 入口。
5. OCR 使用的 STS 结构与 OSS 保持一致，继续复用服务端 `/api/v1/oss/ocr/sts/credentials/` 或同等接口。
6. OCR 能力作为通用 Core 能力，不绑定某个业务页面。

### 3.3 通用客户端目标

1. 文件上传、下载、缓存、OSS、OCR 均放在 SupportClient 通用 Core 层。
2. 新业务只需要注入或读取统一服务，不需要重复写 STS、OSS、缓存、MD5、注册文件逻辑。
3. SupportClient 后续客服工单附件、知识库附件、AI 小任务图片 OCR、Markdown 图片、聊天附件等均能复用同一套底座。

## 4. 非目标

本工单不做：

1. 不改 SparkService 后端业务逻辑，除非发现 SupportClient 缺少必须的 endpoint。
2. 不重写阿里云 SDK。
3. 不把 OSS AccessKey 固定写死在客户端。
4. 不绕过服务端 STS 直接使用长期密钥。
5. 不为某个具体业务页面单独开发上传逻辑。
6. 不修改 AI 设置 Core Data 工单范围。

## 5. 参考目录

### 5.1 SparkClient Objective-C SDK

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Core/Utilities/Objective-C
```

关键内容：

```text
AliyunOSSSDK/
SparkClient-Bridging-Header.h
```

`AliyunOSSSDK` 中包含：

1. `OSSClient.h/.m`
2. `OSSModel.h/.m`
3. `OSSRequest.h/.m`
4. `OSSResult.h/.m`
5. `OSSNetworking.h/.m`
6. `OSSStsTokenCredentialProvider` 相关类型
7. `OSSTask`
8. `OSSFileLog`
9. `OSSIPv6`
10. CRC64、XML、Reachability 等 SDK 辅助文件

### 5.2 SparkClient OSS Core

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/OSS
```

包含：

```text
AliyunOSSRuntimeConfig.swift
FileUtilities.swift
OSSClient.swift
OSSConfiguration.swift
OSSManager.swift
SparkOSSConfigurationStore.swift
```

### 5.3 SparkClient OCR Core

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/OCR
```

包含：

```text
AliyunOCREngine.swift
LocalServerOCREngine.swift
MedicalImagePreprocessor.swift
MedicalTermsCorrector.swift
OCRCredentialsAdapter.swift
OCRDocumentExtractor.swift
OCRFusionSelector.swift
OCRModels.swift
OCROrchestrator.swift
VisionOCREngine.swift
```

### 5.4 SparkClient 文件上传参考

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/FileStorage/FileTransferService.swift
```

### 5.5 SparkClient 启动配置参考

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Sources/App/AppBootstrapper.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/App/Sources/App/Architecture/AssemblyProducts.swift
```

### 5.6 SparkClient 网络接口参考

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Networking/API/OSS/SparkOSSAPI.swift
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/Networking/API/OCR/OCRAPI.swift
```

## 6. SupportClient 当前状态

### 6.1 已存在能力

SupportClient 当前已有：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Core/FileStorage/FileCacheManager.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Core/Networking/SupportAPIs.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Core/Networking/SupportBackend.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App/AppBootstrapper.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App/AppContainer.swift
```

已存在模型/接口：

1. `ManagedFileUploadPayload`
2. `ManagedFileRecord`
3. `ManagedFileUploadRequest`
4. `SupportFileAPI`
5. `OSSCredentialsResponse`
6. `SupportOSSAPI`
7. `ManagedFileService`
8. `FileCacheManager`
9. `OSSObjectKeyBuilder`
10. `OSSCredentialsStore`

### 6.2 当前问题

1. `OSSClientWrapper` 是占位实现，没有真实上传。
2. 没有迁入 SparkClient 的 Objective-C Aliyun OSS SDK。
3. 没有 `OSSManager` 管理客户端生命周期。
4. 没有 `OSSConfiguration` 管理 endpoint/bucket/region。
5. 没有 `AliyunOSSRuntimeConfig` 统一解析服务端 STS + 桶信息。
6. 没有 `SparkOSSConfigurationStore` 同等级的 STS snapshot 缓存。
7. `OSSCredentialsStore` 只缓存一次，没有过期判断。
8. 应用启动/登录后没有预拉 OSS STS。
9. 登出/账号切换没有统一清理 OSS runtime credentials。
10. 文件 object key 规则与 SparkClient 不一致。
11. OCR Core 目录尚未迁入。
12. Prompt 输入页已有 OCR UI 回调入口，但缺少真实 OCR orchestrator 注入。

## 7. 目标目录结构

SupportClient 目标新增或调整目录：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Core/Utilities/Objective-C
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Core/OSS
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Core/OCR
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Core/FileStorage
```

要求：

1. Objective-C SDK 目录结构优先与 SparkClient 保持一致。
2. OSS Swift 目录结构优先与 SparkClient 保持一致。
3. OCR Swift 目录结构优先与 SparkClient 保持一致。
4. SupportClient 现有 `Core/FileStorage` 可以保留，但必须替换占位上传实现。
5. 通用上传服务命名可按 SupportClient 现有风格适配，但职责必须与 SparkClient `FileTransferService` 对齐。

## 8. Objective-C Aliyun OSS SDK 迁移要求

### 8.1 文件复制

从：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Core/Utilities/Objective-C
```

复制到：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Core/Utilities/Objective-C
```

必须包含：

1. `AliyunOSSSDK` 全目录。
2. Bridging Header。
3. SDK 中所有 `.h`、`.m`、`.c` 文件。
4. SDK 中所有子目录，例如 `OSSFileLog`、`OSSIPv6`、`OSSTask`。

### 8.2 Bridging Header

SparkClient 当前文件：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Core/Utilities/Objective-C/SparkClient-Bridging-Header.h
```

SupportClient 需要创建：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Core/Utilities/Objective-C/SupportClient-Bridging-Header.h
```

要求：

1. 引入 Aliyun OSS SDK 所需头文件。
2. Xcode Build Settings 中 `Objective-C Bridging Header` 指向 SupportClient 的 header。
3. SDK `.m/.c` 文件加入 target membership。
4. Swift 侧可以直接使用：

```swift
OSSClient
OSSPutObjectRequest
OSSGetObjectRequest
OSSStsTokenCredentialProvider
OSSTask
```

### 8.3 SDK 引用方式

用户明确要求：

```text
阿里云 sdk 需要和 SparkClient 相同的引用方式
```

因此本工单要求：

1. 不改为 SPM/CocoaPods。
2. 不引入新的第三方包管理方式。
3. 与 SparkClient 一样使用 vendored Objective-C SDK 源码。
4. 保留 SparkClient 已有 Swift wrapper 调用方式。

### 8.4 Objective-C SDK 需要链接的系统库

Aliyun OSS Objective-C SDK 迁移时，除了复制源码和配置 Bridging Header，还必须在 SupportClient target 的 Xcode 配置中加入 SDK 依赖的系统库。

配置位置：

```text
SupportClient Target
→ General
→ Frameworks, Libraries, and Embedded Content
```

必须加入：

| Name | Embed |
| --- | --- |
| `CoreTelephony.framework` | `Do Not Embed` |
| `libresolv.tbd` | `Do Not Embed` |
| `SystemConfiguration.framework` | `Do Not Embed` |

要求：

1. 三个依赖都必须加入 SupportClient app target。
2. 三个依赖都必须设置为 `Do Not Embed`。
3. 不要把系统 framework 设置为 Embed。
4. 不要把 `libresolv.tbd` 复制到项目源码目录。
5. 如果 Xcode 显示为 `libresolv` 或 `libresolv.tbd`，以 Xcode 实际库名为准，但链接目标必须是 `libresolv.tbd`。
6. 如果后续新增 extension target，需要确认 extension 是否实际引用 OSS SDK；未引用则不需要重复添加。

原因：

1. `SystemConfiguration.framework` 支撑网络状态、Reachability 等能力。
2. `CoreTelephony.framework` 支撑 SDK 内部网络环境判断。
3. `libresolv.tbd` 支撑 DNS/resolver 相关符号。
4. 缺少这些系统库时，可能出现 link 阶段 undefined symbols，而不是 Swift 编译错误。

验收：

1. `CoreTelephony.framework` 存在于 SupportClient target 的 linked frameworks。
2. `SystemConfiguration.framework` 存在于 SupportClient target 的 linked frameworks。
3. `libresolv.tbd` 存在于 SupportClient target 的 linked libraries。
4. 三项 Embed 均为 `Do Not Embed`。
5. `xcodebuild` link 阶段不出现 OSS SDK 相关 undefined symbols。

### 8.5 编译风险

可能风险：

1. Bridging Header 路径未配置。
2. `.m/.c` 文件未加入 target。
3. Objective-C 符号与 SupportClient Swift 类型重名。
4. `OSSClient` 与 SupportClient 自己的 `OSSClientWrapper` 命名冲突。
5. Swift Concurrency Sendable 警告。
6. 未链接 `CoreTelephony.framework`、`SystemConfiguration.framework`、`libresolv.tbd` 导致 link 失败。

处理策略：

1. Swift wrapper 保持 `OSSClientWrapper`，Objective-C SDK 原名保持 `OSSClient`。
2. 如 SupportClient 已有同名 `OSSClientWrapper`，直接替换为 SparkClient 版本。
3. 编译错误优先按 SparkClient 配置修复，不做大范围改名。
4. link 错误优先检查 target 的系统库依赖是否与 8.4 一致。

## 9. OSS Core 迁移要求

### 9.1 文件复制

从：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/OSS
```

复制到：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Core/OSS
```

必须包含：

```text
AliyunOSSRuntimeConfig.swift
FileUtilities.swift
OSSClient.swift
OSSConfiguration.swift
OSSManager.swift
SparkOSSConfigurationStore.swift
```

### 9.2 命名适配

建议：

1. `OSSManager`、`OSSClientWrapper`、`OSSConfiguration`、`OSSCredentials` 保持不改名。
2. `AliyunOSSRuntimeConfig` 保持不改名。
3. `SparkOSSConfigurationStore` 可保留原名以减少改动，也可以改为 `SupportOSSConfigurationStore`。
4. 如果改名，必须同步所有引用和文档。

推荐使用：

```swift
final class SupportOSSConfigurationStore
```

但要求行为与 SparkClient 的 `SparkOSSConfigurationStore` 完全一致。

### 9.3 STS 配置解析

SupportClient 当前 `OSSCredentialsResponse` 字段：

```swift
let accessKeyId: String
let accessKeySecret: String
let securityToken: String
let expiration: String?
let endpoint: String
let bucket: String
let region: String?
```

SparkClient `OCRSTSCredentialsResponse` 字段：

```swift
let accessKeyID: String
let accessKeySecret: String
let securityToken: String?
let expiration: String?
let bucketName: String?
let region: String?
let endpoint: String?
```

必须统一适配：

1. SupportClient 可新增 `AliyunOSSRuntimeConfig.init?(response: OSSCredentialsResponse)`。
2. 或调整 `OSSCredentialsResponse` 兼容 SparkClient 字段命名。
3. 支持服务端 snake_case 与 camelCase 两类 key。
4. 支持 `bucket` 与 `bucketName`。
5. 支持 `access_key_id` 与 `accessKeyId`。
6. 支持 `security_token` 与 `securityToken`。
7. `expiration` 支持 ISO-8601 与 Unix 秒。

### 9.4 OSSManager 行为

必须保留 SparkClient 行为：

1. `updateConfiguration(endpoint:bucket:region:)`
2. `updateCredentials(_:)`
3. `resetRuntimeCredentials()`
4. `getValidCredentials()`
5. `ensureInitialized()`
6. `credentialsProvider`
7. 临近过期时自动刷新。
8. 并发刷新时复用同一个 `refreshingTask`，避免多次请求 STS。

### 9.5 OSSClientWrapper 行为

必须支持：

1. `putObject(data:objectKey:contentType:progressCallback:)`
2. `getObject(objectKey:progressCallback:)`
3. `downloadToFile(objectKey:fileURL:progressCallback:)`
4. `presignedURL(objectKey:expires:)`
5. `OSSTask` 到 `async throws` 的桥接。
6. 上传/下载进度回调切回 MainActor。

### 9.6 OSSConfiguration 行为

必须支持：

```swift
enum OSSConfiguration {
    static var endpoint: String
    static var bucket: String
    static var region: String
    static var useSTS: Bool { true }
}
```

要求：

1. endpoint/bucket/region 只由 STS 响应更新。
2. 不允许在代码里写死生产 bucket。
3. 不允许跨账号复用旧 bucket/STS。

## 10. App 启动与登录后 OSS 配置要求

SparkClient 参考：

```swift
await ossConfigurationStore.prefetchFromBackend(using: ossAPI)
```

SupportClient 需要在 `AppBootstrapper` 中加入同等级逻辑。

### 10.1 AppContainer 组装要求

SupportClient 当前：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App/AppContainer.swift
```

必须新增：

1. `SupportOSSConfigurationStore`
2. `OSSManager.shared`
3. `OSSClientWrapper(manager:)`
4. `FileTransferService` 或增强版 `ManagedFileService`
5. `OSSManager.credentialsProvider`

示例目标结构：

```swift
let ossConfigurationStore = SupportOSSConfigurationStore(logger: logger)
let ossManager = OSSManager.shared
let ossClient = OSSClientWrapper(manager: ossManager)

ossManager.credentialsProvider = { [weak ossConfigurationStore, backend] in
    guard let store = ossConfigurationStore else {
        throw SupportOSSConfigurationError.incompleteSTSResponse
    }
    let config = try await store.configurationForUpload(using: backend.oss)
    return OSSCredentials(
        accessKeyId: config.accessKeyId,
        accessKeySecret: config.accessKeySecret,
        securityToken: config.securityToken,
        expiration: config.credentialExpiresAt
    )
}
```

### 10.2 AppBootstrapper 要求

SupportClient 当前：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/App/AppBootstrapper.swift
```

必须增加依赖：

```swift
private let ossConfigurationStore: SupportOSSConfigurationStore
private let ossAPI: SupportOSSAPI
```

登录后账号级 bootstrap 中执行：

```swift
await ossConfigurationStore.prefetchFromBackend(using: ossAPI)
```

要求：

1. 预拉失败不阻断登录。
2. 预拉失败只记录 warning。
3. 上传前仍会通过 `configurationForUpload` 重试。
4. 同一账号只 bootstrap 一次。
5. 切换账号后允许重新 bootstrap。

### 10.3 登出与账号切换清理

必须在账号退出、token 清理、生命周期清理中调用：

```swift
ossConfigurationStore.clear()
OSSManager.shared.resetRuntimeCredentials()
```

要求：

1. 清空 STS snapshot。
2. 清空 runtime OSS client。
3. 取消刷新任务。
4. 不清理本地文件缓存，除非业务明确要求。

## 11. 通用文件上传流程要求

### 11.1 当前 SupportClient 临时流程

当前 `ManagedFileService.upload` 流程大致为：

1. `FileCacheManager.store`
2. `OSSCredentialsStore.credentials`
3. `OSSObjectKeyBuilder.makeObjectKey`
4. `OSSClientWrapper.putObject`
5. `SupportFileAPI.registerFile`

问题：

1. 第 4 步没有真实上传。
2. STS 没有过期刷新。
3. objectKey 规则与 SparkClient 不一致。
4. 没有上传进度。
5. 没有下载、presigned URL。

### 11.2 目标上传流程

必须对齐 SparkClient `FileTransferService.upload`：

1. 生成 `fileUuid`。
2. 计算 MD5。
3. 清洗文件名。
4. 先保存本地缓存。
5. 生成 OSS objectKey。
6. 通过 `SupportOSSConfigurationStore.configurationForUpload(using:)` 获取 STS 和 bucket 配置。
7. 更新 `OSSManager` endpoint/bucket/region。
8. 调用真实 `OSSClientWrapper.putObject` 上传。
9. 调用 `SupportFileAPI.registerFile` 注册 file_manager 记录。
10. 校验本地缓存 MD5。
11. 返回 `ManagedFileRecord`。

### 11.3 objectKey 规则

SparkClient 当前规则：

```swift
let objectKey = FileUtilities.makeObjectKey(
    prefix: "SparkClient/\(ymd)",
    uuidString: fileUuid,
    filename: safeFileName
)
```

SupportClient 目标建议：

```text
SupportClient/{yyyyMMdd}/{fileUuid}/{safeFileName}
```

要求：

1. 前缀固定为 `SupportClient`。
2. 日期使用 UTC `yyyyMMdd`。
3. 中间包含 fileUuid，方便解析和缓存命中。
4. 文件名必须 sanitize。
5. 不再使用当前 `supportclient/{businessType}/yyyy/MM/dd/{uuid}-{name}` 这种与 SparkClient 不一致的规则，除非服务端明确依赖。

### 11.4 文件注册

SupportClient 必须继续使用：

```text
/api/v1/files/
```

或当前 `SupportFileAPI.registerFile` 所对应 endpoint。

注册字段必须包含：

1. `file_uuid`
2. `original_name`
3. `file_size`
4. `mime_type`
5. `file_md5`
6. `is_public`
7. `business_type`
8. `business_id`
9. `file_path`
10. `object_key`
11. `storage_type = "oss"`

### 11.5 下载与预签名

本工单要求同步补齐：

1. `download(file:forceRefresh:)`
2. `cachedURL(file:)`
3. `publicHTTPSURLForObjectKey(_:)`
4. `makePresignedDownloadURL(objectKey:expires:)`
5. `list(businessType:businessID:isPublic:)`
6. `updateBusinessBinding(fileID:businessType:businessID:)`
7. `delete(fileID:)`

如果 SupportClient 当前后端 API 暂不完整，则客户端先保留接口与 TODO，不能影响上传主流程。

### 11.6 上传进度

`ManagedFileUploadPayload` 必须支持上传进度回调。

如果当前 payload 未包含 progress，需要补齐：

```swift
let onUploadProgress: (@Sendable (Double) -> Void)?
```

要求：

1. 进度范围 0.0 到 1.0。
2. OSS SDK 回调切回 MainActor。
3. UI 层可安全绑定进度。

## 12. OCR Core 迁移要求

### 12.1 文件复制

从：

```text
/Users/hua/Downloads/Reference/SparkClient/SparkClient/Projects/Core/OCR
```

复制到：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Core/OCR
```

必须包含：

```text
AliyunOCREngine.swift
LocalServerOCREngine.swift
MedicalImagePreprocessor.swift
MedicalTermsCorrector.swift
OCRCredentialsAdapter.swift
OCRDocumentExtractor.swift
OCRFusionSelector.swift
OCRModels.swift
OCROrchestrator.swift
VisionOCREngine.swift
```

### 12.2 命名适配

SparkClient OCR 内有部分医疗命名：

1. `MedicalImagePreprocessor`
2. `MedicalTermsCorrector`
3. `SparkMedicalImagePreprocessor`
4. `SparkMedicalTermsCorrector`

SupportClient 可以有两种策略：

1. 第一阶段直接复制，保持命名，保证功能先可用。
2. 第二阶段再抽象为 `DocumentImagePreprocessor` / `DomainTermsCorrector`。

本工单建议第一阶段直接复制，避免大改引入风险。

### 12.3 OCR 引擎要求

必须保留：

1. `VisionOCREngine`
2. `AliyunOCREngine`
3. `LocalServerOCREngine`
4. `OCROrchestrator`
5. `OCRFusionSelector`
6. `OCRDocumentExtractor`

`OCROrchestrator` 必须支持：

1. 单张 `UIImage` OCR。
2. `Data` OCR。
3. 本地文档 URL OCR。
4. 多图片/多文档批量 OCR。
5. progress 回调。
6. 图像预处理。
7. 多引擎并发。
8. 结果融合。
9. 术语纠错。

### 12.4 OCR 配置要求

必须迁移或创建：

1. `OCRConfiguration`
2. `OCRRequestOptions`
3. `OCRRecognition`
4. `OCRTextOutput`
5. `OCRRecognitionHints`
6. `OCRError`
7. OCR 引擎协议。

如果这些类型在 `OCRModels.swift` 中，必须整体复制。

### 12.5 OCR STS

SparkClient OCR API：

```text
GET /api/v1/oss/ocr/sts/credentials/
```

SupportClient 必须补齐：

```swift
struct SupportOCRAPI {
    func getSTSCredentials() async throws -> OCRSTSCredentialsResponse
}
```

或复用 `SupportOSSAPI` 的 STS response 类型。

要求：

1. OCR STS 与 OSS STS 数据结构保持兼容。
2. 不把 OCR 访问密钥写死到客户端。
3. STS 过期自动刷新。
4. OCR 上传临时图片或调用阿里云 OCR 时使用同一套安全策略。

### 12.6 Prompt 输入 OCR 接入

SupportClient 当前已有：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Core/UI/SparkPromptInputSheets.swift
```

其中已有：

```swift
var onOCRImage: ((UIImage) async throws -> String)?
```

AI 设置模型/智能体页面也已有 OCR 回调入口：

```text
Projects/Features/AISettings/Presentation/Root/SmallTaskEditorView.swift
Projects/Features/AISettings/Presentation/Models/ModelsSettingsAgentSheet.swift
Projects/Features/AISettings/Presentation/Models/ModelScenarioBindingsEditorView.swift
```

必须实现：

1. 在依赖容器中创建通用 `OCROrchestrator`。
2. 将 `onOCRImage` 接到 `OCROrchestrator.recognize(image:)`。
3. OCR 失败时返回用户可理解错误。
4. OCR 识别中 UI 保持 loading。
5. OCR 输出文本自动填入 prompt 输入框。

## 13. 网络 API 对齐要求

SupportClient 当前：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Core/Networking/SupportAPIs.swift
```

已存在：

```swift
struct SupportOSSAPI {
    func getSTSCredentials() async throws -> OSSCredentialsResponse
}
```

必须补齐或调整：

1. `OSSCredentialsResponse` 兼容 SparkClient 的字段。
2. `SupportOCRAPI`。
3. `SupportFileAPI.list(businessType:businessID:isPublic:)`。
4. `SupportFileAPI.updateBusinessBinding(...)`。
5. `SupportFileAPI.delete(fileID:)`。
6. 必要时新增 download URL 或 object key 查询接口。

服务端参考：

```text
/Users/hua/Downloads/Reference/SparkService/file_manager
```

要求：

1. 客户端字段与 file_manager 返回字段一致。
2. OSS 使用同一套 file_manager。
3. STS 使用同一套 OSS 配置。
4. 不新增 SupportClient 专属文件系统协议。

## 14. AppContainer 依赖注入要求

SupportClient `AppContainer` 需要新增持有：

1. `ossConfigurationStore`
2. `fileCacheManager`
3. `fileTransferService`
4. `ocrOrchestrator`
5. 必要时新增 `managedFileService`

建议结构：

```swift
final class AppContainer {
    let ossConfigurationStore: SupportOSSConfigurationStore
    let fileTransferService: FileTransferService
    let ocrOrchestrator: OCROrchestrator
}
```

如果不希望直接暴露具体类型，可新增依赖结构：

```swift
struct FileStorageDependencies {
    let fileTransferService: FileTransferService
    let fileCacheManager: FileCacheManager
    let ossConfigurationStore: SupportOSSConfigurationStore
}

struct OCRDependencies {
    let orchestrator: OCROrchestrator
}
```

要求：

1. 页面不直接创建 OSSManager。
2. 页面不直接请求 STS。
3. 页面不直接调用阿里云 SDK。
4. 上传与 OCR 都通过容器注入的服务进入。

## 15. 安全要求

1. 客户端不保存长期 AccessKey。
2. 客户端只使用服务端下发的 STS。
3. STS 缓存在内存中，不写入 UserDefaults。
4. 登出和账号切换清空 STS。
5. 日志不得打印完整 accessKeySecret。
6. 日志不得打印 securityToken。
7. 文件名必须 sanitize，禁止路径穿越。
8. objectKey 由客户端规则生成，但必须限制在 `SupportClient/` 前缀内。
9. 上传前检查文件大小限制，避免超大文件导致内存问题。
10. OCR 图片上传或远程识别必须遵守同一认证策略。

## 16. 本地缓存要求

SupportClient 当前 `FileCacheManager` 过于简化，需要对齐 SparkClient。

必须支持：

1. `save(data:fileUUID:fileName:)`
2. `cachedFileURL(fileUUID:fileName:)`
3. `validateMD5(fileUUID:fileName:expectedMD5:)`
4. `remove(fileUUID:)`
5. 安全文件名。
6. MIME type 识别。
7. MD5 计算。
8. 与 objectKey 中 fileUUID 对齐。

缓存目录建议：

```text
Caches/SupportClient/FileCache/{fileUUID}/{fileName}
```

要求：

1. 上传前先写缓存。
2. 下载后写缓存。
3. 命中缓存时校验 MD5。
4. 缓存损坏时自动移除并重新下载。

## 17. 分阶段实施计划

### 阶段 1：SDK 与 OSS Core 迁移

任务：

1. 复制 Objective-C Aliyun OSS SDK。
2. 配置 SupportClient Bridging Header。
3. 复制 `Projects/Core/OSS`。
4. 修复命名和字段适配。
5. 编译通过。

验收：

1. Swift 能识别 `OSSClient`、`OSSPutObjectRequest`、`OSSTask`。
2. `OSSClientWrapper.putObject` 可编译。
3. 未发生 SDK 符号冲突。

### 阶段 2：通用文件上传替换占位实现

任务：

1. 用真实 `OSSClientWrapper` 替换 SupportClient 占位实现。
2. 对齐 `FileTransferService`。
3. 对齐 `FileUtilities`。
4. 对齐 `FileCacheManager`。
5. 上传后调用 `SupportFileAPI.registerFile`。

验收：

1. 实际文件能上传到 OSS。
2. file_manager 中能生成记录。
3. 本地缓存存在且 MD5 正确。
4. 上传进度可回调。

### 阶段 3：App 启动 OSS 配置

任务：

1. `AppContainer` 注入 `SupportOSSConfigurationStore`。
2. `OSSManager.credentialsProvider` 接入 `backend.oss`。
3. `AppBootstrapper` 登录后预拉 OSS STS。
4. 登出/账号切换清理 OSS runtime。

验收：

1. 登录后日志显示 OSS 配置预拉成功或 warning。
2. 预拉失败不影响登录。
3. 上传前可自动刷新 STS。
4. 登出后旧 STS 不再可用。

### 阶段 4：OCR Core 迁移

任务：

1. 复制 `Projects/Core/OCR`。
2. 补齐 `SupportOCRAPI`。
3. 创建 `OCROrchestrator` 依赖。
4. 接入 prompt 输入 OCR 回调。
5. 编译和运行验证。

验收：

1. Vision OCR 可用。
2. 阿里云 OCR 在配置可用时可用。
3. 多引擎融合逻辑可编译。
4. Prompt 输入图片 OCR 能填入文本。

### 阶段 5：下载、预签名、业务复用

任务：

1. 补齐下载与缓存。
2. 补齐 presigned URL。
3. 补齐业务绑定更新。
4. 补齐文件删除。
5. 给客服附件、知识库、Markdown 图片等业务预留接入点。

验收：

1. 上传后的文件可下载。
2. 缓存命中时不重复下载。
3. 预签名 URL 可访问。
4. 删除/绑定接口按服务端能力工作。

## 18. 验收标准

本工单完成必须满足：

1. SupportClient 包含阿里云 OSS Objective-C SDK。
2. SDK 引用方式与 SparkClient 一致。
3. SupportClient 可以通过真实 OSS SDK 上传文件。
4. `OSSClientWrapper.putObject` 不再是占位实现。
5. 上传前自动获取 STS。
6. STS 临近过期自动刷新。
7. 登录后会预拉 OSS 配置。
8. 预拉失败不阻断登录。
9. 登出/账号切换清理 OSS runtime credentials。
10. 文件上传后 file_manager 注册成功。
11. 文件缓存保存、命中、MD5 校验可用。
12. 上传进度回调可用。
13. public HTTPS URL 拼接可用。
14. presigned URL 可用。
15. OCR Core 文件完整迁入。
16. Vision OCR 可用。
17. 阿里云 OCR 的 STS 获取流程可用。
18. Prompt 输入 OCR 回调可用。
19. `xcodebuild` 通过。
20. 文档更新主工单链接。

## 19. 风险与处理策略

### 19.1 Objective-C SDK 编译风险

风险：

SDK 文件多，target membership 或 bridging header 容易漏。

策略：

1. 先完整复制目录。
2. 对比 SparkClient Xcode target 配置。
3. 按编译错误逐个补 target membership。

### 19.2 STS 字段不一致风险

风险：

SparkClient 与 SupportClient 当前 response 字段命名不一致。

策略：

1. `OSSCredentialsResponse` 解码兼容 snake_case/camelCase。
2. `AliyunOSSRuntimeConfig` 同时支持 bucket/bucketName。
3. 缺少 endpoint/bucket/region 时明确抛出 `incompleteSTSResponse`。

### 19.3 跨账号凭证污染风险

风险：

用户 A 的 STS 被用户 B 上传复用。

策略：

1. 登出清理。
2. 账号切换清理。
3. bootstrap 按 accountID 去重。
4. STS 不落盘。

### 19.4 占位实现残留风险

风险：

`OSSClientWrapper` 名称相同，可能误用 SupportClient 旧占位实现。

策略：

1. 删除或替换旧占位 `OSSClientWrapper`。
2. 全局搜索 `putObject(localFileURL:objectKey:credentials:)`。
3. 统一使用 SparkClient 风格 `putObject(data:objectKey:contentType:progressCallback:)`。

### 19.5 OCR 医疗命名适配风险

风险：

SparkClient OCR 有医疗预处理/词库命名，SupportClient 是客服应用。

策略：

1. 第一阶段保留命名，保证功能可用。
2. 不在本工单做大规模抽象重命名。
3. 后续可单独创建 OCR 领域词库抽象工单。

## 20. 实施检查清单

### SDK

- [x] `Core/Utilities/Objective-C/AliyunOSSSDK` 已复制到 SupportClient
- [x] `SupportClient-Bridging-Header.h` 已创建
- [x] Bridging Header Build Settings 已配置
- [x] OSS SDK `.m/.c` 文件已加入 target
- [x] `CoreTelephony.framework` 已加入 target，Embed 为 `Do Not Embed`
- [x] `SystemConfiguration.framework` 已加入 target，Embed 为 `Do Not Embed`
- [x] `libresolv.tbd` 已加入 target，Embed 为 `Do Not Embed`
- [x] Swift 可以访问 OSS SDK 类型

### OSS Core

- [x] `Projects/Core/OSS/AliyunOSSRuntimeConfig.swift` 已迁移
- [x] `Projects/Core/OSS/FileUtilities.swift` 已迁移
- [x] `Projects/Core/OSS/OSSClient.swift` 已迁移
- [x] `Projects/Core/OSS/OSSConfiguration.swift` 已迁移
- [x] `Projects/Core/OSS/OSSManager.swift` 已迁移
- [x] `SupportOSSConfigurationStore` 已实现或 `SparkOSSConfigurationStore` 已适配
- [x] `OSSCredentialsResponse` 字段兼容已完成

### 文件上传

- [x] 旧占位 `OSSClientWrapper` 已删除或替换
- [x] `FileTransferService` 已迁移或 `ManagedFileService` 已升级
- [x] 上传前保存本地缓存
- [x] 上传前获取/刷新 STS
- [x] 上传时调用真实 OSS SDK
- [x] 上传进度回调可用
- [x] 上传后注册 file_manager
- [x] 上传后校验本地缓存 MD5
- [x] objectKey 规则与本工单一致

### App 启动

- [x] `AppContainer` 注入 OSS Store
- [x] `AppContainer` 注入真实 OSS Client
- [x] `OSSManager.credentialsProvider` 已配置
- [x] `AppBootstrapper` 登录后预拉 OSS STS
- [x] 预拉失败不阻断登录
- [x] 登出/账号切换清理 OSS runtime

### OCR

- [x] `Projects/Core/OCR/AliyunOCREngine.swift` 已迁移
- [x] `Projects/Core/OCR/LocalServerOCREngine.swift` 已迁移
- [x] `Projects/Core/OCR/MedicalImagePreprocessor.swift` 已迁移
- [x] `Projects/Core/OCR/MedicalTermsCorrector.swift` 已迁移
- [x] `Projects/Core/OCR/OCRCredentialsAdapter.swift` 已迁移
- [x] `Projects/Core/OCR/OCRDocumentExtractor.swift` 已迁移
- [x] `Projects/Core/OCR/OCRFusionSelector.swift` 已迁移
- [x] `Projects/Core/OCR/OCRModels.swift` 已迁移
- [x] `Projects/Core/OCR/OCROrchestrator.swift` 已迁移
- [x] `Projects/Core/OCR/VisionOCREngine.swift` 已迁移
- [x] `SupportOCRAPI` 已补齐
- [x] Prompt 输入 OCR 回调已接入

### 验收

- [x] `xcodebuild` 通过
- [ ] 登录后 OSS STS 预拉日志正常
- [ ] 上传文件成功进入 OSS
- [ ] file_manager 记录创建成功
- [ ] 退出重进后可下载已上传文件
- [ ] STS 过期后上传会自动刷新
- [ ] 登出后旧 STS 被清理
- [ ] Vision OCR 可识别图片
- [ ] Prompt 输入 OCR 可回填文本
- [ ] 阿里云 OCR 配置可用时可执行

## 21. 完成后需要更新的文档

完成实现后，需要更新：

```text
/Users/hua/Downloads/Reference/SupportClient/需求文档/SUPPORT-ARCH-000001-SparkClient底层核心架构迁移需求工单.md
```

建议新增：

```text
SUPPORT-OSS-OCR-000001 已完成：
- Aliyun OSS Objective-C SDK 已按 SparkClient 引用方式迁入
- OSS Core 已迁入 Projects/Core/OSS
- 文件上传已从占位实现切换为真实 OSS SDK 上传
- App 启动/登录后已预拉 OSS STS
- OCR Core 已迁入 Projects/Core/OCR
- Prompt 输入 OCR 已接入通用 OCROrchestrator
```

## 22. 快速修复子工单：OSS STS bucket_name 字段兼容

已新增快速修复工单：

```text
/Users/hua/Downloads/Reference/SupportClient/需求文档/SUPPORT-OSS-STS-000001-OSS_STS_bucket_name字段兼容快速修复工单.md
```

触发日志：

```text
响应解码成功 type=OSSCredentialsResponse keys=root=[code,data,msg] data=[access_key_id,access_key_secret,bucket_name,endpoint,expiration,region,security_token]
OSS STS 预拉取：字段不完整，未缓存 ownerAccountID=810 phase=bootstrapIfNeeded
```

问题结论：

1. 服务端返回 `bucket_name`。
2. SupportClient 当前 `OSSCredentialsResponse.bucket` 只兼容 `bucket` / `bucketName`。
3. 解码成功但 bucket 为空，导致 `AliyunOSSRuntimeConfig(response:)` 返回 nil。
4. 需要同时修复 `OSSCredentialsResponse` 与 `OCRSTSCredentialsResponse` 的 `bucket_name` 兼容。
