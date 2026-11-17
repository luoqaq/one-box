import SwiftUI

// MARK: - 颜色（对照 prototypes/v1-module-details/index.html :root）

public enum OB {
    public static let ink = Color(hex: 0x111318)
    public static let ink2 = Color(hex: 0x4F5664)
    public static let ink3 = Color(hex: 0x8A919E)

    public static let hairline = Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.08)
    public static let surfaceSubtle = Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.035)
    public static let surfaceHover = Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.048)

    public static let accent = Color(hex: 0x007AFF)
    public static let accentInk = Color(hex: 0x0066D6)
    public static let accentSoft = Color(red: 0, green: 122/255, blue: 1, opacity: 0.10)

    public static let green = Color(hex: 0x1D9A54)
    public static let greenSoft = Color(red: 29/255, green: 154/255, blue: 84/255, opacity: 0.11)
    public static let orange = Color(hex: 0xC96F00)
    public static let red = Color(hex: 0xD93025)
    public static let redSoft = Color(red: 217/255, green: 48/255, blue: 37/255, opacity: 0.10)

    /// 玻璃面板底色 rgba(255,255,255,0.78)
    public static let glass = Color.white.opacity(0.78)
    public static let glassBar1 = Color.white.opacity(0.42)
    public static let glassBar2 = Color.white.opacity(0.22)
    public static let glassFooter = Color.white.opacity(0.36)
    public static let glassHeader = Color.white.opacity(0.40)
    public static let configScroll = Color(red: 249/255, green: 250/255, blue: 252/255, opacity: 0.65)

    /// 标注画布（深色）
    public static let studioBg = Color(hex: 0x111318)
    public static let studioWindow = Color(hex: 0x171A21)
    public static let studioPanel = Color(hex: 0x171A21)
    public static let studioBar = Color(hex: 0x1B1F27)
    public static let studioCanvas = Color(hex: 0x12141A)
    public static let studioSeparator = Color.white.opacity(0.08)

    /// 桌面背景（原型 Sequoia 风格渐变）
    public static let desktopGradient = LinearGradient(
        colors: [Color(hex: 0xE9EEF4), Color(hex: 0xDFE6EF), Color(hex: 0xE8ECF1)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    public static let btnFill = Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.06)
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

    /// 解析工具描述里的 fgHex / bgHex（8 位 ARGB 或 6 位 RGB）。
    public init(flexibleHex: String) {
        let s = flexibleHex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        let value = UInt64(s, radix: 16) ?? 0x8A919E
        if s.count == 8 {
            let a = Double((value >> 24) & 0xFF) / 255
            self.init(.sRGB,
                      red: Double((value >> 16) & 0xFF) / 255,
                      green: Double((value >> 8) & 0xFF) / 255,
                      blue: Double(value & 0xFF) / 255,
                      opacity: a)
        } else {
            self.init(hex: UInt32(truncatingIfNeeded: value))
        }
    }
}

// MARK: - 玻璃面板

/// 原型 .glass-panel：白 0.78 + 模糊 + 0.5px 白描边 + 阴影。
public struct GlassPanelBackground: View {

    public init() {}
    public var body: some View {
        ZStack {
            Rectangle().fill(.white.opacity(0.55))
                .background(.ultraThinMaterial)
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
                    .fill(dark ? Color.white.opacity(0.12) : Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(dark ? Color.white.opacity(0.14) : Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.10), lineWidth: 0.5)
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
        case .secondary: return Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.06)
        case .ghost: return .clear
        case .danger: return OB.redSoft
        case .darkGhost: return .clear
        case .darkSecondary: return Color.white.opacity(0.10)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .secondary: return OB.ink
        case .ghost: return OB.ink2
        case .danger: return OB.red
        case .darkGhost: return .white.opacity(0.72)
        case .darkSecondary: return .white
        }
    }
}

// MARK: - 图标

