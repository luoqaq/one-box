# OneBox 原生方案设计

更新日期：2026-11-18  
状态：V1 开发蓝图（与源码冲突时以源码 / `PROJECT_MEMORY.md` 为准）  
前置文档：[V1 产品与技术方案](v1-plan.md)

## 设计结论

第一版用 **Swift Package + SwiftUI/AppKit + ScreenCaptureKit** 实现 macOS 菜单栏 App。

当前机器没有 Xcode.app，但有 Swift 6.4 和 Apple 命令行工具，因此项目不依赖 `.xcodeproj`：SwiftPM 负责编译，脚本负责生成和签名 `.app`。后续如果需要 SwiftUI 可视化调试，再引入 Xcode 项目也不迟。

## 产品形态

### 工具箱汇总入口

OneBox 按“工具容器”设计。菜单栏图标点击后默认打开 **工具箱 Launcher**，而不是直接进入某一个工具。

工具箱负责：

- 展示全部工具，并显示已启用、规划中和已固定状态。
- 按分类浏览：效率、图像、开发、系统；分类可扩展。
- 支持工具名、动作和关键词搜索。
- 展示最近使用、使用次数和默认快捷键。
- 支持固定工具、修改快捷键、进入工具详情。
- 后续新增工具时，只注册工具描述和入口，不改工具箱框架。

V1 内置工具：

- 剪贴板历史
- 截图与标注（含最近截图记录）
- 屏幕取色器（默认未启用，可在工具箱打开）

工具箱中的“规划中”条目只用于表达扩展方向；当前三个工具均为已安装。

### 直达入口

全局快捷键默认值先定为：

- `⌃⌥Space`：打开工具箱。
- `⌃⌥V`：直达剪贴板历史。
- `⌃⌥⇧4`：开始区域截图。
- `⌃⌥C`：屏幕取色。

默认键只作为初值，偏好设置里允许用户修改；注册失败时明确提示“快捷键已被占用”。

### 剪贴板历史

从工具箱进入后打开历史 Popover：

- 顶部：搜索框和类型筛选。
- 中部：历史列表与当前条目预览。
- 底部：区域截图、最近截图、偏好设置、清空历史。
- 条目操作：单击复制回剪贴板；右键提供复制、置顶、删除。

### 偏好设置

窗口包含六组设置：

1. 工具
   - 菜单栏默认打开工具箱或剪贴板历史。
   - 是否显示规划中的工具。
   - 分类显隐。
2. 常规
   - 登录后启动。
   - 剪贴板记录开关。
   - 保留数量：默认 500 条。
   - 保留天数：默认 30 天。
3. 快捷键
   - 打开工具箱。
   - 直达剪贴板历史。
   - 区域截图。
   - 屏幕取色。
4. 截图
   - 截图后默认动作（标注 / 复制 / 保存）。
   - 默认保存位置。
   - 是否保留最近截图记录。
5. 权限
   - 屏幕录制权限状态与开启入口。
6. 存储
   - 数据位置、占用统计和清理入口。

## 模块设计

目标是把系统复杂度收进少数深模块，UI 只依赖稳定的小接口。

```text
OneBox
├─ AppTarget                 可执行入口、依赖组装、菜单栏外壳、热键同步
├─ HotKeys                   热键规格、匹配、录制
├─ ToolRegistry              工具描述、分类、启用状态、固定状态
├─ ToolLauncherUI            工具箱、搜索、分类、最近使用和工具详情
├─ OneBoxUI                  SwiftUI 工作台、偏好设置、标注编辑器
├─ ClipboardHistory          剪贴板采集、去重、复用、自写抑制、清理
├─ ClipboardStore            SQLite 元数据 + 图片/缩略图文件管理
├─ ScreenCapture             屏幕授权、多屏选区、ScreenCaptureKit 捕获
├─ Annotation                标注数据模型与纯渲染器
├─ CaptureStore              截图记录、PNG 文件、缩略图、清理
└─ ColorPicker               屏幕取色、采样与色值格式化
```

### 1. ToolRegistry

工具箱和偏好设置只依赖工具描述，不依赖具体工具实现。

```swift
struct ToolDescriptor: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let category: ToolCategory
    let keywords: [String]
    let shortcut: KeyboardShortcut?
    let destination: ToolDestination?
    let permissions: [ToolPermission]
    let isBuiltIn: Bool
    let isAvailable: Bool
}

ToolRegistry {
    var tools: [ToolDescriptor]
    var categories: [ToolCategory]
    func search(_ query: String) -> [ToolDescriptor]
    func setPinned(id: String, pinned: Bool) throws
    func setShortcut(id: String, shortcut: KeyboardShortcut) throws
}
```

实现要点：

- V1 使用内置静态注册；后续如果要支持外部工具，再扩展加载机制，不提前做插件系统。
- 工具使用次数、固定状态和快捷键覆盖保存在本地偏好中。
- 工具箱只读取 `ToolRegistry`，不知道剪贴板或截图的内部实现。
- 规划中工具的 `destination = nil`，只展示详情，不可打开。

