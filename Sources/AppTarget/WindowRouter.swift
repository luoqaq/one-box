import AppKit
import SwiftUI
import Combine
import ImageIO
import ToolRegistry
import ToolLauncherUI
import OneBoxUI
import ClipboardHistory
import ClipboardStore
import CaptureStore
import ScreenCapture
import Annotation
import ColorPicker

// MARK: - 窗口路由：管理工具箱面板、工作台窗口、设置与标注窗口

@MainActor
final class WindowRouter {
    let model: AppModel
    private var launcherPanel: NSPanel?
    private var clipboardWindow: NSWindow?
    private var screenshotsWindow: NSWindow?

    var onToggleToolEnabled: (String) -> Void = { _ in }

    init(model: AppModel) {
        self.model = model
    }

    func applyAppearance(_ appearance: NSAppearance?) {
        for window in [launcherPanel, clipboardWindow, screenshotsWindow].compactMap({ $0 }) {
            window.appearance = appearance
            window.contentView?.needsDisplay = true
        }
    }

    private func currentAppearance() -> NSAppearance? {
        switch model.settings.themeMode {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    // MARK: 工具箱面板

    func toggleLauncher() {
        if let panel = launcherPanel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            showLauncher()
        }
    }

    func hideLauncher() {
        launcherPanel?.orderOut(nil)
    }

    /// Dock / reopen 路径专用：只负责显示，不做 toggle。
    func presentLauncher() {
        showLauncher()
    }

    private func showLauncher() {
        let panel = launcherPanel ?? makeLauncherPanel()
        // 每次打开刷新 root，确保设置里改过的热键文案是最新的；也用于从设置同窗返回。
        panel.contentView = NSHostingView(rootView: makeLauncherView())
        presentLauncherPanel(panel)
    }

    /// 将设置/百宝袋内容呈现在同一块 600×540 面板上，避免另开工作台窗造成尺寸跳变。
    private func presentLauncherPanel(_ panel: NSPanel) {
        if !panel.isVisible {
            if let button = AppDelegate.statusItemButton {
                let frame = button.window?.convertToScreen(button.bounds.offsetBy(dx: 0, dy: button.bounds.height)) ?? .zero
                let x = frame.minX - 300 + frame.width / 2
                panel.setFrameOrigin(NSPoint(x: max(8, min(x, NSScreen.main!.frame.maxX - 608)),
                                             y: frame.minY + 8))
            } else {
                center(panel)
            }
        }
        // 先激活再 orderFront：Dock reopen 时若反过来，hidesOnDeactivate 会在激活落稳前把面板藏掉。
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makeLauncherPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 540),
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.title = "OneBox"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        // 无标题栏：靠面板背景拖动；固定尺寸，不做缩放。
        panel.isMovableByWindowBackground = true
        panel.appearance = currentAppearance()
        panel.contentView = NSHostingView(rootView: makeLauncherView())
        launcherPanel = panel
        return panel
    }

    private func makeLauncherView() -> LauncherView {
        LauncherView(
            registry: model.registry,
            hotkeyLabel: { [weak self] tool in
                self?.hotkeyDisplay(for: tool)
            },
            onOpen: { [weak self] dest in
                self?.hideLauncher()
                self?.open(dest)
            },
            onOpenConfig: { [weak self] dest in
                self?.hideLauncher()
                switch dest {
                case .clipboard:
                    self?.showClipboardWindow(initialSubView: .config)
                case .screenshots:
                    self?.showScreenshotsWindow(initialSubView: .config)
                default:
                    self?.open(dest)
                }
            },
            onQuickAction: { [weak self] dest in
                self?.hideLauncher()
                self?.open(dest)
            },
            onOpenSettings: { [weak self] target in
                // 同窗覆盖：不 hide，直接把面板内容换成设置。
                self?.showSettings(initialPanel: Self.settingsPanel(from: target))
            },
            onToggleEnabled: { [weak self] id in
                self?.onToggleToolEnabled(id)
            }
        )
    }

    private static func settingsPanel(from target: LauncherSettingsTarget) -> SettingsWindowView.Panel {
        switch target {
        case .plugins: return .plugins
        case .hotkeys: return .hotkeys
        case .general: return .general
        case .storage: return .storage
        }
    }

