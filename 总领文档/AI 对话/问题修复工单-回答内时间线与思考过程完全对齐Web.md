# 问题修复工单 - 回答内时间线与思考过程完全对齐 Web

## 1. 工单目标

将 iOS 回答卡片内部的时间线、思考过程、工具调用、检索过程和结果摘要，完整对齐 Web 端的真实展示语义。

本工单只做文档方案，不实现业务代码，不改动后端协议，不涉及 HarmonyOS、Android。

## 2. 问题结论

当前 iOS 的回答内时间线和思考过程与 Web 端差距很大，主要表现在：

1. iOS 更像把原始事件流直接铺开，Web 更像把事件流整理成完整可读的回答卡片。
2. iOS 的时间线语义不稳定，思考过程、检索、工具、结果之间的层级没有和 Web 一一对应。
3. iOS 的视觉密度、顺序、缩进、图标语义、标题摘要都和 Web 不一致。
4. iOS 在完成后、恢复后、展开后这几个关键状态上的保留能力不足。

结论是：这不是单个控件样式问题，而是“事件成型方式”和“回答内结构定义”偏离了 Web。

## 3. Web 端参考特征

从截图可见，Web 端具有以下完整语义：

- 顶部显示回答状态摘要，例如 `DeepTutor 回答中... · 1m 3s`
- 下方是可展开的思考 / 时间线区域
- 时间线中的每一步都带有明确语义
- 事件类型被产品化表达，而不是原始字段直出
- 检索、提问、工具、抓取网页、结果等步骤有稳定顺序
- 思考过程和最终答案属于同一个 turn，而不是两个互相割裂的区域

## 4. iOS 当前偏差

### 4.1 时间线展示过于原始

iOS 当前更接近直接暴露事件列表：

- `阶段开始`
- `进度`
- `阶段结束`
- `结果`

这种方式会让用户看到的是协议碎片，而不是产品化的回答过程。

### 4.2 思考过程没有完整收束

思考过程应该是一个完整面板，包含：

- 状态摘要
- 过程节点
- 工具 / 检索 / 结果
- 可展开 / 收起
- 完成后仍保留

当前 iOS 可能只是把部分思考内容塞进正文附近或事件列表中，导致结构不稳定。

### 4.3 事件语义和 Web 不一致

Web 更像把每个阶段映射成可读步骤，例如：

- 检索知识库
- 向你提问
- 联网搜索
- 抓取网页
- 结果整理

iOS 如果只显示底层原始事件，就会缺少这些“产品语义”。

## 5. 对齐目标

对齐不是把 UI 变得像，而是把回答内结构完全一致化：

1. 同一 turn 的状态摘要一致。
2. 同一 turn 的思考过程层级一致。
3. 同一 turn 的时间线顺序一致。
4. 同一 turn 的工具、检索、结果表达一致。
5. 完成态、恢复态、展开态一致。

## 6. 正确的结构定义

建议将回答内结构固定为以下四层：

1. 状态摘要层
2. 思考过程层
3. 事件时间线层
4. 最终回答层

其中：

- 状态摘要层负责显示 `回答中 / 已完成 / 已中断 / 等待输入`
- 思考过程层负责聚合 `thinking`
- 事件时间线层负责聚合 `tool / source / progress / error / result`
- 最终回答层负责展示正式输出正文

## 7. 关键差距分析

### 7.1 顺序差距

Web 的顺序通常是：

1. 状态摘要
2. 思考过程
3. 时间线事件
4. 正文答案

iOS 当前容易变成：

1. 正文碎片
2. 调试事件
3. 状态条
4. 其他附属内容

### 7.2 视觉密度差距

Web 的时间线是收敛的、连续的、可读的。

iOS 当前的问题可能是：

- 行间距过大
- 缩进不统一
- 事件分块过散
- 图标和文本权重失衡
- 过程信息过长，正文被挤压

### 7.3 语义差距

Web 会把底层动作包装成用户可读的步骤。

iOS 若直接显示底层事件，将出现：

- 过多 `responding` / `chat` 之类底层状态
- 工具调用没有统一样式
- 检索、网页抓取、结果输出没有统一归类

## 8. SwiftUI 落地方案

### 8.1 组件结构

建议拆成以下语义层：

- `AIChatTurnCard`
- `AIChatTurnStatusBar`
- `AIChatThinkingHeader`
- `AIChatThinkingTimeline`
- `AIChatThinkingEventRow`
- `AIChatToolEventRow`
- `AIChatSourceEventRow`
- `AIChatAnswerBody`

### 8.2 事件分组策略

不要逐条直接渲染原始事件，应该先做分组：

- `thinking`
- `ask`
- `search`
- `fetch`
- `tool`
- `source`
- `result`
- `error`

展示时再映射成 Web 风格的时间线。

### 8.3 状态策略

回答卡片至少要支持：

- `responding`
- `completed`
- `interrupted`
- `waitingInput`
- `failed`

