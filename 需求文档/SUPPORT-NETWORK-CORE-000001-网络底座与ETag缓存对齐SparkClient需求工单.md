# SUPPORT-NETWORK-CORE-000001 网络底座与 ETag 缓存对齐 SparkClient 需求工单

## 0. 最新状态校准（2026-07-17）

本轮重新按最新源码校准后，本工单不能再按“SupportClient 网络底座完全未迁移”的旧前提执行。SupportClient 当前已经具备一批底层网络能力，后续应在保护现有行为的基础上补齐 SparkClient 的剩余内核能力。

### 0.1 当前源码基准

本轮以以下目录作为唯一有效源码基准：

```text
/Users/hua/Documents/project/Reference/SupportClient
/Users/hua/Documents/project/Reference/SparkClient
```

当前检测到：

```text
/Users/hua/Downloads/Reference
```

不是可用项目目录，而是普通文件；后续不得再把它当作 SupportClient / SparkClient 的源码镜像目录使用。

### 0.2 SupportClient 最新已具备能力

SupportClient 当前已经具备下列能力，不能在实现 ETag 对齐时回退或重写丢失：

1. `SupportHTTPMethod`、`SupportBody`、`SupportNetworkRequest`、`SupportTransportResponse` 等基础请求/响应模型。
2. `SupportNetworkTransport` 与 `URLSessionNetworkTransport`。
3. `SupportNetworkEngine.sendRaw` 作为当前请求执行入口。
4. `AuthTokenProvider`，包含 Keychain token 读写、access token 过期刷新、refresh 并发去重。
5. 401 后强制 refresh token 并重试的核心链路。
6. `SupportAuthSessionInvalidation` 失效通知链路。
7. `SupportNetworkOperation` 与 `CacheableSupportNetworkOperation`。
8. `SupportBackendConfiguration.execute` 与 `executeDecoded`。
9. `SupportCallbackCache` 并发同类 GET 请求回调合并。
10. `SupportAPIResponseDecoder` 统一包裹响应解码与 JSON keys 日志。
11. `SupportNetworkingStrings`、`SupportNetworkOperationBusinessPurpose`、原始 request/response 报文日志。
12. `SupportBackend` 已组合 `auth`、`otp`、`device`、`files`、`oss`、`ocr`、`aiConfig`、`deactivation`、`accountIdentity`。
13. `SupportBackendConfiguration` 已打印 operation 业务目的、method、path、query、requiresAuth、allowRetry、serialKey 等调试信息。
14. 取消请求已有 `SupportCancellationClassifier` 与 `SupportNetworkError.cancelled` 语义。
15. 部分业务 API 已移动到 `SupportClient/SupportClient/Projects/Core/Networking/API`，例如 `Account`、`Auth`。

因此，旧工单中关于 Operation、CallbackCache、日志、Decoder、token refresh “完全缺失”的描述已经过期。后续实现应把这些能力视为既有资产，只做补齐、搬迁、抽层和测试保护。

### 0.3 当前仍缺少的 SparkClient 网络内核能力

对比 SparkClient `Projects/Core/Networking` 后，SupportClient 当前仍缺少：

1. `RetryConfig`、`RetryPolicy`、`RetryAfterParser`、`RetryScheduler`。
2. `RequestQueuePriority`。
3. `SerialRequestGate`。
4. `NetworkStrategy.allowETag`。
5. `NetworkStrategy.retryConfig`。
6. `NetworkStrategy.isIdempotent`。
7. `NetworkStrategy.queuePriority`。
8. `NetworkStrategy.etagTTL`。
9. `SupportTransportResponse.didMerge304` 或等价最终响应标记。
10. `ETagCacheRecord`。
11. `ETagStore`。
12. `FileETagStore`。
13. `ETagHTTPInterceptor`。
14. ETag cache key 按 `URL + Authorization` 指纹隔离。
15. `If-None-Match` 出站条件请求。
16. `X-Cache-Max-Age` 可选请求头。
17. 2xx + `ETag` 写入本地缓存。
18. 304 + 本地 body 合并为可解码成功响应。
19. ETag 请求强制 `URLRequest.cachePolicy = .reloadIgnoringLocalCacheData`，避免 URLSession 本地缓存透明合并吞掉真实 304。

### 0.4 本工单优化后的执行原则

1. 以 SparkClient `Projects/Core/Networking` 的底层架构为最终准绳。
2. SupportClient 当前实现如果和 SparkClient 差异较小，可以保留并适配。
3. SupportClient 当前实现如果和 SparkClient 差异过大，支持推倒重来，直接用 SparkClient 的底层实现覆盖替换。
4. 不回退 SupportClient 已经完成且 SparkClient 不冲突的日志、401 refresh、auth invalidation、OSS/OCR/AIConfig API 组合能力。
5. 优先把 SparkClient 缺失的通用内核能力补入 SupportClient。
6. 目录结构必须向 SparkClient 对齐，允许先保证编译与行为，再清理旧目录。
7. ETag 必须默认关闭，通过 `NetworkStrategy.allowETag = true` 按接口显式启用。
8. 非 GET 请求默认不得自动重试；只有显式 `isIdempotent = true` 才允许进入重试策略。
9. 首批 ETag 只接入配置、列表、字典、AI 初始化配置等 JSON GET 接口，不接入上传、下载、大文件、登录、设备登记。
10. 所有变更必须补测试或最少补可验证日志，避免后续无法判断 304 是否真的合并成功。

### 0.5 具体实现方式：底层源码优先直接复制覆盖

本工单后续进入代码实现时，执行方式必须明确为：

```text
SparkClient 底层网络架构源码优先直接复制到 SupportClient；
SupportClient 现有底层网络文件可以被覆盖、替换、拆分、移动；
差异过大的 SupportClient 网络底层实现允许直接推倒重来；
不支持直接复制的部分再手动适配；
禁止迁移 SparkClient 具体业务 API。
```

执行目标不是“写一套相似实现”，而是让 SupportClient 的网络底层架构、代码组织、文件命名、目录结构尽量与 SparkClient 保持一致，方便后期两个客户端持续统一维护。

判断标准：

