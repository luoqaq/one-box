import AppKit

/// 选区遮罩交互的内部结果。
enum OverlayCompletion {
    case canceled
    case confirmed(CGRect, action: SelectionAction)
}

/// 全屏选区遮罩控制器。
///
/// 每个 NSScreen 建一个非激活、无边框、透明、最高层级（.screenSaver）的窗口；
/// 拖拽画白色 1px 边框 + 蓝色 1px 外圈 + 选区外半透明遮罩 + 四角白色圆点手柄，
/// 选区上方黑底 HUD 显示「W × H」，顶部居中提示胶囊，选区下方深色 dock。
/// Enter 确认（defaultAction）、Esc 取消，均通过本地事件监听处理。
@MainActor
final class SelectionOverlayController: NSObject {

    /// 最小有效选区边长，小于此值视为取消/无效。
    nonisolated static let minimumSelectionSize: CGFloat = 24

    /// 正在运行的控制器；遮罩窗口与事件链都不强持有控制器，需要显式保活。
    private static var current: SelectionOverlayController?

    private let defaultAction: SelectionAction
    private var continuation: CheckedContinuation<OverlayCompletion, Never>?
    private var windows: [OverlayWindow] = []
    private var keyMonitor: Any?
    private var finished = false

    /// 拖拽起点（全局 AppKit 坐标）。
    private var anchor: CGPoint?
    /// 是否处于拖拽过程中（拖拽中显示 HUD、隐藏 dock）。
    private var dragActive = false
    /// 当前选区（全局 AppKit 坐标）；nil 表示尚无选区。
    private var selectionRect: CGRect?
    /// 选区下方操作 dock。
    private var dock: SelectionDock?

    // MARK: - 生命周期

    init(defaultAction: SelectionAction) {
        self.defaultAction = defaultAction
        super.init()
    }

    /// 拉起全屏遮罩并等待交互结果。必须在主线程外 await，内部自动切换到主线程。
    static func run(defaultAction: SelectionAction) async -> OverlayCompletion {
        let controller = SelectionOverlayController(defaultAction: defaultAction)
        current = controller
        return await withCheckedContinuation { continuation in
            MainActor.assumeIsolated {
                controller.start(continuation: continuation)
            }
        }
    }

