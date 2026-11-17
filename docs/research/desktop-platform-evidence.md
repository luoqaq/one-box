# 桌面工具箱 V1：平台能力与证据

核验日期：2026-11-17。范围：macOS / Windows 的文本与图片剪贴板历史、多次复用、截图；不做框架选型定案。
来源仅采用 Apple、Microsoft、Tauri、Electron 的官方文档及所属仓库；不以博客、论坛用户反馈作结论。
“已证实”指文档或源码明确支持，**不代表已经实机测试**；“推断”是工程含义；“待验证”是证据或运行验证尚缺。
本次只做资料读取与本文写入，未读取用户剪贴板、调用截图、操作界面、更改设置或安装依赖。

## 关键结论

- **Tauri v2 官方 clipboard-manager 支持桌面图片读写**；“只支持文本”不成立。公开 JS API 与插件命令表均未提供剪贴板变更监听。[T1][T2]
- **两套框架都不能直接交付完整剪贴板历史工具**：历史持久化、去重、自写入回环抑制、目标应用粘贴及截图选区仍是应用工作。[T1][E1][E4]
- **macOS 15.4 有隐私 API，不等于所有 15/26 系统默认弹窗**：Apple 更新说明仍将提醒机制称为 upcoming feature；本次未找到 26 默认全面启用的明确发布声明。[A5][A6][A7]
- **截图、剪贴板读取、向其他应用发送按键是不同能力**；不能用某一项获权推导其他能力也获权。[A5][A10][A14][A15]
- **跨屏截图必须处理坐标单位与每屏缩放**；Windows 负坐标、混合 DPI 和旋转屏都是明确的平台边界。[W8][W9][W10]

## macOS：剪贴板与隐私

- **已证实｜changeCount**：计数从首次拥有该 pasteboard 时的 0 开始，每次所有权变更递增；不是内容哈希，也不是历史条目数。[A1]
- **推断｜变更检测**：定期比较 changeCount 可作为重新采集的信号；计数变化本身不携带内容。两次采样间连续复制可能只留下最终内容，不能承诺不漏项。[A1]
- **已证实｜多表示**：NSPasteboardItem.types 列出单项支持的 UTI；NSPasteboard.types 是所有项类型的并集。一个复制动作可能包含多个 item 和多种表示。[A2][A3]
- **已证实｜图片类型**：官方定义 `.png` 和 `.tiff`；剪贴板并不保证只出现 PNG。`.fileURL` 是另一种类型，不能把复制图片文件与复制图片像素混同。[A4]
- **推断｜图片保存**：只读取一种编码可能丢失兼容性；仅存转换后的 PNG 也不等于保留源应用的所有表示。原始表示保留范围应另定，不在本文承诺完全还原。[A2][A4]

### macOS 15 / 26 隐私：已知与未知

- **已证实｜API 版本**：NSPasteboard.AccessBehavior 标注 macOS **15.4+**；状态包含 default、ask、alwaysAllow、alwaysDeny。[A5]
- **已证实｜状态语义**：default 对 general pasteboard 的程序化访问定义为询问，其他 pasteboard 默认允许；首次提醒后转为 ask，用户可在系统设置调整该应用行为。[A5]
- **已证实｜用户粘贴例外**：ask / alwaysDeny 的文档均说明，同时符合“用户发起”和“粘贴相关”的访问仍被允许且不提醒；不能把后台轮询自动视为这种访问。[A5]
- **已证实｜开发者预览**：AppKit 的 April 2025 更新将程序化读取提醒称为 **upcoming feature**，提供 `EnablePasteboardPrivacyDeveloperPreview` 供应用提前测试；本次没有执行该设置。[A6]
- **已证实｜低侵入探测**：同一说明提供 detect 方法来判断数据种类，而不读取实际内容或引起提醒；这不能代替历史管理器保存正文和图片的读取。[A6]
- **待验证｜正式默认策略**：15.4 的 API availability 与 April 2025 的预览说明不是同一件事；检查 macOS 26 release notes 未找到明确默认启用声明，不能写成“26 必弹”或“26 永不弹”。[A5][A6][A7]
- **待验证｜监控表现**：需在指定 15.x / 26.x 正式构建测试后台读取、changeCount / 类型探测、拒绝后返回值、授权持久性，以及框架对新状态的暴露情况。
- **证据限制**：API 描述的是策略语义；它没有证明所有系统版本的启用时间，也不能据此断言应用能自行授予后台读取权限。[A5][A6]

## macOS：截图与自动粘贴

