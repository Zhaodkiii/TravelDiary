# 问题修复工单 - Web 中提问类卡片清单与 iOS 对齐方案

## 1. 工单目标

整理 Web 端对话中所有“提问类卡片”的语义分类、触发条件和展示特点，并给出 iOS SwiftUI 的一一对齐方案。

本工单只做文档方案，不实现业务代码，不改动后端协议，不涉及 HarmonyOS、Android。

## 2. 结论先行

Web 端的“提问类卡片”不是单一一种组件，而是一组语义相近但职责不同的卡片集合。当前最重要的对齐目标有三点：

1. 提问类卡片必须和 turn 级状态绑定，而不是和单次 chunk 绑定。
2. 提问类卡片必须能恢复、能回看、能继续回答。
3. iOS 端不能把提问类卡片做成普通消息气泡，必须保留“需要用户参与”的独立语义。

## 3. Web 中提问类卡片清单

### 3.1 向你提问

**语义**

- 模型主动向用户追问一个缺失信息
- 常见于上下文不足、需要选择、需要确认时

**典型表现**

- 标题明确
- 有问题正文
- 可能附带选项
- 可能要求用户输入补充内容

**对话作用**

- 推动对话进入下一步
- 让模型从“回答”切到“收集信息”

### 3.2 你的回答

**语义**

- 不是纯展示消息，而是用户对上一轮提问的回应入口或回应结果
- 在 Web 中常和思考过程、时间线同处一个回答结构中

**典型表现**

- 独立标题区
- 显示回答计数，如 `1/1 answered`
- 与提问卡片存在上下文关联

**对话作用**

- 标识这是一次“待答复问题”的完成结果
- 让卡片形成闭环

### 3.3 补充信息卡片

**语义**

- 要求用户补全条件、背景、目标、限制

**典型表现**

- 说明性文字
- 可能附带输入框
- 可能附带多选或单选

**对话作用**

- 帮助模型拿到足够上下文

### 3.4 确认 / 选择卡片

**语义**

- 要求用户在多个候选项中确认一个或多个

**典型表现**

- 选项列表
- 单选 / 多选
- 确认按钮

**对话作用**

- 把模糊请求转成明确分支

### 3.5 澄清 / 追问卡片

**语义**

- 对用户问题做进一步澄清
- 用于缩小范围、消除歧义

**典型表现**

- 问题更短
- 语义更聚焦
- 常与上一轮内容强绑定

**对话作用**

- 防止模型直接在模糊条件下给出错误答案

### 3.6 二次提问卡片

**语义**

- 在上一轮提问后继续追问
- 属于多轮问答链中的下一步

**典型表现**

- 和已有回答卡片形成连续链路
- 可能保持同一视觉样式，只改变内容

**对话作用**

- 支持“问答-补充-再问”的循环

## 4. Web 卡片的共同特征

无论是哪一种提问类卡片，Web 端一般都有这些共同点：

- 它们是独立语义单元，不是普通聊天正文
- 它们会和 turn / session 绑定
- 它们通常带有明确的标题或摘要
- 它们允许用户参与，而不是单向阅读
- 它们可以和思考过程、时间线、回答正文并存
- 它们在完成后仍应可回看

## 5. iOS 对齐目标

### 5.1 结构对齐

iOS 中提问类卡片应至少拆成三层：

1. 卡片标题层
2. 问题内容层
3. 用户输入 / 选择层

如果需要，还应增加：

4. 选项层
5. 说明层
6. 结果回显层

### 5.2 状态对齐

提问类卡片至少应支持以下状态：

- `idle`
- `prompting`
- `awaitingAnswer`
- `answered`
- `editing`
- `disabled`
- `error`

### 5.3 生命周期对齐

iOS 中提问类卡片必须支持：

- 首次展示
- 用户填写
- 用户提交
- 服务端确认
- 恢复后继续查看
- 回到历史记录时仍可看到上下文

## 6. iOS 组件对齐方案

### 6.1 对应组件建议

- `AIAskUserCard`
- `AIAskPromptCard`
- `AIAskChoiceCard`
- `AIAskConfirmCard`
- `AIAskFollowUpCard`
- `AIAnswerSummaryCard`

### 6.2 组件职责

#### `AIAskUserCard`

- 作为总入口
- 承载“需要用户回答”的通用结构

#### `AIAskPromptCard`

- 承载开放式提问
- 适合单输入框

#### `AIAskChoiceCard`

- 承载单选 / 多选提问
- 适合选项列表

#### `AIAskConfirmCard`

- 承载确认型问题
- 适合“是 / 否”或少量选项

#### `AIAskFollowUpCard`

- 承载多轮追问
- 用于和前一轮答案形成链路

#### `AIAnswerSummaryCard`

- 回显用户已答内容
- 和 `1/1 answered` 类状态对应

## 7. SwiftUI 设计建议

### 7.1 卡片层级

建议在 SwiftUI 中把提问类卡片放进独立的回答单元，而不是消息气泡：

```text
Turn Card
├── Status Bar
├── Thinking Timeline
├── Ask Card
├── Answer Summary
└── Final Answer
```

### 7.2 输入方式

根据卡片类型不同，输入方式也应不同：

