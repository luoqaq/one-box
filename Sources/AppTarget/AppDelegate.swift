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
        syncHotkeys()

        setupStatusItem()

        // 偏好变化时重注册热键。
        model.settings.$hotkeyLauncher.dropFirst().sink { [weak self] _ in self?.syncHotkeys() }.store(in: &cancellables)
        model.settings.$hotkeyClipboard.dropFirst().sink { [weak self] _ in self?.syncHotkeys() }.store(in: &cancellables)
        model.settings.$hotkeyCapture.dropFirst().sink { [weak self] _ in self?.syncHotkeys() }.store(in: &cancellables)

        model.reloadClipboardRecords()
        model.reloadCaptures()
    }

    // MARK: 菜单栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "OneBox")
            button.image?.isTemplate = true
            Self.statusItemButton = button
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
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

        let launcherItem = NSMenuItem(title: "打开工具箱", action: #selector(menuOpenLauncher), keyEquivalent: "")
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
        let launcherOK = hotKeys.register(id: "launcher", spec: s.hotkeyLauncher)
        if !launcherOK { model.showToast("工具箱快捷键 \(s.hotkeyLauncher.display) 注册失败，可能已被占用") }

        // 工具专属热键只在启用时注册，停用即注销（释放热键）。
        if model.registry.isEnabled("clipboard") {
            if !hotKeys.register(id: "clipboard", spec: s.hotkeyClipboard) {
                model.showToast("剪贴板快捷键 \(s.hotkeyClipboard.display) 已被其他应用占用")
            }
        } else {
            hotKeys.unregister(id: "clipboard")
        }

        if model.registry.isEnabled("screenshots") {
            if !hotKeys.register(id: "capture", spec: s.hotkeyCapture) {
                model.showToast("截图快捷键 \(s.hotkeyCapture.display) 已被其他应用占用")
            }
        } else {
            hotKeys.unregister(id: "capture")
        }
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
        default:
            break
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.clipboardService.stop()
    }
}