    /// 工具外侧展示用：优先读设置里的实际热键，否则退回描述里的默认文案。
    private func hotkeyDisplay(for tool: ToolDescriptor) -> String? {
        if let id = tool.hotkeyID {
            return model.settings.hotkey(for: id).display
        }
        guard let shortcut = tool.defaultShortcut, shortcut != "—" else { return nil }
        return shortcut
    }

    // MARK: 目标分发

    func open(_ destination: ToolDestination) {
        switch destination {
        case .clipboard:
            showClipboardWindow(initialSubView: .main)
        case .screenshots:
            showScreenshotsWindow(initialSubView: .main)
        case .capture:
            startSelectionCapture()
        case .colorPicker:
            startColorPick()
        case .settings:
            showSettings()
        }
    }

    // MARK: 剪贴板工作台

    func showClipboardWindow(initialSubView: ClipboardWorkbenchView.SubView) {
        let window = clipboardWindow ?? makeWorkbenchWindow()
        let shouldReset = window.contentView == nil
        if shouldReset || clipboardNeedsRebuild {
            window.contentView = NSHostingView(rootView:
                ClipboardWorkbenchView(
                    model: model,
                    onBack: { [weak self] in
                        window.orderOut(nil)
                        self?.showLauncher()
                    },
                    onOpenCapture: { [weak self] in
                        self?.startSelectionCapture()
                    },
                    initialSubView: initialSubView
                )
            )
        } else if initialSubView == .config, let hosting = window.contentView as? NSHostingView<ClipboardWorkbenchView> {
            hosting.rootView = ClipboardWorkbenchView(
                model: model,
                onBack: { [weak self] in
                    window.orderOut(nil)
                    self?.showLauncher()
                },
                onOpenCapture: { [weak self] in
                    self?.startSelectionCapture()
                },
                initialSubView: .config
            )
        }
        clipboardWindow = window
        show(window)
        model.reloadClipboardRecords()
    }

    private var clipboardNeedsRebuild = true

    // MARK: 截图工作台

    func showScreenshotsWindow(initialSubView: ScreenshotsWorkbenchView.SubView) {
        let window = screenshotsWindow ?? makeWorkbenchWindow()
        window.contentView = NSHostingView(rootView:
            ScreenshotsWorkbenchView(
                model: model,
                onBack: { [weak self] in
                    window.orderOut(nil)
                    self?.showLauncher()
                },
                onStartCapture: { [weak self] in
                    self?.startSelectionCapture()
                },
                onAnnotate: { [weak self] record in
                    self?.annotateCaptureRecord(record)
                },
                initialSubView: initialSubView
            )
        )
        screenshotsWindow = window
        show(window)
        model.reloadCaptures()
    }

    // MARK: 设置（与百宝袋同面板，失焦关闭）

    func showSettings(initialPanel: SettingsWindowView.Panel = .general) {
        let panel = launcherPanel ?? makeLauncherPanel()
        panel.contentView = NSHostingView(rootView:
            SettingsWindowView(model: model, initialPanel: initialPanel, onClose: { [weak self] in
                // 返回百宝袋列表，面板保持打开；点窗外失焦则由 hidesOnDeactivate 整面板收起。
                self?.showLauncher()
            })
        )
        presentLauncherPanel(panel)
    }

