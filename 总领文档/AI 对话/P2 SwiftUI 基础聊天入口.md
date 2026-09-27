# P2 SwiftUI 基础聊天入口

> 本文档只补充 P2 阶段的 iOS SwiftUI 基础聊天入口方案，不实现任何 Swift、Python、TypeScript 或配置代码。

## 1. 阶段定位

P2 的目标是把 P1 已验证或待验证的 WebSocket 最小连通能力，沉淀为用户可进入、可输入、可看到基础消息流、可感知错误和状态的 SwiftUI 原生聊天入口。

P2 不是完整 AI 对话产品化阶段。P2 只负责“基础聊天入口”：

```text
登录后的 SupportClient
    ↓
底部 Tab 或明确入口进入 AI 对话
    ↓
展示空态 / 历史入口 / 新对话按钮
    ↓
用户输入文本
    ↓
发送 start_turn
    ↓
展示 user message + assistant draft
    ↓
收到 done 后沉淀为 assistant message
    ↓
失败时展示错误并允许重试
```

P2 的关键价值：

- 从 P1 调试连通转为真实用户可以理解的基础聊天体验。
- 固定 SwiftUI 页面树、ViewModel 状态消费和组件职责。
- 明确正式入口与 Debug 连通测试入口的边界。
- 给 P3 事件完整渲染预留位置，但不在 P2 过度实现工具、来源和 AskUser 复杂交互。
- 在文档内完成 P0/P1 偏差检查，避免旧文档结论滞后于当前代码。

## 2. P2 结论

| 项目 | P2 冻结结论 |
| --- | --- |
| 当前平台 | 仅 iOS SwiftUI |
| 正式入口 | 登录后的主 Tab 中进入 `AIChatEntryView` |
| 调试入口 | Settings 的 `#if DEBUG` 开发者区保留 `AIChatDebugEntryView` |
| 页面根 | `AIChatRootView` |
| 状态源 | `AIChatViewModel.state` |
| 输入组件 | `AIChatComposer` |
| 消息列表 | `AIChatMessageList` + `AIChatMessageBubble` |
| 空态 | `AIChatEmptyStateView` |
| 错误态 | `AIChatErrorBanner` |
| 会话列表 | P2 可以保留入口，但完整历史/恢复验收后置到 P4/P5 |
| 工具/来源/AskUser | 组件可存在，P2 只做基础占位或轻量展示，完整渲染后置到 P3 |
| 鉴权 | 继续沿用 P1/P4 边界，P2 不重新定义登录体系 |
| 业务代码 | 本文档不改任何业务代码 |

P2 的完成标准不是“所有聊天高级能力都完成”，而是：

- 用户能找到入口。
- 用户能发出一条文本。
- 用户能看到自己发送的消息。
- 用户能看到 AI 流式回复的基础文本。
- 用户能看到连接中、失败、空态、生成中、完成状态。
- 用户能停止正在生成的基础 turn。
- Debug 连通入口和正式聊天入口不混淆。

## 3. 上游依据

| 来源 | 路径 | P2 继承内容 |
| --- | --- | --- |
| P0 主方案 | `/Users/hua/Documents/project/DeepTutor/SupportClient/总领文档/AI 对话/P0 方案与协议冻结/P0 方案与协议冻结.md` | 服务边界、协议事实源、SwiftUI 原生实现、不使用 WebView |
| P0 技术细节 | `/Users/hua/Documents/project/DeepTutor/SupportClient/总领文档/AI 对话/P0 方案与协议冻结/技术细节文档.md` | iOS 分层架构、AIChat 目标目录、DeepTutorSerevr 地址配置、Web 参考边界 |
| P1 文档 | `/Users/hua/Documents/project/DeepTutor/SupportClient/总领文档/AI 对话/P1 iOS 最小连通.md` | WebSocket 最小连通、DTO、Bridge Token、状态机、文件级补齐清单 |
| iOS App 入口 | `/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/App/Sources/App/AppCoordinatorView.swift` | 当前主 Tab 已挂载 `AIChatEntryView` |
| iOS Settings Debug 入口 | `/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/Settings/Presentation/SettingsView.swift` | 当前 `#if DEBUG` 下已有 `AIChatDebugEntryView` 连通测试入口 |
| AIChat Presentation | `/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation` | 已有入口、根页面、消息列表、输入栏、空态、卡片组件 |
| AIChat Application | `/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Application` | 已有 `AIChatViewModel`、UseCase、Reducer |
| AIChat Domain | `/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Domain` | 已有消息、会话、状态、事件、错误模型 |
| AIChat Infrastructure | `/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure` | 已有 WebSocket、Bridge Token、DTO、Repository、Session API |

## 4. P0/P1 偏差检查

本节专门记录 P2 写作前对 P0、P1 和当前 iOS 代码的偏差检查。结论：主架构方向一致，但部分旧文档事实已经被当前代码推进，需要在 P2 中以当前代码为准。

### 4.1 P0 与当前代码偏差

