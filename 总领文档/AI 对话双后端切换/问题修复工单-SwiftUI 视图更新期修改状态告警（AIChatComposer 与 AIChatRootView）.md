# 问题修复工单-SwiftUI 视图更新期修改状态告警（AIChatComposer 与 AIChatRootView）

## 1. 背景

当前 `SupportClient` AI 对话页在 SwiftUI 运行时出现如下告警：

```text
SupportClient - 58818
SwiftUI
/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIChatComposer.swift:85 Modifying state during view update, this will cause undefined behavior.

/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIChatComposer.swift:85 Modifying state during view update, this will cause undefined behavior.

/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIChatRootView.swift:173 Modifying state during view update, this will cause undefined behavior.

/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIChatRootView.swift:173 Modifying state during view update, this will cause undefined behavior.
```

这类告警不是普通日志噪声。

它说明：

> 在 SwiftUI 正在执行一次视图更新时，代码同步改写了 `@State` / `@Binding` / `@StateObject` 相关状态，导致状态变更插入到当前渲染事务中，SwiftUI 认为这会产生未定义行为。

本工单目标是：

1. 找出真实触发链路。
2. 逐行分析为什么会在视图更新期改状态。
3. 明确这不是单点问题，而是 `SwiftUI <- UIViewRepresentable 焦点同步` 设计方式的问题。
4. 给出修复方向。

## 2. 直接触发点

### 2.1 `AIChatComposer.swift:85`

文件：

- [AIChatComposer.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIChatComposer.swift)

关键代码：

```swift
private func handleFocusChange(_ focused: Bool) {
    isComposerFocused = focused
    onFocusChange?(focused ? .composer : nil)
}
```

对应行号：

- 第 84-87 行
- 告警点是第 85 行：`isComposerFocused = focused`

### 2.2 `AIChatRootView.swift:173`

文件：

- [AIChatRootView.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIChatRootView.swift)

关键代码：

```swift
onFocusChange: { focus in
    keyboardFocus = focus
    viewModel.logComposerFocusChanged(isFocused: focus != nil)
},
```

对应行号：

- 第 169-187 行中的 composer 构造参数
- 告警点是第 173 行：`keyboardFocus = focus`

## 3. 表面看起来是谁改了状态

表面上看：

- `AIChatComposer.swift:85`
  - 修改的是本地 `@State private var isComposerFocused`
- `AIChatRootView.swift:173`
  - 修改的是父级 `@State private var keyboardFocus`

如果只看这两行，会误以为：

- “是不是只要把这两行包一层 `DispatchQueue.main.async` 就行”

但这还不够。

因为真正的问题不在“这两行恰好执行了”，而在：

> 这两个赋值是被 `UIViewRepresentable.updateUIView(...)` 周期内同步触发的 delegate 回调直接打回父层的。

## 4. 真实触发链路

## 4.1 `AIChatRootView` 把 `keyboardFocus` 下发给 `AIChatComposer`

文件：

- [AIChatRootView.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIChatRootView.swift)

关键代码：

- 第 7 行
  - `@State private var keyboardFocus: AIChatKeyboardFocus?`
- 第 169-175 行
  - 把 `keyboardFocus` 传给 composer
  - 同时传入 `onFocusChange`

也就是：

```text
AIChatRootView.@State keyboardFocus
  -> AIChatComposer.keyboardFocus
  -> AIChatComposerTextArea.isFocused
  -> AIChatImeTextView.isFocused
```

## 4.2 `AIChatComposer` 再把焦点状态下发到 `UIViewRepresentable`

文件：

- [AIChatComposer.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIChatComposer.swift)
- [AIChatComposerParts.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIChatComposerParts.swift)

关键代码：

- `AIChatComposer.swift` 第 52-56 行
  - `isFocused: keyboardFocus == .composer`
  - `onFocusChange: handleFocusChange`

这里的语义是：

- 父层告诉 composer：“当前应该不应该聚焦”
- composer 再把这个聚焦意图传给底层 UIKit 输入框

## 4.3 `AIChatImeTextView.updateUIView(...)` 在视图更新期同步做焦点切换

文件：

- [AIChatImeTextView.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIChatImeTextView.swift)

关键代码：

```swift
func updateUIView(_ uiView: UITextView, context: Context) {
    context.coordinator.parent = self
    if uiView.text != text {
        uiView.text = text
    }
    uiView.isEditable = isEnabled
    uiView.isSelectable = isEnabled
    uiView.alpha = isEnabled ? 1 : 0.55
    context.coordinator.refreshPlaceholder(for: uiView)
    context.coordinator.recalculateHeight(for: uiView, force: true)
    context.coordinator.syncFocus(for: uiView)
}
```

对应行号：

- 第 43-54 行

最关键的是最后一行：

- 第 53 行：`context.coordinator.syncFocus(for: uiView)`

