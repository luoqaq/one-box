import AppKit
import Annotation

/// 选区 / 贴图标注遮罩的内部结果。
enum OverlayCompletion {
    case canceled
    case confirmed(CapturedImage)
}

/// 全屏选区 + 贴图标注控制器（微信式：框选后原地标注，右上工具 / 右下确认）。
@MainActor
final class SelectionOverlayController: NSObject, NSTextFieldDelegate {

    nonisolated static let minimumSelectionSize: CGFloat = 24

    private static var current: SelectionOverlayController?

    private enum Phase {
        case selecting
        case annotating
    }

    private enum AnnotateTool: Int, CaseIterable {
        case text = 1
        case rectangle
        case line
        case arrow
        case mosaic

        var title: String {
            switch self {
            case .text: return "文字"
            case .rectangle: return "方框"
            case .line: return "直线"
            case .arrow: return "箭头"
            case .mosaic: return "打码"
            }
        }
    }

    /// 笔触/马赛克粗细档位（视图 point；马赛克再换算成像素块）。
    enum StrokePreset: Int, CaseIterable {
        case fine = 1
        case medium
        case thick

        var lineWidth: CGFloat {
            switch self {
            case .fine: return 2.5
            case .medium: return 4
            case .thick: return 6.5
            }
        }

        /// 马赛克块边长（视图 point），乘 density 后写入 annotation.strokeWidth。
        var mosaicBlockPoints: CGFloat {
            switch self {
            case .fine: return 6
            case .medium: return 12
            case .thick: return 22
            }
        }

        var tip: String {
            switch self {
            case .fine: return "细"
            case .medium: return "中"
            case .thick: return "粗"
            }
        }
    }

    private var continuation: CheckedContinuation<OverlayCompletion, Never>?
    private var windows: [OverlayWindow] = []
    private var keyMonitor: Any?
    /// 不全屏 activate 时，Esc 等键仍需在其他 App（含全屏 Space）前台时可用。
    private var globalKeyMonitor: Any?
    private var finished = false
    private var phase: Phase = .selecting

    /// 选区确认后捕获；第二参数为本遮罩各窗的 CGWindowID，供滤镜排除。
    private var captureHandler: ((CGRect, [CGWindowID]) async throws -> CapturedImage)?

    private var anchor: CGPoint?
    private var dragActive = false
    private var selectionRect: CGRect?

    private var captured: CapturedImage?
    private var annotations: [Annotation] = []
    private var redoStack: [Annotation] = []
    private var activeTool: AnnotateTool = .rectangle
    private var strokeColor = AnnotationColor.red
    private var strokePreset: StrokePreset = .medium
    private var annotateDragStart: CGPoint?
    private var annotateDragCurrent: CGPoint?
    /// 底图像素缓冲，供预览层画真实马赛克（与 Renderer 同源算法）。
    private var mosaicSource: (width: Int, height: Int, bytesPerRow: Int, pixels: [UInt8])?

    private var toolDock: AnnotateToolDock?
    private var textField: NSTextField?
    private var pendingTextOrigin: CGPoint?

    fileprivate static let palette: [AnnotationColor] = [
        .red, .blue, .yellow, .green, .white,
    ]

    private var strokeWidth: CGFloat { strokePreset.lineWidth }

    // MARK: - 生命周期

    /// 框选 → 捕获 → 贴图标注。
    static func run(
        capture: @escaping @MainActor (CGRect, [CGWindowID]) async throws -> CapturedImage
    ) async -> OverlayCompletion {
        let controller = SelectionOverlayController()
        controller.captureHandler = capture
        current = controller
        return await withCheckedContinuation { continuation in
            MainActor.assumeIsolated {
                controller.startSelecting(continuation: continuation)
            }
        }
    }

    /// 直接进入贴图标注（历史「继续标注」）。
    static func runAnnotate(captured: CapturedImage) async -> OverlayCompletion {
        let controller = SelectionOverlayController()
        current = controller
        return await withCheckedContinuation { continuation in
            MainActor.assumeIsolated {
                controller.startAnnotateOnly(captured: captured, continuation: continuation)
            }
        }
    }

    private func startSelecting(continuation: CheckedContinuation<OverlayCompletion, Never>) {
        guard openWindows() else {
            continuation.resume(returning: .canceled)
            return
        }
        self.continuation = continuation
        phase = .selecting
        NSCursor.crosshair.push()
    }

    private func startAnnotateOnly(
        captured: CapturedImage,
        continuation: CheckedContinuation<OverlayCompletion, Never>
    ) {
        guard openWindows() else {
            continuation.resume(returning: .canceled)
            return
        }
        self.continuation = continuation
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let maxW = screenFrame.width * 0.72
        let maxH = screenFrame.height * 0.72
        let srcW = max(captured.pointSize.width, 1)
        let srcH = max(captured.pointSize.height, 1)
        let scale = min(1, min(maxW / srcW, maxH / srcH))
        let displaySize = CGSize(width: srcW * scale, height: srcH * scale)
        selectionRect = CGRect(
            x: screenFrame.midX - displaySize.width / 2,
            y: screenFrame.midY - displaySize.height / 2,
            width: displaySize.width,
            height: displaySize.height
        )
        enterAnnotating(with: captured, pushCursor: true)
    }

