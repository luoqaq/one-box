import Combine
import Foundation
import Testing
import ToolRegistry

/// ToolRegistry 测试：搜索命中（含拼音简拼）、置顶/排序/启用语义、持久化。
@MainActor
struct ToolRegistryTests {

    /// 每个测试独立 UserDefaults，避免污染用户状态。
    private func makeDefaults() -> UserDefaults {
        let name = "toolregistry-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test("首次启动默认启用两个闭环工具并置顶")
    func defaultState() {
        let registry = ToolRegistry(defaults: makeDefaults())
        #expect(registry.isEnabled("clipboard"))
        #expect(registry.isEnabled("screenshots"))
        #expect(!registry.isEnabled("color-picker"))
        #expect(registry.builtinTools.map(\.id) == ["clipboard", "screenshots", "color-picker"])
        #expect(registry.enabledCount == 2)
        #expect(registry.disabledCount == 1)
    }

    @Test("拼音简拼与全拼搜索命中")
    func pinyinSearch() {
        let registry = ToolRegistry(defaults: makeDefaults())
        #expect(registry.search("jtb").map(\.id) == ["clipboard"])       // 剪贴板简拼
        #expect(registry.search("jt").contains { $0.id == "screenshots" }) // 截图简拼
        #expect(registry.search("截图").contains { $0.id == "screenshots" })
        #expect(registry.search("取色").contains { $0.id == "color-picker" })
        #expect(registry.search("bucunzai").isEmpty)
    }

    @Test("置顶隐含启用，停用取消置顶")
    func pinEnableSemantics() {
        let registry = ToolRegistry(defaults: makeDefaults())
        registry.setEnabled("color-picker", false)
        registry.togglePinned("color-picker")
        #expect(registry.isEnabled("color-picker"))
        #expect(registry.state(of: registry.tool(id: "color-picker")!).pinned)

        registry.setEnabled("color-picker", false)
        #expect(!registry.state(of: registry.tool(id: "color-picker")!).pinned)
        #expect(!registry.isEnabled("color-picker"))
    }

    @Test("置顶序列内上下移与拖拽交换")
    func reorder() {
        let registry = ToolRegistry(defaults: makeDefaults())
        let order0 = registry.pinnedTools().map(\.id)
        #expect(order0 == ["clipboard", "screenshots"])

        registry.movePinned("screenshots", offset: -1)
        #expect(registry.pinnedTools().map(\.id) == ["screenshots", "clipboard"])

        registry.reorderPinned(dragID: "clipboard", ontoID: "screenshots")
        #expect(registry.pinnedTools().map(\.id) == ["clipboard", "screenshots"])
    }

    @Test("上下移发布 states，供 UI 观察刷新")
    func movePinnedPublishes() {
        let registry = ToolRegistry(defaults: makeDefaults())
        var emissions = 0
        let sub = registry.$states.dropFirst().sink { _ in emissions += 1 }
        registry.movePinned("screenshots", offset: -1)
        #expect(emissions >= 1)
        #expect(registry.pinnedTools().map(\.id) == ["screenshots", "clipboard"])
        _ = sub
    }

    @Test("置顶优先排序 + 状态过滤")
    func filterAndSort() {
        let registry = ToolRegistry(defaults: makeDefaults())
        let disabled = registry.filteredTools(filter: .disabled, search: "", sortMode: .pinned, showInactive: true)
        #expect(disabled.allSatisfy { registry.availability(of: $0) == .disabled })
        #expect(disabled.count == 1)

        let enabled = registry.filteredTools(filter: .enabled, search: "", sortMode: .frequent, showInactive: true)
        #expect(enabled.count == 2)

        // showInactive=false 时 all 过滤器只显示启用工具。
        let activeOnly = registry.filteredTools(filter: .all, search: "", sortMode: .pinned, showInactive: false)
        #expect(activeOnly.allSatisfy { registry.availability(of: $0) == .enabled })
    }

    @Test("使用次数与状态持久化到 UserDefaults")
    func persistence() {
        let suite = "toolregistry-persist-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)

        let first = ToolRegistry(defaults: d)
        first.togglePinned("color-picker")
        first.registerUse("clipboard")
        first.registerUse("clipboard")

        let second = ToolRegistry(defaults: d)
        #expect(second.isEnabled("color-picker"))
        #expect(second.state(of: second.tool(id: "color-picker")!).pinned)
        #expect(second.state(of: second.tool(id: "clipboard")!).uses == 2)
    }

    @Test("工具图标颜色定义符合浅色透明规范且剪贴板颜色匹配")
    func toolColors() {
        let registry = ToolRegistry(defaults: makeDefaults())
        let clipboard = registry.tool(id: "clipboard")!
        #expect(clipboard.fgHex == "#007aff")
        #expect(clipboard.bgHex == "#007aff1c")

        for tool in registry.builtinTools {
            #expect(tool.fgHex.hasPrefix("#"))
            #expect(tool.bgHex.hasPrefix("#"))
            #expect(tool.bgHex.count == 9) // #RRGGBBAA
        }
    }
}