    /// 从最近截图记录进入贴图标注。
    func annotateCaptureRecord(_ record: CaptureRecord) {
        Task { @MainActor in
            let url = await model.captureStore.fileURL(of: record)
            guard let data = try? Data(contentsOf: url),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                model.showToast("读取截图文件失败")
                return
            }
            let captured = CapturedImage(
                image: image,
                pngData: data,
                pointSize: CGSize(width: image.width, height: image.height),
                pixelSize: CGSize(width: image.width, height: image.height)
            )
            hideLauncher()
            screenshotsWindow?.orderOut(nil)
            let outcome = await model.captureService.requestAnnotate(captured: captured)
            if case .selected(let result) = outcome {
                handleConfirmedCapture(result)
            }
        }
    }

    // MARK: 屏幕取色

    func startColorPick() {
        guard model.registry.isEnabled("color-picker") else {
            model.showToast("取色工具未启用")
            return
        }
        hideLauncher()
        Task { @MainActor in
            if !model.captureService.authorizationStatus() {
                guard await model.captureService.requestAccess() else {
                    model.showToast("需要屏幕录制权限：系统设置 > 隐私与安全性 > 屏幕录制")
                    showSettings()
                    return
                }
                model.showToast("屏幕录制权限已开启，若仍无法取色请重启 OneBox")
            }
            let outcome = await model.colorPickService.requestPick()
            switch outcome {
            case .canceled:
                break
            case let .picked(color, format):
                let text = color.string(format: format)
                writeTextToPasteboard(text)
                model.registry.registerUse("color-picker")
                model.showToast("已复制 \(text)")
            }
        }
    }

    // MARK: 区域截图流程

    func startSelectionCapture() {
        guard model.registry.isEnabled("screenshots") else {
            model.showToast("截图工具未启用")
            return
        }
        hideLauncher()
        screenshotsWindow?.orderOut(nil)
        Task { @MainActor in
            do {
                // 未授权时先触发系统原生授权弹窗（点「打开系统设置」可直达且 OneBox 已在列表中）。
                // 用户拒绝或未完成授权时，落到配置页横幅引导；授权后需重启应用生效。
                if !model.captureService.authorizationStatus() {
                    guard await model.captureService.requestAccess() else {
                        model.showToast("需要屏幕录制权限：系统设置 > 隐私与安全性 > 屏幕录制")
                        showScreenshotsWindow(initialSubView: .config)
                        return
                    }
                    model.showToast("屏幕录制权限已开启，若仍无法截图请重启 OneBox")
                }
                let outcome = try await model.captureService.requestSelectionCapture()
                switch outcome {
                case .canceled:
                    break
                case let .selected(captured):
                    handleConfirmedCapture(captured)
                }
            } catch let error as ScreenCaptureError {
                if case .notAuthorized = error {
                    model.showToast("需要屏幕录制权限：系统设置 > 隐私与安全性 > 屏幕录制")
                    showScreenshotsWindow(initialSubView: .config)
                } else {
                    model.showToast("截图失败：\(error.localizedDescription)")
                }
            } catch {
                model.showToast("截图失败：\(error.localizedDescription)")
            }
        }
    }

    /// 贴图标注确认：复制到剪贴板，并按设置写入最近截图。
    private func handleConfirmedCapture(_ captured: CapturedImage) {
        writeImageToPasteboard(pngData: captured.pngData, pointSize: captured.pointSize)
        model.showToast("已复制到剪贴板")
        model.registry.registerUse("screenshots")
        if model.settings.captureKeepRecords {
            Task { @MainActor in
                _ = try? await model.captureStore.insert(png: captured.pngData)
                _ = try? await model.captureStore.enforceRetention(
                    limit: model.settings.captureMaxRecords, days: 30)
                model.reloadCaptures()
            }
        }
    }

    private func writeTextToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        pb.setString("1", forType: NSPasteboard.PasteboardType(OneBoxPasteboardMarker.type))
    }

    private func writeImageToPasteboard(_ image: CGImage, pointSize: CGSize? = nil) {
        let size = pointSize ?? CGSize(width: image.width, height: image.height)
        let nsImage = NSImage(cgImage: image, size: size)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([nsImage])
    }

    /// 按 pointSize 写入剪贴板，保留 Retina 像素密度（避免被当成 1x 大图或糊图）。
    private func writeImageToPasteboard(pngData: Data, pointSize: CGSize) {
        guard let rep = NSBitmapImageRep(data: pngData) else { return }
        rep.size = pointSize
        let image = NSImage(size: pointSize)
        image.addRepresentation(rep)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    private func savePNG(_ data: Data) {
        let dir = URL(fileURLWithPath: model.settings.captureSaveDirectory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let df = DateFormatter()
            df.dateFormat = "yyyyMMdd-HHmmss"
            let url = dir.appendingPathComponent("OneBox-\(df.string(from: Date())).png")
            try data.write(to: url, options: .atomic)
            model.showToast("已保存 PNG 文件")
        } catch {
            model.showToast("保存失败：\(error.localizedDescription)")
        }
    }

    // MARK: 窗口工厂

    private func makeWorkbenchWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        // 普通窗口层级：否则会压住「系统设置」等标准窗口，授权时无法点到前面。
        window.level = .normal
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
        window.appearance = currentAppearance()
        window.center()
        return window
    }

    private func show(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func center(_ window: NSWindow) {
        if let screen = NSScreen.main {
            let f = window.frame
            let origin = NSPoint(
                x: screen.visibleFrame.midX - f.width / 2,
                y: screen.visibleFrame.midY - f.height / 2
            )
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }
    }
}
