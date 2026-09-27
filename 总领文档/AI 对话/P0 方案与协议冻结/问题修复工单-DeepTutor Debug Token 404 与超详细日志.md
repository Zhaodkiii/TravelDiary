# 问题修复工单｜DeepTutor Debug Token 404 与超详细日志

## 1. 工单摘要

当前 iOS 在 Debug 调试链路中请求 DeepTutorSerevr 的 debug token：

```text
AIChat token_resolve_start source=DeepTutorSerevr endpoint=http://192.168.1.152:9898/api/v1/mobile/auth/debug-token ai_trace_id=AIC-20260730-230752-4281E6E1
```

但 DeepTutorSerevr 返回：

```text
backend WARNING deeptutor.api.routers.mobile_auth - mobile auth debug_token rejected reason=debug_token_disabled
backend 192.168.1.212 - "POST /api/v1/mobile/auth/debug-token HTTP/1.1" 404
AIChat token_resolve_response status=404 detail=debug_token_disabled cost=0.037s ai_trace_id=AIC-20260730-230752-4281E6E1
AIChat token_resolve_failed status=404 detail=debug_token_disabled reason=endpoint_unavailable auth_context=deeptutor ai_trace_id=AIC-20260730-230752-4281E6E1
AIChat state_change from=connecting to=failed trigger=connect_error ai_trace_id=AIC-20260730-230752-4281E6E1
```

前端页面已经提示：

```text
AI服务版本不匹配，请更新应用或联系管理员。
```

本工单聚焦两个问题：

1. 找出 debug-token 404 的真实原因并给出修复方案。
2. 把 iOS 的 AIChat 日志补到“超级详细”级别，方便一次失败就能完整复盘。

## 2. 当前事实

### 2.1 debug-token 路由存在，但被开关关闭

DeepTutorSerevr 路由：

```python
@router.post("/debug-token")
async def issue_debug_mobile_token(body: MobileTokenRequest):
    _validate_request(body)
    if not is_debug_mobile_token_enabled():
        logger.warning("mobile auth debug_token rejected reason=debug_token_disabled")
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="debug_token_disabled")
```

服务端开关：

```python
def is_debug_mobile_token_enabled() -> bool:
    return os.getenv("DEEPTUTOR_MOBILE_DEBUG_TOKEN_ENABLED", "false").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }
```

结论：

1. 接口没有丢。
2. 它只是被默认关闭。
3. 当前 404 是预期行为，不是路由错误。

### 2.2 iOS 当前会优先走 debug-token

iOS `DeepTutorTokenAPI` 在 Debug 分支里请求：

```swift
let endpoint = environment.deepTutorBaseURL.appending(path: "api/v1/mobile/auth/debug-token")
```

也就是说：

1. 只要是 Debug 环境；
2. 并且 `environment == .debug`；
3. iOS 就会尝试拿 DeepTutor debug token；
4. 如果服务端没开这个开关，就会直接 404。

### 2.3 当前独立服务边界不变

这个工单延续之前已经确认的架构结论：

```text
DeepTutorSerevr 与 SparkService 完全独立。
token 不通用，不互换，不互相校验。
```

因此，这次不再讨论 Spark token，也不再回到 SparkService 侧换票。

## 3. 根因定位

### 3.1 直接根因

`DEEPTUTOR_MOBILE_DEBUG_TOKEN_ENABLED=false` 或未设置。

所以 `POST /api/v1/mobile/auth/debug-token` 返回 404 `debug_token_disabled`。

### 3.2 为什么 iOS 会显示“AI服务版本不匹配”

这是 iOS 对 `endpoint_unavailable` 的统一用户文案。

当前 `DeepTutorTokenAPI` 在收到 404 时会：

```swift
diagnostics.logTokenResolveFailed(status: 404, detail: detail, reason: "endpoint_unavailable")
throw AIChatError.deepTutorTokenEndpointUnavailable
```

然后 UI 显示版本不匹配或服务不可用。

这不是“版本真的不匹配”，而是“debug-token 在服务端被关闭”。

## 4. 修复方案

### 4.1 服务端修复 A：明确 Debug 开关的启用条件

建议把 debug-token 的启用条件写死为开发/联调环境，并在启动时打印清楚：

```text
mobile auth debug_token_enabled=true env=dev bind=0.0.0.0:9898
```

推荐环境变量：

```bash
DEEPTUTOR_MOBILE_DEBUG_TOKEN_ENABLED=true
```

配套环境建议：

