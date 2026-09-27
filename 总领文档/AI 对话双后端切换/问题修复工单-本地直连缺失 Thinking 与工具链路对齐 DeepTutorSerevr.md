# 问题修复工单-本地直连缺失 Thinking 与工具链路对齐 DeepTutorSerevr

## 1. 背景

当前 `AI 对话双后端切换` 已经支持：

- 设置里切换 `server` / `local`
- `local` 模式下新建会话、发送消息、流式文本、停止生成、会话列表
- iOS 端对复杂事件的 UI 骨架，包括：
  - `thinking`
  - `tool_call` / `tool_result`
  - `sources`
  - `wait_for_input`

但用户在真实联调中已经明确看到两个核心问题：

1. 本地 iOS 直接调用时，没有真正对齐 DeepTutorSerevr 的思考过程。
2. 本地 iOS 直接调用时，没有真正调用工具，也没有像 Web 那样出现提问选择、联网搜索、来源引用、Ask User 等真实智能体行为。

这说明当前 `local` 模式虽然已经有“统一事件 UI 外壳”，但还没有对齐 DeepTutorSerevr 的“运行时编排内核”。

本工单的目标不是补一两个 UI 细节，而是明确：

> 为什么本地直连现在只有基础文本流，没有 DeepTutorSerevr 那套真实 Thinking / Tool / AskUser / Sources / L1-L2 能力链路，并给出必须对齐的架构与修复要求。

## 2. 当前现象

### 2.1 用户可见问题

当前本地 iOS 直连的用户可见问题是：

- 只有基础回复文本，没有和 Web 一致的思考过程。
- 没有真实的工具调用轨迹。
- 没有 Ask User 的真实提问/选项交互链路。
- 没有与工具调用配套的来源引用。
- 没有“为什么用了某个工具、用了哪些工具、用了哪些来源”的可解释过程。

### 2.2 目标参考效果

用户提供的 Web 片段已经说明 DeepTutorSerevr 当前真实表现并不只是“回答一段话”，而是会在同一个 turn 内连续出现：

- 思考说明
- 向用户提问
- 联网搜索
- 抓取网页
- 工具调用参数
- 工具调用结果
- 来源引用
- 整理后的最终回答

这类体验属于 DeepTutorSerevr 的智能体运行时，不是单个大模型 `chat.completions` 文本流天然就会自动给出的。

## 3. 代码事实

### 3.1 iOS 端复杂事件 UI 其实已经具备

当前 iOS 并不是“渲染不了”这些东西。

现有代码已经具备：

- [AIChatEventReducer.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Application/AIChatEventReducer.swift)
  - 已处理 `thinking`、`tool_call`、`tool_result`、`sources`、`wait_for_input`
- [AIChatCardComposer.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Application/AIChatCardComposer.swift)
  - 已支持 `sources`、Ask User、activity panel、loading、recovery banner
- [AIAssistantTurnView.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIAssistantTurnView.swift)
  - 已把 reducer/assembler/composer 结果统一渲染
- [AIChatCardRouter.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIChatCardRouter.swift)
  - 已能渲染 answer、askUser、sources、activityPanel
- [AIAskUserCard.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIAskUserCard.swift)
  - 已有真实 Ask User 卡片交互
- [AISourceReferencesView.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AISourceReferencesView.swift)
  - 已有来源卡片
- [AIToolTraceCard.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIToolTraceCard.swift)
  - 已有工具轨迹卡片

结论：

> 当前问题不在 UI 层，而在本地运行时没有把这些事件真实产出。

### 3.2 local stub 分支已经能“伪造”复杂事件

当前本地 stub 演示层已经存在：

- [LocalAIChatComplexEventPlanner.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalAIChatComplexEventPlanner.swift)
- [LocalAIChatStreamAdapter.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalAIChatStreamAdapter.swift)

它们已经可以产出：

- `tool_call`
- `tool_result`
- `sources`
- `wait_for_input`

这说明 iOS 本地链路的复杂事件协议外壳已经搭起来了。

但这只是 **stub 演示**，不是 DeepTutorSerevr 那种真实运行时能力。

### 3.3 真正走 API 的本地分支仍然只会吐文本

[LocalAIChatRuntime.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalAIChatRuntime.swift) 当前真实 API 分支是：

```text
resolve chat config
  -> LocalAIChatStreamClient.streamCompletion(...)
  -> for each delta:
       emit content
```

[LocalAIChatStreamClient.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalAIChatStreamClient.swift) 当前只做了一件事：

- 请求 OpenAI-compatible `chat/completions` 流
- 从 SSE 里只解析 `delta.content` / `message.content` / `text`

也就是说，当前真实本地直连只能拿到：

- 文本增量

拿不到，也没有尝试拿：

- reasoning / thinking 片段
- tool call structured delta
- tool result structured delta
- ask user payload
- sources metadata
- stage / progress / orchestration trace

### 3.4 start_turn 侧当前没有把 L1/L2 能力真正下发给 local 执行器

[AIChatProtocolModels.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Domain/AIChatProtocolModels.swift) 里当前 `chatTurn()` / `p1Minimal()` 固定是：

- `capability = "chat"`
- `tools = []`
- `knowledge_bases = []`

这意味着当前本地模式起 turn 时，协议层默认就没有真正声明：

- 要不要使用 Web
- 要不要使用 RAG
- 要不要使用 Memory
- 要不要使用 Exec
- 要不要使用 MCP
- 要不要触发 Ask User

结论：

> 当前 iOS 本地模式不是“模型没选对工具”，而是请求入口压根没有把工具能力当成真实运行时输入。

### 3.5 LocalAIChatRepository 虽然支持 Ask User 提交，但只覆盖本地演示续接

[LocalAIChatRepository.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalAIChatRepository.swift) 现在已经支持：

- `submitUserReply`
- `sendUserInput`

但当前语义仍是：

- 只有当本地 stub 先发出 `wait_for_input` 时，这条续接链路才成立
- `regenerate` 仍未对齐
- 工具调用与来源引用没有真实执行内核

所以现在的 Ask User 更接近：

- “UI 和本地演示流已经接好”

而不是：

- “真实智能体流程已经对齐 DeepTutorSerevr”

### 3.6 DeepTutorSerevr 的真实代码入口已经非常明确

这次问题不能只凭 UI 片段推断，必须对照 DeepTutorSerevr 的真实代码位置。

当前已经确认的服务端关键入口如下：

