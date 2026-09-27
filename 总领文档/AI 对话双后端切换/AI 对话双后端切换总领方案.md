# SupportClient｜AI 对话双后端切换总领方案

## 1. 文档定位

本文档用于梳理 `SupportClient` 在 AI 对话能力上新增“`DeepTutorSerevr` 运行 / iOS 本地运行”双后端切换时，需要建立的核心大模块。

当前阶段只做总领与模块拆分，不直接实现业务代码。结论以当前 `SupportClient` 与 `DeepTutorSerevr` 真实代码为准：

- iOS 现有 AI 对话主链路位于 `SupportClient/SupportClient/Projects/Features/AIChat/`，已通过 `AIChatAssembly` + `AIChatRepository` 接入 `DeepTutorSerevr`。
- 当前设置入口位于 `SupportClient/SupportClient/Projects/Features/Settings/Presentation/SettingsView.swift` 和 `SupportClient/SupportClient/Projects/Features/AISettings/Presentation/Root/AISettingsView.swift`。
- `DeepTutorSerevr` 当前会话运行时职责集中在 `deeptutor/services/session/`，并通过统一会话管理承接 session、turn、流式事件、取消、恢复与列表操作。
- 更细的 Web 对齐、业务流程、核心代码骨架见 [技术细节文档.md](./技术细节文档.md)。

## 2. 目标与硬约束

### 2.1 本次目标

- 在设置中增加开关，支持用户切换：
  - `DeepTutorSerevr 运行`
  - `iOS 本地运行`
- iOS 本地运行时，AI 对话由客户端直接调用 AI API，不再依赖 `DeepTutorSerevr` 的对话编排链路。
- 会话消息 UI、消息列表、对话页布局、会话列表交互尽量保持不变。
- 提交消息时，由运行模式决定走本地后端还是 `DeepTutorSerevr` 后端。
- `local` 模式下新建会话、发送消息、恢复续聊都只允许在本地缓存内完成，不能把会话相关请求发送到 `DeepTutorSerevr`。

### 2.2 当前明确约束

- 先不考虑本地持久化与多端同步。
- 本地模式只要求缓存与本地运行，不要求把 session 正式写入数据库。
- iOS 端 AI 后端基础能力要尽量对齐 `DeepTutorSerevr` 当前对话契约。
- 不影响 `DeepTutorSerevr` 现有端口与运行方式；服务端模式仍保持原链路可用。
- `local` 模式与 `DeepTutorSerevr` 的边界不是“少量依赖服务端 session”，而是“会话、消息、恢复全部本地闭环”。
- `local` 模式的模型消费必须接入项目内现有分场景统一模型消费链，不能在 `AIChat` 内再单独维护 chat 模型配置。

## 3. 当前代码事实

### 3.1 已有 iOS AI 对话入口

- `AIChatAssembly.swift` 负责装配 `AIChatRepository`、`AIChatViewModel`、`AIChatDebugViewModel`。
- `AIChatRepository.swift` 当前固定依赖：
  - `DeepTutorTokenAPI`
  - `DeepTutorSessionAPI`
  - `DeepTutorLLMOptionsAPI`
  - `AIChatWebSocketClient`
- `AIChatViewModel` + `AIChatEventReducer` 已经形成稳定的事件驱动 UI 渲染链。

### 3.2 已有 AI 设置与本地 AI 配置基础

- `AIConfigCenter.swift` 已提供本地快照、远端 patch、运行时缓存与 reload 能力。
- `AISettingsViewModel.swift` 已是 AI 设置统一状态入口，适合承接新增运行模式开关。
- `AIConfigModels.swift` 已有：
  - `AIConfigSource`
  - `AIProviderAdapter`
  - `localGGUF`
  - `runtimeOverride`
- 现有工程已经具备“本地模型 / 在线模型”共存的基础语义，但尚未把它接入 `AIChat` 的双后端选择。

### 3.3 已有服务端对齐基线

- `DeepTutorSerevr` 已有统一对话与会话运行时：
  - `deeptutor/services/session/unified_session_manager.py`
  - `deeptutor/services/session/turn_runtime.py`
  - `deeptutor/services/session/protocol.py`
- 这意味着 iOS 本地运行并不是重做一套 UI，而是要在客户端补一套“对齐同一会话语义”的本地运行时。

## 4. 大模块拆分结论

下面是本工程第一阶段必须明确的核心大模块。它们共同组成“AI 对话双后端切换”方案。

