# 问题修复工单｜WebSocket Token 明文日志与 P1 Error 事件

## 1. 工单摘要

当前 iOS 与 DeepTutorSerevr 联调时，WebSocket 握手已经成功：

```text
backend INFO: 192.168.1.212:<port> - "WebSocket /api/v1/ws?token=<full-jwt>" [accepted]
```

但后续仍出现：

```text
P1 event type=error seq=0 session= turn=
```

同时，iOS 仍然因为 SparkService 缺少 AI Bridge Token 签发接口而进入 Debug fallback：

```text
POST /api/v1/ai/chat/token/ -> 404
AI Bridge Token 签发失败，使用 Spark access token 作为 DeepTutor 调试凭证
AIChat WebSocket 连接中 url=ws://192.168.1.152:9898/api/v1/ws?token=<redacted>
```

本工单关注三个联动问题：

1. DeepTutorSerevr access log 明文打印完整 JWT。
2. 同一 token 短时间出现两次 WebSocket `[accepted]`，疑似重复连接或重连噪音。
3. WebSocket accepted 后收到 `type=error`，但 iOS P1 日志没有暴露可定位的错误内容、错误码、request id 或 client message id。

## 2. 当前事实

### 2.1 WebSocket 连接层已通

iOS 当前连接地址：

```text
ws://192.168.1.152:9898/api/v1/ws?token=<redacted>
```

DeepTutorSerevr 返回：

```text
[accepted]
```

说明本次不是 `ws://` scheme 错误，也不是 TCP/WebSocket 握手失败。

### 2.2 Bridge Token 签发仍未完成

iOS 请求：

```http
POST /api/v1/ai/chat/token/
Authorization: Bearer <Spark access token>
```

SparkService 返回：

```http
404 Not Found
Server: daphne
Content-Type: text/html; charset=utf-8
```

该问题已有独立工单：

```text
问题修复工单-AI Bridge Token 签发接口 404.md
```

本工单不重复展开接口实现，只把它作为上游依赖。

### 2.3 iOS P1 已能解析服务端 error 事件

iOS `AIChatDebugViewModel` 收到 `.error` 后会：

```swift
case .error:
    userFacingError = event.content.isEmpty ? "服务端返回错误" : event.content
    connectionState = .failed
```

并记录：

```swift
"P1 event type=\(event.rawEventType) seq=\(event.seq.map(String.init) ?? "-") session=\(event.sessionID ?? "-") turn=\(event.turnID ?? "-")"
```

当前日志只显示：

```text
P1 event type=error seq=0 session= turn=
```

说明服务端发出了 error frame，但 iOS 当前日志没有把 `content` 和 `metadata` 打出来，导致无法从客户端日志定位真实业务失败。

## 3. 问题拆分

| 编号 | 问题 | 严重级别 | 当前表现 | 根因方向 |
| --- | --- | --- | --- | --- |
| WS-P1-1 | 服务端 access log 泄露完整 JWT | P0 安全 | `/api/v1/ws?token=<full-jwt>` 被打印 | token 放 query，uvicorn/daphne access log 记录完整 request line |
| WS-P1-2 | Bridge Token 缺失导致 fallback | P0 阻塞正式链路 | `/api/v1/ai/chat/token/` 404 | SparkService 未实现或未挂载签发接口 |
| WS-P1-3 | 同一 token 出现两次 accepted | P1 稳定性 | 两条 WebSocket accepted 日志 | iOS 重复 connect、旧连接未释放、自动重连或 UI 多次触发 |
| WS-P1-4 | accepted 后立即 error | P1 连通性 | `P1 event type=error seq=0` | start_turn payload 被拒绝、LLM 权限/模型缺失、服务端异常或协议字段缺失 |
| WS-P1-5 | error 可观测性不足 | P1 可调试性 | session/turn 为空，缺少 content/code/request_id | 服务端 error schema 不标准，iOS P1 日志未记录脱敏后的 content/metadata |

## 4. 高概率根因分析

### 4.1 Token 明文日志根因

当前 iOS 已经脱敏：

```text
AIChat WebSocket 连接中 url=ws://192.168.1.152:9898/api/v1/ws?token=<redacted>
```

但服务端 access log 仍打印：

```text
"WebSocket /api/v1/ws?token=<full-jwt>" [accepted]
```

这是服务端日志层问题，不是 iOS 日志问题。

由于当前 DeepTutorSerevr `ws_require_auth` 从 query 读取 token：

