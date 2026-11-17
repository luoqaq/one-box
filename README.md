# OneBox

OneBox 是一个 macOS 菜单栏工具箱。V1 聚焦两个高频工具：

- 剪贴板历史：记录文本和图片，支持搜索、复用、置顶和清理。
- 区域截图：选区截图，支持基础标注，输出到剪贴板或文件。

## 产品决策

- 平台：先做 macOS，本机运行，不做 Windows 兼容层。
- 形态：菜单栏 App；默认打开工具箱汇总入口，支持分类、搜索、固定工具，也支持全局快捷键直达。
- 数据：只存本机，默认不上云、不同步。
- 截图：第一版做到区域截图、箭头/文字/矩形/打码、复制或保存。

## 调研与方案

- [平台能力证据](docs/research/desktop-platform-evidence.md)
- [V1 产品与技术方案](docs/v1-plan.md)
- [原生架构设计](docs/architecture.md)
- [V1 模块交互原型](prototypes/v1-module-details/index.html)

调研结论：Tauri / Electron 官方能力不足以直接覆盖剪贴板变更监听和截图闭环，V1 推荐用 SwiftUI + AppKit + ScreenCaptureKit 做原生 macOS App。

## 开发

技术栈：SwiftPM + SwiftUI/AppKit + ScreenCaptureKit，macOS 15.2+，无需 Xcode 工程。

```bash
# 构建（必须用 CLT 工具链 + MacOSX15.2 SDK：避免未同意 license 的 Xcode；默认 27 SDK 的 SwiftUI @State 宏在纯 CLT 下缺插件）
DEVELOPER_DIR=/Library/Developer/CommandLineTools SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk swift build

# 打包成 .app（自动用 15.2 SDK 构建 + ad-hoc 签名）
./Scripts/package-app.sh
open Scripts/build/OneBox.app

# 测试（非 UI 模块，65 个用例；默认 SDK + Swift Testing，因 15.2 SDK 的 stdlib 缺 SendableMetatype）
./Scripts/run-tests.sh
```


