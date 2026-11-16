# 装订流程验收 · 2026-11-16

设备：iPhone 18 Pro / iOS 27.2 模拟器。

- App Debug 构建通过。
- `DiaryOnboardingTests` 10 项全部通过，包括真实六页素材加载、新增装订状态测试及原有首页交接测试。
- 测试目标原有其他文件存在 actor 隔离、过期认证接口等编译错误；本次用临时 `EXCLUDED_SOURCE_FILE_NAMES` 仅保留 `DiaryOnboardingTests.swift` 编译，再通过 `OTHER_LDFLAGS=$(inherited) -framework SystemConfiguration -framework CoreTelephony` 补齐测试目标所需链接库。未改动项目构建配置，不能据此认定全量测试通过。
- 模拟器调试流程确认：三组跨页均等待装订并完成；进入第四屏风格选择后返回第三跨页，仍显示成品。
- 状态测试确认：点击前不显示文案，重复装订调用被忽略，装订期间不能开始翻页，新页先进入背景状态，返回已装订页不会重播。减少动态效果路径亦保持点击装订步骤。

## 真实截图

- [素材悬浮、等待装订](floating.png)
- [第三跨页装订完成并显示文字](complete.png)

## 调试验收日志

```text
ONBOARDING_CHECK floating page=0 phase=floating
ONBOARDING_CHECK bound page=0 phase=complete
ONBOARDING_CHECK floating page=1 phase=floating
ONBOARDING_CHECK bound page=1 phase=complete
ONBOARDING_CHECK floating page=2 phase=floating
ONBOARDING_CHECK bound page=2 phase=complete
ONBOARDING_CHECK styles page=3
ONBOARDING_CHECK return page=2 phase=complete
```