### 模块 1：运行模式设置模块

职责：

- 在设置中新增 AI 对话运行模式开关。
- 记录当前模式是 `server` 还是 `local`。
- 决定对话页提交时选择哪条链路。

覆盖范围：

- `SettingsView`
- `AISettingsView`
- `AISettingsViewModel`
- `AISettingsSnapshot` / `AIConfigCenter`

关键要求：

- 开关必须是账号级或至少当前用户级隔离，不能污染其他账号。
- 切换模式时要明确是否需要断开当前 WebSocket、清空草稿态、提示会话隔离策略。

### 模块 2：AIChat 双后端装配模块

职责：

- 改造 `AIChatAssembly`，从“固定装配 `AIChatRepository`”升级为“按运行模式装配不同 Runtime”。
- 为 `AIChatViewModel` 提供统一协议，不让 UI 感知本地模式或服务端模式差异。

覆盖范围：

- `AIChatAssembly.swift`
- `AppContainer.swift`
- `AssemblyProducts.swift`

关键要求：

- 保持现有 `AIChatEntryView`、`AIChatRootView` 的入口不变。
- 将模式选择收敛在 Composition Root，而不是散落到页面按钮里。

### 模块 3：AIChat 统一仓储协议模块

职责：

- 抽象当前 `AIChatRepositoryProtocol` 为真正的双实现协议。
- 服务端模式继续使用现有 `DeepTutorSerevr` 仓储。
- 本地模式新增一套 `LocalAIChatRepository` 或同级运行时实现。

覆盖范围：

- `AIChatRepositoryProtocol`
- `AIChatRepository.swift`
- 新的本地 AI 仓储 / 网关 / 适配器

关键要求：

- 对外暴露的方法签名保持稳定：
  - `connect`
  - `startTurn`
  - `cancelActiveTurn`
  - `regenerate`
  - `submitUserReply`
  - `listSessions`
  - `loadSession`
  - `renameSession`
  - `deleteSession`
- UI 和 ViewModel 不能因为后端切换而改成两套分支。

### 模块 4：本地会话与 Turn 运行时模块

职责：

- 在 iOS 内建立最小可用的 session / turn / message / event 运行时。
- 本地模式下只做内存缓存，不做正式持久化与同步。
- 保持会话列表、当前对话、活动 turn、取消、重生成等基础语义可用。
- 新建会话、发送消息、恢复续聊都在本地缓存闭环完成，不调用 `DeepTutorSerevr` 会话接口。

覆盖范围：

- `AIChatState`
- `AIChatMessage`
- `AIChatSession`
- `AIChatResumeStore`
- 新增本地 session store / turn runtime

关键要求：

- 本地模式与服务端模式的 session 数据结构尽量同名。
- 会话列表、重命名、删除在本地模式下也要能工作，但其结果只存在内存缓存。
- 账号切换时必须清空当前账号的本地 AI 会话缓存。
- 本地模式恢复只允许从本地缓存恢复，不能走服务端 `resume_from` 或 session detail 读取。

### 模块 5：本地流式事件适配模块

职责：

- 把本地直接调用 AI API 的流式响应，适配成当前 `AIStreamEvent` 驱动链能消费的事件。
- 保证 `AIChatEventReducer`、卡片编排和消息 UI 继续可用。

覆盖范围：

- `AIStreamEvent`
- `AIChatEventReducer`
- `AIChatCardComposer`
- 新增本地流式事件转换器

关键要求：

- 本地模式至少先对齐这些核心事件：
  - `session`
  - `content`
  - `thinking`
  - `progress`
  - `error`
  - `done`
- `tool_call`、`tool_result`、`sources`、`wait_for_input` 等复杂事件可以分阶段补齐，但文档中必须先冻结语义。

### 模块 6：模型选择与请求提交模块

职责：

- 本地模式下由 iOS 直接根据 `AIConfigCenter` 当前配置解析 endpoint、model、apiKey。
- 服务端模式下仍按当前 `DeepTutorTokenAPI + DeepTutorSessionAPI + WebSocket` 提交。
- 同一条发送入口，根据模式走不同提交器。

覆盖范围：

- `AIConfigCenter`
- `ScenarioPolicyResolver`
- `AISettingsSnapshot`
- 本地 AI 请求客户端

关键要求：