`updateUIView(...)` 本身就运行在 SwiftUI 正在更新视图的阶段。

也就是说：

> 这里不是用户自然点击后触发焦点，而是 SwiftUI 在刷新 `UIViewRepresentable` 时，主动同步 UIKit 的 first responder 状态。

## 4.4 `syncFocus(for:)` 会同步触发 UIKit responder 切换

同文件关键代码：

```swift
func syncFocus(for textView: UITextView) {
    if parent.isFocused {
        if !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
    } else if textView.isFirstResponder {
        textView.resignFirstResponder()
    }
}
```

对应行号：

- 第 127-135 行

这里的问题是：

- `becomeFirstResponder()`
- `resignFirstResponder()`

都可能同步触发 delegate 回调：

- `textViewDidBeginEditing`
- `textViewDidEndEditing`

## 4.5 delegate 回调又同步回到了 SwiftUI 状态

同文件关键代码：

```swift
func textViewDidBeginEditing(_ textView: UITextView) {
    parent.onFocusChange?(true)
}

func textViewDidEndEditing(_ textView: UITextView) {
    parent.onFocusChange?(false)
}
```

对应行号：

- 第 119-125 行

这意味着：

```text
SwiftUI updateUIView
  -> syncFocus
  -> becomeFirstResponder / resignFirstResponder
  -> UITextViewDelegate begin/end editing
  -> parent.onFocusChange?(...)
```

而这个 `parent.onFocusChange` 就是上层 SwiftUI 闭包。

## 4.6 回到 `AIChatComposer.handleFocusChange`

文件：

- [AIChatComposer.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIChatComposer.swift)

关键代码：

```swift
private func handleFocusChange(_ focused: Bool) {
    isComposerFocused = focused
    onFocusChange?(focused ? .composer : nil)
}
```

对应结果：

- 第 85 行改了 composer 自己的 `@State`
- 第 86 行又继续把变更向父层上传

这就导致第一层告警：

- `AIChatComposer.swift:85`

## 4.7 再回到 `AIChatRootView.onFocusChange`

文件：

- [AIChatRootView.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIChatRootView.swift)

关键代码：

```swift
onFocusChange: { focus in
    keyboardFocus = focus
    viewModel.logComposerFocusChanged(isFocused: focus != nil)
},
```

这里又同步改了父级 `@State keyboardFocus`

于是第二层告警出现：

- `AIChatRootView.swift:173`

## 5. 完整问题链路图

当前真实链路是：

```text
AIChatRootView.body
  -> AIChatComposer
  -> AIChatImeTextView.updateUIView(...)
  -> Coordinator.syncFocus(...)
  -> UITextView.becomeFirstResponder()/resignFirstResponder()
  -> textViewDidBeginEditing/textViewDidEndEditing
  -> parent.onFocusChange?(...)
  -> AIChatComposer.handleFocusChange(...)
  -> isComposerFocused = focused            // AIChatComposer.swift:85
  -> onFocusChange?(...)
  -> AIChatRootView.keyboardFocus = focus   // AIChatRootView.swift:173
```

本质问题是：

> UIKit 焦点同步动作发生在 `updateUIView(...)` 中，而 delegate 回调又同步回写到 SwiftUI `@State`，形成“视图更新期间再次修改状态”的递归链。

## 6. 为什么这是未定义行为

SwiftUI 的视图更新周期要求：

- `body`
- `updateUIView`
- layout / diff / reconciliation

这些阶段应该主要是“消费状态，刷新 UI”

不应该在同一轮更新里：

- 再同步回写同一棵视图树的 `@State`
- 再触发新的局部 state transaction

否则会产生：

1. 重复渲染
2. 焦点抖动
3. 动画事务错乱
4. 某些机型/输入法下的 first responder 循环
5. 难以复现的 keyboard 状态错乱

所以 SwiftUI 才会明确报：

```text
Modifying state during view update, this will cause undefined behavior.
```

## 7. 当前代码中还有同类风险点

本次日志只报到了 composer，但同一模式在 Ask User 输入链路中也存在相同结构。

同文件：

- [AIChatImeTextView.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIChatImeTextView.swift)

另一个组件：

- `AIChatImeTextField`

关键代码：

- 第 183-190 行 `updateUIView(...)`
  - 同样调用 `context.coordinator.syncFocus(for: uiView)`
- 第 203-209 行
  - `textFieldDidBeginEditing`
  - `textFieldDidEndEditing`
  - 同样同步执行 `parent.onFocusChange?(...)`

这意味着：

> Ask User 卡片中的文本输入也存在同类“updateUIView 期间触发 delegate，再回写 SwiftUI 状态”的结构风险，只是本次日志尚未明确打到那条路径。

## 8. 根因判断

这次问题的根因不是：