1. SparkClient 已经有完整底层实现，SupportClient 只是局部手写近似实现时，以 SparkClient 为准。
2. SupportClient 当前实现缺少 SparkClient 的关键抽象，例如 `RetryLayer`、`SerialRequestGate`、`ETagHTTPInterceptor`、完整 `NetworkStrategy` 时，以 SparkClient 为准。
3. SupportClient 当前文件职责混杂，难以拆成 SparkClient 同构目录时，可以直接替换为 SparkClient 结构。
4. SupportClient 已经修复过的真实问题，例如 token refresh 兼容、session invalidation、原始报文脱敏日志，可以作为补丁叠加到 SparkClient 同构架构上。
5. 一旦发生架构冲突，优先保留 SparkClient 的底层设计，SupportClient 只保留必要业务入口和适配层。

#### 0.5.1 允许直接复制覆盖的范围

以下属于底层通用网络能力，允许从 SparkClient 直接复制源码到 SupportClient，并按 Support 命名空间做最小必要替换：

1. `SparkNetworkModels.swift` → `SupportNetworkModels.swift`
2. `SparkNetworkTransport.swift` → `SupportNetworkTransport.swift`
3. `SparkNetworkEngine.swift` → `SupportNetworkEngine.swift`
4. `RetryLayer.swift` → `RetryLayer.swift`
5. `SerialRequestGate.swift` → `SerialRequestGate.swift`
6. `ETagStore.swift` → `ETagStore.swift`
7. `SparkNetworkOperation.swift` → `SupportNetworkOperation.swift`
8. `SparkBackendConfiguration.swift` → `SupportBackendConfiguration.swift`
9. `SparkCallbackCache.swift` → `SupportCallbackCache.swift`
10. `SparkAPIResponseDecoder.swift` 或等价解码工具 → `SupportAPIResponseDecoder.swift`
11. `SparkNetworkingStrings.swift` → `SupportNetworkingStrings.swift`
12. `SparkNetworkOperationBusinessPurpose.swift` → `SupportNetworkOperationBusinessPurpose.swift`
13. `AuthTokenProvider` 相关底层 token provider 逻辑，保留 SupportClient 当前已修正的 refresh 兼容与失效通知增强。

复制后必须做命名替换：

```text
SparkHTTPMethod        -> SupportHTTPMethod
SparkBody              -> SupportBody
SparkNetworkRequest    -> SupportNetworkRequest
SparkNetworkResponse   -> SupportNetworkResponse 或 SupportTransportResponse
SparkTransportResponse -> SupportTransportResponse
SparkNetworkError      -> SupportNetworkError
SparkNetworkEngine     -> SupportNetworkEngine
SparkBackend           -> SupportBackend
SparkBackendConfiguration -> SupportBackendConfiguration
SparkCallbackCache     -> SupportCallbackCache
SparkNetworkingStrings -> SupportNetworkingStrings
AuthSessionInvalidation -> SupportAuthSessionInvalidation
DeviceCache            -> Support 侧缓存/ETag Store 实现
```

#### 0.5.2 不允许直接迁移的范围

以下属于 SparkClient 业务代码，不属于本工单范围，禁止为了目录一致而复制：

1. 医疗、问诊、病历、健康档案、聊天等业务 API。
2. SparkClient 专属 AI 业务接口，除非 SupportClient 已经存在同名业务需求。
3. SparkClient 专属页面、ViewModel、Feature、Coordinator。
4. SparkClient 专属业务模型。
5. SparkClient 专属服务端路径、业务 operation name、业务文案。

业务相关内容只能作为调用样例理解底层网络，不得进入 SupportClient 通用网络底座。

#### 0.5.3 覆盖替换策略

实现时优先采用以下顺序：

1. 先在 SupportClient 创建与 SparkClient 一致的 `Projects/Core/Networking` 目录结构。
2. 将 SparkClient 底层网络文件复制到 SupportClient 对应目录。
3. 对复制文件执行 Support 命名空间替换。
4. 评估 SupportClient 当前 `Core/Networking` 中每个文件是否值得保留。
5. 差异小的文件做命名适配后并入 SparkClient 同构结构。
6. 差异大的文件直接废弃，用 SparkClient 复制文件替换。
7. 保留 SupportClient 已经验证过的登录 refresh、session invalidation、原始报文脱敏日志、OSS/OCR/AIConfig 组合入口。
8. 对不兼容点进行手动适配，而不是反向修改整体架构。
9. 编译通过后再逐步删除旧路径，或保留薄 shim 过渡。

#### 0.5.4 推倒重来触发条件

满足以下任意条件时，SupportClient 当前底层文件可以不再继续修补，直接以 SparkClient 实现覆盖：

1. 单个文件同时承担模型、Transport、Engine、TokenProvider、Error、工具函数等多个职责，难以拆分维护。
2. 当前实现缺少 SparkClient 的关键执行管线：`SerialRequestGate -> Auth -> ETag -> Retry -> Transport -> Decode/Error Mapping`。
3. 当前策略模型无法无损表达 SparkClient 的 `allowETag`、`retryConfig`、`isIdempotent`、`queuePriority`、`etagTTL`。
4. 当前响应模型无法表达 `didMerge304`。
5. 当前缓存实现无法支持 ETag metadata/body 分离持久化。
6. 当前目录结构与 SparkClient 差异过大，继续兼容会导致两个客户端长期分叉。
7. 为了保留 SupportClient 当前实现需要反向削弱 SparkClient 的成熟设计。

#### 0.5.5 手动适配点

直接复制后，下列位置需要手动处理：

1. `Logger` 模块命名与 SupportClient 当前日志模块枚举。
2. `JSONEncoder.default` / `JSONDecoder.default` 与 SupportClient 的 `.supportDefault`。
3. `DeviceCache` 在 SupportClient 侧没有完全同构时，ETag 应使用 `FileETagStore` 或 Support 侧缓存实现替代。
4. Keychain account 名称必须沿用 SupportClient 当前登录 token 存储，不能误用 SparkClient 的 key。
5. `SupportAuthSessionInvalidation` 必须保留 SupportClient 当前已经实现的 401/403/session 失效通知。
6. `SupportBackend` 中已有 `auth`、`otp`、`device`、`files`、`oss`、`ocr`、`aiConfig`、`deactivation`、`accountIdentity` 组合入口必须保留。
7. `SupportNetworkOperationBusinessPurpose` 需要保留 SupportClient 已有业务描述，新增底层能力时只扩展，不删除。
8. ETag cache 目录必须使用 `SupportClient.ETagCache`，不能复制成 `SparkClient.ETagCache`。