/// 原型内联 SVG 的 SwiftUI 还原。尺寸由调用方指定。
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
    public var weight: CGFloat = 1.9

    public init(_ icon: ID, size: CGFloat = 15, weight: CGFloat = 1.9) {
        self.icon = icon
        self.size = size
        self.weight = weight
    }

    public init(_ raw: String, size: CGFloat = 15, weight: CGFloat = 1.9) {
        self.icon = ID(rawValue: raw) ?? .clipboard
        self.size = size
        self.weight = weight
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            let s = canvasSize.width / 24
            var path = Path()
            draw(&path, scale: s)
            context.stroke(path, with: .color(.primary.opacity(0.9)),
                           style: StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round))
            context.fill(fillPath(s), with: .color(.primary.opacity(0.9)))
        }
        .frame(width: size, height: size)
    }

    /// 描边路径（24×24 网格，按 scale 缩放）。
    private func draw(_ path: inout Path, scale: CGFloat) {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }
        switch icon {
        case .search:
            path.addEllipse(in: CGRect(x: 4 * scale, y: 4 * scale, width: 14 * scale, height: 14 * scale))
            path.move(to: pt(15.2, 15.2)); path.addLine(to: pt(20, 20))
        case .gear:
            path.addEllipse(in: CGRect(x: 9 * scale, y: 9 * scale, width: 6 * scale, height: 6 * scale))
            // 简化齿轮外圈：8 根辐条
            for i in 0..<8 {
                let angle = Double(i) * .pi / 4
                let cx = 12 * scale, cy = 12 * scale
                let r1 = 5.5 * scale, r2 = 8.2 * scale
                path.move(to: CGPoint(x: cx + CGFloat(cos(angle)) * r1, y: cy + CGFloat(sin(angle)) * r1))
                path.addLine(to: CGPoint(x: cx + CGFloat(cos(angle)) * r2, y: cy + CGFloat(sin(angle)) * r2))
            }
            path.addEllipse(in: CGRect(x: 4 * scale, y: 4 * scale, width: 16 * scale, height: 16 * scale))
        case .chevronLeft:
            path.move(to: pt(15, 18)); path.addLine(to: pt(9, 12)); path.addLine(to: pt(15, 6))
        case .chevronRight:
            path.move(to: pt(9, 18)); path.addLine(to: pt(15, 12)); path.addLine(to: pt(9, 6))
        case .chevronUp:
            path.move(to: pt(6, 15)); path.addLine(to: pt(12, 9)); path.addLine(to: pt(18, 15))
        case .chevronDown:
            path.move(to: pt(6, 9)); path.addLine(to: pt(12, 15)); path.addLine(to: pt(18, 9))
        case .clipboard:
            path.addRoundedRect(in: CGRect(x: 6 * scale, y: 4 * scale, width: 12 * scale, height: 17 * scale),
                                cornerSize: CGSize(width: 3 * scale, height: 3 * scale))
            path.move(to: pt(9, 4))
            path.addCurve(to: pt(15, 4),
                          control1: pt(9, 2), control2: pt(15, 2))
            path.move(to: pt(9, 11)); path.addLine(to: pt(15, 11))
            path.move(to: pt(9, 15)); path.addLine(to: pt(13, 15))
        case .camera:
            path.move(to: pt(4, 8)); path.addLine(to: pt(7, 8)); path.addLine(to: pt(9, 5))
            path.addLine(to: pt(15, 5)); path.addLine(to: pt(17, 8)); path.addLine(to: pt(20, 8))
            path.addLine(to: pt(20, 19)); path.addLine(to: pt(4, 19)); path.closeSubpath()
            path.addEllipse(in: CGRect(x: 8.8 * scale, y: 9.8 * scale, width: 6.4 * scale, height: 6.4 * scale))
        case .eyedropper:
            path.move(to: pt(9, 11)); path.addLine(to: pt(16, 4))
            path.addCurve(to: pt(20, 8), control1: pt(17.5, 3.5), control2: pt(21, 7))
            path.addLine(to: pt(13, 15))
            path.move(to: pt(9, 11)); path.addLine(to: pt(4, 12)); path.addLine(to: pt(5, 16))
            path.addLine(to: pt(8, 19)); path.addLine(to: pt(12, 20)); path.addLine(to: pt(13, 15))
            path.move(to: pt(3, 21)); path.addLine(to: pt(6, 20))
        case .text:
            path.move(to: pt(5, 6)); path.addLine(to: pt(5, 4)); path.addLine(to: pt(19, 4))
            path.addLine(to: pt(19, 6))
            path.move(to: pt(12, 4)); path.addLine(to: pt(12, 20))
            path.move(to: pt(9, 20)); path.addLine(to: pt(15, 20))
        case .qrcode:
            path.addRoundedRect(in: CGRect(x: 4 * scale, y: 4 * scale, width: 6 * scale, height: 6 * scale),
                                 cornerSize: CGSize(width: scale, height: scale))
            path.addRoundedRect(in: CGRect(x: 14 * scale, y: 4 * scale, width: 6 * scale, height: 6 * scale),
                                 cornerSize: CGSize(width: scale, height: scale))
            path.addRoundedRect(in: CGRect(x: 4 * scale, y: 14 * scale, width: 6 * scale, height: 6 * scale),
                                 cornerSize: CGSize(width: scale, height: scale))
            path.move(to: pt(14, 14)); path.addLine(to: pt(17, 14)); path.addLine(to: pt(17, 17))
            path.addLine(to: pt(14, 17)); path.closeSubpath()
            path.move(to: pt(20, 14)); path.addLine(to: pt(21, 14))
            path.move(to: pt(14, 20)); path.addLine(to: pt(15, 20))
            path.move(to: pt(18, 18)); path.addLine(to: pt(21, 18)); path.addLine(to: pt(21, 21))
            path.addLine(to: pt(18, 21)); path.closeSubpath()
        case .folder:
            path.move(to: pt(4, 7)); path.addLine(to: pt(10, 7)); path.addLine(to: pt(12, 9))
            path.addLine(to: pt(20, 9)); path.addLine(to: pt(20, 19)); path.addLine(to: pt(4, 19))
            path.closeSubpath()
            path.move(to: pt(12, 12)); path.addLine(to: pt(12, 17))
            path.move(to: pt(9.5, 14.5)); path.addLine(to: pt(14.5, 14.5))
        case .layout:
            path.addRoundedRect(in: CGRect(x: 4 * scale, y: 5 * scale, width: 7 * scale, height: 14 * scale),
                                 cornerSize: CGSize(width: 1.5 * scale, height: 1.5 * scale))
            path.addRoundedRect(in: CGRect(x: 14 * scale, y: 5 * scale, width: 6 * scale, height: 7 * scale),
                                 cornerSize: CGSize(width: 1.5 * scale, height: 1.5 * scale))
            path.addRoundedRect(in: CGRect(x: 14 * scale, y: 15 * scale, width: 6 * scale, height: 4 * scale),
                                 cornerSize: CGSize(width: 1.5 * scale, height: 1.5 * scale))
        case .pin:
            path.move(to: pt(12, 17)); path.addLine(to: pt(12, 22))
            path.move(to: pt(9, 4)); path.addLine(to: pt(15, 4)); path.addLine(to: pt(14, 9))
            path.addLine(to: pt(17, 12)); path.addLine(to: pt(17, 14)); path.addLine(to: pt(7, 14))
            path.addLine(to: pt(7, 12)); path.addLine(to: pt(10, 9)); path.closeSubpath()
        case .power:
            path.move(to: pt(12, 3)); path.addLine(to: pt(12, 11))
            path.move(to: pt(18.4, 6.6))
            path.addCurve(to: pt(5.6, 6.6), control1: pt(16, 3.6), control2: pt(8, 3.6))
            path.addCurve(to: pt(18.4, 6.6), control1: pt(8, 18), control2: pt(16, 18))
        case .copy:
            path.addRoundedRect(in: CGRect(x: 9 * scale, y: 9 * scale, width: 11 * scale, height: 11 * scale),
                                 cornerSize: CGSize(width: 2 * scale, height: 2 * scale))
            path.move(to: pt(5, 15)); path.addLine(to: pt(5, 6))
            path.addCurve(to: pt(7, 4), control1: pt(5, 4.9), control2: pt(5.9, 4))
            path.addLine(to: pt(16, 4))
        case .link:
            path.move(to: pt(10, 13))
            path.addCurve(to: pt(17.5, 13.5), control1: pt(12.8, 15.2), control2: pt(15.5, 15.5))
            path.addLine(to: pt(20.5, 10.5))
            path.addCurve(to: pt(13.5, 3.5), control1: pt(22.5, 6.5), control2: pt(18, 2))
            path.addLine(to: pt(11.8, 5.2))
            path.move(to: pt(14, 11))
            path.addCurve(to: pt(6.5, 10.5), control1: pt(11.2, 8.8), control2: pt(8.5, 8.5))
            path.addLine(to: pt(3.5, 13.5))
            path.addCurve(to: pt(10.5, 20.5), control1: pt(1.5, 17.5), control2: pt(6, 22))
            path.addLine(to: pt(12.2, 18.8))
        case .code:
            path.move(to: pt(8, 9)); path.addLine(to: pt(4, 12)); path.addLine(to: pt(8, 15))
            path.move(to: pt(16, 9)); path.addLine(to: pt(20, 12)); path.addLine(to: pt(16, 15))
            path.move(to: pt(13, 7)); path.addLine(to: pt(11, 17))
        case .lines:
            path.move(to: pt(6, 7)); path.addLine(to: pt(18, 7))
            path.move(to: pt(6, 12)); path.addLine(to: pt(18, 12))
            path.move(to: pt(6, 17)); path.addLine(to: pt(13, 17))
        case .undo:
            path.move(to: pt(9, 14)); path.addLine(to: pt(4, 9)); path.addLine(to: pt(9, 4))
            path.move(to: pt(4, 9)); path.addLine(to: pt(14, 9))
            path.addCurve(to: pt(14, 21), control1: pt(20, 9), control2: pt(20, 21))
            path.addLine(to: pt(12, 21))
        case .redo:
            path.move(to: pt(15, 14)); path.addLine(to: pt(20, 9)); path.addLine(to: pt(15, 4))
            path.move(to: pt(20, 9)); path.addLine(to: pt(10, 9))
            path.addCurve(to: pt(10, 21), control1: pt(4, 9), control2: pt(4, 21))
            path.addLine(to: pt(12, 21))
        case .plus:
            path.move(to: pt(5, 12)); path.addLine(to: pt(19, 12))
            path.move(to: pt(12, 5)); path.addLine(to: pt(12, 19))
        case .minus:
            path.move(to: pt(5, 12)); path.addLine(to: pt(19, 12))
        case .check:
            path.move(to: pt(5, 13)); path.addLine(to: pt(9, 17)); path.addLine(to: pt(19, 7))
        case .warning:
            path.move(to: pt(12, 9)); path.addLine(to: pt(12, 13))
            path.move(to: pt(12, 17)); path.addLine(to: pt(12, 17.01))
            path.move(to: pt(10.3, 3.9)); path.addLine(to: pt(2.6, 17))
            path.addCurve(to: pt(4.3, 20), control1: pt(2, 18.1), control2: pt(3, 20))
            path.addLine(to: pt(19.7, 20))
            path.addCurve(to: pt(21.4, 17), control1: pt(21, 20), control2: pt(22, 18.1))
            path.addLine(to: pt(13.7, 3.9))
            path.addCurve(to: pt(10.3, 3.9), control1: pt(12.6, 2.7), control2: pt(11.4, 2.7))
        case .keyboard:
            path.addRoundedRect(in: CGRect(x: 3 * scale, y: 6 * scale, width: 18 * scale, height: 12 * scale),
                                 cornerSize: CGSize(width: 3 * scale, height: 3 * scale))
            path.move(to: pt(7, 10)); path.addLine(to: pt(7.1, 10))
            path.move(to: pt(11, 10)); path.addLine(to: pt(11.1, 10))
            path.move(to: pt(15, 10)); path.addLine(to: pt(15.1, 10))
            path.move(to: pt(17, 14)); path.addLine(to: pt(7, 14))
        case .grid:
            path.addRoundedRect(in: CGRect(x: 4 * scale, y: 4 * scale, width: 7 * scale, height: 7 * scale),
                                 cornerSize: CGSize(width: 1.5 * scale, height: 1.5 * scale))
            path.addRoundedRect(in: CGRect(x: 13 * scale, y: 4 * scale, width: 7 * scale, height: 7 * scale),
                                 cornerSize: CGSize(width: 1.5 * scale, height: 1.5 * scale))
            path.addRoundedRect(in: CGRect(x: 4 * scale, y: 13 * scale, width: 7 * scale, height: 7 * scale),
                                 cornerSize: CGSize(width: 1.5 * scale, height: 1.5 * scale))
            path.addRoundedRect(in: CGRect(x: 13 * scale, y: 13 * scale, width: 7 * scale, height: 7 * scale),
                                 cornerSize: CGSize(width: 1.5 * scale, height: 1.5 * scale))
        case .sun:
            path.addEllipse(in: CGRect(x: 9 * scale, y: 9 * scale, width: 6 * scale, height: 6 * scale))
            path.move(to: pt(12, 2)); path.addLine(to: pt(12, 5))
            path.move(to: pt(12, 19)); path.addLine(to: pt(12, 22))
            path.move(to: pt(4.9, 4.9)); path.addLine(to: pt(7, 7))
            path.move(to: pt(17, 17)); path.addLine(to: pt(19.1, 19.1))
            path.move(to: pt(2, 12)); path.addLine(to: pt(5, 12))
            path.move(to: pt(19, 12)); path.addLine(to: pt(22, 12))
            path.move(to: pt(4.9, 19.1)); path.addLine(to: pt(7, 17))
            path.move(to: pt(17, 7)); path.addLine(to: pt(19.1, 4.9))
        case .storage:
            path.addEllipse(in: CGRect(x: 5 * scale, y: 2 * scale, width: 14 * scale, height: 6 * scale))
            path.move(to: pt(5, 5)); path.addLine(to: pt(5, 12))
            path.addCurve(to: pt(12, 15), control1: pt(5, 13.7), control2: pt(8.1, 15))
            path.addCurve(to: pt(19, 12), control1: pt(15.9, 15), control2: pt(19, 13.7))
            path.addLine(to: pt(19, 5))
            path.move(to: pt(5, 12)); path.addLine(to: pt(5, 19))
            path.addCurve(to: pt(12, 22), control1: pt(5, 20.7), control2: pt(8.1, 22))
            path.addCurve(to: pt(19, 19), control1: pt(15.9, 22), control2: pt(19, 20.7))
            path.addLine(to: pt(19, 12))
        case .trash:
            path.move(to: pt(4, 7)); path.addLine(to: pt(20, 7))
            path.move(to: pt(9, 7)); path.addLine(to: pt(9, 4.5))
            path.addLine(to: pt(15, 4.5)); path.addLine(to: pt(15, 7))
            path.addRoundedRect(in: CGRect(x: 6 * scale, y: 7 * scale, width: 12 * scale, height: 13 * scale),
                                  cornerSize: CGSize(width: scale, height: scale))
            path.move(to: pt(10, 11)); path.addLine(to: pt(10, 16))
            path.move(to: pt(14, 11)); path.addLine(to: pt(14, 16))
        case .save:
            path.move(to: pt(19, 21)); path.addLine(to: pt(5, 21))
            path.addCurve(to: pt(3, 19), control1: pt(3, 21), control2: pt(3, 20.1))
            path.addLine(to: pt(3, 5))
            path.addCurve(to: pt(5, 3), control1: pt(3, 3.9), control2: pt(3.9, 3))
            path.addLine(to: pt(16, 3)); path.addLine(to: pt(21, 8))
            path.addLine(to: pt(21, 19))
            path.addCurve(to: pt(19, 21), control1: pt(21, 20.1), control2: pt(20.1, 21))
            path.move(to: pt(7, 3)); path.addLine(to: pt(7, 9))
            path.addLine(to: pt(16, 9))
            path.move(to: pt(7, 21)); path.addLine(to: pt(7, 14))
            path.addLine(to: pt(17, 14)); path.addLine(to: pt(17, 21))
        case .share:
            path.move(to: pt(12, 15)); path.addLine(to: pt(12, 3))
            path.move(to: pt(8, 7)); path.addLine(to: pt(12, 3)); path.addLine(to: pt(16, 7))
            path.move(to: pt(4, 14)); path.addLine(to: pt(4, 20))
            path.addCurve(to: pt(6, 22), control1: pt(4, 21.1), control2: pt(4.9, 22))
            path.addLine(to: pt(18, 22))
            path.addCurve(to: pt(20, 20), control1: pt(19.1, 22), control2: pt(20, 21.1))
            path.addLine(to: pt(20, 14))
        case .mosaic:
            path.addRoundedRect(in: CGRect(x: 4 * scale, y: 5 * scale, width: 16 * scale, height: 14 * scale),
                                  cornerSize: CGSize(width: 2 * scale, height: 2 * scale))
            path.move(to: pt(4, 10)); path.addLine(to: pt(20, 10))
            path.move(to: pt(4, 15)); path.addLine(to: pt(20, 15))
            path.move(to: pt(9, 5)); path.addLine(to: pt(9, 19))
            path.move(to: pt(15, 5)); path.addLine(to: pt(15, 19))
        case .arrowUpRight:
            path.move(to: pt(5, 19)); path.addLine(to: pt(19, 5))
            path.move(to: pt(12, 5)); path.addLine(to: pt(19, 5)); path.addLine(to: pt(19, 12))
        case .rect:
            path.addRoundedRect(in: CGRect(x: 5 * scale, y: 6 * scale, width: 14 * scale, height: 12 * scale),
                                  cornerSize: CGSize(width: 1.5 * scale, height: 1.5 * scale))
        case .typeT:
            path.move(to: pt(5, 6)); path.addLine(to: pt(5, 4)); path.addLine(to: pt(19, 4))
            path.addLine(to: pt(19, 6))
            path.move(to: pt(12, 4)); path.addLine(to: pt(12, 20))
            path.move(to: pt(9, 20)); path.addLine(to: pt(15, 20))
        case .close:
            path.move(to: pt(6, 6)); path.addLine(to: pt(18, 18))
            path.move(to: pt(18, 6)); path.addLine(to: pt(6, 18))
        case .refresh:
            path.move(to: pt(12, 4))
            path.addCurve(to: pt(20, 12), control1: pt(16.4, 4), control2: pt(20, 7.6))
            path.addCurve(to: pt(12, 20), control1: pt(20, 16.4), control2: pt(16.4, 20))
            path.addCurve(to: pt(4, 12), control1: pt(7.6, 20), control2: pt(4, 16.4))
            path.addCurve(to: pt(9, 5.8), control1: pt(4, 8.5), control2: pt(6, 6.2))
            path.move(to: pt(9, 5.8)); path.addLine(to: pt(9, 3)); path.addLine(to: pt(6, 5))
        case .image:
            path.addRoundedRect(in: CGRect(x: 4 * scale, y: 5 * scale, width: 16 * scale, height: 14 * scale),
                                 cornerSize: CGSize(width: 2 * scale, height: 2 * scale))
            path.addEllipse(in: CGRect(x: 8 * scale, y: 9 * scale, width: 2.6 * scale, height: 2.6 * scale))
            path.move(to: pt(6, 17)); path.addLine(to: pt(11, 12)); path.addLine(to: pt(14, 15))
            path.addLine(to: pt(16.5, 12.5)); path.addLine(to: pt(19, 15))
        }
    }

    /// 需要填充的路径（power 图标圆弧不适合，全部走描边；保留接口备用）。
    private func fillPath(_ scale: CGFloat) -> Path { Path() }
}

// MARK: - 状态点

public struct StatusDot: View {

    public init(standby: Bool = false) {
        self.standby = standby
    }
    public var standby = false
    public var body: some View {
        Circle()
            .fill(standby ? OB.accent.opacity(0.75) : Color(hex: 0x22B45D))
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
                    .fill(isOn ? Color(hex: 0x34C759) : Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.16))
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
                                .shadow(color: Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.10),
                                        radius: 1, x: 0, y: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.06))
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
                .foregroundColor(Color(hex: 0x34C759))
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 13)
        .frame(height: 34)
        .background(
            Capsule().fill(Color(red: 20/255, green: 22/255, blue: 28/255, opacity: 0.88))
        )
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.24), radius: 14, x: 0, y: 10)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
