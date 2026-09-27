# 问题修复工单｜WebSocket URL Scheme 崩溃

## 1. 问题摘要

| 项目 | 内容 |
| --- | --- |
| 工单编号 | AIChat-P0-BUG-001 |
| 问题标题 | `URLSessionWebSocketTask` 收到 `http://` URL 导致 App 崩溃 |
| 严重级别 | P0 / Crash |
| 影响模块 | AIChat WebSocket 连接、Debug 联调入口 |
| 影响端 | iOS |
| 当前状态 | 待修复 |
| 是否修改代码 | 本工单只描述方案，不修改代码 |

崩溃日志核心信息：

```text
AIChat WebSocket 连接中 url=http://192.168.1.152:9898/api/v1/ws?token=%3Credacted%3E
*** Terminating app due to uncaught exception 'NSGenericException',
reason: 'WebSocket tasks can only be created with ws or wss schemes'
```

调用栈核心位置：

```text
AIChatWebSocketConnection.makeTask()
  at SupportClient/Projects/Features/AIChat/Infrastructure/AIChatWebSocketConnection.swift:78

AIChatWebSocketClient.openSocket()
  at SupportClient/Projects/Features/AIChat/Infrastructure/AIChatWebSocketClient.swift:88

AIChatRepository.connect()
  at SupportClient/Projects/Features/AIChat/Infrastructure/AIChatRepository.swift:81

AIChatDebugViewModel.connect()
  at SupportClient/Projects/Features/AIChat/Application/AIChatDebugViewModel.swift:44
```

## 2. 根因定位

### 2.1 直接原因

`URLSession.webSocketTask(with:)` 只能接受 `ws://` 或 `wss://` URL。

当前实际传入：

```text
http://192.168.1.152:9898/api/v1/ws?token=<redacted>
```

因此 Foundation 内部抛出 `NSGenericException`：

```text
WebSocket tasks can only be created with ws or wss schemes
```

这个异常是 Objective-C `NSException`，不是普通 Swift `Error`。也就是说：

- `do/catch` 捕获不到。
- `async throws` 捕获不到。
- 一旦调用 `session.webSocketTask(with: httpURL)`，App 会直接终止。

所以必须在调用 `webSocketTask(with:)` 之前完成 URL scheme 校验。

### 2.2 配置根因

当前代码位置：

```text
/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/App/Sources/App/SupportAppEnvironment.swift
```

当前 Debug 配置：

```swift
var deepTutorWebSocketBaseURL: URL {
    switch self {
    case .debug:
        return URL(string: "http://192.168.1.152:9898")!
    case .staging, .production:
        return URL(string: "wss://www.dreamhua.top")!
    }
}
```

问题：

```text
deepTutorWebSocketBaseURL.debug 使用了 http://
```

它经过：

```swift
func deepTutorWebSocketURL(token: String) -> URL {
    var components = URLComponents(
        url: deepTutorWebSocketBaseURL.appending(path: "api/v1/ws"),
        resolvingAgainstBaseURL: false
    )!
    components.queryItems = [URLQueryItem(name: "token", value: token)]
    return components.url!
}
```

最终得到：

```text
http://192.168.1.152:9898/api/v1/ws?token=...
```

然后进入：

```swift
nonisolated func makeTask() -> URLSessionWebSocketTask {
    session.webSocketTask(with: url)
}
```

直接崩溃。

### 2.3 结构性风险

除了本地 `SupportAppEnvironment` 配置错误，还有第二个入口也可能把错误 URL 带进来。

代码位置：

```text
/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/AIBridgeTokenAPI.swift
```

当前逻辑：

```swift
private static func webSocketBaseURL(from wsURLString: String) -> URL? {
    guard var components = URLComponents(string: wsURLString) else { return nil }
    components.path = ""
    components.query = nil
    return components.url
}
```

如果 SparkService 返回：

