# 输入框对齐 Web 到 SwiftUI 工单

## 1. 工单目标

将当前 AI 对话输入框区域从 Web 交互样式完整迁移到 SwiftUI，实现视觉、结构、交互和状态表现一致。

本工单只聚焦 iOS 的 SwiftUI 输入框区域，不涉及后端协议变更，不涉及 Android、HarmonyOS，也不改动对话业务逻辑本身。

## 2. 对齐范围

对齐对象为 Web 端对话输入区域，核心包括：

- 输入框容器的尺寸、圆角、描边、阴影和留白
- 占位文案的位置、字号、颜色、行高
- 左侧辅助工具区的图标排列和间距
- 右侧功能区的图标排列和按钮形态
- 输入态、空态、聚焦态、禁用态、录音态、生成中态的视觉一致性
- 键盘弹出后输入区的贴底表现和安全区处理

## 3. 视觉基准

### 3.1 容器结构

输入框采用一个整体卡片式容器，而不是传统的单行文本框。

参考特征：

- 外层是大圆角卡片
- 边框颜色偏浅灰
- 背景是接近白色或极浅灰
- 有非常轻的阴影或浮起感
- 内容在卡片内垂直方向保留较大留白

### 3.2 文案表现

占位文案为：

- `今天我能帮您什么？`

或在更通用场景下使用：

- `输入消息...`

要求：

- 左上对齐
- 字号偏大
- 字重偏轻
- 颜色低对比度灰色

### 3.3 图标区布局

输入框内部应保留左右两组工具。

左侧：

- 聊天/模式图标
- 下拉箭头
- 加号

右侧：

- 用户/身份入口
- 模型入口
- 语音入口
- 发送/停止按钮

右侧最后一个主按钮应使用高强调色，当前截图为蓝色高亮圆角按钮。

## 4. SwiftUI 组件拆分

建议将输入区拆成以下 SwiftUI 组件，确保后续和 Web 端语义一致：

- `AIChatComposerContainer`
- `AIChatComposerTextArea`
- `AIChatComposerLeadingTools`
- `AIChatComposerTrailingTools`
- `AIChatComposerSendButton`
- `AIChatComposerVoiceButton`
- `AIChatComposerModelButton`
- `AIChatComposerAccountButton`

拆分原则：

- 外层容器只负责布局、背景、边框和阴影
- 中间文本区只负责输入和占位
- 工具按钮独立封装，保证图标、触控区域、禁用态可复用
- 发送按钮和停止按钮应共享同一位置，只切换样式与行为

## 5. 布局建议

### 5.1 外层尺寸

建议输入框使用：

- 最大宽度跟随屏幕自适应
- 内边距充足
- 高度采用内容驱动，但需要设置最小高度
- 圆角足够大，接近“胶囊卡片 + 大圆角面板”的混合形态

### 5.2 内部排列

建议采用三段式结构：

1. 顶部为占位或输入正文
2. 中部为主要输入区域
3. 底部为工具栏与动作按钮

这样可以兼容：

- 单行输入
- 多行输入
- 生成中停止按钮
- 语音录入中状态

### 5.3 安全区与键盘

输入框必须支持：

- 键盘弹出时固定在底部安全区上方
- iPhone 刘海屏底部安全区适配
- iPad 分屏和悬浮键盘适配
- 键盘收起后平滑回落

## 6. 状态定义

输入框至少需要以下状态：

- `idle`
- `focused`
- `typing`
- `sending`
- `generating`
- `voiceListening`
- `disabled`
- `error`

状态之间的切换要求：

- `idle -> focused` 时高亮边框或强调背景
- `typing -> sending` 时发送按钮可见
- `sending -> generating` 时发送按钮切换为停止按钮
- `voiceListening` 时麦克风按钮进入激活态
- `disabled` 时所有可交互项降级显示

## 7. 交互要求

### 7.1 输入行为

- 支持键盘输入
- 支持多行自动增长
- 支持回车发送或换行，需与产品策略一致
- 输入为空时发送按钮应禁用

### 7.2 工具按钮行为

左侧工具：

- 聊天/模式切换入口
- 下拉菜单
- 添加附件或快捷能力入口

右侧工具：

- 用户身份入口
- 模型切换入口
- 语音输入入口
- 发送/停止主按钮