#### 0.5.6 最终目录目标

完成后 SupportClient 网络底座目录应尽量接近：

```text
SupportClient/SupportClient/Projects/Core/Networking/
  API/
    Common/
      SupportAPIResponseDecoder.swift
    Account/
    Auth/
  Caching/
    SupportCallbackCache.swift
  Logging/
    SupportNetworkingStrings.swift
    SupportNetworkOperationBusinessPurpose.swift
  Operations/
    SupportNetworkOperation.swift
  AuthTokenProvider.swift
  BackendErrorLocalizer.swift
  ETagStore.swift
  RetryLayer.swift
  SerialRequestGate.swift
  SupportBackend.swift
  SupportBackendConfiguration.swift
  SupportNetworkEngine.swift
  SupportNetworkModels.swift
  SupportNetworkTransport.swift
```

旧目录：

```text
SupportClient/SupportClient/Core/Networking/
```

可以在迁移阶段短暂保留，但最终应只保留兼容 shim 或清理掉，不能长期作为底层网络主目录。

## 1. 背景

SupportClient 当前已经迁入了一部分 SparkClient 网络能力，例如：

1. `SupportNetworkOperation`
2. `SupportCallbackCache`
3. `SupportBackendConfiguration`
4. `SupportNetworkingStrings`
5. `SupportAPIResponseDecoder`
6. requestID 日志
7. 请求/响应原始报文日志
8. token refresh 部分逻辑

但这些能力仍不是 SparkClient 网络底座的完整形态。按 2026-07-17 最新源码状态，当前 SupportClient 还缺少 SparkClient 网络层最核心的通用策略能力：

1. ETag 缓存与 304 合并。
2. `RetryConfig` / `RetryPolicy` / `Retry-After`。
3. `SerialRequestGate` 串行门控与优先级队列。
4. `SupportTransportResponse` 与最终业务响应之间的 `didMerge304` 标记。
5. `NetworkStrategy.allowETag`、`etagTTL`、`isIdempotent`、`queuePriority`。
6. ETag cache key 按 URL + Authorization 指纹隔离。
7. 磁盘 ETag 元数据和响应体分离存储。
8. GET 条件请求强制禁用 URLSession 本地透明缓存。
9. 304 时用本地 body 填充响应，让上层继续按成功响应解码。

用户要求：

```text
充分理解 网络 /Users/hua/Documents/project/Reference/SparkClient/SparkClient/Projects/Core/Networking
抛弃业务 把网络的底层 理解透
网络内 ETag 缓存 需要加入 通用
SupportClient 对齐 SparkClient 网路底层 目录一致 关键文件一致
/Users/hua/Documents/project/Reference/SupportClient
```

本工单只处理网络底层，不迁移业务 API 逻辑。业务 API 只能作为调用样例，不作为本工单的架构主体。

## 2. 工单编号

```text
SUPPORT-NETWORK-CORE-000001
```

## 3. 总目标

把 SupportClient 网络底座对齐 SparkClient：

1. 目录结构对齐。
2. 关键底层文件对齐。
3. 策略模型对齐。
4. ETag 缓存通用化。
5. 请求执行管线对齐。
6. 错误、重试、取消、鉴权刷新语义对齐。
7. 保留 SupportClient 自己的业务 API，但业务 API 应依赖统一网络底座。

目标不是把 SparkClient 的医疗、聊天、AI 等业务 API 整体复制到 SupportClient，而是把这些业务 API 下面的通用网络基础设施抽出来，作为 SupportClient 后续所有业务模块共同依赖的网络内核。

## 4. 非目标

本工单不做：

1. 不迁移 SparkClient `API/Medical` 业务接口。
2. 不迁移 SparkClient `API/AI` 业务接口，除非 SupportClient 已有同名需求。
3. 不迁移 SparkClient `API/File` 的业务模型，文件业务已有 `SUPPORT-OSS-OCR-000001`。
4. 不修改服务端接口。
5. 不改变登录、设备登记、AI 设置等业务流程。
6. 不强行把所有 API 文件一次性改完，允许分阶段接入底座。

## 5. SparkClient 网络底座理解

SparkClient 的 `Projects/Core/Networking` 不是一个简单 HTTPClient，而是一条完整的网络执行管线：

```text
API Method
  -> SparkNetworkOperation
  -> SparkBackendConfiguration.execute
  -> SparkCallbackCache
  -> SparkNetworkEngine.sendRaw
  -> SerialRequestGate
  -> AuthTokenProvider
  -> ETagHTTPInterceptor.applyIfNoneMatch
  -> SparkNetworkTransport
  -> ETagHTTPInterceptor.intercept
  -> RetryPolicy
  -> APIResponseDecoder
```

核心职责分层：

| 层 | 职责 |
| --- | --- |
| API | 声明业务 endpoint，但不直接拼底层网络细节 |
| Operation | 给每个请求命名，提供 apiName、request、callbackCacheKey |
| BackendConfiguration | 统一执行 Operation，负责业务目的日志与 CallbackCache |
| NetworkEngine | 负责鉴权、ETag、重试、串行门控、错误映射 |
| Transport | 负责 URLSession 发送与请求/响应原始报文日志 |
| ETagStore/Interceptor | 负责 If-None-Match、ETag 元数据、304 body 合并 |
| RetryLayer | 负责状态码、URLError、Retry-After、退避间隔 |
| SerialRequestGate | 负责相同 serialKey 的串行执行和优先级 |
| APIResponseDecoder | 负责 `{code,msg,data}` 解包、直接解码、解码日志 |

## 6. SparkClient 关键文件清单

参考目录：

```text
/Users/hua/Documents/project/Reference/SparkClient/SparkClient/Projects/Core/Networking
```

底层关键文件：

