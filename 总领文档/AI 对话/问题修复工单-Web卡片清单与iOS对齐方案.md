# 问题修复工单 - Web 卡片清单与 iOS 对齐方案

## 1. 工单目标

整理当前 Web 端 AI 对话中已确认的卡片类型，并给出 iOS SwiftUI 的一一对应对齐方案。

本工单只做文档方案，不实现业务代码，不改动后端协议，不涉及 HarmonyOS、Android。

## 2. 说明范围

这里的“卡片”指 Web 对话页中具有独立语义和独立交互边界的展示单元，包括：

- 回答卡片
- 思考过程 / 时间线卡片
- 提问卡片
- 工具调用卡片
- 工具结果卡片
- 来源 / 引用卡片
- 进度 / 阶段卡片
- 错误 / 失败卡片
- 恢复 / 重连提示卡片
- 加载 / 占位卡片

说明：

- 以下清单基于当前已见 Web 截图、现有 iOS 文档和已确认的事件语义整理。
- 如果后续 Web 继续暴露新卡片类型，应补入本工单，不应另起一套命名体系。

## 3. 已确认 Web 卡片清单

### 3.1 回答头部状态卡

特征：

- 展示 `已完成 · 1m 2s`、`回答中 · 1m 3s` 这类摘要
- 作为一轮回答的顶部状态入口
- 可与思考过程卡共同构成完整回答头部

对应语义：

- 回答状态摘要
- turn 生命周期摘要

iOS 对齐：

- `AIChatAnswerStatusBar`
- `AIChatTurnStatusBar`

对齐重点：

- 完成态必须保留
- 状态文案和耗时必须稳定
- 不能因恢复或滚动而消失

### 3.2 思考过程 / 时间线卡

特征：

- 显示 `思考过程 / 时间线`
- 可展开 / 收起
- 显示步骤数，例如 `15 个步骤`
- 与回答正文处于同一 turn

对应语义：

- thinking
- progress
- stage_start / stage_end
- tool 调用链

iOS 对齐：

- `AIChatThinkingTimeline`
- `AIChatThinkingTimelineEntry`
- `AIChatTimelineGroupView`

对齐重点：

- 不能直接渲染原始事件流
- 要先分组，再展示
- 完成后仍可展开
- 恢复后状态不丢

### 3.3 回答卡片 / 你的回答卡

特征：

- 展示 `你的回答`
- 可带 `1/1 answered`
- 作为正式回答单元的容器
- 与思考过程入口是分层关系

对应语义：

- 最终回答正文
- 回答已成型状态

iOS 对齐：

- `AIChatAnswerCard`
- `AIChatAnswerMeta`
- `AIChatAnswerBody`

对齐重点：

- 回答标题必须独立
- 正文不能和时间线混在一起
- 不能被事件碎片挤压成调试区

### 3.4 提问卡

特征：

- 用于模型向用户追问
- 可能表现为 `向你提问`
- 可能在当前回答过程里单独出现

对应语义：

- wait_for_input
- 澄清问题
- 补充上下文

iOS 对齐：

- `AIAskUserCard`
- `AIChatAskUserCardView`

对齐重点：

- 题目要明确
- 选项 / 输入框 / 确认按钮要完整
- 不能当普通消息显示
- 需要支持恢复和继续提交

### 3.5 选择 / 确认卡

特征：

- 用于让用户在多个选项中选择
- 或确认继续
- 与提问卡相邻

对应语义：

- 多选 / 单选 / 确认动作

iOS 对齐：

- `AIChatChoiceCard`
- 可复用 `AIAskUserCard` 的选项区

对齐重点：

- 选项必须可点击
- 选中态要可见
- 与提问卡共享状态流

### 3.6 工具调用卡

特征：

- 展示工具触发、工具名、调用状态
- 作为推理链路的一部分

对应语义：

- tool_call
- stage_start

iOS 对齐：

- `AIToolTraceCard`

对齐重点：

- 需显示调用对象和状态
- 不要只显示原始 JSON 或调试文本
- 必须可折叠

### 3.7 工具结果卡

特征：

- 展示工具返回结果
- 常与调用卡成对出现

对应语义：

- tool_result
- stage_end

iOS 对齐：

- `AIToolTraceCard`
- `AIChatToolResultView`

对齐重点：

- 结果要和调用归为同一组
- 不要让结果散落在正文里

### 3.8 来源 / 引用卡

特征：

- 展示来源、引用、网页、知识库条目
- 常作为答案依据的补充

对应语义：

- sources
- references

iOS 对齐：

- `AISourceReferencesView`

对齐重点：