```bash
DEEPTUTOR_HTTP_BASE_URL=http://192.168.1.152:9898
DEEPTUTOR_WS_URL=ws://192.168.1.152:9898/api/v1/ws
DEEPTUTOR_ALLOWED_MOBILE_BUNDLES=cn.zhaodk.SupportClient
```

### 4.2 服务端修复 B：Debug token 只允许本地/开发环境

即使开关打开，也建议再加一层保护：

| 条件 | 结果 |
| --- | --- |
| `DEBUG=true` 且 `DEEPTUTOR_MOBILE_DEBUG_TOKEN_ENABLED=true` | 允许 |
| `DEBUG=false` | 拒绝 |
| bundle 不在白名单 | 403 |
| 不是 iOS | 400 |

建议日志：

```text
mobile auth debug_token issue_start enabled=true env=debug bundle=cn.zhaodk.SupportClient
mobile auth debug_token issued user_id=local-admin client=ios bundle=cn.zhaodk.SupportClient
```

禁止日志：

```text
token=eyJhbGci...
```

### 4.3 iOS 修复 A：把 token 解析日志再加细一层

当前 iOS 已经有：

```text
token_resolve_start
token_resolve_response
token_resolve_failed
state_change
```

建议继续增强为“请求-响应-重试-状态机”四段式。

#### 4.3.1 请求日志

```text
AIChat token_resolve_request
method=POST
endpoint=http://192.168.1.152:9898/api/v1/mobile/auth/debug-token
auth_context=deeptutor_debug
body_keys=[client,app_bundle,purpose,device_id]
body_masked={client:ios, app_bundle:cn.zhaodk.SupportClient, purpose:deeptutor_ai_chat, device_id:<redacted-or-empty>}
```

#### 4.3.2 响应日志

```text
AIChat token_resolve_response
status=404
detail=debug_token_disabled
cost=0.037s
response_size=179B
response_type=error
```

#### 4.3.3 失败日志

```text
AIChat token_resolve_failed
status=404
detail=debug_token_disabled
reason=endpoint_unavailable
retryable=false
auth_context=deeptutor_debug
ai_trace_id=...
```

#### 4.3.4 状态机日志

```text
AIChat state_change from=idle to=connecting trigger=user_send
AIChat state_change from=connecting to=failed trigger=connect_error code=endpoint_unavailable
AIChat state_change from=failed to=idle trigger=user_dismiss_error
```

### 4.4 iOS 修复 B：失败 UI 分类更准确

当前“AI服务版本不匹配”可以保留，但要在 Debug 日志里区分：

| 失败类型 | 用户文案 | 诊断含义 |
| --- | --- | --- |
| `debug_token_disabled` | AI服务调试入口未开启 | 服务端 debug-token 开关没打开 |
| `endpoint_unavailable` | AI服务版本不匹配，请更新应用或联系管理员 | 调试接口不可用 |
| `auth_failed` | AI服务认证失败，请重新登录 | token 无效或过期 |
| `forbidden_bundle` | 当前应用未被允许使用 AI 服务 | bundle 白名单问题 |

### 4.5 iOS 修复 C：把“超级详细日志”落到具体字段

建议 iOS 最少记录以下字段：

| 类别 | 字段 |
| --- | --- |
| 页面 | `ai_trace_id`、页面名、入口来源 |
| token | `auth_context`、token 来源、token 类型、是否缓存命中、是否刷新 |
| HTTP | method、endpoint、status、detail、cost、response_size、request_id |
| 请求体 | body_keys、body_shape、body hash、body size |
| WebSocket | `connection_attempt_id`、`ws_session_id`、url(脱敏)、connect/open/disconnect/retry |
| 消息 | `client_message_id`、`turn_id`、`session_id`、message type、seq |
| 状态机 | from、to、trigger、error code |
| 错误 | `reason`、`retryable`、`recoverable`、UI 文案 key |

### 4.6 服务端修复 C：在 debug-token 路由加启动提示

当 debug-token 被关闭时，除了 404，还建议给启动日志一个醒目标识：

```text
mobile auth debug_token availability=false reason=disabled_by_env
```

这样开发者一眼就能知道不是代码坏了，而是开关没开。

## 5. 修复路径

### 5.1 开发环境

1. 在 DeepTutorSerevr 开启 `DEEPTUTOR_MOBILE_DEBUG_TOKEN_ENABLED=true`。
2. 确认 `DEEPTUTOR_HTTP_BASE_URL` 和 `DEEPTUTOR_WS_URL` 配置正确。
3. 重新启动 DeepTutorSerevr。
4. iOS Debug 再次请求 `/api/v1/mobile/auth/debug-token`。
5. 成功后进入 WebSocket，再验证 `start_turn`。