- 开放式提问 -> 文本输入框
- 确认型提问 -> 单选按钮
- 选择型提问 -> 列表选择器
- 补充信息型提问 -> 多字段输入区

### 7.3 视觉要求

提问类卡片应保持：

- 明确的标题
- 轻量但高可见度的边框
- 与正文不同的卡片背景
- 清晰的用户参与提示
- 与思考过程区域同属一个 turn 结构

## 8. 对照矩阵

| Web 提问类卡片 | Web 语义 | iOS 对应组件 | iOS 状态 | 是否可编辑 | 是否可恢复 |
| --- | --- | --- | --- | --- | --- |
| 向你提问 | 模型追问用户 | `AIAskPromptCard` | `prompting` / `awaitingAnswer` | 是 | 是 |
| 你的回答 | 用户答复回显 | `AIAnswerSummaryCard` | `answered` | 否 | 是 |
| 补充信息 | 补全上下文 | `AIAskPromptCard` / `AIAskFollowUpCard` | `awaitingAnswer` | 是 | 是 |
| 确认 / 选择 | 选择分支 | `AIAskChoiceCard` / `AIAskConfirmCard` | `awaitingAnswer` | 是 | 是 |
| 澄清 / 追问 | 缩小歧义 | `AIAskFollowUpCard` | `prompting` / `awaitingAnswer` | 是 | 是 |
| 二次提问 | 多轮继续追问 | `AIAskFollowUpCard` | `prompting` / `awaitingAnswer` | 是 | 是 |

## 9. Plain Text 页面草图

```text
┌──────────────────────────────────────────┐
│ 已完成 · 1m 2s                           │
├──────────────────────────────────────────┤
│ 思考过程 / 时间线   15 个步骤            │
├──────────────────────────────────────────┤
│ 向你提问                                 │
│ 这里需要你补充一个条件                    │
│ [输入框 / 选项列表 / 确认按钮]            │
├──────────────────────────────────────────┤
│ 你的回答 1/1 answered                    │
│ 你的补充内容 / 已答内容                  │
├──────────────────────────────────────────┤
│ 最终回答正文                              │
└──────────────────────────────────────────┘
```

## 10. 关键技术与核心代码示意

以下代码仅用于说明职责骨架和状态流转，不是完整业务实现。

### 10.1 提问卡片状态

```swift
enum AIAskCardStatus: String, Codable {
    case prompting
    case awaitingAnswer
    case answered
    case editing
    case disabled
    case error
}
```

```swift
struct AIAskCardViewState {
    var cardID: String
    var sessionID: String
    var turnID: String
    var status: AIAskCardStatus
    var title: String
    var promptText: String
    var selectedOptions: [String]
    var inputText: String
    var answerSummary: String?
    var isExpanded: Bool
}
```

### 10.2 通用提问卡片

```swift
struct AIAskUserCard: View {
    let state: AIAskCardViewState
    let onSubmitText: (String) -> Void
    let onSubmitChoice: ([String]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(state.title)
                .font(.headline)

            Text(state.promptText)
                .font(.body)
                .foregroundStyle(.secondary)

            if !state.selectedOptions.isEmpty {
                AIAskChoiceList(options: state.selectedOptions)
            }

            AIAskInputArea(text: state.inputText, onSubmit: onSubmitText)
        }
    }
}
```

### 10.3 回答回显卡片

```swift
struct AIAnswerSummaryCard: View {
    let answerText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("你的回答")
                Text("· 1/1 answered")
                    .foregroundStyle(.secondary)
            }

            Text(answerText)
        }
    }
}
```

## 11. 恢复与持久化要求

提问类卡片恢复时必须重建：

- 卡片类型
- 标题
- 提问正文
- 选项列表
- 用户已输入内容
- 回答回显
- 展开 / 折叠状态
- 所属 turn 和 session

不能只恢复成一条普通消息，也不能把答复当成单次临时输入。

## 12. 验收标准

以下情况必须通过验收：

- Web 中的提问类卡片在 iOS 都有明确对应组件
- 提问类卡片不是普通消息气泡
- 卡片状态能从 prompting 走到 answered
- 回答回显与提问卡片属于同一 turn
- 恢复后仍能看到提问和回答上下文
- 选项 / 输入 / 确认三种交互都能在 iOS 上表达

## 13. 风险点

- 如果把提问类卡片做成普通消息泡，语义会丢失
- 如果不区分提问、回答、确认、补充，后续 UI 会越来越乱
- 如果恢复时只恢复正文，不恢复卡片状态，历史回答会失真
- 如果没有 turn 级绑定，提问卡片会和时间线、正文分离

## 14. 待确认项

1. Web 中是否还有其他未在截图中出现的提问类卡片变体。
2. `1/1 answered` 是否固定是回答状态计数。
3. 多选场景在 Web 中是否和单选使用同一视觉组件。
4. iOS 是否需要严格复用 Web 的标题文案。

## 15. 建议落地顺序

1. 先把 Web 的提问类卡片语义分清楚。
2. 再给 iOS 建立对应组件。
3. 再统一状态模型和恢复策略。
4. 最后对齐视觉、交互和标题文案。

这样才能避免 iOS 只是在样子上“像提问卡片”，但语义上还是普通消息。
