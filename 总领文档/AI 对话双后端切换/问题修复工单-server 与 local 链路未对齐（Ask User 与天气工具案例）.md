# 问题修复工单-server 与 local 链路未对齐（Ask User 与天气工具案例）

## 1. 背景

当前 `AI 对话双后端切换` 已经支持：

- `server` 模式走 DeepTutorSerevr `WebSocket + TurnRuntimeManager + ChatOrchestrator + StreamBus`
- `local` 模式走 iOS 本地 `Repository + Runtime + Capability + ToolRegistry + StreamBus`

表面上看，两条链路都能：

- 展示思考
- 展示工具调用
- 展示来源
- 进入 `wait_for_input`
- 提交 Ask User 回答

但用户给出的真实联调截图已经说明：

> `server` 和 `local` 并不是“同一条能力链路的两个部署位置”，而是“行为顺序、工具调度方式、Ask User 语义、Thinking 暴露方式都明显不同的两套实现”。

本工单聚焦一个非常具体、非常典型的案例：

- 用户问题：`今天的天气怎么样？先使用工具，问问我在哪个城市。`
- 目标行为：先用 `ask_user` 询问城市，再基于城市执行天气查询与结果整理
- 当前现象：`server` 与 `local` 的执行顺序、日志内容、问答卡片、来源与最终回答完全不一致

本工单目标是：

1. 基于真实代码找出 `server` 与 `local` 没有对齐的部分。
2. 对天气案例的整条链路做逐段代码分析。
3. 明确哪些地方是协议没对齐，哪些地方是运行时没对齐，哪些地方是工具调度没对齐。
4. 形成新的修复基线，而不是继续把 `local` 视为“只差一点点 UI”。

## 2. 用户提供的现象证据

### 2.1 server 模式截图现象

从截图可见，`server` 模式下的行为顺序是：

1. 先思考：`我将询问用户所在的城市。`
2. 触发“向你提问”
3. 用户回答后，再开始联网搜索
4. 再抓取网页、调整搜索、补来源
5. 最终给出天气表格、提示、来源与不确定性说明

这条链路说明 `server` 侧是：

- 先真正阻塞在 `ask_user`
- 再继续后续工具链
- 工具顺序由运行时动态决定
- 最终回答基于用户补充信息继续完成同一个 turn

### 2.2 local 模式截图现象

从截图可见，`local` 模式下的行为顺序是：

1. 一开始就显示：
   - `已挂载工具：ask_user, memory, rag_search, web_search`
   - `memory`
   - `rag search`
   - `来源`
   - `联网搜索`
2. 然后才进入 Ask User 等待状态
3. 思考区直接暴露了非常长的原始推理文本：
   - `用户现在需要我调用 ask_user 工具问他在哪个城市对吧？`
   - `先检查下 ask_user 的参数，required 是 intro 和 questions 对吧？`
   - `然后按照工具调用的格式来写，对吧？`

这条链路说明 `local` 侧是：

- 在没有拿到城市之前，已经先执行了一批 planning 工具
- Ask User 是在这批前置工具之后才触发
- Thinking 暴露的是更接近原始模型推理，而不是运行时整理后的思考事件
- Ask User 不是服务端那种“同 turn 暂停后恢复”，而是本地 runtime 的轻量桥接实现

## 3. 主结论

当前 `server` 与 `local` 没有对齐的核心，不是某一个字段、某一个卡片、某一个 reducer 分支，而是：

> `server` 是“运行时驱动的动态 agent loop”，`local` 目前仍然是“planning 前置执行 + 本地模型 loop + 局部 ask_user 特判”的混合实现。

所以两者会天然出现以下分叉：

1. 工具执行顺序不同
2. Ask User 触发时机不同
3. Ask User 暂停/恢复语义不同
4. Thinking 事件来源不同
5. Tool schema 完整度不同
6. Tool result 载荷结构不同
7. 同一问题的来源与最终答案构成不同

## 4. server 链路逐段代码分析

### 4.1 WebSocket 入口

文件：

- [unified_ws.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/api/routers/unified_ws.py)

关键代码：

- 第 121-132 行
  - `start_turn` / `message` 进入 `runtime.start_turn(msg)`
  - 然后立即订阅 turn 事件
- 第 233-275 行
  - `submit_user_reply`
  - 把用户回答送入 `runtime.submit_user_reply(...)`
- 第 299-320 行
  - `user_input`
  - 直接交给 turn 对应的活跃 `StreamBus`

含义：