- `AIChatComposer.swift:85` 这一行单独有问题
- `AIChatRootView.swift:173` 这一行单独有问题

真正根因是：

### 8.1 焦点同步职责耦合过深

当前一个焦点变化同时承担了三件事：

1. UIKit first responder 控制
2. SwiftUI 视觉焦点状态 `isComposerFocused`
3. 父层键盘焦点路由 `keyboardFocus`

而这三件事通过同步闭包串在一个事务里。

### 8.2 `updateUIView` 不应该直接驱动会反向回写状态的操作

`updateUIView` 当前做了：

- 设置 text
- 设置 enabled
- 计算高度
- 同步焦点

前面几项是“单向刷新 UI”。

最后一项 `syncFocus` 却会通过 delegate 再反向触发状态写入。

这正是设计边界错位。

### 8.3 delegate 回调没有和 SwiftUI 更新事务隔离

当前：

- `textViewDidBeginEditing`
- `textViewDidEndEditing`

直接同步调用：

- `parent.onFocusChange?(...)`

这没有把 UIKit 事件与 SwiftUI 渲染事务隔离开。

## 9. 修复方向

### 9.1 第一优先级：把 focus 回写异步化，脱离当前视图更新事务

最小修复原则：

- 不要在 `updateUIView -> syncFocus -> delegate` 同步链路内直接写 SwiftUI `@State`

至少需要把：

- `AIChatComposer.handleFocusChange`
- `AIChatRootView.onFocusChange`
- `AIChatImeTextView` / `AIChatImeTextField` delegate 回调

中的状态回写改成下一轮 main runloop 再执行。

也就是：

- 把 UIKit delegate 事件变成“异步通知”
- 不要在当前 `updateUIView` 事务里同步改 state

### 9.2 第二优先级：避免无意义的焦点回写

当前 begin/end editing 每次都直接回调。

应增加保护：

- 如果目标状态没有变化，不要继续回写
- 如果本轮焦点本来就是 `.composer`，不要重复写 `keyboardFocus = .composer`
- 如果 `isComposerFocused` 已经等于 `focused`，不要再写

这可以减少重复事务和重复告警。

### 9.3 第三优先级：拆开“显示焦点状态”和“键盘控制状态”

当前：

- `isComposerFocused`
- `keyboardFocus`

都在被同一条 UIKit 事件驱动。

建议拆分：

1. `keyboardFocus`
   - 表示“路由意图”，由父层控制谁应该获得焦点
2. `isComposerFocused`
   - 表示“当前 UITextView 是否真的进入编辑态”
   - 更适合只作为展示态，且异步同步

否则就容易形成：

```text
父层想聚焦
 -> 子层同步焦点
 -> UIKit 回调
 -> 子层又写回
 -> 父层又写回
```

### 9.4 第四优先级：统一审计 `AIChatImeTextView` 与 `AIChatImeTextField`

不能只修 `composer`。

还需要一起审计：

- Ask User 文本输入
- 未来其他需要 programmatic focus 的输入组件

否则 composer 告警修掉后，Ask User 输入链路还会继续报同类警告。

## 10. 建议实施步骤

1. 先冻结当前问题为“焦点同步导致的视图更新期状态写入”，不要误归因为某个普通 `@State` 赋值。
2. 在 `AIChatImeTextView` / `AIChatImeTextField` 侧隔离 delegate 回调，不同步直写上层状态。
3. 给 `AIChatComposer.handleFocusChange` 增加幂等保护与异步调度。
4. 给 `AIChatRootView` 的 `onFocusChange` 增加幂等保护，避免重复写 `keyboardFocus`。
5. 回归验证：
   - composer 点击聚焦
   - 键盘关闭
   - 会话切换
   - Ask User 文本问题聚焦
   - Ask User 选项切换后再回到输入框

## 11. 验收标准

- 不再出现：
  - [AIChatComposer.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIChatComposer.swift:85) `Modifying state during view update`
  - [AIChatRootView.swift](/Users/hua/Documents/project/DeepTutor/SupportClient/SupportClient/Projects/Features/AIChat/Presentation/AIChatRootView.swift:173) `Modifying state during view update`
- composer 获取焦点、失去焦点、发送消息时不发生键盘抖动
- Ask User 文本输入链路不新增同类 SwiftUI 告警
- 焦点高亮、底部输入框样式、键盘路由行为保持现有产品表现不退化

## 12. 最终结论

当前问题本质上是：

> `UIViewRepresentable.updateUIView(...)` 中同步执行了 UIKit 焦点切换，而焦点切换又通过 delegate 同步回写到 SwiftUI `@State`，形成“视图更新期间修改状态”的未定义行为。

所以这不是单点赋值 bug，而是：

- `AIChatComposer`
- `AIChatRootView`
- `AIChatImeTextView`
- `AIChatImeTextField`

这组焦点同步设计需要一起修正的结构性问题。
