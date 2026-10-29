# 手帐字体资源清单

本目录由手帐文字编辑器通过 `DiaryFontCatalog` 按需加载。作品只保存 catalog 中的稳定字体 ID 与版本号；原字体文件和授权文本随 App 一起打包。

## 字体来源与版本

| 字体 | 版本 | 上游来源 | 文件 |
|---|---:|---|---|
| 霞鹜文楷（现有） | 1.522 | https://github.com/lxgw/LxgwWenKai | `fonts/LXGWWenKai-Regular.ttf` |
| 马善政毛笔楷书 | 2.003 | https://fonts.google.com/specimen/Ma+Shan+Zheng | `fonts/MaShanZheng-Regular.ttf` |
| 龙藏体 | 2.001 | https://github.com/googlefonts/longcang | `fonts/LongCang-Regular.ttf` |
| 钟齐流江毛草 | 1.003 | https://github.com/googlefonts/liujianmaocao | `fonts/LiuJianMaoCao-Regular.ttf` |
| 霞鹜臻楷 GB | 0.800.2 | https://github.com/lxgw/LxgwZhenKai/releases/tag/v0.800.2 | `fonts/LXGWZhenKaiGB-Regular.ttf` |
| 霞鹜文楷轻便版 | 1.522 | https://github.com/lxgw/LxgwWenKai-Lite | `fonts/LXGWWenKaiLite-Regular.ttf` |
| 霞鹜文楷 GB 轻便版 | 1.522 | https://github.com/lxgw/LxgwWenkaiGB-Lite | `fonts/LXGWWenKaiGBLite-Regular.ttf` |
| 悠哉字体 | 0.868 | https://github.com/lxgw/yozai-font | `fonts/Yozai-Regular.ttf` |
| 小赖字体（比例版） | 3.126 | https://github.com/lxgw/kose-font | `fonts/Xiaolai-Regular.ttf` |
| 霞鹜漫黑 | 1.004 | https://github.com/lxgw/LxgwMarkerGothic/releases/tag/v1.004 | `fonts/LXGWMarkerGothic-Regular.ttf` |

除霞鹜臻楷使用上游 `v0.800.2` GB 字形版外，其余新增字体取自上游当日发布版本或 Google Fonts 主分支。霞鹜臻楷 GB 的上游后续版本可能更新字形；升级时须同步检查实际效果、更新版本号和 SHA-256。

## 授权

这些字体根据各自上游的 SIL Open Font License 1.1 发布。对应授权文本分别保存在 `licenses/`，霞鹜文楷现有授权文本保存在 `licenses/OFL.txt`。随 App 再分发字体时保留对应授权文本；不得单独出售字体文件。每款字体的保留名称条款各不相同，若未来修改或生成衍生字体，需先阅读对应授权文件。

## 完整性与更新

`catalog.json` 中的 `sha256` 是每个 TTF 文件的 SHA-256。字体目录采用延迟校验和注册：用户打开字体选择器时先读取轻量目录，仅在字体预览或使用时验证对应文件，避免一次性加载所有大型中文字库。替换字体文件时必须同时更新 catalog 中的版本和 SHA-256。

马善政毛笔楷书于 2026-10-28 更新为用户从 Google Fonts 下载的完整 TTF（内置版本仍为 2.003），同时收录下载包中的原始 `OFL.txt` 至 `licenses/mashanzheng-OFL.txt`。保留现有字体 ID 和版本引用，兼容已有作品。
