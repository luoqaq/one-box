import SwiftUI
import ToolLauncherUI
import Annotation

// MARK: - 标注编辑器（原型 view-annotation：深色 studio）

public struct AnnotationStudioView: View {
    let baseImage: CGImage
    let imageTitle: String
    let onBack: () -> Void
    let onRetake: () -> Void
    /// 导出 PNG 后由外壳处理（复制 / 保存），UI 只负责渲染和编辑。
    let onExport: (_ png: Data, _ action: ExportAction) -> Void

    public enum ExportAction {
        case copy
        case save
    }

    public enum StudioTool: String, CaseIterable {
        case select = "选择"
        case arrow = "箭头"
        case rectangle = "矩形"
        case text = "文字"
        case mosaic = "打码"
    }

    @State private var tool: StudioTool = .arrow
    @State private var color = AnnotationColor(hex: "#ff453a")
    @State private var strokeWidth: CGFloat = 4
    @State private var annotations: [Annotation] = []
    @State private var redoStack: [Annotation] = []
    @State private var selectedAnnotationID: UUID?
    @State private var draftText = ""
    @State private var zoom: CGFloat = 1
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var exportError: String?

    public init(
        baseImage: CGImage,
        imageTitle: String = "截图",
        onBack: @escaping () -> Void,
        onRetake: @escaping () -> Void,
        onExport: @escaping (_ png: Data, _ action: ExportAction) -> Void
    ) {
        self.baseImage = baseImage
        self.imageTitle = imageTitle
        self.onBack = onBack
        self.onRetake = onRetake
        self.onExport = onExport
    }

    private var selectedAnnotation: Annotation? {
        annotations.first { $0.id == selectedAnnotationID }
    }

