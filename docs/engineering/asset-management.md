# 图片与颜色资源管理

## 目录约定

运行时 Asset Catalog 统一位于 `TravelDiaryClient/Projects/App/Resources/Assets.xcassets`。

```text
Assets.xcassets/
├── Brand/AppIcons/                   # 主应用图标
├── DesignSystem/Colors/              # 全局强调色
├── Features/
│   ├── DiaryEditor/
│   │   ├── BookAppearance/           # 书皮、装订环
│   │   ├── Export/                   # 导出背景
│   │   └── TextPapers/               # 文本纸张
│   ├── DiaryCanvasAI/
│   │   ├── LayoutPreviews/           # AI 排版预览
│   │   └── StylePreviews/            # AI 风格预览
│   └── SecondCamera/
│       ├── Capture/                  # 拍摄操作图标
│       ├── Colors/                   # 相机专用颜色
│       └── Editor/                   # 照片编辑、字体预览
└── Shared/IntegrationIcons/          # 有同名引用、暂保留的集成图标
```

普通分组不启用 `provides-namespace`，移动目录不改变运行时资源名称及生成的 Swift 资源符号。已有资源名称保持兼容；新增资源按所属功能放置，使用可辨识的功能前缀，避免全局重名。应用图标和强调色名称由 Xcode Build Settings 指定。

字体、原生手账包等有独立加载协议的 bundle 不合并到 Asset Catalog；本次仅整理图片、颜色和应用图标。

## 未使用候选资源

归档位于仓库根目录 `ResourceArchive/UnusedAssets/Assets.xcassets`，不在应用的文件系统同步根目录 `TravelDiaryClient` 中，因此不参与 App 资源编译。不要将该目录加入应用 Target。

本次扫描应用、测试的 Swift / JSON / plist / storyboard / xib，以及 Xcode 工程配置，检查字符串引用和生成的 Swift 资源符号。额外保留动态名称族：`TextPaper-`、`TravelLayout-`、`TravelStyle-`、`font-`。

未发现静态引用的资源属于“未使用候选”，不是对远程数据或未来代码的绝对保证；归档保留完整原始文件，可随时恢复。存在同名文本但无法证明是图片调用的资源暂保留，例如集成图标中的通用名称，避免仅凭文本匹配误移。每项引用及新旧路径记录于 `asset-inventory.json`。

## 维护流程

1. 新资源进入对应功能分组；检查尺寸、透明通道、压缩格式及授权。
2. 删除或归档前同时检查字符串、Swift 资源符号、动态拼接及构建配置。
3. 候选先移动到 `ResourceArchive/UnusedAssets`，更新清单，确认对应页面功能。
4. 恢复时移动完整 `.imageset` / `.colorset` 到所属分组，不改资源名称。
5. 使用 Xcode Asset Catalog 编译检查资源文件有效性；改动图片内容时另做界面视觉验收。

## 本次归档清单

| 资源 | 原分类 | 大小 KiB |
|---|---|---:|
| `ai302` | AI | 172.2 |
| `aihubmix` | AI | 158.1 |
| `amap` | AI | 1065.0 |
| `applemap` | AI | 95.0 |
| `applogo` | AI | 660.8 |
| `arxiv` | AI | 6.5 |
| `assistant` | AI | 23.8 |
| `baidumap` | AI | 17.8 |
| `bing` | AI | 146.6 |
| `bochaai` | AI | 433.8 |
| `brave` | AI | 1504.7 |
| `cherry` | AI | 109.3 |
| `claude` | AI | 161.1 |
| `deepseek` | AI | 10.0 |
| `defaultIcon` | AI | 30.2 |
| `doubao` | AI | 127.6 |
| `exa` | AI | 360.0 |
| `gitee` | AI | 118.5 |
| `gitee_dark` | AI | 118.2 |
| `github` | AI | 92.5 |
| `github_dark` | AI | 91.5 |
| `google_search` | AI | 110.4 |
| `googlemap` | AI | 18.5 |
| `hanlin` | AI | 244.7 |
| `huggingface` | AI | 179.3 |
| `hunyuan` | AI | 22.5 |
| `iflow` | AI | 12.9 |
| `kimi` | AI | 65.9 |
| `kimi_dark` | AI | 64.0 |
| `knowledge_bag` | AI | 890.9 |
| `langsearch` | AI | 19.4 |
| `lm_studio` | AI | 55.8 |
| `lm_studio_dark` | AI | 55.6 |
| `longcat` | AI | 103.1 |
| `longcat_dark` | AI | 104.4 |
| `mimo` | AI | 109.9 |
| `mimo_dark` | AI | 106.8 |
| `minimax` | AI | 119.4 |
| `modelscope` | AI | 37.7 |
| `n1n` | AI | 24.6 |
| `openai` | AI | 135.9 |
| `openai_dark` | AI | 133.4 |
| `openrouter` | AI | 64.8 |
| `openrouter_dark` | AI | 62.9 |
| `openweather` | AI | 17.6 |
| `perplexity` | AI | 128.2 |
| `poe` | AI | 132.2 |
| `poe_dark` | AI | 121.6 |
| `qweather` | AI | 14.6 |
| `qweather_dark` | AI | 14.9 |
| `qwen` | AI | 3.2 |
| `siliconflow` | AI | 32.0 |
| `siri` | AI | 1769.5 |
| `spark` | AI | 135.7 |
| `tavily` | AI | 135.5 |
| `tiangong` | AI | 175.1 |
| `translate_circle` | AI | 4.2 |
| `webreader` | AI | 997.4 |
| `wenxin` | AI | 187.9 |
| `xai` | AI | 94.4 |
| `xai_dark` | AI | 94.2 |
| `yi` | AI | 63.4 |
| `yi_dark` | AI | 63.3 |
| `zhipuai` | AI | 73.4 |
| `zhipuai_dark` | AI | 51.8 |
| `AppIcon1` | Assets.xcassets | 2250.8 |
| `album-tilt-28` | SecondCamera | 6.0 |
| `check-circle-fill` | SecondCamera | 1.7 |
| `chevron-left-bold-28` | SecondCamera | 1.4 |
| `chevron-right-colored-42` | SecondCamera | 2.5 |
| `flash-auto` | SecondCamera | 2.4 |
| `flash-off` | SecondCamera | 2.2 |
| `flash-on` | SecondCamera | 1.3 |
| `lock-28` | SecondCamera | 4.2 |
| `media-editor-video-trim-gray` | SecondCamera | 2.0 |
| `media-editor-video-trim-yellow` | SecondCamera | 2.0 |
| `multicapture-off` | SecondCamera | 6.1 |
| `multicapture-on` | SecondCamera | 3.8 |
| `play-fill-32` | SecondCamera | 1.2 |
| `switch-camera-28` | SecondCamera | 2.3 |
| `x-circle-fill` | SecondCamera | 1.9 |