```json
{
  "deeptutor_ws_url": "http://192.168.1.152:9898/api/v1/ws"
}
```

当前方法会生成：

```text
http://192.168.1.152:9898
```

后续 `AIChatRepository` 再拼接 `/api/v1/ws`，仍然会得到错误的 `http://` WebSocket URL。

因此修复不能只改 Debug 配置，还要在 WebSocket URL 入口做统一校验和归一化。

## 3. 影响范围

| 场景 | 是否受影响 | 说明 |
| --- | --- | --- |
| Debug 本地联调 | 是 | 当前 `deepTutorWebSocketBaseURL` 为 `http://192.168.1.152:9898` |
| Simulator 连接本机服务 | 可能 | 如果配置为 `http://localhost:<port>` 同样崩溃 |
| 真机连接局域网服务 | 是 | 需要 `ws://局域网IP:端口` |
| Staging | 取决于配置 | 当前示例是 `wss://www.dreamhua.top`，但仍需校验 |
| Production | 高风险 | 如果后端覆盖返回 `http://`，会造成线上 crash |
| AI Bridge Token 回退 access token | 间接受影响 | 当前日志显示回退后使用环境中的错误 WebSocket URL |

## 4. 修复目标

修复后必须满足：

- 任何进入 `URLSession.webSocketTask(with:)` 的 URL 必须是 `ws` 或 `wss`。
- Debug 下本地 IP 使用 `ws://`，不是 `http://`。
- Production 下必须使用 `wss://`，不允许 `ws://`。
- 如果 SparkService 返回 `deeptutor_ws_url`，客户端必须校验和归一化。
- 如果 URL 非法，返回可展示的 `AIChatError.connectionFailed`，不能 crash。
- 日志中继续脱敏 token。

## 5. 推荐修复方案

### 5.1 第一层修复：修正环境配置

文件：

```text
SupportClient/Projects/App/Sources/App/SupportAppEnvironment.swift
```

Debug 应改为：

```swift
var deepTutorWebSocketBaseURL: URL {
    switch self {
    case .debug:
        return URL(string: "ws://192.168.1.152:9898")!
    case .staging, .production:
        return URL(string: "wss://www.dreamhua.top")!
    }
}
```

注意：

- `deepTutorBaseURL` 仍然应该是 `http://192.168.1.152:9898`，用于 HTTP API。
- `deepTutorWebSocketBaseURL` 必须是 `ws://192.168.1.152:9898`，用于 WebSocket。
- HTTP 和 WebSocket 地址可以 host/port 相同，但 scheme 必须不同。

正确结果：

```text
ws://192.168.1.152:9898/api/v1/ws?token=<redacted>
```

错误结果：

```text
http://192.168.1.152:9898/api/v1/ws?token=<redacted>
```

### 5.2 第二层修复：在 URL builder 层做 scheme 归一化

建议新增一个统一方法，把 HTTP base URL 转为 WebSocket base URL。

适用位置：

```text
SupportAppEnvironment.swift
```

示例：

```swift
private static func webSocketBaseURL(from baseURL: URL) -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
        assertionFailure("Invalid DeepTutor base URL: \(baseURL)")
        return baseURL
    }

    switch components.scheme?.lowercased() {
    case "http":
        components.scheme = "ws"
    case "https":
        components.scheme = "wss"
    case "ws", "wss":
        break
    default:
        assertionFailure("Unsupported WebSocket URL scheme: \(components.scheme ?? "<nil>")")
    }

    components.path = ""
    components.query = nil
    components.fragment = nil

    return components.url ?? baseURL
}
```

然后可以把配置收敛成：

```swift
var deepTutorBaseURL: URL {
    switch self {
    case .debug:
        return URL(string: "http://192.168.1.152:9898")!
    case .staging, .production:
        return URL(string: "https://www.dreamhua.top")!
    }
}

var deepTutorWebSocketBaseURL: URL {
    Self.webSocketBaseURL(from: deepTutorBaseURL)
}
```