- **已证实｜版本**：ScreenCaptureKit 从 **12.3+** 可用；单帧截图类 SCScreenshotManager 从 **14.0+** 可用，可返回 CGImage 或 CMSampleBuffer。[A8][A9]
- **已证实｜矩形截图**：`SCScreenshotManager.captureImage(in:completionHandler:)` 从 **15.2+** 可用；矩形单位是屏幕空间的 **points**，官方明确支持多个显示器。[A11]
- **已证实｜权限实例**：Apple 的直接捕获示例首次运行请求 Screen Recording，授权后要求重启应用；该示例项目要求 15.0，不代表整个 ScreenCaptureKit 最低要求是 15.0。[A10]
- **已证实｜系统选择器**：SCContentSharingPicker 从 **14.0+** 可用，用系统 UI 提供捕获内容的过滤器；官方建议使用系统选择器。[A12]
- **待验证｜权限边界**：直接枚举并截图与系统选择器授权所选内容应分开测试；本次证据不足以保证两条路径提示完全一致、从此免提示或永不需要重启。[A10][A12]
- **推断｜范围选择**：14.x 可用内容过滤器与截图配置；15.2 新增矩形便利接口。框选交互、遮罩隐藏、Retina 混屏输出尺寸仍需应用设计与验证。[A9][A11]

- **已证实｜发送按键**：CGEvent.post 将 Quartz 事件送入事件流；Core Graphics 另有 `CGPreflightPostEventAccess` / `CGRequestPostEventAccess`，均为 **10.15+**。[A13][A14][A17]
- **已证实｜辅助功能路线**：若用 System Events 的界面脚本模拟 Cmd+V，Apple 明确要求逐应用启用 accessibility；AXIsProcessTrustedWithOptions 检查的是受信任辅助功能客户端身份。[A15][A16]
- **边界｜不能混称**：PostEvent 检查和 AX trust 检查是不同 API；所查 API 正文不足以证明它们在所有 15/26 构建中的对应关系。CGEvent 路线的具体授权入口与充分条件留待实机确认。[A14][A16]
- **待验证｜一键粘贴**：写回剪贴板、恢复目标应用焦点、发送 Cmd+V、确认目标接收是不同步骤；需验证撤权、权限变化后重启、目标应用差异及连续复用。

## Windows：剪贴板与图片

- **已证实｜更新通知**：给 HWND 调用 AddClipboardFormatListener，变更后收到 **WM_CLIPBOARDUPDATE**；最低 Windows Vista。消息只通知变化，内容仍需另行读取。[W1]
- **已证实｜读取竞争**：其他窗口打开剪贴板时 OpenClipboard 会失败，成功后应 CloseClipboard；收到更新不保证立即读取成功。[W2]
- **已证实｜标准格式**：文本可用 CF_UNICODETEXT；图片有 CF_BITMAP（HBITMAP）、CF_DIB（BITMAPINFO + 像素）、CF_DIBV5（BITMAPV5HEADER + 色彩信息 + 像素）。[W3]
- **已证实｜多格式与转换**：同一内容可发布多种格式；系统可在 CF_BITMAP / CF_DIB / CF_DIBV5 间合成转换。Microsoft 建议复制位图时放 CF_DIB 或 CF_DIBV5。[W4]
- **边界｜PNG**：标准 CF_* 列表没有 CF_PNG；Windows 支持注册自定义格式，不能把某应用发布的 PNG 格式假定为所有来源都有的标准表示。[W3][W4]
- **推断｜采集实现**：需要在占用失败时有限重试、及时复制数据、避免长期占锁；保存历史与再次写回属于应用层逻辑。[W1][W2][W4]
- **待验证｜图片往返**：以浏览器、聊天工具、图像编辑器分别测试透明通道、色彩、DIB 行方向、大图内存和多次复用；官方格式存在不代表每个目标应用表现一致。

## Windows：截图、DPI 与多屏