```text
AuthTokenProvider.swift
Backend.swift
BackendErrorLocalizer.swift
ETagStore.swift
RetryLayer.swift
SerialRequestGate.swift
SparkBackendConfiguration.swift
SparkNetworkEngine.swift
SparkNetworkModels.swift
SparkNetworkTransport.swift
Caching/DeviceCache.swift
Caching/SparkCallbackCache.swift
Logging/NetworkOperationBusinessPurpose.swift
Logging/SparkNetworkingStrings.swift
Operations/SparkNetworkOperation.swift
API/Common/APIResponseDecoder.swift
```

业务 API 目录作为非本工单范围：

```text
API/AI
API/Account
API/Auth
API/Device
API/File
API/Medical
API/OCR
API/OSS
API/Version
WebSocket
```

说明：

1. `API/Auth`、`API/Device`、`API/OSS` 可以作为 SupportClient 已有 API 对齐样例。
2. `API/Medical`、`API/AI` 不能作为本工单必须迁移项。
3. `WebSocket` 暂不纳入本工单，除非 SupportClient 后续有实时连接需求。

## 7. SupportClient 当前目录现状

参考目录：

```text
/Users/hua/Documents/project/Reference/SupportClient/SupportClient/Core/Networking
/Users/hua/Documents/project/Reference/SupportClient/SupportClient/Projects/Core/Networking
```

当前已有：

```text
Core/Networking/BackendErrorLocalizer.swift
Core/Networking/Caching/SupportCallbackCache.swift
Core/Networking/Logging/SupportAPIResponseDecoder.swift
Core/Networking/Logging/SupportNetworkOperationBusinessPurpose.swift
Core/Networking/Logging/SupportNetworkingStrings.swift
Core/Networking/Operations/SupportNetworkOperation.swift
Core/Networking/SupportAPIs.swift
Core/Networking/SupportAuthSessionInvalidation.swift
Core/Networking/SupportBackend.swift
Core/Networking/SupportBackendConfiguration.swift
Core/Networking/SupportDeviceCacheStub.swift
Core/Networking/SupportNetwork.swift
Projects/Core/Networking/API/Account/AccountIdentityAPI.swift
Projects/Core/Networking/API/Account/DeactivationAPI.swift
Projects/Core/Networking/API/Auth/AuthAPI.swift
Projects/Core/Networking/API/Auth/OTPAPI.swift
```

当前问题：

1. 底层目录仍在 `Core/Networking`，没有完全对齐 SparkClient 的 `Projects/Core/Networking`。
2. `SupportNetwork.swift` 承载了太多职责：模型、transport、error、token provider、engine 都在一个文件里。
3. 没有 `ETagStore.swift`。
4. 没有 `RetryLayer.swift`。
5. 没有 `SerialRequestGate.swift`。
6. `NetworkStrategy` 只有 `requiresAuth`、`allowRetry`、`serialKey`，不支持 `allowETag`、`etagTTL`、`isIdempotent`、`queuePriority`、`RetryConfig`。
7. `SupportTransportResponse` 没有 `didMerge304`。
8. `SupportNetworkEngine.sendRaw` 没有 ETag apply/intercept。
9. `SupportNetworkEngine.sendRaw` 没有可配置重试策略。
10. `SupportCallbackCache` 已存在，但仍缺少 ETag 缓存共同组成完整 GET 缓存层。

## 8. 目标目录结构

目标对齐 SparkClient：

```text
SupportClient/SupportClient/Projects/Core/Networking
├── API
│   └── Common
│       └── SupportAPIResponseDecoder.swift
├── AuthTokenProvider.swift
├── Backend.swift
├── BackendErrorLocalizer.swift
├── Caching
│   ├── DeviceCache.swift
│   └── SupportCallbackCache.swift
├── ETagStore.swift
├── Logging
│   ├── SupportNetworkOperationBusinessPurpose.swift
│   └── SupportNetworkingStrings.swift
├── Operations
│   └── SupportNetworkOperation.swift
├── RetryLayer.swift
├── SerialRequestGate.swift
├── SupportBackendConfiguration.swift
├── SupportNetworkEngine.swift
├── SupportNetworkModels.swift
└── SupportNetworkTransport.swift
```

迁移策略：

1. 第一阶段可以保留 `Core/Networking` shim，避免一次性改坏所有引用。
2. 第二阶段把底层文件移动到 `Projects/Core/Networking`。
3. 第三阶段清理旧 `Core/Networking`，或只保留向后兼容转发文件。
4. 业务 API 后续也应逐步放到 `Projects/Core/Networking/API/...`，但本工单只要求底层目录先对齐。

## 9. 关键文件对齐要求

### 9.1 SupportNetworkModels.swift

应从当前 `SupportNetwork.swift` 拆出：

1. `SupportHTTPMethod`
2. `AnyEncodable`
3. `SupportBody`
4. `RetryConfig`
5. `RequestQueuePriority`
6. `NetworkStrategy`
7. `SupportNetworkRequest`
8. `SupportNetworkResponse`
9. `ETagCacheRecord`
10. `JSONValue`
11. `BackendError`
12. `SupportNetworkError`
13. `SupportAuthSessionInvalidation`

目标对齐 SparkClient：

```swift
struct NetworkStrategy: Sendable {
    var requiresAuth: Bool
    var allowETag: Bool
    var serialKey: String?
    var retryConfig: RetryConfig
    var isIdempotent: Bool
    var queuePriority: RequestQueuePriority
    var etagTTL: TimeInterval?
}
```

当前 SupportClient：

```swift
struct NetworkStrategy: Sendable {
    var requiresAuth: Bool = false
    var allowRetry: Bool = true
    var serialKey: String?
}
```

必须升级。

### 9.2 SupportNetworkResponse.swift / SupportTransportResponse

SparkClient 有两层响应：

```swift
SparkTransportResponse
SparkNetworkResponse
```

其中：

```swift
struct SparkNetworkResponse: Sendable {
    let data: Data
    let httpResponse: HTTPURLResponse
    let didMerge304: Bool
}
```

SupportClient 当前只有：

```swift
struct SupportTransportResponse: Sendable {
    let data: Data
    let httpResponse: HTTPURLResponse
}
```

目标：