- `server` 的 Ask User 并不是前端本地凑出来的。
- 它绑定在一个真实活跃 turn 上。
- 用户回答不是重新起一个本地流程，而是回填到原 turn 的运行时。

### 4.2 TurnRuntimeManager 的暂停恢复语义

文件：

- [turn_runtime.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/services/session/turn_runtime.py)

关键代码：

- 第 933-957 行附近
  - `submit_user_reply(...)` 把 `text/answers` 放进 `_reply_queues[turn_id]`
  - 这是 turn 级回复队列
- 第 1151-1163 行附近
  - 每个 turn 在 `_run_turn` 前都会创建 `reply_queue`
  - `self._reply_queues[turn_id] = reply_queue`
- 第 1616-1624 行附近
  - `context.metadata["wait_for_user_reply"] = _wait_for_user_reply`
  - agentic pipeline 在 `ask_user` 暂停时，等待的就是这个回调

含义：

- `server` 的 Ask User 是真实“同一回合暂停恢复”。
- pause/resume 不是模拟。
- 用户回答不会重启一个新编排，而是继续原 loop。

### 4.3 server 的 ask_user 工具定义

文件：

- [deeptutor/tools/builtin/__init__.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/tools/builtin/__init__.py)
- [deeptutor/tools/ask_user.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/tools/ask_user.py)

关键代码：

- `builtin/__init__.py` 第 1193-1295 行
  - 定义了完整 `ask_user` schema
  - `questions` 必填
  - `intro` 可选
  - question 支持：
    - `prompt`
    - `header`
    - `options`
    - `multi_select`
    - `id`
    - `allow_free_text`
    - `placeholder`
- 第 1297-1320 行
  - `execute()` 调用 `build_ask_user_payload(...)`
  - 返回 `ToolResult`
  - `metadata={"ask_user": payload_dict}`
  - `pause_for_user=payload_dict`

`ask_user.py` 关键点：

- 会对 payload 做完整规范化
- 支持 legacy shape 自动归一
- 支持 option label/description
- 去重“Other”
- 自动补 question id
- 限制 question 数量、长度、header 长度、placeholder 长度

含义：

- `server` 的 ask_user 不只是一个 schema，而是一个完整的“参数校验 + 规范化 + pause_for_user 语义”工具。
- 前端消费的是服务端真实 `tool_result.metadata.ask_user` 与 `wait_for_input` 事件。

## 5. local 链路逐段代码分析

### 5.1 local 会话入口

文件：

- [LocalAIChatRepository.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalAIChatRepository.swift)

关键代码：

- 第 108-149 行
  - `startTurn` 里创建本地会话、写用户消息、创建 turnID、组装 `LocalAIUnifiedContext`
  - 然后异步执行 `runTurn(context:)`
- 第 181-210 行
  - `submitUserReply` / `sendUserInput`
  - 回答不是送入活跃 `StreamBus`
  - 而是由 repository 持有 `activeTurnContext` 后再续接
- 第 361-415 行
  - `resumeTurnAfterUserReply(...)`
  - 最终是重新走 `runtime.resumeAfterUserReply(...)`

含义：

- `local` 并没有服务端那种 turn 级 reply queue。
- Ask User 恢复不是 server 那种“同 loop 恢复”，而是把补充信息重新并入上下文，再执行一次 capability。

### 5.2 local runtime 入口

文件：

- [LocalAIChatRuntime.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalAIChatRuntime.swift)
- [LocalTurnRuntimeManager.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalRuntime/LocalTurnRuntimeManager.swift)

关键代码：

- `LocalAIChatRuntime.swift` 第 27-33 行
  - `runTurn` 把执行交给 `LocalTurnRuntimeManager.startTurn(...)`
- `LocalTurnRuntimeManager.swift` 第 19-35 行
  - 先创建 `LocalAIStreamBus`
  - 发 `session`
  - 再交给 `LocalCapabilityRouter.execute(...)`
- 第 38-46 行
  - 恢复时直接 `context.withSupplementalReply(replyText)` 后重新 `startTurn`

含义：

- `local` 已经有本地 runtime manager 骨架。
- 但 Ask User 的恢复语义仍然是“重新起一遍 capability 执行”，不是服务端 queue resume。

### 5.3 local capability 主链路

文件：

- [LocalChatCapability.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalCapabilities/LocalChatCapability.swift)

这是这次天气案例最核心的分叉点。

#### A. 先 planning，后 synthesis

关键代码：

- 第 42-44 行
  - 一开始就发：
    - `planning`
    - `thinking`
    - `已挂载工具...`
