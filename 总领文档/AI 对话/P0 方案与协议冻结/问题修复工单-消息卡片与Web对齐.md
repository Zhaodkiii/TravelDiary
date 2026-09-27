# 问题修复工单｜消息卡片与 Web 对齐

## 1. 问题描述

iOS 端的 AI 对话消息卡片，在“工具调用中、请作答继续、问题/回答、已继续、已回复”等状态上的展示语义，与 Web 端没有完全对齐。

当前表现不是单纯的字号或圆角偏差，而是消息流结构和卡片状态表达已经出现差异，导致用户在 iOS 和 Web 上看到的对话过程不一致。

## 2. 影响范围

- iOS 对话消息流
- iOS 工具状态展示
- iOS `ask_user` 追问卡
- iOS 回答后的已继续 / 已回复状态
- 对齐基线：Web 端聊天页面

## 3. 参考代码位置

### iOS

- [AIChatRootView.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIChatRootView.swift)
- [AIChatMessageList.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIChatMessageList.swift)
- [AIAssistantTurnView.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIAssistantTurnView.swift)
- [AIAssistantActivityView.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIAssistantActivityView.swift)
- [AIAskUserCard.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIAskUserCard.swift)

### Web

- [ChatMessages.tsx](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/web/components/chat/home/ChatMessages.tsx)
- [TracePanels.tsx](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/web/components/chat/home/TracePanels.tsx)
- [AskUserOptions.tsx](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/web/components/chat/home/AskUserOptions.tsx)
- [SessionActivityPanel.tsx](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/web/components/chat/home/SessionActivityPanel.tsx)
- [ChatComposer.tsx](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/web/components/chat/home/ChatComposer.tsx)

## 4. 现象概述

### 4.1 工具状态卡和 Web 不一致

Web 的消息流里，工具过程是“inline trace rows + status label + 可展开的细分 trace + tool_call/tool_result 的顺序展示”。

iOS 目前是：

- 用 [AIAssistantActivityView.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIAssistantActivityView.swift) 显示一个单独的状态条。
- 状态文案偏摘要化，例如“DeepTutor 思考中… / 调用工具中… / 等待你的回答 / DeepTutor 已回复”。
- 工具过程被压缩为简短摘要，不是 Web 那种按事件顺序展开的 trace 行。

### 4.2 `ask_user` 追问卡和 Web 不一致

Web 的 [AskUserOptions.tsx](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/web/components/chat/home/AskUserOptions.tsx) 支持：

- 多问题 tab
- 每题 prompt + options + description
- 单选后自动跳下一题
- 多选
- 自定义文本
- 提交后可折叠的 resolved Q&A 总结

iOS 的 [AIAskUserCard.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIAskUserCard.swift) 目前更像“简化答题卡”：

- 顶部仅有“请作答以继续。”
- 选项使用字母序号按钮
- 只提供提交/下一题逻辑
- 没有 Web 那种 resolved 总结态
- 没有按 `prompt + description` 的语义展示

### 4.3 消息体分段和 Web 不一致

Web 的 [ChatMessages.tsx](/Users/hua/Documents/project/DeepTutor/DeepTutorSerevr/web/components/chat/home/ChatMessages.tsx) 会把同一轮对话拆成：

- 文字片段
- 工具 trace
- ask_user 卡
- 已解析的回答摘要

iOS 的 [AIAssistantTurnView.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIAssistantTurnView.swift) 是：

- assistant 正文
- tool/activity 状态条
- source references

这会让同一轮里“工具过程、追问、回答”的阅读顺序和 Web 不一致。

## 5. 具体差距

### 5.1 信息架构差距

- Web 把“工具调用中”和“请作答”视为消息流中的不同阶段。
- iOS 把它们更像是一个助手回合里的附加状态。
- 结果是 iOS 的卡片语义更弱，用户不容易区分“工具在跑”与“需要我作答”。

### 5.2 状态表达差距

- Web 会明确区分 `tool_call`、`tool_result`、`ask_user`、`resolved`。
- iOS 当前只把它们压成少量文案状态。
- 结果是“继续”“已继续”“回答”“工具问题”这些语义没有完整对齐到对应的事件状态。

### 5.3 交互差距

- Web 的 ask_user 卡支持更完整的问答流转。
- iOS 现在更偏单卡片交互，缺少 Web 的多问题、描述、折叠、已答总结。

### 5.4 排版差距

- Web 的 trace 是纵向卡片流，强调事件顺序。
- iOS 的状态条更扁平，缺少事件级分层。

## 6. 排查重点

1. 检查 iOS 的 `AIChatEventReducer` 是否已经正确区分：
   - `tool_call`
   - `tool_result`
   - `ask_user`
   - `ask_user_resolved`
2. 检查 `AIAssistantActivityView` 是否只展示了“摘要状态”，没有把 Web 的 trace 层级补出来。
3. 检查 `AIAskUserCard` 是否需要补齐：
   - prompt/description
   - resolved summary
   - 多问题 tab 的语义
   - 多选语义
4. 检查消息流渲染顺序是否与 Web 一致：
   - 文字片段在前
   - 工具 trace 在中
   - ask_user 卡在后
   - resolved 结果回填到原卡片
5. 检查“请作答以继续”和“已继续/已回复”文案是否与 Web 同源，而不是 iOS 单独拼文案。

## 7. 建议修复方向

### 7.1 统一消息分段模型

建议 iOS 消息流按 Web 的事件模型重构为三层：

- 正文 bubble
- tool / trace 行
- ask_user 卡

不要把工具过程全部塞进一个简化 activity header。

### 7.2 对齐 ask_user 卡语义

建议 iOS 的追问卡补齐 Web 已有语义：

- 多题 tab
- 每题说明文案
- 单选自动跳下一题
- 多选
- 自定义输入
- resolved 只读总结态

### 7.3 对齐工具状态文案

建议把状态文案改成和 Web 同一语义层：

- Tool call
- Asking you
- Tool result
- Response
- Reasoning

### 7.4 对齐 resolved 状态

建议 iOS 在用户提交后，不是直接消失，而是像 Web 一样保留 resolved 卡片，让用户能回看“问题 + 回答”。

## 8. 验收标准

- iOS 和 Web 的同一轮对话中，工具调用、追问、回答三类信息的顺序一致。
- iOS 的 ask_user 卡支持 resolved 回显。
- iOS 不再只用一个“调用工具中 / 等待你的回答”的摘要条代替完整 trace。
- 用户在 iOS 上能清楚区分：
  - 工具正在执行
  - 系统在等待用户回答
  - 用户已经提交
  - 系统已经继续生成

## 9. 结论

这不是单一样式差异，而是消息卡片的语义层没有和 Web 对齐。

优先修复顺序建议：

1. 统一事件分段与渲染顺序
2. 补齐 ask_user 卡的 resolved / 多题 / 自定义回答语义
3. 再补工具状态条的 trace 级展示
4. 最后再做字体、间距、圆角和颜色的细节对齐
