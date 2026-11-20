import AppKit
import Annotation

/// 选区 / 贴图标注遮罩的内部结果。
enum OverlayCompletion {
    case canceled
    case confirmed(CapturedImage)
}

/// 全屏选区 + 贴图标注控制器（支持全屏定格后选区调整与标注双套操作并行）。
@MainActor
final class SelectionOverlayController: NSObject, NSTextFieldDelegate {

    nonisolated static let minimumSelectionSize: CGFloat = 24

    private static var current: SelectionOverlayController?

    private enum Mode {
        case live(snapshots: [ScreenSnapshot], crop: @MainActor (CGRect) throws -> CapturedImage)
        case annotateOnly(CapturedImage)
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

    /// 笔触/马赛克粗细档位（视图 point；导出时再按图像密度换算像素）。
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

        /// 马赛克块边长（视图 point）。
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

    /// 全局 AppKit point 坐标下的标注，使选区缩放/移动时已画标注保持原地不动。
    private struct OverlayAnnotation {
        var kind: Annotation.Kind
        var globalRect: CGRect
        var startPoint: CGPoint?
        var endPoint: CGPoint?
        var color: AnnotationColor
        var lineWidth: CGFloat
        var text: String?
        var fontSize: CGFloat
    }

    private struct PixelSource {
        let frame: CGRect
        let width: Int
        let height: Int
        let bytesPerRow: Int
        let pixels: [UInt8]
    }

    private var continuation: CheckedContinuation<OverlayCompletion, Never>?
    private var windows: [OverlayWindow] = []
    private var keyMonitor: Any?
    /// 不全屏 activate 时，Esc 等键仍需在其他 App（含全屏 Space）前台时可用。
    private var globalKeyMonitor: Any?
    private var finished = false
    private var mode: Mode?

    private var isLiveMode: Bool {
        if case .live = mode { return true }
        return false
    }

    private enum SelectionDragKind {
        case create(anchor: CGPoint)
        case move(startPoint: CGPoint, original: CGRect)
        case resize(handle: SelectionEditing.Handle, original: CGRect)
    }

    private static let handleHitSlop: CGFloat = 11
    /// 边框拖动环带向选区外侧偏置，把内部尽量让给贴边标注起笔。
    private static let frameHitOutset: CGFloat = 12
    private static let frameHitInset: CGFloat = 3
    private static let selectionBorderWidth: CGFloat = 3

    private var selectionDrag: SelectionDragKind?
    private var dragActive = false
    private var selectionRect: CGRect?

    private var annotations: [OverlayAnnotation] = []
    private var redoStack: [OverlayAnnotation] = []
    private var activeTool: AnnotateTool?
    private var strokeColor = AnnotationColor.red
    private var strokePreset: StrokePreset = .medium
    private var annotateDragStart: CGPoint?
    private var annotateDragCurrent: CGPoint?
    /// 按屏幕帧或单图延迟生成的像素缓冲，供实时马赛克预览。
    private var pixelSources: [PixelSource] = []

    private var toolDock: AnnotateToolDock?
    private var textField: NSTextField?
    private var pendingTextOrigin: CGPoint?
    private var lockedDragCursor: NSCursor?
    private var appliedCursor: NSCursor?

    fileprivate static let palette: [AnnotationColor] = [
        .red, .blue, .yellow, .green, .white,
    ]

    private var strokeWidth: CGFloat { strokePreset.lineWidth }

    // MARK: - 生命周期

    /// 全屏定格后并行框选调整与标注。
    static func run(
        snapshots: [ScreenSnapshot],
        crop: @escaping @MainActor (CGRect) throws -> CapturedImage
    ) async -> OverlayCompletion {
        let controller = SelectionOverlayController()
        controller.mode = .live(snapshots: snapshots, crop: crop)
        current = controller
        return await withCheckedContinuation { continuation in
            MainActor.assumeIsolated {
                controller.startLiveSelection(continuation: continuation)
            }
        }
    }

    /// 直接进入贴图标注（历史「继续标注」）。
    static func runAnnotate(captured: CapturedImage) async -> OverlayCompletion {
        let controller = SelectionOverlayController()
        controller.mode = .annotateOnly(captured)
        current = controller
        return await withCheckedContinuation { continuation in
            MainActor.assumeIsolated {
                controller.startAnnotateOnly(captured: captured, continuation: continuation)
            }
        }
    }

