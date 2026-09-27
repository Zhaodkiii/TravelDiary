# 问题修复工单 - 回答头部摘要与思考过程时间线对齐 Web

## 1. 工单目标

将 iOS 回答卡片顶部的状态摘要、`思考过程 / 时间线` 入口、回答卡片标题区、以及正文内容，完整对齐 Web 端的展示层级和交互语义。

本工单只描述 iOS SwiftUI 的对齐方案，不实现业务代码，不改动后端协议，不涉及 HarmonyOS、Android。

## 2. 问题结论

从当前截图对比可以直接确认，iOS 端和 Web 端在“回答头部”这一区域存在明显差异：

1. Web 端有稳定的完成态摘要，例如 `已完成 · 1m 2s`。
2. Web 端把 `思考过程 / 时间线` 作为独立的、可展开的头部入口，并显示步骤数量。
3. Web 端在思考过程下方还有一个单独的 `你的回答 · 1/1 answered` 卡片，说明回答内容和过程入口是分层的。
4. iOS 端当前的头部层级不稳定，容易把状态、过程、答案混在一起，导致用户先看到正文或碎片信息，而不是统一的回答卡片结构。

结论是：当前差距不是一个按钮样式问题，而是“回答头部区域的信息架构”没有和 Web 对齐。

## 3. Web 端参考特征

从截图可见，Web 端这一段有明确结构：

- 最上方是完成态状态条
- 第二层是 `思考过程 / 时间线`，并显示步骤数
- 第三层是 `你的回答` 卡片，带 `1/1 answered`
- 最终正文出现在结构化容器下方

这说明 Web 端已经不是原始事件流，而是已经完成产品化收束。

## 4. iOS 当前偏差

### 4.1 状态摘要不稳定

iOS 端容易把“完成中 / 已完成 / 用时”与正文内容绑定在一起，导致：

- 完成态不够显眼
- 切换状态后位置漂移
- 恢复后摘要消失或变形

### 4.2 思考过程入口不一致

Web 端的 `思考过程 / 时间线` 是一个独立入口，带步骤数。

iOS 当前问题通常是：

- 直接展示事件列表
- 没有统一的入口标题
- 没有步骤计数
- 完成态仍像调试信息

### 4.3 回答卡片标题层级不一致

Web 端的 `你的回答 · 1/1 answered` 是一个单独的标题区。

iOS 若直接把正文扔进消息 bubble 或普通段落，就会失去：

- 卡片标题感
- 回答单元感
- 与思考过程的分层关系

## 5. 对齐目标

对齐目标不是“把 UI 做得差不多”，而是让回答头部具有一致的产品语义：

1. 顶部状态摘要一致。
2. 思考过程入口一致。
3. 步骤数展示一致。
4. 回答卡片标题一致。
5. 回答正文和过程层级一致。
6. 完成态、恢复态、展开态一致。

## 6. 正确的结构定义

建议把一轮回答固定为以下四层：

1. 状态摘要层
2. 思考过程入口层
3. 回答标题层
4. 回答正文层

其中：

- 状态摘要层负责显示 `已完成 · 1m 2s`
- 思考过程入口层负责显示 `思考过程 / 时间线 15 个步骤`
- 回答标题层负责显示 `你的回答 · 1/1 answered`
- 回答正文层负责显示最终输出

## 7. 根因分析

### 7.1 事件与标题没有分层

如果 iOS 只是把事件直接塞进一个消息卡片，就会出现：

- 标题不稳定
- 时间线不稳定
- 回答正文不稳定

### 7.2 步骤数没有成为一等信息

Web 端把“15 个步骤”作为可见状态，这说明它已经把事件聚合成了步骤级结构。

iOS 若不显示步骤数，只显示零散事件，就会显得像“半成品链路”。

### 7.3 `answered` 状态没有独立表达

Web 端 `1/1 answered` 表明这不是普通消息，而是一个回答单元。

iOS 如果没有这个状态，就会缺少“回答已形成”的产品感。

## 8. SwiftUI 落地方案

### 8.1 组件结构

建议把这一段拆成以下语义层：

- `AIChatAnswerHeader`
- `AIChatAnswerStatusBar`
- `AIChatThinkingTimelineEntry`
- `AIChatAnswerCard`
- `AIChatAnswerBody`
- `AIChatAnswerMeta`

### 8.2 状态模型

建议 turn 状态至少包含：