```python
token = ws.query_params.get("token") or ws.cookies.get("dt_token")
```

P1 可以继续使用 query token，但必须满足：

1. token 短时效；
2. 服务端 access log 脱敏；
3. Release 不使用 Spark access token fallback；
4. 工单、终端、截图、集中日志不出现原始 JWT。

### 4.2 WebSocket accepted 后仍然 error 的原因

DeepTutorSerevr `/api/v1/ws` 在连接成功后，会根据客户端消息类型处理：

```python
if msg_type in {"message", "start_turn"}:
    try:
        _, turn = await runtime.start_turn(msg)
    except RuntimeError as exc:
        await safe_send({
            "type": "error",
            "source": "unified_ws",
            "content": str(exc),
            "metadata": {"turn_terminal": True, "status": "rejected"},
            "session_id": str(msg.get("session_id") or ""),
            "turn_id": "",
            "seq": 0,
        })
```

因此 `accepted` 只代表 WebSocket 握手成功，不代表 AI 对话 turn 创建成功。

`type=error seq=0 session= turn=` 可能来自：

| 触发点 | 服务端返回 | 可能原因 |
| --- | --- | --- |
| JSON 解析失败 | `Invalid JSON.` | iOS 发送 frame 不是合法 JSON |
| 未知消息类型 | `Unknown type: xxx` | iOS type 字段与后端不一致 |
| 缺少 `turn_id` | `Missing turn_id.` | resume/cancel/submit_user_reply 缺字段 |
| 缺少 `session_id` | `Missing session_id.` | subscribe/check/regenerate 缺字段 |
| `start_turn` 被拒绝 | `RuntimeError(...)` | capability/config/llm_selection/model grant/权限失败 |
| 服务端异常 | `str(exc)` | DeepTutorSerevr 内部异常 |

### 4.3 iOS 当前 P1 payload 与 DeepTutorSerevr 的风险点

iOS P1 最小 payload：

```swift
static func p1Minimal(content: String, sessionID: String? = nil) -> AIStartTurnPayload {
    AIStartTurnPayload(
        content: content,
        sessionID: sessionID,
        capability: "chat",
        tools: [],
        knowledgeBases: [],
        language: "zh",
        config: [:],
        llmSelection: nil
    )
}
```

编码后核心字段为：

```json
{
  "type": "start_turn",
  "content": "用户输入",
  "session_id": null,
  "capability": "chat",
  "tools": [],
  "knowledge_bases": [],
  "language": "zh",
  "config": {},
  "llm_selection": null
}
```

DeepTutorSerevr `start_turn` 中，如果没有 `llm_selection`，会尝试使用 session preferences 或用户授权模型。对非管理员用户，如果没有可用 LLM 授权，会抛出：

```text
No LLM model is assigned to your account. Please contact an administrator.
```

所以本次 `P1 event type=error` 的高概率原因之一是：

1. iOS P1 没有传 `llm_selection`；
2. DeepTutorSerevr 当前用户不是 admin；
3. DeepTutorSerevr 没有给该用户映射可用 LLM grant；
4. 服务端返回 error，但 iOS 当前日志没有打印 error content。

### 4.4 Spark fallback 会放大用户映射问题

当前 fallback 使用 Spark access token：

```text
使用 Spark access token 作为 DeepTutor 调试凭证
```

这个 token 的用户字段来自 SparkService，例如 `user_id=860`。DeepTutorSerevr 即使能接受该 token，也不代表：

1. DeepTutorSerevr 已有同一用户；
2. DeepTutorSerevr 已为该用户分配 LLM 模型；
3. DeepTutorSerevr 能把 Spark user id 映射到自己的 grants；
4. DeepTutorSerevr 能读取 Spark 侧 proOverlay 解析出来的模型。

因此 fallback 只能证明“握手临时可通”，不能证明“正式 AI turn 可创建”。

## 5. 优化目标

1. 服务端日志不再泄露完整 JWT。
2. iOS WebSocket connect 具备幂等保护，不重复建立同一连接。
3. DeepTutorSerevr error frame 标准化，能定位错误原因。
4. iOS P1 Debug 日志展示脱敏后的 error content 和 metadata。
5. Bridge Token 正式签发后，Release 不再使用 Spark access token fallback。
6. iOS 能把模型选择或 DeepTutorSerevr 可识别的 LLM grant 明确传入/映射。

## 6. 服务端优化方案