### 2. ClipboardHistory

对外只暴露历史行为，隐藏 pasteboard、轮询、哈希和回环细节。

```swift
ClipboardHistory {
    func start()
    func stop()
    var changes: AsyncStream<ClipboardChange>

    func reuseItem(id: ClipboardItem.ID) async throws
    func setPinned(id: ClipboardItem.ID, pinned: Bool) async throws
    func deleteItem(id: ClipboardItem.ID) async throws
    func clear() async throws
}
```

实现要点：

- 默认每 0.5 秒比较 `NSPasteboard.general.changeCount`。
- 文本读取纯文本；图片优先读 PNG，其次 TIFF，再退化到 `NSImage` 转 PNG。
- 内容哈希用 SHA-256；文本按原字符串，图片按规范化 PNG 字节。
- 复用历史时同时写入一个 `com.onebox.internal-write` 私有 pasteboard 类型，监听器看到该标记就跳过，避免把自己的写回再次入历史。
- 重复内容只更新 `lastUsedAt` 和 `useCount`，不生成新条目。
- 暂停记录时停止轮询，不读取剪贴板。

### 3. ClipboardStore

只负责“怎么存”，不关心内容来自哪个 App。

```swift
ClipboardStore {
    func insert(_ item: ClipboardItem, imageData: Data?) async throws
    func updateUsed(id: UUID) async throws
    func setPinned(id: UUID, pinned: Bool) async throws
    func delete(id: UUID) async throws
    func clear() async throws
    func records(limit:search:pinnedOnly:) async throws -> [ClipboardRecord]
    func enforceRetention(limit:days:) async throws
}
```

数据模型：

```swift
ClipboardRecord {
    id: UUID
    kind: .text / .image
    textContent: String?       // 文本内容，用于展示和搜索
    contentHash: String
    imageFile: String?         // images/<uuid>.png
    thumbnailFile: String?     // thumbnails/<uuid>.png
    imageWidth: Int?
    imageHeight: Int?
    byteCount: Int
    createdAt: Date
    lastUsedAt: Date
    useCount: Int
    pinned: Bool
}
```

存储位置：

```text
~/Library/Application Support/OneBox/
├─ store.sqlite
├─ images/<uuid>.png
└─ thumbnails/<uuid>.png
```

图片先写临时文件再原子替换，避免崩溃留下半文件。清空历史必须同时删除数据库记录和对应图片。

### 4. ScreenCapture

对外暴露一次完整的“框选并返回截图”能力。

```swift
ScreenCaptureService {
    func authorizationStatus() -> CaptureAuthorization
    func requestSelectionCapture() async throws -> CapturedImage
    func capture(rect: CGRect) async throws -> CapturedImage
}
```

实现要点：

- 通过 ScreenCaptureKit 检查屏幕录制权限；未授权时抛带恢复路径的错误。
- 在所有显示器上创建非激活、无边框、最高层级的遮罩窗口。
- 选区坐标统一使用屏幕 point；输出前再按目标显示比例换算 pixel。
- V1 主路径使用 `SCScreenshotManager.captureImage(in:)`；跨屏结果作为重点验收项。
- `CapturedImage` 同时保留 `CGImage`、PNG 数据和尺寸，后续标注和复制不需要重复编码。

### 5. Annotation

标注模型与渲染分离，渲染器保持纯函数，方便测试。

```swift
Annotation {
    id: UUID
    kind: .arrow / .rectangle / .text / .mosaic
    rect: CGRect
    color: AnnotationColor
    strokeWidth: CGFloat
    text: String?
}
```

```swift
AnnotationRenderer {
    func render(image: CGImage, annotations: [Annotation]) throws -> CGImage
}
```

实现要点：

- 箭头：起止点、线宽和头部尺寸自动计算。
- 矩形：边框色、线宽、可选半透明填充。
- 文字：系统字体、字号、颜色，按选区自适应换行。
- 打码：对底图区域按像素块采样重绘，不依赖外部库。
- 输出保持原图像素尺寸，导出 PNG。

### 6. CaptureStore

截图记录单独存储，避免和剪贴板历史混在一起。

```text
~/Library/Application Support/OneBox/
└─ captures/<uuid>.png
```

记录字段：`id`、`file`、`thumbnailFile`、`width`、`height`、`byteCount`、`createdAt`。  
默认保留最近 100 张或 30 天；偏好设置里可关闭“保留最近截图”。

## 核心交互流程

### 打开工具

1. 用户点击菜单栏图标或按 `⌃⌥Space`。
2. `ToolLauncherUI` 展示 `ToolRegistry` 中的工具集合。
3. 用户搜索、按分类筛选，或直接选择固定/最近使用工具。
4. Launcher 根据工具描述打开对应页面或触发动作。
5. 工具自身只负责业务界面，不承担汇总导航。

