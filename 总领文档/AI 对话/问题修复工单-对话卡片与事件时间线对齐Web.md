# 问题修复工单 - 对话卡片与事件时间线对齐 Web

## 1. 工单目标

将 iOS 端对话页的消息卡片、顶部状态条、事件时间线、输入区与整体页面密度，对齐到 Web 端的真实体验，而不是只保留“看起来像聊天页”的外观。

本工单只描述 iOS SwiftUI 的对齐方案，不修改业务代码，不改动后端协议，不涉及 HarmonyOS、Android。

## 2. 问题结论

从当前截图对比可以直接确认：

1. iOS 端的事件时间线占据了过大的垂直空间，严重挤压消息正文。
2. iOS 端把推理、进度、阶段、结果等事件渲染成了低密度的“调试列表”，而 Web 端更像是一个收敛后的“对话卡片内事件面板”。
3. iOS 端的状态条、事件区、消息正文之间的层级关系不稳定，导致用户先看到的是事件噪音，再看到答案正文。
4. iOS 端的整体视觉节奏比 Web 更松、更空，缺少 Web 端那种紧凑、连续、可回看的一体化卡片感。

结论是：当前差距已经不是单个控件的样式偏差，而是信息架构和组件职责分配发生了偏移。

## 3. Web 端预期特征

Web 端的对话体验更接近以下语义：

- 顶部有轮次状态摘要
- `thinking` / 事件时间线是卡片内的一部分
- 完成后仍可展开查看过程
- 事件区是“辅助理解的折叠层”，不是主视觉焦点
- 最终回答始终是主内容
- 输入区紧贴页面底部，卡片内容与输入区之间留白受控

## 4. iOS 当前偏差

### 4.1 事件区过大

iOS 当前的事件时间线把每个阶段拆得过细，且每条事件的视觉体积偏大，造成：

- 一屏内只能看到少量正文
- 用户需要反复滚动才能回到答案
- 事件本应是辅助信息，却抢占了主内容优先级

### 4.2 事件语义过“调试化”

截图中事件条目呈现为：

- `responding`
- `chat`
- `阶段开始`
- `进度`
- `阶段结束`
- `结果`

这说明当前实现更像把原始事件流直接铺到界面，而不是做过产品化聚合后的展示。

### 4.3 组件层级不稳定

当前卡片结构看起来像：

- 顶部状态条
- 大块事件列表
- 再往下才是正文

这和 Web 的“状态摘要 + 正文 + 可展开过程”顺序不一致。

### 4.4 页面密度偏松

iOS 目前存在大量：

- 空白过大
- 字号层级不收敛
- 行距和块间距偏散
- 事件列表上下文不紧凑

导致整页看上去更像“示意页”，不是正式产品页。

## 5. 根因分析

### 5.1 将事件流直接映射成列表

如果 reducer 或 ViewModel 把每个事件都单独渲染成一行，UI 就会天然膨胀。

正确做法应该是：

- 事件流先归并
- 再分组
- 再映射成面板结构

### 5.2 `thinking` 面板没有产品化收束

Web 端的事件面板更可能包含：

- 摘要
- 折叠态
- 展开态
- 分组态

iOS 当前缺少这些中间层，所以看起来更“长”和“散”。

### 5.3 消息正文没有保持主视觉优先级

在正确的结构里，答案正文应始终压过事件区。

当前 iOS 的表现是：

- 事件区先抢眼
- 正文被挤到下面
- 用户的阅读路径被打断

## 6. 优化方向

### 6.1 调整主次顺序

推荐顺序应改为：

1. 顶部状态条
2. 消息正文
3. 可展开的事件面板
4. 工具 / 来源 / 追问

这样用户先看答案，再看过程。

### 6.2 压缩事件时间线

事件时间线应做产品化聚合：

- 合并重复阶段
- 合并连续进度
- 工具调用与结果成对显示
- 来源引用集中展示
- 错误与恢复单独高亮

### 6.3 收敛字号、间距和留白

需要统一以下视觉规则：

