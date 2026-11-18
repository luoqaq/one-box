# 开发交接

更新：2026-11-18。只保存可版本化的工程上下文。

## 当前产品

macOS 菜单栏工具箱，已实现三个内置工具：

| 工具 | 默认热键 | 说明 |
| --- | --- | --- |
| 工具箱 Launcher | ⌃⌥Space | 分类、搜索、固定、启用/停用 |
| 剪贴板历史 | ⌃⌥V | 文本/图片监听、搜索、置顶、清理 |
| 截图与标注 | ⌃⌥⇧4 | 区域截图、箭头/文字/矩形/打码、最近记录 |
| 屏幕取色器 | ⌃⌥C | 吸取屏幕色，复制 HEX / RGB / OKLCH（默认未启用） |

偏好设置可改热键；注册失败提示占用。截图默认动作可选：进入标注 / 直接复制 / 保存文件。

## 模块地图

```text
AppTarget          入口、菜单栏、热键同步、WindowRouter、ToolEngine
HotKeys            热键规格、匹配、录制、修饰键左右侧
ToolRegistry       工具描述与运行时启用/置顶状态
ToolLauncherUI     工具箱 UI + DesignSystem
OneBoxUI           工作台、设置、标注工作室、权限引导
ClipboardHistory   pasteboard 采集与回环抑制
ClipboardStore     SQLite 元数据 + 图片/缩略图文件
ScreenCapture      选区遮罩、跨屏几何、ScreenCaptureKit、窗口排除
Annotation         标注模型与 PNG 渲染
CaptureStore       最近截图记录
ColorPicker        取色遮罩、采样、格式化
```

## 已知工程约束

- 无 Xcode.app 时用 CLT + 15.2 SDK 构建；测试与构建 SDK 不能混用（见 `AGENTS.md`）
- 打包签名：`Scripts/ensure-codesign-identity.sh` + 本机「OneBox Local」身份
- Bundle id：`com.onebox.app`；开发收尾默认 `./Scripts/reload-app.sh`
- 早期调研文档（Tauri/Electron/MyGo）结论仍有效：V1 走原生；细节以源码为准，部分蓝图字段已落后于实现

## 文档与原型

- 方案蓝图：`docs/v1-plan.md`、`docs/architecture.md`（已补取色器，接口示意可能仍偏早期草稿）
- 平台调研：`docs/research/`（归档证据，日常开发不必重读）
- UI 原型：`prototypes/v1-module-details/`（交互参考；真机以 SwiftUI 为准）
- Logo 探索稿已剔除，正式资源在 `Resources/`

## 未做 / 明确不做（当前）

- 跨设备同步、滚动长截图、OCR、贴图、录屏、Windows
- 第三方插件系统、云端工具市场
- 默认自动向目标应用发送粘贴键（辅助功能相关能力按需另议）