| 编号 | P0 内容 | 当前代码事实 | 偏差结论 | P2 处理 |
| --- | --- | --- | --- | --- |
| P2-D0-1 | P0 技术细节写 SupportClient “尚无 AI 对话 Feature” | 当前已有 `Projects/Features/AIChat` 四层目录和完整文件 | P0 技术细节已过时 | P2 以当前 AIChat 目录为事实 |
| P2-D0-2 | P0 技术细节写 `SupportAppEnvironment` 当前只有 SparkService `apiBaseURL` | 当前已出现 `deepTutorBaseURL`、`deepTutorWebSocketBaseURL`、`deepTutorWebSocketURL(token:)` | P0 技术细节已过时 | P2 标记 DeepTutor 地址已存在，重点转为验收 |
| P2-D0-3 | P0 主方案强调 P1/P2 起新增 SwiftUI 入口 | 当前 `AppCoordinatorView` 已挂载 `AIChatEntryView` Tab | 代码推进快于文档 | P2 不再设计新入口，而是规范现有入口 |
| P2-D0-4 | P0 冻结 AI Bridge Token 正式方向，P1 可开发过渡 | 当前已有 `AIBridgeTokenAPI` 和 Debug fallback | 方向一致，但需要后端确认 | P2 不重新定义鉴权，继续引用 P1/P4 |
| P2-D0-5 | P0 说 Web 只作为参考，不使用 WebView | 当前 SwiftUI 原生组件已存在 | 一致 | P2 继续保持 SwiftUI 原生方案 |

### 4.2 P1 与当前代码偏差

| 编号 | P1 内容 | 当前代码事实 | 偏差结论 | P2 处理 |
| --- | --- | --- | --- | --- |
| P2-D1-1 | P1 定位为“允许开发期调试入口或隐藏入口，不做正式产品化聊天 UI” | 当前既有 Debug 入口，也有正式 Tab 入口 | P1 范围和代码现状出现阶段重叠 | P2 负责正式基础入口，P1 继续只代表连通测试 |
| P2-D1-2 | P1 建议目标文件结构中出现 `DeepTutorWebSocketClient.swift` | 当前真实文件名是 `AIChatWebSocketClient.swift` | 文档命名偏差 | P2 文件结构使用真实文件名 |
| P2-D1-3 | P1 写 P1 不做会话列表 | 当前 `AIChatRootView` 已有会话列表 sheet 和 `DeepTutorSessionAPI` | 代码超前 | P2 允许入口存在，但完整历史验收后置 |
| P2-D1-4 | P1 写 P1 不做 AskUser/工具/来源完整渲染 | 当前已有 `AIAskUserCard`、`AIToolTraceCard`、`AISourceReferencesView` | 代码超前 | P2 只说明组件存在，不把完整渲染列为 P2 完成条件 |
| P2-D1-5 | P1 章节升级后部分子标题仍是 `### 8.1/9.1/10.1/11.1` | P1 主标题已变成 `## 12/13/14/15` | 文档编号偏差 | 建议后续单独整理 P1 编号，不影响 P2 内容 |
| P2-D1-6 | P1 只要求最小事件展示 | 当前 `AIChatEventReducer` 已开始处理 content、session、tool、source、wait_for_input | 代码超前 | P2 只要求基础 content/done/error 体验，复杂事件归 P3 |

### 4.3 P2 对偏差的处理原则

- P2 以当前 iOS 代码事实为准，不回退已有入口和已有组件。
- P2 不扩大后端职责，不改变 P0 服务边界。
- P2 不把 P3/P4/P5 的已存在代码当作 P2 必须验收。
- P2 文档只写当前 iOS SwiftUI，不展开其他客户端实现。
- P1 的编号偏差属于文档整理问题，建议后续维护 P1 时修正，但不阻塞 P2。

## 5. P2 不做范围

| 不做项 | 原因 | 后续阶段 |
| --- | --- | --- |
| 完整 Markdown / 公式 / 代码块高保真渲染 | P2 只要求基础文本可读 | P3/P5 |
| 工具调用 Trace 完整交互 | 需要事件矩阵和折叠/展开规范 | P3 |
| 来源引用完整卡片 | 需要来源字段、打开策略、可信展示规则 | P3 |
| AskUser 多问题完整产品体验 | 需要等待输入事件和表单规范 | P3 |
| 会话历史完整恢复 | 需要账号隔离、resume_from、lastSeq 持久化验收 | P4 |
| 正式 AI Bridge Token 闭环 | 需要 SparkService 与 DeepTutorSerevr 双端确认 | P4 |
| 附件、图片、文件 | 需要 OSS 与 DeepTutor 附件归属冻结 | P5 |
| 高级动效和视觉产品化 | P2 先保证基础可用 | P5 |

## 6. 当前代码事实

### 6.1 正式入口

当前正式入口在：

```text
/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/App/Sources/App/AppCoordinatorView.swift
```

当前行为：

```text
TabView
├── 首页
├── AI 对话
├── 第二相机
└── 设置
```

AI 对话 Tab 当前挂载：

```text
AIChatEntryView(
    accountID: session.accountID,
    makeViewModel: dependencies.makeAIChatViewModel
)
```

P2 结论：

- P2 不再新增入口。
- P2 以当前 Tab 入口作为基础聊天入口。
- P2 需要确认这个 Tab 是否在未完成正式鉴权时允许进入。
- 如果正式鉴权尚未稳定，P2 建议通过 feature flag 或 Debug-only 开关控制正式 Tab 曝光，但本文档不修改代码。