    private func startLiveSelection(continuation: CheckedContinuation<OverlayCompletion, Never>) {
        guard openWindows() else {
            continuation.resume(returning: .canceled)
            return
        }
        self.continuation = continuation
        activeTool = nil
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
        activeTool = .rectangle
        NSCursor.crosshair.push()
        ensureToolDock()
        toolDock?.selectTool(tag: activeTool?.rawValue)
        toolDock?.selectColor(index: Self.palette.firstIndex(of: strokeColor) ?? 0)
        toolDock?.selectStroke(tag: strokePreset.rawValue)
        toolDock?.updateHistoryEnabled(canUndo: false, canRedo: false)
        layoutChrome()
        refresh()
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
            if selectionRect != nil, !dragActive {
                confirmAndFinish()
                return nil
            }
        case 51, 117: // Delete / Forward Delete
            if textField == nil, !annotations.isEmpty {
                undoAnnotation()
                return nil
            }
        default:
            break
        }
        // ⌘Z / ⇧⌘Z
        if textField == nil,
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

    // MARK: - 标注历史与导出

    private func pushAnnotation(_ annotation: OverlayAnnotation) {
        annotations.append(annotation)
        redoStack.removeAll()
        refresh()
        toolDock?.updateHistoryEnabled(canUndo: !annotations.isEmpty, canRedo: !redoStack.isEmpty)
    }

    private func undoAnnotation() {
        guard textField == nil, let last = annotations.popLast() else { return }
        redoStack.append(last)
        refresh()
        toolDock?.updateHistoryEnabled(canUndo: !annotations.isEmpty, canRedo: !redoStack.isEmpty)
    }

    private func redoAnnotation() {
        guard textField == nil, let next = redoStack.popLast() else { return }
        annotations.append(next)
        refresh()
        toolDock?.updateHistoryEnabled(canUndo: !annotations.isEmpty, canRedo: !redoStack.isEmpty)
    }

    private static func makePixelBuffer(of image: CGImage, frame: CGRect) -> PixelSource? {
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
        return PixelSource(frame: frame, width: width, height: height, bytesPerRow: width * 4, pixels: buffer)
    }

    /// 延迟准备马赛克像素缓冲，避免未用打码时拷贝全屏 RGBA。
    private func pixelSource(containing globalPoint: CGPoint) -> PixelSource? {
        if let existing = pixelSources.first(where: { $0.frame.contains(globalPoint) }) {
            return existing
        }
        switch mode {
        case .live(let snapshots, _):
            guard let snap = snapshots.first(where: { $0.frame.contains(globalPoint) }),
                  let built = Self.makePixelBuffer(of: snap.image, frame: snap.frame) else { return nil }
            pixelSources.append(built)
            return built
        case .annotateOnly(let captured):
            guard let selection = selectionRect,
                  let built = Self.makePixelBuffer(of: captured.image, frame: selection) else { return nil }
            pixelSources.append(built)
            return built
        case nil:
            return nil
        }
    }

    private func confirmAndFinish() {
        guard let selection = selectionRect, let mode else { return }
        commitTextInput()

        let baseCaptured: CapturedImage
        let exportSelection: CGRect
        switch mode {
        case .live(_, let crop):
            exportSelection = CGRect(
                x: selection.minX.rounded(.down),
                y: selection.minY.rounded(.down),
                width: selection.width.rounded(.down),
                height: selection.height.rounded(.down)
            )
            do {
                baseCaptured = try crop(exportSelection)
            } catch {
                finish(.canceled)
                return
            }
        case .annotateOnly(let captured):
            exportSelection = selection
            baseCaptured = captured
        }

        let exportAnnotations = Self.toExportAnnotations(
            annotations,
            selection: exportSelection,
            imageSize: CGSize(width: baseCaptured.image.width, height: baseCaptured.image.height)
        )
        do {
            let rendered = try AnnotationRenderer.render(base: baseCaptured.image, annotations: exportAnnotations)
            let png = try AnnotationRenderer.pngData(base: baseCaptured.image, annotations: exportAnnotations)
            let result = CapturedImage(
                image: rendered,
                pngData: png,
                pointSize: baseCaptured.pointSize,
                pixelSize: CGSize(width: rendered.width, height: rendered.height)
            )
            finish(.confirmed(result))
        } catch {
            finish(.confirmed(baseCaptured))
        }
    }

