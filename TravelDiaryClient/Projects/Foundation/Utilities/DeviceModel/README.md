# 统一设备信息

业务代码使用 `AppleDeviceInfo`（主线程）：`modelIdentifier`、`modelName`、`model`、`isDuo`、`isSimulator`、`systemVersion`、`deviceName`。
`SupportSystemInfo` 保留原有入口并转发到这里。屏幕尺寸、窗口布局、实时方向继续使用 UIKit，避免把硬件型号与当前窗口状态混淆。

## 来源

沿用参考项目 `SparkClient/Projects/Foundation/Utilities/DeviceModel/AppleDeviceModel.generated.swift` 的 DeviceKit 方案。
2026-10-23 通过 Git 获取 https://github.com/devicekit/DeviceKit.git 的 HEAD：
`19528aa07e1426626ea9fb2c4a161edf43c4f9e8`（v5.9.0）。
`AppleDeviceModel.generated.swift` 来自上游 `Source/Device.generated.swift`；许可证见 `LICENSE.DeviceKit`。

上游暂未收录 Duo。`AppleDeviceInfo` 单独补充 `iPhone19,4` → `iPhone Duo`（本机 Duo 模拟器已验证）；其 `model` 仍是上游的 unknown，显示名称和 Duo 判断使用统一入口。未知型号保留原标识，不猜测设备名称。

更新时从上游 Git 获取最新提交，替换生成文件及许可证，更新此处提交号，然后执行设备信息测试和应用编译。不要把本地补充映射写进生成文件。