- 事件行字重减弱
- 时间线节点尺寸减小
- 行距收紧
- 卡片内边距收敛
- 事件区和正文之间保持固定节奏

### 6.4 让正文始终成为主内容

最终回答必须：

- 视觉上更大
- 优先级更高
- 出现在事件面板之前或紧贴之后
- 不被调试信息稀释

## 7. SwiftUI 落地建议

### 7.1 组件重构方向

建议拆成以下层级：

- `AIChatTurnCard`
- `AIChatTurnHeader`
- `AIChatTurnStatusBar`
- `AIChatMessageBody`
- `AIChatThinkingPanel`
- `AIChatEventTimeline`
- `AIChatTimelineGroup`
- `AIToolTraceCard`
- `AISourceReferencesView`

### 7.2 事件分组策略

建议把原始事件归并成以下组：

- `thinking`
- `progress`
- `tool`
- `source`
- `question`
- `error`
- `result`

展示时不要每个原始事件都单独占据一行。

### 7.3 交互策略

- 默认收起事件面板，或仅显示摘要
- 用户需要时再展开完整时间线
- 完成后保留入口
- 恢复后保持折叠/展开状态
- 错误或追问时自动强调相关事件组

## 8. Plain Text 页面草图

### 8.1 目标结构

```text
┌──────────────────────────────────────────┐
│ 顶部状态条：已完成 · 4s                 │
├──────────────────────────────────────────┤
│ 最终回答正文                              │
│                                          │
│ ...                                      │
├──────────────────────────────────────────┤
│ thinking / event panel   [展开 / 收起]   │
│ - 阶段开始                              │
│ - 进度                                  │
│ - tool call / result                    │
│ - sources                               │
└──────────────────────────────────────────┘
```

### 8.2 当前偏差形态

```text
┌──────────────────────────────────────────┐
│ 顶部状态条                               │
├──────────────────────────────────────────┤
│ 超长事件列表                              │
│ 阶段开始                                 │
│ 进度                                     │
│ 进度                                     │
│ 阶段结束                                 │
│ 结果                                     │
├──────────────────────────────────────────┤
│ 最终回答正文                              │
└──────────────────────────────────────────┘
```

## 9. 验收标准

以下内容必须满足：

- Web 和 iOS 的主次层级一致
- 最终回答在视觉上是主内容
- 事件时间线不再占据过多垂直空间
- 同类事件会自动分组或收束
- 完成后仍可展开回看过程
- 恢复后事件区不丢失
- 页面密度与 Web 接近

## 10. 风险点

- 如果继续直接渲染原始事件流，UI 只会越来越长
- 如果不做事件归并，工具和进度会不断膨胀
- 如果正文和事件面板权重不调整，iOS 会一直像调试页
- 如果折叠状态不按 turn 记忆，刷新后体验会漂移

## 11. 待确认项

1. Web 端是否对事件时间线做了默认折叠。
2. Web 端是否把 tool / source / progress 做了分组。
3. 完成态是否允许只显示摘要，不默认展开全部过程。
4. 事件区是否允许在不同消息类型下使用不同密度。

## 12. 建议执行顺序

1. 先把事件流从“逐条列表”改成“分组面板”。
2. 再收紧卡片密度和字号。
3. 再调整消息正文与事件面板的顺序。
4. 最后统一恢复态、折叠态和完成态。

这样才能真正从“差很多”收敛到“是同一套产品语义”。

## 13. 关键技术与核心代码示例

以下代码仅用于说明职责骨架和状态流转，不是完整业务实现。

### 13.1 Turn 状态模型

```swift
enum AIChatTurnStatus: String, Codable {
    case thinking
    case streaming
    case completed
    case interrupted
    case waitingInput
    case failed
}
```

```swift
struct AIChatTurnViewState {
    var sessionID: String
    var turnID: String
    var status: AIChatTurnStatus
    var elapsedSeconds: Int
    var isThinkingExpanded: Bool
    var assistantText: String
    var thinkingEvents: [AIStreamEvent]
    var sourceItems: [AISourceReference]
    var pendingAskUserCard: AIAskUserCard?
}
```

