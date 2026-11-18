import SwiftUI
import AppKit

// MARK: - 窗口拖动区（NSHostingView 默认不转发背景拖动）

/// 铺满父视图；`mouseDown` 转给 `NSWindow.performDrag`（比 `mouseDownCanMoveWindow` 可靠）。
/// 放在 ZStack 最底层，交互控件叠在上面；标题/Spacer 建议 `.allowsHitTesting(false)` 以便从文字处也能拖。
public struct WindowDragRegion: View {
    public init() {}

    public var body: some View {
        DragNSRepr()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .allowsHitTesting(true)
    }
}

private struct DragNSRepr: NSViewRepresentable {
    func makeNSView(context: Context) -> DragNSView { DragNSView() }
    func updateNSView(_ nsView: DragNSView, context: Context) {}
}

private final class DragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - 颜色（方案 B：黑白极简主控件 + 明黄点缀）

public enum OB {
    // MARK: 中性文字
    public static let ink = Color(hex: 0x18181B)
    /// 次级文字：略加深，避免玻璃底上发灰发虚。
    public static let ink2 = Color(hex: 0x52525B)
    public static let ink3 = Color(hex: 0x71717A)

    // MARK: 中性表面与边框（统一炭灰阶梯，避免各处散落不同透明度）
    public static let hairline = Color(red: 24/255, green: 24/255, blue: 27/255, opacity: 0.08)
    public static let borderStrong = Color(red: 24/255, green: 24/255, blue: 27/255, opacity: 0.14)
    public static let surfaceSubtle = Color(red: 24/255, green: 24/255, blue: 27/255, opacity: 0.04)
    public static let surfaceHover = Color(red: 24/255, green: 24/255, blue: 27/255, opacity: 0.065)
    public static let surfaceActive = Color(red: 24/255, green: 24/255, blue: 27/255, opacity: 0.095)
    public static let btnFill = surfaceHover
    public static let scrim = Color(red: 24/255, green: 24/255, blue: 27/255, opacity: 0.24)
    public static let cardSurface = Color.white.opacity(0.86)
    public static let modalSurface = Color.white.opacity(0.94)
    public static let previewBg = Color(hex: 0xF5F5F7)

    // MARK: 主强调色（黑白极简主控件）
    public static let accent = Color(hex: 0x18181B)
    public static let accentInk = Color(hex: 0x18181B)
    public static let accentSoft = Color(red: 24/255, green: 24/255, blue: 27/255, opacity: 0.075)

    // MARK: 品牌点缀黄（呼应黄白 Logo，仅用于小面积焦点、指示条、状态点与徽章）
    public static let brandYellow = Color(hex: 0xFACC15)
    public static let brandYellowInk = Color(hex: 0xA16207)
    public static let brandYellowSoft = Color(red: 250/255, green: 204/255, blue: 21/255, opacity: 0.18)

    // MARK: 语义状态色
    public static let green = Color(hex: 0x1D9A54)
    public static let greenSoft = Color(red: 29/255, green: 154/255, blue: 84/255, opacity: 0.11)
    public static let orange = Color(hex: 0xD97706)
    public static let red = Color(hex: 0xD93025)
    public static let redSoft = Color(red: 217/255, green: 48/255, blue: 37/255, opacity: 0.10)

    /// 玻璃面板底色：略提高不透明度，减轻文字/细线在材质上的发虚感。
    public static let glass = Color.white.opacity(0.88)
    public static let glassBar1 = Color.white.opacity(0.55)
    public static let glassBar2 = Color.white.opacity(0.36)
    public static let glassFooter = Color.white.opacity(0.48)
    public static let glassHeader = Color.white.opacity(0.52)
    public static let sidebarBg = Color(red: 244/255, green: 244/255, blue: 246/255, opacity: 0.78)
    public static let contentBg = Color(red: 250/255, green: 250/255, blue: 252/255, opacity: 0.92)
    public static let configScroll = Color(red: 250/255, green: 250/255, blue: 252/255, opacity: 0.80)

    /// 标注画布（深色）
    public static let studioBg = Color(hex: 0x111215)
    public static let studioWindow = Color(hex: 0x16181D)
    public static let studioPanel = Color(hex: 0x16181D)
    public static let studioBar = Color(hex: 0x1B1D24)
    public static let studioCanvas = Color(hex: 0x111215)
    public static let studioSeparator = Color.white.opacity(0.08)
    public static let studioInk = Color.white
    public static let studioInk2 = Color.white.opacity(0.76)
    public static let studioInk3 = Color.white.opacity(0.54)
    public static let studioSurface = Color.white.opacity(0.06)
    public static let studioSurfaceHover = Color.white.opacity(0.12)
    public static let studioBorder = Color.white.opacity(0.12)

