# SUPPORT-OSS-STS-000001 OSS STS bucket_name 字段兼容快速修复工单

## 1. 问题结论

SupportClient 当前 OSS STS 接口请求成功，HTTP 状态码为 200，响应体也包含完整的 OSS 临时凭证与桶信息，但客户端仍打印：

```text
OSS STS 预拉取：字段不完整，未缓存 ownerAccountID=810 phase=bootstrapIfNeeded
```

根因不是单独缺 `bucket_name` 兼容分支，而是 **SupportClient 全局 `JSONDecoder` 未开启 `convertFromSnakeCase`**，与 SparkClient 不一致。

SparkClient：

```swift
decoder.keyDecodingStrategy = .convertFromSnakeCase
```

因此服务端 `bucket_name` 会先被转换成 `bucketName`，再被：

```swift
self.bucketName = try? container.decode(String.self, forKey: .key("bucketName"))
```

读到。

SupportClient 修复目标：全局 decoder/encoder 与 SparkClient 对齐，而不是只在 STS DTO 里补 `bucket_name`。

服务端当前返回：

```json
{
  "code": 0,
  "data": {
    "access_key_id": "STS.xxx",
    "access_key_secret": "***",
    "bucket_name": "zhaodkdream",
    "endpoint": "https://oss-cn-beijing.aliyuncs.com",
    "expiration": 1783616825,
    "region": "cn-shanghai",
    "security_token": "***"
  },
  "msg": "success"
}
```

SupportClient 旧 `JSONDecoder.supportDefault` 只有 `.iso8601`，没有 `convertFromSnakeCase`，因此 `bucket_name` 不会变成 `bucketName`，`response.bucket == ""`，`AliyunOSSRuntimeConfig(response:)` 返回 nil。

## 2. 工单编号

```text
SUPPORT-OSS-STS-000001
```

## 3. 影响范围

### 3.1 直接影响

1. 登录后 OSS STS 预拉取失败。
2. `SupportOSSConfigurationStore.snapshot` 无法缓存。
3. 上传前 `configurationForUpload(using:)` 会再次请求 STS，但仍会因为 bucket 为空失败。
4. `OSSManager.updateConfiguration(endpoint:bucket:region:)` 不会执行。
5. 文件上传无法进入真实 OSS 上传流程。
6. public HTTPS URL 和 presigned URL 无法使用。

### 3.2 潜在影响

SupportClient 当前 `OCRSTSCredentialsResponse` 也没有兼容 `bucket_name`：

```swift
self.bucketName =
    (try? container.decode(String.self, forKey: .key("bucketName"))) ??
    (try? container.decode(String.self, forKey: .key("bucket")))
```

如果 OCR STS 接口返回同样的 snake_case 字段，OCR 远程引擎也会出现同类“字段不完整”问题。

## 4. SparkClient 对比

SparkClient 的 `AliyunOSSRuntimeConfig` 以 `OCRSTSCredentialsResponse.bucketName` 作为 bucket 来源：

```swift
let bucket = response.bucketName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
guard !bucket.isEmpty, !region.isEmpty, !endpoint.isEmpty else { return nil }
```

SparkClient 能正常工作的前提是：

1. 服务端 DTO 已经把服务端 bucket 字段规范成 `bucketName`。
2. 或接口实际返回 camelCase。
3. 或 SparkClient 所用 decoder/DTO 已在其他层做过兼容。

SupportClient 当前日志显示服务端实际返回的是 `bucket_name`。正确对齐方式是：

1. 全局 `JSONDecoder.supportDefault` / `JSONDecoder.default` 开启 `convertFromSnakeCase`。
2. 全局 `JSONEncoder.supportDefault` / `JSONEncoder.default` 开启 `convertToSnakeCase`。
3. 所有显式 `CodingKeys` 的 raw value 改为转换后的 camelCase（例如 `account_id` → `accountId`），否则会与策略冲突。
4. STS DTO 继续按 camelCase key 读取（`bucketName` / `bucket`），与 SparkClient 一致。

## 5. 目标

1. 修复 OSS STS 200 成功但被判定字段不完整的问题。
2. 全局 JSONDecoder/Encoder 与 SparkClient 对齐（snake_case 策略）。
3. `OSSCredentialsResponse` / `OCRSTSCredentialsResponse` 在全局策略下可读到 `bucket_name`。
4. `AliyunOSSRuntimeConfig` 可正确拿到 bucket、region、endpoint。
5. 登录后 OSS STS 预拉取成功并缓存。
6. 上传前配置刷新也能成功。
7. 日志能打印：

```text
OSS 配置已加载 bucket=zhaodkdream region=cn-shanghai
```

8. 不泄露 `access_key_secret` 和 `security_token`。

## 6. 修改文件

目标文件：

```text
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Foundation/Utilities.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Core/Networking/SupportAPIs.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Core/Networking/SupportNetwork.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Core/OSS/AliyunOSSRuntimeConfig.swift
/Users/hua/Downloads/Reference/SupportClient/SupportClient/Projects/Core/OSS/SupportOSSConfigurationStore.swift
```