这样 Debug 自动得到：

```text
ws://192.168.1.152:9898
```

Production 自动得到：

```text
wss://www.dreamhua.top
```

### 5.3 第三层修复：在 `deepTutorWebSocketURL(token:)` 做最终校验

文件：

```text
SupportAppEnvironment.swift
```

当前方法直接 `return components.url!`，建议改成可失败版本或增加前置校验。

推荐新增：

```swift
func makeDeepTutorWebSocketURL(token: String) throws -> URL {
    var components = URLComponents(
        url: deepTutorWebSocketBaseURL.appending(path: "api/v1/ws"),
        resolvingAgainstBaseURL: false
    )!
    components.queryItems = [URLQueryItem(name: "token", value: token)]

    guard let url = components.url else {
        throw AIChatError.connectionFailed("无法生成 AI 对话 WebSocket URL")
    }

    guard url.isWebSocketURL else {
        throw AIChatError.connectionFailed("AI 对话 WebSocket URL 配置错误")
    }

    return url
}
```

配套扩展：

```swift
extension URL {
    var isWebSocketURL: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "ws" || scheme == "wss"
    }
}
```

如果暂时不想改方法签名，也至少要在内部 `precondition` 或 `assertionFailure` 前发现问题。但从稳定性看，更推荐 `throws`。

### 5.4 第四层修复：在 `AIChatWebSocketConnection.makeTask()` 前置校验

文件：

```text
SupportClient/Projects/Features/AIChat/Infrastructure/AIChatWebSocketConnection.swift
```

当前代码：

```swift
nonisolated func makeTask() -> URLSessionWebSocketTask {
    session.webSocketTask(with: url)
}
```

推荐改为：

```swift
nonisolated func makeTask() throws -> URLSessionWebSocketTask {
    guard url.isWebSocketURL else {
        throw AIChatError.connectionFailed(
            "Invalid WebSocket URL scheme: \(url.scheme ?? "<nil>")"
        )
    }
    return session.webSocketTask(with: url)
}
```

同时 `AIChatWebSocketClient.openSocket()` 改为：

```swift
let webSocketTask = try connection.makeTask()
task = webSocketTask
webSocketTask.resume()
```

这样非法 URL 会进入现有 `async throws` 链路，而不是触发 `NSException`。

### 5.5 第五层修复：校验 AI Bridge Token 返回的 WS 覆盖 URL

文件：

```text
SupportClient/Projects/Features/AIChat/Infrastructure/AIBridgeTokenAPI.swift
```

当前方法只清 path/query，不校验 scheme：

```swift
private static func webSocketBaseURL(from wsURLString: String) -> URL? {
    guard var components = URLComponents(string: wsURLString) else { return nil }
    components.path = ""
    components.query = nil
    return components.url
}
```

推荐改为：

```swift
private static func webSocketBaseURL(from wsURLString: String) -> URL? {
    guard var components = URLComponents(string: wsURLString) else { return nil }

    switch components.scheme?.lowercased() {
    case "ws", "wss":
        break
    case "http":
        components.scheme = "ws"
    case "https":
        components.scheme = "wss"
    default:
        return nil
    }

    components.path = ""
    components.query = nil
    components.fragment = nil

    guard let url = components.url, url.isWebSocketURL else { return nil }
    return url
}
```

如果希望更严格：

- Debug 可以允许 `http -> ws`、`https -> wss` 自动转换。
- Production 只接受服务端返回 `wss://`，不接受 `http://` 或 `ws://`。

Production 严格版本示例：

