# OneBox

macOS 菜单栏工具箱。本机运行，数据不上云。

## 功能

- **工具箱**：分类、搜索、固定工具；菜单栏或 ⌃⌥Space 打开
- **剪贴板历史**：文本/图片，搜索、置顶、清理；⌃⌥V
- **截图与标注**：区域截图，箭头/文字/矩形/打码，复制或保存；⌃⌥⇧4
- **屏幕取色器**：吸取色值（HEX / RGB / OKLCH）；⌃⌥C（默认关闭，可在工具箱启用）

平台：macOS 15.2+。技术栈：SwiftPM + SwiftUI/AppKit + ScreenCaptureKit。

## 开发

```bash
# 构建（CLT + MacOSX15.2 SDK；脚本已封装）
./Scripts/package-app.sh
open Scripts/build/OneBox.app

# 打包并替换当前正在运行的 OneBox（开发收尾默认）
./Scripts/reload-app.sh

# 非 UI 模块测试
./Scripts/run-tests.sh

# 图标：方案 A SVG → icns + 菜单栏模板
./Scripts/gen-icon.sh
```

Agent 收尾：改完 UI/原生后跑 `.cursor/skills/reload-onebox`（即 `reload-app.sh`），不要让用户手动退出再开。

## 文档与上下文

| 入口 | 说明 |
| --- | --- |
| [AGENTS.md](AGENTS.md) | 开发规则与构建约束 |
| [PROJECT_MEMORY.md](PROJECT_MEMORY.md) | 当前能力与模块交接 |
| [docs/README.md](docs/README.md) | 方案/调研文档索引 |
| [prototypes/v1-module-details/](prototypes/v1-module-details/) | 早期交互原型（参考用） |