- **已证实｜WGC**：Windows.Graphics.Capture 提供显示器/窗口帧，可保存单张截图；GraphicsCapturePicker 从 **Windows 10 1803 / 17134** 可用，系统 UI 选择目标并显示捕获边框。[W5][W6]
- **已证实｜桌面互操作**：IGraphicsCaptureItemInterop 从 **Windows 10 1903 / 18362** 支持 CreateForWindow / CreateForMonitor，分别面向 HWND / HMONITOR；需与 picker 的交互路径区分。[W7]
- **已证实｜捕获限制**：WGC 应先检查 IsSupported；尺寸改变需处理帧池重建。关闭捕获边框有单独的用户授权和 capability 要求，不能默认无边框。[W5][W11]
- **已证实｜Desktop Duplication**：Windows 8 提供 DXGI 桌面帧；整桌面需为每个活动 output 建立 duplication，并自行组合，API 不提供跨输出显式同步。[W8][W12]
- **已证实｜异常边界**：Duplication 的输出表面需要自行处理旋转和可能分离的光标；安全桌面可能拒绝访问，断开的会话也有明确错误。[W8][W12]
- **已证实｜负坐标**：主屏包含原点，未必位于所有屏幕左上角；左侧或上方副屏可能有负坐标，不能把坐标截断成非负值。[W9]
- **已证实｜DPI**：Microsoft 推荐 Per-Monitor v2（Windows 10 1703+）；不正确的线程 DPI awareness 会让 API 坐标被虚拟化，不能直接当成捕获像素。[W10]
- **推断｜框选与拼接**：将选区按显示器相交拆分，再按各自坐标和比例裁剪、拼接；单个全局 scaleFactor 无法普遍处理混合 DPI。[W9][W10]
- **待验证｜屏幕矩阵**：100% / 150% / 200% 混屏、跨屏框选、竖屏、热插拔、HDR 到 SDR、远程桌面、受保护窗口和取消截图。

## Tauri v2：官方插件覆盖范围

- **已证实｜图片**：clipboard-manager 的 `readImage(): Promise<Image>`、`writeImage(...)` 从 2.0.0 提供；Android / iOS 不支持图片，本项目桌面目标不受此限制。[T1]
- **已证实｜表示层**：桌面源码经 arboard 将图片转为 RGBA + width / height，再构造 Tauri Image；这不是原始 PNG/TIFF 表示集合的透传。[T3]
- **已证实｜监听缺口**：所查公开 JS API、Rust 桌面实现和 invoke_handler 均未提供 clipboard changed / watch / subscribe；不能把第三方监听插件算成官方能力。[T1][T2][T3]
- **已证实｜快捷键**：global-shortcut 支持注册、注销、查询本应用注册；回调有 Pressed / Released，已有其他应用占用的快捷键不能保证触发。[T4]
- **已证实｜应用权限**：插件 capability 命令权限需显式开放；这属于 Tauri IPC 权限，不能替代 macOS 屏幕录制或按键控制授权。[T5][A10][A14]
- **推断｜V1 缺口**：这两个插件不提供桌面截图与向目标应用发送粘贴键；原生捕获、变更检测、焦点和事件注入需另接平台能力。此处不推导“整个生态没有实现”。[T1][T4]

## Electron：能力、版本差异与缺口

- **版本锚点**：本次 GitHub releases/latest 返回 **v45.3.3**（2026-11-14）；以下主要按该固定 tag 核验，避免滚动 latest 文档与选定运行时混淆。[E0]
- **已证实｜当前 clipboard**：v45.3.3 的主进程 API 是异步 `readText/writeText` 和 `read/write`；后者用 ClipboardItem 表达 text、HTML、PNG/JPEG 及原生自定义格式，单次 write 原子提交。[E1]
- **已证实｜旧版区别**：v40.0.0 文档仍有同步 `readImage/writeImage`、`availableFormats`、`readBuffer/writeBuffer`；不能把这些旧签名直接写进 v45 接口设计。[E2]
- **已证实｜nativeImage**：支持 PNG/JPEG、编码导出、裁剪、缩放及多比例表示；raw bitmap 格式依平台而异，不应直接当作 Tauri 的 RGBA 缓冲区。[E3][T3]
- **已证实｜desktopCapturer**：主进程 getSources 枚举 screen/window 并返回 NativeImage 缩略图，可配 getDisplayMedia 获取媒体流；macOS 10.15+ 捕获屏幕需用户同意。[E4]
- **已证实｜尺寸缺口**：thumbnailSize 默认 150×150，官方明确不保证实际缩略图尺寸等于请求值；不能把默认缩略图当作原分辨率截图。[E4][E5]
- **已证实｜屏幕坐标**：Display.bounds 是 DIP，scaleFactor 是输出比例；screen 有 Windows 的 DIP/物理坐标转换，display_id 可与 screen 的 Display.id 对应，但可能为空。[E5][E6][E7]
- **已证实｜监听缺口**：v45.3.3 clipboard 公开文档没有变更事件；需自行实现检测或原生通知桥接。clipboard 内容读写并不自动产生可查询历史。[E1]
- **已证实｜快捷键边界**：globalShortcut 在应用失焦时仍可工作；占用时注册失败。它检测按键，不提供向其他应用注入 Cmd+V 的能力。[E8]
- **推断｜V1 缺口**：Electron 降低图像转换、屏幕源枚举和捕获流接入工作量；选区遮罩、精确像素输出、历史管理和跨应用自动粘贴仍需实现与验收。[E1][E3][E4][E5]

