import SwiftUI
import ToolLauncherUI
import ToolRegistry

// MARK: - 全局设置窗口（原型 view-settings：204pt 侧栏 + 主区）

public struct SettingsWindowView: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void

    public enum Panel: String, CaseIterable, Identifiable {
        case plugins
        case general
        case hotkeys
        case storage

        public var id: String { rawValue }

        var title: String {
            switch self {
            case .plugins: return "工具插件"
            case .general: return "通用"
            case .hotkeys: return "全局快捷键"
            case .storage: return "权限与存储"
            }
        }

        var icon: OBIcon.ID {
            switch self {
            case .plugins: return .grid
            case .general: return .sun
            case .hotkeys: return .keyboard
            case .storage: return .storage
            }
        }
    }

    @State private var panel: Panel = .plugins
    @State private var showResetConfirm = false

    public init(model: AppModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            main
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(GlassPanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(toastOverlay)
        .preferredColorScheme(.light)
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

    // MARK: 侧栏

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                TrafficDots()
                Spacer()
                Text("v0.1.0")
                    .font(.system(size: 11).monospaced())
                    .foregroundColor(OB.ink3)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 16)

            ForEach(Panel.allCases) { p in
                Button {
                    panel = p
                } label: {
                    HStack(spacing: 9) {
                        OBIcon(p.icon, size: 15, weight: 1.9)
                        Text(p.title)
                            .font(.system(size: 13, weight: panel == p ? .semibold : .regular))
                    }
                    .foregroundColor(panel == p ? OB.accentInk : OB.ink2)
                    .padding(.horizontal, 9)
                    .frame(height: 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(panel == p ? OB.accentSoft : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 204, alignment: .top)
        .background(Color(red: 242/255, green: 244/255, blue: 247/255, opacity: 0.72))
        .overlay(alignment: .trailing) { Divider().overlay(OB.hairline) }
    }

    // MARK: 主区

    private var main: some View {
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
            .padding(EdgeInsets(top: 22, leading: 26, bottom: 26, trailing: 26))
        }
        .background(Color(red: 249/255, green: 250/255, blue: 252/255, opacity: 0.90))
    }

    private var heading: some View {
        Text(panel.title)
            .font(.system(size: 18, weight: .semibold))
            .padding(.bottom, 14)
    }

    // 工具插件
    private var pluginPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("工具插件（按需加载）")
                .font(.system(size: 18, weight: .semibold))
                .padding(.bottom, 2)

            SettingsCard {
                ForEach(model.registry.builtinTools.filter(\.isInstalled)) { tool in
                    PluginSettingsRow(
                        tool: tool,
                        isEnabled: model.registry.isEnabled(tool.id),
                        onToggle: { model.registry.toggleEnabled(tool.id) }
                    )
                }
            }

            SettingsCard {
                SettingsRow(title: "在工具箱展示未启用和规划中工具", desc: "关闭后工具箱只列出当前已启用模块，桌面更极简") {
                    OBToggle(isOn: model.settings.showInactiveTools) {
                        model.settings.showInactiveTools.toggle()
                        OBLauncherPreferences.showInactiveTools = model.settings.showInactiveTools
                    }
                }
            }
        }
    }

    /// 插件行：标题带运行时状态（· 后台监听中 · ~4 MB（按需缓存））。
    private struct PluginSettingsRow: View {
        let tool: ToolDescriptor
        let isEnabled: Bool
        let onToggle: () -> Void

        var body: some View {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(tool.name)
                            .font(.system(size: 13, weight: .medium))
                        Text(isEnabled ? "· \(tool.runtimeLabel) · \(tool.memoryLabel)" : "· 未启用 · 0 MB")
                            .font(.system(size: 11).monospaced())
                            .foregroundColor(isEnabled ? OB.green : OB.ink3)
                    }
                    Text(tool.desc)
                        .font(.system(size: 11.5))
                        .foregroundColor(OB.ink3)
                }
                Spacer(minLength: 12)
                OBToggle(isOn: isEnabled, action: onToggle)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 48, alignment: .center)
            .overlay(alignment: .bottom) { Divider().overlay(OB.hairline) }
        }
    }

    // 通用
    private var generalPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading
            SettingsCard {
                SettingsRow(title: "登录后启动", desc: "常驻菜单栏，不在 Dock 栏占用图标") {
                    OBToggle(isOn: model.settings.launchAtLogin) {
                        model.settings.launchAtLogin.toggle()
                        LaunchAtLoginController.setEnabled(model.settings.launchAtLogin)
                    }
                }
                SettingsRow(title: "点击菜单栏默认打开", desc: "工具箱聚合入口或直达单个高频工具") {
                    OBSegmentedControl(options: [true, false], title: { $0 ? "工具箱" : "剪贴板历史" },
                                        selection: Binding(get: { model.settings.defaultOpenLauncher },
                                                           set: { model.settings.defaultOpenLauncher = $0 }))
                }
            }
        }
    }

    // 全局快捷键
    private var hotkeyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading
            SettingsCard {
                SettingsRow(title: "打开工具箱", desc: "呼出工具聚合搜索入口") {
                    HotkeyButton(spec: model.settings.hotkeyLauncher) { spec in
                        model.settings.setHotkey(spec, for: "launcher")
                        model.showToast("快捷键已更新")
                    }
                }
                SettingsRow(title: "直达剪贴板历史", desc: "仅在启用剪贴板工具时注册监听") {
                    HotkeyButton(spec: model.settings.hotkeyClipboard) { spec in
                        model.settings.setHotkey(spec, for: "clipboard")
                        model.showToast("快捷键已更新")
                    }
                }
                SettingsRow(title: "开始区域截图", desc: "仅在启用截图工具时注册监听") {
                    HotkeyButton(spec: model.settings.hotkeyCapture) { spec in
                        model.settings.setHotkey(spec, for: "capture")
                        model.showToast("快捷键已更新")
                    }
                }
            }
        }
    }

    // 权限与存储
    private var storagePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading
            SettingsCard {
                SettingsRow(title: "屏幕录制", desc: "用于截图与标注工具") {
                    PermBadge(model.captureService.authorizationStatus() ? .ok("已允许") : .warn("未授权"))
                }
                SettingsRow(title: "剪贴板访问", desc: "系统隐私策略可能会提示确认") {
                    PermBadge(.warn("待实机确认"))
                }
                SettingsRow(title: "辅助功能", desc: "V1 不自动发送 Cmd+V，无需开启") {
                    PermBadge(.off("未使用"))
                }
            }
            SettingsCard {
                SettingsRow(title: "本地数据目录", desc: "所有工具数据均仅存在这台 Mac") {
                    PathChip(path: NSHomeDirectory() + "/Library/Application Support/OneBox")
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
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("总占用空间")
                    .font(.system(size: 13, weight: .medium))
                Text("剪贴板 \(clipCount) 条 · 截图 \(capCount) 条")
                    .font(.system(size: 11.5))
                    .foregroundColor(OB.ink3)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.09))
                        Capsule().fill(OB.accent)
                            .frame(width: max(4, geo.size.width * usageFraction))
                    }
                }
                .frame(width: 240, height: 5)
                .padding(.top, 4)
            }
            Spacer()
            Text(OBFormat.bytes(totalBytes))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
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