1. 保留 `SupportTransportResponse` 作为 transport 原始响应。
2. 新增 `SupportNetworkResponse`，包含 `didMerge304`。
3. `SupportNetworkEngine.sendRaw` 返回 `SupportNetworkResponse`。
4. `SupportBackendConfiguration.execute` 返回 `SupportNetworkResponse`。
5. `SupportAPIResponseDecoder` 接收 `SupportNetworkResponse`。

### 9.3 SupportNetworkTransport.swift

应从 `SupportNetwork.swift` 拆出：

1. `SupportNetworkTransport`
2. `URLSessionNetworkTransport`
3. 请求日志
4. 响应日志
5. requestID
6. raw body/header 脱敏

要求：

1. Transport 不处理业务解码。
2. Transport 不处理 ETag。
3. Transport 不处理 retry。
4. Transport 只做真实发送和基础日志。

### 9.4 SupportNetworkEngine.swift

目标对齐 SparkClient 执行顺序：

```text
sendRaw
  -> serialKey
  -> RetryPolicy
  -> SerialRequestGate.enqueue
  -> performAttempt
      -> build URLRequest
      -> cachePolicy reloadIgnoringLocalCacheData when allowETag
      -> X-Request-ID
      -> Content-Type
      -> Authorization
      -> ETagHTTPInterceptor.applyIfNoneMatch
      -> transport.send
      -> ETagHTTPInterceptor.intercept
  -> 401 refresh
  -> success判定 2xx or 304 merged
  -> retry判定
  -> auth invalidation
  -> error mapping
```

SupportClient 当前 `sendRaw` 只有：

1. make request。
2. transport send。
3. 401 refresh。
4. 非 2xx throw。

必须补齐：

1. `SerialRequestGate`。
2. `RetryPolicy`。
3. `ETagHTTPInterceptor`。
4. `isSuccess` 识别 304 merged。
5. `shouldRetry` 幂等判断。
6. CancellationError 映射。

### 9.5 ETagStore.swift

必须新增通用 ETag 缓存。

目标结构对齐 SparkClient：

```swift
protocol ETagStore: Sendable {
    func record(forKey key: String) -> ETagCacheRecord?
    func cachedBody(forKey key: String) -> Data?
    func store(record: ETagCacheRecord, body: Data, forKey key: String) throws
    func removeCache(forKey key: String)
}
```

默认实现：

```swift
struct FileETagStore: ETagStore
```

SupportClient 缓存目录建议：

```text
Caches/SupportClient.ETagCache
```

必须保存：

```text
{cacheKey}.meta.json
{cacheKey}.body
```

### 9.6 ETagHTTPInterceptor

必须新增：

```swift
struct ETagHTTPInterceptor: Sendable
```

职责：

1. 基于 URL + Authorization 指纹生成 cacheKey。
2. 未过期时附加 `If-None-Match`。
3. 请求有 `etagTTL` 时附加 `X-Cache-Max-Age`。
4. 本地缓存过期时删除缓存并跳过 If-None-Match。
5. 收到 304 时读取 cached body。
6. 304 + cached body 时返回 `didMerge304=true`。
7. 收到 2xx + ETag 时写入 `.meta.json` 和 `.body`。
8. 根据 `Cache-Control`、`Expires`、`etagTTL` 计算过期时间。

必须注意：

1. ETag cache key 必须包含 Authorization 指纹，避免账号 A 的缓存给账号 B 使用。
2. 请求启用 ETag 时必须设置：

```swift
urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
```

否则 URLSession 可能透明合并 304，让自定义 ETag 层看不到真实 304。

### 9.7 RetryLayer.swift

必须新增：

1. `RetryAfterParser`
2. `RetryScheduler`
3. `DefaultRetryScheduler`
4. `RetryPolicy`

对齐 SparkClient：

1. 支持 `Retry-After` delta seconds。
2. 支持 HTTP-date。
3. 支持 retryable status codes：429、500、502、503、504。
4. 支持 retryable URLError：timeout、DNS、notConnected、networkConnectionLost 等。
5. 支持 backoff intervals。
6. 支持 GET 默认可重试，非 GET 必须 `isIdempotent=true` 才可自动重试。

### 9.8 SerialRequestGate.swift

必须新增：

```swift
actor SerialRequestGate
```

能力：

1. 按 `serialKey` 串行。
2. 同一 `serialKey` 内支持优先级。
3. retry 优先级最高。
4. 保持同优先级 FIFO。
5. 支持取消。

### 9.9 SupportBackendConfiguration.swift

当前已有，但需要升级：

1. `execute` 返回 `SupportNetworkResponse`。
2. 日志中打印 `allowETag`。
3. 日志中打印 `retryEnabled` 和 `maxRetry`。
4. 日志中打印 `queuePriority`。
5. 支持 CallbackCache 返回同一个 `Task<SupportNetworkResponse, Error>`。

目标日志：

```text
业务=xxx Operation 请求详情 method=GET path=/... query= requiresAuth=true allowETag=true retryEnabled=true maxRetry=2 serialKey=... queuePriority=normal
```

### 9.10 SupportAPIResponseDecoder.swift

必须升级为接收 `SupportNetworkResponse`。

要求：

1. 304 merged 后仍能正常解码。
2. backend wrapped 解码时 `code != 0` 转业务错误。
3. 支持 direct 模式。
4. 解码成功日志保留。
5. 解码失败日志保留 JSON key summary。

## 10. ETag 通用接入要求

### 10.1 请求侧启用方式

业务 API 只需要在 request strategy 打开：

```swift
strategy: NetworkStrategy(
    requiresAuth: true,
    allowETag: true,
    serialKey: "resource.members",
    retryConfig: .default,
    isIdempotent: true,
    queuePriority: .normal,
    etagTTL: 120
)
```

### 10.2 缓存流程

第一次请求：

```text
GET /api/v1/xxx
-> 200
-> response header ETag: "abc"
-> store abc + response body
```

第二次请求：

```text
GET /api/v1/xxx
-> If-None-Match: "abc"
-> 304
-> read cached body
-> return SupportNetworkResponse(data: cached, didMerge304: true)
-> 上层正常 decode
```

### 10.3 账号隔离

ETag cache key 必须包含：

1. URL absoluteString。
2. Authorization header 指纹。

不允许只按 path/query 缓存。

原因：

1. SupportClient 是账号级应用。
2. 同一个 URL 在不同账号下可能返回不同数据。
3. 304 合并本地 body 时如果不隔离账号，会造成数据串号。