    private func openWindows() -> Bool {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            Self.current = nil
            return false
        }
        for screen in screens {
            let window = OverlayWindow(contentRect: screen.frame)
            window.contentView = SelectionOverlayView(controller: self, screenFrame: screen.frame)
            // 不要 NSApp.activate：regular 策略下会把副屏全屏 Space 切回桌面，遮罩盖不到全屏内容。
            window.orderFrontRegardless()
            windows.append(window)
        }
        windows.first?.makeKeyAndOrderFront(nil)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            _ = self?.handleKeyDown(event)
        }
        return true
    }

    private func finish(_ completion: OverlayCompletion) {
        guard !finished else { return }
        finished = true
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
        NSCursor.pop()
        dismissChrome()
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows = []
        Self.current = nil
        continuation?.resume(returning: completion)
        continuation = nil
    }

    private func dismissChrome() {
        toolDock?.removeFromSuperview()
        textField?.removeFromSuperview()
        toolDock = nil
        textField = nil
    }

    // MARK: - 键盘

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 53: // Esc
            if textField != nil {
                cancelTextInput()
                return nil
            }
            finish(.canceled)
            return nil
        case 36, 76: // Return
            if textField != nil {
                commitTextInput()
                return nil
            }
            if phase == .selecting, let selection = selectionRect, !dragActive {
                Task { await confirmSelection(selection) }
                return nil
            }
            if phase == .annotating {
                confirmAnnotate()
                return nil
            }
        case 51, 117: // Delete / Forward Delete
            if phase == .annotating, textField == nil {
                undoAnnotation()
                return nil
            }
        default:
            break
        }
        // ⌘Z / ⇧⌘Z
        if phase == .annotating, textField == nil,
           event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            if event.modifierFlags.contains(.shift) {
                redoAnnotation()
            } else {
                undoAnnotation()
            }
            return nil
        }
        return event
    }

    // MARK: - 选区确认 → 捕获 → 标注

    private func confirmSelection(_ selection: CGRect) async {
        guard phase == .selecting, let captureHandler, !finished else { return }
        // 遮罩保持可见：捕获滤镜排除本窗，避免 orderOut → 截图 → 再显示的跳变。
        let excludeIDs = windows.map { CGWindowID($0.windowNumber) }
        do {
            let captured = try await captureHandler(selection, excludeIDs)
            // 与真实捕获矩形对齐，避免 point 取整后鼠标映射漂移
            selectionRect = CGRect(
                x: selection.minX.rounded(.down),
                y: selection.minY.rounded(.down),
                width: captured.pointSize.width,
                height: captured.pointSize.height
            )
            enterAnnotating(with: captured, pushCursor: false)
        } catch {
            finish(.canceled)
        }
    }

    private func enterAnnotating(with captured: CapturedImage, pushCursor: Bool) {
        self.captured = captured
        phase = .annotating
        dragActive = false
        anchor = nil
        annotations = []
        redoStack = []
        annotateDragStart = nil
        annotateDragCurrent = nil
        mosaicSource = Self.makePixelBuffer(of: captured.image)
        if pushCursor {
            NSCursor.crosshair.push()
        }
        NSCursor.arrow.set()
        toolDock = AnnotateToolDock(
            target: self,
            selectedToolTag: activeTool.rawValue,
            selectedColorIndex: Self.palette.firstIndex(of: strokeColor) ?? 0,
            selectedStrokeTag: strokePreset.rawValue
        )
        toolDock?.updateHistoryEnabled(canUndo: false, canRedo: false)
        layoutChrome()
        refresh()
    }

    private func pushAnnotation(_ annotation: Annotation) {
        annotations.append(annotation)
        redoStack.removeAll()
        refresh()
        toolDock?.updateHistoryEnabled(canUndo: !annotations.isEmpty, canRedo: !redoStack.isEmpty)
    }

    private func undoAnnotation() {
        guard phase == .annotating, textField == nil, let last = annotations.popLast() else { return }
        redoStack.append(last)
        refresh()
        toolDock?.updateHistoryEnabled(canUndo: !annotations.isEmpty, canRedo: !redoStack.isEmpty)
    }

    private func redoAnnotation() {
        guard phase == .annotating, textField == nil, let next = redoStack.popLast() else { return }
        annotations.append(next)
        refresh()
        toolDock?.updateHistoryEnabled(canUndo: !annotations.isEmpty, canRedo: !redoStack.isEmpty)
    }

    private static func makePixelBuffer(of image: CGImage) -> (width: Int, height: Int, bytesPerRow: Int, pixels: [UInt8])? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        return (width, height, width * 4, buffer)
    }

    private func confirmAnnotate() {
        guard phase == .annotating, let captured else { return }
        commitTextInput()
        do {
            let rendered = try AnnotationRenderer.render(base: captured.image, annotations: annotations)
            let png = try AnnotationRenderer.pngData(base: captured.image, annotations: annotations)
            let result = CapturedImage(
                image: rendered,
                pngData: png,
                pointSize: captured.pointSize,
                pixelSize: CGSize(width: rendered.width, height: rendered.height)
            )
            finish(.confirmed(result))
        } catch {
            // 渲染失败时退回原图，仍可复制
            finish(.confirmed(captured))
        }
    }

    // MARK: - dock 动作

    @objc func toolButtonTapped(_ sender: NSButton) {
        guard let tool = AnnotateTool(rawValue: sender.tag) else { return }
        commitTextInput()
        activeTool = tool
        toolDock?.selectTool(tag: tool.rawValue)
    }

    @objc func colorSwatchTapped(_ sender: NSButton) {
        let index = sender.tag
        guard Self.palette.indices.contains(index) else { return }
        commitTextInput()
        strokeColor = Self.palette[index]
        toolDock?.selectColor(index: index)
    }

    @objc func strokePresetTapped(_ sender: NSButton) {
        guard let preset = StrokePreset(rawValue: sender.tag) else { return }
        commitTextInput()
        strokePreset = preset
        toolDock?.selectStroke(tag: preset.rawValue)
        // 拖拽中切换粗细时立刻反映到草稿
        if annotateDragStart != nil {
            refresh()
        }
    }

    @objc func historyButtonTapped(_ sender: NSButton) {
        guard let tag = AnnotateToolDock.HistoryTag(rawValue: sender.tag) else { return }
        switch tag {
        case .undo:
            undoAnnotation()
        case .redo:
            redoAnnotation()
        }
    }

    @objc func confirmButtonTapped(_ sender: NSButton) {
        guard let tag = AnnotateToolDock.ActionTag(rawValue: sender.tag) else { return }
        switch tag {
        case .confirm:
            confirmAnnotate()
        case .cancel:
            finish(.canceled)
        }
    }

    // MARK: - 鼠标：选区

    fileprivate func beginDrag(at globalPoint: CGPoint) {
        if phase == .annotating {
            beginAnnotateDrag(at: globalPoint)
            return
        }
        anchor = globalPoint
        dragActive = true
        selectionRect = nil
        refresh()
    }

    fileprivate func updateDrag(to globalPoint: CGPoint) {
        if phase == .annotating {
            updateAnnotateDrag(to: globalPoint)
            return
        }
        guard let anchor else { return }
        selectionRect = Self.rect(from: anchor, to: globalPoint)
        refresh()
    }

    fileprivate func endDrag(at globalPoint: CGPoint) {
        if phase == .annotating {
            endAnnotateDrag(at: globalPoint)
            return
        }
        guard let anchor else { return }
        let rect = Self.rect(from: anchor, to: globalPoint)
        self.anchor = nil
        dragActive = false
        if rect.width >= Self.minimumSelectionSize, rect.height >= Self.minimumSelectionSize {
            selectionRect = rect
            Task { await confirmSelection(rect) }
        } else {
            selectionRect = nil
            refresh()
        }
    }

    private static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }

    // MARK: - 鼠标：标注

    private func beginAnnotateDrag(at globalPoint: CGPoint) {
        commitTextInput()
        guard let selection = selectionRect, selection.contains(globalPoint) else { return }
        annotateDragStart = globalPoint
        annotateDragCurrent = globalPoint
        if activeTool == .text {
            // 文字：单击落点，弹出输入框
            pendingTextOrigin = globalPoint
            return
        }
        annotateDragCurrent = globalPoint
        refresh()
    }

    private func updateAnnotateDrag(to globalPoint: CGPoint) {
        guard annotateDragStart != nil, activeTool != .text else { return }
        annotateDragCurrent = clampToSelection(globalPoint)
        refresh()
    }

    private func endAnnotateDrag(at globalPoint: CGPoint) {
        defer {
            annotateDragStart = nil
            annotateDragCurrent = nil
        }
        if activeTool == .text {
            if let origin = pendingTextOrigin ?? annotateDragStart {
                beginTextInput(at: origin)
            }
            pendingTextOrigin = nil
            return
        }
        guard let start = annotateDragStart else { return }
        let end = clampToSelection(globalPoint)
        let annotation = makeDraft(from: start, to: end)
        let minSpan: CGFloat = activeTool == .line || activeTool == .arrow ? 4 : 6
        if annotation.rect.width < minSpan && annotation.rect.height < minSpan,
           annotation.kind != .line, annotation.kind != .arrow {
            refresh()
            return
        }
        if let s = annotation.startPoint, let e = annotation.endPoint, s == e {
            refresh()
            return
        }
        pushAnnotation(annotation)
    }

    private func clampToSelection(_ point: CGPoint) -> CGPoint {
        guard let selection = selectionRect else { return point }
        return CGPoint(
            x: min(max(point.x, selection.minX), selection.maxX),
            y: min(max(point.y, selection.minY), selection.maxY)
        )
    }

    /// 全局 AppKit 点 → 图像像素坐标（左上原点）。
    private func pixelPoint(from global: CGPoint) -> CGPoint? {
        guard let selection = selectionRect, let captured else { return nil }
        return ScreenGeometry.pixelPoint(
            global: clampToSelection(global),
            selection: selection,
            imageSize: CGSize(width: captured.image.width, height: captured.image.height)
        )
    }

    private func makeDraft(from globalStart: CGPoint, to globalEnd: CGPoint) -> Annotation {
        let p0 = pixelPoint(from: globalStart) ?? .zero
        let p1 = pixelPoint(from: globalEnd) ?? .zero
        let rect = CGRect(
            x: min(p0.x, p1.x),
            y: min(p0.y, p1.y),
            width: max(abs(p1.x - p0.x), 1),
            height: max(abs(p1.y - p0.y), 1)
        )
        // 线宽/马赛克块按图像像素密度放大，使导出与屏幕预览接近
        let density: CGFloat = {
            guard let selection = selectionRect, let captured else { return 1 }
            return CGFloat(captured.image.width) / max(selection.width, 1)
        }()
        let pixelStroke = strokePreset.lineWidth * density
        let mosaicBlock = strokePreset.mosaicBlockPoints * density
        switch activeTool {
        case .rectangle:
            return Annotation(kind: .rectangle, rect: rect, color: strokeColor, strokeWidth: pixelStroke)
        case .mosaic:
            // strokeWidth 对马赛克表示「块边长（像素）」
            return Annotation(kind: .mosaic, rect: rect, color: strokeColor, strokeWidth: mosaicBlock)
        case .line:
            return Annotation(kind: .line, rect: rect, startPoint: p0, endPoint: p1,
                              color: strokeColor, strokeWidth: pixelStroke)
        case .arrow:
            return Annotation(kind: .arrow, rect: rect, startPoint: p0, endPoint: p1,
                              color: strokeColor, strokeWidth: pixelStroke)
        case .text:
            let textRect = CGRect(x: p0.x, y: p0.y, width: 220 * density, height: 40 * density)
            return Annotation(kind: .text, rect: textRect, color: strokeColor, text: "", fontSize: 16 * density)
        }
    }

    // MARK: - 文字输入

    private func beginTextInput(at globalPoint: CGPoint) {
        guard let selection = selectionRect,
              let hostWindow = windows.first(where: { $0.frame.contains(globalPoint) }) ?? windows.first,
              let hostView = hostWindow.contentView else { return }
        cancelTextInput()
        pendingTextOrigin = globalPoint

        let field = NSTextField(frame: .zero)
        field.placeholderString = "输入文字后回车"
        field.font = .systemFont(ofSize: 14, weight: .medium)
        field.textColor = NSColor(srgbRed: strokeColor.r, green: strokeColor.g, blue: strokeColor.b, alpha: 1)
        field.backgroundColor = NSColor.black.withAlphaComponent(0.55)
        field.isBordered = false
        field.focusRingType = .none
        field.delegate = self
        let local = CGPoint(x: globalPoint.x - hostWindow.frame.minX, y: globalPoint.y - hostWindow.frame.minY)
        field.frame = CGRect(x: local.x, y: local.y - 14, width: min(240, selection.maxX - globalPoint.x + 40), height: 28)
        hostView.addSubview(field)
        hostWindow.makeKeyAndOrderFront(nil)
        field.becomeFirstResponder()
        textField = field
    }

    private func commitTextInput() {
        guard let field = textField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let origin = pendingTextOrigin
        field.removeFromSuperview()
        textField = nil
        pendingTextOrigin = nil
        guard !text.isEmpty, let origin, var annotation = Optional(makeDraft(from: origin, to: origin)) else {
            refresh()
            return
        }
        annotation.text = text
        // 按字数估宽
        let width = max(120, CGFloat(text.count) * annotation.fontSize * 0.7)
        annotation.rect = CGRect(x: annotation.rect.minX, y: annotation.rect.minY, width: width, height: max(34, annotation.fontSize + 12))
        pushAnnotation(annotation)
    }

    private func cancelTextInput() {
        textField?.removeFromSuperview()
        textField = nil
        pendingTextOrigin = nil
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitTextInput()
    }

    // MARK: - chrome 布局（统一底部悬浮工具栏）

    private func layoutChrome() {
        guard let selection = selectionRect else { return }
        layoutToolDock(selection: selection)
    }

    private func layoutToolDock(selection: CGRect) {
        guard let dock = toolDock else { return }
        let size = dock.fittingSize
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let hostScreen = NSScreen.screens.first {
            $0.frame.contains(CGPoint(x: selection.midX, y: selection.midY))
        }
        // 优先选区底部外侧右对齐；底部不够则翻到顶部外侧；都不够则贴选区底部内侧
        var origin = CGPoint(x: selection.maxX - width, y: selection.minY - 10 - height)
        if let screen = hostScreen {
            if origin.y < screen.frame.minY + 6 {
                let topY = selection.maxY + 10
                if topY + height <= screen.frame.maxY - 6 {
                    origin.y = topY
                } else {
                    origin.y = selection.minY + 10
                }
            }
            origin.x = min(origin.x, screen.frame.maxX - width - 6)
            origin.x = max(origin.x, screen.frame.minX + 6)
        }
        place(dock, origin: origin, size: CGSize(width: width, height: height))
    }

    private func place(_ view: NSView, origin: CGPoint, size: CGSize) {
        let center = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        let hostWindow = windows.first { $0.frame.contains(center) } ?? windows.first
        guard let hostView = hostWindow?.contentView as? SelectionOverlayView,
              let hostFrame = hostWindow?.frame else { return }
        if view.superview !== hostView {
            view.removeFromSuperview()
            hostView.addSubview(view)
        }
        view.frame = CGRect(
            x: origin.x - hostFrame.minX,
            y: origin.y - hostFrame.minY,
            width: size.width,
            height: size.height
        )
        view.isHidden = false
    }

    private func refresh() {
        for window in windows {
            window.contentView?.needsDisplay = true
        }
        if phase == .annotating {
            layoutChrome()
        }
    }

    // MARK: - 绘制

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

        if phase == .selecting, selectionRect == nil || dragActive {
            drawHintPill(in: bounds)
        }

        guard let sel = localSelection else { return }

        if phase == .annotating, let base = captured?.image {
            // 底图 + 视图坐标标注（跟鼠标对齐）；马赛克从像素缓冲采样，不是色块遮罩。
            // 导出仍走 AnnotationRenderer，与预览算法一致。
            drawCapturedImage(base, in: sel)
            drawAnnotationsOverlay(in: sel, screenFrame: screenFrame)
            if let start = annotateDragStart, let current = annotateDragCurrent, activeTool != .text {
                drawDraftOverlay(from: start, to: current, screenFrame: screenFrame)
            }
        }

        // 单层明黄选框（避免双线叠层造成的杂乱感）
        let ring = NSColor(srgbRed: 250 / 255, green: 204 / 255, blue: 21 / 255, alpha: 0.92)
        ring.setStroke()
        let borderPath = NSBezierPath(rect: sel.insetBy(dx: -0.75, dy: -0.75))
        borderPath.lineWidth = 1.5
        borderPath.stroke()

        if phase == .selecting {
            drawHandles(around: sel)
            if dragActive {
                drawSizeHUD(for: sel, in: bounds)
            }
        }
    }

    /// 合成后的 CGImage 已是正向；遮罩视图的 CTM 与之同向，不再额外翻 Y
    ///（此前翻 Y 是在掩盖合成颠倒，合成修好后再翻就会把预览弄反）。
    private func drawCapturedImage(_ image: CGImage, in sel: CGRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.saveGState()
        cg.interpolationQuality = .high
        cg.draw(image, in: sel)
        cg.restoreGState()
    }

    private func drawAnnotationsOverlay(in sel: CGRect, screenFrame: CGRect) {
        guard let selection = selectionRect, let captured else { return }
        let imageSize = CGSize(width: captured.image.width, height: captured.image.height)
        for annotation in annotations {
            drawAnnotation(annotation, selection: selection, imageSize: imageSize, screenFrame: screenFrame)
        }
    }

    private func drawDraftOverlay(from start: CGPoint, to end: CGPoint, screenFrame: CGRect) {
        let p0 = CGPoint(x: start.x - screenFrame.minX, y: start.y - screenFrame.minY)
        let p1 = CGPoint(x: end.x - screenFrame.minX, y: end.y - screenFrame.minY)
        let color = NSColor(srgbRed: strokeColor.r, green: strokeColor.g, blue: strokeColor.b, alpha: 1)
        switch activeTool {
        case .rectangle:
            let rect = Self.rect(from: p0, to: p1)
            color.withAlphaComponent(0.08).setFill()
            rect.fill()
            color.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = strokeWidth
            path.stroke()
        case .mosaic:
            let draft = makeDraft(from: start, to: end)
            guard let selection = selectionRect else { return }
            let imageSize = CGSize(
                width: mosaicSource?.width ?? Int(draft.rect.width),
                height: mosaicSource?.height ?? Int(draft.rect.height)
            )
            drawMosaicAnnotation(draft, selection: selection, imageSize: imageSize, screenFrame: screenFrame)
        case .line:
            color.setStroke()
            let path = NSBezierPath()
            path.move(to: p0)
            path.line(to: p1)
            path.lineWidth = strokeWidth
            path.lineCapStyle = .round
            path.stroke()
        case .arrow:
            drawArrow(from: p0, to: p1, color: color, strokeWidth: strokeWidth)
        case .text:
            break
        }
    }

    private func drawAnnotation(
        _ annotation: Annotation,
        selection: CGRect,
        imageSize: CGSize,
        screenFrame: CGRect
    ) {
        let color = NSColor(
            srgbRed: annotation.color.r,
            green: annotation.color.g,
            blue: annotation.color.b,
            alpha: annotation.color.a
        )
        let density = imageSize.width / max(selection.width, 1)
        let viewStroke = max(annotation.strokeWidth / density, 1)

        func toLocal(_ pixel: CGPoint) -> CGPoint {
            let global = ScreenGeometry.globalPoint(pixel: pixel, selection: selection, imageSize: imageSize)
            return CGPoint(x: global.x - screenFrame.minX, y: global.y - screenFrame.minY)
        }

        switch annotation.kind {
        case .rectangle:
            let tl = toLocal(annotation.rect.origin)
            let br = toLocal(CGPoint(x: annotation.rect.maxX, y: annotation.rect.maxY))
            let rect = Self.rect(from: tl, to: br)
            color.withAlphaComponent(0.08).setFill()
            rect.fill()
            color.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = viewStroke
            path.stroke()
        case .mosaic:
            drawMosaicAnnotation(annotation, selection: selection, imageSize: imageSize, screenFrame: screenFrame)
        case .line:
            guard let start = annotation.startPoint, let end = annotation.endPoint else { return }
            let p0 = toLocal(start)
            let p1 = toLocal(end)
            color.setStroke()
            let path = NSBezierPath()
            path.move(to: p0)
            path.line(to: p1)
            path.lineWidth = viewStroke
            path.lineCapStyle = .round
            path.stroke()
        case .arrow:
            guard let start = annotation.startPoint, let end = annotation.endPoint else { return }
            let p0 = toLocal(start)
            let p1 = toLocal(end)
            drawArrow(from: p0, to: p1, color: color, strokeWidth: viewStroke)
        case .text:
            let origin = toLocal(annotation.rect.origin)
            let text = annotation.text ?? ""
            let fontSize = annotation.fontSize / density
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: max(fontSize, 10), weight: .semibold),
                .foregroundColor: color,
            ]
            (text as NSString).draw(at: origin, withAttributes: attrs)
        }
    }

    /// 在视图坐标系画真实像素马赛克（采样底图，块大小来自 annotation.strokeWidth）。
    private func drawMosaicAnnotation(
        _ annotation: Annotation,
        selection: CGRect,
        imageSize: CGSize,
        screenFrame: CGRect
    ) {
        guard let source = mosaicSource else { return }
        let blockSize = AnnotationRenderer.mosaicBlockSize(for: annotation)
        let block = CGFloat(blockSize)
        let area = annotation.rect.intersection(CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height))
        guard area.width > 0, area.height > 0 else { return }

        let startBlockX = Int(floor(area.minX / block)) * blockSize
        let endX = Int(ceil(area.maxX))
        let startBlockY = Int(floor(area.minY / block)) * blockSize
        let endY = Int(ceil(area.maxY))

        func toLocal(_ pixel: CGPoint) -> CGPoint {
            let global = ScreenGeometry.globalPoint(pixel: pixel, selection: selection, imageSize: imageSize)
            return CGPoint(x: global.x - screenFrame.minX, y: global.y - screenFrame.minY)
        }

        var blockX = startBlockX
        while blockX < endX {
            var blockY = startBlockY
            while blockY < endY {
                let blockRect = CGRect(x: CGFloat(blockX), y: CGFloat(blockY), width: block, height: block)
                let region = blockRect.intersection(area)
                if region.width >= 1, region.height >= 1,
                   let avg = Self.averageColor(
                    in: region,
                    source: source.pixels,
                    bytesPerRow: source.bytesPerRow,
                    width: source.width,
                    height: source.height
                   ) {
                    let tl = toLocal(CGPoint(x: region.minX, y: region.minY))
                    let br = toLocal(CGPoint(x: region.maxX, y: region.maxY))
                    let viewRect = Self.rect(from: tl, to: br)
                    NSColor(srgbRed: avg.r, green: avg.g, blue: avg.b, alpha: avg.a).setFill()
                    viewRect.fill()
                }
                blockY += blockSize
            }
            blockX += blockSize
        }
    }

    private static func averageColor(
        in region: CGRect,
        source: [UInt8],
        bytesPerRow: Int,
        width: Int,
        height: Int
    ) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
        let x0 = max(0, Int(floor(region.minX)))
        let x1 = min(width - 1, Int(ceil(region.maxX)) - 1)
        let y0 = max(0, Int(floor(region.minY)))
        let y1 = min(height - 1, Int(ceil(region.maxY)) - 1)
        guard x0 <= x1, y0 <= y1 else { return nil }
        var sumR = 0.0, sumG = 0.0, sumB = 0.0, sumA = 0.0, colorCount = 0.0
        let pixelCount = Double((x1 - x0 + 1) * (y1 - y0 + 1))
        for y in y0...y1 {
            for x in x0...x1 {
                let offset = y * bytesPerRow + x * 4
                let alpha = Double(source[offset + 3]) / 255.0
                if alpha > 0 {
                    sumR += Double(source[offset]) / 255.0 / alpha
                    sumG += Double(source[offset + 1]) / 255.0 / alpha
                    sumB += Double(source[offset + 2]) / 255.0 / alpha
                    colorCount += 1
                }
                sumA += alpha
            }
        }
        guard colorCount > 0 else { return nil }
        return (
            CGFloat(sumR / colorCount),
            CGFloat(sumG / colorCount),
            CGFloat(sumB / colorCount),
            CGFloat(sumA / pixelCount)
        )
    }

    private func drawArrow(from: CGPoint, to: CGPoint, color: NSColor, strokeWidth: CGFloat) {
        guard let geo = AnnotationArrowGeometry(from: from, to: to, strokeWidth: strokeWidth) else { return }

        color.setStroke()
        let shaft = NSBezierPath()
        shaft.move(to: from)
        shaft.line(to: geo.shaftEnd)
        shaft.lineWidth = strokeWidth
        shaft.lineCapStyle = .round
        shaft.stroke()

        let head = NSBezierPath()
        head.move(to: geo.tip)
        head.line(to: geo.leftWing)
        head.line(to: geo.neck)
        head.line(to: geo.rightWing)
        head.close()
        color.setFill()
        head.fill()
    }

    private func drawHandles(around sel: CGRect) {
        let centers = [
            CGPoint(x: sel.minX, y: sel.minY),
            CGPoint(x: sel.maxX, y: sel.minY),
            CGPoint(x: sel.minX, y: sel.maxY),
            CGPoint(x: sel.maxX, y: sel.maxY),
        ]
        for center in centers {
            let dot = NSBezierPath(ovalIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
            NSColor.white.setFill()
            dot.fill()
            NSColor.black.withAlphaComponent(0.35).setStroke()
            let outline = NSBezierPath(ovalIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
            outline.lineWidth = 1
            outline.stroke()
        }
    }

    private func drawSizeHUD(for sel: CGRect, in bounds: CGRect) {
        let text = "\(Int(sel.width.rounded())) × \(Int(sel.height.rounded()))"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.94),
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let hudWidth = textSize.width + 16
        let hudHeight: CGFloat = 22
        var origin = CGPoint(x: sel.minX, y: sel.maxY + 6)
        if origin.y + hudHeight > bounds.maxY {
            origin.y = sel.maxY - 6 - hudHeight
        }
        let rect = CGRect(x: origin.x, y: origin.y, width: hudWidth, height: hudHeight)
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

    private func drawHintPill(in bounds: CGRect) {
        struct Segment {
            let text: String
            let isKey: Bool
        }
        let segments: [Segment] = [
            Segment(text: "拖拽框选区域", isKey: false),
            Segment(text: "⏎", isKey: true),
            Segment(text: "标注", isKey: false),
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

        var totalWidth = pillHorizontalPadding * 2
        var segmentWidths: [CGFloat] = []
        for (index, segment) in segments.enumerated() {
            let font = segment.isKey ? keyFont : textFont
            let width = (segment.text as NSString).size(withAttributes: [.font: font]).width
            let displayWidth = segment.isKey ? width + chipHorizontalPadding * 2 : width
            segmentWidths.append(displayWidth)
            totalWidth += displayWidth
            if index < segments.count - 1 { totalWidth += segmentGap }
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

// MARK: - Window / View

/// 截屏遮罩必须用 NSPanel + nonactivatingPanel，才能稳定盖在其他 App 的全屏 Space 上。
/// 普通 NSWindow 即使写了 fullScreenAuxiliary，窗口服务器仍常钉在桌面 Space；再配上
/// NSApp.activate 还会把副屏全屏 Space 切走（双屏「全屏那块截不了」的根因）。
final class OverlayWindow: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
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
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
    }

    override var canBecomeKey: Bool { true }
}

final class SelectionOverlayView: NSView {
    private let controller: SelectionOverlayController
    private let screenFrame: CGRect

    init(controller: SelectionOverlayController, screenFrame: CGRect) {
        self.controller = controller
        self.screenFrame = screenFrame
        // 窗口内容区原点为 (0,0)；全局坐标 = 本地 + screenFrame.origin
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SelectionOverlayView 只在代码里创建，不支持 coder 初始化")
    }

    override var acceptsFirstResponder: Bool { true }

    /// 快捷键从其他 App 拉起遮罩时，第一下点击仍要开始框选，不能只用来激活窗口。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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

    /// 与绘制使用同一套 screenFrame 映射，避免 convertToScreen 与选区坐标系漂移。
    private func globalLocation(of event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(x: local.x + screenFrame.minX, y: local.y + screenFrame.minY)
    }
}

// MARK: - 统一悬浮工具栏（图标化工具 + 色板 + 历史 + 确认）

@MainActor
final class AnnotateToolDock: NSStackView {
    enum HistoryTag: Int {
        case undo = 1
        case redo = 2
    }

    enum ActionTag: Int {
        case cancel = 1
        case confirm = 2
    }

    private var toolButtons: [NSButton] = []
    private var colorButtons: [NSButton] = []
    private var strokeButtons: [NSButton] = []
    private var undoButton: NSButton?
    private var redoButton: NSButton?

    private static let brandYellow = NSColor(srgbRed: 250 / 255, green: 204 / 255, blue: 21 / 255, alpha: 1)
    private static let darkInk = NSColor(srgbRed: 24 / 255, green: 24 / 255, blue: 27 / 255, alpha: 1)

    init(
        target: SelectionOverlayController,
        selectedToolTag: Int,
        selectedColorIndex: Int,
        selectedStrokeTag: Int
    ) {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 4
        edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 20 / 255, green: 22 / 255, blue: 27 / 255, alpha: 0.92).cgColor
        layer?.cornerRadius = 11
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        layer?.borderWidth = 0.5
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -4)

        let tools: [(symbol: String, tip: String, tag: Int)] = [
            ("textformat", "文字标注", 1),
            ("rectangle", "矩形框", 2),
            ("line.diagonal", "直线", 3),
            ("arrow.up.right", "箭头", 4),
            ("checkerboard.rectangle", "打码", 5),
        ]
        for tool in tools {
            let button = Self.makeToolButton(
                symbol: tool.symbol,
                toolTip: tool.tip,
                tag: tool.tag,
                selected: tool.tag == selectedToolTag,
                target: target
            )
            toolButtons.append(button)
            addArrangedSubview(button)
        }

        appendSeparator(after: toolButtons.last)

        for (index, color) in SelectionOverlayController.palette.enumerated() {
            let button = Self.makeColorButton(
                color: color,
                index: index,
                selected: index == selectedColorIndex,
                target: target
            )
            colorButtons.append(button)
            addArrangedSubview(button)
            if index < SelectionOverlayController.palette.count - 1 {
                setCustomSpacing(4, after: button)
            }
        }

        appendSeparator(after: colorButtons.last)

        for preset in SelectionOverlayController.StrokePreset.allCases {
            let button = Self.makeStrokeButton(
                title: preset.tip,
                tag: preset.rawValue,
                selected: preset.rawValue == selectedStrokeTag,
                target: target
            )
            strokeButtons.append(button)
            addArrangedSubview(button)
        }

        appendSeparator(after: strokeButtons.last)

        let undo = Self.makeHistoryButton(
            symbol: "arrow.uturn.backward",
            tag: HistoryTag.undo.rawValue,
            toolTip: "撤销 ⌘Z",
            target: target
        )
        let redo = Self.makeHistoryButton(
            symbol: "arrow.uturn.forward",
            tag: HistoryTag.redo.rawValue,
            toolTip: "重做 ⇧⌘Z",
            target: target
        )
        undoButton = undo
        redoButton = redo
        addArrangedSubview(undo)
        addArrangedSubview(redo)

        appendSeparator(after: redo)

        addArrangedSubview(Self.makeConfirmButton(
            symbol: "xmark",
            toolTip: "取消 Esc",
            tag: ActionTag.cancel.rawValue,
            primary: false,
            target: target
        ))
        addArrangedSubview(Self.makeConfirmButton(
            symbol: "checkmark",
            toolTip: "完成并复制 ↩",
            tag: ActionTag.confirm.rawValue,
            primary: true,
            target: target
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("AnnotateToolDock 只在代码里创建")
    }

    func selectTool(tag: Int) {
        for button in toolButtons {
            let on = button.tag == tag
            button.layer?.backgroundColor = on ? Self.brandYellow.cgColor : NSColor.clear.cgColor
            button.contentTintColor = on ? Self.darkInk : NSColor.white.withAlphaComponent(0.84)
        }
    }

    func selectColor(index: Int) {
        for (i, button) in colorButtons.enumerated() {
            let on = i == index
            button.layer?.borderWidth = on ? 2.0 : 0
            button.layer?.borderColor = on ? NSColor.white.cgColor : NSColor.clear.cgColor
        }
    }

    func selectStroke(tag: Int) {
        for button in strokeButtons {
            let on = button.tag == tag
            button.layer?.backgroundColor = on ? Self.brandYellow.cgColor : NSColor.clear.cgColor
            button.contentTintColor = on ? Self.darkInk : NSColor.white.withAlphaComponent(0.84)
        }
    }

    func updateHistoryEnabled(canUndo: Bool, canRedo: Bool) {
        undoButton?.isEnabled = canUndo
        redoButton?.isEnabled = canRedo
        undoButton?.alphaValue = canUndo ? 1.0 : 0.38
        redoButton?.alphaValue = canRedo ? 1.0 : 0.38
    }

    private static func makeToolButton(
        symbol: String,
        toolTip: String,
        tag: Int,
        selected: Bool,
        target: SelectionOverlayController
    ) -> NSButton {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(config)
        let button = NSButton(
            image: image ?? NSImage(),
            target: target,
            action: #selector(SelectionOverlayController.toolButtonTapped(_:))
        )
        button.tag = tag
        button.toolTip = toolTip
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = selected ? darkInk : NSColor.white.withAlphaComponent(0.84)
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.masksToBounds = true
        button.layer?.backgroundColor = selected ? brandYellow.cgColor : NSColor.clear.cgColor
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    private static func makeStrokeButton(
        title: String,
        tag: Int,
        selected: Bool,
        target: SelectionOverlayController
    ) -> NSButton {
        let button = NSButton(
            title: title,
            target: target,
            action: #selector(SelectionOverlayController.strokePresetTapped(_:))
        )
        button.tag = tag
        button.toolTip = "粗细：\(title)（线条/马赛克块）"
        button.isBordered = false
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.contentTintColor = selected ? darkInk : NSColor.white.withAlphaComponent(0.84)
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.masksToBounds = true
        button.layer?.backgroundColor = selected ? brandYellow.cgColor : NSColor.clear.cgColor
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        return button
    }

    private final class SwatchFillView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private static func makeColorButton(
        color: AnnotationColor,
        index: Int,
        selected: Bool,
        target: SelectionOverlayController
    ) -> NSButton {
        let button = NSButton(
            title: "",
            target: target,
            action: #selector(SelectionOverlayController.colorSwatchTapped(_:))
        )
        button.tag = index
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 10
        button.layer?.masksToBounds = true
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.layer?.borderWidth = selected ? 2.0 : 0
        button.layer?.borderColor = selected ? NSColor.white.cgColor : NSColor.clear.cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 20).isActive = true
        button.widthAnchor.constraint(equalToConstant: 20).isActive = true

        let swatch = SwatchFillView()
        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = 6
        swatch.layer?.masksToBounds = true
        swatch.layer?.backgroundColor = NSColor(
            srgbRed: color.r, green: color.g, blue: color.b, alpha: color.a
        ).cgColor
        swatch.layer?.borderWidth = 0.75
        swatch.layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
        swatch.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(swatch)
        NSLayoutConstraint.activate([
            swatch.widthAnchor.constraint(equalToConstant: 12),
            swatch.heightAnchor.constraint(equalToConstant: 12),
            swatch.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            swatch.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        return button
    }

    private static func makeHistoryButton(
        symbol: String,
        tag: Int,
        toolTip: String,
        target: SelectionOverlayController
    ) -> NSButton {
        let config = NSImage.SymbolConfiguration(pointSize: 11.5, weight: .medium)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(config)
        let button = NSButton(
            image: image ?? NSImage(),
            target: target,
            action: #selector(SelectionOverlayController.historyButtonTapped(_:))
        )
        button.tag = tag
        button.toolTip = toolTip
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = .white
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.masksToBounds = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        button.widthAnchor.constraint(equalToConstant: 26).isActive = true
        return button
    }

    private static func makeConfirmButton(
        symbol: String,
        toolTip: String,
        tag: Int,
        primary: Bool,
        target: SelectionOverlayController
    ) -> NSButton {
        let config = NSImage.SymbolConfiguration(pointSize: 11.5, weight: .semibold)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(config)
        let button = NSButton(
            image: image ?? NSImage(),
            target: target,
            action: #selector(SelectionOverlayController.confirmButtonTapped(_:))
        )
        button.tag = tag
        button.toolTip = toolTip
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = primary ? darkInk : NSColor.white.withAlphaComponent(0.86)
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.masksToBounds = true
        button.layer?.backgroundColor = primary
            ? brandYellow.cgColor
            : NSColor.white.withAlphaComponent(0.10).cgColor
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        button.widthAnchor.constraint(equalToConstant: primary ? 30 : 26).isActive = true
        button.setButtonType(.momentaryChange)
        return button
    }

    private func appendSeparator(after prev: NSView?) {
        if let prev {
            setCustomSpacing(8, after: prev)
        }
        let separator = Self.makeSeparator()
        addArrangedSubview(separator)
        setCustomSpacing(8, after: separator)
    }

    private static func makeSeparator() -> NSView {
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 14).isActive = true
        return separator
    }
}