- 第 48-80 行
  - 会先遍历 `registry.planningDefinitions(for: mountedTools)`
  - 对每个 planning tool 先发 `tool_call`
  - 再执行本地工具
  - 再发 `tool_result`
  - 如果有来源再发 `sources`

含义：

- `local` 当前是固定先走 planning。
- 不是像 `server` 那样先由 agent loop 决定“现在最该问用户还是最该搜索”。

#### B. Ask User 发生在 planning 之后

关键代码：

- 第 93-104 行
  - planning 完成后，才进入 `streamAgenticSynthesis(...)`
- 第 206-215 行
  - 如果模型在 loop 中返回 `ask_user`
  - 才发 `wait_for_input`
  - 然后 `pausedForUserInput = true`

含义：

- `local` 的 Ask User 是“planning 后置 ask_user”
- `server` 的 Ask User 是“agent loop 当前步动态决策 ask_user”

这正是天气案例里最大的不对齐点。

## 6. 天气案例为什么在 local 会跑偏

### 6.1 planning 固定顺序导致先搜错问题

文件：

- [LocalToolRegistry.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalRuntime/LocalToolRegistry.swift)
- [LocalToolRegistryFactory.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalRuntime/LocalToolRegistryFactory.swift)
- [LocalToolExecutors.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalTools/LocalToolExecutors.swift)

关键代码：

- `LocalToolRegistry.swift` 第 12-23 行
  - planning 顺序被写死为：
    - `memory -> rag -> web`
- `LocalToolRegistryFactory.swift` 第 14-18 行
  - `memory` 注册为 planning-only
- 第 40-50 行
  - `rag` 同时支持 planning + agentic
- 第 52-56 行
  - `web` 注册为 planning-only
- `LocalToolExecutors.swift` 第 128-149 行
  - `rag` / `web` planning 参数都是：
    - `query = context.userMessage`

也就是说，在用户说：

```text
今天的天气怎么样？先使用工具，问问我在哪个城市。
```

时，`local` 会：

1. 直接用整句原文去做 `rag/web` planning 查询
2. 此时根本还没有城市
3. 搜索条件天然不充分
4. 然后才在后面的 synthesis 中补一个 `ask_user`

这就是截图里出现：

- 先 `memory`
- 再 `rag search`
- 再 `来源`
- 再 `联网搜索`
- 最后才进入等待回答

的直接代码原因。

### 6.2 server 不会这样做

服务端不是固定 planning 顺序。

原因：

- `server` 由 capability + tool registry + orchestrator + agent loop 动态决定下一步
- `ask_user` 可以在当前最合适的时候先发生
- `web` 搜索不会被本地固定顺序硬编码提前触发

所以在天气案例里，`server` 能先问城市，再搜索天气。

## 7. Ask User schema 没有完全对齐

### 7.1 server ask_user schema 更完整

服务端定义见：

- [builtin/__init__.py](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/deeptutor/tools/builtin/__init__.py:1193)

支持：

- `intro` 可选
- `questions` 必填
- question 支持：
  - `prompt`
  - `header`
  - `options`
  - `multi_select`
  - `id`
  - `allow_free_text`
  - `placeholder`

### 7.2 local ask_user schema 过窄

文件：

- [LocalToolRegistry.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalRuntime/LocalToolRegistry.swift)

关键代码：

- 第 69-95 行
  - `askUserSchema` 当前只明确声明：
    - `intro`
    - `questions`
    - question item 只列出：
      - `id`
      - `prompt`
      - `allow_free_text`
  - 而且 `required = ["intro", "questions"]`

问题：

1. `server` 里 `intro` 是可选，`local` 却把 `intro` 写成必填
2. `server` schema 显式支持 `header/options/multi_select/placeholder`
3. `local` schema 没把这些核心字段完整暴露给模型

结果：

- 弱模型更容易产出不完整 ask_user 参数
- 即使本地 parser 能吃更多字段，schema 本身也没有正确引导模型输出完整结构

## 8. local 的 Ask User 是“特判”，不是完整工具语义

文件：

- [LocalChatCapability.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalCapabilities/LocalChatCapability.swift)

关键代码：

- 第 206-215 行
  - 当 `toolName == ask_user`
  - 直接：
    - 解析参数
    - `emitWaitForInput`
    - 返回 `pausedForUserInput = true`

但这里没有：

- 像 server 那样产出标准 `ToolResult(metadata.ask_user=payload, pause_for_user=payload)`
- 像 server 那样由 turn runtime 把“暂停等待用户回答”作为 tool result 语义来处理
- 像 server 那样统一进入 reply queue

结论：