- 来源应可点击
- 标题、摘要、URL 需结构化
- 不能混成普通文本段落

### 3.9 进度卡

特征：

- 显示任务推进过程
- 可能多次出现

对应语义：

- progress

iOS 对齐：

- `AIChatProgressRow`
- 或并入 `AIChatThinkingTimeline`

对齐重点：

- 多个进度事件要聚合
- 不要每条都单独占大行

### 3.10 阶段开始 / 阶段结束卡

特征：

- 表示子流程开始或结束
- 常用于工具、检索、分析阶段

对应语义：

- stage_start
- stage_end

iOS 对齐：

- `AIChatStageEventRow`
- 或并入 `AIChatTimelineGroupView`

对齐重点：

- 开始 / 结束应成对理解
- 不能分别当成普通消息

### 3.11 错误 / 失败卡

特征：

- 显示调用失败、网络失败、恢复失败等
- 可能带重试

对应语义：

- error
- terminal error

iOS 对齐：

- `AIChatErrorCard`
- `AIChatInlineErrorView`

对齐重点：

- 错误必须可见
- 不能静默吞掉
- 要给出重试或继续入口

### 3.12 恢复 / 重连提示卡

特征：

- 显示恢复中、重连中、续接中
- 让用户知道系统正在补回上下文

对应语义：

- resume
- reconnect
- resume_from

iOS 对齐：

- `AIChatRecoveryBanner`
- `AIChatReconnectStatusView`

对齐重点：

- 恢复后状态要保留
- 不可直接清空推理过程

### 3.13 加载 / 占位卡

特征：

- 正在构建内容时的占位
- 可能是骨架屏、渐显、占位行

对应语义：

- loading
- pending
- draft

iOS 对齐：

- `AIChatLoadingCard`
- `AIChatSkeletonRow`

对齐重点：

- 不能和正式内容混淆
- 加载结束后要平滑过渡到正式卡片

## 4. Web 卡片到 iOS 的统一映射表

| Web 卡片 | 主要语义 | iOS 对齐组件 | 是否可折叠 | 是否参与恢复 |
| --- | --- | --- | --- | --- |
| 回答头部状态卡 | turn 摘要 | `AIChatTurnStatusBar` | 否 | 是 |
| 思考过程 / 时间线卡 | 推理链路 | `AIChatThinkingTimeline` | 是 | 是 |
| 回答卡片 / 你的回答 | 正文容器 | `AIChatAnswerCard` | 否 | 是 |
| 提问卡 | 追问 / 澄清 | `AIAskUserCard` | 否 | 是 |
| 选择 / 确认卡 | 选择动作 | `AIChatChoiceCard` | 否 | 是 |
| 工具调用卡 | 工具触发 | `AIToolTraceCard` | 是 | 是 |
| 工具结果卡 | 工具返回 | `AIToolTraceCard` | 是 | 是 |
| 来源 / 引用卡 | 证据来源 | `AISourceReferencesView` | 是 | 是 |
| 进度卡 | 任务推进 | `AIChatProgressRow` | 可选 | 是 |
| 阶段开始 / 结束卡 | 子流程边界 | `AIChatStageEventRow` | 可选 | 是 |
| 错误 / 失败卡 | 失败反馈 | `AIChatErrorCard` | 否 | 是 |
| 恢复 / 重连提示卡 | 恢复状态 | `AIChatRecoveryBanner` | 否 | 是 |
| 加载 / 占位卡 | 生成前占位 | `AIChatLoadingCard` | 否 | 否 / 部分 |

## 5. iOS 对齐原则

### 5.1 不直接渲染原始事件

iOS 不应把 Web 端的事件流一条条原样铺到屏幕上，而要先做：

- 去重
- 分组
- 收束
- 成型

### 5.2 同一 turn 内卡片必须连贯

回答状态、思考过程、工具、来源、提问都应该属于同一 turn。

### 5.3 可恢复状态要优先

凡是 Web 端恢复后还能看到的卡片，iOS 都应该具备同等恢复能力。

### 5.4 正文始终是主内容

思考过程和时间线是辅助理解，不能压过最终回答正文。

## 6. 推荐 SwiftUI 目录职责

建议在 iOS 里按以下职责拆分：

```text
AIChat/
├── Domain/
│   ├── AIChatTurn.swift
│   ├── AIChatState.swift
│   ├── AIStreamEvent.swift
│   └── AIChatCardModels.swift
├── Application/
│   ├── AIChatEventReducer.swift
│   └── AIChatViewModel.swift
└── Presentation/
    ├── AIChatTurnStatusBar.swift
    ├── AIChatThinkingTimeline.swift
    ├── AIChatAnswerCard.swift
    ├── AIAskUserCard.swift
    ├── AIToolTraceCard.swift
    ├── AISourceReferencesView.swift
    └── AIChatErrorCard.swift
```

