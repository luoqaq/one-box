import AppKit
import SwiftUI
import Combine
import ToolRegistry
import ToolLauncherUI
import OneBoxUI
import ClipboardHistory
import ClipboardStore
import CaptureStore
import ScreenCapture
import Annotation

// MARK: - 窗口路由：管理工具箱面板、工作台窗口、设置与标注窗口

@MainActor
final class WindowRouter {
    let model: AppModel
    private var launcherPanel: NSPanel?
    private var clipboardWindow: NSWindow?
    private var screenshotsWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var studioWindow: NSWindow?

    var onToggleToolEnabled: (String) -> Void = { _ in }

    init(model: AppModel) {
        self.model = model
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

    private func showLauncher() {
        let panel = launcherPanel ?? makeLauncherPanel()
        if let button = AppDelegate.statusItemButton {
            let frame = button.window?.convertToScreen(button.bounds.offsetBy(dx: 0, dy: button.bounds.height)) ?? .zero
            let x = frame.minX - 300 + frame.width / 2
            panel.setFrameOrigin(NSPoint(x: max(8, min(x, NSScreen.main!.frame.maxX - 608)),
                                         y: frame.minY + 8))
        } else {
            center(panel)
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        panel.contentView = NSHostingView(rootView:
            LauncherView(
                registry: model.registry,
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
                onOpenSettings: { [weak self] in
                    self?.hideLauncher()
                    self?.showSettings()
                },
                onToggleEnabled: { [weak self] id in
                    self?.onToggleToolEnabled(id)
                }
            )
        )
        launcherPanel = panel
        return panel
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
                    self?.openStudioForRecord(record)
                },
                initialSubView: initialSubView
            )
        )
        screenshotsWindow = window
        show(window)
        model.reloadCaptures()
    }

    // MARK: 设置

    func showSettings() {
        let window = settingsWindow ?? makeWorkbenchWindow()
        window.contentView = NSHostingView(rootView:
            SettingsWindowView(model: model, onClose: {
                window.orderOut(nil)
            })
        )
        settingsWindow = window
        show(window)
    }

    // MARK: 标注

    func showStudio(baseImage: CGImage, title: String, sourceRecord: CaptureRecord?) {
        let window = studioWindow ?? makeWorkbenchWindow()
        window.setContentSize(NSSize(width: 1080, height: 700))
        window.contentView = NSHostingView(rootView:
            AnnotationStudioView(
                baseImage: baseImage,
                imageTitle: title,
                onBack: { [weak self] in
                    window.orderOut(nil)
                    self?.showScreenshotsWindow(initialSubView: .main)
                },
                onRetake: { [weak self] in
                    window.orderOut(nil)
                    self?.startSelectionCapture()
                },
                onExport: { [weak self] png, action in
                    self?.handleStudioExport(png: png, action: action)
                }
            )
        )
        studioWindow = window
        center(window)
        show(window)
    }

    /// 从最近截图记录打开标注。
    func openStudioForRecord(_ record: CaptureRecord) {
        Task { @MainActor in
            let url = await model.captureStore.fileURL(of: record)
            if let data = try? Data(contentsOf: url),
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                showStudio(baseImage: image, title: record.file, sourceRecord: record)
            } else {
                model.showToast("读取截图文件失败")
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
        let defaultAction: SelectionAction
        switch model.settings.captureDefaultAction {
        case .annotate: defaultAction = .annotate
        case .copy: defaultAction = .copy
        case .save: defaultAction = .save
        }
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
                let outcome = try await model.captureService.requestSelectionCapture(defaultAction: defaultAction)
                switch outcome {
                case .canceled:
                    break
                case let .selected(captured, action):
                    handleCaptured(captured, action: action)
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

    private func handleCaptured(_ captured: CapturedImage, action: SelectionAction) {
        if model.settings.captureKeepRecords {
            Task { @MainActor in
                _ = try? await model.captureStore.insert(png: captured.pngData)
                _ = try? await model.captureStore.enforceRetention(
                    limit: model.settings.captureMaxRecords, days: 30)
                model.reloadCaptures()
            }
        }
        switch action {
        case .annotate:
            showStudio(baseImage: captured.image, title: "区域截图", sourceRecord: nil)
        case .copy:
            writeImageToPasteboard(captured.image)
            model.showToast("已复制选区截图")
        case .save:
            savePNG(captured.pngData)
        }
    }

    private func handleStudioExport(png: Data, action: AnnotationStudioView.ExportAction) {
        switch action {
        case .copy:
            writeImageToPasteboard(pngData: png)
            model.showToast("已复制到剪贴板")
        case .save:
            savePNG(png)
        }
        // 标注结果也计入最近截图
        if model.settings.captureKeepRecords {
            Task { @MainActor in
                _ = try? await model.captureStore.insert(png: png)
                model.reloadCaptures()
            }
        }
    }

    private func writeImageToPasteboard(_ image: CGImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))])
    }

    private func writeImageToPasteboard(pngData: Data) {
        guard let image = NSImage(data: pngData) else { return }
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
        window.level = .floating
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
        window.center()
        return window
    }

    private func show(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
