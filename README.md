# Personal Journal

一款本地优先的 iOS/Android 个人日志应用。支持多用户（例如“我的日志”“孩子”）、系统输入法语音转文字、图片与视频、按日归档、日历浏览、Markdown 分析包，以及可校验的完整备份与恢复。

应用本身只负责可靠记录和导出，不直接调用大模型。分析包可以在 Windows 上交给 ChatGPT、Claude 或其他本地/在线 AI 工具分析。

## 核心边界

- 数据默认只保存在应用私有目录，不依赖 iCloud 或后端服务。
- 语音输入使用 iOS/Android 系统输入法，不录音、不保存音频。
- 图片和视频导入后复制到应用私有目录，之后不依赖系统相册中的原文件。
- 同一设备可创建、切换、重命名和归档多个用户，数据按用户隔离。
- 分析导出为 Markdown + 媒体 ZIP；完整备份为 SQLite 快照 + 全部媒体 + manifest + SHA-256 checksums ZIP。
- 恢复采用合并策略：相同 UUID 跳过，不覆盖已有对象。

## 开发

需要 Flutter stable。常用命令：

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
```

移动端集成测试需要已连接设备或已启动模拟器：

```bash
flutter test integration_test -d <device-id>
```

本机 Windows 若未安装 Android SDK，只能运行 Dart/Widget 测试，不能生成 Android 安装包。iOS 构建必须在 macOS/Xcode 环境完成；仓库内 GitHub Actions 会测试并生成无签名 IPA。

## 架构

- `lib/core/database`：SQLite schema 与数据库启动。
- `lib/core/files`：私有文件、校验和与原子 ZIP。
- `lib/features/profiles`：多用户与当前用户状态。
- `lib/features/entries`：草稿、发布、媒体、编辑与时间线。
- `lib/features/calendar`：按月统计与按日历史。
- `lib/features/export`：Markdown 分析包。
- `lib/features/backup`：完整备份、校验、预览与合并恢复。
- `lib/features/settings`：存储统计、备份恢复和侧载提醒。

生产依赖在 `lib/main.dart` 组合，通过构造参数注入页面；没有全局可变 service locator。

## 数据与导出

SQLite 数据库和 `media/images`、`media/videos`、`media/thumbnails` 位于系统提供的应用支持目录。临时导出、恢复 staging 位于系统临时目录。具体绝对路径由 iOS/Android 决定，不应由用户手动修改。

分析 ZIP 包含每日 Markdown、人物信息、选择的图片/视频和版本化 manifest，适合复制到 Windows 后交给 AI。完整备份 ZIP 用于灾难恢复，不应手工编辑；恢复前会校验路径、schema、文件清单和 SHA-256。

> **重要：卸载 iPhone 应用会删除应用私有目录中的本地日志与媒体。没有完整备份时无法恢复。刷新免费侧载时不要先卸载旧应用。**

Windows 免费侧载步骤见 [docs/side-loading-windows.md](docs/side-loading-windows.md)，发布前人工验收见 [docs/release-checklist.md](docs/release-checklist.md)。
