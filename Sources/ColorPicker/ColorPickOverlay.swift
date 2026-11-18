import AppKit
import CoreGraphics

/// 多屏取色遮罩：跟随光标的放大镜 HUD，单击确认，Esc 取消，1/2/3 切换格式。
@MainActor
final class ColorPickOverlayController: NSObject {

    private static var current: ColorPickOverlayController?

    private var continuation: CheckedContinuation<ColorPickOutcome, Never>?
    private var windows: [PickOverlayWindow] = []
    private var hud: LoupeHUD?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var sampleTimer: DispatchSourceTimer?
    private var finished = false
    private var format: ColorFormat = .hex
    private var latestColor: ColorValue = .black
    private var sampling = false

    static func run() async -> ColorPickOutcome {
        let controller = ColorPickOverlayController()
        current = controller
        return await withCheckedContinuation { continuation in
            MainActor.assumeIsolated {
                controller.start(continuation: continuation)
            }
        }
    }

    private func start(continuation: CheckedContinuation<ColorPickOutcome, Never>) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            Self.current = nil
            continuation.resume(returning: .canceled)
            return
        }
        self.continuation = continuation

        for screen in screens {
            let window = PickOverlayWindow(contentRect: screen.frame)
            let view = PickOverlayView(controller: self, screenFrame: screen.frame)
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
        }

        let hud = LoupeHUD()
        self.hud = hud
        if let first = windows.first {
            first.contentView?.addSubview(hud)
        }

        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.push()

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .mouseMoved, .leftMouseUp]) { [weak self] event in
            self?.handleMouse(event)
            return nil // 吞掉，避免点穿
        }
        // 全局鼠标：跟踪移到其他 app 窗口上的移动与点击
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
            self?.handleMouse(event)
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKey(event) ?? event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            _ = self?.handleKey(event)
        }

        startSamplingLoop()
        refreshSample(at: NSEvent.mouseLocation)
    }

    private func startSamplingLoop() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            guard let self, !self.finished else { return }
            self.refreshSample(at: NSEvent.mouseLocation)
        }
        timer.resume()
        sampleTimer = timer
    }

    private func refreshSample(at point: CGPoint) {
        guard !sampling else { return }
        sampling = true
        Task { @MainActor in
            defer { self.sampling = false }
            do {
                let sample = try await ColorSampler.sample(at: point)
                guard !self.finished else { return }
                self.latestColor = sample.color
                self.hud?.update(
                    loupe: sample.loupeImage,
                    color: sample.color,
                    format: self.format,
                    cursor: point
                )
                self.repositionHUD(cursor: point)
            } catch {
                // 采样失败时保持上一帧，不打断会话
            }
        }
    }

    private func repositionHUD(cursor: CGPoint) {
        guard let hud else { return }
        // 找到光标所在屏的窗口，把 HUD 挂到该窗
        guard let host = windows.first(where: { $0.frame.contains(cursor) }) ?? windows.first,
              let content = host.contentView else { return }
        if hud.superview !== content {
            hud.removeFromSuperview()
            content.addSubview(hud)
        }
        // mouseLocation 是屏幕全局坐标；content.convert(_:from:nil) 却按窗口坐标解释，
        // 大屏 / 非原点屏上会把 HUD 甩出很远。
        let local = ColorPickLayout.contentPoint(screenPoint: cursor, windowFrame: host.frame)
        let size = hud.bounds.size
        var origin = CGPoint(x: local.x + 18, y: local.y - size.height - 18)
        let bounds = content.bounds
        if origin.x + size.width > bounds.maxX { origin.x = local.x - size.width - 18 }
        if origin.y < bounds.minY { origin.y = local.y + 18 }
        if origin.x < bounds.minX { origin.x = bounds.minX + 8 }
        if origin.y + size.height > bounds.maxY { origin.y = bounds.maxY - size.height - 8 }
        hud.setFrameOrigin(origin)
    }

    private func handleMouse(_ event: NSEvent) {
        let point = NSEvent.mouseLocation
        if event.type == .mouseMoved {
            refreshSample(at: point)
            return
        }
        if event.type == .leftMouseDown {
            confirmPick()
        }
    }

    fileprivate func noteMouseMoved() {
        refreshSample(at: NSEvent.mouseLocation)
    }

    fileprivate func confirmPick() {
        finish(.picked(latestColor, format: format))
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 53: // Esc
            finish(.canceled)
            return nil
        case 18: // 1
            format = .hex
            hud?.updateFormat(format)
            return nil
        case 19: // 2
            format = .rgb
            hud?.updateFormat(format)
            return nil
        case 20: // 3
            format = .oklch
            hud?.updateFormat(format)
            return nil
        default:
            return event
        }
    }

    private func finish(_ outcome: ColorPickOutcome) {
        guard !finished else { return }
        finished = true
        sampleTimer?.cancel()
        sampleTimer = nil
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        localMouseMonitor = nil
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        globalMouseMonitor = nil
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        localKeyMonitor = nil
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        globalKeyMonitor = nil
        NSCursor.pop()
        hud?.removeFromSuperview()
        hud = nil
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows = []
        Self.current = nil
        continuation?.resume(returning: outcome)
        continuation = nil
    }
}