    public var body: some View {
        VStack(spacing: 0) {
            topbar
            HStack(spacing: 0) {
                canvasArea
                inspector
            }
            bottombar
        }
        .frame(minWidth: 1080, minHeight: 700)
        .background(OB.studioWindow)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OB.studioBorder, lineWidth: 0.5)
        )
        .preferredColorScheme(.dark)
        .tint(OB.brandYellow)
    }

    // MARK: 顶栏（50pt）

    private var topbar: some View {
        ZStack {
            OB.studioBar.allowsHitTesting(false)
            WindowDragRegion()
            HStack {
                HStack(spacing: 12) {
                    TrafficDots()
                    Text("标注编辑")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(OB.studioInk)
                        .allowsHitTesting(false)
                    Text("\(baseImage.width) × \(baseImage.height) · PNG")
                        .font(.system(size: 11.5).monospaced())
                        .foregroundColor(OB.studioInk3)
                        .allowsHitTesting(false)
                }
                Spacer(minLength: 0).allowsHitTesting(false)
                // 工具条
                HStack(spacing: 2) {
                    studioToolButton(.select, icon: .arrowUpRight)
                    studioToolButton(.arrow, icon: .arrowUpRight)
                    studioToolButton(.rectangle, icon: .rect)
                    studioToolButton(.text, icon: .typeT)
                    studioToolButton(.mosaic, icon: .mosaic)
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(OB.studioSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(OB.studioSeparator, lineWidth: 0.5)
                )
                Spacer(minLength: 0).allowsHitTesting(false)
                HStack(spacing: 6) {
                    studioIconButton(.undo, title: "撤销") { undo() }
                    studioIconButton(.redo, title: "重做") { redo() }
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 50)
        .overlay(alignment: .bottom) { Divider().overlay(OB.studioSeparator) }
    }

    private func studioToolButton(_ t: StudioTool, icon: OBIcon.ID) -> some View {
        Button {
            tool = t
            selectedAnnotationID = nil
        } label: {
            HStack(spacing: 5) {
                OBIcon(icon, size: 14, weight: 1.65)
                Text(t.rawValue)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(tool == t ? OB.studioInk : OB.studioInk2)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tool == t ? OB.studioSurfaceHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func studioIconButton(_ icon: OBIcon.ID, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            OBIcon(icon, size: 15, weight: 1.65)
                .foregroundColor(OB.studioInk2)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }

    // MARK: 画布区

    private var canvasArea: some View {
        GeometryReader { geo in
            let fitted = fitSize(in: geo.size)
            let scale = fitted.width > 0 ? CGFloat(baseImage.width) / fitted.width : 1

            ZStack {
                // 点阵底
                Canvas { context, size in
                    let dot: CGFloat = 18
                    let r: CGFloat = 0.5
                    var y: CGFloat = r
                    while y < size.height {
                        var x: CGFloat = r
                        while x < size.width {
                            context.fill(
                                Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                with: .color(Color.white.opacity(0.045))
                            )
                            x += dot
                        }
                        y += dot
                    }
                }

                // 画板
                ZStack {
                    Image(decorative: baseImage, scale: 1)
                        .resizable()
                        .frame(width: fitted.width, height: fitted.height)

                    // 标注层（显示坐标 = 像素坐标 / scale）
                    AnnotationOverlayView(
                        annotations: annotations,
                        scale: scale,
                        selectedID: selectedAnnotationID
                    )
                    .allowsHitTesting(false)

                    // 草稿标注
                    if let start = dragStart, let current = dragCurrent, tool != .select {
                        let draft = draftAnnotation(from: start, to: current, scale: scale)
                        AnnotationOverlayView(
                            annotations: [draft],
                            scale: scale,
                            selectedID: nil
                        )
                        .allowsHitTesting(false)
                    }
                }
                .frame(width: fitted.width, height: fitted.height)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                )
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if tool == .select { return }
                            if dragStart == nil {
                                dragStart = value.startLocation
                                // 点击选中已有标注
                                if tool == .select { return }
                            }
                            dragCurrent = value.location
                        }
                        .onEnded { value in
                            defer {
                                dragStart = nil
                                dragCurrent = nil
                            }
                            guard tool != .select else { return }
                            let annotation = draftAnnotation(from: value.startLocation, to: value.location, scale: scale)
                            guard annotation.rect.width >= 6 || annotation.kind == .text else { return }
                            if annotation.kind == .arrow,
                               annotation.startPoint == annotation.endPoint { return }
                            annotations.append(annotation)
                            redoStack.removeAll()
                            selectedAnnotationID = annotation.kind == .text ? annotation.id : nil
                            if annotation.kind == .text { draftText = "" }
                        }
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(26)
        .background(OB.studioCanvas)
    }

    /// 按画布尺寸适配图片显示大小（保持比例，留边）。
    private func fitSize(in container: CGSize) -> CGSize {
        guard baseImage.width > 0, baseImage.height > 0,
              container.width > 0, container.height > 0 else {
            return CGSize(width: 400, height: 300)
        }
        let inset = CGSize(width: 52, height: 52)
        let avail = CGSize(width: max(60, container.width - inset.width),
                           height: max(60, container.height - inset.height))
        let ratio = min(avail.width / CGFloat(baseImage.width),
                        avail.height / CGFloat(baseImage.height))
        return CGSize(width: CGFloat(baseImage.width) * ratio,
                      height: CGFloat(baseImage.height) * ratio)
    }

    /// 拖拽（显示坐标）→ 标注（像素坐标）。
    private func draftAnnotation(from start: CGPoint, to end: CGPoint, scale: CGFloat) -> Annotation {
        let p0 = CGPoint(x: start.x * scale, y: start.y * scale)
        let p1 = CGPoint(x: end.x * scale, y: end.y * scale)
        let rect = CGRect(
            x: min(p0.x, p1.x), y: min(p0.y, p1.y),
            width: max(abs(p1.x - p0.x), 1), height: max(abs(p1.y - p0.y), 1)
        )
        switch tool {
        case .select:
            return Annotation(kind: .rectangle, rect: rect, color: color, strokeWidth: strokeWidth, text: nil)
        case .arrow:
            return Annotation(kind: .arrow, rect: rect, startPoint: p0, endPoint: p1,
                               color: color, strokeWidth: strokeWidth, text: nil)
        case .rectangle:
            return Annotation(kind: .rectangle, rect: rect, color: color, strokeWidth: strokeWidth, text: nil)
        case .text:
            let textRect = rect.width < 24 && rect.height < 24
                ? CGRect(x: p0.x, y: p0.y, width: 220, height: 40)
                : CGRect(x: rect.minX, y: rect.minY, width: max(rect.width, 120), height: max(rect.height, 34))
            return Annotation(kind: .text, rect: textRect, color: color, strokeWidth: strokeWidth,
                              text: draftText.isEmpty ? "双击右侧输入文字" : draftText)
        case .mosaic:
            return Annotation(kind: .mosaic, rect: rect, color: color, strokeWidth: strokeWidth, text: nil)
        }
    }

    // MARK: 检查器（224pt）

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 当前工具
                VStack(alignment: .leading, spacing: 10) {
                    insLabel("当前工具", trailing: tool.rawValue)
                    HStack(spacing: 9) {
                        swatch("#ff453a")
                        swatch("#0a84ff")
                        swatch("#ffd60a")
                        swatch("#30d158")
                        swatch("#ffffff")
                    }
                }
                insDivider

                // 线条粗细
                VStack(alignment: .leading, spacing: 10) {
                    insLabel("线条粗细", trailing: strokeLabel)
                    HStack(spacing: 6) {
                        strokeOption(2.5, label: "细 · 2.5pt", height: 2)
                        strokeOption(4, label: "中 · 4pt", height: 4)
                        strokeOption(6.5, label: "粗 · 6.5pt", height: 6)
                    }
                }
                insDivider

                // 文字样式 / 文本编辑
                VStack(alignment: .leading, spacing: 10) {
                    insLabel("文字样式")
                    insKV("字号", "13 pt")
                    insKV("底色", "深色胶囊")
                    if selectedAnnotation?.kind == .text {
                        TextField("输入标注文字…", text: $draftText, onCommit: commitText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                            .onAppear {
                                draftText = selectedAnnotation?.text ?? ""
                            }
                    }
                }
                insDivider

                // 图层
                VStack(alignment: .leading, spacing: 6) {
                    insLabel("图层", trailing: "\(annotations.count)")
                    ForEach(Array(annotations.enumerated().reversed()), id: \.element.id) { idx, annotation in
                        Button {
                            selectedAnnotationID = annotation.id
                            tool = .select
                            if annotation.kind == .text { draftText = annotation.text ?? "" }
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(red: annotation.color.r,
                                                green: annotation.color.g,
                                                blue: annotation.color.b))
                                    .frame(width: 7, height: 7)
                                Text(layerName(annotation))
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.78))
                                Spacer()
                                if selectedAnnotationID == annotation.id {
                                    OBIcon(.close, size: 11, weight: 1.65)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedAnnotationID == annotation.id ? OB.brandYellowSoft : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("删除该标注") { removeAnnotation(at: idx) }
                        }
                    }
                    if annotations.isEmpty {
                        Text("拖拽画布创建标注")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
            }
            .padding(EdgeInsets(top: 16, leading: 14, bottom: 16, trailing: 14))
        }
        .frame(width: 224)
        .background(OB.studioPanel)
        .overlay(alignment: .leading) { Divider().overlay(OB.studioSeparator) }
    }

    private var strokeLabel: String {
        switch strokeWidth {
        case 2.5: return "细 · 2.5pt"
        case 6.5: return "粗 · 6.5pt"
        default: return "中 · 4pt"
        }
    }

    private func layerName(_ annotation: Annotation) -> String {
        switch annotation.kind {
        case .arrow: return "箭头"
        case .line: return "直线"
        case .rectangle: return "矩形框"
        case .text: return "文字标注"
        case .mosaic: return "打码"
        }
    }

    private func swatch(_ hex: String) -> some View {
        let c = AnnotationColor(hex: hex)
        let isActive = abs(c.r - color.r) < 0.01 && abs(c.g - color.g) < 0.01 && abs(c.b - color.b) < 0.01
        return Button {
            color = c
        } label: {
            ZStack {
                if isActive {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .frame(width: 24, height: 24)
                }
                Circle()
                    .fill(Color(red: c.r, green: c.g, blue: c.b))
                    .frame(width: isActive ? 16 : 20, height: isActive ? 16 : 20)
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                    )
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
    }

    private func strokeOption(_ value: CGFloat, label: String, height: CGFloat) -> some View {
        Button {
            strokeWidth = value
        } label: {
            RoundedRectangle(cornerRadius: 7)
                .fill(strokeWidth == value ? Color.white.opacity(0.14) : Color.white.opacity(0.05))
                .frame(height: 30)
                .overlay(
                    Capsule()
                        .fill(Color.white.opacity(0.88))
                        .frame(width: 22, height: height)
                )
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private func insLabel(_ title: String, trailing: String? = nil) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.62))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
    }

    private func insKV(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(.system(size: 12)).foregroundColor(.white.opacity(0.78))
            Spacer()
            Text(value).font(.system(size: 11.5)).foregroundColor(.white.opacity(0.58))
        }
    }

    private var insDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 0.5)
    }

    // MARK: 底栏（46pt）

    private var bottombar: some View {
        HStack {
            HStack(spacing: 6) {
                studioIconButton(.minus, title: "缩小") { zoom = max(0.25, zoom - 0.25) }
                Text("\(Int(zoom * 100))%")
                    .font(.system(size: 12).monospaced())
                    .foregroundColor(.white.opacity(0.55))
                studioIconButton(.plus, title: "放大") { zoom = min(3, zoom + 0.25) }
            }
            Spacer()
            HStack(spacing: 6) {
                Button {
                    onBack()
                } label: {
                    Text("返回列表")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.72))
                        .frame(height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    onRetake()
                } label: {
                    HStack(spacing: 6) {
                        Text("重截")
                            .font(.system(size: 12.5, weight: .medium))
                        Kbd(text: "R", dark: true)
                    }
                    .foregroundColor(.white.opacity(0.72))
                    .frame(height: 30)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r")

                Button {
                    export(.save)
                } label: {
                    HStack(spacing: 6) {
                        Text("保存")
                            .font(.system(size: 12.5, weight: .medium))
                        Kbd(text: "⌘S", dark: true)
                    }
                    .foregroundColor(OB.studioInk)
                    .frame(height: 30)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(OB.studioSurfaceHover)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("s", modifiers: .command)

                Button {
                    export(.copy)
                } label: {
                    HStack(spacing: 6) {
                        Text("复制")
                            .font(.system(size: 12.5, weight: .semibold))
                        Kbd(text: "⌘↩")
                    }
                    .foregroundColor(OB.ink)
                    .frame(height: 30)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(OB.brandYellow)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(OB.studioBar)
        .overlay(alignment: .top) { Divider().overlay(OB.studioSeparator) }
    }

    // MARK: 编辑操作

    private func undo() {
        guard let last = annotations.popLast() else { return }
        redoStack.append(last)
        selectedAnnotationID = nil
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        annotations.append(next)
    }

    private func removeAnnotation(at index: Int) {
        guard annotations.indices.contains(index) else { return }
        if annotations[index].id == selectedAnnotationID { selectedAnnotationID = nil }
        annotations.remove(at: index)
    }

    private func commitText() {
        guard let id = selectedAnnotationID,
              let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[idx].text = draftText.isEmpty ? " " : draftText
    }

    private func export(_ action: ExportAction) {
        do {
            let data = try AnnotationRenderer.pngData(base: baseImage, annotations: annotations)
            onExport(data, action)
        } catch {
            exportError = "标注渲染失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 窗口红绿灯（接近系统 12pt；传入 onClose 时可点，否则仅装饰）

struct TrafficDots: View {
    var onClose: (() -> Void)? = nil
    /// 视觉直径；系统红绿灯约 12pt。
    var diameter: CGFloat = 12

    private var isInteractive: Bool { onClose != nil }

    var body: some View {
        HStack(spacing: 8) {
            trafficDot(color: Color(hex: 0xFF5F57), help: "关闭", action: onClose)
            trafficDot(color: Color(hex: 0xFEBC2E), help: "最小化") {
                NSApp.keyWindow?.miniaturize(nil)
            }
            trafficDot(color: Color(hex: 0x28C840), help: "缩放") {
                NSApp.keyWindow?.zoom(nil)
            }
        }
        .allowsHitTesting(isInteractive)
    }

    @ViewBuilder
    private func trafficDot(color: Color, help: String, action: (() -> Void)?) -> some View {
        let dot = Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .frame(width: 20, height: 20)
            .contentShape(Circle())

        if isInteractive, let action {
            Button(action: action) { dot }
                .buttonStyle(.plain)
                .help(help)
        } else {
            dot
        }
    }
}

// MARK: - 标注实时预览层

/// 把像素坐标标注按 1/scale 缩小为显示坐标并绘制。
struct AnnotationOverlayView: View {
    let annotations: [Annotation]
    let scale: CGFloat
    let selectedID: UUID?

    var body: some View {
        Canvas { context, size in
            for annotation in annotations {
                let s = 1 / scale
                let rect = CGRect(
                    x: annotation.rect.minX * s,
                    y: annotation.rect.minY * s,
                    width: annotation.rect.width * s,
                    height: annotation.rect.height * s
                )
                let color = Color(red: annotation.color.r, green: annotation.color.g,
                                  blue: annotation.color.b, opacity: annotation.color.a)
                let cg = CGColor(red: annotation.color.r, green: annotation.color.g,
                                 blue: annotation.color.b, alpha: annotation.color.a)

                switch annotation.kind {
                case .arrow:
                    guard let start = annotation.startPoint, let end = annotation.endPoint else { continue }
                    let p0 = CGPoint(x: start.x * s, y: start.y * s)
                    let p1 = CGPoint(x: end.x * s, y: end.y * s)
                    drawArrow(&context, from: p0, to: p1, color: color, strokeWidth: annotation.strokeWidth)

                case .line:
                    guard let start = annotation.startPoint, let end = annotation.endPoint else { continue }
                    let p0 = CGPoint(x: start.x * s, y: start.y * s)
                    let p1 = CGPoint(x: end.x * s, y: end.y * s)
                    var path = Path()
                    path.move(to: p0)
                    path.addLine(to: p1)
                    context.stroke(path, with: .color(color),
                                   style: StrokeStyle(lineWidth: annotation.strokeWidth, lineCap: .round))

                case .rectangle:
                    let path = Path(roundedRect: rect, cornerRadius: 4)
                    context.fill(path, with: .color(color.opacity(0.06)))
                    context.stroke(path, with: .color(color),
                                  style: StrokeStyle(lineWidth: annotation.strokeWidth))

                case .text:
                    let text = annotation.text ?? ""
                    context.draw(
                        Text(verbatim: text)
                            .font(.system(size: annotation.fontSize, weight: .semibold))
                            .foregroundColor(color),
                        at: CGPoint(x: rect.minX, y: rect.minY + 10),
                        anchor: .leading
                    )

                case .mosaic:
                    // 预览层画半透明灰块示意，导出时是像素级打码
                    let path = Path(rect)
                    context.fill(path, with: .color(color.opacity(0.55)))
                }

                if annotation.id == selectedID {
                    let sel = Path(rect.insetBy(dx: -4, dy: -4))
                    context.stroke(sel, with: .color(OB.brandYellow.opacity(0.9)),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func drawArrow(_ context: inout GraphicsContext, from: CGPoint, to: CGPoint,
                           color: Color, strokeWidth: CGFloat) {
        guard let geo = AnnotationArrowGeometry(from: from, to: to, strokeWidth: strokeWidth) else { return }
        var shaft = Path()
        shaft.move(to: from)
        shaft.addLine(to: geo.shaftEnd)
        context.stroke(shaft, with: .color(color),
                       style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))

        var head = Path()
        head.move(to: geo.tip)
        head.addLine(to: geo.leftWing)
        head.addLine(to: geo.neck)
        head.addLine(to: geo.rightWing)
        head.closeSubpath()
        context.fill(head, with: .color(color))
    }
}
