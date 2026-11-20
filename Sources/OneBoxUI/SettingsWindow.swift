import SwiftUI
import ToolLauncherUI
import ToolRegistry

// MARK: - 全局设置（与百宝袋同窗 600×540 覆盖；无红绿灯，失焦关闭）

public struct SettingsWindowView: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void

    public enum Panel: String, CaseIterable, Identifiable {
        case general
        case plugins
        case hotkeys
        case storage

        public var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "通用与外观"
            case .plugins: return "工具管理"
            case .hotkeys: return "快捷键"
            case .storage: return "权限与数据"
            }
        }

        var icon: OBIcon.ID {
            switch self {
            case .general: return .sun
            case .plugins: return .grid
            case .hotkeys: return .keyboard
            case .storage: return .storage
            }
        }
    }

    @State private var panel: Panel
    @State private var showResetConfirm = false

    public init(model: AppModel, initialPanel: Panel = .general, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        _panel = State(initialValue: initialPanel)
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            main
        }
        .frame(width: 600, height: 540)
        .background(GlassPanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(toastOverlay)
        .tint(OB.accent)
        .overlay {
            if showResetConfirm {
                ConfirmModal(
                    title: "清空全部本地数据？",
                    message: "将删除剪贴板历史与最近截图的全部本地记录和文件，恢复首次安装状态，且无法撤销。",
                    confirmTitle: "清空全部",
                    onConfirm: {
                        showResetConfirm = false
                        model.clearAllLocalData()
                    },
                    onCancel: { showResetConfirm = false }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: 侧栏（顶对齐导航 + 左下版本号）

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            WindowDragRegion()
            VStack(alignment: .leading, spacing: 2) {
                backToLauncherButton
                    .padding(.bottom, 8)

                ForEach(Panel.allCases) { p in
                    SidebarItemView(panel: p, isSelected: panel == p) {
                        panel = p
                    }
                }

                Spacer(minLength: 0)
                    .allowsHitTesting(false)

                Text("v0.1.0")
                    .font(.system(size: 11).monospaced())
                    .foregroundColor(OB.ink3)
                    .padding(.horizontal, 9)
                    .padding(.top, 6)
                    .allowsHitTesting(false)
            }
            .padding(10)
        }
        .frame(width: 168, alignment: .topLeading)
        .background(OB.sidebarBg)
        .overlay(alignment: .trailing) { Divider().overlay(OB.hairline) }
    }

    private var backToLauncherButton: some View {
        Button(action: onClose) {
            HStack(spacing: 6) {
                OBIcon(.chevronLeft, size: 13, weight: 1.65)
                Text("返回百宝袋")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .foregroundColor(OB.ink2)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("返回工具箱")
    }

    // MARK: 主区

    private var main: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                WindowDragRegion()
                Text(panel.title)
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 18)
                    .allowsHitTesting(false)
            }
            .frame(height: 48)
            .overlay(alignment: .bottom) { Divider().overlay(OB.hairline) }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch panel {
                    case .plugins: pluginPanel
                    case .general: generalPanel
                    case .hotkeys: hotkeyPanel
                    case .storage: storagePanel
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 14, leading: 18, bottom: 18, trailing: 18))
            }
        }
        .background(OB.contentBg)
    }

    // 工具管理
    private var pluginPanel: some View {
        VStack(alignment: .leading, spacing: 12) {

            SettingsCard {
                ForEach(model.registry.builtinTools.filter(\.isInstalled)) { tool in
                    PluginSettingsRow(
                        tool: tool,
                        isEnabled: model.registry.isEnabled(tool.id),
                        hotkeyLabel: {
                            if let id = tool.hotkeyID {
                                return model.settings.hotkey(for: id).display
                            }
                            return tool.defaultShortcut
                        }(),
                        onToggle: { model.registry.toggleEnabled(tool.id) }
                    )
                }
            }

            SettingsCard {
                SettingsRow(title: "在百宝袋中显示未启用工具", desc: "关闭后百宝袋仅展示已启用的工具") {
                    OBToggle(isOn: model.settings.showInactiveTools) {
                        model.settings.showInactiveTools.toggle()
                        OBLauncherPreferences.showInactiveTools = model.settings.showInactiveTools
                    }
                }
            }
        }
    }

    private struct SidebarItemView: View {
        let panel: Panel
        let isSelected: Bool
        let action: () -> Void
        @State private var isHovering = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 9) {
                    OBIcon(panel.icon, size: 15, weight: 1.55)
                    Text(panel.title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                }
                .foregroundColor(isSelected ? OB.accentInk : (isHovering ? OB.ink : OB.ink2))
                .padding(.horizontal, 9)
                .frame(height: 32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? OB.accentSoft : (isHovering ? OB.surfaceHover : Color.clear))
                )
                .overlay(alignment: .leading) {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(OB.brandYellow)
                            .frame(width: 3, height: 16)
                            .padding(.leading, 2)
                    }
                }
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .animation(.easeInOut(duration: 0.12), value: isHovering)
        }
    }

    /// 工具管理行：名称旁显示状态徽标（● 监听中 / ● 已就绪 / 未启用），下方简明功能说明。
    private struct PluginSettingsRow: View {
        let tool: ToolDescriptor
        let isEnabled: Bool
        let hotkeyLabel: String?
        let onToggle: () -> Void

        private var statusText: String {
            guard isEnabled else { return "未启用" }
            return tool.id == "clipboard" ? "● 监听中" : "● 已就绪"
        }

        var body: some View {
            let fgColor = Color(flexibleHex: tool.fgHex)
            let bgColor = Color(flexibleHex: tool.bgHex)

            HStack(alignment: .center, spacing: 13) {
                OBIcon(tool.iconID, size: 15, weight: 1.6)
                    .foregroundColor(fgColor)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(bgColor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(fgColor.opacity(0.18), lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(tool.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Text(statusText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isEnabled ? OB.green : OB.ink3)
                            .lineLimit(1)
                    }
                    Text(tool.desc)
                        .font(.system(size: 11.5))
                        .foregroundColor(OB.ink3)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    if let hotkeyLabel, hotkeyLabel != "—", !hotkeyLabel.isEmpty {
                        Kbd(text: hotkeyLabel)
                    }
                    OBToggle(isOn: isEnabled, action: onToggle)
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 48, alignment: .center)
            .overlay(alignment: .bottom) { Divider().overlay(OB.hairline) }
        }
    }

    // 通用与外观
    private var generalPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard {
                SettingsRow(title: "外观主题", desc: "切换浅色、深色或跟随系统外观") {
                    OBSegmentedControl(
                        options: AppThemeMode.allCases,
                        title: { $0.title },
                        selection: Binding(
                            get: { model.settings.themeMode },
                            set: { model.settings.themeMode = $0 }
                        )
                    )
                }
            }
            SettingsCard {
                SettingsRow(title: "开机自动启动", desc: "登录 macOS 后自动在菜单栏后台待命") {
                    OBToggle(isOn: model.settings.launchAtLogin) {
                        model.settings.launchAtLogin.toggle()
                        LaunchAtLoginController.setEnabled(model.settings.launchAtLogin)
                    }
                }
                SettingsRow(title: "在程序坞 (Dock) 中显示", desc: "关闭后仅保留顶部菜单栏图标与快捷键唤起") {
                    OBToggle(isOn: model.settings.showInDock) {
                        model.settings.showInDock.toggle()
                    }
                }
                SettingsRow(title: "点击菜单栏图标打开", desc: "左键单击菜单栏图标时的默认窗口") {
                    OBSegmentedControl(options: [true, false], title: { $0 ? "百宝袋" : "剪贴板历史" },
                                        selection: Binding(get: { model.settings.defaultOpenLauncher },
                                                           set: { model.settings.defaultOpenLauncher = $0 }))
                }
            }
        }
    }

    // 全局快捷键
    private var hotkeyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard {
                SettingsRow(title: "辅助功能权限", desc: "全局快捷键依赖此项（含双击、左右键）") {
                    HStack(spacing: 8) {
                        PermBadge(AccessibilityPermission.isTrusted ? .ok("已允许") : .warn("未授权"))
                        if !AccessibilityPermission.isTrusted {
                            OBButton(title: "系统设置", style: .secondary) {
                                _ = AccessibilityPermission.promptIfNeeded()
                                AccessibilityPermission.openSystemSettings()
                            }
                        }
                    }
                }
                SettingsRow(title: "打开百宝袋", desc: "呼出工具聚合搜索入口") {
                    hotkeyButton(for: "launcher", spec: model.settings.hotkeyLauncher)
                }
                SettingsRow(title: "直达剪贴板历史", desc: "仅在启用剪贴板工具时注册监听") {
                    hotkeyButton(for: "clipboard", spec: model.settings.hotkeyClipboard)
                }
                SettingsRow(title: "开始区域截图", desc: "仅在启用截图工具时注册监听") {
                    hotkeyButton(for: "capture", spec: model.settings.hotkeyCapture)
                }
                SettingsRow(title: "屏幕取色", desc: "仅在启用取色工具时注册") {
                    hotkeyButton(for: "colorPicker", spec: model.settings.hotkeyColorPicker)
                }
            }
        }
    }

    private func hotkeyButton(for id: String, spec: HotKeySpec) -> some View {
        HotkeyButton(spec: spec, onRecord: { newSpec in
            model.settings.setHotkey(newSpec, for: id)
            model.showToast("快捷键已更新")
            if !AccessibilityPermission.isTrusted {
                _ = AccessibilityPermission.promptIfNeeded()
                model.showToast("请在系统设置中允许辅助功能后快捷键才会生效")
            }
        }, onInvalid: { message in
            model.showToast(message)
        })
    }

    // 权限与数据
    private var storagePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard {
                SettingsRow(title: "屏幕录制权限", desc: "用于区域截图、标注与屏幕取色") {
                    HStack(spacing: 8) {
                        PermBadge(model.captureService.authorizationStatus() ? .ok("已允许") : .warn("未授权"))
                        if !model.captureService.authorizationStatus() {
                            OBButton(title: "去授权", style: .secondary) {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
                SettingsRow(title: "辅助功能权限", desc: "用于监听全局快捷键（含双击修饰键）") {
                    HStack(spacing: 8) {
                        PermBadge(AccessibilityPermission.isTrusted ? .ok("已允许") : .warn("未授权"))
                        if !AccessibilityPermission.isTrusted {
                            OBButton(title: "去授权", style: .secondary) {
                                _ = AccessibilityPermission.promptIfNeeded()
                                AccessibilityPermission.openSystemSettings()
                            }
                        }
                    }
                }
            }
            SettingsCard {
                SettingsRow(title: "本地存储目录", desc: "数据仅保存在本机，不上传云端") {
                    OBButton(title: "在访达中打开", style: .secondary) {
                        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                            .appendingPathComponent("OneBox", isDirectory: true)
                        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(url)
                    }
                }
                StorageUsageRow(model: model)
                SettingsRow(title: "重置全部本地数据", desc: "恢复首次安装状态") {
                    OBButton(title: "清空全部", style: .danger) { showResetConfirm = true }
                }
            }
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = model.toast {
            ToastView(text: toast)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 20)
        }
    }
}

// MARK: - 存储占用行

private struct StorageUsageRow: View {
    @ObservedObject var model: AppModel
    @State private var totalBytes: Int64 = 0
    @State private var clipCount = 0
    @State private var capCount = 0

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("总占用空间")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text("剪贴板 \(clipCount) 条 · 截图 \(capCount) 条")
                    .font(.system(size: 11.5))
                    .foregroundColor(OB.ink3)
                    .lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(OB.surfaceActive)
                        Capsule().fill(OB.brandYellow)
                            .frame(width: max(4, geo.size.width * usageFraction))
                    }
                }
                .frame(maxWidth: 160, maxHeight: 5)
                .frame(height: 5)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(OBFormat.bytes(totalBytes))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .fixedSize()
                .layoutPriority(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 48, alignment: .center)
        .overlay(alignment: .bottom) { Divider().overlay(OB.hairline) }
        .task {
            totalBytes = await model.totalStorageBytes()
            clipCount = model.clipboardRecords.count
            capCount = model.captures.count
        }
        .onReceive(model.$clipboardRecords) { clipCount = $0.count }
        .onReceive(model.$captures) { capCount = $0.count }
    }

    private var usageFraction: CGFloat {
        // 1 GB 上限内的占比示意
        let gb: Double = 1024 * 1024 * 1024
        return min(1, Double(totalBytes) / gb)
    }
}

// MARK: - 登录启动（SMAppService）

enum LaunchAtLoginController {
    /// macOS 13+：SMAppService 注册；失败静默（未打包 .app 时无法注册）。
    static func setEnabled(_ enabled: Bool) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        if let cls = NSClassFromString("SMAppService") as? NSObject.Type,
           let mainApp = cls.perform(Selector(("mainApp")))?.takeUnretainedValue() as? NSObject {
            if enabled {
                _ = mainApp.perform(Selector(("registerAndReturnError:")), with: nil)
            } else {
                _ = mainApp.perform(Selector(("unregisterAndReturnError:")), with: nil)
            }
        }
    }
}