    private func start(continuation: CheckedContinuation<OverlayCompletion, Never>) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            Self.current = nil
            continuation.resume(returning: .canceled)
            return
        }
        for screen in screens {
            let window = OverlayWindow(contentRect: screen.frame)
            window.contentView = SelectionOverlayView(controller: self, screenFrame: screen.frame)
            window.orderFrontRegardless()
            windows.append(window)
        }
        // 遮罩窗口需要接收键盘事件（Enter/Esc），必须激活本 App 并让窗口成为 key
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
        dock = SelectionDock(defaultAction: defaultAction, target: self)
        NSCursor.crosshair.push()
        self.continuation = continuation
    }

    private func finish(_ completion: OverlayCompletion) {
        guard !finished else { return }
        finished = true
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        NSCursor.pop()
        dock?.removeFromSuperview()
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows = []
        Self.current = nil
        continuation?.resume(returning: completion)
        continuation = nil
    }

    // MARK: - 键盘

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 53: // Esc
            finish(.canceled)
            return nil
        case 36, 76: // Return / 小键盘 Enter
            if let selection = selectionRect {
                finish(.confirmed(selection, action: defaultAction))
                return nil
            }
        default:
            break
        }
        return event
    }

    // MARK: - dock 按钮

    /// dock 按钮动作分发（NSButton.tag 对应 SelectionDock.ActionTag）。
    @objc func dockButtonTapped(_ sender: NSButton) {
        switch SelectionDock.ActionTag(rawValue: sender.tag) {
        case .annotate:
            confirm(.annotate)
        case .copy:
            confirm(.copy)
        case .save:
            confirm(.save)
        case .cancel:
            finish(.canceled)
        case nil:
            break
        }
    }

    private func confirm(_ action: SelectionAction) {
        guard let selection = selectionRect else { return }
        finish(.confirmed(selection, action: action))
    }

    // MARK: - 鼠标拖拽

    fileprivate func beginDrag(at globalPoint: CGPoint) {
        anchor = globalPoint
        dragActive = true
        selectionRect = nil
        dock?.isHidden = true
        refresh()
    }

    fileprivate func updateDrag(to globalPoint: CGPoint) {
        guard let anchor else { return }
        selectionRect = Self.rect(from: anchor, to: globalPoint)
        refresh()
    }

    fileprivate func endDrag(at globalPoint: CGPoint) {
        guard let anchor else { return }
        let rect = Self.rect(from: anchor, to: globalPoint)
        self.anchor = nil
        dragActive = false
        // 小于最小选区视为误触：清空选区，保持遮罩等待重新框选
        if rect.width >= Self.minimumSelectionSize, rect.height >= Self.minimumSelectionSize {
            selectionRect = rect
            layoutDock()
        } else {
            selectionRect = nil
        }
        refresh()
    }

    /// 两点归一化为全局矩形（任意拖拽方向都得到正尺寸矩形）。
    private static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }

    private var hasConfirmedSelection: Bool {
        selectionRect != nil && !dragActive
    }

    private func refresh() {
        for window in windows {
            window.contentView?.needsDisplay = true
        }
    }

    // MARK: - dock 布局

    /// dock 默认放在选区下方 8pt、水平居中；下方放不下时改到选区上方。
    private func layoutDock() {
        guard let selection = selectionRect, let dock else { return }
        let dockSize = dock.fittingSize
        let dockWidth = max(dockSize.width, 1)
        let dockHeight = max(dockSize.height, 1)

        // 用包含选区中心的屏幕做边界约束
        let hostScreen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: selection.midX, y: selection.midY)) }

        var origin = CGPoint(
            x: selection.midX - dockWidth / 2,
            y: selection.minY - 8 - dockHeight
        )
        // 下方放不下 → 放到选区上方
        if let screen = hostScreen, origin.y < screen.frame.minY {
            origin.y = selection.maxY + 8
        }
        // 水平方向夹在屏幕内
        if let screen = hostScreen {
            origin.x = max(screen.frame.minX + 4, min(origin.x, screen.frame.maxX - dockWidth - 4))
        }

        // dock 归属包含其中心的遮罩窗口（跨屏选区时可能不在选区所在屏）
        let dockCenter = CGPoint(x: origin.x + dockWidth / 2, y: origin.y + dockHeight / 2)
        let hostWindow = windows.first { $0.frame.contains(dockCenter) } ?? windows.first
        guard let hostView = hostWindow?.contentView as? SelectionOverlayView, let hostFrame = hostWindow?.frame else { return }

        if dock.superview !== hostView {
            dock.removeFromSuperview()
            hostView.addSubview(dock)
        }
        dock.frame = CGRect(
            x: origin.x - hostFrame.minX,
            y: origin.y - hostFrame.minY,
            width: dockWidth,
            height: dockHeight
        )
        dock.isHidden = false
    }

    // MARK: - 绘制（由各屏 SelectionOverlayView 驱动）

    /// 在指定屏幕的遮罩视图上绘制整个交互层。坐标先换算到该屏本地坐标系。
    fileprivate func drawOverlay(in view: NSView, screenFrame: CGRect) {
        let bounds = view.bounds
        let localSelection = selectionRect.map {
            CGRect(
                x: $0.minX - screenFrame.minX,
                y: $0.minY - screenFrame.minY,
                width: $0.width,
                height: $0.height
            )
        }

        // 1) 选区外半透明遮罩 rgba(10,14,22,0.48)，选区部分镂空
        NSColor(srgbRed: 10 / 255, green: 14 / 255, blue: 22 / 255, alpha: 0.48).setFill()
        if let local = localSelection {
            let hole = local.intersection(bounds)
            if !hole.isNull, hole.width > 0, hole.height > 0 {
                let path = NSBezierPath()
                path.appendRect(bounds)
                path.appendRect(hole)
                path.windingRule = .evenOdd
                path.fill()
            } else {
                bounds.fill()
            }
        } else {
            bounds.fill()
        }

        // 2) 顶部居中提示胶囊（确认选区后隐藏，由 dock 接管提示）
        if !hasConfirmedSelection {
            drawHintPill(in: bounds)
        }

        guard let sel = localSelection else { return }

        // 3) 蓝色 1px 外圈（选区外侧）
        let ring = NSColor(srgbRed: 0, green: 122 / 255, blue: 1, alpha: 0.85)
        ring.setStroke()
        let ringPath = NSBezierPath(rect: sel.insetBy(dx: -1.5, dy: -1.5))
        ringPath.lineWidth = 1
        ringPath.stroke()

        // 4) 白色 1px 边框（选区内侧）
        NSColor.white.withAlphaComponent(0.92).setStroke()
        let borderPath = NSBezierPath(rect: sel.insetBy(dx: 0.5, dy: 0.5))
        borderPath.lineWidth = 1
        borderPath.stroke()

        // 5) 四角白色圆点手柄
        drawHandles(around: sel)

        // 6) 拖拽中显示「W × H」尺寸 HUD
        if dragActive {
            drawSizeHUD(for: sel, in: bounds)
        }
    }

    /// 四角 8pt 白色圆点，带 1px 黑描边。
    private func drawHandles(around sel: CGRect) {
        let centers = [
            CGPoint(x: sel.minX, y: sel.minY),
            CGPoint(x: sel.maxX, y: sel.minY),
            CGPoint(x: sel.minX, y: sel.maxY),
            CGPoint(x: sel.maxX, y: sel.maxY),
        ]
        for center in centers {
            let dot = NSBezierPath(ovalIn: CGRect(
                x: center.x - 4, y: center.y - 4, width: 8, height: 8
            ))
            NSColor.white.setFill()
            dot.fill()
            NSColor.black.withAlphaComponent(0.35).setStroke()
            let outline = NSBezierPath(ovalIn: CGRect(
                x: center.x - 4, y: center.y - 4, width: 8, height: 8
            ))
            outline.lineWidth = 1
            outline.stroke()
        }
    }

    /// 黑底 HUD：「W × H」等宽字体，显示在选区上方左缘；越过屏幕顶部时改到选区内。
    private func drawSizeHUD(for sel: CGRect, in bounds: CGRect) {
        let text = "\(Int(sel.width.rounded())) × \(Int(sel.height.rounded()))"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.94),
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let hudWidth = textSize.width + 16
        let hudHeight = 22

        var origin = CGPoint(x: sel.minX, y: sel.maxY + 6)
        if origin.y + CGFloat(hudHeight) > bounds.maxY {
            origin.y = sel.maxY - 6 - CGFloat(hudHeight)
        }
        let rect = CGRect(x: origin.x, y: origin.y, width: hudWidth, height: CGFloat(hudHeight))
        drawRoundedBackground(
            rect,
            radius: 6,
            fill: NSColor(srgbRed: 18 / 255, green: 20 / 255, blue: 26 / 255, alpha: 0.82),
            border: NSColor.white.withAlphaComponent(0.14)
        )
        (text as NSString).draw(
            at: CGPoint(x: rect.minX + 8, y: rect.midY - textSize.height / 2),
            withAttributes: attributes
        )
    }

    /// 顶部居中提示胶囊：拖拽框选区域 ⏎ 动作 ⎋ 取消。
    private func drawHintPill(in bounds: CGRect) {
        struct Segment {
            let text: String
            let isKey: Bool
        }
        let segments: [Segment] = [
            Segment(text: "拖拽框选区域", isKey: false),
            Segment(text: "⏎", isKey: true),
            Segment(text: defaultAction.title, isKey: false),
            Segment(text: "⎋", isKey: true),
            Segment(text: "取消", isKey: false),
        ]

        let textFont = NSFont.systemFont(ofSize: 12)
        let keyFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let segmentGap: CGFloat = 8
        let chipHorizontalPadding: CGFloat = 5
        let pillHeight: CGFloat = 30
        let chipHeight: CGFloat = 18
        let pillHorizontalPadding: CGFloat = 12

        // 测量总宽度
        var totalWidth = pillHorizontalPadding * 2
        var segmentWidths: [CGFloat] = []
        for (index, segment) in segments.enumerated() {
            let font = segment.isKey ? keyFont : textFont
            let width = (segment.text as NSString).size(withAttributes: [.font: font]).width
            let displayWidth = segment.isKey ? width + chipHorizontalPadding * 2 : width
            segmentWidths.append(displayWidth)
            totalWidth += displayWidth
            if index < segments.count - 1 {
                totalWidth += segmentGap
            }
        }

        let pillRect = CGRect(
            x: bounds.midX - totalWidth / 2,
            y: bounds.maxY - 18 - pillHeight,
            width: totalWidth,
            height: pillHeight
        )
        drawRoundedBackground(
            pillRect,
            radius: pillHeight / 2,
            fill: NSColor(srgbRed: 18 / 255, green: 20 / 255, blue: 26 / 255, alpha: 0.78),
            border: NSColor.white.withAlphaComponent(0.14)
        )

        var x = pillRect.minX + pillHorizontalPadding
        for (index, segment) in segments.enumerated() {
            let font = segment.isKey ? keyFont : textFont
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(segment.isKey ? 1.0 : 0.88),
            ]
            let textSize = (segment.text as NSString).size(withAttributes: attributes)
            if segment.isKey {
                let chipRect = CGRect(
                    x: x,
                    y: pillRect.midY - chipHeight / 2,
                    width: segmentWidths[index],
                    height: chipHeight
                )
                drawRoundedBackground(
                    chipRect,
                    radius: 4,
                    fill: NSColor.white.withAlphaComponent(0.12),
                    border: NSColor.white.withAlphaComponent(0.16)
                )
                (segment.text as NSString).draw(
                    at: CGPoint(x: chipRect.minX + (chipRect.width - textSize.width) / 2,
                                y: chipRect.midY - textSize.height / 2),
                    withAttributes: attributes
                )
            } else {
                (segment.text as NSString).draw(
                    at: CGPoint(x: x, y: pillRect.midY - textSize.height / 2),
                    withAttributes: attributes
                )
            }
            x += segmentWidths[index] + segmentGap
        }
    }

    /// 深色圆角背景：填充 + 0.5px 描边。
    private func drawRoundedBackground(_ rect: CGRect, radius: CGFloat, fill: NSColor, border: NSColor) {
        let background = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        fill.setFill()
        background.fill()
        border.setStroke()
        let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: radius, yRadius: radius)
        outline.lineWidth = 0.5
        outline.stroke()
    }
}