### 10.4 清理策略

需要支持：

1. 清理单个 cacheKey。
2. 按账号切换时可选择保留或清理。
3. 登出时建议清理认证相关 ETag cache。
4. 系统 cache 目录被清理后不影响功能，只会重新拉取。

本工单第一阶段要求：

1. ETag 默认落在 `Caches/SupportClient.ETagCache`。
2. 无本地 body 的 304 按 HTTP 错误处理，不伪造成功。
3. 账号切换是否清理可以后续加，但 cache key 必须已包含 Authorization。

## 11. 与业务 API 的边界

本工单明确“抛弃业务”，所以：

1. 不要求迁移 SparkClient 医疗 API。
2. 不要求迁移 SparkClient AI API。
3. 不要求迁移 SparkClient Chat API。
4. 不要求迁移 SparkClient WebSocket。

但 SupportClient 现有业务 API 必须逐步使用新底座：

1. Auth API
2. OTP API
3. Device API
4. OSS API
5. OCR API
6. File API
7. Account API
8. AI Config API

业务 API 只负责声明：

1. operation name。
2. apiName。
3. path/query/body。
4. strategy。
5. 解码目标。

不允许业务 API 自己实现：

1. 重试。
2. ETag。
3. token refresh。
4. requestID。
5. raw HTTP 日志。
6. CallbackCache。

## 12. 分阶段实施计划

### 阶段 0：最新能力审计与行为冻结

任务：

1. 以 `/Users/hua/Documents/project/Reference/SupportClient` 为准重新扫描当前网络文件。
2. 明确 `SupportNetwork.swift` 中已有模型、Transport、Engine、TokenProvider、错误类型和取消分类。
3. 明确 `Core/Networking/Caching`、`Logging`、`Operations` 中已有文件。
4. 明确 `Projects/Core/Networking/API` 中已经存在的业务 API 文件，不把它们误判为缺失。
5. 对每个现有底层文件给出处理结论：保留适配、复制覆盖、拆分迁移、废弃。
6. 对差异过大的文件直接标记为“以 SparkClient 覆盖替换”，不要继续局部修补。
7. 补一份最小行为快照：登录、token refresh、OSS STS、OCR、AIConfig、设备登记、CallbackCache 日志链路当前必须保持一致。

验收：

1. 现有登录、设备登记、OSS STS、AIConfig、OCR 调用不因网络底座调整而回退。
2. 原始请求/响应日志仍能打印。
3. `SupportAuthSessionInvalidation` 仍能在明确鉴权失效时触发。
4. `SupportCallbackCache` 仍能对相同 GET 合并并发请求。
5. 已形成“哪些文件直接复制覆盖、哪些文件手动适配、哪些业务 API 不迁移”的明确清单。

### 阶段 1：文件拆分与目录对齐

任务：

1. 创建 `SupportClient/SupportClient/Projects/Core/Networking`。
2. 优先从 SparkClient `Projects/Core/Networking` 直接复制底层源码到 SupportClient 对应目录。
3. 复制后按 Support 命名空间替换 `Spark*` 类型与文件名。
4. 从 `Core/Networking/SupportNetwork.swift` 拆出或替换为：
   - `SupportNetworkModels.swift`
   - `SupportNetworkTransport.swift`
   - `SupportNetworkEngine.swift`
   - `AuthTokenProvider.swift`
5. 移动或复制当前已经存在的底层文件：
   - `SupportBackendConfiguration.swift`
   - `BackendErrorLocalizer.swift`
   - `SupportAuthSessionInvalidation.swift`
   - `Caching/SupportCallbackCache.swift`
   - `Logging/*`
   - `Operations/*`
6. `SupportAPIs.swift` 当前承载 `SupportDeviceAPI`、`SupportFileAPI`、`SupportOSSAPI`、`SupportOCRAPI`、`SupportAIConfigAPI` 等业务 API，可暂时保留；后续再按 API 域逐步拆到 `Projects/Core/Networking/API`。
7. 保留旧路径兼容或更新所有引用。

验收：

1. 目录与 SparkClient 同级形态一致。
2. 编译通过。
3. 行为不变，现有网络日志、401 refresh、CallbackCache 不回退。
4. 底层核心文件不是重新手写的相似实现，而是以 SparkClient 源码复制替换为主，并完成 Support 命名适配。
5. 对差异过大的 SupportClient 旧实现不保留双轨逻辑，必须删除、废弃或改成薄 shim。

### 阶段 2：升级策略模型

任务：

1. 把当前 `NetworkStrategy` 从：

```swift
struct NetworkStrategy: Sendable {
    var requiresAuth: Bool = false
    var allowRetry: Bool = true
    var serialKey: String?
}
```

升级为接近 SparkClient 的形态：

```swift
struct NetworkStrategy: Sendable {
    var requiresAuth: Bool
    var allowETag: Bool
    var serialKey: String?
    var retryConfig: RetryConfig
    var isIdempotent: Bool
    var queuePriority: RequestQueuePriority
    var etagTTL: TimeInterval?
}
```

2. 为兼容当前 SupportClient 已有调用点，短期可保留 `allowRetry` 适配初始化器，但内部应转换成 `RetryConfig.isEnabled`。
3. GET 默认允许重试；非 GET 默认不自动重试。
4. `allowETag` 默认必须为 `false`。
5. `etagTTL` 默认为 `nil` 或使用拦截器默认 TTL，不能改变现有请求行为。

验收：

1. 旧 API 调用点无需大面积改动即可编译。
2. 所有原有 `requiresAuth`、`allowRetry`、`serialKey` 语义可映射到新策略。
3. 未显式启用 ETag 的请求行为与当前版本一致。

### 阶段 3：引入 RetryLayer 与 SerialRequestGate

任务：

1. 从 SparkClient 直接复制 `RetryLayer.swift`。
2. 从 SparkClient 直接复制 `SerialRequestGate.swift`。
3. `SupportNetworkEngine` 初始化时持有 `SerialRequestGate` 与 `RetryPolicy`。
4. `SupportNetworkEngine.sendRaw` 外层接入 `gate.enqueue(serialKey:priority:)`。
5. `SupportNetworkEngine.sendRaw` 接入 HTTP status 与 `URLError` 重试。
6. 401 refresh 逻辑继续保留在 sendRaw 中，并和 retry 计数协调，避免无限循环。

