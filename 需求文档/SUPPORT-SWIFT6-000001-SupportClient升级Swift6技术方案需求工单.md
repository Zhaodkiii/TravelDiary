# SUPPORT-SWIFT6-000001：SupportClient 升级 Swift 6 技术方案需求工单

> 状态：新需求 / 待评审 / 待实现  
> 文档性质：迁移总工单与技术实施方案  
> 约束：本文只定义范围、方案、步骤、风险与验收标准，不直接实施代码修改。  
> 经验来源：`SparkClient` 当前工作区中尚未提交的 Swift 6 迁移改动，以及迁移期间已暴露的 Debug、运行时和 Release Archive 问题。

## 0. 工单摘要

| 项目 | 内容 |
| --- | --- |
| 工单号 | `SUPPORT-SWIFT6-000001` |
| 目标项目 | `/Users/hua/Downloads/Reference/SupportClient` |
| 参考项目 | `/Users/hua/Downloads/Reference/SparkClient` |
| 当前语言版本 | Swift 5（工程中 `SWIFT_VERSION = 5.0`） |
| 目标语言版本 | Swift 6 |
| 默认隔离策略 | 保留 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` |
| 迁移策略 | 风险分层、同源文件对照、逐阶段编译、Debug 与 Release 双轨验收 |
| 主要范围 | App、Core、AI Runtime、AISettings、OSS/OCR、Memory、Markdown、SecondCamera、Tests |
| 非目标 | 不迁入 SparkClient 独有的聊天、医疗、营养、健康、知识库等业务代码 |
| 是否直接实现 | 否 |

## 1. 背景与目标

SupportClient 与 SparkClient 共享大量基础设施和相机编辑代码。SparkClient 已经进行一轮大范围 Swift 6 迁移，当前未提交改动中包含编译隔离、`Sendable`、Objective-C 回调桥接、静态共享状态、UIKit/MainActor 边界和 Release 优化器问题的处理经验。

SupportClient 当前工程已经提前开启：

```text
SWIFT_APPROACHABLE_CONCURRENCY = YES
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
```

但 App 与 Tests 的 Debug/Release 配置仍使用：

```text
SWIFT_VERSION = 5.0
```

这意味着 SupportClient 已具备接近 Swift 6 的默认隔离语义，但尚未接受 Swift 6 完整语言模式和严格并发检查。直接把所有配置切换到 Swift 6，预计会集中暴露同源模块中的 actor isolation、`Sendable`、跨语言回调和 Release 优化问题。

本工单的目标是：

1. 将 SupportClient App target 与 Test target 的 Debug、Release 配置升级到 Swift 6。
2. 保持默认 MainActor 策略，不通过回退隔离策略掩盖问题。
3. 复用 SparkClient 已验证的迁移模式，减少重复排查。
4. 只迁移并发语义和必要的安全重构，不覆盖 SupportClient 已存在的业务差异。
5. 完成 Debug、Release、真机、Archive 与关键功能回归。
6. 建立后续两个客户端同源模块的 Swift 6 同步规则。

## 2. 代码盘点结论

### 2.1 工程规模

静态盘点结果：

| 指标 | SparkClient | SupportClient |
| --- | ---: | ---: |
| Swift 文件总量 | 约 1160 | 348 |
| SparkClient 本轮已修改 Swift 文件 | 166 | - |
| 与上述改动同名的 SupportClient 文件 | - | 62 |
| SupportClient Objective-C `.m/.h` 文件 | - | 115 |
| SupportClient 含 continuation 的 Swift 文件 | - | 7 |
| SupportClient 含 `@unchecked Sendable` 的 Swift 文件 | - | 17 |
| SupportClient 含 `deinit` 的 Swift 文件 | - | 6 |

62 个同名文件没有字节级完全一致的文件，因此不能整文件覆盖；必须以 SparkClient 的并发修复意图为参考，对 SupportClient 当前实现逐项适配。

### 2.2 SupportClient 模块分布

| 模块 | Swift 文件量 | 风险判断 |
| --- | ---: | --- |
| SecondCamera | 201 | 最高；UIKit、AVFoundation、Vision、CALayer、静态状态和历史编辑器工具较集中 |
| AISettings | 41 | 高；模型、仓储、Provider、CoreData 与 UI 隔离交叉 |
| Core 根目录 | 38 | 高；网络、数据库、AI Runtime、文件存储等跨任务基础设施 |
| App | 14 | 中高；组合根、启动流程、状态对象通常属于 MainActor |
| OCR | 10 | 高；Vision/Objective-C completion 与 continuation 桥接 |
| Markdown | 7 | 中高；UIKit/TextKit、缓存和后台渲染边界 |
| OSS | 6 | 最高；Objective-C SDK 回调与非 Sendable result 跨边界 |
| Memory | 6 | 中高；Domain 模型、Repository、CoreData 隔离一致性 |
| Core UI | 6 | 中；明确 MainActor 与非 UI 数据边界 |
| Foundation | 6 | 中；静态共享状态、编码器和锁的并发语义 |

### 2.3 SupportClient 已具备的基础

SupportClient 当前并不是从零开始：

- 已有 61 个文件显式使用 `@MainActor`。
- 已有 34 个文件出现 `nonisolated`。
- 已有 11 个文件使用 actor。
- 已有 76 个文件声明或引用 `Sendable`。
- SecondCamera 的 Vision 人脸识别已经采用非隔离 helper 和主线程 UI 回切。
- 部分静态共享状态已经使用 `nonisolated(unsafe)`。

因此迁移重点不是机械添加注解，而是补齐 Swift 5 模式尚未强制验证的边界，并清理已经过度或不准确的 `unsafe` 使用。

## 3. SparkClient 迁移经验总结

### 3.1 默认 MainActor 会影响非 UI 声明

启用 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 后，未标注的结构体、枚举、静态工具、DTO、协议实现和闭包都可能被推断为 MainActor 隔离。它们一旦被 actor、后台任务、URLSession、Vision 或 Objective-C SDK 使用，就会出现：

- `main actor-isolated` 成员无法从非隔离上下文调用；
- protocol requirement 与 actor-isolated witness 不匹配；
- `sending` 参数可能导致数据竞争；
- 回调在后台队列执行时命中 `_swift_task_checkIsolatedSwift`。

经验原则：

- UI、ViewModel、路由和应用生命周期保留或显式使用 `@MainActor`。
- 纯 DTO、枚举、错误描述、格式化前的值模型、编码 payload 和无状态算法优先使用普通 `nonisolated`。
- 不要为了减少报错把整个模块标记 `nonisolated(unsafe)`。

### 3.2 `Sendable` 必须表达真实所有权

SparkClient 迁移中大量问题来自闭包、Repository、SDK 对象和共享单例跨任务传递。

采用顺序：

1. 值类型优先声明 `Sendable`，成员也必须可发送。
2. 可变状态优先放入 actor 或由锁完整保护。
3. 回调跨任务时声明 `@Sendable`，并检查捕获值。
4. 只有已经由锁、串行执行器或外部契约保证安全的引用类型，才允许 `@unchecked Sendable`。
5. `nonisolated(unsafe)` 只用于无法由类型系统表达、且有明确外部同步机制的窄边界。

禁止把 `@unchecked Sendable` 当成消除编译错误的通用手段。

### 3.3 不要让锁跨越 `await`

SparkClient 的 OSS 凭证刷新表明，传统写法容易在持锁状态创建任务、等待异步结果或遗漏解锁。

推荐模式：

```swift
private nonisolated func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
}
```

锁内只读取或更新同步状态，并产生“立即返回值”或“待等待 Task”；真正的 `await task.value` 必须在锁外执行。

### 3.4 Objective-C / 系统回调是运行时高风险边界

Swift 6 无法从旧 Objective-C Block 接口完整推导 actor 和 `Sendable` 语义。代码可能通过编译，却在 SDK 后台队列进入 Swift 闭包时崩溃。

已知案例：

- OSS `OSSTask` 在后台 `NSOperationQueue` 调用被默认推断为 MainActor 的 `successBlock`；
- Vision 在内部队列调用被错误继承 MainActor 的 completion；
- UIKit/Notification/URLSession delegate 的回调线程与 Swift actor 不完全等价。

处理原则：

- 将回调桥接 helper 明确设为 `nonisolated`。
- 回调只解析结果、构造可发送值或恢复 continuation。
- UI 更新显式通过 `Task { @MainActor in ... }` 或 `await MainActor.run`。
- 不要用 `MainActor.assumeIsolated` 对后台回调作虚假承诺。

### 3.5 continuation 不直接返回第三方非 Sendable 对象

SupportClient 当前 OSS 适配层通过 continuation 返回泛型 `T`：

```swift
private func taskResult<T: AnyObject>(_ task: OSSTask<T>) async throws -> T
```

SparkClient 的经验是：这会把 Objective-C SDK result 直接跨越 Swift 并发边界。推荐改成“只等待完成”的 `Void` continuation，等待结束后在适配层读取并立即转换结果：

```swift
private nonisolated func awaitTask<T: AnyObject>(_ task: OSSTask<T>) async throws
```

业务层只接收 `Data`、`URL`、Swift Error 或自有 `Sendable` DTO，不接收 `OSSTask` / `OSSResult`。

### 3.6 静态共享状态优先不可变

对于只初始化一次的格式化结果，SparkClient 已确定以下原则：

```swift
private nonisolated(unsafe) static let zeroDurationString: String? = {
    // 保留国际化动态计算逻辑
}()
```

SupportClient 的 `SecondCameraEditorFormat.swift` 当前仍为 `static var`，迁移时应改为 `static let`。由于初始化闭包内部使用非 Sendable 的 `DateComponentsFormatter`，窄范围保留 `nonisolated(unsafe)`；不可变性可以减少并发写风险，同时保留本地化和 UI 对齐逻辑。

对其他 `static var` 必须逐项分类：

- 计算属性且无状态：改成 `static var` 计算属性或静态函数，并标注正确隔离域；
- 初始化后不变：改成 `static let`；
- 真正共享可变状态：迁入 actor、锁保护容器或 MainActor；
- Preview 数据：确保只参与 Debug/Preview，不误判为生产共享状态。

### 3.7 `deinit` 不能依赖 MainActor 状态

Swift 6 对析构和隔离的检查更严格。控制器、观察者 token、缓存对象在 `deinit` 中访问 MainActor 隔离属性时可能报错。

推荐方式：

- 观察者 token 存储设计为可在析构上下文安全读取；
- 清理逻辑不调用需要 actor hop 的方法；
- 必要时将纯资源句柄存储标记为窄范围 `nonisolated(unsafe)`，并保证只在生命周期边界访问；
- 不在 `deinit` 中创建无法保证执行完成的异步清理任务。

### 3.8 Release Archive 必须作为独立质量门

SparkClient 曾在 Debug 成功后，使用 Swift 6.3.3、Release `-O`、Whole Module Optimization 归档时，崩溃于：

```text
EarlyPerfInliner
SecondCameraEditorBlurWeakRef<T>.deinit
```

根因是泛型弱引用盒子、合成 `deinit`、默认 MainActor 和 Release 优化路径组合触发编译器缺陷。SupportClient 当前保留完全相同的泛型弱引用结构，因此必须提前处理。

推荐将其改成显式 `nonisolated` 的非泛型专用弱引用上下文；不要依赖全局关闭 Release 优化。

## 4. SupportClient 与 SparkClient 的同源范围

### 4.1 可直接复用“修复意图”的模块

| SupportClient 模块 | SparkClient 参考模块 | 可复用内容 |
| --- | --- | --- |
| `Projects/Features/SecondCamera` | `Projects/Features/CustomCamera` | 编辑器工具类隔离、Vision 回调、CALayer/UI 边界、静态状态、Release Archive 规避 |
| `Projects/Core/OSS` | `Projects/Core/OSS` | SDK 回调非隔离桥接、Void continuation、凭证状态锁保护 |
| `Projects/Core/OCR` | `Projects/Core/OCR` | OCR 模型非隔离、Vision continuation、引擎 `Sendable` 边界 |
| `Core/AIRuntime` | `Projects/Core/AIRuntime` | 配置值模型、Provider、搜索模型、流式字节处理 |
| `Projects/Features/AISettings` | `Projects/Features/AISettings` | Domain 模型、种子、Snapshot、Repository 隔离 |
| `Projects/Features/Memory` | `Projects/Features/Memory` | Domain/Repository 非隔离与 CoreData 适配 |
| `Core/Database` | `Projects/Core/Database` | CoreDataStack 的 Sendable 与 continuation 处理 |
| `Projects/Core/Markdown` | `Projects/Core/Markdown` | 后台语法高亮、UI 文档视图和缓存边界 |
| `Core/FileStorage` | `Projects/Core/FileStorage` | 上传 payload、进度回调和 OSS 客户端调用边界 |

### 4.2 不能直接照搬的部分

以下 SparkClient 改动不属于 SupportClient 本工单范围：

- Chat、消息同步、问报告和工具卡片；
- Home 医疗列表、病例、检查报告和用药；
- Nutrition、HealthKit 和健康资源；
- MedicalRecord、Medical Workflow 和医疗 API；
- Knowledge、科普、分享等 SupportClient 当前不存在或语义不同的模块；
- SparkClient 专属 App 路由、登录启动、账号清理和资源文案。

即使文件名相同，也必须保留 SupportClient 的：

- `Support*` 类型命名；
- 自有 API endpoint 和 DTO；
- 自有 CoreData model 与实体名；
- 自有 AppContainer / Bootstrapper 装配方式；
- SecondCamera 已有产品行为和资源路径。

## 5. 目标并发架构

### 5.1 隔离边界

```text
MainActor
  ├─ App 生命周期、路由、SwiftUI/UIKit View
  ├─ Observable ViewModel / UI Store
  └─ UI 状态和用户交互回调