```swift
private static func webSocketBaseURL(
    from wsURLString: String,
    environment: SupportAppEnvironment
) -> URL? {
    guard var components = URLComponents(string: wsURLString) else { return nil }

    let scheme = components.scheme?.lowercased()
    switch (environment, scheme) {
    case (.production, "wss"):
        break
    case (.production, _):
        return nil
    case (_, "ws"), (_, "wss"):
        break
    case (_, "http"):
        components.scheme = "ws"
    case (_, "https"):
        components.scheme = "wss"
    default:
        return nil
    }

    components.path = ""
    components.query = nil
    components.fragment = nil
    return components.url
}
```

## 6. 最小修复路径

如果要快速止血，最小改动是两处：

### 6.1 改 Debug WebSocket scheme

```swift
case .debug:
    return URL(string: "ws://192.168.1.152:9898")!
```

### 6.2 `makeTask()` 改为 throwing guard

```swift
nonisolated func makeTask() throws -> URLSessionWebSocketTask {
    guard url.isWebSocketURL else {
        throw AIChatError.connectionFailed("AI 对话 WebSocket URL 必须使用 ws 或 wss")
    }
    return session.webSocketTask(with: url)
}
```

这两处可以立即避免当前 crash。

但完整修复仍建议包含：

- URL builder 归一化。
- AIBridgeTokenAPI 覆盖 URL 校验。
- 单元测试。
- Production `wss` 安全门槛。

## 7. 测试用例建议

### 7.1 URL scheme 单元测试

目标文件建议：

```text
SupportClientTests/AIChat/AIChatWebSocketURLTests.swift
```

测试示例：

```swift
func testDebugDeepTutorWebSocketURLUsesWSScheme() throws {
    let environment = SupportAppEnvironment.debug
    let url = environment.deepTutorWebSocketURL(token: "abc")

    XCTAssertEqual(url.scheme, "ws")
    XCTAssertEqual(url.path, "/api/v1/ws")
    XCTAssertTrue(url.absoluteString.contains("token=abc"))
}

func testProductionDeepTutorWebSocketURLUsesWSSScheme() throws {
    let environment = SupportAppEnvironment.production
    let url = environment.deepTutorWebSocketURL(token: "abc")

    XCTAssertEqual(url.scheme, "wss")
    XCTAssertEqual(url.path, "/api/v1/ws")
}
```

如果方法改成 `throws`：

```swift
func testInvalidWebSocketSchemeThrowsBeforeCreatingTask() throws {
    let url = URL(string: "http://example.com/api/v1/ws?token=abc")!
    let connection = AIChatWebSocketConnection(url: url, session: .shared)

    XCTAssertThrowsError(try connection.makeTask())
}
```

### 7.2 AIBridgeTokenAPI 覆盖 URL 测试

```swift
func testBridgeTokenWSURLNormalizesHTTPToWSInDebug() {
    let url = AIBridgeTokenAPI.webSocketBaseURLForTest(
        from: "http://192.168.1.152:9898/api/v1/ws?token=abc",
        environment: .debug
    )

    XCTAssertEqual(url?.scheme, "ws")
    XCTAssertEqual(url?.host, "192.168.1.152")
    XCTAssertEqual(url?.port, 9898)
    XCTAssertEqual(url?.path, "")
}

func testBridgeTokenWSURLRejectsHTTPInProduction() {
    let url = AIBridgeTokenAPI.webSocketBaseURLForTest(
        from: "http://example.com/api/v1/ws",
        environment: .production
    )

    XCTAssertNil(url)
}
```

## 8. 验收标准

| 编号 | 验收项 | 标准 |
| --- | --- | --- |
| AC1 | Debug 连接 URL | 日志显示 `ws://192.168.1.152:9898/api/v1/ws?token=<redacted>` |
| AC2 | Production 连接 URL | 只能生成 `wss://.../api/v1/ws?token=<redacted>` |
| AC3 | 非法 scheme | `http://...` 不会进入 `webSocketTask(with:)`，而是返回 `AIChatError.connectionFailed` |
| AC4 | 崩溃消失 | 不再出现 `WebSocket tasks can only be created with ws or wss schemes` |
| AC5 | token 脱敏 | 日志中不出现真实 token |
| AC6 | Bridge override | SparkService 返回 `deeptutor_ws_url` 时必须校验 scheme |
| AC7 | 回退 access token | Debug 回退 access token 时仍使用 `ws://` URL |
| AC8 | 测试覆盖 | 新增 URL scheme、makeTask guard、Bridge override 测试 |