    private static func toExportAnnotations(
        _ items: [OverlayAnnotation],
        selection: CGRect,
        imageSize: CGSize
    ) -> [Annotation] {
        guard selection.width > 0, selection.height > 0 else { return [] }
        let densityX = imageSize.width / selection.width
        let densityY = imageSize.height / selection.height
        let density = max(densityX, densityY)

        func toPixel(_ global: CGPoint) -> CGPoint {
            CGPoint(
                x: (global.x - selection.minX) * densityX,
                y: (selection.maxY - global.y) * densityY
            )
        }

        func toPixelRect(_ globalRect: CGRect) -> CGRect {
            CGRect(
                x: (globalRect.minX - selection.minX) * densityX,
                y: (selection.maxY - globalRect.maxY) * densityY,
                width: globalRect.width * densityX,
                height: globalRect.height * densityY
            )
        }

        return items.map { item in
            Annotation(
                kind: item.kind,
                rect: toPixelRect(item.globalRect),
                startPoint: item.startPoint.map(toPixel),
                endPoint: item.endPoint.map(toPixel),
                color: item.color,
                strokeWidth: item.lineWidth * density,
                text: item.text,
                fontSize: item.fontSize * density
            )
        }
    }

    // MARK: - dock 动作

    @objc func toolButtonTapped(_ sender: NSButton) {
        guard let tool = AnnotateTool(rawValue: sender.tag) else { return }
        commitTextInput()
        if isLiveMode, activeTool == tool {
            // 再次点击当前高亮工具可取消选中，回到内部直接拖动选区
            activeTool = nil
        } else {
            activeTool = tool
        }
        toolDock?.selectTool(tag: activeTool?.rawValue)
        if let loc = windows.first?.mouseLocationOutsideOfEventStream {
            let global = CGPoint(x: loc.x + (windows.first?.frame.minX ?? 0), y: loc.y + (windows.first?.frame.minY ?? 0))
            updateHoverCursor(at: global)
        }
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
            confirmAndFinish()
        case .cancel:
            finish(.canceled)
        }
    }

    // MARK: - 鼠标：选区与标注并行路由

    fileprivate func beginDrag(at globalPoint: CGPoint) {
        if !isLiveMode {
            beginAnnotateDrag(at: globalPoint)
            return
        }
        if let existing = selectionRect {
            switch SelectionEditing.hitTest(
                point: globalPoint,
                in: existing,
                handleSlop: Self.handleHitSlop,
                edgeOutset: Self.frameHitOutset,
                edgeInset: Self.frameHitInset
            ) {
            case .handle(let handle):
                commitTextInput()
                selectionDrag = .resize(handle: handle, original: existing)
                dragActive = true
                toolDock?.isHidden = true
                let cursor = cursorForHandle(handle)
                lockedDragCursor = cursor
                applyCursor(cursor)
                refresh()
                return
            case .frame:
                commitTextInput()
                selectionDrag = .move(startPoint: globalPoint, original: existing)
                dragActive = true
                toolDock?.isHidden = true
                lockedDragCursor = .closedHand
                applyCursor(.closedHand)
                refresh()
                return
            case .interior:
                if activeTool != nil {
                    beginAnnotateDrag(at: globalPoint)
                } else {
                    selectionDrag = .move(startPoint: globalPoint, original: existing)
                    dragActive = true
                    toolDock?.isHidden = true
                    lockedDragCursor = .closedHand
                    applyCursor(.closedHand)
                    refresh()
                }
                return
            case .none:
                break
            }
        }
        commitTextInput()
        selectionDrag = .create(anchor: globalPoint)
        dragActive = true
        selectionRect = nil
        toolDock?.isHidden = true
        lockedDragCursor = .crosshair
        applyCursor(.crosshair)
        refresh()
    }

