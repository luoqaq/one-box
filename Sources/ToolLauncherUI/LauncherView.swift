import SwiftUI
import UniformTypeIdentifiers
import ToolRegistry

// MARK: - 工具箱（原型 view-launcher：单栏直达，无右侧详情栏）

/// 工具箱跳进全局设置时的落点。
public enum LauncherSettingsTarget: String, Sendable {
    case plugins
    case hotkeys
    case general
    case storage
}

public struct LauncherView: View {
    @ObservedObject var registry: ToolRegistry
    /// 按工具返回外侧展示的全局热键文案（如 "⌃⌥V"）；无则不显示。
    let hotkeyLabel: (ToolDescriptor) -> String?
    let onOpen: (ToolDestination) -> Void
    let onOpenConfig: (ToolDestination) -> Void
    let onQuickAction: (ToolDestination) -> Void
    let onOpenSettings: (LauncherSettingsTarget) -> Void
    let onToggleEnabled: (String) -> Void

    @State private var searchText = ""
    @State private var filter: LauncherFilter = .all
    @State private var sortMode: LauncherSortMode = .pinned
    @State private var selectedID: String?
    @State private var toast: String?
    @FocusState private var searchFocused: Bool
    @State private var keyboardMonitor: Any?

    public init(
        registry: ToolRegistry,
        hotkeyLabel: @escaping (ToolDescriptor) -> String? = { $0.defaultShortcut },
        onOpen: @escaping (ToolDestination) -> Void,
        onOpenConfig: @escaping (ToolDestination) -> Void,
        onQuickAction: @escaping (ToolDestination) -> Void,
        onOpenSettings: @escaping (LauncherSettingsTarget) -> Void,
        onToggleEnabled: @escaping (String) -> Void
    ) {
        self._registry = ObservedObject(wrappedValue: registry)
        self.hotkeyLabel = hotkeyLabel
        self.onOpen = onOpen
        self.onOpenConfig = onOpenConfig
        self.onQuickAction = onQuickAction
        self.onOpenSettings = onOpenSettings
        self.onToggleEnabled = onToggleEnabled
    }

    /// 过滤 + 排序后的当前列表（上下键选择共用）。
    private var items: [ToolDescriptor] {
        registry.filteredTools(
            filter: filter,
            search: searchText,
            sortMode: sortMode,
            showInactive: OBLauncherPreferences.showInactiveTools
        )
    }

    private var enabledOrdered: [ToolDescriptor] {
        items.filter { registry.availability(of: $0) == .enabled }
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchBar
            filterBar
            toolList
            footer
        }
        .frame(width: 600, height: 540)
        .background(GlassPanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(toastOverlay)
        .onAppear {
            searchFocused = true
            installKeyboardMonitor()
        }
        .onDisappear {
            if let monitor = keyboardMonitor {
                NSEvent.removeMonitor(monitor)
                keyboardMonitor = nil
            }
        }
        .preferredColorScheme(.light)
        .tint(OB.accent)
    }

    // MARK: 搜索栏（54pt）