## 8.1 DeepTutorSerevr `ws://` 正确连接方式

### 8.1.0 `deeptutor restart` 启动脚本结论

用户本地启动输出：

```text
deeptutor restart
正在检查工作目录 /Users/hua/Documents/project/DeepTutor/DeepTutorSerevr 的 DeepTutor 配置端口
后端        端口 9898
前端        端口 9896

后端         http://localhost:9898
前端         http://localhost:9896

backend INFO: Uvicorn running on http://0.0.0.0:9898
frontend ▲ Next.js 16.2.3
frontend - Local:   http://localhost:9896
```

结论：

- 启动脚本没有单独打印 `ws://` 配置。
- 启动脚本只打印 HTTP 后端地址和 Web 前端地址。
- WebSocket 不是另一个独立服务，也不是另一个端口。
- DeepTutorSerevr 的 WebSocket 由同一个 FastAPI / uvicorn 后端端口提供。
- 当前本机后端端口是 `9898`，所以 iOS Debug 应连接 `ws://192.168.1.152:9898/api/v1/ws?token=...`。
- 当前前端端口是 `9896`，它是 Next.js Web UI，不是 iOS 原生客户端首选连接目标。

启动命令中的后端进程：

```text
python -m uvicorn deeptutor.api.main:app \
  --host 0.0.0.0 \
  --port 9898 \
  --log-level info \
  --no-access-log \
  --ws-max-size 43341141
```

这说明：

| 配置项 | 值 | 对 iOS 的含义 |
| --- | --- | --- |
| `--host` | `0.0.0.0` | 后端监听所有网卡，iPhone 真机可通过 Mac 局域网 IP 访问 |
| `--port` | `9898` | iOS WebSocket 也使用这个端口 |
| `--ws-max-size` | `43341141` | uvicorn 已启用 WebSocket，并配置了 frame size |
| 前端端口 | `9896` | 只给浏览器访问 Web UI，不作为 iOS WebSocket 目标 |

因此启动脚本中的：

```text
后端 http://localhost:9898
```

在 iOS 真机上应转换为：

```text
HTTP API Base:
http://192.168.1.152:9898

WebSocket URL:
ws://192.168.1.152:9898/api/v1/ws?token=<token>
```

不是：

```text
http://192.168.1.152:9898/api/v1/ws?token=<token>
```

也不是：

```text
ws://192.168.1.152:9896/api/v1/ws?token=<token>
```

### 8.1.1 服务端真实 WebSocket 入口

DeepTutorSerevr 工程根目录：

```text
/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr
```

服务端 WebSocket 入口代码：

```text
/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/api/routers/unified_ws.py
```

入口定义：

```python
@router.websocket("/ws")
async def unified_websocket(ws: WebSocket) -> None:
    ...
```

路由挂载位置：

```text
/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/api/main.py
```

挂载代码：

```python
app.include_router(unified_ws.router, prefix="/api/v1", tags=["unified-ws"])
```

因此最终 WebSocket path 是：

```text
/api/v1/ws
```

不是：

```text
/ws
/api/ws
/api/v1/chat/ws
```

### 8.1.2 DeepTutorSerevr 端口规则

DeepTutorSerevr 后端由 uvicorn 启动，监听：

```text
0.0.0.0:<backend_port>
```

代码位置：

```text
/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/api/run_server.py
/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/runtime/launcher.py
```

默认端口语义：