### 5.2 生产环境

1. 不允许 debug-token。
2. 只允许正式 DeepTutor mobile auth 方案。
3. Debug token 入口必须 404 或 403。
4. iOS Release 必须不依赖 debug-token。

## 6. 验证步骤

### 6.1 先验服务端开关

```bash
echo $DEEPTUTOR_MOBILE_DEBUG_TOKEN_ENABLED
```

预期：

```text
true
```

### 6.2 打接口验证

```bash
curl -i \
  -X POST "http://192.168.1.152:9898/api/v1/mobile/auth/debug-token" \
  -H "Content-Type: application/json" \
  -d '{
    "client": "ios",
    "app_bundle": "cn.zhaodk.SupportClient",
    "purpose": "deeptutor_ai_chat",
    "device_id": "debug-device"
  }'
```

预期成功响应：

```json
{
  "code": 0,
  "msg": "ok",
  "data": {
    "token": "<deeptutor-mobile-token>",
    "token_type": "deeptutor_mobile_access"
  }
}
```

### 6.3 iOS 端验证

成功时日志应该出现：

```text
AIChat token_resolve_start source=DeepTutorSerevr auth_context=deeptutor_debug endpoint=...
AIChat token_resolve_request method=POST endpoint=... auth_context=deeptutor_debug body_keys=[client,app_bundle,purpose,device_id]
AIChat token_resolve_response status=200 detail=ok cost=...
AIChat token_resolve_result auth_mode=DeepTutor Mobile Access source=deeptutor_debug expires_in=... ws_url=...
AIChat ws_connect_start ...
```

失败时日志应该出现：

```text
AIChat token_resolve_failed status=404 detail=debug_token_disabled reason=endpoint_unavailable auth_context=deeptutor_debug
```

## 7. 验收标准

| 编号 | 标准 |
| --- | --- |
| AC1 | `DEEPTUTOR_MOBILE_DEBUG_TOKEN_ENABLED=true` 时 `/api/v1/mobile/auth/debug-token` 可返回 200 |
| AC2 | `DEEPTUTOR_MOBILE_DEBUG_TOKEN_ENABLED=false` 时 debug-token 继续 404 |
| AC3 | iOS Debug 日志能明确区分 `debug_token_disabled` 与 `endpoint_unavailable` |
| AC4 | iOS 日志包含 request method / endpoint / status / detail / cost / body_keys / ai_trace_id |
| AC5 | iOS 不打印 token 原文 |
| AC6 | 成功拿到 debug token 后可继续进入 WebSocket |
| AC7 | 失败时状态机能从 `connecting` 正确回到 `failed`，不会卡死 |
| AC8 | Release 构建不依赖 debug-token |
| AC9 | 服务端启动日志能一眼看出 debug-token 是否启用 |
| AC10 | 开发者不需要猜测“版本不匹配”到底是接口没开还是环境没配 |

## 8. 实施拆分

| 阶段 | 目标 | 负责端 | 说明 |
| --- | --- | --- | --- |
| T0 | 启动日志补充 | DeepTutorSerevr | 打印 debug-token 开关状态 |
| T1 | debug-token 开关校验 | DeepTutorSerevr | 只在明确的 dev 环境启用 |
| T2 | iOS 请求日志增强 | SupportClient | 请求/响应/状态机三段式日志 |
| T3 | iOS 失败分类 | SupportClient | 区分 disabled / unavailable / auth_failed |
| T4 | 端到端联调 | iOS + DeepTutorSerevr | debug token -> ws -> start_turn |

## 9. 风险与注意事项

1. 不要把 debug-token 当成生产认证接口。
2. 不要因为 404 就判断接口坏了，它可能只是开关关闭。
3. 不要把 token 原文打进日志。
4. 不要让 Release 依赖 debug-token。
5. 不要把“AI服务版本不匹配”作为唯一文案，日志里要区分真实原因。
6. iOS 日志增强后要继续保持脱敏，不要为了排障牺牲安全。

## 10. 本工单结论

当前问题的真实原因是：

```text
DeepTutorSerevr 的 debug-token 路由被环境开关关闭了。
```

修复方案是：

1. 开发环境显式开启 `DEEPTUTOR_MOBILE_DEBUG_TOKEN_ENABLED=true`。
2. DeepTutorSerevr 打印 debug-token 开关状态。
3. iOS 补充超级详细日志，区分请求、响应、状态机和错误原因。
4. Release 不依赖 debug-token。

