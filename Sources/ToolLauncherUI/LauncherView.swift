import SwiftUI
import UniformTypeIdentifiers
import ToolRegistry

// MARK: - 工具箱（原型 view-launcher：单栏直达，无右侧详情栏）

public struct LauncherView: View {
    let registry: ToolRegistry
    let onOpen: (ToolDestination) -> Void
    let onOpenConfig: (ToolDestination) -> Void
    let onQuickAction: (ToolDestination) -> Void
    let onOpenSettings: () -> Void
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
        onOpen: @escaping (ToolDestination) -> Void,
        onOpenConfig: @escaping (ToolDestination) -> Void,
        onQuickAction: @escaping (ToolDestination) -> Void,
        onOpenSettings: @escaping () -> Void,
        onToggleEnabled: @escaping (String) -> Void
    ) {
        self.registry = registry
        self.onOpen = onOpen
        self.onOpenConfig = onOpenConfig
        self.onQuickAction = onQuickAction
        self.onOpenSettings = onOpenSettings
        self.onToggleEnabled = onToggleEnabled
    }

    /// 过滤 + 排序后的当前列表（⌘1-9 与上下键共用）。
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
    }

    // MARK: 搜索栏（54pt）

    private var searchBar: some View {
        HStack(spacing: 11) {
            OBIcon(.search, size: 18, weight: 2)
                .foregroundColor(OB.ink3)
            TextField("搜索工具、拼音简拼（jtb / jt）或关键词…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .regular))
                .focused($searchFocused)
                .onSubmit { openSelected() }
            HStack(spacing: 6) {
                Kbd(text: "⌘K")
                iconButton(.gear, title: "全局设置与工具管理") { onOpenSettings() }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(OB.glassBar1)
        .overlay(alignment: .bottom) { Divider().overlay(OB.hairline) }
    }

    // MARK: 过滤栏（38pt）

    private var filterBar: some View {
        HStack {
            HStack(spacing: 2) {
                ForEach(LauncherFilter.allCases, id: \.self) { f in
                    pill(f.title, active: filter == f) {
                        filter = f
                    }
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Button {
                    sortMode = sortMode == .pinned ? .frequent : .pinned
                } label: {
                    HStack(spacing: 4) {
                        OBIcon(.refresh, size: 12, weight: 2)
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
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(OB.glassBar2)
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
                        .shadow(color: active ? Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.08) : .clear, radius: 1, x: 0, y: 1)
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
                    ForEach(Array(pinned.enumerated()), id: \.element.id) { idx, tool in
                        row(tool, quickIndex: idx + 1)
                    }
                }
                if !otherEnabled.isEmpty {
                    groupLabel("已启用", trailing: "\(otherEnabled.count)", topPadding: 4)
                    ForEach(Array(otherEnabled.enumerated()), id: \.element.id) { idx, tool in
                        row(tool, quickIndex: pinned.count + idx + 1)
                    }
                }
                if !disabled.isEmpty {
                    groupLabel("已内置 · 未启用（0 内存）", trailing: "\(disabled.count)", topPadding: 6)
                    ForEach(disabled) { tool in
                        row(tool, quickIndex: 0)
                    }
                }
                if !planned.isEmpty {
                    groupLabel("后续扩展", trailing: "\(planned.count)", topPadding: 6)
                    ForEach(planned) { tool in
                        row(tool, quickIndex: 0)
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

    private func row(_ tool: ToolDescriptor, quickIndex: Int) -> some View {
        let state = registry.state(of: tool)
        let availability = registry.availability(of: tool)
        let isSelected = selectedID == tool.id

        return ToolRowView(
            tool: tool,
            state: state,
            availability: availability,
            quickIndex: quickIndex,
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
                if availability == .disabled { onToggleEnabled(tool.id) }
                if tool.id == "clipboard" { onOpenConfig(.clipboard) }
                else if tool.id == "screenshots" { onOpenConfig(.screenshots) }
                else { onToggleEnabled(tool.id) }
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
        HStack {
            Text("单击整行直达 · 拖拽或点 ↑↓ 调整置顶顺序")
            Spacer()
            HStack(spacing: 12) {
                hint("⌘1-9", "秒开")
                hint("↑↓", "选择")
                hint("↵", "打开")
            }
        }
        .font(.system(size: 11.5))
        .foregroundColor(OB.ink3)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(OB.glassFooter)
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
            guard let registry, event.window?.contentView?.window is NSWindow else { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasCommand = flags.contains(.command)

            if hasCommand, let key = event.charactersIgnoringModifiers, key.lowercased() == "k" {
                searchFocused = true
                return nil
            }
            if hasCommand, let digit = event.charactersIgnoringModifiers, digit.range(of: "^[1-9]$", options: .regularExpression) != nil {
                let index = Int(digit)! - 1
                if index < enabledOrdered.count {
                    open(enabledOrdered[index])
                    return nil
                }
                return event
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

private func iconButton(_ icon: OBIcon.ID, title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        OBIcon(icon, size: 15, weight: 1.9)
            .foregroundColor(OB.ink2)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.clear)
            )
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(title)
}

// MARK: - 工具行视图

struct ToolRowView: View {
    let tool: ToolDescriptor
    let state: ToolRuntimeState
    let availability: ToolAvailability
    let quickIndex: Int
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
            OBIcon(tool.iconID, size: 17)
                .foregroundColor(Color(flexibleHex: tool.fgHex))
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(flexibleHex: tool.bgHex))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.06), lineWidth: 0.5)
                )

            // 名称 + 描述
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    if availability == .enabled {
                        StatusDot(standby: tool.id != "clipboard")
                    }
                    Text(tool.name)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(isSelected ? OB.accentInk : OB.ink)
                    if availability == .disabled {
                        Text("· 未启用（0 内存）")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(OB.ink3)
                    } else if availability == .planned {
                        Text("· 规划中")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(OB.ink3)
                    }
                }
                Text(tool.desc)
                    .font(.system(size: 11.5))
                    .foregroundColor(OB.ink3)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右侧操作
            HStack(spacing: 6) {
                if isHovering || isSelected {
                    hoverActions
                }
                trailingControls
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
        .overlay(alignment: .top) {
            if isDragOver {
                RoundedRectangle(cornerRadius: 1)
                    .fill(OB.accent)
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
                miniAction(.gear, title: "工具配置") { onConfig() }
                miniAction(.power, title: state.enabled ? "停用释放内存" : "启用") { onToggleEnabled() }
            }
        }
    }

    @ViewBuilder
    private var trailingControls: some View {
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
                            .fill(Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.06))
                    )
            }
            .buttonStyle(.plain)
        }

        // ⌘1-9 或全局快捷键
        if availability == .enabled, quickIndex >= 1, quickIndex <= 9 {
            Kbd(text: "⌘\(quickIndex)")
        } else if availability == .enabled, let shortcut = tool.defaultShortcut, shortcut != "—" {
            Text(shortcut)
                .font(.system(size: 11).monospaced())
                .foregroundColor(OB.ink3)
        }
    }

    private func miniAction(_ icon: OBIcon.ID, title: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            OBIcon(icon, size: 13, weight: 1.9)
                .foregroundColor(filled ? OB.accent : OB.ink3)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering ? Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.08) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
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