### 13.2 Event Reducer 核心逻辑

```swift
func reduce(_ state: inout AIChatTurnViewState, event: AIStreamEvent) {
    switch event.type {
    case .thinking:
        state.status = .thinking
        state.thinkingEvents.append(event)

    case .content:
        state.status = .streaming
        state.assistantText += event.content ?? ""

    case .toolCall, .toolResult, .progress, .stageStart, .stageEnd:
        state.thinkingEvents.append(event)

    case .sources:
        state.thinkingEvents.append(event)
        state.sourceItems = parseSources(event)

    case .waitForInput:
        state.status = .waitingInput
        state.pendingAskUserCard = buildAskUserCard(event)

    case .error:
        state.status = .failed
        state.thinkingEvents.append(event)

    case .done:
        state.status = .completed

    case .unrecognized:
        state.thinkingEvents.append(event)
    }
}
```

### 13.3 顶部状态条

```swift
struct AIChatTurnStatusBar: View {
    let status: AIChatTurnStatus
    let elapsedSeconds: Int

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("· \(elapsedSeconds)s")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch status {
        case .thinking: return "思考中"
        case .streaming: return "响应中"
        case .completed: return "已完成"
        case .interrupted: return "已中断"
        case .waitingInput: return "等待输入"
        case .failed: return "失败"
        }
    }

    private var statusIcon: some View {
        Image(systemName: "sparkles")
    }
}
```

### 13.4 可展开 Thinking 面板

```swift
struct AIChatThinkingPanel: View {
    let events: [AIStreamEvent]
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack {
                    Text("thinking")
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(events.indices, id: \.self) { index in
                        AIChatEventRow(event: events[index])
                    }
                }
            }
        }
    }
}
```

### 13.5 对话卡片主结构

```swift
struct AIChatTurnCard: View {
    @State var state: AIChatTurnViewState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AIChatTurnStatusBar(
                status: state.status,
                elapsedSeconds: state.elapsedSeconds
            )

            Text(state.assistantText)
                .font(.body)
                .foregroundStyle(.primary)

            AIChatThinkingPanel(
                events: state.thinkingEvents,
                isExpanded: $state.isThinkingExpanded
            )

            if let askUser = state.pendingAskUserCard {
                AIAskUserCardView(card: askUser)
            }

            if !state.sourceItems.isEmpty {
                AISourceReferencesView(items: state.sourceItems)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}
```

### 13.6 恢复后保留 Thinking 的关键点

```swift
func restoreTurn(from cache: TurnCache) -> AIChatTurnViewState {
    AIChatTurnViewState(
        sessionID: cache.sessionID,
        turnID: cache.turnID,
        status: cache.status,
        elapsedSeconds: cache.elapsedSeconds,
        isThinkingExpanded: cache.isThinkingExpanded,
        assistantText: cache.assistantText,
        thinkingEvents: cache.thinkingEvents,
        sourceItems: cache.sourceItems,
        pendingAskUserCard: cache.pendingAskUserCard
    )
}
```

### 13.7 会话日志接入示例

```swift
struct SessionLogger {
    static func log(_ message: String,
                    sessionID: String? = nil,
                    turnID: String? = nil) {
        print("[AIChat] session=\(sessionID ?? "-") turn=\(turnID ?? "-") \(message)")
    }
}
```

```swift
SessionLogger.log("send_message begin", sessionID: state.sessionID, turnID: state.turnID)
SessionLogger.log("websocket connected", sessionID: state.sessionID, turnID: state.turnID)
SessionLogger.log("event received: thinking", sessionID: state.sessionID, turnID: state.turnID)
SessionLogger.log("turn completed", sessionID: state.sessionID, turnID: state.turnID)
```

### 13.8 这组代码的设计约束

- `done` 只改状态，不清空 `thinking`
- `thinking` 是 turn 级持久数据，不是一次性临时文本
- 顶部状态条绑定 turn 生命周期，不绑定单纯连接状态
- 事件时间线要先归并，再展示，不要直接把原始事件逐条铺出来

## 14. iOS 字节流式展示问题