| 服务 | 默认端口 | 用途 | iOS 是否应该直连 |
| --- | --- | --- | --- |
| Backend / FastAPI | `8001` | `/api/v1/ws`、`/api/v1/sessions`、API 路由 | 是 |
| Frontend / Next.js | `3782` | Web 页面 | 否，iOS 首选直连 Backend |

如果你的本机实际启动端口是 `9898`，则说明当前 DeepTutorSerevr 后端已经被配置或代理到：

```text
http://192.168.1.152:9898
```

对应 WebSocket 应该写成：

```text
ws://192.168.1.152:9898/api/v1/ws
```

### 8.1.3 iOS Simulator 与真机连接差异

| 运行环境 | DeepTutorSerevr 在哪里 | HTTP API Base | WebSocket URL |
| --- | --- | --- | --- |
| iOS Simulator + Mac 本机后端默认端口 | 同一台 Mac | `http://127.0.0.1:8001` 或 `http://localhost:8001` | `ws://127.0.0.1:8001/api/v1/ws?token=...` |
| iOS Simulator + Mac 本机后端自定义端口 | 同一台 Mac | `http://127.0.0.1:9898` | `ws://127.0.0.1:9898/api/v1/ws?token=...` |
| iPhone 真机 + Mac 局域网后端默认端口 | Mac 局域网 IP | `http://192.168.1.152:8001` | `ws://192.168.1.152:8001/api/v1/ws?token=...` |
| iPhone 真机 + Mac 局域网后端自定义端口 | Mac 局域网 IP | `http://192.168.1.152:9898` | `ws://192.168.1.152:9898/api/v1/ws?token=...` |
| Production | 公网 HTTPS 域名 | `https://deeptutor.example.com` | `wss://deeptutor.example.com/api/v1/ws?token=...` |

关键规则：

- `http://` 对应 WebSocket 时必须转为 `ws://`。
- `https://` 对应 WebSocket 时必须转为 `wss://`。
- iPhone 真机不能用 `localhost` 访问 Mac 上的服务，因为真机里的 `localhost` 指的是 iPhone 自己。
- 真机必须使用 Mac 的局域网 IP，例如 `192.168.1.152`。
- iOS 首选连接 DeepTutorSerevr 后端端口，不连接 Next.js 前端端口。

### 8.1.4 DeepTutorSerevr WebSocket 鉴权方式

代码位置：

```text
/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/api/routers/auth.py
```

当前 WebSocket 鉴权逻辑：

```python
token = ws.query_params.get("token") or ws.cookies.get("dt_token")
payload = decode_token(token) if token else None
if not payload:
    await ws.close(code=4001)
    return ws_auth_failed
```

因此 iOS 当前正确连接格式是：

```text
ws://<deeptutor-host>:<backend-port>/api/v1/ws?token=<ai_bridge_token>
```

Debug 回退 Spark access token 时：

```text
ws://192.168.1.152:9898/api/v1/ws?token=<spark_access_token>
```

正式环境：

```text
wss://<deeptutor-production-host>/api/v1/ws?token=<ai_bridge_token>
```

说明：

- iOS 不应该依赖 `dt_token` cookie。
- iOS 当前使用 query `token` 是符合 DeepTutorSerevr 现有实现的。
- token 只能在 URLComponents 中编码，日志必须脱敏。
- 如果 `AUTH_ENABLED=false`，服务端允许无 token，但该模式只能用于本地开发，不能进入 Release。

## 8.2 SwiftUI 与 DeepTutorSerevr WebSocket 通讯配置方案

### 8.2.1 `SupportAppEnvironment` 正确配置方式

推荐把 HTTP Base 和 WebSocket Base 分开表达：

```swift
var deepTutorBaseURL: URL {
    switch self {
    case .debug:
        return URL(string: "http://192.168.1.152:9898")!
    case .staging, .production:
        return URL(string: "https://www.dreamhua.top")!
    }
}

var deepTutorWebSocketBaseURL: URL {
    switch self {
    case .debug:
        return URL(string: "ws://192.168.1.152:9898")!
    case .staging, .production:
        return URL(string: "wss://www.dreamhua.top")!
    }
}
```