- `status`：`responding` / `completed` / `failed` / `waitingInput`
- `elapsedSeconds`
- `stepCount`
- `answeredCount`
- `isTimelineExpanded`
- `isAnswerExpanded`

### 8.3 交互策略

- 完成态摘要始终可见
- 思考过程入口可展开 / 收起
- 步骤数始终展示在入口上
- 回答卡片标题不随正文滚动而消失
- 恢复后保持展开/收起状态

## 9. Plain Text 页面草图

### 9.1 目标结构

```text
┌──────────────────────────────────────────┐
│ 已完成 · 1m 2s                           │
├──────────────────────────────────────────┤
│ 思考过程 / 时间线        15 个步骤   >    │
├──────────────────────────────────────────┤
│ 你的回答                 1/1 answered     │
├──────────────────────────────────────────┤
│ 最终回答正文                              │
│                                          │
│ ...                                      │
└──────────────────────────────────────────┘
```

### 9.2 当前偏差形态

```text
┌──────────────────────────────────────────┐
│ 正文 / 事件 / 状态混在一个区域           │
│ 思考过程标题不稳定                       │
│ 步骤数缺失                               │
│ 回答标题缺失                             │
└──────────────────────────────────────────┘
```

## 10. 关键技术与核心代码示意

以下代码仅用于说明职责骨架和状态流转，不是完整业务实现。

### 10.1 回答头部状态模型

```swift
enum AIChatAnswerStatus: String, Codable {
    case responding
    case completed
    case failed
    case waitingInput
}
```

```swift
struct AIChatAnswerViewState {
    var sessionID: String
    var turnID: String
    var status: AIChatAnswerStatus
    var elapsedSeconds: Int
    var stepCount: Int
    var answeredCount: Int
    var isTimelineExpanded: Bool
    var isAnswerExpanded: Bool
    var answerText: String
    var timelineGroups: [AITimelineGroup]
}
```

### 10.2 时间线入口

```swift
struct AIChatThinkingTimelineEntry: View {
    let stepCount: Int
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 10) {
                Text("思考过程 / 时间线")
                Spacer()
                Text("\(stepCount) 个步骤")
                    .foregroundStyle(.secondary)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.right")
            }
        }
    }
}
```

### 10.3 回答卡片标题

```swift
struct AIChatAnswerMeta: View {
    let answeredCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
            Text("你的回答")
                .font(.headline)
            Text("· \(answeredCount)/1")
                .foregroundStyle(.secondary)
        }
    }
}
```

### 10.4 完整回答卡片

```swift
struct AIChatAnswerCard: View {
    @State var state: AIChatAnswerViewState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AIChatAnswerStatusBar(
                status: state.status,
                elapsedSeconds: state.elapsedSeconds
            )

            AIChatThinkingTimelineEntry(
                stepCount: state.stepCount,
                isExpanded: $state.isTimelineExpanded
            )

            AIChatAnswerMeta(answeredCount: state.answeredCount)

            Text(state.answerText)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }
}
```

## 11. 恢复与持久化要求

恢复时必须重建：

- 完成态摘要
- 思考过程入口
- 步骤数
- 回答计数
- 时间线展开态
- 回答正文

不能只恢复正文，也不能只恢复原始事件。

## 12. 验收标准

以下情况必须通过验收：

- iOS 回答头部的层级和 Web 一致
- `已完成 · 1m 2s` 一直可见
- `思考过程 / 时间线` 独立成行并显示步骤数
- `你的回答 · 1/1 answered` 独立成卡片标题
- 完成态和恢复态都保持一致
- 正文和头部层级不再混在一起

## 13. 风险点

- 如果头部状态和正文共用一个容器，层级就会继续漂移
- 如果步骤数不从事件聚合得到，就会失去产品化表达
- 如果恢复时不重建标题层，Web 与 iOS 的差距会继续扩大

## 14. 待确认项

1. Web 端 `思考过程 / 时间线` 是否始终显示步骤数。
2. Web 端 `你的回答 · 1/1 answered` 是否会在多回答场景变化为其他计数。
3. iOS 是否需要完全复用 Web 的标题文案。
4. 是否允许思考过程入口默认折叠。

## 15. 建议落地顺序

1. 先定义回答头部三层结构。
2. 再把事件聚合成步骤数。
3. 再把回答卡片标题独立出来。
4. 最后统一恢复态和展开态。

这样才能把 iOS 的回答头部真正对齐到 Web 的完整产品结构。