### 6.1 P0：关闭或脱敏 WebSocket access log

本地最快止血方案：

```bash
uvicorn deeptutor.api.main:app \
  --host 0.0.0.0 \
  --port 9898 \
  --no-access-log
```

如果必须保留 access log，需要增加 token 脱敏过滤。

伪代码：

```python
import logging
import re


class WebSocketTokenRedactionFilter(logging.Filter):
    token_pattern = re.compile(r"(token=)[^\\s\\\"]+")

    def filter(self, record: logging.LogRecord) -> bool:
        message = record.getMessage()
        redacted = self.token_pattern.sub(r"\\1<redacted>", message)
        record.msg = redacted
        record.args = ()
        return True


logging.getLogger("uvicorn.access").addFilter(WebSocketTokenRedactionFilter())
```

验收标准：

```text
允许：WebSocket /api/v1/ws?token=<redacted> [accepted]
禁止：WebSocket /api/v1/ws?token=eyJhbGci...
```

### 6.2 P0：Bridge Token 正式化

继续推进已有工单：

```text
问题修复工单-AI Bridge Token 签发接口 404.md
```

正式链路：

```text
iOS -> SparkService: POST /api/v1/ai/chat/token/
SparkService -> iOS: short-lived deeptutor_bridge token
iOS -> DeepTutorSerevr: ws://.../api/v1/ws?token=<bridge-token>
DeepTutorSerevr: 校验 token_type/purpose/iss/aud/exp/user mapping
```

Release 约束：

1. `/api/v1/ai/chat/token/` 失败时不 fallback。
2. 不把 Spark access token 传给 DeepTutorSerevr。
3. Bridge token TTL 建议 10 分钟，不超过 15 分钟。

### 6.3 P1：标准化 WebSocket error frame

当前 error frame 只有 `type/content/session_id/turn_id/seq`，信息不足。

建议统一为：

```json
{
  "type": "error",
  "source": "unified_ws",
  "stage": "start_turn",
  "content": "No LLM model is assigned to your account. Please contact an administrator.",
  "metadata": {
    "code": "llm_model_not_assigned",
    "reason": "no_available_llm_grant",
    "status": "rejected",
    "turn_terminal": true,
    "recoverable": false,
    "request_id": "server-request-id",
    "client_message_id": "ios-generated-message-id"
  },
  "session_id": "",
  "turn_id": "",
  "seq": 0
}
```

建议错误码：

| code | reason | 用户提示 | 是否可重试 |
| --- | --- | --- | --- |
| `invalid_json` | frame 不是合法 JSON | 请求格式错误 | 否 |
| `unknown_message_type` | type 不在协议内 | 客户端版本不兼容 | 否 |
| `missing_session_id` | 缺少 session_id | 会话状态异常 | 否 |
| `missing_turn_id` | 缺少 turn_id | 对话状态异常 | 否 |
| `invalid_capability_config` | capability/config 校验失败 | 对话配置异常 | 否 |
| `llm_model_not_assigned` | 用户没有可用 LLM grant | 当前账号未配置可用模型 | 否 |
| `llm_selection_invalid` | llm_selection 不存在或无权限 | 模型不可用，请重新选择 | 否 |
| `turn_rejected` | start_turn 被业务拒绝 | 对话启动失败 | 视 reason |
| `internal_error` | 未分类服务端异常 | 服务暂时不可用 | 是 |

### 6.4 P1：服务端记录脱敏排障日志

在 `start_turn` RuntimeError 分支记录结构化日志：

伪代码：

```python
logger.warning(
    "WS start_turn rejected user_id=%s session_id=%s code=%s reason=%s client_message_id=%s",
    current_user.id,
    msg.get("session_id") or "",
    error_code,
    reason,
    msg.get("client_message_id") or "",
)
```

注意：

1. 不记录 token。
2. 不记录完整用户输入 content。
3. content 最多记录长度、hash 或前 20 字脱敏摘要。

### 6.5 P1：模型选择/授权映射

当前日志出现：

```text
已解析场景=chat，来源=proOverlay，模型=agent-19-15-doubao-seed-2-0-pro-260215
```

但 iOS P1 payload 当前不传 `llm_selection`。

建议三选一，推荐方案 A：