    fileprivate func updateDrag(to globalPoint: CGPoint) {
        if let lockedDragCursor {
            applyCursor(lockedDragCursor)
        }
        if annotateDragStart != nil {
            updateAnnotateDrag(to: globalPoint)
            return
        }
        guard let selectionDrag else { return }
        applySelectionDrag(selectionDrag, to: globalPoint)
        refresh()
    }

    fileprivate func endDrag(at globalPoint: CGPoint) {
        if annotateDragStart != nil {
            endAnnotateDrag(at: globalPoint)
            lockedDragCursor = nil
            updateHoverCursor(at: globalPoint)
            return
        }
        guard let selectionDrag else { return }
        switch selectionDrag {
        case .create(let anchor):
            let rect = Self.rect(from: anchor, to: globalPoint)
            if rect.width >= Self.minimumSelectionSize, rect.height >= Self.minimumSelectionSize {
                selectionRect = rect
            } else {
                selectionRect = nil
            }
        case .move, .resize:
            applySelectionDrag(selectionDrag, to: globalPoint)
            if let rect = selectionRect,
               rect.width < Self.minimumSelectionSize || rect.height < Self.minimumSelectionSize {
                selectionRect = nil
            }
        }
        self.selectionDrag = nil
        dragActive = false
        lockedDragCursor = nil
        refresh()
        updateHoverCursor(at: globalPoint)
    }

    private func applySelectionDrag(_ kind: SelectionDragKind, to globalPoint: CGPoint) {
        switch kind {
        case .create(let anchor):
            selectionRect = Self.rect(from: anchor, to: globalPoint)
        case .move(let startPoint, let original):
            selectionRect = SelectionEditing.move(
                original,
                by: CGVector(dx: globalPoint.x - startPoint.x, dy: globalPoint.y - startPoint.y)
            )
        case .resize(let handle, let original):
            selectionRect = SelectionEditing.resize(
                original,
                handle: handle,
                to: globalPoint,
                minimumSize: Self.minimumSelectionSize
            )
        }
    }

    /// 悬停光标：拖拽期间锁定当前光标；悬停时按手柄/边框/内部态切换。
    fileprivate func updateHoverCursor(at globalPoint: CGPoint) {
        if let lockedDragCursor {
            applyCursor(lockedDragCursor)
            return
        }
        guard !dragActive else { return }
        if isPointOverToolDock(globalPoint) {
            applyCursor(.arrow)
            return
        }
        if !isLiveMode {
            applyCursor(activeTool == .text ? .iBeam : .crosshair)
            return
        }
        guard let selection = selectionRect else {
            applyCursor(.crosshair)
            return
        }
        switch SelectionEditing.hitTest(
            point: globalPoint,
            in: selection,
            handleSlop: Self.handleHitSlop,
            edgeOutset: Self.frameHitOutset,
            edgeInset: Self.frameHitInset
        ) {
        case .handle(let handle):
            applyCursor(cursorForHandle(handle))
        case .frame:
            applyCursor(.openHand)
        case .interior:
            if let tool = activeTool {
                applyCursor(tool == .text ? .iBeam : .crosshair)
            } else {
                applyCursor(.openHand)
            }
        case .none:
            applyCursor(.crosshair)
        }
    }

    private func cursorForHandle(_ handle: SelectionEditing.Handle) -> NSCursor {
        switch handle {
        case .top, .bottom:
            return .resizeUpDown
        case .left, .right:
            return .resizeLeftRight
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return .crosshair
        }
    }

    private func isPointOverToolDock(_ globalPoint: CGPoint) -> Bool {
        guard let dock = toolDock, !dock.isHidden, let hostWindow = dock.window else { return false }
        let globalFrame = dock.frame.offsetBy(dx: hostWindow.frame.minX, dy: hostWindow.frame.minY)
        return globalFrame.contains(globalPoint)
    }

