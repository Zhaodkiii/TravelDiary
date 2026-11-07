# 未使用候选资源归档

此目录保存经引用扫描未发现使用的资源，不参与 App 编译，禁止加入应用 Target。

完整分类、扫描边界、恢复方法及资源清单见 `docs/engineering/asset-management.md` 和 `docs/engineering/asset-inventory.json`。

恢复资源时，将完整资源集移动到运行时 Assets.xcassets 的对应功能分组，保持资源名称不变。