/// 遮罩窗口：非激活、无边框、透明、最高层级，跨 Space 可见。
final class OverlayWindow: NSWindow {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        isReleasedWhenClosed = false
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
    }

    /// 无边框窗口默认不能成为 key，导致键盘事件收不到；这里放行。
    override var canBecomeKey: Bool { true }
}

/// 单个屏幕上的遮罩视图：接收鼠标事件并把绘制委托给控制器（全局坐标系）。
final class SelectionOverlayView: NSView {

    private let controller: SelectionOverlayController
    private let screenFrame: CGRect

    init(controller: SelectionOverlayController, screenFrame: CGRect) {
        self.controller = controller
        self.screenFrame = screenFrame
        super.init(frame: screenFrame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SelectionOverlayView 只在代码里创建，不支持 coder 初始化")
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        controller.drawOverlay(in: self, screenFrame: screenFrame)
    }

    override func mouseDown(with event: NSEvent) {
        controller.beginDrag(at: globalLocation(of: event))
    }

    override func mouseDragged(with event: NSEvent) {
        controller.updateDrag(to: globalLocation(of: event))
    }

    override func mouseUp(with event: NSEvent) {
        controller.endDrag(at: globalLocation(of: event))
    }

    /// 事件坐标（窗口系）→ 全局 AppKit 坐标。
    private func globalLocation(of event: NSEvent) -> CGPoint {
        guard let window else { return event.locationInWindow }
        return window.convertToScreen(CGRect(origin: event.locationInWindow, size: .zero)).origin
    }
}

/// 选区下方的操作 dock：标注 / 复制 / 保存 ｜ 取消，主按钮（defaultAction）蓝色高亮。
@MainActor
final class SelectionDock: NSStackView {