| 层级 | DeepTutorSerevr 代码位置 | 作用 | 对 iOS 本地直连的意义 |
| --- | --- | --- | --- |
| WebSocket 入口 | [deeptutor/api/routers/unified_ws.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/api/routers/unified_ws.py) | 定义 `start_turn`、`resume_from`、`cancel_turn`、`submit_user_reply`、`user_input`、`check_active_turn` | iOS `server` 模式已经在消费这套协议；`local` 若想真对齐，语义上也必须有同名能力 |
| Turn 生命周期 | [deeptutor/services/session/turn_runtime.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/services/session/turn_runtime.py) | `TurnRuntimeManager` 真正管理 turn 创建、执行、取消、回复、恢复、订阅 | iOS 当前缺失的不是消息页，而是这个运行时层 |
| 能力总入口 | [deeptutor/runtime/orchestrator.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/runtime/orchestrator.py) | `ChatOrchestrator` 把 `UnifiedContext` 路由到 capability | iOS `local` 当前没有 capability router |
| 统一上下文 | [deeptutor/core/context.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/core/context.py) | `UnifiedContext` 承载 session、history、tools、KB、language、memory、persona、metadata | iOS 当前只有简化 payload，没有对齐这一层上下文模型 |
| 流式总线 | [deeptutor/core/stream_bus.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/core/stream_bus.py) | `thinking`、`tool_call`、`tool_result`、`sources`、`progress`、`result`、`error` 的统一发射口 | iOS 现在有 `AIStreamEvent`，但没有 server 等价的本地 event bus |
| 全局事件总线 | [deeptutor/events/event_bus.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/events/event_bus.py) | 跨模块发布完成事件、异步观察结果 | iOS 本地直连短期可以不完整复制，但要知道 server 有更高一层事件总线 |
| Capability 注册 | [deeptutor/runtime/bootstrap/builtin_capabilities.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/runtime/bootstrap/builtin_capabilities.py) | 显式注册 `chat`、`deep_solve`、`deep_research`、`visualize`、`mastery_path` 等 | iOS `local` 不能永远只有硬编码 `chat` |
| Tool 注册 | [deeptutor/runtime/registry/tool_registry.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/runtime/registry/tool_registry.py) | 全部工具的注册、解析、执行、OpenAI schema 暴露 | iOS `local` 当前没有本地 tool registry |
| 工具可配置面 | [deeptutor/api/utils/tool_options.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/api/utils/tool_options.py) | 区分 toggleable tools / builtin tools / MCP tools | iOS `local` 需要明确哪些工具可选，哪些上下文自动挂载 |
| 架构说明 | [AGENTS.md](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/AGENTS.md) | 官方架构总览，清楚写明 L1/L2、orchestrator、StreamBus | 可以作为本工单的服务端结构对照基线 |

### 3.7 DeepTutorSerevr 的 L1 / L2 不是概念，而是已落代码的注册表

从服务端代码可确认：

- L2 capability 注册在 [builtin_capabilities.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/runtime/bootstrap/builtin_capabilities.py)
  - `chat`
  - `deep_solve`
  - `deep_question`
  - `deep_research`
  - `visualize`
  - `math_animator`
  - `mastery_path`

- L1 tools 注册在 [tool_registry.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/runtime/registry/tool_registry.py) 与 [tool_options.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/api/utils/tool_options.py)
  - toggleable tools
  - builtin auto-mounted tools
  - deferred MCP tools

这意味着：

> DeepTutorSerevr 的 Thinking / Tool / Sources / Ask User，不是某个模型的副产品，而是 capability registry + tool registry + stream bus 联合运行的结果。

### 3.8 当前 iOS 本地实现与服务端目录层级完全不对等

当前 iOS 本地链路的核心文件集中在：

- [LocalAIChatRuntime.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalAIChatRuntime.swift)
- [LocalAIChatStreamClient.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalAIChatStreamClient.swift)
- [LocalAIChatComplexEventPlanner.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalAIChatComplexEventPlanner.swift)
- [LocalAIChatRepository.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalAIChatRepository.swift)

它们合起来做了：

- session 创建
- user message 写本地缓存
- 走一个 OpenAI-compatible 文本流
- 必要时走 stub 复杂事件演示

但它们没有形成 server 对等层次的：

- runtime manager
- unified context
- capability registry
- tool registry
- stream bus
- mounted tool policy

这正是当前“本地模式体验落后于 server”的结构性原因。

## 4. 问题判断

### 4.1 主问题结论

当前本地 iOS 直连的主问题不是某个卡片没显示，而是：

> 当前 `local` 真正执行分支只接了一个 OpenAI-compatible 文本流客户端，没有接 DeepTutorSerevr 那套运行时编排层，所以自然不会产生 DeepTutorSerevr 的 thinking、tool_call、tool_result、sources、Ask User 等智能体事件。

### 4.2 更深一层的架构偏差

DeepTutorSerevr 的真实能力链路不是：

```text
user input -> llm text output
```

而是更接近：

```text
user input
 -> runtime orchestration
 -> context planning
 -> capability dispatch
 -> tool selection
 -> tool execution
 -> source collection
 -> ask-user interruption if needed
 -> final synthesis
 -> stream bus output
```

而 iOS 本地直连当前真实实现是：

```text
user input
 -> resolve one model endpoint
 -> call chat.completions stream
 -> append content text
```

这两条链路天然不等价。

### 4.3 当前“不对齐”的根因清单

根因至少有六项：

1. **缺少本地运行时编排层**
   - 没有 DeepTutorSerevr 等价的 `TurnRuntimeManager / ChatOrchestrator / StreamBus`

2. **缺少本地能力路由层**
   - 没有按 `capability` 把 turn 分发到 Chat / Auto / Deep Solve / Deep Research / Visualize / Mastery Path

3. **缺少本地工具注册与调度层**
   - 没有真正注册 `RAG / Memory / Web / Exec / MCP / Ask User`

4. **缺少 structured tool stream 解析**
   - `LocalAIChatStreamClient` 只解析文本，不解析工具结构化事件

5. **缺少来源聚合器**
   - `sources` 现在只有 stub 演示，没有真实引用链路

6. **缺少与 DeepTutorSerevr 一致的 ask_user 工具语义**
   - 当前 Ask User 只有本地演示，不是工具链路中断恢复的一部分

## 5. 与 DeepTutorSerevr 的能力差异

### 5.1 L2 能力差异

用户明确要求对齐的 L2 能力是：

- `Chat`
- `Auto`
- `Deep Solve`
- `Deep Research`
- `Visualize`
- `Mastery Path`

当前本地 iOS 真实状态如下：

| L2 能力 | DeepTutorSerevr | iOS `server` 模式 | iOS `local` 当前真实状态 | 结论 |
| --- | --- | --- | --- | --- |
| `Chat` | 已有完整编排 | 已可消费 | 只有基础文本流 | 仅最小连通 |
| `Auto` | 有运行时编排 | 已可消费 | 无本地能力路由 | 未对齐 |
| `Deep Solve` | 有 planning / tool / synthesize | 已可消费 | 无规划层 | 未对齐 |
| `Deep Research` | 有检索与来源 | 已可消费 | 无真实 RAG / Web / sources | 未对齐 |
| `Visualize` | 可进入专门能力路径 | 已可消费 | 无本地能力分发 | 未对齐 |
| `Mastery Path` | 有专门能力语义 | 已可消费 | 无本地能力分发 | 未对齐 |

### 5.2 L1 工具差异

用户明确要求对齐的 L1 工具是：

- `RAG`
- `Memory`
- `Web`
- `Exec`
- `MCP`
- `Ask User`

当前本地 iOS 真实状态如下：

| L1 工具 | DeepTutorSerevr | iOS `local` 当前真实状态 | 当前问题 |
| --- | --- | --- | --- |
| `RAG` | 已进入工具链与来源链 | 没有真实接入 | 只有 stub sources |
| `Memory` | 已进入上下文运行时 | 没有真实接入 | 无长期/短期记忆调度 |
| `Web` | 已有联网搜索/网页抓取 | 没有真实接入 | 无本地 web tool |
| `Exec` | 已有执行工具链 | 没有真实接入 | 无本地执行器 |
| `MCP` | 已可加载工具生态 | 没有真实接入 | 无本地 MCP runtime |
| `Ask User` | 已是运行时中断工具的一部分 | 仅 stub 演示可见 | 非真实工具结果驱动 |

