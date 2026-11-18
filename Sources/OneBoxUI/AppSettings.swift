import SwiftUI
import Combine
import ToolRegistry
import HotKeys

// Re-export hotkey model for UI call sites.
public typealias HotKeySpec = HotKeys.HotKeySpec
public typealias ModifierKey = HotKeys.ModifierKey
public typealias ModifierKind = HotKeys.ModifierKind
public typealias ModifierSide = HotKeys.ModifierSide

// MARK: - 截图默认动作

public enum CaptureDefaultAction: String, Codable, CaseIterable, Sendable {
    case annotate
    case copy
    case save

    public var title: String {
        switch self {
        case .annotate: return "进入标注"
        case .copy: return "直接复制"
        case .save: return "保存文件"
        }
    }
}

// MARK: - 全局设置

/// 偏好设置（UserDefaults 持久化），六组设置里跨工具的部分。
/// 工具专属配置（如剪贴板保留条数）也在各自工作台的「工具配置」子视图里编辑。
@MainActor
public final class AppSettings: ObservableObject {
    private let defaults: UserDefaults
    private let prefix = "onebox.settings"

    @Published public var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: prefix + ".launchAtLogin") } }
    @Published public var defaultOpenLauncher: Bool { didSet { defaults.set(defaultOpenLauncher, forKey: prefix + ".defaultOpenLauncher") } }
    @Published public var showInactiveTools: Bool { didSet { defaults.set(showInactiveTools, forKey: prefix + ".showInactiveTools") } }

    @Published public var hotkeyLauncher: HotKeySpec { didSet { defaults.set(encode(hotkeyLauncher), forKey: prefix + ".hotkey.launcher") } }
    @Published public var hotkeyClipboard: HotKeySpec { didSet { defaults.set(encode(hotkeyClipboard), forKey: prefix + ".hotkey.clipboard") } }
    @Published public var hotkeyCapture: HotKeySpec { didSet { defaults.set(encode(hotkeyCapture), forKey: prefix + ".hotkey.capture") } }
    @Published public var hotkeyColorPicker: HotKeySpec { didSet { defaults.set(encode(hotkeyColorPicker), forKey: prefix + ".hotkey.colorPicker") } }

    @Published public var clipboardMaxRecords: Int { didSet { defaults.set(clipboardMaxRecords, forKey: prefix + ".clipboard.maxRecords") } }
    @Published public var clipboardRetentionDays: Int { didSet { defaults.set(clipboardRetentionDays, forKey: prefix + ".clipboard.retentionDays") } }

    @Published public var captureDefaultAction: CaptureDefaultAction { didSet { defaults.set(captureDefaultAction.rawValue, forKey: prefix + ".capture.defaultAction") } }
    @Published public var captureKeepRecords: Bool { didSet { defaults.set(captureKeepRecords, forKey: prefix + ".capture.keepRecords") } }
    @Published public var captureMaxRecords: Int { didSet { defaults.set(captureMaxRecords, forKey: prefix + ".capture.maxRecords") } }
    @Published public var captureSaveDirectory: String { didSet { defaults.set(captureSaveDirectory, forKey: prefix + ".capture.saveDirectory") } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        launchAtLogin = defaults.bool(forKey: prefix + ".launchAtLogin")
        defaultOpenLauncher = defaults.object(forKey: prefix + ".defaultOpenLauncher") as? Bool ?? true
        showInactiveTools = defaults.object(forKey: prefix + ".showInactiveTools") as? Bool ?? true
        hotkeyLauncher = Self.decode(defaults.data(forKey: prefix + ".hotkey.launcher")) ?? .launcherDefault
        hotkeyClipboard = Self.decode(defaults.data(forKey: prefix + ".hotkey.clipboard")) ?? .clipboardDefault
        hotkeyCapture = Self.decode(defaults.data(forKey: prefix + ".hotkey.capture")) ?? .captureDefault
        hotkeyColorPicker = Self.decode(defaults.data(forKey: prefix + ".hotkey.colorPicker")) ?? .colorPickerDefault
        clipboardMaxRecords = defaults.object(forKey: prefix + ".clipboard.maxRecords") as? Int ?? 500
        clipboardRetentionDays = defaults.object(forKey: prefix + ".clipboard.retentionDays") as? Int ?? 30
        captureDefaultAction = CaptureDefaultAction(rawValue: defaults.string(forKey: prefix + ".capture.defaultAction") ?? "") ?? .annotate
        captureKeepRecords = defaults.object(forKey: prefix + ".capture.keepRecords") as? Bool ?? true
        captureMaxRecords = defaults.object(forKey: prefix + ".capture.maxRecords") as? Int ?? 100
        captureSaveDirectory = defaults.string(forKey: prefix + ".capture.saveDirectory")
            ?? NSHomeDirectory() + "/Pictures/OneBox"
    }

    public func hotkey(for id: String) -> HotKeySpec {
        switch id {
        case "clipboard": return hotkeyClipboard
        case "capture": return hotkeyCapture
        case "colorPicker": return hotkeyColorPicker
        default: return hotkeyLauncher
        }
    }

    public func setHotkey(_ spec: HotKeySpec, for id: String) {
        switch id {
        case "clipboard": hotkeyClipboard = spec
        case "capture": hotkeyCapture = spec
        case "colorPicker": hotkeyColorPicker = spec
        default: hotkeyLauncher = spec
        }
    }

    private func encode(_ spec: HotKeySpec) -> Data {
        (try? JSONEncoder().encode(spec)) ?? Data()
    }

    private static func decode(_ data: Data?) -> HotKeySpec? {
        data.flatMap { try? JSONDecoder().decode(HotKeySpec.self, from: $0) }
    }
}