| 方案 | 说明 | 推荐度 |
| --- | --- | --- |
| A | SparkService Bridge Token 签发时返回 DeepTutorSerevr 可识别的 `llm_selection` 或 model mapping | 推荐 |
| B | iOS 从 Spark AI 设置读取模型映射后，在 `start_turn.llm_selection` 中显式传给 DeepTutorSerevr | 可用 |
| C | DeepTutorSerevr 根据 bridge token 中的 Spark user id 自动映射默认 LLM grant | 可用，但服务端耦合更强 |

推荐响应增加：

```json
{
  "code": 0,
  "msg": "ok",
  "data": {
    "token": "<bridge-token>",
    "expires_at": 1785422366,
    "deeptutor_ws_url": "ws://192.168.1.152:9898/api/v1/ws",
    "deeptutor_http_base_url": "http://192.168.1.152:9898",
    "llm_selection": {
      "profile_id": "agent-19-15",
      "model_id": "doubao-seed-2-0-pro-260215"
    }
  }
}
```

iOS 再透传到：

```json
{
  "type": "start_turn",
  "content": "用户输入",
  "capability": "chat",
  "llm_selection": {
    "profile_id": "agent-19-15",
    "model_id": "doubao-seed-2-0-pro-260215"
  }
}
```

字段名必须以 DeepTutorSerevr `LLMSelection.from_payload` 真实要求为准。

## 7. iOS 优化方案

### 7.1 P1：WebSocket connect 幂等保护

当前 `AIChatWebSocketClient.connect(url:)` 会直接 `openSocket()`：

```swift
func connect(url: URL) async throws {
    intentionalClose = false
    connectionURL = url
    reconnectAttempt = 0
    try await openSocket()
}
```

建议增加同 URL 幂等逻辑：

```swift
func connect(url: URL) async throws {
    if task?.state == .running, connectionURL == url {
        logger.debug("AIChat WebSocket 已连接，跳过重复 connect", module: .aiChat)
        return
    }

    if task != nil {
        disconnect(clearResumeState: false)
    }

    intentionalClose = false
    connectionURL = url
    reconnectAttempt = 0
    try await openSocket()
}
```

验收：

1. 点击“连接”后再点击“发送”，不应出现第二条相同 token 的 `[accepted]`。
2. 网络断开后的自动重连仍然可用。
3. 主动 disconnect 后再 connect 可以重新连接。

### 7.2 P1：为 outgoing message 增加 client_message_id

建议 iOS 每次发送业务 frame 时带上 `client_message_id`：

```json
{
  "type": "start_turn",
  "client_message_id": "ios-uuid",
  "content": "用户输入",
  "session_id": null,
  "capability": "chat"
}
```

服务端 error frame 原样回传：

```json
{
  "type": "error",
  "metadata": {
    "client_message_id": "ios-uuid",
    "code": "llm_model_not_assigned"
  }
}
```

这样可以把：

```text
iOS send start_turn -> server reject -> iOS receive error
```

串成同一条诊断链路。

### 7.3 P1：P1 Debug 日志补充 error content 和 metadata

当前日志：

```swift
"P1 event type=\(event.rawEventType) seq=\(event.seq.map(String.init) ?? "-") session=\(event.sessionID ?? "-") turn=\(event.turnID ?? "-")"
```

建议 error 分支额外打印脱敏摘要：

```swift
if event.type == .error {
    logger.warning(
        "P1 error seq=\(event.seq.map(String.init) ?? "-") session=\(event.sessionID ?? "-") turn=\(event.turnID ?? "-") content=\(LogMessageSanitizer.singleLineSnippet(event.content, limit: 160)) metadata=\(AIChatLogSanitizer.metadataSummary(event.metadata))",
        module: .aiChat
    )
}
```

注意：

1. 不打印 token。
2. 不打印完整用户输入。
3. metadata 需要过滤 `token`、`authorization`、`api_key`、`secret`、`password`。

### 7.4 P1：Release 禁止 fallback

Debug 可以保留：

```swift
#if DEBUG
// Spark access token fallback for local integration only
#endif
```

Release 必须：

1. Bridge Token 签发失败即失败；
2. 不连接 DeepTutorSerevr；
3. 展示“AI 服务暂不可用/配置未完成”；
4. 打点错误原因但不泄露 token。

## 8. 排障顺序

### 8.1 第一步：先止血 token 日志

目标：

```text
服务端日志不再出现 eyJhbGci...
```

执行后再继续联调，避免每一次测试都泄露新 token。

### 8.2 第二步：确认重复连接来源

观察一次完整操作：

1. 只点击“连接”。
2. 查看服务端是否只有一条 `[accepted]`。
3. 再点击“发送”。
4. 查看是否出现第二条 `[accepted]`。