> `local` 目前把 ask_user 作为 capability 内部特判，而不是 server 那种真正注册在 tool runtime 里的 pause-capable tool。

## 9. wait_for_input 事件虽然能渲染，但来源语义仍不同

### 9.1 UI 能吃两种来源

文件：

- [AIChatMessageSegment.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Domain/AIChatMessageSegment.swift)
- [AIChatEventReducer.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Application/AIChatEventReducer.swift)

关键代码：

- `AIChatMessageSegment.swift` 第 92-104 行
  - 支持从 `tool_result.metadata.tool_metadata.ask_user` 解析 Ask User 卡
- 第 106-117 行
  - 也支持从 `wait_for_input` 直接解析 Ask User 卡
- `AIChatEventReducer.swift` 第 177-193 行
  - 收到 `wait_for_input` 后会置 `waitingForUser`
  - 并设置 `pendingAskUserCard`

这说明：

- iOS UI 兼容了 server 路线和 local 路线两种来源
- 但兼容渲染不等于语义对齐

### 9.2 当前 local 主要走的是 wait_for_input 直接成卡

本地当前并没有像 server 那样稳定地输出：

- `tool_result.metadata.tool_metadata.ask_user`

而是更多依赖：

- `emitWaitForInput(intro:questions:)`

这会导致：

- 工具调用日志与卡片来源割裂
- 事件时间线与 tool result 的因果关系不如 server 完整
- “这是一个工具暂停结果”与“这是一个前端等待态”没有完全绑定

## 10. Thinking 没有对齐

### 10.1 local 直接暴露模型原始 thinking

文件：

- [LocalAIChatStreamClient.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalAIChatStreamClient.swift)
- [LocalChatCapability.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalCapabilities/LocalChatCapability.swift)

关键代码：

- `LocalAIChatStreamClient.swift` 第 186-198 行
  - 解析：
    - `delta.reasoning_content`
    - `delta.thinking`
    - `delta.tool_calls`
- `LocalChatCapability.swift` 第 181-193 行
  - 对 `thinking` 直接 `bus.emitThinking(text)`

结果就是截图中出现的原始 thinking：

- `用户现在需要我调用 ask_user 工具问他在哪个城市对吧？`
- `先检查下 ask_user 的参数...`
- `然后按照工具调用的格式来写...`

### 10.2 server Thinking 更接近运行时整理后的事件

服务端虽然也有 thinking 事件，但它来自：

- capability / runtime / stream_bus 的统一发射

不是简单把本地兼容模型的原始推理文本逐字外露。

所以两者表现差异是：

- `server` 更像“产品化后的思考事件”
- `local` 更像“原始模型 reasoning transcript”

## 11. submit_user_reply / user_input 语义没有对齐

### 11.1 server

文件：

- [AIChatRepository.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/AIChatRepository.swift)
- [AIChatWebSocketConnection.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/AIChatWebSocketConnection.swift)
- [AIChatProtocolModels+Outbound.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Domain/AIChatProtocolModels+Outbound.swift)

关键代码：

- `AIChatRepository.swift` 第 158-164 行
  - `submitUserReply` 走 websocket `submit_user_reply`
  - `sendUserInput` 走 websocket `user_input`
- `AIChatWebSocketConnection.swift` 第 30-37 行
  - 正式编码为 ws payload
- `AIChatProtocolModels+Outbound.swift` 第 39-63 行
  - `submit_user_reply` 与 `user_input` 都是协议的一部分

### 11.2 local

文件：

- [LocalAIChatRepository.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalAIChatRepository.swift)
- [LocalAskUserBridge.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Infrastructure/LocalRuntime/LocalAskUserBridge.swift)

关键点：

- 本地没有 websocket
- 没有活跃 `StreamBus.get_bus(turn_id)`
- 没有服务端 reply queue
- 只是：
  - `markWaiting(turnID)`
  - `submitReply(turnID,text)`
  - 然后 repository 再 `resumeAfterUserReply`

结论：

> `server` 和 `local` 虽然都能叫 “submit user reply”，但底层根本不是同一种恢复模型。

## 12. 本案例里没有对齐的部分清单

### 12.1 工具调度顺序未对齐

- `server`
  - 动态 agent loop 决定先 ask_user 还是先 web
- `local`
  - 固定先 `memory -> rag -> web`
  - 再进入 ask_user

### 12.2 ask_user schema 未对齐

- `server`
  - `intro` 可选
  - question schema 完整
- `local`
  - `intro` 被错误声明为必填
  - 问题对象字段暴露不完整

### 12.3 ask_user 工具语义未对齐