### 复制内容入历史

1. 用户在其他 App 执行复制。
2. `ClipboardHistory` 发现 `changeCount` 改变。
3. 判断是否有 OneBox 私有写入标记；有则忽略。
4. 读取文本或图片，规范化并计算哈希。
5. 已存在则更新使用时间；不存在则写数据库和图片文件。
6. UI 通过 `changes` 刷新列表。

### 复用历史

1. 用户点击历史条目。
2. 写回 `NSPasteboard`，同时附带私有写入标记。
3. 更新 `lastUsedAt`、`useCount`。
4. 用户到目标 App 手动 `Cmd+V`。

### 区域截图

1. 用户按快捷键或菜单项。
2. `ScreenCaptureService` 检查权限。
3. 所有屏幕显示遮罩，用户拖框或按 Esc 取消。
4. 捕获选区得到原始 PNG。
5. 打开标注编辑器。
6. 用户选择复制或保存。
7. 若开启最近截图记录，则写入 `CaptureStore`。

## 错误与边界

- 屏幕录制未授权：显示权限说明和“打开系统设置”按钮。
- 快捷键注册失败：提示当前组合键被占用，并引导到偏好设置修改。
- 剪贴板读取失败：跳过本次，不影响 App。
- 图片转换失败：记录错误，不把空图片写入历史。
- 保存文件失败：显示目标目录权限/磁盘空间提示。
- 清空历史：弹确认框；删除数据库记录和资源文件。
- 关闭“剪贴板记录”后，不再轮询 `changeCount`。

## 构建与打包

仓库建议结构：

```text
one-box/
├─ Package.swift
├─ Sources/
│  ├─ AppTarget/
│  ├─ ToolRegistry/
│  ├─ ToolLauncherUI/
│  ├─ OneBoxUI/
│  ├─ ClipboardHistory/
│  ├─ ClipboardStore/
│  ├─ ScreenCapture/
│  ├─ Annotation/
│  └─ CaptureStore/
├─ Tests/
├─ Scripts/
│  └─ package-app.sh
└─ docs/
```

`.app` 由脚本生成：

- 复制 SwiftPM release 可执行文件。
- 写入 `Info.plist`。
- 设置 `LSUIElement = true`，只显示菜单栏，不进 Dock。
- 加入应用图标和版本信息。
- 开发阶段做 ad-hoc 签名，方便本机直接运行。

V1 不使用 App Sandbox。屏幕录制、全局热键和本地文件访问在沙盒下都会增加额外限制；个人本地工具先保持非沙盒。

## 测试策略

优先测深模块，不追 UI 自动化覆盖率。

1. `ToolRegistry`
   - 名称、副标题、分类和关键词搜索命中。
   - 固定、快捷键覆盖和启用状态持久化。
   - 新增工具描述后无需修改工具箱 UI。
2. `AnnotationRenderer`
   - 空标注输出等于原图。
   - 箭头、矩形、文字、打码渲染结果尺寸不变。
   - 多条标注按顺序叠加。
3. 内容规范化与去重
   - 相同文本只更新使用时间。
   - PNG/TIFF 转 PNG 后相同像素不重复入库。
4. 自写抑制
   - `reuseItem` 后监听器不会生成新条目。
5. 存储清理
   - 超数量/超天数清理置顶外条目。
   - 删除记录时同步删除图片。
6. 截图坐标
   - point 与 pixel 换算、跨屏 rect、空选区取消。
7. 手工验收
   - 浏览器、聊天工具、预览、访达复制文本/图片。
   - 单屏和双屏截图、标注后粘贴到微信/备忘录。

## 实施切片

1. **骨架**：SwiftPM、菜单栏入口、`.app` 打包脚本、快捷键注册。
2. **工具箱**：工具注册表、分类、搜索、固定、最近使用和工具详情。
3. **剪贴板核心**：文本采集、SwiftData 存储、自写抑制、基础测试。
4. **历史 UI**：搜索、列表、复制、置顶、删除、清空。
5. **图片历史**：PNG/TIFF 规范化、缩略图、图片预览。
6. **截图核心**：权限、多屏遮罩、选区捕获。
7. **标注编辑器**：四种标注、复制、保存。
8. **收尾**：偏好设置、最近截图、保留策略、错误提示、验收打包。

## 待实机确认

- macOS 27.2.1 上后台读取剪贴板是否触发隐私提示，以及拒绝后的返回值。
- ScreenCaptureKit 权限首次申请、撤回、恢复后的行为。
- `SCScreenshotManager.captureImage(in:)` 在 Retina 双屏/混合缩放下的输出。
- 快捷键 `⌃⌥Space`、`⌃⌥V`、`⌃⌥⇧4` 在用户常用环境中的占用情况。
- SwiftPM 生成 `.app` 在目标机器直接运行的签名和权限表现。