并且完成后仍保留思考过程入口，而不是收起后消失。

### 8.4 交互策略

- 默认显示状态摘要
- 思考区可展开 / 收起
- 完成后仍能展开查看
- 恢复后保留展开状态
- 时间线支持回看，但不应该吞掉正文优先级

## 9. Plain Text 页面草图

```text
┌──────────────────────────────────────────┐
│ DeepTutor 回答中... · 1m 3s              │
├──────────────────────────────────────────┤
│ ▼ 思考过程 / 时间线                      │
│   - 检索知识库                            │
│   - 向你提问                              │
│   - 联网搜索                              │
│   - 抓取网页                              │
│   - 结果                                  │
├──────────────────────────────────────────┤
│ 最终回答正文                              │
│                                          │
└──────────────────────────────────────────┘
```

收起态：

```text
┌──────────────────────────────────────────┐
│ DeepTutor 已完成 · 4s                    │
├──────────────────────────────────────────┤
│ ▶ 思考过程 / 时间线                      │
├──────────────────────────────────────────┤
│ 最终回答正文                              │
└──────────────────────────────────────────┘
```

## 10. 关键技术与核心代码示意

以下代码仅用于描述职责骨架和状态流转，不是完整业务实现。

### 10.1 Turn 状态模型

```swift
enum AIChatTurnStatus: String, Codable {
    case responding
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
    var answerText: String
    var thinkingEvents: [AIStreamEvent]
    var timelineGroups: [AITimelineGroup]
}
```

### 10.2 时间线分组

```swift
enum AITimelineGroupKind {
    case thinking
    case ask
    case search
    case fetch
    case tool
    case source
    case result
    case error
}
```

```swift
struct AITimelineGroup {
    let kind: AITimelineGroupKind
    var title: String
    var events: [AIStreamEvent]
}
```

### 10.3 Reducer 核心逻辑

```swift
func reduce(_ state: inout AIChatTurnViewState, event: AIStreamEvent) {
    switch event.type {
    case .thinking:
        state.status = .responding
        appendEvent(&state, event, kind: .thinking)

    case .content:
        state.status = .responding
        state.answerText += event.content ?? ""

    case .toolCall, .toolResult:
        appendEvent(&state, event, kind: .tool)

    case .sources:
        appendEvent(&state, event, kind: .source)

    case .waitForInput:
        state.status = .waitingInput
        appendEvent(&state, event, kind: .ask)

    case .progress:
        appendEvent(&state, event, kind: .thinking)

    case .stageStart, .stageEnd:
        appendEvent(&state, event, kind: .thinking)

    case .error:
        state.status = .failed
        appendEvent(&state, event, kind: .error)

    case .done:
        state.status = .completed
    }
}
```

### 10.4 时间线卡片

```swift
struct AIChatThinkingTimeline: View {
    let groups: [AITimelineGroup]
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack {
                    Text("思考过程")
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(groups.indices, id: \.self) { index in
                        AIChatTimelineGroupView(group: groups[index])
                    }
                }
            }
        }
    }
}
```

### 10.5 完整回答卡片

```swift
struct AIChatTurnCard: View {
    @State var state: AIChatTurnViewState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AIChatTurnStatusBar(
                status: state.status,
                elapsedSeconds: state.elapsedSeconds
            )

            AIChatThinkingTimeline(
                groups: state.timelineGroups,
                isExpanded: $state.isThinkingExpanded
            )

            Text(state.answerText)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }
}
```

## 11. 恢复与持久化要求

恢复时必须重建：

- turn 状态
- 状态摘要
- 思考过程展开态
- 时间线分组
- 最终答案正文

不能只恢复字节流碎片，也不能只恢复最终正文。

## 12. 验收标准

以下情况必须通过验收：

- iOS 回答内的时间线和思考过程与 Web 结构一致
- 完成后仍能看到摘要和展开入口
- 恢复后不会丢失事件链路
- 时间线是聚合后的产品化表达，不是原始事件直出
- 正文始终是主内容
- 视觉密度、顺序、图标语义、缩进和 Web 一致

## 13. 风险点

- 如果仍然直接渲染原始事件，iOS 会继续像调试页
- 如果不做事件分组，时间线会越来越长
- 如果展开状态不按 turn 保存，恢复后会反复漂移
- 如果正文和时间线没有主次划分，Web 与 iOS 会继续割裂

## 14. 待确认项

1. Web 端时间线是否默认展开。
2. Web 端是否把检索、抓取、工具、结果做了统一分组。
3. 完成态是否保留完整思考过程入口。
4. iOS 是否需要与 Web 完全一致的事件顺序和命名。

## 15. 建议落地顺序

1. 先定义 turn 级别的回答结构。
2. 再把原始事件聚合成时间线分组。
3. 再调整状态条、思考过程和正文的顺序。
4. 最后统一恢复态和展开态。

这样才能把 iOS 从“字节流式展示”真正收敛到“完整回答卡片”。