    /// dock 按钮与 tag 的映射（NSControl target 不持有对象，用 tag 分发）。
    enum ActionTag: Int {
        case annotate = 1
        case copy = 2
        case save = 3
        case cancel = 4
    }

    init(defaultAction: SelectionAction, target: SelectionOverlayController) {
        super.init(frame: .zero)

        orientation = .horizontal
        alignment = .centerY
        spacing = 4
        edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)

        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 22 / 255, green: 24 / 255, blue: 30 / 255, alpha: 0.88).cgColor
        layer?.cornerRadius = 10
        layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        layer?.borderWidth = 0.5
        layer?.masksToBounds = true

        let accent = NSColor(srgbRed: 0, green: 122 / 255, blue: 1, alpha: 1)
        for (action, tag) in [
            (SelectionAction.annotate, ActionTag.annotate),
            (.copy, ActionTag.copy),
            (.save, ActionTag.save),
        ] {
            let button = Self.makeButton(
                title: action.title,
                tag: tag.rawValue,
                primary: action == defaultAction,
                accent: accent,
                target: target
            )
            addArrangedSubview(button)
        }
        addArrangedSubview(Self.makeSeparator())
        addArrangedSubview(Self.makeButton(
            title: "取消",
            tag: ActionTag.cancel.rawValue,
            primary: false,
            accent: accent,
            target: target
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SelectionDock 只在代码里创建，不支持 coder 初始化")
    }

    private static func makeButton(
        title: String,
        tag: Int,
        primary: Bool,
        accent: NSColor,
        target: SelectionOverlayController
    ) -> NSButton {
        let button = NSButton(
            title: title,
            target: target,
            action: #selector(SelectionOverlayController.dockButtonTapped(_:))
        )
        button.tag = tag
        button.isBordered = false
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.contentTintColor = primary ? .white : NSColor.white.withAlphaComponent(0.86)
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.layer?.masksToBounds = true
        button.layer?.backgroundColor = primary ? accent.cgColor : NSColor.clear.cgColor
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    private static func makeSeparator() -> NSView {
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return separator
    }
}