### 6.2 Debug 连通入口

当前 Debug 入口在：

```text
/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/Settings/Presentation/SettingsView.swift
```

当前行为：

```text
#if DEBUG
Settings
└── 开发者
    └── AI 对话连通测试
        └── AIChatDebugEntryView
#endif
```

P2 结论：

- Debug 入口继续保留，服务 P1 连通验收。
- 正式 `AIChatEntryView` 服务 P2 基础聊天。
- 两者不能互相替代。
- Debug 入口必须继续只在 Debug 构建可见。

### 6.3 SwiftUI 页面文件

| 文件 | 当前职责 | P2 定位 |
| --- | --- | --- |
| `AIChatEntryView.swift` | 按账号创建 `AIChatRootView` | 正式入口桥接层 |
| `AIChatRootView.swift` | 页面根、错误条、空态/消息列表、AskUser、输入栏、Toolbar、会话列表 Sheet | P2 核心页面 |
| `AIChatComposer.swift` | 输入框、发送、停止按钮 | P2 核心组件 |
| `AIChatMessageList.swift` | ScrollViewReader、消息列表、assistant draft、自动滚动 | P2 核心组件 |
| `AIChatMessageBubble.swift` | user/assistant 气泡、assistant markdown、trace/source 插槽 | P2 基础气泡，复杂插槽后置 |
| `AIChatEmptyStateView.swift` | 空态和连接状态提示 | P2 必须 |
| `AIChatSessionListView.swift` | 会话列表、刷新、选择、重命名、删除 | P2 可见但完整验收后置 |
| `AIAskUserCard.swift` | 等待用户补充输入卡片 | P2 可保留，完整交互后置 |
| `AIToolTraceCard.swift` | 工具 Trace 卡片 | P3 |
| `AISourceReferencesView.swift` | 来源引用展示 | P3 |
| `AIChatDebugEntryView.swift` | P1 连通调试页面 | Debug-only，不属于正式聊天入口 |

### 6.4 ViewModel 与状态

当前 ViewModel：

```text
/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Application/AIChatViewModel.swift
```

P2 使用的关键状态：

| ViewModel/State | P2 用途 |
| --- | --- |
| `state.connectionState` | 驱动空态、发送/停止按钮、错误状态 |
| `state.messages` | 已完成 user/assistant 消息 |
| `state.assistantDraft` | 正在流式生成的 assistant 草稿 |
| `state.userFacingError` | 顶部错误条 |
| `composerText` | 输入框文本 |
| `canSend` | 发送按钮是否可用 |
| `isStreaming` | 是否显示停止按钮 |
| `state.activeSession` | 导航标题和会话上下文 |
| `sessions` | 会话列表 Sheet 数据，P2 不作为核心验收 |

P2 核心调用：

```text
AIChatRootView.task
    ↓
AIChatViewModel.onAppear()
    ↓
connectIfNeeded()

AIChatComposer.onSend
    ↓
AIChatViewModel.sendMessage()
    ↓
StartAIChatTurnUseCase.execute(payload:)
    ↓
AIChatRepository.startTurn(_:)

AIChatRepository.eventHandler
    ↓
AIChatViewModel.handle(event:)
    ↓
AIChatEventReducer.reduce(state:event:)
    ↓
SwiftUI 自动刷新消息列表
```

## 7. P2 目标页面结构

### 7.1 页面树

```text
AIChatEntryView
└── AIChatRootView
    ├── AIChatErrorBanner
    ├── AIChatEmptyStateView
    ├── AIChatMessageList
    │   └── AIChatMessageBubble
    ├── AIAskUserCardView
    ├── AIChatComposer
    ├── Toolbar
    │   ├── 会话列表 Button
    │   └── 新对话 Button
    └── Sheet
        └── AIChatSessionListView
```

P2 必须稳定的主路径：

```text
AIChatEntryView
└── AIChatRootView
    ├── Empty / Message List
    └── Composer
```

P2 可先保留但不完整验收的路径：

```text
Toolbar Session Sheet
AIAskUserCardView
AIToolTraceCard
AISourceReferencesView
```

### 7.2 页面草图

```text
┌──────────────────────────────────────┐
│                 AI 对话              │
│                         [历史] [新建] │
├──────────────────────────────────────┤
│ 错误条，可选：AI 对话服务连接失败      │
├──────────────────────────────────────┤
│                                      │
│      开始一段 AI 对话                 │
│      输入问题，获取智能解答。          │
│                                      │
│ 或：                                  │
│  用户：你好                           │
│                         ┌──────────┐ │
│                         │ 你好     │ │
│                         └──────────┘ │
│  ┌────────────────────────────────┐  │
│  │ AI 正在回复的 assistant draft  │  │
│  │ [小 loading]                    │  │
│  └────────────────────────────────┘  │
│                                      │
├──────────────────────────────────────┤
│ [输入消息……                      ] [↑]│
│ streaming 时：[输入禁用/保留] [停止]  │
└──────────────────────────────────────┘
```

### 7.3 基础状态页面

