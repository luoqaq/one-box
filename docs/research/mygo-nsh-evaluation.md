# MyGo / NSH / NSGo 技术评估

评估日期：2026-11-17  
范围：能否支撑 OneBox V1 的“剪贴板历史 + 区域截图/标注”。

## 结论

**可以用 MyGo 做试验性方案，但不是开箱即用；NSH / NSGo 不建议作为 V1 主线。**

如果目标是尽快交付稳定工具，仍推荐 SwiftUI + AppKit 原生方案。  
如果目标是验证 MyGo，并以少量 Swift 桥接为代价换取 Go UI / 工具链，可以走“MyGo 外壳 + Swift 原生模块”。

## 对比

| 方案 | 剪贴板历史 | 截图 | 菜单栏 / 快捷键 | V1 判断 |
|---|---|---|---|---|
| SwiftUI + AppKit | 直接访问 `NSPasteboard`、图片表示和 `changeCount` | 直接访问 ScreenCaptureKit | 原生实现 | 推荐 |
| MyGo | 官方 Clipboard API 支持文本、图片、多表示；但未见系统剪贴板变更事件，后台历史仍需桥接或轮询 | 未见官方屏幕捕获 API；需 Swift/Rust/Zig native module 调 ScreenCaptureKit | 官方支持 tray、global shortcut、panel、display 信息 | 可做技术验证 |
| NSH | 公开 Clipboard 能力偏应用内读写/用户粘贴；未见后台剪贴板历史监听 | 未见官方屏幕捕获 API | 能做原生 macOS 窗口和菜单，但菜单栏工具箱不是其核心场景 | 不推荐 V1 |
| NSGo | NSH 思路的 Go 移植；不会比 NSH 多出系统截图能力 | 同 NSH，需要原生桥接 | 较新，生态和资料更少 | 不推荐 V1 |

## MyGo：可行的边界

**已证实的能力**

- Go 写桌面 App，支持 Native UI 或系统 WebView 前端。
- 支持窗口、tray、menus、global shortcuts、displays、dialogs、notifications 等桌面 API。
- Clipboard API 支持 `ReadText`、`WriteText`、`ReadImage`、`WriteImage`、`AvailableFormats`。
- 数据交换模型支持文本、HTML、PNG、文件列表、自定义格式和懒加载 provider。
- Native UI 具备绘制、图片、Canvas、Overlay、文本输入、列表等基础，足够做剪贴板历史和简单标注编辑器。
- Native modules 标记为 experimental，可用 Swift / Rust / Zig 补 macOS 框架能力。
- Launcher 文档提供了“后台 App + panel + global shortcut”的参考形态。

**缺口**

- 官方公开文档未看到系统剪贴板“changed / watch / subscribe”事件；历史监听仍要处理 `changeCount` 或原生通知桥接。
- 官方公开文档未看到屏幕捕获 / 屏幕录制 / ScreenCaptureKit 封装；`CapturePage`、automation screenshot 是窗口或自动化用途，不等于桌面区域截图。
- 标注编辑器和箭头/文字/打码需要自己在 MyGo UI 中实现，不是现成组件。
- MyGo native module 仍是实验能力；截图和剪贴板桥接要先做最小验证。
- 当前机器未检测到 Go；走 MyGo 需要先安装 Go 工具链。

## NSH / NSGo：为什么不推荐 V1

NSH 的优势是 Rust / TSX 一套组件跨 iOS、Android、macOS、Windows、Linux 和 Web；macOS 后端确实使用 AppKit / Core Animation / CoreText。

但 OneBox V1 不是普通跨平台表单 App，而是高度依赖 macOS 系统服务：

- 后台剪贴板监听与隐私行为。
- 剪贴板图片多表示保存。
- ScreenCaptureKit 截图权限。
- 多屏选区遮罩和像素级输出。
- 全局快捷键唤起截图。

NSH 公开 API 已覆盖 Clipboard 基本读写和用户 paste 事件，但未见后台剪贴板监听；未见屏幕捕获模块。Native Components / AppKit host 可以补能力，但那已经接近“用 AppKit 写核心，再嵌一层 UI 框架”，V1 复杂度不划算。

NSGo 是 NSH 设计在 Go 上的移植，官方说明其目标是用 Go 工具链复用 NSH 架构；它不会自动补齐 ScreenCaptureKit 和后台剪贴板能力，且比 MyGo 更早期。

## 如果坚持用 MyGo

推荐只做一个小型技术验证，不直接承诺完整 V1：

1. 最小 tray app：菜单栏图标、历史面板、全局快捷键。
2. 剪贴板：MyGo Clipboard 读取文本/PNG，列表展示和写回复用。
3. Swift native module：暴露 `NSPasteboard.changeCount` 轮询和 ScreenCaptureKit 矩形截图。
4. 标注：在 MyGo Canvas 上实现矩形、箭头、文字、打码和 PNG 导出。
5. 验证权限：屏幕录制授权、剪贴板隐私提示、自写抑制、多屏 Retina 输出。

验证通过后再决定 MyGo 是否替代 SwiftUI 主线；不通过就回到原生方案。

## 官方来源

- MyGo 总览：https://mygo.egoist.dev/docs
- MyGo Clipboard：https://mygo.egoist.dev/docs/data-transfer
- MyGo Desktop APIs：https://mygo.egoist.dev/docs/native
- MyGo Launcher：https://mygo.egoist.dev/docs/launchers
- MyGo Windows / native access：https://mygo.egoist.dev/docs/windows
- MyGo Image：https://mygo.egoist.dev/docs/ui/image
- MyGo Overlays：https://mygo.egoist.dev/docs/ui/overlays
- NSH macOS：https://nsh.dev/docs/macos
- NSH Clipboard capability：https://nsh.dev/docs/sandbox-and-capabilities
- NSH paste event：https://nsh.dev/docs/forms-and-keyboard
- NSH Native Components：https://nsh.dev/docs/native-components
- NSGo 与 NSH 关系：https://github.com/oneo-me/nsgo/blob/main/docs/architecture/nsh.md
