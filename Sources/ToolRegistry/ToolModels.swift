import Foundation

/// 工具分类（架构文档：效率、图像、开发、系统，可扩展）。
public enum ToolCategory: String, Codable, CaseIterable, Sendable, Hashable {
    case efficiency = "效率"
    case image = "图像"
    case developer = "开发"
    case system = "系统"
}

/// 工具打开后落到哪个工作台。
public enum ToolDestination: String, Codable, Sendable, Hashable {
    case clipboard
    case screenshots
    case capture
    case colorPicker
    case settings
}

/// 工具行 / 设置页里的快捷动作（如「立即截图」）。
public struct ToolQuickAction: Codable, Hashable, Sendable {
    public let label: String
    public let destination: ToolDestination

    public init(label: String, destination: ToolDestination) {
        self.label = label
        self.destination = destination
    }
}

/// 内置工具静态描述。运行时状态（启用/置顶/排序/使用次数）见 ToolRuntimeState。
public struct ToolDescriptor: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let desc: String
    public let category: ToolCategory
    /// 搜索关键词，空格分隔，包含拼音简拼与全拼。
    public let keywords: String
    /// 展示用默认快捷键，如 "⌃⌥V"；nil 显示为 "—"。
    public let defaultShortcut: String?
    /// 关联的全局热键 id（AppSettings/HKHotKeyCenter 使用），nil 表示无热键。
    public let hotkeyID: String?
    public let destination: ToolDestination?
    public let quickAction: ToolQuickAction?
    /// V1 已实现（可启用）还是规划中（只展示）。
    public let isInstalled: Bool
    /// UI 图标 id，由 OneBoxUI/ToolLauncherUI 解析成矢量图标。
    public let iconID: String
    /// squircle 前景/背景色（十六进制），与原型一致。
    public let fgHex: String
    public let bgHex: String
    /// 设置页插件管理器展示的运行时状态文案。
    public let runtimeLabel: String
    public let memoryLabel: String

    public init(
        id: String,
        name: String,
        desc: String,
        category: ToolCategory,
        keywords: String,
        defaultShortcut: String?,
        hotkeyID: String? = nil,
        destination: ToolDestination? = nil,
        quickAction: ToolQuickAction? = nil,
        isInstalled: Bool = true,
        iconID: String,
        fgHex: String,
        bgHex: String,
        runtimeLabel: String,
        memoryLabel: String
    ) {
        self.id = id
        self.name = name
        self.desc = desc
        self.category = category
        self.keywords = keywords
        self.defaultShortcut = defaultShortcut
        self.hotkeyID = hotkeyID
        self.destination = destination
        self.quickAction = quickAction
        self.isInstalled = isInstalled
        self.iconID = iconID
        self.fgHex = fgHex
        self.bgHex = bgHex
        self.runtimeLabel = runtimeLabel
        self.memoryLabel = memoryLabel
    }
}

/// 工具运行时状态，持久化在 UserDefaults。
public struct ToolRuntimeState: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var pinned: Bool
    public var order: Int
    public var uses: Int

    public init(enabled: Bool = false, pinned: Bool = false, order: Int = 0, uses: Int = 0) {
        self.enabled = enabled
        self.pinned = pinned
        self.order = order
        self.uses = uses
    }
}

/// 工具箱过滤器（原型 pill-tabs）。
public enum LauncherFilter: String, CaseIterable, Sendable {
    case all
    case pinned
    case enabled
    case disabled

    public var title: String {
        switch self {
        case .all: return "全部"
        case .pinned: return "已置顶"
        case .enabled: return "已启用"
        case .disabled: return "未启用"
        }
    }
}

/// 工具箱排序模式（原型 sort-pill）。
public enum LauncherSortMode: String, CaseIterable, Sendable {
    case pinned
    case frequent

    public var title: String { self == .pinned ? "置顶优先" : "使用频率" }
}

/// 工具可用性：已启用 / 已内置未启用 / 规划中。
public enum ToolAvailability: Equatable, Sendable {
    case enabled
    case disabled
    case planned
}
