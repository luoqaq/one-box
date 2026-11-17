import SwiftUI
import ToolLauncherUI
import ToolRegistry

// MARK: - 工具工作台窗口外壳（原型 .tool-window：920×600 玻璃 + 圆角 16）

public struct ToolWorkbenchShell<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .frame(minWidth: 920, minHeight: 600)
            .background(GlassPanelBackground())
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .preferredColorScheme(.light)
    }
}

// MARK: - 工作台顶栏（原型 .tool-topbar：50pt）

public struct ToolTopbar<Trailing: View>: View {
    let title: String
    let onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    public init(title: String, onBack: @escaping () -> Void, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.onBack = onBack
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                OBIcon(.chevronLeft, size: 15, weight: 2)
                    .foregroundColor(OB.ink2)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("返回工具箱")

            Text(title)
                .font(.system(size: 13.5, weight: .semibold))

            Spacer()
            trailing()
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(OB.glassHeader)
        .overlay(alignment: .bottom) { Divider().overlay(OB.hairline) }
    }
}

// MARK: - 内联搜索框（原型 .inline-search：32pt）

public struct InlineSearchField: View {
    @Binding var text: String
    var placeholder: String

    public init(text: Binding<String>, placeholder: String) {
        _text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: 8) {
            OBIcon(.search, size: 14, weight: 2)
                .foregroundColor(OB.ink3)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.06), lineWidth: 0.5)
        )
    }
}

// MARK: - 记录状态按钮（原型 .status-dot-btn）

public struct RecordStatusButton: View {
    let isPaused: Bool
    let action: () -> Void

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isPaused ? OB.ink2 : OB.green)
                    .frame(width: 6, height: 6)
                Text(isPaused ? "已暂停" : "记录中")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundColor(isPaused ? OB.ink2 : OB.green)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isPaused ? OB.surfaceSubtle : OB.greenSoft)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 设置卡片与行（原型 .s-card / .s-row）

public struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 0) { content() }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(OB.hairline, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

public struct SettingsRow<Trailing: View>: View {
    let title: String
    let desc: String
    @ViewBuilder var trailing: () -> Trailing

    public init(title: String, desc: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.desc = desc
        self.trailing = trailing
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(OB.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(desc)
                    .font(.system(size: 11.5))
                    .foregroundColor(OB.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 48, alignment: .center)
        .overlay(alignment: .bottom) { Divider().overlay(OB.hairline) }
    }
}

// MARK: - 步进器（原型 .stepper）

public struct StepperView: View {
    let value: Int
    let step: Int
    let range: ClosedRange<Int>
    let unit: String
    let onChange: (Int) -> Void

    public var body: some View {
        HStack(spacing: 4) {
            Button {
                onChange(clamp(value - step))
            } label: {
                Text("−").font(.system(size: 14))
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.06)))
            }
            .buttonStyle(.plain)
            Text("\(value)\(unit)")
                .font(.system(size: 12.5, weight: .medium))
                .monospacedDigit()
                .frame(minWidth: 54)
            Button {
                onChange(clamp(value + step))
            } label: {
                Text("＋").font(.system(size: 14))
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.06)))
            }
            .buttonStyle(.plain)
        }
    }

    private func clamp(_ v: Int) -> Int {
        min(range.upperBound, max(range.lowerBound, v))
    }
}

// MARK: - 热键按钮（原型 .hotkey-btn，支持录制）

public struct HotkeyButton: View {
    let spec: HotKeySpec
    let onRecord: (HotKeySpec) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    public init(spec: HotKeySpec, onRecord: @escaping (HotKeySpec) -> Void) {
        self.spec = spec
        self.onRecord = onRecord
    }