// MARK: - Window / View

private final class PickOverlayWindow: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = false
        hasShadow = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
}

private final class PickOverlayView: NSView {
    weak var controller: ColorPickOverlayController?
    let screenFrame: CGRect
    private var tracking: NSTrackingArea?

    init(controller: ColorPickOverlayController, screenFrame: CGRect) {
        self.controller = controller
        self.screenFrame = screenFrame
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.001).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        controller?.noteMouseMoved()
    }

    override func mouseDown(with event: NSEvent) {
        controller?.confirmPick()
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Loupe HUD

private final class LoupeHUD: NSView {
    private let loupeView = NSImageView()
    private let swatch = NSView()
    private let valueLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "1 HEX · 2 RGB · 3 OKLCH · 单击复制 · Esc 取消")
    private var format: ColorFormat = .hex
    private var color: ColorValue = .black

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 196, height: 168))
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 0.92).cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor

        loupeView.imageScaling = .scaleAxesIndependently
        loupeView.wantsLayer = true
        loupeView.layer?.magnificationFilter = .nearest
        loupeView.layer?.cornerRadius = 8
        loupeView.layer?.masksToBounds = true
        addSubview(loupeView)

        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = 6
        swatch.layer?.borderWidth = 0.5
        swatch.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        addSubview(swatch)

        valueLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        valueLabel.textColor = .white
        valueLabel.lineBreakMode = .byTruncatingTail
        addSubview(valueLabel)

        hintLabel.font = .systemFont(ofSize: 10)
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.55)
        hintLabel.maximumNumberOfLines = 2
        addSubview(hintLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let inset: CGFloat = 10
        loupeView.frame = NSRect(x: inset, y: bounds.height - inset - 96, width: 96, height: 96)
        swatch.frame = NSRect(x: inset + 108, y: bounds.height - inset - 36, width: 68, height: 36)
        valueLabel.frame = NSRect(x: inset, y: 34, width: bounds.width - inset * 2, height: 18)
        hintLabel.frame = NSRect(x: inset, y: 8, width: bounds.width - inset * 2, height: 28)
    }

    func update(loupe: CGImage, color: ColorValue, format: ColorFormat, cursor: CGPoint) {
        self.color = color
        self.format = format
        let rep = NSBitmapImageRep(cgImage: loupe)
        let image = NSImage(size: NSSize(width: loupe.width, height: loupe.height))
        image.addRepresentation(rep)
        loupeView.image = image
        swatch.layer?.backgroundColor = NSColor(
            srgbRed: color.r, green: color.g, blue: color.b, alpha: 1
        ).cgColor
        valueLabel.stringValue = color.string(format: format)
        needsLayout = true
    }

    func updateFormat(_ format: ColorFormat) {
        self.format = format
        valueLabel.stringValue = color.string(format: format)
    }
}
