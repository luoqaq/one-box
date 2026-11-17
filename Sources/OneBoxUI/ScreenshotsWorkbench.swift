import SwiftUI
import ToolLauncherUI
import ToolRegistry
import CaptureStore
import ScreenCapture

// MARK: - 截图与标注工作台（合并闭环：最近截图 + 工具内配置）

public struct ScreenshotsWorkbenchView: View {
    @ObservedObject var model: AppModel
    let onBack: () -> Void
    let onStartCapture: () -> Void
    let onAnnotate: (CaptureRecord) -> Void
    var initialSubView: SubView = .main

    public enum SubView {
        case main
        case config
    }

    @State private var subView: SubView = .main
    @State private var searchText = ""
    @State private var selectedID: UUID?

    public init(
        model: AppModel,
        onBack: @escaping () -> Void,
        onStartCapture: @escaping () -> Void,
        onAnnotate: @escaping (CaptureRecord) -> Void,
        initialSubView: SubView = .main
    ) {
        self.model = model
        self.onBack = onBack
        self.onStartCapture = onStartCapture
        self.onAnnotate = onAnnotate
        self.initialSubView = initialSubView
    }

    private var captures: [CaptureRecord] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return model.captures }
        return model.captures.filter { record in
            let name = record.file.replacingOccurrences(of: "captures/", with: "")
            return name.lowercased().contains(q)
        }
    }

    private var selected: CaptureRecord? {
        if let id = selectedID, let r = captures.first(where: { $0.id == id }) { return r }
        return captures.first
    }

    public var body: some View {
        ToolWorkbenchShell {
            VStack(spacing: 0) {
                topbar
                if subView == .main {
                    mainView
                } else {
                    configView
                }
            }
            .overlay(toastOverlay)
        }
        .onAppear {
            subView = initialSubView
            model.reloadCaptures()
        }
    }

    // MARK: 顶栏

    private var topbar: some View {
        ToolTopbar(title: "截图与标注", onBack: onBack) {
            HStack(spacing: 10) {
                if subView == .main {
                    InlineSearchField(text: $searchText, placeholder: "搜索最近截图记录…")
                    OBButton(title: "开始区域截图", style: .primary, kbdShortcut: model.settings.hotkeyCapture.display, action: onStartCapture)
                }
                OBIconButton(.gear, isActive: subView == .config, title: "截图工具配置") {
                    subView = subView == .config ? .main : .config
                }
            }
        }
    }

    // MARK: 主视图

    private var mainView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                capturesList
                captureDetail
            }
            footer
        }
    }

    private var capturesList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if captures.isEmpty {
                    VStack(spacing: 14) {
                        EmptyBoxView(
                            icon: .camera,
                            title: "还没有截图记录",
                            message: "点击「开始区域截图」或按全局快捷键，框选后即可标注、复制或保存。"
                        )
                        OBButton(title: "立即截图", style: .primary, action: onStartCapture)
                    }
                    .padding(.top, 56)
                    .padding(.horizontal, 16)
                } else {
                    ForEach(captures) { record in
                        CaptureRowView(
                            record: record,
                            isSelected: selected?.id == record.id,
                            onSelect: { selectedID = record.id }
                        )
                    }
                }
            }
            .padding(8)
        }
        .frame(width: 296)
        .overlay(alignment: .trailing) { Divider().overlay(OB.hairline) }
    }

    @ViewBuilder
    private var captureDetail: some View {
        VStack(spacing: 0) {
            if let record = selected {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("最近截图 · \(OBTimeFormat.short(record.createdAt))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(OB.ink3)
                        Text(captureName(record))
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.bottom, 12)

                CaptureStage(record: record)
                    .frame(maxHeight: .infinity)

                HStack {
                    Text("\(record.width) × \(record.height) · \(OBFormat.bytes(record.byteCount))")
                        .font(.system(size: 11.5))
                        .foregroundColor(OB.ink3)
                    Spacer()
                    HStack(spacing: 6) {
                        OBButton(title: "删除", style: .ghost) {
                            model.deleteCapture(record.id)
                            model.showToast("已删除截图记录")
                        }
                        OBButton(title: "访达显示", style: .secondary) { revealInFinder(record) }
                        OBButton(title: "继续标注", style: .secondary) { onAnnotate(record) }
                        OBButton(title: "重新复制", style: .primary) { recopy(record) }
                    }
                }
                .padding(.top, 12)
            } else {
                EmptyBoxView(icon: .camera, title: "选择一张截图", message: "左侧选择截图查看详情")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 16, trailing: 20))
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white.opacity(0.34))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            PermBadge(model.captureService.authorizationStatus() ? .ok("屏幕录制已授权") : .warn("屏幕录制未授权"))
            Text("· 自动保留 30 天 · 保存目录 \(model.settings.captureSaveDirectory.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
                .font(.system(size: 11.5))
                .foregroundColor(OB.ink3)
                .lineLimit(1)
            Spacer()
            OBButton(title: "截图设置", style: .ghost) {
                subView = .config
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(OB.glassFooter)
        .overlay(alignment: .top) { Divider().overlay(OB.hairline) }
    }

    // MARK: 工具内配置

    private var configView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("截图与标注 · 工具配置")
                            .font(.system(size: 16, weight: .semibold))
                        Text("与截图流程相关的默认动作、保存路径、上限和权限都集中在这里")
                            .font(.system(size: 12))
                            .foregroundColor(OB.ink3)
                    }
                    Spacer()
                    OBButton(title: "返回截图记录", style: .secondary) {
                        subView = .main
                    }
                }
                .padding(.bottom, 14)

                if !model.captureService.authorizationStatus() {
                    BannerCard(
                        kind: .warn,
                        title: "需要屏幕录制权限",
                        message: "请在系统设置中允许 OneBox 录制屏幕，授权后重启生效。",
                        actionTitle: "去开启",
                        action: { openSystemSettings() }
                    )
                    .padding(.bottom, 12)
                }

                SettingsCard {
                    SettingsRow(title: "启用截图与标注模块", desc: "关闭后注销全局截图热键并释放渲染上下文") {
                        OBToggle(isOn: model.registry.isEnabled("screenshots")) {
                            model.registry.toggleEnabled("screenshots")
                        }
                    }
                    SettingsRow(title: "区域截图快捷键", desc: "全局任意场景按下立即拉起全屏选区") {
                        HotkeyButton(spec: model.settings.hotkeyCapture) { spec in
                            model.settings.setHotkey(spec, for: "capture")
                            model.showToast("快捷键已更新")
                        }
                    }
                    SettingsRow(title: "框选完成后默认动作", desc: "完成框选并按下回车后的流向") {
                        OBSegmentedControl(
                            options: CaptureDefaultAction.allCases,
                            title: { $0.title },
                            selection: Binding(
                                get: { model.settings.captureDefaultAction },
                                set: { model.settings.captureDefaultAction = $0 }
                            )
                        )
                    }
                }


                SettingsCard {
                    SettingsRow(title: "默认保存路径", desc: "导出 PNG 截图的默认目录") {
                        PathChip(path: model.settings.captureSaveDirectory)
                    }
                    SettingsRow(title: "保留最近截图记录", desc: "方便在工具内重新复制、继续标注或定位文件") {
                        OBToggle(isOn: model.settings.captureKeepRecords) {
                            model.settings.captureKeepRecords.toggle()
                        }
                    }
                    SettingsRow(title: "最近截图上限", desc: "超出后自动清理最早记录") {
                        StepperView(value: model.settings.captureMaxRecords, step: 20, range: 20...500, unit: " 张") {
                            model.settings.captureMaxRecords = $0
                        }
                    }
                    SettingsRow(title: "屏幕录制权限", desc: "ScreenCaptureKit 截图所需系统授权") {
                        PermBadge(model.captureService.authorizationStatus() ? .ok("已允许") : .warn("未授权"))
                    }
                }
            }
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 28, trailing: 28))
        }
        .background(OB.configScroll)
    }

    // MARK: 动作

    private func captureName(_ record: CaptureRecord) -> String {
        let id = record.file.replacingOccurrences(of: "captures/", with: "")
            .replacingOccurrences(of: ".png", with: "")
        return "截图 \(id.prefix(6))"
    }

    private func revealInFinder(_ record: CaptureRecord) {
        Task { @MainActor in
            let url = await model.captureStore.fileURL(of: record)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func recopy(_ record: CaptureRecord) {
        Task { @MainActor in
            let url = await model.captureStore.fileURL(of: record)
            if let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([image])
                model.showToast("已重新复制到剪贴板")
            } else {
                model.showToast("读取截图文件失败")
            }
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = model.toast {
            ToastView(text: toast)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 52)
        }
    }
}