### 14.1 现象

Web 端已经是完整产品态，消息正文、状态摘要、事件面板和展开逻辑都已经成型。

iOS 当前的问题是把“流式接收中的碎片”直接暴露给用户，表现为：

- 内容像字节流一样逐段冒出
- 事件面板展示的是未收束的中间态
- 同一轮对话的内容被拆成很多短行
- 用户看到的是流式过程，而不是完整消息

这会让 iOS 看起来不像“完整聊天产品”，更像“流式调试视图”。

### 14.2 根因判断

当前问题通常来自以下几种实现偏差：

1. 服务端事件到达后，没有先做内容聚合，就直接渲染。
2. `content`、`thinking`、`tool_call`、`tool_result` 没有按 turn 收束成一个完整卡片。
3. Markdown 或文本片段没有在最终态统一整理，而是边来边画。
4. 恢复流程只恢复了当前 chunk，没有恢复完整 turn 结构。
5. UI 直接消费底层流事件，缺少“消息成型”这一层。

### 14.3 Web 与 iOS 的职责差异

Web 端的职责更像：

- 接收事件流
- 聚合状态
- 成型消息卡片
- 再展示完整内容

iOS 目前更像：

- 接收事件流
- 直接把事件碎片渲染出来

这就是两端体验差距很大的核心原因。

### 14.4 正确的 iOS 处理链路

iOS 应该先把流式碎片收敛为 turn，再由 turn 驱动 UI：

1. 接收 byte chunk / event chunk
2. 解码成事件对象
3. 做 seq 去重和顺序整理
4. 聚合为 assistant draft、thinking draft、tool draft
5. 在 `done` 或恢复完成后固化为完整 turn
6. 由完整 turn 渲染卡片、状态条、事件面板

### 14.5 关键技术点

#### 14.5.1 不要直接展示底层 chunk

底层 chunk 只属于协议层，不属于 UI。

UI 应该只看到：

- 最终回答正文
- 可展开 thinking
- 归并后的工具和来源
- 可恢复的 turn 状态

#### 14.5.2 内容成型后再刷新

建议将更新节奏控制为：

- 流式阶段局部更新 draft
- 关键事件到达时刷新面板摘要
- 完成态时一次性固化最终结构

#### 14.5.3 恢复后重建完整 turn

恢复不能只重播最后几个 chunk，而要重建：

- turn status
- assistant body
- thinking panel
- tool trace
- source references
- pending question

### 14.6 SwiftUI 骨架示意

```swift
struct AIChatTurnDraft {
    var rawChunks: [String] = []
    var assistantText: String = ""
    var thinkingText: String = ""
    var toolEvents: [AIStreamEvent] = []
    var sourceItems: [AISourceReference] = []
    var isCompleted: Bool = false
}
```

```swift
func appendChunk(_ draft: inout AIChatTurnDraft, event: AIStreamEvent) {
    switch event.type {
    case .content:
        draft.rawChunks.append(event.content ?? "")
        draft.assistantText += event.content ?? ""

    case .thinking:
        draft.thinkingText += event.content ?? ""

    case .toolCall, .toolResult, .progress, .stageStart, .stageEnd:
        draft.toolEvents.append(event)

    case .sources:
        draft.sourceItems = parseSources(event)

    case .done:
        draft.isCompleted = true

    default:
        break
    }
}
```

### 14.7 UI 层的修正原则

- UI 不直接绑定 raw chunk
- UI 绑定的是成型后的 turn state
- 事件流只驱动 state，不直接驱动每一行文本
- 完成后保留完整消息，不保留碎片感
- 恢复后应显示“完整消息”，不是“继续吐字节流”

### 14.8 验收标准

以下现象必须消失：

- 同一条回答被拆成大量碎片行
- 事件面板呈现未收束的流式调试感
- 恢复后只看到半截内容
- 完成后仍然像在跑字节流

以下结果必须成立：

- iOS 看起来像完整聊天产品
- Web 和 iOS 的消息成型方式一致
- 流式细节只保留在面板中，不污染正文
- 完成态和恢复态都能展示完整 turn