| 状态 | 页面主体 | Composer | Toolbar | 错误 |
| --- | --- | --- | --- | --- |
| `idle` | 空态提示“输入问题，获取智能解答” | 可输入，发送触发连接 | 可见 | 无 |
| `connecting` | 空态提示“正在连接 AI 服务” | 禁用发送或显示连接中 | 可见 | 无 |
| `ready` | 空态或已有消息 | 可发送 | 可见 | 无 |
| `sending` | 已追加 user message，assistant 等待首包 | 显示停止或禁用发送 | 可见 | 无 |
| `streaming` | assistant draft 持续更新 | 显示停止 | 可见 | 无 |
| `done` | draft 固化成 assistant message | 可继续发送 | 可见 | 无 |
| `failed` | 保留已有消息和输入上下文 | 可重试 | 可见 | 显示错误条 |
| `cancelled` | 保留已收到内容 | 可继续发送 | 可见 | 可选提示 |
| `waitingForUser` | 可显示 AskUser 卡片 | Composer 可按策略禁用或保留 | 可见 | 无 |

P2 最低要求：

- `idle/connecting/ready/sending/streaming/done/failed` 必须有用户可理解的表现。
- `waitingForUser/cancelled` 可轻量展示，不作为 P2 完整验收。

## 8. 入口策略

### 8.1 正式入口策略

当前 `AppCoordinatorView` 已将 AI 对话放入主 Tab。P2 需要冻结以下产品策略：

| 项 | 冻结策略 |
| --- | --- |
| 入口位置 | 登录后主 Tab |
| 标题 | `AI 对话` |
| 图标 | `message.fill` |
| 导航容器 | `NavigationStack` |
| 账号参数 | 使用当前 `UserSession.accountID` |
| ViewModel 创建 | 通过 `dependencies.makeAIChatViewModel(accountID)` |
| 未登录访问 | 不进入主 Tab；登录态由 App 主框架控制 |

如果 P2 开始时正式 AI 服务仍未稳定，推荐策略：

- Debug 构建显示正式 Tab 和 Debug 入口。
- Release 构建是否显示正式 Tab，需要产品确认。
- 如果 Release 先隐藏正式 Tab，不能删除 `AIChat` 模块，只通过 feature flag 或构建开关控制入口。

### 8.2 Debug 入口策略

Debug 入口职责：

| 项 | 内容 |
| --- | --- |
| 页面 | `AIChatDebugEntryView` |
| 所属阶段 | P1 连通测试 |
| 入口 | Settings > 开发者 > AI 对话连通测试 |
| 构建限制 | `#if DEBUG` |
| 展示内容 | endpoint、auth mode、session_id、turn_id、last_seq、raw events |
| 禁止用途 | 不作为正式用户聊天入口 |

P2 中 Debug 入口只用于排障：

- 正式入口发不出消息时，先用 Debug 入口验证 `ping/pong` 和 `start_turn`。
- Debug 入口成功但正式入口失败，优先检查 ViewModel、Reducer、UI 状态。
- Debug 入口失败，优先检查 P1 连接、鉴权、ATS、服务地址。

## 9. 文件结构与职责冻结

### 9.1 App 层

| 文件 | P2 职责 | 不应承担 |
| --- | --- | --- |
| `AppCoordinatorView.swift` | 挂载 AIChat Tab，传入当前账号和 ViewModel 工厂 | 不创建 WebSocket，不拼 JSON |
| `AppContainer.swift` | 组合 `AIChatAssemblyProduct`，注入依赖 | 不持有聊天 UI 状态 |
| `AIChatAssembly.swift` | 创建 Repository、ViewModel、UseCase 依赖 | 不写 UI |
| `AccountSessionRuntime.swift` | 账号切换/登出时断开 AIChat、清理账号态 | 不处理 AI 消息渲染 |
| `SupportAppEnvironment.swift` | 提供 DeepTutor HTTP/WS 地址 | 不获取 token |

### 9.2 Presentation 层

| 文件 | P2 职责 | 后续阶段 |
| --- | --- | --- |
| `AIChatEntryView.swift` | 账号级入口壳 | P2 |
| `AIChatRootView.swift` | 页面容器、状态切换、toolbar、sheet | P2 |
| `AIChatComposer.swift` | 输入、发送、停止 | P2 |
| `AIChatMessageList.swift` | 消息滚动列表、draft 自动滚动 | P2 |
| `AIChatMessageBubble.swift` | 基础 user/assistant 气泡 | P2，复杂 Markdown 后续 |
| `AIChatEmptyStateView.swift` | 空态和连接态提示 | P2 |
| `AIChatSessionListView.swift` | 会话列表入口可见 | P4/P5 完整验收 |
| `AIAskUserCard.swift` | 等待用户补充输入 | P3 |
| `AIToolTraceCard.swift` | 工具调用可视化 | P3 |
| `AISourceReferencesView.swift` | 来源引用 | P3 |
| `AIChatDebugEntryView.swift` | P1 连通测试 | Debug-only |

### 9.3 Application 层

| 文件 | P2 职责 |
| --- | --- |
| `AIChatViewModel.swift` | 连接、发送、取消、事件处理、错误文案、输入状态 |
| `AIChatUseCases.swift` | 把 ViewModel 行为拆到具体 UseCase |
| `AIChatEventReducer.swift` | 把 StreamEvent 转成 `AIChatState` |
| `AIChatDebugViewModel.swift` | Debug 入口状态，不参与正式 UI 主路径 |