// MARK: - 截图预览台（原型 .captures-stage）

struct CaptureStage: View {
    let record: CaptureRecord
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Canvas { context, size in
                    let dot: CGFloat = 14
                    let r: CGFloat = 0.4
                    var y: CGFloat = r
                    while y < size.height {
                        var x: CGFloat = r
                        while x < size.width {
                            context.fill(
                                Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                with: .color(Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.06))
                            )
                            x += dot
                        }
                        y += dot
                    }
                }
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width - 40, height: geo.size.height - 40)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Text("加载中…")
                        .font(.system(size: 12))
                        .foregroundColor(OB.ink3)
                }
            }
        }
        .background(Color(hex: 0xF4F5F7))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(OB.hairline, lineWidth: 0.5)
        )
        .task(id: record.id) {
            guard let path = record.thumbnailFile else { return }
            if let url = await AppModelImageLoader.url(for: path), let data = try? Data(contentsOf: url) {
                image = NSImage(data: data)
            }
        }
    }
}

// MARK: - 截图行（原型 .cap-row）

struct CaptureRowView: View {
    let record: CaptureRecord
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            CaptureThumbView(record: record)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(record.width) × \(record.height)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? OB.accentInk : OB.ink)
                Text(OBTimeFormat.short(record.createdAt))
                    .font(.system(size: 11))
                    .foregroundColor(OB.ink3)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? OB.accentSoft : (isHovering ? OB.surfaceSubtle : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovering = $0 }
    }
}

struct CaptureThumbView: View {
    let record: CaptureRecord
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.white
            }
        }
        .frame(width: 62, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color(red: 15/255, green: 23/255, blue: 42/255, opacity: 0.10), lineWidth: 0.5)
        )
        .task(id: record.id) {
            guard let path = record.thumbnailFile else { return }
            if let url = await AppModelImageLoader.url(for: path), let data = try? Data(contentsOf: url) {
                image = NSImage(data: data)
            }
        }
    }
}