## 6. DeepTutorSerevr 关键技术对齐

### 6.1 技术一：统一 WebSocket turn 协议

DeepTutorSerevr 的真实协议入口在：

- [unified_ws.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/api/routers/unified_ws.py)

该入口支持的核心动作包括：

- `start_turn`
- `subscribe_turn`
- `subscribe_session`
- `resume_from`
- `cancel_turn`
- `submit_user_reply`
- `check_active_turn`
- `user_input`
- `regenerate`

对 iOS 本地模式的真正要求不是“也开一个 WebSocket”，而是：

- 本地运行时也要拥有这些动作对应的**业务语义**
- 即使 transport 不一样，turn 生命周期也要一样

当前 iOS `local` 的偏差是：

- `start_turn`：有
- `cancel_turn`：有
- `submit_user_reply`：部分有
- `user_input`：部分有
- `resume_from`：无真实运行时恢复
- `regenerate`：未对齐
- `subscribe_turn/session`：没有本地事件订阅抽象

### 6.2 技术二：TurnRuntimeManager

DeepTutorSerevr 的 turn 生命周期核心在：

- [turn_runtime.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/services/session/turn_runtime.py)

从代码上看，这个类至少负责：

- turn 创建
- payload 校验
- capability / tools / knowledge_bases / language / persona / llm_selection 收敛
- 执行状态管理
- 取消
- ask_user 回复队列
- persisted + live events 混合订阅
- orphan running turn 恢复

这一层非常关键，因为它说明：

> DeepTutorSerevr 的复杂事件，不是 capability 里随便往外 print 出来的，而是被一个 turn runtime manager 统一托管。

iOS 当前缺失的是这一层的本地等价物。

建议本地补齐时显式建立：

```text
LocalTurnRuntimeManager
```

职责至少包括：

- `startTurn`
- `cancelTurn`
- `submitUserReply`
- `sendUserInput`
- `regenerate`
- `subscribeTurn`
- `loadReplayEvents`
- `resumeIfNeeded`

### 6.3 技术三：UnifiedContext

DeepTutorSerevr 的统一上下文模型在：

- [context.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/core/context.py)

它承载的不是“一个 prompt 字符串”，而是：

- session_id
- user_message
- conversation_history
- enabled_tools
- allowed_builtin_tools
- active_capability
- knowledge_bases
- attachments
- config_overrides
- language
- memory_context
- persona_context
- skills_manifest
- source_manifest
- metadata

而当前 iOS 本地 `AIStartTurnPayload` 只包含：

- `content`
- `session_id`
- `capability`
- `tools`
- `knowledge_bases`
- `language`
- `config`
- `persona`
- `llm_selection`

这意味着当前 iOS 本地输入层比服务端的 UnifiedContext 少了：

- memory_context
- source_manifest
- allowed_builtin_tools
- attachments 的统一工具上下文消费语义
- skills_manifest
- 更丰富的 metadata

所以要真正对齐，建议本地新增：

```text
LocalAIUnifiedContext
```

并让 `LocalAIChatRuntime` 不再直接吃原始 payload，而是吃统一上下文对象。

### 6.4 技术四：Capability Registry

DeepTutorSerevr 的 capability 注册在：

- [builtin_capabilities.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/runtime/bootstrap/builtin_capabilities.py)

这说明 L2 能力不是 UI 层标签，而是真正可路由的运行时模块。

当前 iOS 本地模式还没有：

- capability class registry
- capability router
- capability-specific config validator

建议本地显式建立：

```text
LocalCapabilityRouter
LocalCapabilityKind
LocalCapabilityExecutor
```

至少先支持：

- `chat`
- `deep_research`
- `deep_solve`
- `visualize`
- `mastery_path`

即使首期内部都还是走同一模型，也必须先把 capability 路由层搭起来，否则永远无法和 DeepTutorSerevr 对齐。

### 6.5 技术五：Tool Registry 与挂载策略

DeepTutorSerevr 的工具注册与配置分成两层：

- [tool_registry.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/runtime/registry/tool_registry.py)
- [tool_options.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/api/utils/tool_options.py)

这里最关键的不是“有哪些工具名”，而是：

- 工具是注册对象，不是硬编码判断
- 有 toggleable tools
- 有 builtin auto-mounted tools
- 有 MCP deferred tools
- 工具还可以导出 function schema

当前 iOS 本地模式最大的问题之一是：

- 还没有一个本地 tool registry
- 也没有 mounted tool policy

建议本地新增：

```text
LocalToolRegistry
LocalToolMountPolicy
LocalToolDefinition
LocalToolExecutor
```

工具分层建议：

- user-toggleable
  - `Web`
  - `RAG`
  - `Exec`
- auto-mounted
  - `Memory`
  - `Ask User`
  - `read_source` 等来源辅助
- deferred / external
  - `MCP`

### 6.6 技术六：StreamBus

DeepTutorSerevr 的统一事件发射层在：

- [stream_bus.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/core/stream_bus.py)

它至少原生支持：

- `content`
- `thinking`
- `observation`
- `tool_call`
- `tool_result`
- `progress`
- `sources`
- `result`
- `error`
- `stage_start`
- `stage_end`

当前 iOS 虽然有 `AIStreamEvent`，但并没有一个与 server 同级的本地事件总线。

现在是：

- runtime 内部临时 `emit(event)`

而不是：

- 多个 capability / tool / orchestrator 都往一条标准 StreamBus 发事件

建议本地新增：

```text
LocalAIStreamBus
```

目标：

- capability 发 thinking / stage
- tool executor 发 tool_call / tool_result
- source collector 发 sources
- runtime manager 发 session / done / error

### 6.7 技术七：Ask User 的暂停恢复机制

DeepTutorSerevr 的 `ask_user` 不是 UI 提示，而是 turn runtime 的暂停恢复机制。

从服务端代码位置可以确认：

- [unified_ws.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/api/routers/unified_ws.py)
  - 有 `submit_user_reply`
  - 有 `user_input`
- [turn_runtime.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/services/session/turn_runtime.py)
  - 有 `_reply_queues`
  - 有 `submit_user_reply(...)`

这说明服务端的真实语义是：

- 工具或 capability 暂停
- runtime manager 建立 reply queue
- 客户端提交答案
- 原 turn 继续跑

而当前 iOS 本地模式的 Ask User 只有：

- stub 触发
- 交互表单
- 再拼一段本地续接文本

建议本地最终形态也改成：

- `LocalTurnRuntimeManager` 持有 reply queue
- `LocalAskUserBridge` 负责等待与恢复
- Ask User 由工具链路或 capability 主动触发

### 6.8 技术八：来源链路

DeepTutorSerevr 的 `sources` 不是 UI 补丁，而是检索、搜索、网页抓取、文档读取、记忆召回后的统一结果视图。

当前本地模式的问题是：

- `sources` 只在 `LocalAIChatComplexEventPlanner` 里用演示数据拼出来

建议本地新增：

```text
LocalSourceCollector
```

负责统一收口：

- Web 搜索来源
- RAG 命中来源
- Memory 命中来源
- MCP / Exec / 读取类工具的结果来源

## 7. DeepTutorSerevr 目录结构对齐

### 7.1 服务端真实目录职责