### 9.4 Domain 层

| 文件 | P2 职责 |
| --- | --- |
| `AIChatState.swift` | 页面状态、连接状态、assistant draft、pending card |
| `AIChatMessage.swift` | 基础 user/assistant 消息 |
| `AIStreamEvent.swift` | 后端事件领域模型 |
| `AIChatProtocolModels.swift` | start_turn 和 AskUser answer payload |
| `AIChatError.swift` | 用户可见错误 |
| `AIChatSession.swift` | active session title/id，完整历史后置 |
| `AIChatTurn.swift` | active turn 和 lastSeq，恢复后置 |
| `AIChatDebugModels.swift` | Debug runtime 信息 |

### 9.5 Infrastructure 层

| 文件 | P2 职责 |
| --- | --- |
| `AIChatRepository.swift` | 正式 UI 与 WebSocket/HTTP API 的门面 |
| `AIChatWebSocketClient.swift` | WebSocket 连接、接收、心跳、重连 |
| `AIChatWebSocketConnection.swift` | URLSession task 和 outgoing JSON |
| `AIChatEventDecoder.swift` | StreamEvent DTO 到 Domain |
| `AIChatDTOs.swift` | 后端 JSON DTO |
| `AIBridgeTokenAPI.swift` | AI 对话 token 签发请求 |
| `DeepTutorSessionAPI.swift` | 会话 HTTP API，完整验收后置 |
| `AIChatResumeStore.swift` | 账号级恢复快照，P4 完整验收 |

## 10. 数据模型与 UI 消费

### 10.1 `AIChatState`

| 字段 | P2 是否使用 | UI 消费 |
| --- | --- | --- |
| `connectionState` | 是 | 空态文案、发送/停止按钮、loading |
| `activeSession` | 是 | 导航标题、继续会话 |
| `activeTurn` | 是 | 停止、lastSeq、恢复预留 |
| `messages` | 是 | `AIChatMessageList` |
| `assistantDraft` | 是 | 正在生成的 assistant draft |
| `pendingAskUserCard` | 可见但不完整验收 | `AIAskUserCardView` |
| `traceGroups` | 可见但不完整验收 | `AIToolTraceCard` |
| `sourceReferences` | 可见但不完整验收 | `AISourceReferencesView` |
| `userFacingError` | 是 | `AIChatErrorBanner` |
| `consumedEventKeys` | 是 | reducer 去重，UI 不直接展示 |

### 10.2 `AIChatMessage`

P2 基础消息要求：

| 字段 | P2 用途 |
| --- | --- |
| `id` | List identity 和 scroll target |
| `role` | user 右侧气泡，assistant 左侧气泡 |
| `content` | 文本展示 |
| `events` | P2 可为空，P3 扩展 |
| `isOptimistic` | 用户消息发送后立即显示 |

P2 消息生成规则：

```text
用户点击发送
    ↓
立即追加 optimistic user message
    ↓
收到 content/result
    ↓
追加 assistantDraft
    ↓
收到 done
    ↓
assistantDraft 固化为 assistant message
    ↓
清空 assistantDraft
```

### 10.3 `AIChatConnectionState`

| 状态 | P2 UI 行为 |
| --- | --- |
| `idle` | 显示空态，允许输入 |
| `connecting` | 显示“正在连接 AI 服务”，发送按钮不可重复触发 |
| `ready` | 可发送 |
| `sending` | 显示用户消息，等待首包 |
| `streaming` | 显示 assistant draft 和停止按钮 |
| `waitingForUser` | 可显示 AskUser 卡片，完整交互后置 |
| `reconnecting` | 可显示连接恢复中，P4 完整处理 |
| `cancelling` | 停止按钮进入处理中 |
| `cancelled` | 恢复可发送 |
| `done` | 转回可发送 |
| `failed` | 显示错误条，允许重试 |

### 10.4 `AIStreamEvent` 到 UI 的 P2 映射

| 事件 | P2 UI 行为 | 后续阶段 |
| --- | --- | --- |
| `pong` | 不显示 | P1/P4 |
| `session` | 更新 active session 和标题 | P2 |
| `session_meta` | 可更新标题 | P2 |
| `content` | 追加 assistant draft | P2 |
| `result` | 如果有文本，追加 assistant draft | P2 |
| `done` | 固化 assistant message | P2 |
| `error` | 显示错误条，进入 failed | P2 |
| `thinking` | P2 可不显示或轻量显示 | P3 |
| `stage_start` | P2 可忽略 | P3 |
| `stage_end` | P2 可忽略 | P3 |
| `observation` | P2 可忽略 | P3 |
| `tool_call` | P2 可保留数据，不要求完整 UI | P3 |
| `tool_result` | P2 可保留数据，不要求完整 UI | P3 |
| `progress` | P2 可忽略 | P3 |
| `sources` | P2 可保留数据，不要求完整 UI | P3 |
| `wait_for_input` | P2 可显示基础卡片，不要求完整验收 | P3 |
| `active_turn_info` | P2 可记录，不要求恢复 | P4 |