如果发送时出现第二条 `[accepted]`，优先查 iOS `sendStartTurn()` 是否在 `connectionState` 判断下再次 `repository.connect()`。

如果没有点击发送也出现第二条 `[accepted]`，优先查 `AIChatWebSocketClient` 自动重连、heartbeat timeout 或 receive loop 报错。

### 8.3 第三步：打印 error content

在 iOS P1 Debug 或服务端日志确认 error content。

常见判断：

| content | 判断 |
| --- | --- |
| `No LLM model is assigned...` | DeepTutorSerevr 用户没有可用模型授权 |
| `Unknown type: ...` | iOS 发送 type 与后端协议不一致 |
| `Invalid JSON.` | iOS frame 编码异常 |
| `Missing session_id.` | iOS 对需要 session 的消息没有传 session_id |
| `Missing turn_id.` | iOS 对 turn 操作没有传 turn_id |
| `invalid capability config` | iOS config 字段与 capability schema 不一致 |

### 8.4 第四步：收敛模型选择

如果 error 是模型授权问题，按以下顺序处理：

1. 确认 DeepTutorSerevr 当前用户是否 admin。
2. 确认当前用户是否有 LLM grant。
3. 确认 Spark user id 与 DeepTutor user id 映射。
4. 确认 proOverlay 解析出的模型是否能转换为 DeepTutorSerevr `llm_selection`。
5. 确认 iOS `start_turn` 是否传入 `llm_selection`，或 Bridge Token 是否携带默认模型。

## 9. 验收标准

| 编号 | 标准 |
| --- | --- |
| AC1 | DeepTutorSerevr access log 不再打印完整 JWT |
| AC2 | iOS 日志继续只打印 `<redacted>` token |
| AC3 | 同一次用户操作不会建立两个相同 URL/token 的 WebSocket 连接 |
| AC4 | Bridge Token 404 问题关闭后，iOS Debug 使用 bridge token 而不是 Spark access token |
| AC5 | iOS Release 不存在 Spark access token fallback |
| AC6 | 服务端 error frame 包含 `metadata.code`、`metadata.reason`、`metadata.recoverable` |
| AC7 | 服务端 error frame 能回传 `client_message_id` |
| AC8 | iOS P1 Debug 能展示脱敏后的 error content 和 metadata 摘要 |
| AC9 | 如果用户没有 LLM 授权，iOS 展示明确提示，而不是只显示“服务端返回错误” |
| AC10 | 如果模型配置正确，`start_turn` 后能收到 `session`、`content/result`、`done` 事件 |

## 10. 实施拆分

| 阶段 | 目标 | 负责端 | 说明 |
| --- | --- | --- | --- |
| T0 | 关闭或脱敏服务端 access log token | DeepTutorSerevr | 安全止血，优先级最高 |
| T1 | Bridge Token 签发接口完成 | SparkService + DeepTutorSerevr | 参考已有 404 工单 |
| T2 | WebSocket connect 幂等 | iOS | 避免重复 accepted |
| T3 | error frame 标准化 | DeepTutorSerevr | code/reason/request_id/client_message_id |
| T4 | iOS error 日志与 UI 诊断增强 | iOS | 脱敏输出 content/metadata |
| T5 | 模型选择/授权映射 | SparkService + DeepTutorSerevr + iOS | 解决 accepted 后 start_turn rejected |

## 11. 风险与注意事项

1. 不能把 `[accepted]` 当作 AI 对话可用，只能说明 WebSocket 握手成功。
2. 不能继续在工单、截图、终端记录完整 JWT。
3. 不能在 Release 使用 Spark access token fallback。
4. 不能只改 iOS，`type=error` 的根因多半在 DeepTutorSerevr `start_turn` 校验或模型授权。
5. 不能只让 DeepTutorSerevr 接受 Spark token，必须收敛到短时效 Bridge Token。
6. 如果 iOS 需要传 `llm_selection`，字段必须与 DeepTutorSerevr `LLMSelection.from_payload` 对齐，不能直接把 Spark 侧模型字符串当成 DeepTutor 结构。

## 12. 建议优先级

本工单建议优先级：

```text
P0 安全止血：token 明文日志
P0 正式链路：Bridge Token 404
P1 连通稳定：重复连接幂等
P1 可观测性：error schema + iOS Debug 日志
P1 业务可用：LLM selection / grant 映射
```