当前与本问题最相关的 DeepTutorSerevr 目录职责可收敛为：

```text
DeepTutorSerevr/
├── deeptutor/api/
│   ├── routers/unified_ws.py
│   └── utils/tool_options.py
├── deeptutor/services/session/
│   └── turn_runtime.py
├── deeptutor/runtime/
│   ├── orchestrator.py
│   ├── bootstrap/builtin_capabilities.py
│   └── registry/
│       ├── capability_registry.py
│       └── tool_registry.py
├── deeptutor/core/
│   ├── context.py
│   └── stream_bus.py
└── deeptutor/events/
    └── event_bus.py
```

### 7.2 iOS 本地建议对齐目录

建议 iOS 不要继续把所有本地能力都塞在一个 `LocalAIChatRuntime.swift` 里。

更合理的结构是：

```text
SupportClient/SupportClient/Projects/Features/AIChat/
├── Domain/
│   ├── AIChatProtocolModels.swift
│   ├── AIStreamEvent.swift
│   ├── LocalAIUnifiedContext.swift
│   ├── LocalCapabilityKind.swift
│   ├── LocalToolDefinition.swift
│   └── LocalToolResult.swift
├── Application/
│   ├── AIChatEventReducer.swift
│   ├── AIChatTurnAssembler.swift
│   ├── AIChatCardComposer.swift
│   └── LocalToolMountPolicy.swift
├── Infrastructure/
│   ├── LocalRuntime/
│   │   ├── LocalTurnRuntimeManager.swift
│   │   ├── LocalCapabilityRouter.swift
│   │   ├── LocalAIStreamBus.swift
│   │   ├── LocalAskUserBridge.swift
│   │   └── LocalSourceCollector.swift
│   ├── LocalCapabilities/
│   │   ├── LocalChatCapability.swift
│   │   ├── LocalDeepResearchCapability.swift
│   │   ├── LocalDeepSolveCapability.swift
│   │   ├── LocalVisualizeCapability.swift
│   │   └── LocalMasteryPathCapability.swift
│   ├── LocalTools/
│   │   ├── LocalToolRegistry.swift
│   │   ├── LocalWebTool.swift
│   │   ├── LocalRAGTool.swift
│   │   ├── LocalMemoryTool.swift
│   │   ├── LocalExecTool.swift
│   │   ├── LocalMCPToolBridge.swift
│   │   └── LocalAskUserTool.swift
│   ├── LocalAIChatRuntime.swift
│   ├── LocalAIChatRepository.swift
│   ├── LocalAIChatStreamClient.swift
│   └── LocalAIChatStreamAdapter.swift
└── Presentation/
    ├── AIAskUserCard.swift
    ├── AIToolTraceCard.swift
    └── AISourceReferencesView.swift
```

### 7.3 为什么要拆目录

因为当前最大的问题就是：

- runtime manager
- capability router
- tool registry
- event bus

这些职责都还没从 `LocalAIChatRuntime` 里分离出来。

如果不先拆目录，后续：

- `Chat`
- `Auto`
- `Deep Solve`
- `Deep Research`
- `Visualize`
- `Mastery Path`

只会继续堆在一个文件里，最后无法维护，也无法稳定对齐服务端。

## 8. 当前代码和产品壳之间的错位

当前项目已经出现一个很典型的“壳先于魂”的状态：

- UI 壳：基本齐了
- reducer 壳：基本齐了
- event type 壳：基本齐了
- 本地演示壳：部分齐了
- 真实本地运行时内核：明显不齐

换句话说：

> 当前 iOS 本地模式已经能“显示出复杂事件应该长什么样”，但还不能“真实地产生 DeepTutorSerevr 那些复杂事件”。

这也是为什么用户看到的体验是：

- Web 端有真实 thinking、联网搜索、提问选择、来源
- iOS 本地直连只有基础回复或演示型复杂事件

## 9. 修复要求

### 7.1 第一优先级：本地真实执行分支必须从“纯文本流”升级为“智能体事件流”

必须满足：

1. 不能只解析 `content delta`
2. 必须支持 structured event
3. 必须支持 tool call / tool result
4. 必须支持 ask user interruption
5. 必须支持 sources aggregation
6. 必须支持 capability-based execution

### 7.2 第二优先级：本地运行时必须建立 DeepTutorSerevr 对齐的能力分发

本地至少要引入一层等价职责：

```text
LocalTurnRuntimeManager
  -> LocalUnifiedContext
  -> LocalCapabilityRouter
  -> LocalToolRegistry
  -> LocalStreamBus
```

职责要求：

- `LocalTurnRuntimeManager`
  - 管 turn 生命周期、取消、恢复、等待输入
- `LocalUnifiedContext`
  - 统一携带 session、history、capability、tool budget、sources
- `LocalCapabilityRouter`
  - 按 `Chat / Auto / Deep Solve / Deep Research / Visualize / Mastery Path` 分发
- `LocalToolRegistry`
  - 注册 `RAG / Memory / Web / Exec / MCP / Ask User`
- `LocalStreamBus`
  - 统一把内部动作翻译成 `AIStreamEvent`

### 7.3 第三优先级：不要继续把 stub 演示事件当成真实对齐

当前 `LocalAIChatComplexEventPlanner` 只能作为：

- UI 演示工具
- 联调占位工具

不能继续被视为“本地复杂事件已经对齐”的证据。

### 7.4 第四优先级：start_turn 协议必须允许本地真正声明能力与工具

当前固定：

- `capability = chat`
- `tools = []`
- `knowledge_bases = []`

这必须升级成可配置、可路由的真实输入。

至少要支持：

- 当前轮 capability
- 当前轮允许的 L1 工具集合
- 是否允许 Ask User
- 是否允许来源引用
- 是否允许 RAG / Web / Memory

## 10. 推荐修复方向

### 8.1 推荐方向 A：本地实现“轻量版 DeepTutorSerevr 运行时”

这是最推荐的方向。

不是把 DeepTutorSerevr 整个搬到 iOS，而是把它最关键的运行时职责在 Swift 侧重新落一层：

- 会话与 turn 编排
- capability 分发
- tool registry
- structured event bus
- ask user bridge
- sources collector

优点：

- 最接近 DeepTutorSerevr 语义
- 后续 L1/L2 才有继续补齐的空间
- UI、reducer、card 已经能直接复用

### 8.2 推荐方向 B：继续只走 OpenAI-compatible chat completions，但增强为 tool-aware client

这条路可以作为过渡，但不是长期最佳方案。

必须额外补：

- tool schema 下发
- tool call result 解析
- reasoning event 兼容
- ask user 中断协议
- sources 收口层

问题在于：

- 普通 `chat.completions` 本身不等于 DeepTutorSerevr runtime
- 就算补强，也依然缺能力分发层和工具统一调度层

所以它更适合作为短期过渡，不适合作为最终形态。

## 11. 验收标准

### 9.1 Thinking 对齐验收

- [ ] 本地真实 API 分支不再只有基础文本流
- [ ] 能产出与 Web 一致语义的 `thinking` / `progress` / `stage` 信息
- [ ] Thinking 面板不是只显示“正在生成回复”这类单句占位

### 9.2 Tool 对齐验收

- [ ] 本地真实 API 分支能出现真实 `tool_call`
- [ ] 本地真实 API 分支能出现真实 `tool_result`
- [ ] 工具卡内容来自真实工具执行，不是 stub 拼接