- `server`
  - ask_user 是正式 tool
  - 返回 `pause_for_user`
- `local`
  - ask_user 是 capability 内部特判

### 12.4 wait_for_input 恢复机制未对齐

- `server`
  - reply queue + original turn resume
- `local`
  - bridge + context 补充 + capability re-run

### 12.5 Thinking 事件来源未对齐

- `server`
  - 运行时整理后的事件
- `local`
  - 直接暴露原始 reasoning

### 12.6 ToolResult 事件结构未完全对齐

- `server`
  - 可从 `tool_result.metadata.tool_metadata.ask_user` 构卡
- `local`
  - 当前主要依赖 `wait_for_input` 直接构卡

### 12.7 天气场景下 query 构造未对齐

- `server`
  - 可以等到获得城市后再搜天气
- `local`
  - planning 阶段直接对整句用户原文做 web/rag 查询

## 13. 修复要求

### 13.1 第一优先级：取消“先 planning 再 ask_user”的硬顺序

至少在 `Chat/Auto` 本地 capability 中，不能对所有回合无脑先跑：

- memory
- rag
- web

应改为：

- 先由模型或 policy 判断是否缺关键参数
- 若缺关键参数，先 ask_user
- 用户回复后，再执行 web/rag 等下游工具

### 13.2 第二优先级：本地 ask_user schema 对齐服务端

需要把本地 `askUserSchema` 至少补齐到：

- `intro` 可选
- `questions` 必填
- item 包含：
  - `prompt`
  - `header`
  - `options`
  - `multi_select`
  - `id`
  - `allow_free_text`
  - `placeholder`

### 13.3 第三优先级：本地 ask_user 改成真正的 registry tool 语义

本地不要继续只靠：

- `if toolName == "ask_user" { ... emitWaitForInput ... }`

应升级为：

- registry 中定义 ask_user executor / pause contract
- tool_result 挂载标准 ask_user payload
- runtime 统一处理 pause/resume

### 13.4 第四优先级：Thinking 产品化收敛

本地不能把兼容模型的原始 reasoning 逐字透出到用户日志。

至少需要：

- thinking 文本裁剪
- 内部 prompt/schema 自检内容过滤
- call construction 自言自语过滤
- 与 server 一致的状态话术收敛

## 14. 建议新增实现任务

建议基于本工单继续拆 3 个子工单：

1. `问题修复工单-local Ask User Schema 与 Pause 语义对齐 server.md`
2. `问题修复工单-local Planning 顺序改造为动态 Tool Policy.md`
3. `问题修复工单-local Thinking 过滤与日志产品化对齐 server.md`

## 15. 验收标准

### 15.1 天气案例验收

输入：

```json
{
  "questions": [
    {
      "header": "所在城市",
      "prompt": "请问你在哪个城市？我好帮你查询今天的天气。",
      "options": [
        {
          "label": "北京",
          "description": "查询北京今天的天气"
        },
        {
          "label": "上海",
          "description": "查询上海今天的天气"
        },
        {
          "label": "广州",
          "description": "查询广州今天的天气"
        },
        {
          "label": "深圳",
          "description": "查询深圳今天的天气"
        }
      ]
    }
  ]
}
```

验收要求：

- `local` 首轮不能在未获得城市前就先跑天气搜索
- `local` 首轮必须优先 ask_user
- 用户回答后，同一 turn 继续执行下游工具
- 工具时间线顺序与 `server` 语义一致：
  - ask_user
  - user reply
  - web / fetch / source
  - answer

### 15.2 Thinking 验收

- `local` 不再显示原始“先检查 schema/required 是不是...”这类内部推理
- `local` 的 thinking 文案与 `server` 保持同等级别的产品化表达

### 15.3 Ask User 验收

- `local` ask_user schema 与 server 一致
- `local` card 既可以从 `tool_result.metadata.ask_user` 构建
- 也可以兼容 `wait_for_input`
- 但主链路应优先走与 server 一致的 tool result 语义

## 16. 最终结论

当前 `server` 和 `local` 最大的问题不是“功能名称一样但实现细节略有不同”，而是：

> `server` 是基于真实 turn runtime 的动态 agent pipeline，`local` 当前仍然是“固定 planning 前置 + 本地 ask_user 特判 + 重新执行 capability 恢复”的混合链路。

这会直接导致：

- 天气案例工具顺序错位
- Ask User 时机错位
- Thinking 暴露过深
- 结果来源与最终答案不一致

因此，本问题必须作为新的独立修复工单处理，不能再归为“P3 复杂事件补一点细节”。
