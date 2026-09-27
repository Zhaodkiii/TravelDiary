# SUPPORT-NETWORK-CORE-000001 变更摘要

## 策略

以 SparkClient `Projects/Core/Networking` 为准：**能拷就拷覆盖**，再做 Support 命名与装配适配；不迁医疗业务 API。

## 结果目录

```text
SupportClient/Projects/Core/Networking/
  AuthTokenProvider.swift
  BackendErrorLocalizer.swift
  ETagStore.swift
  EmptyResponse.swift
  RetryLayer.swift
  SerialRequestGate.swift
  SupportNetworkModels.swift
  SupportNetworkEngine.swift
  SupportNetworkTransport.swift
  SupportBackendConfiguration.swift
  SupportCancellationClassifier.swift
  Caching/DeviceCache.swift
  Caching/SupportCallbackCache.swift
  Logging/SupportNetworkingStrings.swift
  Logging/SupportNetworkOperationBusinessPurpose.swift
  Operations/SupportNetworkOperation.swift
  API/Common/SupportAPIResponseDecoder.swift
  API/Auth|Account/…（既有账户 API，保留）
```

`Core/Networking/` 仅保留业务聚合：`SupportAPIs.swift`、`SupportBackend.swift`。

## 关键能力

| 能力 | 状态 |
| --- | --- |
| NetworkStrategy（allowETag / retryConfig / isIdempotent / queuePriority） | 已对齐 |
| SupportNetworkResponse.didMerge304 | 已对齐 |
| ETagStore + FileETagStore + ETagHTTPInterceptor | 已对齐 |
| RetryLayer + SerialRequestGate | 已对齐 |
| CallbackCache | 已对齐 |
| 账号隔离（URL + Authorization 指纹） | 已对齐 |

## 首批 ETag 接入

- `GET /api/v1/ai/config/bootstrap/`
- `GET /api/v1/files/`

未启用：登录、token refresh、设备登记。

## 验收

- `xcodebuild -scheme SupportClient … build` → **BUILD SUCCEEDED**
- 单测：`SupportClientTests/Networking/SupportNetworkCoreETagRetryGateTests.swift`