### 9.3 Ask User 对齐验收

- [ ] `wait_for_input` 由真实运行时触发
- [ ] 用户回答后，本地 turn 能真实续接
- [ ] Ask User 不再只是问号命中或演示规则触发

### 9.4 Sources 对齐验收

- [ ] `sources` 来自真实检索或工具引用结果
- [ ] 来源卡不再使用演示数据
- [ ] 恢复历史会话时，sources 仍能重建

### 9.5 L1 / L2 能力验收

- [ ] 至少 `Chat + Web + Ask User + Sources` 完成一条真实本地闭环
- [ ] 后续再逐步补 `RAG / Memory / Exec / MCP`
- [ ] capability 分发能区分 `Chat / Auto / Deep Solve / Deep Research / Visualize / Mastery Path`

## 12. 建议工序

1. 先冻结“本地真实能力对齐 DeepTutorSerevr”的范围，不再把 stub 当完成态。
2. 建立本地 capability router 和 tool registry。
3. 升级 `LocalAIChatRuntime`，让真实 API 分支产出 structured event，而不是只吐文本。
4. 让 `AIStartTurnPayload` 支持真实 capability/tools/knowledge_bases 输入。
5. 先打通 `Chat + Web + Ask User + Sources` 这条最小智能体链路。
6. 再按优先级补 `RAG / Memory / Exec / MCP`。

## 13. 结论

当前本地 iOS 直连的问题，不是某个视图没写完，而是：

> `local` 模式目前只有“文本流客户端 + 复杂事件演示器”，还没有 DeepTutorSerevr 那种“能力编排 + 工具调度 + 结构化事件总线”的真实运行时。

因此，想真正对齐：

- Thinking
- 工具调用
- Ask User
- Sources
- L1/L2 能力

就不能继续只修表层卡片或补几条假事件，必须把本地运行时内核补起来。

## 14. 当前真实代码链路逐段分析

这一节不再停留在“有没有这个文件”的层面，而是把当前 iOS 本地直连与 DeepTutorSerevr 的完整链路按执行顺序拆开。

目标是明确三件事：

1. 当前链路已经落了哪些真正的运行时层。
2. 当前链路在哪一段开始与 DeepTutorSerevr 分叉。
3. 每一段为什么会直接导致 “Thinking 不完整、工具没真正执行、Ask User 只有半闭环”。

### 14.1 iOS 本地直连实际入口链路

当前用户在 iOS 发起一次本地对话时，真实链路已经不是旧版那种单文件串流，而是：

```text
AIChatViewModel / RepositoryFacade
  -> LocalAIChatRepository.startTurn(...)
  -> LocalAIUnifiedContext.from(...)
  -> LocalAIChatRuntime.runTurn(...)
  -> LocalTurnRuntimeManager.startTurn(...)
  -> LocalAIStreamBus.emitSession()
  -> LocalCapabilityRouter.execute(...)
  -> LocalChatCapability.execute(...)
  -> LocalToolMountPolicy.mountedTools(...)
  -> Memory / RAG / Web 预执行
  -> streamAgenticSynthesis(...)
  -> LocalAIChatStreamClient.streamCompletion(...)
  -> 解析 thinking/content/tool_calls
  -> 回写 AIStreamEvent
  -> reducer / card composer / SwiftUI 卡片渲染
```

这说明当前工程已经开始朝 DeepTutorSerevr 的结构靠拢，但“靠拢”不等于“完全对齐”。

### 14.2 `LocalAIChatRepository` 代码级职责分析

文件：

- [LocalAIChatRepository.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalAIChatRepository.swift)

关键代码段与含义：

- 第 4 行
  - `LocalAIChatRepository` 明确声明自己是 `local` 模式仓储，职责是本地内存会话闭环，不允许调用 DeepTutorSerevr 会话接口。
- 第 15-21 行
  - 注入 `sessionStore`、`resumeStore`、`runtime`、`aiConfigCenter`、`sessionLogger`、`diagnostics`。
  - 这说明仓储层已经不是“直接请求模型”，而是在做本地会话、恢复快照、运行时编排的总装配。
- 第 108-162 行 `startTurn`
  - 先校验账号。
  - 再本地建会话、写用户消息、生成 turnID。
  - 再把历史消息取出，组装 `LocalAIUnifiedContext`。
  - 最后异步调用 `runTurn(context:)`。
  - 这段与服务端 `start_turn -> TurnRuntimeManager.start_turn -> build context` 已有明显对应关系。
- 第 164-175 行 `cancelActiveTurn`
  - 当前取消只取消本地 `Task`，没有服务端那种全局 bus、订阅者、active turn 查询语义。
  - 对应 DeepTutorSerevr 只能算“最小取消”。
- 第 177-179 行 `regenerate`
  - 仍然直接报错。
  - 这意味着本地会话语义还没有完全对齐服务端。
- 第 181-210 行 `submitUserReply` / `sendUserInput`
  - 当前已经支持 Ask User 后续接。
  - 但判断条件仍依赖 `runtime.isWaitingForInput(turnID:)` 与当前 `activeTurnContext`。
  - 这是一种本地轻量暂停恢复，不是服务端那种 reply queue + subscriber 模式。
- 第 292-359 行 `runTurn`
  - 真正把 `runtime.runTurn(...)` 产出的事件透传给 UI。
  - 结束后把 `assistantContent` 持久在本地 sessionStore。
  - 如果 `pausedForUserInput == true`，就把 turn 留在等待态。
  - 这说明 Repository 已经具备“turn 生命周期承接层”，问题不在页面。
- 第 361-415 行 `resumeTurnAfterUserReply`
  - 续接后仍然复用同一个 turnID。
  - 说明当前本地直连的 Ask User 恢复语义已经基本形成，但仍是单机实现。

结论：

> `LocalAIChatRepository` 现在已经是一个真正的“本地聊天会话编排外壳”，不再只是旧式 API client；但它只负责会话、状态和结果回写，不负责能力编排本身。

### 14.3 `LocalAIChatRuntime` 代码级职责分析

文件：

- [LocalAIChatRuntime.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalAIChatRuntime.swift)

关键代码段与含义：

- 第 12-25 行
  - `LocalAIChatRuntime` 现在已经变成对 `LocalTurnRuntimeManager` 的薄封装。
  - 这意味着旧版本“所有逻辑全塞 runtime”的结构已经开始拆层。
- 第 27-33 行 `runTurn`
  - 从 `AIConfigCenter` 取快照。
  - 把 `context + snapshot + emit` 交给 `turnRuntimeManager.startTurn(...)`。
- 第 35-47 行 `resumeAfterUserReply`
  - 同样只是把续接请求转发给 `turnRuntimeManager.resumeAfterUserReply(...)`。
- 第 49-59 行
  - `submitUserReply/isWaitingForInput/clear` 都转交给 runtime manager 内部的 AskUserBridge。

结论：

> 当前 `LocalAIChatRuntime` 本身已经不再是缺陷根源，真正决定是否对齐 DeepTutorSerevr 的，是它委托进去的 `LocalTurnRuntimeManager + LocalCapabilityRouter + LocalChatCapability`。

### 14.4 `LocalTurnRuntimeManager` 代码级职责分析

文件：

- [LocalTurnRuntimeManager.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalRuntime/LocalTurnRuntimeManager.swift)