更推荐用 HTTP Base 自动派生 WebSocket Base，减少手写错 scheme 的概率：

```swift
var deepTutorBaseURL: URL {
    switch self {
    case .debug:
        return URL(string: "http://192.168.1.152:9898")!
    case .staging, .production:
        return URL(string: "https://www.dreamhua.top")!
    }
}

var deepTutorWebSocketBaseURL: URL {
    deepTutorBaseURL.websocketBaseURL()
}
```

配套转换：

```swift
extension URL {
    func websocketBaseURL() -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }

        switch components.scheme?.lowercased() {
        case "http":
            components.scheme = "ws"
        case "https":
            components.scheme = "wss"
        case "ws", "wss":
            break
        default:
            break
        }

        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url ?? self
    }
}
```

### 8.2.2 最终 URL 构造方式

推荐让 `SupportAppEnvironment` 统一生成最终 URL：

```swift
func deepTutorWebSocketURL(token: String) throws -> URL {
    var components = URLComponents(
        url: deepTutorWebSocketBaseURL.appending(path: "api/v1/ws"),
        resolvingAgainstBaseURL: false
    )!
    components.queryItems = [URLQueryItem(name: "token", value: token)]

    guard let url = components.url else {
        throw AIChatError.connectionFailed("无法生成 AI 对话 WebSocket URL")
    }

    guard url.isWebSocketURL else {
        throw AIChatError.connectionFailed("AI 对话 WebSocket URL 必须使用 ws 或 wss")
    }

    return url
}
```

配套校验：

```swift
extension URL {
    var isWebSocketURL: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "ws" || scheme == "wss"
    }
}
```

### 8.2.3 SwiftUI 调用链

目标调用链：

```text
AIChatDebugEntryView / AIChatRootView
    ↓
AIChatDebugViewModel.connect()
    ↓
AIChatRepository.connect()
    ↓
resolveBridgeToken()
    ↓
SupportAppEnvironment.deepTutorWebSocketURL(token:)
    ↓
AIChatWebSocketClient.connect(url:)
    ↓
AIChatWebSocketConnection.makeTask()
    ↓
URLSession.webSocketTask(with: wsURL)
```

其中必须保证：

```text
传入 URLSession.webSocketTask(with:) 的 URL.scheme 只能是 ws 或 wss
```

### 8.2.4 SwiftUI 发送消息示例

连接成功后，SwiftUI 侧发送的第一条最小消息：

```swift
let payload = AIStartTurnPayload(
    type: "start_turn",
    content: "你好",
    sessionID: nil,
    language: "zh"
)

try await repository.startTurn(payload)
```

实际 WebSocket frame：

```json
{
  "type": "start_turn",
  "content": "你好",
  "session_id": null,
  "language": "zh"
}
```

心跳 frame：

```json
{
  "type": "ping"
}
```

恢复 frame：

```json
{
  "type": "resume_from",
  "turn_id": "turn-id",
  "seq": 12
}
```

取消 frame：

```json
{
  "type": "cancel_turn",
  "turn_id": "turn-id"
}
```

### 8.2.5 DeepTutorSerevr 返回事件示例

服务端会返回 JSON text frame。

`pong`：

```json
{
  "type": "pong"
}
```

`content`：

```json
{
  "type": "content",
  "source": "chat",
  "stage": "",
  "content": "你好，我可以帮你。",
  "metadata": {},
  "session_id": "session-id",
  "turn_id": "turn-id",
  "seq": 1,
  "timestamp": 1785400000
}
```

`done`：

```json
{
  "type": "done",
  "source": "chat",
  "stage": "",
  "content": "",
  "metadata": {},
  "session_id": "session-id",
  "turn_id": "turn-id",
  "seq": 2,
  "timestamp": 1785400001
}
```

