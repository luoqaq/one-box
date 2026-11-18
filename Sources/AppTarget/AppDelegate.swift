import AppKit
import Combine
import ToolRegistry
import OneBoxUI
import ClipboardHistory
import ScreenCapture

// MARK: - 应用委托：菜单栏外壳 + 依赖组装 + 热键注册

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var instance: AppDelegate?
    static private(set) var statusItemButton: NSStatusBarButton?

    private var model: AppModel!
    private var router: WindowRouter!
    private var hotKeys: HotKeyCenter!
    private var toolEngine: ToolEngine!
    private var statusItem: NSStatusItem!
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.instance = self

        do {
            let registry = ToolRegistry()
            let settings = AppSettings()
            let appModel = try AppModel(registry: registry, settings: settings)
            model = appModel
        } catch {
            // 存储初始化失败也要能起来：给用户可见错误并退出。
            let alert = NSAlert()
            alert.messageText = "OneBox 本地存储初始化失败"
            alert.informativeText = "\(error.localizedDescription)\n\n请检查磁盘权限后重试。"
            alert.runModal()
            NSApp.terminate(self)
            return
        }

        router = WindowRouter(model: model)
        router.onToggleToolEnabled = { [weak self] id in
            self?.model.registry.toggleEnabled(id)
        }

        toolEngine = ToolEngine(model: model) { [weak self] event in
            self?.router.open(event)
        }
        toolEngine.start()

        hotKeys = HotKeyCenter()
        hotKeys.onTrigger = { [weak self] id in
            self?.handleHotKey(id)
        }
        hotKeys.onAccessibilityRequired = { [weak self] in
            self?.model.showToast("全局快捷键需要辅助功能权限：系统设置 › 隐私与安全性 › 辅助功能")
        }
        syncHotkeys()

        setupStatusItem()

        // 偏好 / 工具启用变化时重注册热键。
        model.settings.$hotkeyLauncher.dropFirst().sink { [weak self] _ in self?.syncHotkeys() }.store(in: &cancellables)
        model.settings.$hotkeyClipboard.dropFirst().sink { [weak self] _ in self?.syncHotkeys() }.store(in: &cancellables)
        model.settings.$hotkeyCapture.dropFirst().sink { [weak self] _ in self?.syncHotkeys() }.store(in: &cancellables)
        model.settings.$hotkeyColorPicker.dropFirst().sink { [weak self] _ in self?.syncHotkeys() }.store(in: &cancellables)
        model.registry.$states.dropFirst().sink { [weak self] _ in self?.syncHotkeys() }.store(in: &cancellables)

        model.reloadClipboardRecords()
        model.reloadCaptures()
    }

    // MARK: 菜单栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
            button.image?.isTemplate = true
            Self.statusItemButton = button
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    /// 叮当口袋菜单栏图标：采用原生纯矢量 DrawingHandler，在任意屏幕（Retina @2x、@3x、1x）上以物理像素级极度锐利绘制，彻底杜绝位图模糊与拉伸。
    private static func menuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // 外轮廓口袋 (占满 18x18，大号饱满半圆大肚兜)
            let pocket = NSBezierPath()
            pocket.move(to: NSPoint(x: 4.2, y: 15.2))
            pocket.line(to: NSPoint(x: 13.8, y: 15.2))
            pocket.curve(to: NSPoint(x: 16.6, y: 9.0), controlPoint1: NSPoint(x: 15.8, y: 15.2), controlPoint2: NSPoint(x: 16.6, y: 13.4))
            // 半圆弧从右侧 0° 顺时针扫到底部 (9.0, 1.4) 并到达左侧 (1.4, 9.0) 180°
            pocket.appendArc(withCenter: NSPoint(x: 9.0, y: 9.0), radius: 7.6, startAngle: 0, endAngle: 180, clockwise: true)
            pocket.curve(to: NSPoint(x: 4.2, y: 15.2), controlPoint1: NSPoint(x: 1.4, y: 13.4), controlPoint2: NSPoint(x: 2.2, y: 15.2))
            pocket.close()

            // 翻盖下凹弧线缝线
            let seam = NSBezierPath()
            seam.move(to: NSPoint(x: 2.2, y: 10.8))
            seam.curve(to: NSPoint(x: 7.2, y: 8.6), controlPoint1: NSPoint(x: 4.2, y: 9.4), controlPoint2: NSPoint(x: 5.7, y: 8.6))
            seam.move(to: NSPoint(x: 10.8, y: 8.6))
            seam.curve(to: NSPoint(x: 15.8, y: 10.8), controlPoint1: NSPoint(x: 12.3, y: 8.6), controlPoint2: NSPoint(x: 13.8, y: 9.4))

            // 铃铛圆扣 (直径 3.2pt，居中清晰醒目)
            let bell = NSBezierPath(ovalIn: NSRect(x: 7.4, y: 7.0, width: 3.2, height: 3.2))

            NSColor.black.setStroke()
            pocket.lineWidth = 1.6
            pocket.lineJoinStyle = .round
            pocket.lineCapStyle = .round
            pocket.stroke()

            seam.lineWidth = 1.5
            seam.lineCapStyle = .round
            seam.stroke()

            bell.lineWidth = 1.3
            bell.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            statusItem.menu = makeMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            // 设置了「点击菜单栏默认打开」剪贴板历史时直达。
            if model.settings.defaultOpenLauncher {
                router.toggleLauncher()
            } else if model.registry.isEnabled("clipboard") {
                router.hideLauncher()
                router.showClipboardWindow(initialSubView: .main)
            } else {
                router.toggleLauncher()
            }
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let launcherItem = NSMenuItem(title: "打开百宝袋", action: #selector(menuOpenLauncher), keyEquivalent: "")
        launcherItem.target = self
        menu.addItem(launcherItem)

        let clipboardItem = NSMenuItem(title: "剪贴板历史", action: #selector(menuOpenClipboard), keyEquivalent: "")
        clipboardItem.target = self
        menu.addItem(clipboardItem)

        let captureItem = NSMenuItem(title: "开始区域截图", action: #selector(menuStartCapture), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "偏好设置…", action: #selector(menuOpenSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 OneBox", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    @objc private func menuOpenLauncher() {
        router.hideLauncher()
        router.toggleLauncher()
    }

    @objc private func menuOpenClipboard() {
        router.hideLauncher()
        router.showClipboardWindow(initialSubView: .main)
    }

    @objc private func menuStartCapture() {
        router.startSelectionCapture()
    }

    @objc private func menuOpenSettings() {
        router.hideLauncher()
        router.showSettings()
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    // MARK: 热键

    private func syncHotkeys() {
        let s = model.settings
        hotKeys.register(id: "launcher", spec: s.hotkeyLauncher)

        // 工具专属热键只在启用时注册，停用即注销。
        if model.registry.isEnabled("clipboard") {
            hotKeys.register(id: "clipboard", spec: s.hotkeyClipboard)
        } else {
            hotKeys.unregister(id: "clipboard")
        }

        if model.registry.isEnabled("screenshots") {
            hotKeys.register(id: "capture", spec: s.hotkeyCapture)
        } else {
            hotKeys.unregister(id: "capture")
        }

        if model.registry.isEnabled("color-picker") {
            hotKeys.register(id: "colorPicker", spec: s.hotkeyColorPicker)
        } else {
            hotKeys.unregister(id: "colorPicker")
        }

        _ = hotKeys.refreshAccessibility()
    }

    private func handleHotKey(_ id: String) {
        switch id {
        case "launcher":
            router.toggleLauncher()
        case "clipboard":
            if model.registry.isEnabled("clipboard") {
                router.hideLauncher()
                router.showClipboardWindow(initialSubView: .main)
            }
        case "capture":
            if model.registry.isEnabled("screenshots") {
                router.startSelectionCapture()
            }
        case "colorPicker":
            if model.registry.isEnabled("color-picker") {
                router.startColorPick()
            }
        default:
            break
        }
    }

    // Dock 图标点击 / Cmd-Tab 切回时：没有可见窗口就打开工具箱。
    // 当前形态是菜单栏优先，默认不会自动弹出主窗口；若不处理 reopen，用户只会看到 Dock 亮起。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard model != nil, router != nil else { return true }
        if !flag {
            // 延后到下一个 runloop：等 Dock 激活落稳后再弹，
            // 否则 hidesOnDeactivate 面板会「闪一下立刻消失」。
            DispatchQueue.main.async { [weak self] in
                self?.openDefaultSurfaceFromReopen()
            }
        }
        return true
    }

    private func openDefaultSurfaceFromReopen() {
        guard model != nil, router != nil else { return }
        if model.settings.defaultOpenLauncher {
            router.presentLauncher()
        } else if model.registry.isEnabled("clipboard") {
            router.showClipboardWindow(initialSubView: .main)
        } else {
            router.presentLauncher()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.clipboardService.stop()
    }
}
