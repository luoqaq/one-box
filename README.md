# OneBox

macOS 菜单栏工具箱。本机运行，数据不上云。

## 功能

- **工具箱**：分类、搜索、固定工具；菜单栏或 ⌃⌥Space 打开
- **剪贴板历史**：文本/图片，搜索、置顶、清理；⌃⌥V
- **截图与标注**：区域截图，箭头/文字/矩形/打码，复制或保存；⌃⌥⇧4
- **屏幕取色器**：吸取色值（HEX / RGB / OKLCH）；⌃⌥C（默认关闭，可在工具箱启用）

要求：macOS 15.2+。技术栈：SwiftPM + SwiftUI/AppKit + ScreenCaptureKit。

## 构建与运行

```bash
./Scripts/package-app.sh
open Scripts/build/OneBox.app
```

常用脚本：

```bash
./Scripts/reload-app.sh   # 打包并替换当前正在运行的 OneBox
./Scripts/run-tests.sh    # 非 UI 模块测试
```

图标已在 `Resources/`。首次签名会由 `Scripts/ensure-codesign-identity.sh` 在本机创建「OneBox Local」身份（仅本地开发用）。

## 贡献

欢迎 Issue 与 PR。请保持改动聚焦；涉及 UI / 原生行为时，用 `./Scripts/reload-app.sh` 在真机验证后再提交。

## 许可

[MIT](LICENSE)