关键代码段与含义：

- 第 3-17 行
  - 初始化时创建 `LocalChatCapability`、`LocalCapabilityRouter`、`LocalAskUserBridge`。
  - 说明本地运行时现在已经有：
    - capability 执行器
    - capability 路由层
    - Ask User 暂停恢复桥
- 第 19-36 行 `startTurn`
  - 创建 `LocalAIStreamBus`
  - 先发 `session` 事件
  - 再把执行交给 `capabilityRouter.execute(...)`
  - 这已经和 DeepTutorSerevr 的 `SESSION -> capability.run -> DONE` 主节奏非常接近。
- 第 38-46 行 `resumeAfterUserReply`
  - 通过 `withSupplementalReply` 把用户补充信息重新并入上下文，再走一次完整 `startTurn`
  - 这是本地恢复逻辑的核心。
- 第 48-58 行
  - 只保留一个轻量 `askUserBridge`
  - 缺少服务端那种 reply queue、多订阅者、resume_from、active bus registry。

结论：

> `LocalTurnRuntimeManager` 已经补上了“本地 TurnRuntimeManager”的最小骨架，但它仍属于单进程轻量版，没有完全复刻 DeepTutorSerevr 的 turn 管理能力。

### 14.5 `LocalAIUnifiedContext` 代码级职责分析

文件：

- [LocalAIUnifiedContext.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Domain/LocalAIUnifiedContext.swift)

关键代码段与含义：

- 第 3-18 行
  - 上下文字段已经包括：
    - `accountID`
    - `sessionID`
    - `turnID`
    - `userMessage`
    - `history`
    - `capability`
    - `enabledTools`
    - `knowledgeBases`
    - `language`
    - `persona`
    - `llmSelection`
    - `metadata`
    - `supplementalUserReply`
  - 这已经比之前“只有 content + sessionID”的阶段完整很多。
- 第 20-43 行 `from(...)`
  - 明确从 `AIStartTurnPayload` 映射 capability、tools、knowledgeBases。
  - 这意味着旧文档里“local 入口永远 tools = []”已经不能作为当前事实。
- 第 45-61 行 `withSupplementalReply`
  - 用于 Ask User 后恢复 turn。

与 DeepTutorSerevr 对比：

- 优点
  - 已有本地统一上下文概念。
  - 能够承载 capability 与 tools。
- 缺口
  - 还没有服务端 `UnifiedContext` 里的 memory/persona/source manifest/attachments/config overrides 那么完整。
  - 没有清晰区分“用户显式允许工具”和“系统自动挂载工具”。

### 14.6 `LocalAIStreamBus` 代码级职责分析

文件：

- [LocalAIStreamBus.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalRuntime/LocalAIStreamBus.swift)
- [deeptutor/core/stream_bus.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/core/stream_bus.py)

当前 iOS 已实现：

- `emitSession`
- `emitThinking`
- `emitProgress`
- `emitStageStart`
- `emitStageEnd`
- `emitContent`
- `emitToolCall`
- `emitToolResult`
- `emitSources`
- `emitWaitForInput`
- `emitError`
- `emitDone`

当前服务端已实现：

- `content`
- `thinking`
- `observation`
- `tool_call`
- `tool_result`
- `progress`
- `sources`
- `result`
- `error`
- `wait_for_input`
- `stage(...)`
- subscriber replay / history / input listeners

结论：

> iOS 本地 `StreamBus` 在事件类型表面上已经追上大半，但在“事件回放、历史订阅、等待输入监听、result 事件、observation 事件、trace metadata 合并”这些运行时细节上仍没有完全对齐。

### 14.7 `LocalCapabilityRouter` 代码级职责分析

文件：

- [LocalCapabilityRouter.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalRuntime/LocalCapabilityRouter.swift)

关键代码段与含义：

- 第 3-9 行
  - 当前只注册了一个 `LocalChatCapability`。
- 第 11-27 行 `execute`
  - 虽然可以识别：
    - `chat`
    - `auto`
    - `deepSolve`
    - `deepResearch`
    - `visualize`
    - `masteryPath`
  - 但这些 capability 最终都落到同一个 `chatCapability.execute(...)`。

这意味着：

- 协议层已经允许 capability 枚举扩展。
- 执行层目前还没有真正的多 capability 分治。

所以当前状态只能判定为：

> “capability 路由骨架已建立，但 capability 真实分层尚未落地。”

### 14.8 `LocalChatCapability` 代码级职责分析

文件：

- [LocalChatCapability.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalCapabilities/LocalChatCapability.swift)

这是当前本地直连最核心的文件，也是“为什么现在有 Thinking 但还不完整、为什么能见到工具框架但工具没完全跑起来”的关键位置。

#### A. 初始化层

- 第 4-24 行
  - 注入：
    - `AIConfigCenter`
    - `LocalAIChatStreamClient`
    - `LocalWebTool`
    - `LocalMemoryTool`
    - `LocalRAGTool`
  - 结论：
    - 当前已经有真正的 Web/Memory/RAG 工具入口对象。
    - 但尚未看到 Exec/MCP 入口。

#### B. 本轮 capability 执行主流程

- 第 26-144 行 `execute(...)`
  - 第 33 行
    - 先根据 `LocalToolMountPolicy` 计算挂载工具。
  - 第 34-35 行
    - 建立 `LocalSourceCollector` 与文本累积器。
  - 第 37-40 行
    - 先发 `planning` 阶段开始、思考说明、工具挂载进度。
    - 这已经比旧版“只有 answer 文本”明显进步。
  - 第 43-48 行 Memory
    - 会发 `tool_call`
    - 调用 `memoryTool.recall(...)`
    - 再发 `tool_result`
    - 但当前 Memory 仍然只是占位摘要。
  - 第 50-56 行 RAG
    - 会发 `tool_call`
    - 调用 `ragTool.search(...)`
    - 再发 `tool_result`
    - 当前仍未接真实 KB 检索。
  - 第 58-80 行 Web
    - 这是当前最接近真实工具的部分。
    - 会发 `tool_call`
    - 真实调用 `webTool.search(...)`
    - 把结果交给 `sourceCollector`
    - 发 `tool_result`
    - 再发 `sources`
  - 第 82-83 行
    - 结束 `planning`，开始 `synthesis`
  - 第 85-91 行
    - 解析模型配置，失败则回退 stub。
  - 第 93-127 行
    - 如果 endpoint 不是 `local`，则进入 `streamAgenticSynthesis(...)`
  - 第 129-143 行
    - 否则走 stub 文本回答

这一段的真实结论非常关键：

> 当前本地模式已经不再是“纯文本直连”。它已经具备前置工具阶段、sources 收集、stage/progress/thinking 发射和 tool-aware synthesis 的雏形。

但同时也必须如实写出：

- Memory 仍是占位。
- RAG 仍是占位。
- Exec 不存在。
- MCP 不存在。
- capability 仍然共享同一个执行器。
- 真实 tool loop 只对 `ask_user` 做了特殊处理。

#### C. 真正的 agentic synthesis 循环

- 第 154-216 行 `streamAgenticSynthesis(...)`

这一段是当前 iOS 本地直连与 DeepTutorSerevr 最接近的地方，也是最大的差距所在。

- 第 162-163 行
  - 先构建 messages 与 tools schema。
- 第 165-167 行
  - 设置最多 4 轮 tool iteration。