测试或验证文件可按项目实际测试目录新增。

## 7. 快速修复方案

### 7.1 对齐全局 JSONDecoder / JSONEncoder

```swift
extension JSONDecoder {
    nonisolated static var supportDefault: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    nonisolated static var supportDefault: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
```

### 7.2 修正显式 CodingKeys

开启 `convertFromSnakeCase` 后，JSON key 会先变成 camelCase 再匹配 CodingKeys。

错误：

```swift
case accountID = "account_id"
```

正确：

```swift
case accountID = "accountId"
```

### 7.3 STS DTO 与 SparkClient 对齐

依赖全局策略后，DTO 只读 camelCase：

```swift
self.bucketName =
    (try? container.decode(String.self, forKey: .key("bucketName"))) ??
    (try? container.decode(String.self, forKey: .key("bucket")))

self.bucket =
    (try? container.decode(String.self, forKey: .key("bucketName"))) ??
    (try? container.decode(String.self, forKey: .key("bucket"))) ?? ""
```

### 7.4 增强字段不完整日志

当前日志：

```text
OSS STS 预拉取：字段不完整，未缓存 ownerAccountID=810 phase=bootstrapIfNeeded
```

建议改为：

```text
OSS STS 预拉取：字段不完整，未缓存 ownerAccountID=810 phase=bootstrapIfNeeded missing=[bucket] hasAccessKey=true hasEndpoint=true hasRegion=true
```

要求：

1. 不打印 accessKeySecret。
2. 不打印 securityToken。
3. 可以打印 boolean 判断，方便定位缺哪个字段。

## 8. 验证样例

### 8.1 必须通过的 JSON 样例

snake_case：

```json
{
  "access_key_id": "STS.xxx",
  "access_key_secret": "secret",
  "security_token": "token",
  "expiration": 1783616825,
  "bucket_name": "zhaodkdream",
  "region": "cn-shanghai",
  "endpoint": "https://oss-cn-beijing.aliyuncs.com"
}
```

camelCase：

```json
{
  "accessKeyId": "STS.xxx",
  "accessKeySecret": "secret",
  "securityToken": "token",
  "expiration": "1783616825",
  "bucketName": "zhaodkdream",
  "region": "cn-shanghai",
  "endpoint": "https://oss-cn-beijing.aliyuncs.com"
}
```

legacy bucket：

```json
{
  "accessKeyId": "STS.xxx",
  "accessKeySecret": "secret",
  "securityToken": "token",
  "expiration": "1783616825",
  "bucket": "zhaodkdream",
  "region": "cn-shanghai",
  "endpoint": "https://oss-cn-beijing.aliyuncs.com"
}
```

### 8.2 预期结果

三种样例都应满足：

```swift
AliyunOSSRuntimeConfig(response: response) != nil
config.bucketName == "zhaodkdream"
config.region == "cn-shanghai"
config.endpointURL == "https://oss-cn-beijing.aliyuncs.com"
```

## 9. 验收标准

1. 全局 `JSONDecoder.supportDefault` 开启 `convertFromSnakeCase`。
2. 全局 `JSONEncoder.supportDefault` 开启 `convertToSnakeCase`。
3. `OSSCredentialsResponse` / `OCRSTSCredentialsResponse` 能通过全局策略解码 `bucket_name`。
4. OSS STS 预拉取不再出现“字段不完整，未缓存”。
5. 登录后日志出现：

```text
OSS 配置已加载 bucket=zhaodkdream region=cn-shanghai
```

6. `SupportOSSConfigurationStore.snapshot` 不为空。
7. `configurationForUpload(using:)` 可返回有效 `AliyunOSSRuntimeConfig`。
8. 上传前 `OSSManager.updateConfiguration` 能拿到非空 bucket。
9. `xcodebuild` 通过。
10. 日志中 `access_key_secret` 与 `security_token` 仍保持脱敏。

## 10. 实施检查清单

- [x] `JSONDecoder.supportDefault` 增加 `convertFromSnakeCase`
- [x] `JSONEncoder.supportDefault` 增加 `convertToSnakeCase`
- [x] 显式 `CodingKeys` raw value 改为 camelCase（与策略兼容）
- [x] STS DTO 按 camelCase key 读取（与 SparkClient 一致）
- [x] 如有单元测试目录，增加 snake_case / camelCase / bucket 三种样例测试
- [x] 增强字段不完整日志，打印 missing 字段列表和 boolean 状态
- [ ] 运行 App，确认 OSS STS 预拉取成功
- [ ] 运行一次文件上传，确认 upload 前配置有效
- [x] 确认日志无密钥泄露
- [x] `xcodebuild` 通过

## 11. 与现有工单关系

本工单是 `SUPPORT-OSS-OCR-000001` 的快速修复子工单。

父工单：

```text
/Users/hua/Downloads/Reference/SupportClient/需求文档/SUPPORT-OSS-OCR-000001-OSS文件上传与OCR底座迁移对齐SparkClient需求工单.md
```

本工单优先级高于 OSS/OCR 后续增强，因为当前问题会直接阻断 OSS STS 配置缓存和文件上传。