## 15. iOS 回答正文必须完全对齐 Web

### 15.1 现象

从截图可以确认，Web 端的回答正文已经是完整成品态，具备以下特征：

- 有完整的开场句
- 有连续的解释段落
- 有明确的列表结构
- 有统一的语气和风格
- 有适度的 emoji 或符号点缀
- 有可直接阅读的自然语言节奏

iOS 端当前的问题是回答正文没有以完整成品的方式出现，而是更像：

- 流式片段的拼接结果
- 逐块吐出的字节流
- 事件驱动下的局部文本更新

这会导致用户看到的不是“回答”，而是“正在生成中的文本痕迹”。

### 15.2 Web 的完整回答特征

Web 端回答正文通常具备：

1. 开场明确。
2. 结构完整。
3. 语义闭合。
4. 段落与列表分层清晰。
5. 结束语稳定。

例如截图中的 Web 回答表现为：

- 先有一句完整的问候或解释
- 再有一段自我介绍或主题展开
- 然后用 bullet list 给出能力项
- 整体语气一致，不会被流式碎片打断

### 15.3 iOS 的偏差来源

当前 iOS 的偏差不止是渲染问题，更是“消息成型”问题：

1. 流式 chunk 过早进入正文区域。
2. 正文还没收束就被 UI 固定成多个短块。
3. Markdown / 富文本未在完成态统一整理。
4. 段落、列表、emoji、引用样式没有统一落地。
5. 恢复后正文只剩局部片段，而不是完整回答。

### 15.4 应该建立的正文成型链路

iOS 必须把“回答正文”从流式碎片变成完整消息，再交给 SwiftUI 渲染：

1. 接收 `content` chunk。
2. 暂存在 `assistantDraft`。
3. 累积到 `done` 或可结束状态。
4. 统一做 Markdown / 富文本 / 段落整理。
5. 固化为 `assistantMessage.body`。
6. 由 `AIChatMessageBubble` 一次性渲染完整正文。

### 15.5 正文对齐的具体要求

iOS 回答正文必须满足：

- 和 Web 一样是完整回答，而不是片段拼接
- 开场、展开、总结的节奏一致
- 列表、缩进、段落间距一致
- emoji 和语气风格一致
- 不显示字节流式的跳动过程
- 完成后正文布局不再变化

### 15.6 SwiftUI 落地建议

建议将正文渲染拆成两个阶段：

#### 阶段 A：流式收集

```swift
struct AIChatAnswerDraft {
    var rawText: String = ""
    var finalizedText: String = ""
    var isCompleted: Bool = false
}
```

```swift
func appendAnswerChunk(_ draft: inout AIChatAnswerDraft, chunk: String) {
    draft.rawText += chunk
}
```

#### 阶段 B：完成态固化

```swift
func finalizeAnswer(_ draft: inout AIChatAnswerDraft) {
    draft.finalizedText = normalizeMarkdown(draft.rawText)
    draft.isCompleted = true
}
```

#### 阶段 C：统一渲染

```swift
struct AIChatAnswerBody: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.primary)
    }
}
```

### 15.7 不允许的实现方式

以下方式都会让 iOS 继续偏离 Web：

- 每来一个 chunk 就重新生成一条正文行
- 把流式中间结果直接展示给用户
- 不做 Markdown 整理就直接分段绘制
- 让正文跟随事件面板一起抖动
- 恢复后正文只显示半截内容

### 15.8 验收标准

以下要求必须满足：

- iOS 回答正文和 Web 一样是完整成品
- 不再看到字节流式的断裂文本
- 完成后正文段落稳定
- 列表、缩进、emoji、语气和 Web 保持一致
- 恢复后正文仍然完整
- 正文不被事件流污染

### 15.9 与前文的关系

这一节和前面的“事件时间线对齐”“字节流式展示问题”是同一根因的不同表现：

- 前者解决“事件区怎么展示”
- 后者解决“正文怎么成型”

两者都要先把流式碎片收束成完整 turn，才能真正做到 iOS 对齐 Web。