验收：

1. GET 可按默认策略重试。
2. 非 GET 默认不自动重试。
3. 幂等非 GET 可通过 `isIdempotent=true` 重试。
4. 相同 `serialKey` 串行执行。

### 阶段 4：引入 ETagStore 与 ETagHTTPInterceptor

任务：

1. 从 SparkClient 直接复制 `ETagStore.swift`。
2. 保留 `ETagCacheRecord`、`ETagStore`、`FileETagStore`、`ETagHTTPInterceptor` 的整体结构。
3. 将缓存目录从 `SparkClient.ETagCache` 修改为 `SupportClient.ETagCache`。
4. `SupportNetworkEngine.performAttempt` 接入 `applyIfNoneMatch`。
5. `SupportNetworkEngine.performAttempt` 接入 `intercept`。
6. 新增 `SupportNetworkResponse.didMerge304`。
7. 如果继续沿用 `SupportTransportResponse` 命名，应补 `didMerge304: Bool` 字段；如果新增 `SupportNetworkResponse`，则需要同步 `SupportAPIResponseDecoder` 入参。
8. ETag 目录建议使用 SupportClient 自己的 cache 子目录，例如 `Caches/SupportClient.ETagCache`，不要沿用 `SparkClient.ETagCache` 字符串。

验收：

1. 2xx + ETag 可以落盘。
2. 第二次 GET 能带 `If-None-Match`。
3. 服务端 304 时能用本地 body 合并成功。
4. 上层 API 不需要知道 304，仍正常拿到 decoded data。
5. 本地没有 body 时不错误合并。
6. ETag 请求的 `URLRequest.cachePolicy` 已强制为 `.reloadIgnoringLocalCacheData`。

### 阶段 5：业务 API 策略试点接入

先接入安全的 GET API：

1. `SupportAIConfigAPI` 中 AI 初始化配置、模型/场景配置类 GET 可优先试点。
2. `SupportFileAPI` 的文件列表类 GET 可按响应体大小谨慎试点。
3. `SupportAccountIdentityAPI` / `SupportDeactivationAPI` 的查询类 GET 可按需试点。
4. `current session`、登录态检查类接口默认不启用 ETag，除非明确验证不会影响账号切换和 session 失效判断。

原则：

1. 先 GET。
2. 先幂等。
3. 先列表/配置类。
4. 不对登录、token refresh、设备登记启用 ETag。
5. 不对上传、下载、大文件二进制流启用 ETag。

### 阶段 6：测试与验收

必须新增测试：

1. ETag store 写入/读取。
2. cache key 包含 Authorization。
3. 304 + cached body 合并。
4. 304 + missing body 不合并。
5. Cache-Control max-age 过期。
6. Retry-After 解析。
7. GET 重试。
8. 非幂等 POST 不重试。
9. SerialRequestGate 同 key 串行。
10. CallbackCache 相同 GET 只发一次。
11. 401 refresh 失败时 session invalidation 行为不回退。
12. 原始报文日志仍对密钥字段脱敏。

## 13. 验收标准

本工单完成必须满足：

1. SupportClient 网络底层目录对齐 `Projects/Core/Networking`。
2. 关键底层文件以 SparkClient 实现为准，差异过大的 SupportClient 旧实现已推倒重来。
3. 不保留两套长期并行的网络底座。
4. `SupportNetwork.swift` 不再长期承载模型、Transport、Engine、TokenProvider、Error 的巨型混合职责。
5. `NetworkStrategy` 支持 `allowETag`、`etagTTL`、`retryConfig`、`isIdempotent`、`queuePriority`。
6. `SupportTransportResponse` 或 `SupportNetworkResponse` 支持 `didMerge304`。
7. `ETagStore.swift` 已加入通用网络底座。
8. `FileETagStore` 可以写入 `.meta.json` 和 `.body`。
9. `ETagHTTPInterceptor` 可以附加 `If-None-Match`。
10. 304 可以合并本地 body 并正常解码。
11. ETag cache key 包含 Authorization 指纹。
12. `RetryLayer.swift` 已加入。
13. `SerialRequestGate.swift` 已加入。
14. `SupportBackendConfiguration` 最新日志能力被保留。
15. `SupportAPIResponseDecoder` 支持 merged 304，同时保留当前 keys summary 日志。
16. `AuthTokenProvider`、401 refresh、`SupportAuthSessionInvalidation` 行为不回退。
17. `SupportBackend` 中已有 `auth`、`otp`、`device`、`files`、`oss`、`ocr`、`aiConfig`、`deactivation`、`accountIdentity` 组合不被破坏。
18. `xcodebuild` 通过。

## 14. 风险与策略

### 14.1 目录迁移风险

风险：

移动文件可能导致 target membership 或引用失效。

策略：

1. 第一阶段复制新目录。
2. 编译通过后删除旧路径。
3. 每次移动后运行 build。

### 14.2 ETag 串号风险

风险：

如果 cache key 不包含 Authorization，账号之间可能共享缓存 body。

策略：

1. cache key 必须包含 Authorization。
2. Authorization 只参与 hash，不落明文。
3. 登出可额外清理 ETag cache。

### 14.3 URLSession 透明缓存风险

风险：

URLSession 可能把 304 透明变成 200，让自定义 ETag 层失效。

策略：

启用 ETag 时强制：

```swift
urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
```

### 14.4 非幂等请求重试风险

风险：

POST/PATCH/DELETE 自动重试可能造成重复写入。

策略：

1. GET 默认可重试。
2. 非 GET 必须显式 `isIdempotent=true`。
3. 设备登记如要重试，需要明确后端幂等依据。

### 14.5 大响应体缓存风险

风险：

ETag body 缓存大响应可能占用磁盘。

策略：

1. 初期不对大文件下载启用 ETag。
2. 只对 JSON 配置/列表类接口启用。
3. 后续增加 size limit 和 LRU。

## 15. 实施检查清单

### 目录