Actor / 锁保护引用类型
  ├─ 可变缓存、凭证刷新、串行请求
  ├─ CoreData 上下文协调
  └─ 长生命周期共享服务状态

nonisolated + Sendable 值域
  ├─ DTO、Domain Model、Error、枚举
  ├─ 编解码 payload、配置解析、纯算法
  └─ Objective-C / Vision / OSS 回调桥接入口
```

依赖方向保持：

```text
App/UI → Feature/Application → Repository/Service → Core/Adapter
```

底层 SDK adapter 不应依赖 MainActor；它只向上暴露可发送的 Swift 值。

### 5.2 注解决策表

| 场景 | 首选方案 | 禁止默认选择 |
| --- | --- | --- |
| View / ViewModel / UIKit 控制器 | `@MainActor` | `nonisolated(unsafe)` |
| 纯 struct/enum/DTO | `nonisolated` + `Sendable`（适用时） | 整体 `@MainActor` |
| 无状态算法/格式转换 | `nonisolated` 函数或类型 | 强制主线程运行 |
| 共享可变状态 | actor 或完整锁保护 | 裸 `static var` |
| 锁保护引用类型跨任务 | 审核后 `@unchecked Sendable` | 未说明同步契约的 unchecked |
| Objective-C completion | `nonisolated` adapter + 值转换 | 假设回调在主线程 |
| 一次初始化非 Sendable formatter | 窄范围 `nonisolated(unsafe) static let` | 可写 `static var` |
| UI 回调 | 显式切换 `MainActor` | 从 SDK 队列直接更新 UIKit |

## 6. 分阶段实施方案

### 阶段 0：建立迁移基线

1. 创建独立迁移分支，不与功能开发混合。
2. 记录当前 Xcode、Swift、macOS 与 iOS SDK 版本。
3. 在 Swift 5 模式完成一次 Debug、Release 和 Archive 基线。
4. 记录现有 warning、测试失败和已知运行问题，避免迁移后误归因。
5. 保存 SupportClient 当前 348 个 Swift 文件清单和 target membership。

交付物：基线构建日志、已知问题清单、工具链版本记录。

### 阶段 1：切换工程语言版本

将以下构建配置中的 `SWIFT_VERSION` 从 `5.0` 调整为 `6.0`：

- SupportClient App target / Debug；
- SupportClient App target / Release；
- SupportClientTests target / Debug；
- SupportClientTests target / Release。

保留：

```text
SWIFT_APPROACHABLE_CONCURRENCY = YES
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
```

不要在该阶段同时：

- 关闭默认 MainActor；
- 全局添加 `-Onone`；
- 批量添加 `@unchecked Sendable`；
- 顺手重构业务逻辑或目录结构。

先收集完整编译错误，按本工单后续阶段分类处理。

### 阶段 2：迁移纯数据与协议层

优先处理最底层的类型，以减少上层连锁错误：

1. AI Runtime / AISettings 配置模型；
2. OCR 模型；
3. Memory Domain 模型与 Repository 协议；
4. FileStorage payload；
5. 网络请求/响应 DTO、错误和编码 payload；
6. 静态本地化、解析和纯计算 helper。

处理要求：

- 纯模型从隐式 MainActor 解耦；
- Codable/Equatable/Hashable/LocalizedError witness 与协议隔离一致；
- 数组、字典和闭包成员逐项满足 Sendable；
- 不把 UIKit、CoreData managed object 或第三方 SDK 对象放入 Sendable DTO。

### 阶段 3：迁移共享服务和基础设施

按以下顺序处理：

1. CoreDataStack；
2. AI Runtime gateway / provider；
3. AISettings Repository；
4. Memory Repository；
5. FileStorage；
6. OSSManager / OSSClient；
7. OCR engines。

重点审核：

- actor 中保存的依赖是否 Sendable；
- `Task` 是否捕获非 Sendable self；
- 锁是否跨 `await`；
- completion 是否被恢复多次；
- URLSession/stream iterator 是否通过高阶函数隐式跨隔离；
- CoreData 对象是否离开其 context/queue。

### 阶段 4：优先修复跨语言回调

#### OSS

SupportClient 当前的 `OSSClient.taskResult<T>` 应参考 SparkClient 改为非隔离、只等待完成的桥接，避免：

- Objective-C SDK 后台队列调用 MainActor 闭包导致运行时断言；
- `OSSResult` 泛型对象跨并发边界；
- continuation 泛型推断和 Sendable 诊断。

`OSSManager` 应参考 SparkClient 的同步边界：

- 类型明确为非 UI 服务；
- provider closure 为 `@Sendable`；
- 客户端、凭证和刷新任务统一由锁保护；
- 锁内决定复用或创建 refresh task，锁外等待结果。

#### OCR / Vision

- Vision completion 在 `nonisolated` helper 内创建；
- completion 只输出 `String`、`CGRect` 数组或自有 Sendable DTO；
- UIKit 图像和页面状态只在 MainActor 使用；
- continuation 明确写出成功值和 Error 类型，避免 Swift 6 推断歧义。

### 阶段 5：迁移 SecondCamera

SecondCamera 占 SupportClient Swift 源码的一半以上，应拆分处理，禁止一次性全目录机械替换。

推荐顺序：

1. Editing/Support 中的锁、Atomic、缓存、格式化、文件系统和字符串工具；
2. Editing/UIKitExtensions 中的纯几何与 UIKit 扩展；
3. ImageEditor item/model/transform；
4. Sticker、Canvas、Stroke；
5. ViewController、手势、通知和 `deinit`；
6. Vision 自动模糊；
7. Preview loader、相册读取和保存；
8. Camera manager、AVFoundation session 和计时器。

明确复用 SparkClient 的已知处理：

- `SecondCameraEditorFormat.zeroDurationString` 保留动态国际化逻辑并由 `var` 改为 `let`；
- Atomic、UnfairLock、LRUCache、DataSourcePath 等非 UI 支撑类型显式 `nonisolated`；
- UI 类和 UIKit API 保持 MainActor，不因编译方便整体取消隔离；
- Vision callback 使用非隔离 helper；
- `SecondCameraEditorBlurWeakRef<T>` 改为显式非隔离的非泛型专用弱引用上下文；
- `deinit` 中的 observer/token 清理不依赖 actor hop；
- 静态 mutable 数组、timer 列表和 orientation lock 必须有明确同步所有者。

### 阶段 6：App 与测试目标收口

1. App 生命周期、Container、Bootstrapper、页面状态保持 MainActor。
2. 工厂闭包根据产物声明 `@MainActor` / `@Sendable`。
3. 测试用例若直接创建 UI/ViewModel，测试类型或方法标注 `@MainActor`。
4. actor/service 测试使用 `await`，不使用不安全的同步等待。
5. 清理仅为过渡添加但已不再需要的 `unsafe` 注解。

### 阶段 7：Release 与 Archive 专项

1. 使用 Release `-O` 编译真机 arm64。
2. 保持 Whole Module Optimization 完成 Archive。
3. 若出现 `swift-frontend` stack dump，先定位日志中的具体 SILFunction，不把它误判为普通源码错误。
4. 优先缩小触发类型的泛型、弱引用、合成 `deinit` 或隔离组合。
5. 只有紧急发版时才对单文件临时使用 `-Onone`，不得全局关闭优化。

## 7. 首批重点文件清单

### P0：已知会复现 SparkClient 风险

| SupportClient 文件 | 风险 | 计划 |
| --- | --- | --- |
| `Projects/Core/OSS/OSSClient.swift` | Objective-C 后台回调继承 MainActor；返回非 Sendable SDK result | 非隔离 Void continuation adapter |
| `Projects/Core/OSS/OSSManager.swift` | 凭证、client、refresh Task 共享可变状态 | 锁内决策、锁外 await、Sendable provider |
| `Projects/Features/SecondCamera/.../SecondCameraImageEditorViewController+Blur.swift` | Release EarlyPerfInliner 在泛型弱引用 `deinit` 崩溃 | 非泛型专用弱引用上下文 |
| `Projects/Features/SecondCamera/.../SecondCameraEditorFormat.swift` | `nonisolated(unsafe) static var` 可写共享状态 | 保留动态格式化，改 `static let` |
| `Projects/Features/SecondCamera/.../SecondCameraEditorLRUCache.swift` | 静态延迟释放数组与 `deinit` | 明确锁与非隔离边界 |
| `Projects/Features/SecondCamera/.../SecondCameraEditorAppContextImpl.swift` | bootstrap 静态状态 | 一次初始化与并发保护审计 |

### P1：同源迁移高复用区

- `AISettingsDomainModels.swift`
- `AISettingsSeedLoader.swift`
- `AISettingsSnapshot.swift`
- `DefaultAISettingsRepository.swift`
- `AIRuntimeModels.swift`
- `SearchRuntimeConfigResolver.swift`
- `SearchRuntimeModels.swift`
- `LocalModelService.swift`
- `SmallTask.swift`
- `OCRModels.swift`
- `AliyunOCREngine.swift`
- `VisionOCREngine.swift`
- `LocalServerOCREngine.swift`
- `MedicalImagePreprocessor.swift`
- `MedicalTermsCorrector.swift`
- `OCRFusionSelector.swift`
- `CoreDataStack.swift`
- `FileTransferService.swift`
- `MemoryModels.swift`
- `MemoryRepository.swift`
- `MemorySearchEngine.swift`
- `MarkdownCodeSyntaxHighlighter.swift`
- `MarkdownDocumentView.swift`

### P2：SecondCamera 支撑与 UI 边界

- `SecondCameraEditorAtomicValue.swift`
- `SecondCameraEditorUnfairLock.swift`
- `SecondCameraEditorDataSourcePath.swift`
- `SecondCameraEditorDispatchQueue.swift`
- `SecondCameraEditorFileSystem.swift`
- `SecondCameraEditorImageSource.swift`
- `SecondCameraEditorImageQuality.swift`
- `SecondCameraEditorLRUCache.swift`
- `SecondCameraEditorMath.swift`
- `SecondCameraEditorMathExt.swift`
- `SecondCameraEditorString.swift`
- `SecondCameraEditorStringSanitizer.swift`
- `SecondCameraEditorUIStubs.swift`
- `SecondCameraEditorSticker.swift`
- `SecondCameraImageEditorCanvasView.swift`
- `SecondCameraImageEditorStrokeItem.swift`
- `SecondCameraImageEditorTransform.swift`
- `SecondCameraColorPickerBar.swift`
- `SecondCameraEditorColor.swift`
- `SecondCameraEditorFont+TextStyle.swift`
- `SecondCameraEditorUIGeometry.swift`
- `SecondCameraEditorUIKitImage.swift`

## 8. 实施规则

### 8.1 允许复用

- 可逐 hunk 参考 SparkClient 当前工作区 diff。
- 可复用并发注解意图、锁策略、continuation 结构和回调线程模型。
- 对真正同源的 SecondCamera helper，可在确认业务代码一致后移植最小修改。
- 每次移植必须以 SupportClient 当前文件为基底。

### 8.2 禁止操作

- 禁止把 SparkClient 的 166 个改动文件整体复制到 SupportClient。
- 禁止通过关闭 Swift 6、默认 MainActor 或 Release 优化完成验收。
- 禁止无说明批量添加 `@unchecked Sendable` / `nonisolated(unsafe)`。
- 禁止在并发迁移中顺带更改产品逻辑、接口字段和页面交互。
- 禁止将第三方 SDK result、CoreData managed object、UIKit 对象直接作为跨 actor 返回值。
- 禁止只验证模拟器 Debug。

### 8.3 每个修改点必须记录

每个迁移提交至少说明：

1. 原始 Swift 6 诊断或运行风险；
2. 声明应该属于哪个隔离域；
3. 是否跨任务传递，以及为什么满足 Sendable；
4. 是否使用 unsafe/unchecked；如果使用，外部同步保证是什么；
5. 对应测试或功能验证。

## 9. 测试与验收方案

### 9.1 编译门槛

- [ ] SupportClient App Debug / iOS Simulator 编译通过。
- [ ] SupportClientTests Debug 编译与执行通过。
- [ ] SupportClient App Release / generic iOS device 编译通过。
- [ ] Product > Archive 成功生成 `.xcarchive`。
- [ ] 无 Swift 6 concurrency error。
- [ ] 无 `swift-frontend` stack dump、`EarlyPerfInliner` 或 SIL pipeline 崩溃。
- [ ] 不依赖全局 `-Onone`、关闭默认 MainActor 或退回 Swift 5。

### 9.2 运行时门槛

- [ ] Main Thread Checker 无新增告警。
- [ ] Thread Sanitizer 覆盖关键共享状态，无新增数据竞争。
- [ ] 不出现 `_swift_task_checkIsolatedSwift`、`dispatch_assert_queue_fail`。
- [ ] continuation 在成功、失败、取消路径均只恢复一次。
- [ ] 页面退出后 ViewModel、相机控制器、预览 loader 和 observer 可正常释放。

### 9.3 功能回归

- [ ] App 冷启动、登录态恢复和退出登录正常。
- [ ] AI 配置读取、模型列表、场景设置和 Repository 持久化正常。
- [ ] OSS 上传、内存下载、文件下载和预签名 URL 正常。
- [ ] STS 过期刷新、失败重试和账号切换清理正常。
- [ ] Vision OCR、其他 OCR engine 和结果融合正常。
- [ ] Markdown 展示、语法高亮和图片加载正常。
- [ ] Memory 读写、搜索和 CoreData 持久化正常。
- [ ] SecondCamera 拍摄、相册选择、预览、编辑、贴纸、画笔、模糊、保存正常。
- [ ] 自动人脸模糊在成功、无人脸、失败、页面提前退出时均正常。

## 10. 提交拆分建议

建议按可独立回滚的提交拆分：

1. `build: switch SupportClient targets to Swift 6`
2. `concurrency: migrate pure models and protocol witnesses`
3. `concurrency: migrate AI runtime and repositories`
4. `concurrency: harden CoreData and file storage boundaries`
5. `concurrency: fix OSS and OCR callback bridges`
6. `concurrency: migrate SecondCamera support utilities`
7. `concurrency: migrate SecondCamera UI boundaries`
8. `build: fix Swift 6 Release archive optimizer blockers`
9. `test: add Swift 6 concurrency regression coverage`

不要把全部迁移压在一个提交中，否则难以定位 Swift 编译器回归和业务行为变化。

## 11. 风险、取舍与回滚

| 风险 | 概率 | 影响 | 应对 |
| --- | --- | --- | --- |
| 批量注解导致错误隔离 | 高 | 运行时崩溃或 UI 越界 | 按职责分类，不机械替换 |
| unsafe/unchecked 扩散 | 中高 | 隐藏真实数据竞争 | 每处记录同步契约并复审 |
| OSS/Vision 回调运行时断言 | 高 | 上传/OCR/模糊功能崩溃 | 优先修复跨语言 adapter |
| SecondCamera 改动面过大 | 高 | 编辑功能回归 | 按 Support、Model、UI、Manager 分批 |
| Release 优化器崩溃 | 中高 | 阻断生产包 | 提前处理泛型弱引用并持续 Archive |
| 整文件复制覆盖业务差异 | 高 | SupportClient 功能倒退 | 只移植最小 diff 意图 |
| CoreData 对象跨队列 | 中 | 数据竞争或崩溃 | 只跨边界传 objectID/DTO |

回滚采用提交级回滚。工程语言版本切换提交最后回滚；优先回滚具体模块迁移提交。紧急发布时可对确认触发编译器缺陷的单文件临时降低优化，但必须建立后续清理项。

## 12. 完成定义

满足以下条件才可关闭工单：

1. App 与 Tests 的 Debug/Release 均为 Swift 6。
2. Debug、Release、真机和 Archive 全部通过。
3. P0 文件全部完成专项处理和回归。
4. 62 个同源重点文件已完成“适用 / 不适用 / 已处理”的逐项记录。
5. 不存在无说明的 `@unchecked Sendable` 或 `nonisolated(unsafe)` 新增。
6. OSS、OCR、SecondCamera、AISettings、Memory、Markdown、CoreData 完成回归。
7. 迁移没有引入 SparkClient 独有业务代码或覆盖 SupportClient 差异。
8. 临时编译参数和迁移期 workaround 已清理或登记明确移除期限。

## 13. 同源文件附录

SparkClient 本轮 Swift 6 改动与 SupportClient 当前源码存在 62 个同名文件，迁移实施时应逐项核对：

```text
AILocalScenarioBundleBuilder.swift
AIRuntimeModels.swift
AISettingsDomainModels.swift
AISettingsSeedLoader.swift
AISettingsSnapshot.swift
AliyunOCREngine.swift
CoreDataStack.swift
DefaultAISettingsRepository.swift
DeviceRegistrationCoordinator.swift
FileTransferService.swift
LocalModelService.swift
LocalServerOCREngine.swift
MarkdownCodeSyntaxHighlighter.swift
MarkdownDocumentView.swift
MedicalImagePreprocessor.swift
MedicalTermsCorrector.swift
MemoryModels.swift
MemoryRepository.swift
MemorySearchEngine.swift
OCRFusionSelector.swift
OCRModels.swift
OSSClient.swift
OSSManager.swift
SearchRuntimeConfigResolver.swift
SearchRuntimeModels.swift
SecondCameraAttachment.swift
SecondCameraColorPickerBar.swift
SecondCameraDefaultStickerStore.swift
SecondCameraEditorAppContext.swift
SecondCameraEditorAppContextImpl.swift
SecondCameraEditorAssertions.swift
SecondCameraEditorAtomicValue.swift
SecondCameraEditorColor.swift
SecondCameraEditorDataSourcePath.swift
SecondCameraEditorDispatchQueue.swift
SecondCameraEditorFileSystem.swift
SecondCameraEditorFont+TextStyle.swift
SecondCameraEditorFormat.swift
SecondCameraEditorImageQuality.swift
SecondCameraEditorImageSource.swift
SecondCameraEditorL10n.swift
SecondCameraEditorL10nBridge.swift
SecondCameraEditorLRUCache.swift
SecondCameraEditorMath.swift
SecondCameraEditorMathExt.swift
SecondCameraEditorMediaUtils.swift
SecondCameraEditorMimeTypeUtil.swift
SecondCameraEditorSticker.swift
SecondCameraEditorString.swift
SecondCameraEditorStringSanitizer.swift
SecondCameraEditorStubs.swift
SecondCameraEditorSwiftUtils.swift
SecondCameraEditorUIGeometry.swift
SecondCameraEditorUIKitImage.swift
SecondCameraEditorUIStubs.swift
SecondCameraEditorUnfairLock.swift
SecondCameraImageEditorCanvasView.swift
SecondCameraImageEditorStrokeItem.swift
SecondCameraImageEditorTransform.swift
SecondCameraImageEditorViewController+Blur.swift
SmallTask.swift
VisionOCREngine.swift
```

逐项记录建议使用：

| 文件 | SparkClient 修复意图 | SupportClient 是否适用 | SupportClient 适配方式 | Debug | Release | 功能回归 |
| --- | --- | --- | --- | --- | --- | --- |
| 示例 | 纯模型解除 MainActor | 是 | 添加普通 `nonisolated` | 待验证 | 待验证 | 待验证 |

## 14. 关联文档

SupportClient 既有相关工单：

- `SUPPORT-ARCH-000001-SparkClient底层核心架构迁移需求工单.md`
- `SUPPORT-OSS-OCR-000001-OSS文件上传与OCR底座迁移对齐SparkClient需求工单.md`

SparkClient 已形成的 Swift 6 问题经验：

- `Swift6-OSS后台回调触发MainActor断言崩溃修复方案.md`
- `Swift6-Release归档EarlyPerfInliner编译器崩溃修复工单.md`

本工单优先级高于上述旧迁移工单中与 Swift 6 并发语义冲突的历史建议；业务范围仍以 SupportClient 已实现代码为准。