- 第 172-185 行
  - 调用 `streamClient.streamCompletion(config:messages:tools:)`
  - 对返回块做三类处理：
    - `thinking`
    - `content`
    - `toolCall`
- 第 193-195 行
  - 如果这一轮没有工具调用，就退出循环。
- 第 197-212 行
  - 对每个 toolCall：
    - 先发 `tool_call`
    - 如果是 `ask_user`
      - 解析参数
      - 发 `wait_for_input`
      - 立刻暂停并返回
    - 否则
      - 当前统一写成“本地运行时中尚未实现完整执行器”
      - 发失败型 `tool_result`
      - 再把这段失败摘要作为 tool message 塞回模型上下文

这就是当前问题的最核心根源：

> 当前模型流里虽然已经能解析出 tool call，但除了 `ask_user` 以外，其他模型触发的工具调用都没有真正执行器，只会变成“记录调用参数 + 返回未实现摘要”。

换句话说：

- `thinking` 已经开始接了。
- `tool_call` 已经开始接了。
- `ask_user` 已经开始接了。
- 但 `tool execution dispatch` 还没有真正落地。

这正是用户看到“本地没有真正起工具”的直接原因。

#### D. messages 构建逻辑

- 第 218-246 行 `buildMessages(...)`
  - 系统提示里明确写了：
    - 信息不足时调用 `ask_user`
    - 不要编造来源
  - 会把前置工具结果块拼进系统提示。
  - 会把 `supplementalUserReply` 拼进系统提示。
  - 会把历史消息按角色还原。

这说明当前本地模式已经不是无脑 prompt，而是在模拟服务端 capability 的上下文合成。

#### E. OpenAI tool schema 暴露逻辑

- 第 248-278 行 `openAIToolSchemas(...)`
  - 目前只真正向模型暴露了一个函数：
    - `ask_user`

这意味着：

- 即使本地前置阶段手动执行了 Web/Memory/RAG，
- 在模型自由 tool-calling 阶段里，它真正“知道自己可以主动调用”的工具只有 Ask User。

这也是为什么当前“工具链路没有完全起来”。

### 14.9 `LocalAIChatStreamClient` 代码级职责分析

文件：

- [LocalAIChatStreamClient.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalAIChatStreamClient.swift)

关键变化和当前结论：

- 第 26-31 行
  - 现在的流式 chunk 已支持：
    - `thinking`
    - `content`
    - `toolCall`
- 第 49-74 行
  - `streamCompletion(config:messages:tools:)` 已支持携带 OpenAI tool schema。
- 第 123-143 行
  - 请求体已支持 `"tools"` 与 `"tool_choice": "auto"`。
- 第 158-168 行
  - 已有工具流增量累积器 `LocalToolCallStreamAccumulator`。
- 第 186-218 行
  - SSE 解析已支持：
    - `delta.reasoning_content`
    - `delta.thinking`
    - `delta.content`
    - `delta.tool_calls`
    - `message.tool_calls`

这意味着旧判断“本地 API 分支只能解析文本流”也已经过时。

现在更准确的判断应该是：

> 本地 API 分支已经能够解析 thinking 与 tool_calls，但上层只有 Ask User 被真正消费，其余工具没有执行调度器，因此表现仍不完整。

### 14.10 `AIStartTurnPayload` 代码级职责分析

文件：

- [AIChatProtocolModels.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Domain/AIChatProtocolModels.swift)

关键代码段与含义：

- 第 23-35 行
  - `AIStartTurnPayload` 已具备：
    - `capability`
    - `tools`
    - `knowledge_bases`
    - `language`
    - `config`
    - `persona`
    - `llm_selection`
    - `client_message_id`
- 第 68-95 行 `localTurn(...)`
  - 本地模式现在已经会根据设置生成：
    - 默认 `ask_user`
    - 默认 `memory`
    - 按设置追加 `web_search`
    - 按设置追加 `rag_search`

这同样说明旧结论“local 起 turn 永远 tools = []”已经不再准确。

但仍有真实缺口：

- `chatTurn()` 与 `p1Minimal()` 仍是服务端模式老写法。
- `knowledgeBases` 仍为空数组。
- `config/persona/llm_selection` 还没有对本地 capability 形成完整驱动。
- tool 名称只覆盖少量映射，未与 DeepTutorSerevr registry 全面对齐。

## 15. 与 DeepTutorSerevr 的逐层偏差校正

前面的文档与工单里，如果继续把本地模式描述成“只有文本流 + stub”，已经不完全符合当前代码事实。

更准确的现状应该修正为：

### 15.1 已经对齐到的层

- 已有本地统一上下文 `LocalAIUnifiedContext`
- 已有本地 TurnRuntimeManager `LocalTurnRuntimeManager`
- 已有本地 capability router `LocalCapabilityRouter`
- 已有本地 stream bus `LocalAIStreamBus`
- 已有本地 Ask User bridge `LocalAskUserBridge`
- 已有本地 source collector `LocalSourceCollector`
- 已有本地 tool mount policy `LocalToolMountPolicy`
- 已有本地模型流 tool-call/thinking 解析 `LocalAIChatStreamClient`

### 15.2 只对齐到骨架、未对齐到完整行为的层

- capability registry
  - 现在只是多 capability 名称共用同一个 `LocalChatCapability`
- tool registry
  - 现在没有 server 等价的统一 `ToolRegistry`
- tool execution dispatch
  - 当前只有 Web 前置执行、Ask User 动态处理
  - 其他模型主动工具调用没有真正执行器
- sources chain
  - 现在主要来源于 Web 搜索结果，RAG/Memory/Exec/MCP 没有统一来源注入
- wait_for_input runtime
  - 现在是本地 bridge 模式，不是服务端 reply queue / resume protocol 模式
- event replay / subscribe / result / observation
  - 仍未完整对齐 `StreamBus`

### 15.3 仍明显缺失的层

- Exec 工具
- MCP 工具
- 真正可执行的 Memory 工具
- 真正可执行的 RAG 工具
- 各 capability 独立执行器
- 与服务端同级的 configurable tools / builtin tools / deferred MCP surface
- 更完整的 tool schema 暴露

## 16. 每一个工具的当前实现与缺口

本节只谈 L1 工具，不谈 UI 卡片。

### 16.1 Ask User

当前代码位置：

- [LocalChatCapability.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalCapabilities/LocalChatCapability.swift)
- [LocalAskUserTool in LocalAgentTools.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalTools/LocalAgentTools.swift)
- [LocalAskUserBridge.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalRuntime/LocalAskUserBridge.swift)

当前怎么工作：

1. `LocalToolMountPolicy` 默认挂载 `askUser`
2. `LocalChatCapability.openAIToolSchemas(...)` 向模型声明 `ask_user`
3. 模型流里如果返回 `tool_call(name=ask_user)`
4. `streamAgenticSynthesis(...)` 会特殊处理它
5. 解析参数为 `intro + questions`
6. 发出 `wait_for_input`
7. `LocalAskUserBridge.markWaiting(turnID:)`
8. 用户提交回答后，Repository 重新调用 `resumeAfterUserReply`

当前问题：

- 这是唯一被真正动态执行的工具。
- 但它仍没有服务端那种统一 pause/resume bus。
- `consumeReply(for:)` 目前没有形成复杂 listener 模式。
- 续接是“重新跑一轮 capability”，不是恢复到 server 的运行帧。