    /// 桌面背景（中性暖灰渐变）
    public static let desktopGradient = LinearGradient(
        colors: [Color(hex: 0xECEEF0), Color(hex: 0xE3E6EA), Color(hex: 0xEAECEF)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

extension Color {
    public init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// 解析工具描述里的 fgHex / bgHex（支持 8 位 RRGGBBAA 或 6 位 RRGGBB）。
    public init(flexibleHex: String) {
        let s = flexibleHex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        let value = UInt64(s, radix: 16) ?? 0x8A919E
        if s.count == 8 {
            let r = Double((value >> 24) & 0xFF) / 255
            let g = Double((value >> 16) & 0xFF) / 255
            let b = Double((value >> 8) & 0xFF) / 255
            let a = Double(value & 0xFF) / 255
            self.init(.sRGB,
                      red: r,
                      green: g,
                      blue: b,
                      opacity: a)
        } else {
            self.init(hex: UInt32(truncatingIfNeeded: value))
        }
    }
}

// MARK: - 玻璃面板

/// 玻璃面板：material + 半透明白；白层略实，避免正文/小图标对比度被吃掉。
public struct GlassPanelBackground: View {

    public init() {}
    public var body: some View {
        ZStack {
            Rectangle().fill(.thinMaterial)
            Rectangle().fill(Color.white.opacity(0.88))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.72), lineWidth: 0.5)
        )
        .shadow(color: Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.20),
                radius: 28, x: 0, y: 24)
        .shadow(color: Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.06),
                radius: 6, x: 0, y: 4)
    }
}

// MARK: - 按键 kbd

/// 原型 .kbd：高 20 圆角 5、浅灰底、等宽字体。
public struct Kbd: View {

    public init(text: String, dark: Bool = false) {
        self.text = text
        self.dark = dark
    }
    public let text: String
    public var dark: Bool = false

    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium).monospaced())
            .foregroundColor(dark ? .white.opacity(0.85) : OB.ink2)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(dark ? OB.studioSurfaceHover : OB.surfaceHover)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(dark ? OB.studioBorder : OB.hairline, lineWidth: 0.5)
            )
    }
}

// MARK: - 按钮

public enum OBButtonStyle {
    case primary
    case secondary
    case ghost
    case danger
    case darkGhost   // 深色画布里的 ghost
    case darkSecondary
}

/// 原型 .btn：高 30 圆角 7。
public struct OBButton: View {

    public init(title: String, style: OBButtonStyle = .secondary, icon: OBIcon.ID? = nil, kbdShortcut: String? = nil, action: @escaping () -> Void = {}) {
        self.title = title
        self.style = style
        self.icon = icon
        self.kbdShortcut = kbdShortcut
        self.action = action
    }
    public let title: String
    public var style: OBButtonStyle = .secondary
    public var icon: OBIcon.ID? = nil
    public var kbdShortcut: String? = nil
    public var action: () -> Void = {}

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    OBIcon(icon, size: 14)
                }
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                if let kbdShortcut {
                    Kbd(text: kbdShortcut, dark: style == .primary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: return OB.accent
        case .secondary: return OB.btnFill
        case .ghost: return .clear
        case .danger: return OB.redSoft
        case .darkGhost: return .clear
        case .darkSecondary: return OB.studioSurfaceHover
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .secondary: return OB.ink
        case .ghost: return OB.ink2
        case .danger: return OB.red
        case .darkGhost: return OB.studioInk2
        case .darkSecondary: return OB.studioInk
        }
    }
}

// MARK: - 图标

/// 采用 macOS 原生 SF Symbols 渲染系统级矢量图标，支持动态字重与尺寸。
public struct OBIcon: View {
    public enum ID: String {
        case search, gear, chevronLeft, chevronRight, chevronUp, chevronDown
        case clipboard, camera, eyedropper, text, qrcode, folder, layout
        case pin, power, copy, link, code, lines
        case undo, redo, plus, minus, check, warning, keyboard
        case grid, sun, storage, trash, save, share, mosaic
        case arrowUpRight, rect, typeT, close, refresh, image
    }

    public let icon: ID
    public var size: CGFloat = 15
    public var weight: CGFloat = 1.6

