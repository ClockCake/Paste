<p align="center">
  <img src="Paste/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" height="128" alt="Paste App Icon">
</p>

<h1 align="center">Paste</h1>

<p align="center">
  一款轻量、优雅的跨平台剪贴板管理器（macOS + iOS）
</p>

## 功能特性

- 自动捕获剪贴板内容（文本、URL、图片）
- 智能内容识别（颜色代码、电话号码、邮箱地址）
- 支持 iCloud 同步
- 显示来源应用图标
- 智能相对时间显示（刚刚、x 分钟前、x 小时前、昨天、x 天前、具体日期）
- 中英文双语支持
- 浅色 / 深色 / 跟随系统外观模式
- 全局快捷键呼出
- 双击卡片自动粘贴
- 收藏、搜索、按类型和时间筛选
- 复制时音效反馈
- 点击即可复制回剪贴板

## iOS 支持（前台自动采集）

iOS 端支持前台自动采集（App 处于激活状态时自动读取系统剪贴板），不支持系统级后台常驻采集与快捷键能力。

| 功能 | macOS | iOS |
|------|-------|-----|
| 自动捕获剪贴板 | ✅（全局） | ✅（前台） |
| 历史查询 / 搜索 / 筛选 | ✅ | ✅ |
| 卡片详情阅读 | ✅ | ✅ |
| 图片全屏缩放预览 | ✅（系统窗口） | ✅（全屏 + Pinch Zoom） |
| 全局快捷键唤起 | ✅ | ❌ |
| 双击自动粘贴到其他应用 | ✅ | ❌ |
| iCloud 同步 | ✅ | ✅ |

## 截图

![截图](https://image.itimes.me/file/1770822524031_image.png)

## 系统要求

- macOS 13.0+
- iOS 17.0+
- Xcode 15.0+

## 构建

```bash
git clone https://github.com/你的用户名/Paste.git
cd Paste
open Paste.xcodeproj
```

在 Xcode 中选择目标设备后按 `Cmd + R` 运行。

## 许可证

本项目不采用开源许可证，保留所有权利。详见 [LICENSE](LICENSE) 文件。
