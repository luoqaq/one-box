import Foundation

/// V1 内置工具注册表（静态描述 + UserDefaults 持久化运行时状态）。
/// 工具箱与设置只读这里，不知道剪贴板/截图的实现。
@MainActor
public final class ToolRegistry: ObservableObject {
    private static let storageKey = "onebox.tools.runtime-state.v1"

    @Published public private(set) var states: [String: ToolRuntimeState]
    public let builtinTools: [ToolDescriptor]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let tools = Self.makeBuiltinTools()
        self.builtinTools = tools

        var loaded: [String: ToolRuntimeState] = [:]
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: ToolRuntimeState].self, from: data) {
            loaded = decoded
        }
        if loaded.isEmpty {
            // 首次启动默认值：两个闭环工具启用 + 置顶；取色器默认未启用。
            loaded["clipboard"] = ToolRuntimeState(enabled: true, pinned: true, order: 1, uses: 0)
            loaded["screenshots"] = ToolRuntimeState(enabled: true, pinned: true, order: 2, uses: 0)
            loaded["color-picker"] = ToolRuntimeState(enabled: false, pinned: false, order: 3, uses: 0)
        }
        var merged: [String: ToolRuntimeState] = [:]
        for tool in tools {
            if var s = loaded[tool.id] {
                // 规划中的工具永远不可启用。
                if !tool.isInstalled {
                    s.enabled = false
                    s.pinned = false
                }
                merged[tool.id] = s
            } else {
                merged[tool.id] = ToolRuntimeState(
                    enabled: false, pinned: false,
                    order: (merged.values.map(\.order).max() ?? 0) + 1, uses: 0
                )
            }
        }
        self.states = merged
        persist()
    }

    // MARK: - 查询

    public func tool(id: String) -> ToolDescriptor? {
        builtinTools.first { $0.id == id }
    }

    public func state(of tool: ToolDescriptor) -> ToolRuntimeState {
        states[tool.id] ?? ToolRuntimeState()
    }

    public func availability(of tool: ToolDescriptor) -> ToolAvailability {
        if !tool.isInstalled { return .planned }
        return state(of: tool).enabled ? .enabled : .disabled
    }

    public func isEnabled(_ id: String) -> Bool {
        guard let tool = tool(id: id), tool.isInstalled else { return false }
        return states[id]?.enabled ?? false
    }

    public var enabledCount: Int {
        builtinTools.filter { availability(of: $0) == .enabled }.count
    }

    public var disabledCount: Int {
        builtinTools.filter { availability(of: $0) == .disabled }.count
    }

    /// 搜索：名称 + 描述 + 关键词（含拼音简拼/全拼），大小写不敏感。
    /// 不去掉内部空白：「jt bz」不能拼成「jtbz」而误命中「jtb」。
    public func search(_ query: String) -> [ToolDescriptor] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return builtinTools }
        return builtinTools.filter { tool in
            let haystack = "\(tool.name) \(tool.desc) \(tool.keywords)".lowercased()
            return haystack.contains(q)
        }
    }

    /// 过滤 + 排序后的工具列表（工具箱主列表使用）。
    public func filteredTools(
        filter: LauncherFilter,
        search query: String,
        sortMode: LauncherSortMode,
        showInactive: Bool
    ) -> [ToolDescriptor] {
        var list = search(query)
        if !showInactive && filter == .all {
            list = list.filter { availability(of: $0) == .enabled }
        }
        list = list.filter { tool in
            switch filter {
            case .all: return true
            case .pinned: return state(of: tool).pinned
            case .enabled: return availability(of: tool) == .enabled
            case .disabled: return availability(of: tool) == .disabled
            }
        }
        return sorted(list, sortMode: sortMode)
    }

    /// 置顶工具（启用且 pinned），按 order 升序，供 ↑↓ 与拖拽排序。
    public func pinnedTools() -> [ToolDescriptor] {
        builtinTools
            .filter { state(of: $0).pinned && availability(of: $0) == .enabled }
            .sorted { state(of: $0).order < state(of: $1).order }
    }

    public func sorted(_ list: [ToolDescriptor], sortMode: LauncherSortMode) -> [ToolDescriptor] {
        list.sorted { a, b in
            let sa = state(of: a)
            let sb = state(of: b)
            switch sortMode {
            case .frequent:
                if sa.enabled != sb.enabled { return sa.enabled }
                if sa.uses != sb.uses { return sa.uses > sb.uses }
                return sa.order < sb.order
            case .pinned:
                if sa.pinned != sb.pinned { return sa.pinned }
                return sa.order < sb.order
            }
        }
    }

    // MARK: - 变更

    /// 启用/停用。停用时取消置顶（原型 toggleToolEnabled 语义）。
    public func setEnabled(_ id: String, _ on: Bool) {
        guard var s = states[id], tool(id: id)?.isInstalled == true else { return }
        s.enabled = on
        if !on { s.pinned = false }
        states[id] = s
        persist()
    }

    public func toggleEnabled(_ id: String) {
        setEnabled(id, !(states[id]?.enabled ?? false))
    }

    /// 置顶/取消置顶。置顶隐含启用；置顶时 order 排到已置顶之后。
    public func togglePinned(_ id: String) {
        guard var s = states[id], tool(id: id)?.isInstalled == true else { return }
        s.pinned.toggle()
        if s.pinned {
            if !s.enabled { s.enabled = true }
            let maxOrder = states.values.map(\.order).max() ?? 0
            s.order = maxOrder + 1
        }
        states[id] = s
        persist()
    }

    /// 在置顶序列内上移/下移。
    public func movePinned(_ id: String, offset: Int) {
        let pinned = pinnedTools()
        guard let idx = pinned.firstIndex(where: { $0.id == id }) else { return }
        let target = idx + offset
        guard pinned.indices.contains(target) else { return }
        let a = pinned[idx].id
        let b = pinned[target].id
        // 整值写回，确保 @Published 发出变更（原地改 Dictionary 内字段不会）。
        var sa = states[a]!
        var sb = states[b]!
        let tmp = sa.order
        sa.order = sb.order
        sb.order = tmp
        states[a] = sa
        states[b] = sb
        persist()
    }

    /// 拖拽排序：把 dragID 移到 ontoID 的位置（交换 order，原型同款语义）。
    public func reorderPinned(dragID: String, ontoID: String) {
        guard dragID != ontoID,
              var a = states[dragID], var b = states[ontoID],
              a.pinned, b.pinned else { return }
        let tmp = a.order
        a.order = b.order
        b.order = tmp
        states[dragID] = a
        states[ontoID] = b
        persist()
    }

    public func registerUse(_ id: String) {
        guard states[id] != nil else { return }
        states[id]!.uses += 1
        persist()
    }

    // MARK: - Private

    private func persist() {
        if let data = try? JSONEncoder().encode(states) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }


    private static func makeBuiltinTools() -> [ToolDescriptor] {
        [
            ToolDescriptor(
                id: "clipboard",
                name: "剪贴板历史",
                desc: "记录文本和图片，支持搜索、预览、置顶与专属配置",
                category: .efficiency,
                keywords: "clipboard copy paste jtb jianqieban 复制 粘贴 历史",
                defaultShortcut: "⌃⌥V",
                hotkeyID: "clipboard",
                destination: .clipboard,
                isInstalled: true,
                iconID: "clipboard",
                fgHex: "#007aff",
                bgHex: "#007aff1c",
                runtimeLabel: "后台监听中",
                memoryLabel: "~4 MB（按需缓存）"
            ),
            ToolDescriptor(
                id: "screenshots",
                name: "截图与标注",
                desc: "区域截图、矢量标注、最近截图与保存配置",
                category: .image,
                keywords: "screenshot capture annotation jt bz jietu 截图 标注 打码 最近",
                defaultShortcut: "⌃⌥⇧4",
                hotkeyID: "capture",
                destination: .screenshots,
                quickAction: ToolQuickAction(label: "立即截图", destination: .capture),
                isInstalled: true,
                iconID: "camera",
                fgHex: "#1d9a54",
                bgHex: "#1d9a541c",
                runtimeLabel: "热键待命",
                memoryLabel: "<1 MB（打开画布时加载）"
            ),
            ToolDescriptor(
                id: "color-picker",
                name: "屏幕取色器",
                desc: "吸取屏幕颜色并复制 HEX / RGB / OKLCH 色值",
                category: .developer,
                keywords: "color picker qs quse 取色 色值 hex rgb oklch",
                defaultShortcut: "⌃⌥C",
                hotkeyID: "colorPicker",
                destination: .colorPicker,
                quickAction: ToolQuickAction(label: "立即取色", destination: .colorPicker),
                isInstalled: true,
                iconID: "eyedropper",
                fgHex: "#af52de",
                bgHex: "#af52de1a",
                runtimeLabel: "热键待命",
                memoryLabel: "<1 MB（取色时加载）"
            ),
        ]
    }
}