    private var searchBar: some View {
        ZStack {
            OB.glassBar1.allowsHitTesting(false)
            WindowDragRegion()
            HStack(spacing: 11) {
                OBIcon(.search, size: 18, weight: 1.65)
                    .foregroundColor(OB.ink3)
                    .allowsHitTesting(false)
                TextField("搜索工具、拼音简拼（jtb / jt）或关键词…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .regular))
                    .focused($searchFocused)
                    .onSubmit { openSelected() }
                HStack(spacing: 6) {
                    Kbd(text: "⌘K").allowsHitTesting(false)
                    LauncherIconButton(icon: .gear, title: "全局设置与工具管理") { onOpenSettings(.plugins) }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 54)
        .overlay(alignment: .bottom) { Divider().overlay(OB.hairline) }
    }

    // MARK: 过滤栏（38pt）

    private var filterBar: some View {
        ZStack {
            OB.glassBar2.allowsHitTesting(false)
            WindowDragRegion()
            HStack {
                HStack(spacing: 2) {
                    ForEach(LauncherFilter.allCases, id: \.self) { f in
                        pill(f.title, active: filter == f) {
                            filter = f
                        }
                    }
                }
                Spacer(minLength: 0).allowsHitTesting(false)
                HStack(spacing: 6) {
                    Button {
                        sortMode = sortMode == .pinned ? .frequent : .pinned
                    } label: {
                        HStack(spacing: 4) {
                            OBIcon(.refresh, size: 12, weight: 1.65)
                                .opacity(0.75)
                            Text(sortMode.title)
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundColor(OB.ink2)
                        .padding(.horizontal, 8)
                        .frame(height: 25)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Text("\(registry.enabledCount) 启用 · \(registry.disabledCount) 待机")
                        .font(.system(size: 11))
                        .foregroundColor(OB.ink3)
                        .monospacedDigit()
                        .padding(.trailing, 4)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 38)
        .overlay(alignment: .bottom) { Divider().overlay(OB.hairline) }
    }

    private func pill(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(active ? OB.ink : OB.ink2)
                .padding(.horizontal, 10)
                .frame(height: 25)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? Color.white.opacity(0.85) : Color.clear)
                        .shadow(color: active ? OB.hairline : .clear, radius: 1, x: 0, y: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: 工具列表

    private var toolList: some View {
        ScrollView {
            LazyVStack(spacing: 2, pinnedViews: []) {
                let pinned = items.filter { registry.state(of: $0).pinned && registry.availability(of: $0) == .enabled }
                let otherEnabled = items.filter { !registry.state(of: $0).pinned && registry.availability(of: $0) == .enabled }
                let disabled = items.filter { registry.availability(of: $0) == .disabled }
                let planned = items.filter { registry.availability(of: $0) == .planned }

                if !pinned.isEmpty {
                    groupLabel("已置顶", trailing: "可拖拽或 ↑↓ 排序")
                    ForEach(pinned) { tool in
                        row(tool)
                    }
                }
                if !otherEnabled.isEmpty {
                    groupLabel("已启用", trailing: "\(otherEnabled.count)", topPadding: 4)
                    ForEach(otherEnabled) { tool in
                        row(tool)
                    }
                }
                if !disabled.isEmpty {
                    groupLabel("已内置 · 未启用（0 内存）", trailing: "\(disabled.count)", topPadding: 6)
                    ForEach(disabled) { tool in
                        row(tool)
                    }
                }
                if !planned.isEmpty {
                    groupLabel("后续扩展", trailing: "\(planned.count)", topPadding: 6)
                    ForEach(planned) { tool in
                        row(tool)
                    }
                }
                if items.isEmpty {
                    Text("没有匹配的工具")
                        .font(.system(size: 12.5))
                        .foregroundColor(OB.ink3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private func groupLabel(_ title: String, trailing: String? = nil, topPadding: CGFloat = 0) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let trailing {
                Text(trailing)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(OB.ink3)
        .padding(.horizontal, 10)
        .padding(.top, 8 + topPadding)
        .padding(.bottom, 4)
    }

    // MARK: 工具行

    private func row(_ tool: ToolDescriptor) -> some View {
        let state = registry.state(of: tool)
        let availability = registry.availability(of: tool)
        let isSelected = selectedID == tool.id

        return ToolRowView(
            tool: tool,
            state: state,
            availability: availability,
            globalHotkey: hotkeyLabel(tool),
            isSelected: isSelected,
            registry: registry,
            onOpen: { open(tool) },
            onPin: {
                registry.togglePinned(tool.id)
                showToast(state.pinned ? "已取消置顶「\(tool.name)」" : "已置顶「\(tool.name)」")
            },
            onMoveUp: { registry.movePinned(tool.id, offset: -1) },
            onMoveDown: { registry.movePinned(tool.id, offset: 1) },
            onConfig: {
                // 有独立配置页的工具直达；带热键的进快捷键页；其余进插件管理。
                if tool.id == "clipboard" {
                    onOpenConfig(.clipboard)
                } else if tool.id == "screenshots" {
                    onOpenConfig(.screenshots)
                } else if tool.hotkeyID != nil {
                    onOpenSettings(.hotkeys)
                } else {
                    onOpenSettings(.plugins)
                }
            },
            onToggleEnabled: {
                onToggleEnabled(tool.id)
                let enabled = registry.isEnabled(tool.id)
                showToast(enabled ? "已启用「\(tool.name)」" : "已停用「\(tool.name)」，运行时内存已释放")
            },
            onQuickAction: { dest in onQuickAction(dest) }
        )
    }

    private func open(_ tool: ToolDescriptor) {
        guard tool.isInstalled else { return }
        if !registry.isEnabled(tool.id) {
            onToggleEnabled(tool.id)
            showToast("已按需加载「\(tool.name)」")
        }
        registry.registerUse(tool.id)
        if let dest = tool.destination {
            onOpen(dest)
        } else {
            showToast("已进入「\(tool.name)」工作台（扩展模块预览）")
        }
    }

    private func openSelected() {
        if let id = selectedID, let tool = registry.tool(id: id) {
            open(tool)
        } else if let first = enabledOrdered.first {
            open(first)
        }
    }

    // MARK: 底栏（36pt）

    private var footer: some View {
        ZStack {
            OB.glassFooter.allowsHitTesting(false)
            WindowDragRegion()
            HStack {
                Text("单击整行直达 · 拖拽或点 ↑↓ 调整置顶顺序")
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    hint("↑↓", "选择")
                    hint("↵", "打开")
                }
            }
            .font(.system(size: 11.5))
            .foregroundColor(OB.ink3)
            .padding(.horizontal, 14)
            .allowsHitTesting(false)
        }
        .frame(height: 36)
        .overlay(alignment: .top) { Divider().overlay(OB.hairline) }
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Kbd(text: keys)
            Text(label)
        }
    }

    // MARK: 键盘

    private func installKeyboardMonitor() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak registry] event in
            guard registry != nil, event.window?.contentView?.window is NSWindow else { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasCommand = flags.contains(.command)

            if hasCommand, let key = event.charactersIgnoringModifiers, key.lowercased() == "k" {
                searchFocused = true
                return nil
            }
            guard !hasCommand else { return event }
            switch event.specialKey {
            case .downArrow:
                moveSelection(1)
                return nil
            case .upArrow:
                moveSelection(-1)
                return nil
            case .carriageReturn:
                if selectedID != nil {
                    openSelected()
                    return nil
                }
            default:
                break
            }
            return event
        }
    }

    private func moveSelection(_ delta: Int) {
        let list = items
        guard !list.isEmpty else { return }
        let idx = selectedID.flatMap { id in list.firstIndex(where: { $0.id == id }) } ?? -1
        let next = list[(idx + delta + list.count) % list.count]
        selectedID = next.id
    }

    // MARK: Toast

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast {
            ToastView(text: toast)
                .padding(.bottom, 44)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        if self.toast == toast { self.toast = nil }
                    }
                }
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.easeInOut(duration: 0.16)) { toast = text }
    }
}

private struct LauncherIconButton: View {
    let icon: OBIcon.ID
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            OBIcon(icon, size: 15.5, weight: 1.6)
                .foregroundColor(isHovering ? OB.ink : OB.ink2)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHovering ? OB.surfaceHover : OB.surfaceSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isHovering ? OB.hairline : OB.surfaceSubtle, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(title)
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}

private struct LauncherRowMiniButton: View {
    let icon: OBIcon.ID
    let title: String
    var filled: Bool = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            OBIcon(icon, size: 13, weight: 1.55)
                .foregroundColor(filled ? OB.brandYellowInk : (isHovering ? OB.ink : OB.ink2))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(filled ? OB.brandYellowSoft : (isHovering ? OB.surfaceActive : OB.surfaceSubtle))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isHovering ? OB.hairline : Color.clear, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(title)
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}

// MARK: - 工具行视图

struct ToolRowView: View {
    let tool: ToolDescriptor
    let state: ToolRuntimeState
    let availability: ToolAvailability
    let globalHotkey: String?
    let isSelected: Bool
    let registry: ToolRegistry
    let onOpen: () -> Void
    let onPin: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onConfig: () -> Void
    let onToggleEnabled: () -> Void
    let onQuickAction: (ToolDestination) -> Void

    @State private var isHovering = false
    @State private var isDragOver = false

    var body: some View {
        HStack(spacing: 11) {
            // squircle 图标
            let fgColor = Color(flexibleHex: tool.fgHex)
            let bgColor = Color(flexibleHex: tool.bgHex)

            OBIcon(tool.iconID, size: 17.5, weight: 1.65)
                .foregroundColor(fgColor)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(bgColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(fgColor.opacity(0.18), lineWidth: 0.5)
                )
                .shadow(color: fgColor.opacity(0.08), radius: 2, x: 0, y: 1)

            // 名称 + 热键提示（替代原描述文案）
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(tool.name)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(isSelected ? OB.accentInk : OB.ink)
                    if availability == .disabled {
                        Text("· 未启用")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(OB.ink3)
                    } else if availability == .planned {
                        Text("· 规划中")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(OB.ink3)
                    }
                }
                subtitleHint
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右侧操作：快捷动作 / 悬停操作，设置齿轮始终在最右
            HStack(spacing: 6) {
                if isHovering || isSelected {
                    hoverActions
                }
                trailingActions
                if tool.isInstalled, availability != .planned {
                    miniAction(.gear, title: "打开工具配置") { onConfig() }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 50, alignment: .center)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(availability == .planned ? 0.46 : availability == .disabled ? 0.72 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard tool.isInstalled, availability != .planned else { return }
            onOpen()
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .onDrag {
            guard state.pinned else { return NSItemProvider() }
            return NSItemProvider(object: tool.id as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: ToolDropDelegate(
                targetID: tool.id,
                registry: registry,
                isPinnedTarget: state.pinned,
                onDragOver: { isDragOver = $0 }
            )
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(OB.brandYellow)
                    .frame(width: 3, height: 22)
                    .padding(.leading, 3)
            }
        }
        .overlay(alignment: .top) {
            if isDragOver {
                RoundedRectangle(cornerRadius: 1)
                    .fill(OB.brandYellow)
                    .frame(height: 2)
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        let active = isSelected
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                active ? OB.accentSoft
                : (isHovering && tool.isInstalled && availability != .planned ? OB.surfaceSubtle : Color.clear)
            )
    }

    @ViewBuilder
    private var hoverActions: some View {
        HStack(spacing: 2) {
            if tool.isInstalled {
                if state.pinned {
                    miniAction(.chevronUp, title: "上移排序") { onMoveUp() }
                    miniAction(.chevronDown, title: "下移排序") { onMoveDown() }
                }
                miniAction(.pin, title: state.pinned ? "取消置顶" : "置顶", filled: state.pinned) { onPin() }
                miniAction(.power, title: state.enabled ? "停用释放内存" : "启用") { onToggleEnabled() }
            }
        }
    }

    /// 标题下提示：有全局热键时说明「按什么键能干什么」；否则回退短状态文案。
    @ViewBuilder
    private var subtitleHint: some View {
        if let globalHotkey, globalHotkey != "—", !globalHotkey.isEmpty, let action = hotkeyActionHint {
            HStack(spacing: 6) {
                Kbd(text: globalHotkey)
                Text(action)
                    .font(.system(size: 11.5))
                    .foregroundColor(OB.ink3)
                    .lineLimit(1)
            }
        } else {
            Text(fallbackSubtitle)
                .font(.system(size: 11.5))
                .foregroundColor(OB.ink3)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// 各工具热键动作说明（比通用 desc 更直接）。
    private var hotkeyActionHint: String? {
        switch tool.id {
        case "clipboard": return "快速打开粘贴历史"
        case "screenshots": return "快速截图"
        case "color-picker": return "快速取色"
        default: return nil
        }
    }

    private var fallbackSubtitle: String {
        if availability == .planned { return "后续版本扩展" }
        if availability == .disabled { return "启用后可在此使用" }
        return tool.desc
    }

    @ViewBuilder
    private var trailingActions: some View {
        if availability == .enabled, let quick = tool.quickAction {
            Button {
                onQuickAction(quick.destination)
            } label: {
                HStack(spacing: 4) {
                    Text(quick.label)
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundColor(OB.green)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(OB.greenSoft)
                )
            }
            .buttonStyle(.plain)
        } else if availability == .disabled {
            Button {
                onToggleEnabled()
            } label: {
                Text("启用")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(OB.ink2)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(OB.btnFill)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func miniAction(_ icon: OBIcon.ID, title: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        LauncherRowMiniButton(icon: icon, title: title, filled: filled, action: action)
    }
}

// MARK: - 拖拽排序

struct ToolDropDelegate: DropDelegate {
    let targetID: String
    let registry: ToolRegistry
    let isPinnedTarget: Bool
    let onDragOver: (Bool) -> Void

    func dropEntered(info: DropInfo) {
        onDragOver(true)
        guard isPinnedTarget else { return }
        // 拖拽源 id 从 NSItemProvider 异步读出，回主线程交换 order。
        info.itemProviders(for: [UTType.text]).first?.loadObject(ofClass: NSString.self) { object, _ in
            guard let dragID = object as? String, dragID != self.targetID else { return }
            Task { @MainActor in
                self.registry.reorderPinned(dragID: dragID, ontoID: self.targetID)
            }
        }
    }

    func dropExited(info: DropInfo) {
        onDragOver(false)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: isPinnedTarget ? .move : .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        onDragOver(false)
        return true
    }
}

// MARK: - 偏好

/// 工具箱显示未启用/规划中工具的偏好（设置页同步）。
public enum OBLauncherPreferences {
    public static var showInactiveTools: Bool {
        get { UserDefaults.standard.object(forKey: "onebox.launcher.showInactive") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "onebox.launcher.showInactive") }
    }
}

import AppKit