## 11. 关键技术落地方案

### 11.1 ViewModel 驱动视图

P2 应保持单向状态流：

```text
User Action
    ↓
AIChatViewModel
    ↓
UseCase
    ↓
AIChatRepository
    ↓
WebSocket / HTTP
    ↓
AIStreamEvent
    ↓
AIChatEventReducer
    ↓
AIChatState
    ↓
SwiftUI View
```

规则：

- View 只绑定状态和触发 action。
- View 不拼 `start_turn` JSON。
- View 不直接持有 token。
- Reducer 不发网络请求。
- Repository 不决定 UI 文案，只抛出领域错误或回调状态。

### 11.2 输入栏

当前输入栏：

```text
AIChatComposer(text:canSend:isStreaming:onSend:onStop:)
```

P2 规则：

| 行为 | 要求 |
| --- | --- |
| 空文本 | send 按钮禁用 |
| 多行输入 | `lineLimit(1...6)`，避免撑爆页面 |
| sending/streaming | 显示停止按钮 |
| failed | 保留输入或允许重新输入 |
| 发送成功 | `composerText` 清空，消息列表出现 optimistic user message |
| 输入法 | P2 可使用系统默认避让，P5 再做精细优化 |

### 11.3 消息列表

当前消息列表：

```text
ScrollViewReader
└── ScrollView
    └── LazyVStack
        ├── AIChatMessageBubble(messages)
        └── AIChatMessageBubble(assistantDraft)
```

P2 规则：

- 新 user message 出现后滚到底部。
- assistant draft 更新后滚到底部。
- `assistantDraft` 为空时不显示草稿气泡。
- `messages` 为空且 `assistantDraft` 为空时显示空态。
- P2 不要求虚拟化超长历史，P5 再评估性能。

### 11.4 消息气泡

P2 基础样式规则：

| 角色 | 布局 | 背景 | 文本 |
| --- | --- | --- | --- |
| user | 右对齐 | accentColor | 白色 |
| assistant | 左对齐 | secondarySystemBackground | primary |
| assistant draft | 左对齐 | secondarySystemBackground | 文本 + 小 loading |

P2 不要求：

- 复杂 Markdown 高保真。
- 代码块复制。
- 表格横向滚动。
- 引用角标。
- tool trace 动效。

当前 `AIChatMessageBubble` 已使用 `MarkdownDocumentView` 渲染 assistant 文本。P2 可以保留，但验收只要求基础文字可读。

### 11.5 错误条

当前错误条：

```text
AIChatErrorBanner(message:)
```

P2 错误规则：

- 错误条出现在页面顶部。
- 错误文案使用 `state.userFacingError`。
- 错误不能清空已有消息。
- 错误不能触发 SparkService 登出。
- 用户再次发送或连接成功后清理错误。

### 11.6 空态

当前空态：

```text
AIChatEmptyStateView(connectionState:)
```

P2 空态规则：

| 连接状态 | 文案目标 |
| --- | --- |
| connecting/reconnecting | 正在连接 AI 服务 |
| failed | 连接失败，请检查网络或稍后重试 |
| idle/ready | 输入问题，获取智能解答 |

P2 建议：

- 空态不要展示调试 token、endpoint。
- Debug 信息只留在 `AIChatDebugEntryView`。
- 空态可以在 P5 再做品牌化、引导 prompt 和推荐问题。

### 11.7 Toolbar

当前 toolbar：

| 按钮 | 当前行为 | P2 定位 |
| --- | --- | --- |
| 历史 | 打开 `AIChatSessionListView` sheet | 可保留，但完整验收后置 |
| 新对话 | 调用 `viewModel.startNewSession()` | P2 可验收 |

P2 对“新对话”的最低要求：

- 清空当前 messages。
- 清空 assistantDraft。
- 清空 activeSession。
- 保持连接 ready 或可发送。
- 不清除账号登录态。

### 11.8 生命周期

当前生命周期：

```text
.task { await viewModel.onAppear() }
.onDisappear { viewModel.onDisappear() }
```

P2 规则：

- 页面出现时可以自动连接。
- 页面消失时保存 resume snapshot，但不强制断开。
- 账号切换/登出由 `AccountSessionRuntime` 统一断开。
- 如果自动连接导致未配置服务时频繁报错，P2 可建议改成首次发送时连接，但不在本文档中改代码。

## 12. SwiftUI 页面验收矩阵

### 12.1 入口验收

| 编号 | 验收项 | 通过标准 |
| --- | --- | --- |
| P2-E1 | 登录后可见 AI 对话入口 | 主 Tab 出现 `AI 对话` |
| P2-E2 | 入口使用当前账号 | `AIChatEntryView` 使用 `session.accountID` |
| P2-E3 | Debug 入口隔离 | Settings 开发者入口只在 Debug 构建出现 |
| P2-E4 | 页面标题正确 | 无会话时显示 `AI 对话`，有会话时可显示会话标题 |

### 12.2 基础聊天验收