    public var body: some View {
        Button {
            startRecording()
        } label: {
            Group {
                if isRecording {
                    Text("按下快捷键…")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(OB.accentInk)
                } else {
                    HStack(spacing: 3) {
                        ForEach(Array(spec.display), id: \.self) { ch in
                            Kbd(text: String(ch))
                        }
                    }
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isRecording ? OB.accentSoft : Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isRecording ? OB.accent : OB.hairline, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var mods: Set<HotKeySpec.Modifier> = []
            if flags.contains(.control) { mods.insert(.control) }
            if flags.contains(.option) { mods.insert(.option) }
            if flags.contains(.shift) { mods.insert(.shift) }
            if flags.contains(.command) { mods.insert(.command) }
            stopRecording()
            // 修饰键单独按下不算快捷键；至少一个修饰键 + 普通键。
            if !mods.isEmpty, event.keyCode != 54, event.keyCode != 55, event.keyCode != 56,
               event.keyCode != 57, event.keyCode != 58, event.keyCode != 59, event.keyCode != 60,
               event.keyCode != 61, event.keyCode != 62, event.keyCode != 63 {
                onRecord(HotKeySpec(keyCode: Int(event.keyCode), modifiers: mods))
            }
            return nil
        }
        // 6 秒未录制到就自动退出录制态
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            if isRecording { stopRecording() }
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }
}

// MARK: - 路径胶囊 / 权限徽标

public struct PathChip: View {
    let path: String

    public var body: some View {
        Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
            .font(.system(size: 11.5).monospaced())
            .foregroundColor(OB.ink2)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.045))
            )
    }
}

public enum PermBadgeStyle {
    case ok(String)
    case warn(String)
    case off(String)

    var text: String {
        switch self {
        case .ok(let s), .warn(let s), .off(let s): return s
        }
    }

    var color: Color {
        switch self {
        case .ok: return OB.green
        case .warn: return OB.orange
        case .off: return OB.ink3
        }
    }
}

/// 原型 .perm-badge：圆点 + 文案。
public struct PermBadge: View {
    let style: PermBadgeStyle

    public init(_ style: PermBadgeStyle) {
        self.style = style
    }

    public var body: some View {
        HStack(spacing: 5) {
            Circle().fill(style.color).frame(width: 6, height: 6)
            Text(style.text)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(style.color)
    }
}

// MARK: - 确认弹窗（原型 .modal）

public struct ConfirmModal: View {
    let title: String
    let message: String
    let confirmTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    public init(title: String, message: String, confirmTitle: String,
                onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.24)
                .background(.ultraThinMaterial)
                .onTapGesture { onCancel() }

            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.bottom, 6)
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundColor(OB.ink2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.bottom, 16)
                HStack(spacing: 8) {
                    modalButton(title: "取消", fg: OB.ink, bg: OB.btnFill, action: onCancel)
                    modalButton(title: confirmTitle, fg: OB.red, bg: OB.redSoft, action: onConfirm)
                }
            }
            .padding(20)
            .frame(width: 340)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.12), lineWidth: 0.5)
            )
        }
    }

    private func modalButton(title: String, fg: Color, bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(fg)
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(bg)
        )
    }
}

// MARK: - 空状态（原型 .empty-box）

public struct EmptyBoxView: View {
    let icon: OBIcon.ID
    let title: String
    let message: String

    public init(icon: OBIcon.ID, title: String, message: String) {
        self.icon = icon
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 0) {
            OBIcon(icon, size: 22, weight: 1.8)
                .foregroundColor(OB.ink2)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.05))
                )
                .padding(.bottom, 12)
            Text(title)
                .font(.system(size: 14.5, weight: .semibold))
                .padding(.bottom, 5)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundColor(OB.ink2)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: 340)
    }
}

// MARK: - 横幅（原型 .banner-card）

public struct BannerCard: View {
    public enum Kind { case warn, danger }
    public let kind: Kind
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    public init(kind: Kind, title: String, message: String, actionTitle: String, action: @escaping () -> Void) {
        self.kind = kind
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var accent: Color { kind == .danger ? OB.red : OB.orange }

    public var body: some View {
        HStack(spacing: 12) {
            OBIcon(.warning, size: 18, weight: 2)
                .foregroundColor(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(OB.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            OBButton(title: actionTitle, style: .primary, action: action)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(OB.hairline, lineWidth: 0.5)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(accent)
                .frame(width: 3)
                .padding(.vertical, 12)
                .padding(.leading, 6)
        }
    }
}

// MARK: - 图标按钮

public struct OBIconButton: View {
    let icon: OBIcon.ID
    var isActive = false
    let title: String
    let action: () -> Void

    public init(_ icon: OBIcon.ID, isActive: Bool = false, title: String, action: @escaping () -> Void) {
        self.icon = icon
        self.isActive = isActive
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            OBIcon(icon, size: 15, weight: 1.9)
                .foregroundColor(isActive ? OB.accentInk : OB.ink2)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isActive ? OB.accentSoft : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}