## 7. 关键技术与核心代码示意

以下代码仅用于说明职责骨架和状态流转，不是完整业务实现。

### 7.1 卡片模型

```swift
enum AIChatCardKind {
    case answerHeader
    case thinkingTimeline
    case answerBody
    case askUser
    case choice
    case toolTrace
    case sources
    case progress
    case stage
    case error
    case recovery
    case loading
}
```

```swift
struct AIChatCardItem {
    let kind: AIChatCardKind
    let turnID: String
    let title: String
    let stepCount: Int?
    let isExpanded: Bool
}
```

### 7.2 卡片渲染器

```swift
struct AIChatCardRenderer: View {
    let item: AIChatCardItem

    var body: some View {
        switch item.kind {
        case .answerHeader:
            AIChatTurnStatusBar(status: .completed, elapsedSeconds: 62)
        case .thinkingTimeline:
            AIChatThinkingTimeline(groups: [], isExpanded: .constant(true))
        case .answerBody:
            AIChatAnswerCard(state: placeholderState)
        case .askUser:
            AIAskUserCardView(card: placeholderAskUser)
        case .choice:
            AIChatChoiceCardView()
        case .toolTrace:
            AIToolTraceCard()
        case .sources:
            AISourceReferencesView(items: [])
        case .progress:
            AIChatProgressRow()
        case .stage:
            AIChatStageEventRow()
        case .error:
            AIChatErrorCard()
        case .recovery:
            AIChatRecoveryBanner()
        case .loading:
            AIChatLoadingCard()
        }
    }
}
```

### 7.3 事件到卡片的转换

```swift
func makeCards(from turn: AIChatTurnViewState) -> [AIChatCardItem] {
    var cards: [AIChatCardItem] = []

    cards.append(.init(
        kind: .answerHeader,
        turnID: turn.turnID,
        title: "状态摘要",
        stepCount: nil,
        isExpanded: false
    ))

    cards.append(.init(
        kind: .thinkingTimeline,
        turnID: turn.turnID,
        title: "思考过程",
        stepCount: turn.timelineGroups.count,
        isExpanded: turn.isThinkingExpanded
    ))

    cards.append(.init(
        kind: .answerBody,
        turnID: turn.turnID,
        title: "你的回答",
        stepCount: nil,
        isExpanded: false
    ))

    return cards
}
```

## 8. 验收标准

以下情况必须通过验收：

- Web 中已确认的卡片类型在 iOS 中都有对应组件
- 同类卡片的职责和层级一致
- 完成态和恢复态都能保留回答头部和思考过程
- 提问、工具、来源、错误都不是普通消息文本
- iOS 不再直接暴露原始事件流碎片
- 正文、卡片、时间线的主次顺序和 Web 一致

## 9. 风险点

- 如果继续直接把事件流映射到列表，卡片数量会失控
- 如果不做统一卡片模型，未来会每个页面一套写法
- 如果恢复状态缺失，Web/iOS 一致性会继续下降
- 如果错误、提问、工具、来源不分卡片，阅读路径会混乱

## 10. 待确认项

1. Web 是否还有未在截图中暴露的特殊卡片类型。
2. `answer` / `thinking` / `tool` 是否在所有任务类型中都一致。
3. `choice` 与 `ask user` 是否共用同一交互组件。
4. iOS 是否需要和 Web 完全同文案，还是只对齐语义。

## 11. 建议落地顺序

1. 先统一卡片模型。
2. 再做事件到卡片的分组转换。
3. 再补齐每种卡片的 SwiftUI 组件。
4. 最后统一恢复态、折叠态和完成态。

这样可以把 Web 的卡片语义完整落到 iOS，而不是只做一个“像聊天”的页面。

## 12. 实现细节

### 12.1 总体实现链路

对齐 Web 的核心，不是单个 View，而是一条固定的消息成型链路：

1. WebSocket / API 收到原始事件。
2. Event Decoder 先把原始帧解析成 `AIStreamEvent`。
3. Event Reducer 负责去重、顺序整理和 turn 聚合。
4. Card Builder 将 turn 状态映射成卡片模型。
5. Presentation 层只渲染卡片，不直接消费原始事件。
6. 恢复时先恢复 turn，再恢复卡片列表和折叠状态。

### 12.2 和 Web 对齐的关键点

Web 的本质是：