| 编号 | 验收项 | 通过标准 |
| --- | --- | --- |
| P2-C1 | 空态可见 | 无消息时显示基础引导 |
| P2-C2 | 输入可用 | 输入框可输入 1-6 行 |
| P2-C3 | 空文本不可发送 | 空白输入不会触发 start_turn |
| P2-C4 | 用户消息乐观展示 | 点击发送后立即出现 user 气泡 |
| P2-C5 | assistant draft 展示 | 收到 `content` 后显示 assistant 草稿 |
| P2-C6 | 生成完成 | 收到 `done` 后草稿固化为 assistant message |
| P2-C7 | 自动滚动 | 新消息和 draft 更新时滚到底部 |
| P2-C8 | 停止按钮 | streaming 时显示停止，点击触发 cancel |

### 12.3 状态验收

| 编号 | 验收项 | 通过标准 |
| --- | --- | --- |
| P2-S1 | 连接中 | `connecting` 显示连接中状态 |
| P2-S2 | 可发送 | `ready/done/failed/cancelled` 可发送 |
| P2-S3 | 生成中 | `sending/streaming` 显示停止按钮 |
| P2-S4 | 失败 | `failed` 显示错误条 |
| P2-S5 | 失败不清消息 | 失败后已发送消息仍保留 |
| P2-S6 | 失败不登出 | AIChat 失败不清 SparkService 登录态 |

### 12.4 安全与边界验收

| 编号 | 验收项 | 通过标准 |
| --- | --- | --- |
| P2-B1 | View 不持有 token | Presentation 文件不读取 token |
| P2-B2 | View 不拼 JSON | Presentation 文件不构造 WebSocket payload |
| P2-B3 | 错误不泄露 token | 错误条不包含 token、Authorization、query token |
| P2-B4 | Debug 信息不进正式入口 | 正式 `AIChatRootView` 不显示 endpoint/token/auth mode |
| P2-B5 | 账号切换断开 | `AccountSessionRuntime` 调用 AIChat disconnect |

## 13. 与 P1 的衔接

P2 依赖 P1 已验证或可排障的能力：

| P1 能力 | P2 使用方式 |
| --- | --- |
| WebSocket connect | 页面出现或发送时连接 |
| `ping/pong` | 连接健康由 runtime 维护，正式 UI 不展示 pong |
| `start_turn` | 发送用户消息 |
| `content/result/done` | 展示 assistant draft 和完成消息 |
| `error` | 显示错误条 |
| token 策略 | P2 不重新定义，只消费 Repository |
| Debug 入口 | P2 排障工具 |

P2 如果出现问题，定位顺序：

```text
正式入口无法发送
    ↓
检查 Debug 入口 ping/pong
    ↓
Debug 失败：回到 P1 连接/鉴权/ATS
    ↓
Debug 成功：检查 P2 ViewModel/Reducer/UI 状态
```

## 14. 与 P3 的边界

P2 只做基础可用，不承担完整事件渲染。

| 事件/组件 | P2 行为 | P3 行为 |
| --- | --- | --- |
| `thinking` | 可不显示或轻量进入 draft | 明确思考状态样式 |
| `tool_call` | 可保留 trace 数据 | 完整工具卡片 |
| `tool_result` | 可保留 trace 数据 | 完整结果卡片 |
| `sources` | 可保留引用数据 | 完整来源引用 |
| `wait_for_input` | 可显示基础 AskUser 卡片 | 完整多问题、多选项、回填和失败处理 |
| Markdown | 基础可读 | 高保真渲染 |
| trace/source 插槽 | 可存在 | 完整视觉和交互验收 |

P2 不应为了完整渲染事件而阻塞基础聊天入口验收。

## 15. 与 P4/P5 的边界

| 能力 | P2 处理 | 后续阶段 |
| --- | --- | --- |
| 会话列表 | 入口可见，基础加载可测试 | P4/P5 完整历史、分页、恢复 |
| `resume_from` | 可保留 runtime 能力 | P4 完整验收 |
| 账号隔离 | 使用 `accountID` 和 AccountSessionRuntime | P4 深入验收 |
| AI Bridge Token | 继续按 P1/P4 边界 | P4 正式闭环 |
| 输入法避让 | 使用系统基础能力 | P5 精修 |
| 品牌视觉 | 基础 SwiftUI 样式 | P5 产品化 |
| 动效 | 只保留必要滚动动画 | P5 精修 |

## 16. P2 风险与处理

| 风险 | 表现 | 处理方式 |
| --- | --- | --- |
| 正式 Tab 早于后端正式鉴权上线 | 用户看到入口但连接失败 | Release 前通过 feature flag 或产品开关控制 |
| Debug 入口和正式入口混淆 | 开发者把 Debug 成功当成正式 UI 完成 | 文档和验收分开记录 |
| 自动连接导致错误频繁出现 | 用户刚进页面就看到连接失败 | 可改为首次发送时连接，或优化空态错误策略 |
| 会话列表能力超出 P2 | 历史加载失败影响基础聊天验收 | P2 不以历史列表为阻断项 |
| assistant draft 和 done 重复文本 | `result` 与 `content` 同时追加可能重复 | P3/P5 结合真实事件样本优化 reducer |
| `MarkdownDocumentView` 复杂内容显示异常 | 表格/代码块/公式不稳定 | P2 只验收基础文本，P3/P5 完整处理 |
| 账号切换残留消息 | 切换账号后旧消息可见 | 依赖 AccountSessionRuntime + ViewModel cache 清理，P4 深验 |
| token 泄露到错误文案 | WebSocket URL 或后端错误包含 token | 继续使用脱敏 URL，不把 raw URL 放入正式 UI |

