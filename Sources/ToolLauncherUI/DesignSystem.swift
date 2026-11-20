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

// MARK: - 颜色（方案 B：炭黑/象牙白主控件 + 明黄点缀，自适应浅/深色）

public enum OB {
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        })
    }

    private static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }

    private static func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    // MARK: 中性文字
    public static let ink = dynamic(light: hex(0x18181B), dark: hex(0xF4F4F5))
    /// 次级文字：略加深，避免玻璃底上发灰发虚。
    public static let ink2 = dynamic(light: hex(0x52525B), dark: hex(0xA1A1AA))
    public static let ink3 = dynamic(light: hex(0x71717A), dark: hex(0x71717A))

    // MARK: 中性表面与边框
    public static let hairline = dynamic(light: rgba(24, 24, 27, 0.08), dark: rgba(255, 255, 255, 0.08))
    public static let borderStrong = dynamic(light: rgba(24, 24, 27, 0.14), dark: rgba(255, 255, 255, 0.15))
    public static let surfaceSubtle = dynamic(light: rgba(24, 24, 27, 0.04), dark: rgba(255, 255, 255, 0.045))
    public static let surfaceHover = dynamic(light: rgba(24, 24, 27, 0.068), dark: rgba(255, 255, 255, 0.08))
    public static let surfaceActive = dynamic(light: rgba(24, 24, 27, 0.095), dark: rgba(255, 255, 255, 0.12))
    public static let btnFill = surfaceHover
    public static let scrim = dynamic(light: rgba(24, 24, 27, 0.24), dark: rgba(0, 0, 0, 0.45))
    public static let cardSurface = dynamic(light: NSColor.white.withAlphaComponent(0.88), dark: hex(0x22242A, alpha: 0.84))
    public static let modalSurface = dynamic(light: NSColor.white.withAlphaComponent(0.94), dark: hex(0x1E2026, alpha: 0.95))
    public static let previewBg = dynamic(light: hex(0xF4F4F6), dark: hex(0x131418))
    public static let segActiveSurface = dynamic(light: .white, dark: NSColor.white.withAlphaComponent(0.14))

    // MARK: 主强调色（炭黑 / 象牙白主控件）
    public static let accent = dynamic(light: hex(0x18181B), dark: hex(0xF4F4F5))
    public static let accentInk = dynamic(light: hex(0x18181B), dark: hex(0xF4F4F5))
    public static let primaryFg = dynamic(light: .white, dark: hex(0x18181B))
    public static let accentSoft = dynamic(light: rgba(24, 24, 27, 0.075), dark: rgba(255, 255, 255, 0.10))

    // MARK: 品牌点缀黄（呼应黄白 Logo，仅用于小面积焦点、指示条、状态点与徽章）
    public static let brandYellow = Color(hex: 0xFACC15)
    public static let brandYellowInk = dynamic(light: hex(0xA16207), dark: hex(0xFDE047))
    public static let brandYellowSoft = Color(red: 250/255, green: 204/255, blue: 21/255, opacity: 0.17)

    // MARK: 语义状态色
    public static let green = dynamic(light: hex(0x1D9A54), dark: hex(0x30D158))
    public static let greenSoft = dynamic(light: rgba(29, 154, 84, 0.11), dark: rgba(48, 209, 88, 0.15))
    public static let orange = dynamic(light: hex(0xD97706), dark: hex(0xFF9F0A))
    public static let red = dynamic(light: hex(0xD93025), dark: hex(0xFF453A))
    public static let redSoft = dynamic(light: rgba(217, 48, 37, 0.10), dark: rgba(255, 69, 58, 0.15))

    /// 玻璃面板底色：略提高不透明度，减轻文字/细线在材质上的发虚感。
    public static let glass = dynamic(light: NSColor.white.withAlphaComponent(0.88), dark: hex(0x18191D, alpha: 0.88))
    public static let glassBorder = dynamic(light: NSColor.white.withAlphaComponent(0.72), dark: NSColor.white.withAlphaComponent(0.12))
    public static let glassBar1 = dynamic(light: NSColor.white.withAlphaComponent(0.55), dark: NSColor.white.withAlphaComponent(0.035))
    public static let glassBar2 = dynamic(light: NSColor.white.withAlphaComponent(0.38), dark: NSColor.white.withAlphaComponent(0.02))
    public static let glassFooter = glassBar2
    public static let glassHeader = glassBar1
    public static let sidebarBg = dynamic(light: rgba(244, 244, 246, 0.82), dark: rgba(20, 21, 25, 0.84))
    public static let contentBg = dynamic(light: rgba(250, 250, 252, 0.92), dark: rgba(26, 27, 32, 0.92))
    public static let configScroll = contentBg

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

/// 玻璃面板：material + 动态玻璃底色。
public struct GlassPanelBackground: View {

    public init() {}
    public var body: some View {
        ZStack {
            Rectangle().fill(.thinMaterial)
            Rectangle().fill(OB.glass)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(OB.glassBorder, lineWidth: 0.5)
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

    public init(text: String, dark: Bool = false, onPrimary: Bool = false) {
        self.text = text
        self.dark = dark
        self.onPrimary = onPrimary
    }
    public let text: String
    public var dark: Bool = false
    public var onPrimary: Bool = false

    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium).monospaced())
            .foregroundColor(fgColor)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(bgColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.5)
            )
    }

    private var fgColor: Color {
        if onPrimary { return OB.primaryFg.opacity(0.88) }
        return dark ? .white.opacity(0.85) : OB.ink2
    }

    private var bgColor: Color {
        if onPrimary { return Color.gray.opacity(0.24) }
        return dark ? OB.studioSurfaceHover : OB.surfaceHover
    }

    private var borderColor: Color {
        if onPrimary { return .clear }
        return dark ? OB.studioBorder : OB.hairline
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
                    Kbd(text: kbdShortcut, onPrimary: style == .primary)
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
        case .primary: return OB.primaryFg
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
        case grid, sun, moon, storage, trash, save, share, mosaic
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
        case .moon: return "moon"
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
                                .fill(selection == option ? OB.segActiveSurface : Color.clear)
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