iOS 处理规则：

- `pong` 只刷新连接活性，不进入消息列表。
- `content` 追加到 assistant draft。
- `done` 将 assistant draft 落定为最终消息。
- `error` 如果是 terminal error，结束当前 turn 并展示重试。

### 8.2.6 本地联调检查清单

| 检查项 | 正确值 |
| --- | --- |
| DeepTutorSerevr 后端监听地址 | `0.0.0.0:9898` 或 `0.0.0.0:8001` |
| iPhone 与 Mac 是否同一局域网 | 是 |
| iPhone 访问 Mac IP | `192.168.1.152` |
| HTTP API Base | `http://192.168.1.152:9898` |
| WebSocket URL | `ws://192.168.1.152:9898/api/v1/ws?token=<redacted>` |
| URL scheme | `ws` |
| URL path | `/api/v1/ws` |
| token 参数 | `token=<ai_bridge_token>` 或 Debug fallback access token |
| 日志 | token 必须显示 `<redacted>` |

### 8.2.7 常见错误对照

| 错误配置 | 结果 | 正确配置 |
| --- | --- | --- |
| `http://192.168.1.152:9898/api/v1/ws` | App 直接崩溃 | `ws://192.168.1.152:9898/api/v1/ws` |
| `https://host/api/v1/ws` | App 直接崩溃 | `wss://host/api/v1/ws` |
| `ws://localhost:9898` 真机 | 连接 iPhone 自己，失败 | `ws://Mac局域网IP:9898` |
| `ws://192.168.1.152:3782/api/v1/ws` | 可能连到 Next 前端，不是后端 | `ws://192.168.1.152:<backend_port>/api/v1/ws` |
| 缺少 `/api/v1` | 404 或握手失败 | `/api/v1/ws` |
| 缺少 `token` 且 AUTH_ENABLED=true | 服务端关闭，code 4001 | `?token=<token>` |

### 8.2.8 本工单新增验收项

| 编号 | 验收项 | 标准 |
| --- | --- | --- |
| AC9 | DeepTutorSerevr path | iOS 最终连接 path 必须是 `/api/v1/ws` |
| AC10 | 后端端口 | iOS Debug 连接 DeepTutorSerevr backend port，不连接 Web frontend port |
| AC11 | 真机局域网 | 真机 Debug 使用 Mac 局域网 IP，不使用 `localhost` |
| AC12 | 鉴权 query | AUTH_ENABLED=true 时 URL 必须带 `?token=` |
| AC13 | SwiftUI 通讯 | 连接成功后可发送 `ping` 并收到 `pong`，可发送最小 `start_turn` 并收到 `content/done` |

## 9. 修复优先级

建议按以下顺序处理：

1. 修正 `SupportAppEnvironment.deepTutorWebSocketBaseURL.debug` 为 `ws://192.168.1.152:9898`。
2. 给 `AIChatWebSocketConnection.makeTask()` 增加 `ws/wss` 前置校验，并改为 `throws`。
3. 调整 `AIChatWebSocketClient.openSocket()` 消费 throwing `makeTask()`。
4. 增加 URL scheme 归一化工具，避免 HTTP base URL 被误用。
5. 校验 `AIBridgeTokenAPI.webSocketBaseURL(from:)` 的返回值。
6. 补单元测试。
7. Production 增加 `wss` 与 host 白名单门槛。

## 10. 结论

本次崩溃不是后端连接失败，也不是 token 本身失效，而是 iOS WebSocket URL scheme 配置错误：

```text
错误：http://192.168.1.152:9898/api/v1/ws
正确：ws://192.168.1.152:9898/api/v1/ws
```

同时需要在 `makeTask()` 前做强校验，因为 `URLSession.webSocketTask(with:)` 对非法 scheme 抛出的是不可由 Swift `catch` 接住的 `NSException`。只要非法 URL 进入该 API，App 就会直接崩溃。