## 后续验证优先级（本次未执行）

1. **先验证 macOS 权限**：指定 15.x / 26.x 构建，区分未开启预览与显式预览、用户粘贴与后台读取；记录原生 API 和框架路径的真实结果。
2. **再验证图片复用**：文本/PNG/TIFF/DIB、多表示、透明图往返；连续选择同一历史记录，观察自写回去重和目标应用接收。
3. **再验证截图边界**：两平台混合 DPI / Retina、负坐标、跨屏、旋转、热插拔；权限拒绝和撤回、取消动作、输出尺寸与内容一致。
4. **最后验证一键粘贴**：焦点恢复与事件授权独立验证；若自动发送按键不可用，保留“写回后由用户手动粘贴”的可验证路径。

## 官方来源（正文编号对应直接 URL）

正文中的来源编号可直接点击；Apple 动态文档另以官方 DocC JSON 核对了版本与更新说明。

[A1]: https://developer.apple.com/documentation/appkit/nspasteboard/changecount
[A2]: https://developer.apple.com/documentation/appkit/nspasteboarditem/types
[A3]: https://developer.apple.com/documentation/appkit/nspasteboard/types
[A4]: https://developer.apple.com/documentation/appkit/nspasteboard/pasteboardtype
[A5]: https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum
[A6]: https://developer.apple.com/documentation/updates/appkit
[A7]: https://developer.apple.com/documentation/macos-release-notes/macos-26-release-notes
[A8]: https://developer.apple.com/documentation/screencapturekit
[A9]: https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager
[A10]: https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos
[A11]: https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/captureimage(in:completionhandler:)
[A12]: https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker
[A13]: https://developer.apple.com/documentation/coregraphics/cgevent/post(tap:)
[A14]: https://developer.apple.com/documentation/coregraphics/cgrequestposteventaccess()
[A15]: https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/AutomatetheUserInterface.html
[A16]: https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions
[A17]: https://developer.apple.com/documentation/coregraphics/cgpreflightposteventaccess()
[W1]: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-addclipboardformatlistener
[W2]: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-openclipboard
[W3]: https://learn.microsoft.com/en-us/windows/win32/dataxchg/standard-clipboard-formats
[W4]: https://learn.microsoft.com/en-us/windows/win32/dataxchg/clipboard-formats
[W5]: https://learn.microsoft.com/en-us/windows/apps/develop/media-authoring-processing/screen-capture
[W6]: https://learn.microsoft.com/en-us/uwp/api/windows.graphics.capture.graphicscapturepicker
[W7]: https://learn.microsoft.com/en-us/windows/win32/api/windows.graphics.capture.interop/nn-windows-graphics-capture-interop-igraphicscaptureiteminterop
[W8]: https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/desktop-dup-api
[W9]: https://learn.microsoft.com/en-us/windows/win32/gdi/the-virtual-screen
[W10]: https://learn.microsoft.com/en-us/windows/win32/hidpi/high-dpi-desktop-application-development-on-windows
[W11]: https://learn.microsoft.com/en-us/uwp/api/windows.graphics.capture.graphicscapturesession.isborderrequired
[W12]: https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_2/nf-dxgi1_2-idxgioutput1-duplicateoutput
[T1]: https://v2.tauri.app/reference/javascript/clipboard-manager/
[T2]: https://github.com/tauri-apps/plugins-workspace/blob/v2/plugins/clipboard-manager/src/lib.rs
[T3]: https://github.com/tauri-apps/plugins-workspace/blob/v2/plugins/clipboard-manager/src/desktop.rs
[T4]: https://v2.tauri.app/reference/javascript/global-shortcut/
[T5]: https://v2.tauri.app/plugin/global-shortcut/
[E0]: https://github.com/electron/electron/releases/tag/v45.3.3
[E1]: https://github.com/electron/electron/blob/v45.3.3/docs/api/clipboard.md
[E2]: https://github.com/electron/electron/blob/v40.0.0/docs/api/clipboard.md
[E3]: https://github.com/electron/electron/blob/v45.3.3/docs/api/native-image.md
[E4]: https://github.com/electron/electron/blob/v45.3.3/docs/api/desktop-capturer.md
[E5]: https://github.com/electron/electron/blob/v45.3.3/docs/api/structures/desktop-capturer-source.md
[E6]: https://github.com/electron/electron/blob/v45.3.3/docs/api/screen.md
[E7]: https://github.com/electron/electron/blob/v45.3.3/docs/api/structures/display.md
[E8]: https://github.com/electron/electron/blob/v45.3.3/docs/api/global-shortcut.md