    private func applyCursor(_ cursor: NSCursor) {
        if appliedCursor === cursor && NSCursor.current === cursor {
            return
        }
        appliedCursor = cursor
        cursor.set()
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
        guard let tool = activeTool,
              let selection = selectionRect,
              selection.contains(globalPoint) else { return }
        annotateDragStart = globalPoint
        annotateDragCurrent = globalPoint
        let cursor: NSCursor = tool == .text ? .iBeam : .crosshair
        lockedDragCursor = cursor
        applyCursor(cursor)
        if tool == .text {
            pendingTextOrigin = globalPoint
            return
        }
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
        guard let tool = activeTool else { return }
        if tool == .text {
            if let origin = pendingTextOrigin ?? annotateDragStart {
                beginTextInput(at: origin)
            }
            pendingTextOrigin = nil
            return
        }
        guard let start = annotateDragStart else { return }
        let end = clampToSelection(globalPoint)
        guard let annotation = makeDraft(tool: tool, from: start, to: end) else {
            refresh()
            return
        }
        let minSpan: CGFloat = tool == .line || tool == .arrow ? 4 : 6
        if annotation.globalRect.width < minSpan && annotation.globalRect.height < minSpan,
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

    private func makeDraft(tool: AnnotateTool, from globalStart: CGPoint, to globalEnd: CGPoint) -> OverlayAnnotation? {
        let p0 = clampToSelection(globalStart)
        let p1 = clampToSelection(globalEnd)
        let rect = CGRect(
            x: min(p0.x, p1.x),
            y: min(p0.y, p1.y),
            width: max(abs(p1.x - p0.x), 1),
            height: max(abs(p1.y - p0.y), 1)
        )
        switch tool {
        case .rectangle:
            return OverlayAnnotation(
                kind: .rectangle,
                globalRect: rect,
                color: strokeColor,
                lineWidth: strokePreset.lineWidth,
                fontSize: 16
            )
        case .mosaic:
            return OverlayAnnotation(
                kind: .mosaic,
                globalRect: rect,
                color: strokeColor,
                lineWidth: strokePreset.mosaicBlockPoints,
                fontSize: 16
            )
        case .line:
            return OverlayAnnotation(
                kind: .line,
                globalRect: rect,
                startPoint: p0,
                endPoint: p1,
                color: strokeColor,
                lineWidth: strokePreset.lineWidth,
                fontSize: 16
            )
        case .arrow:
            return OverlayAnnotation(
                kind: .arrow,
                globalRect: rect,
                startPoint: p0,
                endPoint: p1,
                color: strokeColor,
                lineWidth: strokePreset.lineWidth,
                fontSize: 16
            )
        case .text:
            let textRect = CGRect(x: p0.x, y: p0.y - 20, width: 220, height: 32)
            return OverlayAnnotation(
                kind: .text,
                globalRect: textRect,
                color: strokeColor,
                lineWidth: strokePreset.lineWidth,
                text: "",
                fontSize: 16
            )
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
        guard !text.isEmpty, let origin,
              var annotation = makeDraft(tool: .text, from: origin, to: origin) else {
            refresh()
            return
        }
        annotation.text = text
        let width = max(120, CGFloat(text.count) * annotation.fontSize * 0.7)
        annotation.globalRect = CGRect(x: origin.x, y: origin.y - 14, width: width, height: 28)
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

    // MARK: - chrome 布局

    private func layoutChrome() {
        guard let selection = selectionRect else {
            toolDock?.isHidden = true
            return
        }
        guard !dragActive else {
            toolDock?.isHidden = true
            return
        }
        ensureToolDock()
        layoutToolDock(selection: selection)
    }

    private func ensureToolDock() {
        guard toolDock == nil else { return }
        toolDock = AnnotateToolDock(
            target: self,
            selectedToolTag: activeTool?.rawValue,
            selectedColorIndex: Self.palette.firstIndex(of: strokeColor) ?? 0,
            selectedStrokeTag: strokePreset.rawValue
        )
        toolDock?.updateHistoryEnabled(canUndo: !annotations.isEmpty, canRedo: !redoStack.isEmpty)
    }

    private func layoutToolDock(selection: CGRect) {
        guard let dock = toolDock else { return }
        let size = dock.fittingSize
        placeDock(dock, selection: selection, size: size)
    }

    /// 优先选区底部外侧右对齐；底部不够则翻到顶部外侧；都不够则贴选区底部内侧。
    private func placeDock(_ dock: NSView, selection: CGRect, size: CGSize) {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let hostScreen = NSScreen.screens.first {
            $0.frame.contains(CGPoint(x: selection.midX, y: selection.midY))
        }
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
        layoutChrome()
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

        // 实时模式：先画定格全屏底图，再盖半透明遮罩（选区内挖空保留原图）
        if case .live(let snapshots, _) = mode,
           let snap = snapshots.first(where: { $0.frame == screenFrame }) {
            drawCapturedImage(snap.image, in: bounds)
        }

        NSColor(srgbRed: 10 / 255, green: 14 / 255, blue: 22 / 255, alpha: 0.48).setFill()
        if let local = localSelection, isLiveMode {
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

        if isLiveMode {
            drawHintPill(in: bounds, hasSelection: selectionRect != nil && !dragActive)
        }

        guard let sel = localSelection else { return }

        if case .annotateOnly(let captured) = mode {
            drawCapturedImage(captured.image, in: sel)
        }

        // 标注裁切在选区内绘制：选区缩放或移动时，已画标注锚定在屏幕原位，超出选区部分自动裁掉
        if let cg = NSGraphicsContext.current?.cgContext {
            cg.saveGState()
            NSBezierPath(rect: sel).addClip()
            drawAnnotationsOverlay(screenFrame: screenFrame)
            if let start = annotateDragStart, let current = annotateDragCurrent,
               let tool = activeTool, tool != .text {
                drawDraftOverlay(tool: tool, from: start, to: current, screenFrame: screenFrame)
            }
            cg.restoreGState()
        }

        // 加粗明黄选框
        let ring = NSColor(srgbRed: 250 / 255, green: 204 / 255, blue: 21 / 255, alpha: 0.95)
        ring.setStroke()
        let half = Self.selectionBorderWidth / 2
        let borderPath = NSBezierPath(rect: sel.insetBy(dx: -half, dy: -half))
        borderPath.lineWidth = Self.selectionBorderWidth
        borderPath.stroke()

        // 实时模式下始终展示 8 向手柄与尺寸 HUD，随时可与标注并行调整选区
        if isLiveMode {
            drawHandles(around: sel)
            drawSizeHUD(for: sel, in: bounds)
        }
    }

    /// 合成后的 CGImage 已是正向；遮罩视图的 CTM 与之同向，不再额外翻 Y。
    private func drawCapturedImage(_ image: CGImage, in rect: CGRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.saveGState()
        cg.interpolationQuality = .high
        cg.draw(image, in: rect)
        cg.restoreGState()
    }

    private func drawAnnotationsOverlay(screenFrame: CGRect) {
        for annotation in annotations {
            drawAnnotation(annotation, screenFrame: screenFrame)
        }
    }

    private func drawDraftOverlay(tool: AnnotateTool, from start: CGPoint, to end: CGPoint, screenFrame: CGRect) {
        guard let draft = makeDraft(tool: tool, from: start, to: end) else { return }
        drawAnnotation(draft, screenFrame: screenFrame)
    }

    private func drawAnnotation(_ annotation: OverlayAnnotation, screenFrame: CGRect) {
        let color = NSColor(
            srgbRed: annotation.color.r,
            green: annotation.color.g,
            blue: annotation.color.b,
            alpha: annotation.color.a
        )
        func toLocal(_ global: CGPoint) -> CGPoint {
            CGPoint(x: global.x - screenFrame.minX, y: global.y - screenFrame.minY)
        }
        func toLocalRect(_ globalRect: CGRect) -> CGRect {
            globalRect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        }

        switch annotation.kind {
        case .rectangle:
            let rect = toLocalRect(annotation.globalRect)
            color.withAlphaComponent(0.08).setFill()
            rect.fill()
            color.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = annotation.lineWidth
            path.stroke()
        case .mosaic:
            drawMosaicOverlay(
                globalRect: annotation.globalRect,
                blockPoints: annotation.lineWidth,
                screenFrame: screenFrame
            )
        case .line:
            guard let start = annotation.startPoint, let end = annotation.endPoint else { return }
            color.setStroke()
            let path = NSBezierPath()
            path.move(to: toLocal(start))
            path.line(to: toLocal(end))
            path.lineWidth = annotation.lineWidth
            path.lineCapStyle = .round
            path.stroke()
        case .arrow:
            guard let start = annotation.startPoint, let end = annotation.endPoint else { return }
            drawArrow(from: toLocal(start), to: toLocal(end), color: color, strokeWidth: annotation.lineWidth)
        case .text:
            let localRect = toLocalRect(annotation.globalRect)
            let text = annotation.text ?? ""
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: max(annotation.fontSize, 10), weight: .semibold),
                .foregroundColor: color,
            ]
            (text as NSString).draw(at: localRect.origin, withAttributes: attrs)
        }
    }

    /// 在视图坐标系画真实像素马赛克（采样全屏/单图底图）。
    private func drawMosaicOverlay(globalRect: CGRect, blockPoints: CGFloat, screenFrame: CGRect) {
        let probe = CGPoint(x: screenFrame.midX, y: screenFrame.midY)
        guard let source = pixelSource(containing: probe) else { return }
        let clippedGlobal = globalRect.intersection(source.frame)
        guard !clippedGlobal.isNull, clippedGlobal.width > 0, clippedGlobal.height > 0 else { return }

        let scaleX = CGFloat(source.width) / max(source.frame.width, 1)
        let scaleY = CGFloat(source.height) / max(source.frame.height, 1)
        let density = max(scaleX, scaleY)
        let blockSize = max(4, Int((blockPoints * density).rounded()))
        let block = CGFloat(blockSize)

        let area = CGRect(
            x: (clippedGlobal.minX - source.frame.minX) * scaleX,
            y: (source.frame.maxY - clippedGlobal.maxY) * scaleY,
            width: clippedGlobal.width * scaleX,
            height: clippedGlobal.height * scaleY
        ).intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard area.width > 0, area.height > 0 else { return }

        let startBlockX = Int(floor(area.minX / block)) * blockSize
        let endX = Int(ceil(area.maxX))
        let startBlockY = Int(floor(area.minY / block)) * blockSize
        let endY = Int(ceil(area.maxY))

        func pixelToLocal(_ px: CGPoint) -> CGPoint {
            let gx = source.frame.minX + px.x / scaleX
            let gy = source.frame.maxY - px.y / scaleY
            return CGPoint(x: gx - screenFrame.minX, y: gy - screenFrame.minY)
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
                    let tl = pixelToLocal(CGPoint(x: region.minX, y: region.minY))
                    let br = pixelToLocal(CGPoint(x: region.maxX, y: region.maxY))
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
        let radius: CGFloat = 5
        for (_, center) in SelectionEditing.handlePositions(in: sel) {
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            let dot = NSBezierPath(ovalIn: rect)
            NSColor.white.setFill()
            dot.fill()
            NSColor.black.withAlphaComponent(0.35).setStroke()
            let outline = NSBezierPath(ovalIn: rect)
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

    private func drawHintPill(in bounds: CGRect, hasSelection: Bool) {
        struct Segment {
            let text: String
            let isKey: Bool
        }
        let segments: [Segment] = hasSelection
            ? [
                Segment(text: "拖边框/内部移动 · 拖手柄缩放 · 选工具标注", isKey: false),
                Segment(text: "⏎", isKey: true),
                Segment(text: "完成", isKey: false),
                Segment(text: "⎋", isKey: true),
                Segment(text: "取消", isKey: false),
            ]
            : [
                Segment(text: "拖拽框选区域", isKey: false),
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
        animationBehavior = .none
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
    private var trackingArea: NSTrackingArea?

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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.cursorUpdate, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    /// 接管系统光标更新，避免 AppKit 在重绘或跨子视图时偷偷重置回默认箭头。
    override func cursorUpdate(with event: NSEvent) {
        controller.updateHoverCursor(at: globalLocation(of: event))
    }

    override func resetCursorRects() {
        // 不调用 super，防止 AppKit 添加默认 arrow cursor rect。
    }

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

    override func mouseMoved(with event: NSEvent) {
        controller.updateHoverCursor(at: globalLocation(of: event))
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

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    private static let brandYellow = NSColor(srgbRed: 250 / 255, green: 204 / 255, blue: 21 / 255, alpha: 1)
    private static let darkInk = NSColor(srgbRed: 24 / 255, green: 24 / 255, blue: 27 / 255, alpha: 1)

    init(
        target: SelectionOverlayController,
        selectedToolTag: Int?,
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

    func selectTool(tag: Int?) {
        for button in toolButtons {
            let on = tag.map { button.tag == $0 } ?? false
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