- 先成型，再展示
- 先聚合，再渲染
- 先稳定状态，再更新局部内容

iOS 也必须保持这条链路，否则就会回到“字节流直接上屏”的问题。

### 12.3 卡片渲染原则

每张卡片都要满足以下原则：

- 有独立语义
- 有稳定标题
- 有稳定状态
- 有明确展开 / 收起边界
- 能在恢复后重新生成
- 不能依赖临时 chunk 直接渲染

### 12.4 刷新策略

刷新不能全量重绘整页，而应分级：

- `thinking` / `progress` 更新时只刷新时间线局部
- `tool_call` / `tool_result` 更新时只刷新对应分组
- `done` 时刷新回答卡片完成态
- `resume` 时刷新 turn 级恢复状态

### 12.5 展开状态策略

展开状态必须按 turn 保存：

- 同一轮回答再次进入时，保持上一次展开/收起选择
- 完成后不能自动丢失
- 恢复后不能退回默认态，除非产品明确要求

## 13. 关键技术方案

### 13.1 事件归并

Web 端能看起来“像完整回答”，依赖的是事件归并。

建议 iOS 也用同样的逻辑：

- 连续 thinking 合并
- 连续 progress 合并
- tool call 和 tool result 成对展示
- stage start / end 合并为阶段组
- sources 统一放入引用组

### 13.2 turn 级数据持久化

必须把下列内容写入 turn 级状态：

- 当前状态
- 已耗时
- 是否展开
- 步骤数
- answered 数
- thinking 事件组
- tool / source / error 事件组
- 最终回答正文

这样恢复后才能重建 Web 一样的回答结构。

### 13.3 局部 diff 更新

为了避免 iOS 频繁抖动，建议：

- 同一分组内追加事件时，仅更新该分组
- 新增卡片时，仅插入对应位置
- 状态切换时，仅刷新头部状态条
- 完成态变化时，仅刷新回答卡片尾部

### 13.4 主次层级

Web 的卡片感来自严格的主次层级：

1. 状态摘要
2. 思考过程入口
3. 回答标题
4. 正文
5. 工具 / 来源 / 错误作为辅助信息

iOS 必须维持相同层级，不能让工具或事件压过正文。

## 14. 主要代码示例

以下代码均为职责骨架示意，不是完整业务实现。

### 14.1 事件归并器

```swift
final class AIChatCardComposer {
    func composeCards(from turn: AIChatTurnViewState) -> [AIChatCardItem] {
        var cards: [AIChatCardItem] = []

        cards.append(.init(
            kind: .answerHeader,
            turnID: turn.turnID,
            title: "状态摘要",
            stepCount: nil,
            isExpanded: false
        ))

        cards.append(.init(
            kind: .thinkingTimeline,
            turnID: turn.turnID,
            title: "思考过程 / 时间线",
            stepCount: turn.timelineGroups.count,
            isExpanded: turn.isThinkingExpanded
        ))

        if !turn.answerText.isEmpty {
            cards.append(.init(
                kind: .answerBody,
                turnID: turn.turnID,
                title: "你的回答",
                stepCount: nil,
                isExpanded: false
            ))
        }

        for group in turn.timelineGroups {
            switch group.kind {
            case .ask:
                cards.append(.init(
                    kind: .askUser,
                    turnID: turn.turnID,
                    title: group.title,
                    stepCount: group.events.count,
                    isExpanded: group.isExpanded
                ))
            case .tool:
                cards.append(.init(
                    kind: .toolTrace,
                    turnID: turn.turnID,
                    title: group.title,
                    stepCount: group.events.count,
                    isExpanded: group.isExpanded
                ))
            case .source:
                cards.append(.init(
                    kind: .sources,
                    turnID: turn.turnID,
                    title: group.title,
                    stepCount: group.events.count,
                    isExpanded: group.isExpanded
                ))
            case .error:
                cards.append(.init(
                    kind: .error,
                    turnID: turn.turnID,
                    title: group.title,
                    stepCount: group.events.count,
                    isExpanded: false
                ))
            default:
                break
            }
        }

        return cards
    }
}
```

### 14.2 事件到分组

```swift
func appendEvent(_ state: inout AIChatTurnViewState, event: AIStreamEvent) {
    switch event.type {
    case .thinking:
        state.timelineGroups.appendOrMerge(event, kind: .thinking)
    case .progress:
        state.timelineGroups.appendOrMerge(event, kind: .thinking)
    case .toolCall, .toolResult:
        state.timelineGroups.appendOrMerge(event, kind: .tool)
    case .sources:
        state.timelineGroups.appendOrMerge(event, kind: .source)
    case .waitForInput:
        state.timelineGroups.appendOrMerge(event, kind: .ask)
    case .error:
        state.timelineGroups.appendOrMerge(event, kind: .error)
    default:
        break
    }
}
```