## 17. P2 实施拆分

### 17.1 P2-A 入口确认

目标：

- 确认 `AIChatEntryView` Tab 是否作为当前阶段正式入口。
- 确认 Release 是否展示入口。
- 保留 Settings Debug 入口只服务 P1 排障。

验收：

- 产品确认入口位置。
- Debug 入口不进 Release。
- 正式入口不显示 endpoint/token/auth mode。

### 17.2 P2-B 页面状态整理

目标：

- 明确 `AIChatRootView` 的空态、错误态、消息态、生成态。
- 确认 `connectionState` 到 UI 的映射。

验收：

- 每个状态都有可见表现。
- 失败不清空消息。
- 失败可重试。

### 17.3 P2-C 输入与发送

目标：

- 输入为空不可发送。
- 发送后立即出现 user message。
- streaming 时显示停止按钮。

验收：

- `composerText` trim 后为空不会调用 `start_turn`。
- 发送后输入框清空。
- streaming 中不能重复发送。

### 17.4 P2-D 基础消息渲染

目标：

- user/assistant 左右气泡区分。
- assistant draft 可持续更新。
- done 后固化 assistant message。

验收：

- 收到多段 `content` 时 draft 连续显示。
- 收到 `done` 后 draft 清空并出现在 messages。
- 自动滚动到底部。

### 17.5 P2-E 错误与排障

目标：

- AIChat 错误展示为顶部错误条。
- Debug 入口用于判断是 P1 连接问题还是 P2 UI 状态问题。

验收：

- 连接失败、发送失败、服务端 error 都有用户可读错误。
- 错误不包含敏感信息。
- SparkService 登录态不被清空。

## 18. 手工验收脚本

### 18.1 基础入口

```text
1. 登录 SupportClient。
2. 进入主界面。
3. 确认底部 Tab 存在“AI 对话”。
4. 点击“AI 对话”。
5. 确认进入 SwiftUI 原生 AIChatRootView。
6. 确认页面无 WebView 痕迹。
```

### 18.2 空态与输入

```text
1. 新账号或新对话进入 AI 对话。
2. 确认显示空态“开始一段 AI 对话”。
3. 输入空格，确认发送按钮不可用。
4. 输入“你好，请用一句话介绍你自己”。
5. 确认发送按钮可用。
```

### 18.3 发送与流式展示

```text
1. 点击发送。
2. 确认用户消息立即出现在右侧。
3. 确认页面进入发送中或生成中。
4. 收到 content 后，确认 assistant draft 出现在左侧。
5. 收到多段 content 时，确认 draft 追加且自动滚动。
6. 收到 done 后，确认 assistant draft 固化为消息。
7. 确认输入栏恢复可发送。
```

### 18.4 停止生成

```text
1. 发送一条较长生成请求。
2. streaming 时确认发送按钮替换为停止按钮。
3. 点击停止。
4. 确认发送 cancel_turn。
5. 确认已有内容不被清空。
6. 确认输入栏最终恢复可发送。
```

### 18.5 错误与 Debug 排障

```text
1. 故意关闭 DeepTutorSerevr 或配置不可用地址。
2. 进入正式 AI 对话。
3. 确认页面显示 AI 服务连接失败。
4. 确认不会退出登录。
5. 进入 Settings > 开发者 > AI 对话连通测试。
6. 使用 Debug 入口验证 ping/pong。
7. 记录问题属于 P1 连接层还是 P2 UI 层。
```

## 19. P2 文档验收清单

| 编号 | 验收项 | 通过标准 |
| --- | --- | --- |
| P2-DOC-1 | 只写 iOS SwiftUI | 文档不展开其他客户端实现 |
| P2-DOC-2 | 说明 P0/P1 偏差 | 文档包含偏差检查表 |
| P2-DOC-3 | 使用真实文件名 | 文件结构与当前工程一致 |
| P2-DOC-4 | 区分代码事实和目标设计 | 不把计划写成已实现 |
| P2-DOC-5 | 不改业务代码 | 本阶段只维护 Markdown |
| P2-DOC-6 | 阶段边界清楚 | P3/P4/P5 能力没有混入 P2 必须验收 |

## 20. P2 完成定义

P2 可标记完成，需要同时满足：

- 登录后存在明确的 AI 对话入口。
- 正式入口进入 `AIChatEntryView` / `AIChatRootView`。
- 页面有空态、消息列表、输入栏、错误条。
- 输入非空文本后可以触发发送。
- 用户消息可以乐观展示。
- assistant 流式文本可以作为 draft 展示。
- `done` 后 draft 可以固化为 assistant message。
- streaming 时可以看到停止入口。
- 连接或发送失败时有用户可读错误。
- AIChat 错误不会清空 SparkService 登录态。
- Debug 连通入口仍只在 Debug 构建出现。
- P0/P1 偏差已在本文档记录，并明确 P2 以当前代码事实为准。

P2 完成后，进入 P3 事件完整渲染。