### 7.3 生成中行为

当对话生成中：

- 主按钮切换为停止按钮
- 输入框不应整体抖动
- 工具按钮位置不应变化
- 停止按钮需有明确可点击面积

## 8. 与 Web 对齐的关键点

### 8.1 结构一致

SwiftUI 不能只做“长得像”，而要保持结构语义一致：

- Web 的输入容器 -> SwiftUI 容器
- Web 的 icon group -> SwiftUI 左右工具栏
- Web 的 primary action -> SwiftUI 发送/停止按钮

### 8.2 动作一致

同一状态下，Web 和 iOS 应该呈现相同的动作逻辑：

- 空态不允许发送
- 正在生成时显示停止
- 语音输入时按钮状态联动
- 聚焦时输入区强调

### 8.3 视觉一致

需重点控制：

- 圆角半径
- 边框颜色
- 按钮尺寸
- 图标视觉权重
- 内部间距
- 占位字体大小

## 9. 关键技术方案

### 9.1 推荐实现方式

输入框采用 SwiftUI 原生实现，不使用 WebView。

建议技术组合：

- `SwiftUI`
- `TextEditor` 或自定义多行输入控件
- `GeometryReader` 处理尺寸自适应
- `safeAreaInset` 或底部容器布局处理键盘
- `FocusState` 管理焦点
- `ScrollViewReader` 处理自动滚动

### 9.2 输入区技术细节

需要解决的关键问题：

- `TextEditor` 默认样式与 Web 不一致
- 占位文案需要自定义层叠实现
- 工具按钮需要保证 44pt 以上点击区域
- 多行高度增长时，外层容器不能突然跳变

### 9.3 键盘联动

建议通过统一的键盘状态管理层驱动：

- 键盘高度变化
- 底部输入区位移
- 动画曲线同步
- 焦点恢复和收起

## 10. 组件内容要求

SwiftUI 组件内容必须与 Web 一致，至少包含：

- 统一的占位文案策略
- 统一的图标集合
- 统一的按钮顺序
- 统一的生成中状态
- 统一的禁用态表现
- 统一的输入区边界样式

如果 Web 端存在的工具入口在 iOS 暂时不可用，也不能直接删除，应在组件中保留语义位，必要时先隐藏，但结构要预留。

## 11. 关键代码示意

以下为职责骨架示意，只描述实现方式，不直接落业务代码。

```swift
struct AIChatComposerView: View {
    @Binding var text: String
    let state: AIChatComposerState
    let onSend: () -> Void
    let onStop: () -> Void
    let onAttach: () -> Void
    let onVoice: () -> Void
    let onModelTap: () -> Void
    let onAccountTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            AIChatComposerTextArea(text: $text, state: state)
            AIChatComposerToolbar(
                state: state,
                onSend: onSend,
                onStop: onStop,
                onAttach: onAttach,
                onVoice: onVoice,
                onModelTap: onModelTap,
                onAccountTap: onAccountTap
            )
        }
    }
}
```

```swift
enum AIChatComposerState {
    case idle
    case focused
    case typing
    case sending
    case generating
    case voiceListening
    case disabled
    case error
}
```

```swift
struct AIChatComposerTextArea: View {
    @Binding var text: String
    let state: AIChatComposerState

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("今天我能帮您什么？")
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
        }
    }
}
```

## 12. 验收标准

以下内容需要通过验收：

- 输入框在视觉上与 Web 端高度接近
- 图标位置、间距、尺寸一致
- 占位文案位置一致
- 键盘弹出后底部贴合正确
- 生成中按钮切换自然
- 输入框在空态、输入态、生成态之间没有布局抖动

## 13. 风险点

- 原生 `TextEditor` 默认样式偏系统化，必须重做背景和占位层
- 多行高度变化容易导致工具栏漂移
- 语音、模型、账号入口如果没有统一状态模型，后续容易和 Web 分叉
- 键盘处理若散落在各页面，会造成不同页面行为不一致

## 14. 后续建议

建议后续再拆两份附属工单：

1. 输入框动画与键盘联动工单
2. 输入框工具栏与按钮状态工单

这样可以把视觉对齐和交互对齐分开推进，降低一次性改动风险。