### 16.2 Web

当前代码位置：

- [LocalAgentTools.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalTools/LocalAgentTools.swift)
- [LocalChatCapability.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalCapabilities/LocalChatCapability.swift)
- [LocalSourceCollector.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalRuntime/LocalSourceCollector.swift)

当前怎么工作：

1. `LocalToolMountPolicy` 根据 `snapshot.searchToolPreferences.useSearch` 决定是否挂载 `web`
2. 在 capability 前置 planning 阶段，直接调用 `webTool.search(...)`
3. 真实走 `WebSearchGateway`
4. 返回 `WebSearchResponse`
5. `LocalSourceCollector.addWeb(...)` 把结果转成 `AISourceReference`
6. 发 `tool_result`
7. 发 `sources`
8. 同时把 `response.markdown` 塞进后续 synthesis 上下文

当前问题：

- 这是当前最接近真实的本地工具。
- 但它是“前置执行型工具”，不是“模型在 loop 中自由调度型工具”。
- 模型侧目前并没有 `web_search` 的 OpenAI schema，因此模型主动调用 Web 的能力并未真正建立。
- 与 DeepTutorSerevr 的统一 registry + prompt hints + schema build 仍有明显差距。

### 16.3 Memory

当前代码位置：

- [LocalAgentTools.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalTools/LocalAgentTools.swift)

当前怎么工作：

1. `LocalToolMountPolicy` 默认挂载 `memory`
2. planning 阶段会发 `tool_call(memory)`
3. 调用 `memoryTool.recall(...)`
4. 返回固定摘要：
   - 本地 Memory 工具尚未接入服务端记忆索引，本轮跳过

当前问题：

- 已有工具位。
- 没有真实记忆检索。
- 没有 source references。
- 没有写回记忆能力。
- 与 DeepTutorSerevr 的 `read_memory/write_memory` 语义完全不等价。

### 16.4 RAG

当前代码位置：

- [LocalAgentTools.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalTools/LocalAgentTools.swift)

当前怎么工作：

1. `LocalToolMountPolicy` 根据 `useKnowledge` 决定是否挂载 `rag`
2. planning 阶段会发 `tool_call(rag)`
3. 调用 `ragTool.search(...)`
4. 当前返回固定摘要：
   - 本地 RAG 检索尚未接入知识库执行器，本轮跳过

当前问题：

- 已有工具位。
- 没有真实知识库索引。
- `knowledgeBases` 虽有字段，但没有真正驱动检索执行器。
- 没有返回来源、片段、分段引用。
- 与 DeepTutorSerevr 的 RAG 能力只对齐了协议名，没有对齐执行面。

### 16.5 Exec

当前代码位置：

- 当前本地 iOS 链路中未发现本地 Exec 工具实现入口。

当前问题：

- `LocalToolKind` / `LocalToolMountPolicy` / `LocalChatCapability` 未建立完整 Exec 路径。
- 没有任何安全边界、沙箱、执行策略、结果映射。
- 与 DeepTutorSerevr 的 sandbox / exec 工具完全未对齐。

### 16.6 MCP

当前代码位置：

- 当前本地 iOS 链路中未发现本地 MCP bridge 执行器。

当前问题：

- 没有 deferred tools surface。
- 没有 provider identity。
- 没有 grant/allowlist。
- 没有 schema build 与执行代理。
- 与服务端 `tool_options.py` 的 `mcp_tools` 面完全未建立。

## 17. DeepTutorSerevr 每个工具使用方式对 iOS 的对齐要求

这一节不只是列名称，而是明确“服务端为什么能跑起来，本地为什么现在跑不起来”。

### 17.1 服务端工具不是直接写死在 capability 里

服务端关键代码：

- [tool_registry.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/runtime/registry/tool_registry.py)
- [tool_options.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/api/utils/tool_options.py)
- [orchestrator.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/runtime/orchestrator.py)

服务端的真实模式是：

1. `ToolRegistry` 统一注册所有 built-in / plugin / deferred 工具
2. capability 按上下文挑选可用工具
3. registry 构建 OpenAI schema
4. 模型返回 tool_call
5. runtime 通过 registry 找到真实执行器
6. 结果再通过 `StreamBus.tool_result(...)` 回流

这和当前 iOS 最大的差异是：

- iOS 目前没有统一 registry
- 没有“tool name -> concrete executor”的中心调度
- 只有少量前置工具与一个 ask_user 特判

### 17.2 服务端工具面分成三层

从 `tool_options.py` 可以确认，服务端工具面至少分成：

- `tools`
  - 用户可切换的系统工具池
- `builtin_tools`
  - 自动挂载但可限制的内建工具
- `mcp_tools`
  - 由 provider 提供的延迟暴露工具

iOS 当前只有：

- 用户设置驱动的 `web/rag`
- 默认挂载的 `memory/askUser`

缺少：

- builtin tools 明确分层
- mcp tools surface
- provider identity
- 配置授权面

### 17.3 iOS 要真正对齐时，工具调度必须从“if/else”升级成 registry

建议必须落成：

```text
LocalToolRegistry
  - register(definition, executor)
  - enabledTools(context, snapshot)
  - openAISchemas(enabledTools)
  - execute(toolCall, context, snapshot)
```

至少要把以下职责从 `LocalChatCapability` 拆出去：

- tool schema 拼装
- tool name 解析
- tool executor 分发
- tool result -> sources 收口
- failed / terminal / retry 分类

如果继续把所有工具都写在 `LocalChatCapability` 里：

- capability 代码会越来越臃肿
- 多 capability 无法复用
- Exec/MCP 很难接入
- 无法对齐 DeepTutorSerevr registry 语义

## 18. 本工单需要追加的实施要求

### 18.1 文档结论修正

后续所有 P 文档与工单若再描述当前状态，必须统一改成以下表述：

- 不能再写：
  - “本地模式只有文本流”
  - “本地模式完全没有 Thinking/Tool 结构”
- 必须改写为：
  - “本地模式已经具备最小 runtime/capability/stream/tool skeleton，并已支持 thinking/tool_call/ask_user 的部分链路，但除 Web 前置执行和 Ask User 外，大多数工具仍未形成真实执行闭环。”

### 18.2 新增子任务建议

建议在本目录继续拆 4 个子工单：

1. `问题修复工单-本地 Tool Registry 对齐 DeepTutorSerevr.md`
2. `问题修复工单-本地 Capability Router 与 L2 能力分治.md`
3. `问题修复工单-本地 Web RAG Memory Exec MCP 工具执行器补齐.md`
4. `问题修复工单-本地 StreamBus 与 AskUser 恢复协议产品化.md`

### 18.3 本工单最终判断

截至 2026-08-01 当前代码事实，结论应该更新为：

1. 本地 iOS 直连不再是“纯文本流 demo”，已经有轻量 agent runtime 骨架。
2. Thinking 缺失问题已经从“完全没有”演进为“有事件入口，但深度、来源和时机仍未完全对齐 DeepTutorSerevr”。
3. 工具缺失问题已经从“完全不能发工具事件”演进为“有挂载、有前置调用、有 tool_call 解析，但缺少统一 registry 和完整执行闭环”。
4. 真正的核心缺口不再只是 UI 或事件协议，而是：
   - registry
   - capability 分治
   - tool execution dispatch
   - richer source/memory/rag/mcp/exec runtime
