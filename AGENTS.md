# OneBox · 开发规则

本文件约束在本仓库开发与维护 OneBox，不作为 App 运行时提示词。

## 每次开发读取

1. `PROJECT_MEMORY.md`：当前能力、模块边界、已知约束
2. 按任务再读 `docs/README.md` 里的对应文档与相关源码
3. 先看 `git status --short`；保留用户及其他 Agent 的未提交改动

## 产品边界

- 平台：仅 macOS 15.2+ 本机菜单栏 App；不做 Windows / 云同步 / 第三方插件市场
- 形态：菜单栏 + Dock；默认打开工具箱 Launcher，也支持全局快捷键直达
- 数据：只存本机 Application Support；剪贴板与截图可能含敏感内容，提供清空与清理
- 技术栈：SwiftPM + SwiftUI/AppKit + ScreenCaptureKit；无 `.xcodeproj`，用脚本打包签名

## 常用入口

| 任务 | 入口 |
| --- | --- |
| 工程交接 | `PROJECT_MEMORY.md` |
| 文档导航 | `docs/README.md` |
| 打包并替换当前 App | `./Scripts/reload-app.sh`（skill：`.cursor/skills/reload-onebox`；Agent Shell 须 `required_permissions: ["all"]`） |
| 仅打包 | `./Scripts/package-app.sh` |
| 非 UI 模块测试 | `./Scripts/run-tests.sh` |
| 图标资源 | `./Scripts/gen-icon.sh` |

## 构建约束（本机 CLT）

- **构建 App**：必须 `DEVELOPER_DIR=/Library/Developer/CommandLineTools` + `MacOSX15.2.sdk`（默认 27 SDK 的 SwiftUI `@State` 宏在纯 CLT 下缺插件）
- **跑测试**：用默认 SDK（15.2 SDK 的 stdlib 缺 `SendableMetatype`）；`run-tests.sh` 在 `/tmp` 独立包中只测非 SwiftUI 模块
- 打包脚本已封装上述约束；不要让用户手动拼环境变量，除非在排查脚本本身

## 代码约定

- 新工具走 `ToolRegistry` 静态描述 + `WindowRouter` / `ToolEngine` 入口，不改 Launcher 框架
- 系统能力（剪贴板、截图、取色、热键）收进对应深模块；UI 只依赖稳定小接口
- UI / 原生改完需要真机看效果时，主动跑 `reload-app.sh`，不要只写「请退出后重新打开」
- 不要提交 `prototypes/logo-exploration/`、`.build/`、`Scripts/build/`、本机签名私钥

## Git

- `AGENTS.md`、`PROJECT_MEMORY.md`、`README.md`、`docs/` 属于可版本化开发上下文
- 按功能提交；提交前确认无密钥、本机路径隐私、未忽略的构建产物