    public init(_ icon: ID, size: CGFloat = 15, weight: CGFloat = 1.6) {
        self.icon = icon
        self.size = size
        self.weight = weight
    }

    public init(_ raw: String, size: CGFloat = 15, weight: CGFloat = 1.6) {
        self.icon = ID(rawValue: raw) ?? .clipboard
        self.size = size
        self.weight = weight
    }

    private var sfSymbolName: String {
        switch icon {
        case .search: return "magnifyingglass"
        case .gear: return "gearshape"
        case .chevronLeft: return "chevron.left"
        case .chevronRight: return "chevron.right"
        case .chevronUp: return "chevron.up"
        case .chevronDown: return "chevron.down"
        case .clipboard: return "doc.on.clipboard"
        case .camera: return "camera"
        case .eyedropper: return "eyedropper.halffull"
        case .text: return "text.alignleft"
        case .qrcode: return "qrcode"
        case .folder: return "folder"
        case .layout: return "rectangle.split.2x1"
        case .pin: return "pin"
        case .power: return "power"
        case .copy: return "doc.on.doc"
        case .link: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .lines: return "line.3.horizontal"
        case .undo: return "arrow.uturn.backward"
        case .redo: return "arrow.uturn.forward"
        case .plus: return "plus"
        case .minus: return "minus"
        case .check: return "checkmark"
        case .warning: return "exclamationmark.triangle"
        case .keyboard: return "keyboard"
        case .grid: return "square.grid.2x2"
        case .sun: return "sun.max"
        case .storage: return "internaldrive"
        case .trash: return "trash"
        case .save: return "square.and.arrow.down"
        case .share: return "square.and.arrow.up"
        case .mosaic: return "checkerboard.rectangle"
        case .arrowUpRight: return "arrow.up.right"
        case .rect: return "rectangle"
        case .typeT: return "textformat"
        case .close: return "xmark"
        case .refresh: return "arrow.triangle.2.circlepath"
        case .image: return "photo"
        }
    }

    private var symbolWeight: Font.Weight {
        if weight >= 2.0 { return .bold }
        if weight >= 1.5 { return .medium }
        return .regular
    }

    public var body: some View {
        Image(systemName: sfSymbolName)
            .font(.system(size: size, weight: symbolWeight))
            .frame(width: size, height: size, alignment: .center)
    }
}

// MARK: - 状态点

public struct StatusDot: View {

    public init(standby: Bool = false) {
        self.standby = standby
    }
    public var standby = false
    public var body: some View {
        Circle()
            .fill(standby ? OB.brandYellow : OB.green)
            .frame(width: 6, height: 6)
    }
}

// MARK: - 开关

/// 原型 .toggle：38×22，开时绿色。
public struct OBToggle: View {

    public init(isOn: Bool, action: @escaping () -> Void) {
        self.isOn = isOn
        self.action = action
    }
    public let isOn: Bool
    public let action: () -> Void

    public var body: some View {
        Button(action: action) {
            ZStack {
                Capsule()
                    .fill(isOn ? OB.green : OB.borderStrong)
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.22), radius: 1.5, x: 0, y: 1)
                    .frame(width: 18, height: 18)
                    .offset(x: isOn ? 8 : -8)
            }
            .frame(width: 38, height: 22)
            .animation(.easeInOut(duration: 0.16), value: isOn)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 分段控件

/// 原型 .seg-control。
public struct OBSegmentedControl<Option: Hashable>: View {

    public init(options: [Option], title: @escaping (Option) -> String, selection: Binding<Option>) {
        self.options = options
        self.title = title
        self._selection = selection
    }
    public let options: [Option]
    public let title: (Option) -> String
    @Binding var selection: Option

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(selection == option ? OB.ink : OB.ink2)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selection == option ? Color.white : Color.clear)
                                .shadow(color: OB.hairline, radius: 1, x: 0, y: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(OB.surfaceHover)
        )
    }
}

// MARK: - Toast / 确认弹窗

/// 原型 .toast：底部居中黑底胶囊。
public struct ToastView: View {

    public init(text: String) {
        self.text = text
    }
    public let text: String

    public var body: some View {
        HStack(spacing: 7) {
            OBIcon(.check, size: 14, weight: 2.2)
                .foregroundColor(OB.green)
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 13)
        .frame(height: 34)
        .background(
            Capsule().fill(OB.studioBar.opacity(0.94))
        )
        .overlay(
            Capsule().strokeBorder(OB.studioBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.24), radius: 14, x: 0, y: 10)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
