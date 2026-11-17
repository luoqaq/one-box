import SwiftUI
import Combine
import ToolRegistry

// MARK: - 热键

/// 全局快捷键描述（Carbon 注册用 key code + 修饰键）。
public struct HotKeySpec: Codable, Equatable, Sendable {
    public enum Modifier: String, Codable, CaseIterable, Sendable {
        case control, option, shift, command
    }

    public var keyCode: Int
    public var modifiers: Set<Modifier>

    public init(keyCode: Int, modifiers: Set<Modifier>) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// 默认：⌃⌥Space（打开工具箱）
    public static let launcherDefault = HotKeySpec(keyCode: 49, modifiers: [.control, .option])
    /// 默认：⌃⌥V（剪贴板历史）
    public static let clipboardDefault = HotKeySpec(keyCode: 9, modifiers: [.control, .option])
    /// 默认：⌃⌥⇧4（区域截图）
    public static let captureDefault = HotKeySpec(keyCode: 21, modifiers: [.control, .option, .shift])

    /// 展示文案，如 "⌃⌥V"。
    public var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    /// 常用按键名（Carbon virtual key codes）。
    public static func keyName(_ keyCode: Int) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36, 76: return "↩"
        case 53: return "⎋"
        case 48: return "⇥"
        case 51: return "⌫"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:
            let mapped = UnicodeScalar(97 + (keyCode - 0))
            if keyCode >= 0 && keyCode <= 25, let scalar = mapped, scalar.isASCII {
                return String(Character(scalar)).uppercased()
            }
            return "键\(keyCode)"
        }
    }
}

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
        default: return hotkeyLauncher
        }
    }

    public func setHotkey(_ spec: HotKeySpec, for id: String) {
        switch id {
        case "clipboard": hotkeyClipboard = spec
        case "capture": hotkeyCapture = spec
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