### 14.3 回答头部状态条

```swift
struct AIChatAnswerStatusBar: View {
    let status: AIChatAnswerStatus
    let elapsedSeconds: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: status == .completed ? "checkmark.circle.fill" : "sparkles")
                .foregroundStyle(status == .completed ? .blue : .secondary)
            Text(statusTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("· \(elapsedSeconds)s")
                .font(.subheadline)
                .foregroundStyle(.secondary.opacity(0.8))
        }
    }

    private var statusTitle: String {
        switch status {
        case .responding: return "回答中"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .waitingInput: return "等待输入"
        }
    }
}
```

### 14.4 思考过程入口

```swift
struct AIChatThinkingTimelineEntry: View {
    let stepCount: Int
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.secondary)
                Text("思考过程 / 时间线")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("\(stepCount) 个步骤")
                    .font(.subheadline)
                    .foregroundStyle(.secondary.opacity(0.8))
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.right")
                    .foregroundStyle(.secondary.opacity(0.8))
            }
        }
    }
}
```

### 14.5 卡片路由器

```swift
struct AIChatCardRouter: View {
    let item: AIChatCardItem

    var body: some View {
        switch item.kind {
        case .answerHeader:
            AIChatAnswerStatusBar(status: .completed, elapsedSeconds: 62)
        case .thinkingTimeline:
            AIChatThinkingTimeline(groups: [], isExpanded: .constant(true))
        case .answerBody:
            AIChatAnswerBodyView(text: "...")
        case .askUser:
            AIAskUserCardView(card: placeholderAskUser)
        case .choice:
            AIChatChoiceCardView()
        case .toolTrace:
            AIToolTraceCard()
        case .sources:
            AISourceReferencesView(items: [])
        case .progress:
            AIChatProgressRow()
        case .stage:
            AIChatStageEventRow()
        case .error:
            AIChatErrorCard()
        case .recovery:
            AIChatRecoveryBanner()
        case .loading:
            AIChatLoadingCard()
        }
    }
}
```

### 14.6 恢复策略

```swift
func restoreTurnState(from cache: TurnCache) -> AIChatTurnViewState {
    AIChatTurnViewState(
        sessionID: cache.sessionID,
        turnID: cache.turnID,
        status: cache.status,
        elapsedSeconds: cache.elapsedSeconds,
        stepCount: cache.stepCount,
        answeredCount: cache.answeredCount,
        isTimelineExpanded: cache.isTimelineExpanded,
        isAnswerExpanded: cache.isAnswerExpanded,
        answerText: cache.answerText,
        timelineGroups: cache.timelineGroups
    )
}
```

### 14.7 日志接入

```swift
struct SessionLogger {
    static func log(_ message: String,
                    sessionID: String? = nil,
                    turnID: String? = nil,
                    cardKind: String? = nil) {
        print("[AIChat] session=\(sessionID ?? "-") turn=\(turnID ?? "-") card=\(cardKind ?? "-") \(message)")
    }
}
```

```swift
SessionLogger.log("compose cards", sessionID: turn.sessionID, turnID: turn.turnID, cardKind: "answerHeader")
SessionLogger.log("append thinking event", sessionID: turn.sessionID, turnID: turn.turnID, cardKind: "thinkingTimeline")
SessionLogger.log("restore expanded state", sessionID: turn.sessionID, turnID: turn.turnID, cardKind: "answerBody")
```

## 15. 与 Web 对齐的验收点

以下内容必须一一对齐：

- 状态摘要是否固定可见
- 思考过程是否有独立入口和步骤数
- 回答标题是否独立
- 提问卡是否可恢复
- 工具、来源、错误是否有单独卡片
- 完成态是否保留完整结构
- 恢复态是否不丢展开状态
- 正文是否始终居于主内容位置

## 16. 风险点

- 如果继续让 View 直接消费原始事件，Web 对齐会失败
- 如果不做卡片模型，后续每个功能都会长出新写法
- 如果恢复态没保存展开状态，完成后卡片会反复变形
- 如果工具 / 来源 / 提问混进正文，信息架构会继续混乱

## 17. 待确认项

1. Web 是否还有未覆盖的特殊卡片类型。
2. `answered` 计数在多轮场景下是否需要动态变化。
3. 思考过程入口是否应在完成后默认折叠。
4. iOS 是否需要完全复用 Web 的卡片标题文案。