- 本地模式优先复用现有 AI 设置数据，不新建平行配置中心。
- `llm_selection`、默认模型、场景模型偏好等语义，需要定义“哪些继续生效、哪些只在服务端模式生效”。
- chat 场景模型解析必须继续走 `AIConfigCenter.resolve(for: .chat)` / `ScenarioPolicyResolver`，`local` 模式只替换执行器，不替换模型消费链。

### 模块 7：会话列表与历史兼容模块

职责：

- 保证会话列表、加载历史、重命名、删除等交互在两种模式下都能维持相同 UI 行为。
- 区分“服务端会话”和“本地临时会话”的来源与隔离策略。
- `local` 模式的会话列表和会话详情来源只允许是本地缓存，不允许回退读取 `DeepTutorSerevr`。

覆盖范围：

- `AIChatViewModel`
- `DeepTutorSessionAPI` 当前消费点
- 新增本地 session list provider

关键要求：

- 模式切换后，不应把服务端会话和本地临时会话错误混在一起。
- 需要定义：
  - 切到本地模式时是否展示独立本地会话列表
  - 切回服务端模式时是否恢复服务端会话列表
  - 正在进行中的 turn 是否允许跨模式延续

### 模块 8：账号、生命周期与缓存清理模块

职责：

- 管理登录、登出、账号切换、进入后台、重新进入前台时的 AI 对话状态。
- 保证本地缓存、服务端连接和运行模式状态不会互相污染。

覆盖范围：

- `AppLifecycleCoordinator`
- `AppSessionStore`
- `AccountSessionRuntime`
- `AIChatAssembly.disconnectAll`

关键要求：

- 登出或切换账号时：
  - 服务端模式要断开 WebSocket
  - 本地模式要清空本地会话缓存与 active turn
- 不能因为 AI 对话本地化改动，影响 `DeepTutorSerevr` 现有连接端口或原登录态链路。

### 模块 9：调试、诊断与验收模块

职责：

- 让开发阶段可以明确知道当前对话走的是哪条链路。
- 保留足够日志，帮助排查是本地 API、模型配置、流式解析，还是服务端 WebSocket 出错。

覆盖范围：

- `AIChatDiagnostics`
- `AIChatSessionLogger`
- `AIChatDebugViewModel`
- DEBUG 专用入口

关键要求：

- 至少显示：
  - 当前运行模式
  - 当前 endpoint / provider / model
  - 当前 session 来源（local/server）
  - 最近一次 turn 的启动、取消、完成、失败原因

## 5. 建议的阶段拆分

### P0：协议冻结与开关落位

- 定义运行模式枚举、设置入口和快照字段。
- 冻结本地模式需要兼容的最小事件集。
- 约束哪些能力首期必须对齐，哪些允许占位。
- 详细方案见 [P0 方案与协议冻结.md](./P0%20方案与协议冻结.md)

### P1：最小双链路连通

- 服务端模式保持现状。
- 本地模式打通：
  - 新建会话
  - 发送消息
  - 流式文本
  - 停止生成
  - 本地会话列表
- 详细方案见 [P1 最小双链路连通.md](./P1%20最小双链路连通.md)

### P2：会话语义补齐

- 重生成
- 历史会话加载
- 重命名 / 删除
- 账号切换清理
- 模式切换隔离
- 详细方案见 [P2 会话语义补齐.md](./P2%20会话语义补齐.md)

### P3：复杂事件与产品化

- `wait_for_input`
- `tool_call` / `tool_result`
- `sources`
- 更完整的错误映射、重试、诊断与灰度开关
- 详细方案见 [P3 复杂事件与产品化.md](./P3%20复杂事件与产品化.md)

## 6. 当前最重要的结论

这次工程的真正核心不是“再写一个本地 AI 请求器”，而是建立一层稳定的双后端运行时边界，让：

- 设置负责决定模式；
- 装配层负责选择实现；
- `AIChatViewModel` 和现有 UI 继续只面对统一协议；
- 本地模式在不影响 `DeepTutorSerevr` 端口与现有链路的前提下，补齐最小会话运行时。

如果后续进入实现阶段，建议先从下面 4 个点动手，而不是直接改页面：

1. `AISettingsSnapshot / AIConfigCenter` 增加运行模式字段。
2. `AIChatAssembly` 改成按模式装配仓储。
3. 定义 `LocalAIChatRepository` 的协议与内存 session store。
4. 定义“本地流式响应 -> AIStreamEvent”的事件转换层。