- [x] 当前已有 `SupportClient/SupportClient/Core/Networking`
- [x] 当前已有 `Core/Networking/Caching`
- [x] 当前已有 `Core/Networking/Logging`
- [x] 当前已有 `Core/Networking/Operations`
- [x] 当前已有 `SupportClient/SupportClient/Projects/Core/Networking/API/Account`
- [x] 当前已有 `SupportClient/SupportClient/Projects/Core/Networking/API/Auth`
- [ ] 创建或补齐 `SupportClient/SupportClient/Projects/Core/Networking`
- [ ] 创建 `Projects/Core/Networking/API/Common`
- [ ] 将底层通用文件逐步从 `Core/Networking` 迁移到 `Projects/Core/Networking`
- [x] 旧目录 shim 或引用已清理（巨型 `SupportNetwork.swift` 已删除，业务 API 仍可留在 `Core/Networking/SupportAPIs.swift`），并确认 target membership 正确

### 关键文件

- [x] `SupportBackendConfiguration.swift`
- [x] `BackendErrorLocalizer.swift`
- [x] `Backend.swift` / `SupportBackend.swift`
- [x] `Caching/SupportCallbackCache.swift`
- [x] `Logging/SupportNetworkingStrings.swift`
- [x] `Logging/SupportNetworkOperationBusinessPurpose.swift`
- [x] `Logging/SupportAPIResponseDecoder.swift`
- [x] `Operations/SupportNetworkOperation.swift`
- [x] `SupportNetwork.swift` 当前包含 `SupportNetworkModels`、`SupportNetworkTransport`、`SupportNetworkEngine`、`AuthTokenProvider` 等职责
- [ ] 拆出 `SupportNetworkModels.swift`
- [ ] 拆出 `SupportNetworkEngine.swift`
- [ ] 拆出 `SupportNetworkTransport.swift`
- [ ] 拆出 `AuthTokenProvider.swift`
- [x] `ETagStore.swift`
- [x] `RetryLayer.swift`
- [x] `SerialRequestGate.swift`
- [x] `API/Common/SupportAPIResponseDecoder.swift` 或保持当前 Logging 目录但文档注明原因

### ETag

- [x] `ETagCacheRecord` 已加入
- [x] `ETagStore` protocol 已加入
- [x] `FileETagStore` 已加入
- [x] `ETagHTTPInterceptor` 已加入
- [x] cache key 使用 URL + Authorization 指纹
- [x] `If-None-Match` 可附加
- [x] `X-Cache-Max-Age` 可附加
- [x] 2xx + ETag 可写缓存
- [x] 304 + body 可合并
- [x] 304 + missing body 不合并

### Retry / Gate

- [x] `RetryConfig` 已加入
- [x] `RetryPolicy` 已加入
- [x] `RetryAfterParser` 已加入
- [x] `RequestQueuePriority` 已加入
- [x] `SerialRequestGate` 已加入
- [x] GET 默认可重试
- [x] 非 GET 默认不重试（需 `isIdempotent=true`）
- [x] 非 GET 幂等标记后可重试

### 现有能力保护

- [x] `SupportNetworkOperation` 已存在
- [x] `SupportCallbackCache` 已存在
- [x] `SupportBackendConfiguration.executeDecoded` 已存在
- [x] requestID 日志已存在
- [x] 请求/响应原始报文日志已存在
- [x] `SupportAPIResponseDecoder` keys summary 日志已存在
- [x] `AuthTokenProvider` refresh 并发去重已存在
- [x] 401 refresh 后重试链路已存在
- [x] `SupportAuthSessionInvalidation` 已存在
- [ ] 接入 ETag/Retry/Gate 后，上述能力全部保持

### 验收

- [x] 编译通过（`xcodebuild` BUILD SUCCEEDED）
- [x] 单元测试覆盖 ETag 304 合并（`SupportNetworkCoreETagRetryGateTests`）
- [x] 单元测试覆盖账号隔离（Authorization 指纹）
- [x] 单元测试覆盖 retry
- [x] 单元测试覆盖 serial gate
- [ ] 实机/模拟器日志能看到 If-None-Match 与 304 合并

## 16. 完成后更新文档

完成实现后，需要更新：

```text
/Users/hua/Documents/project/Reference/SupportClient/需求文档/SUPPORT-ARCH-000001-SparkClient底层核心架构迁移需求工单.md
```

建议新增：

```text
SUPPORT-NETWORK-CORE-000001 已完成：
- SupportClient 网络底层目录已对齐 SparkClient 的 Projects/Core/Networking
- NetworkStrategy / RetryLayer / SerialRequestGate / CallbackCache 已对齐
- ETagStore 与 ETagHTTPInterceptor 已加入通用网络底座
- 304 可合并本地 body 并正常解码
- ETag cache key 已按 URL + Authorization 指纹隔离账号
```

## 17. 文档落点与当前源码基准

用户指定目标项目：

```text
/Users/hua/Documents/project/Reference/SupportClient
```

本轮已直接更新目标项目内文档：

```text
/Users/hua/Documents/project/Reference/SupportClient/需求文档/SUPPORT-NETWORK-CORE-000001-网络底座与ETag缓存对齐SparkClient需求工单.md
```

当前检测到：

```text
/Users/hua/Downloads/Reference
```

为普通文件，不是可用项目目录。因此本工单后续实现、验收、同步均以 `/Users/hua/Documents/project/Reference/SupportClient` 为准，不再引用 Downloads 镜像目录。

## 18. 本轮优化结论（2026-07-17）

本轮文档优化后的核心结论：

1. SupportClient 网络底座已经不是空白状态，Operation、CallbackCache、BackendConfiguration、原始报文日志、Decoder、TokenProvider、401 refresh、Session invalidation 都已经存在。
2. SparkClient 仍领先的关键能力集中在 ETag、Retry、SerialRequestGate、完整 NetworkStrategy、`didMerge304` 响应标记和目录拆分。
3. 后续实现应优先补齐这些通用底层能力，不要重复搬运已经存在的 SupportClient 网络代码。
4. ETag 必须通用但默认关闭，按安全 GET 接口逐步启用。
5. 网络底座对齐完成后，AI 设置初始化、文件列表、配置类接口可以复用 ETag 缓存，登录、token refresh、设备登记、上传下载不应作为首批接入对象。
