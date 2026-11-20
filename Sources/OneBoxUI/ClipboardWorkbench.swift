import SwiftUI
import ToolLauncherUI
import ToolRegistry
import ClipboardHistory
import ClipboardStore

// MARK: - 剪贴板历史工作台（工具内闭环：列表 + 预览 + 工具内配置）

public struct ClipboardWorkbenchView: View {
    @ObservedObject var model: AppModel
    let onBack: () -> Void
    let onOpenCapture: () -> Void
    var initialSubView: SubView = .main

    public enum SubView {
        case main
        case config
    }

    @State private var subView: SubView = .main
    @State private var searchText = ""
    @State private var filter: ClipboardRecordFilter = .all
    @State private var selectedID: UUID?
    @State private var showClearConfirm = false
    @State private var keyboardMonitor: Any?
    public init(
        model: AppModel,
        onBack: @escaping () -> Void,
        onOpenCapture: @escaping () -> Void,
        initialSubView: SubView = .main
    ) {
        self.model = model
        self.onBack = onBack
        self.onOpenCapture = onOpenCapture
        self.initialSubView = initialSubView
    }

    private var records: [ClipboardRecord] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return model.clipboardRecords.filter { record in
            let filterOK: Bool
            switch filter {
            case .all: filterOK = true
            case .pinned: filterOK = record.pinned
            case .text: filterOK = record.kind == .text
            case .image: filterOK = record.kind == .image
            }
            let searchOK = q.isEmpty
                || (record.textContent ?? "").lowercased().contains(q)
                || record.imageFile?.lowercased().contains(q) == true
            return filterOK && searchOK
        }
    }

    private var selected: ClipboardRecord? {
        if let id = selectedID, let r = records.first(where: { $0.id == id }) { return r }
        return records.first
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
            model.reloadClipboardRecords()
            installKeyboardMonitor()
        }
        .onDisappear {
            if let monitor = keyboardMonitor {
                NSEvent.removeMonitor(monitor)
                keyboardMonitor = nil
            }
        }
        .overlay {
            if showClearConfirm {
                ConfirmModal(
                    title: "清空剪贴板历史？",
                    message: "将删除 \(model.clipboardRecords.count) 条本地记录及对应图片文件，包括已置顶内容，且无法撤销。",
                    confirmTitle: "清空历史",
                    onConfirm: {
                        showClearConfirm = false
                        model.clearClipboardHistory()
                    },
                    onCancel: { showClearConfirm = false }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: 顶栏

    private var topbar: some View {
        ToolTopbar(title: "剪贴板历史", onBack: onBack) {
            HStack(spacing: 10) {
                if subView == .main {
                    InlineSearchField(text: $searchText, placeholder: "搜索文本、图片或来源应用…")
                    OBSegmentedControl(
                        options: [ClipboardRecordFilter.all, .text, .image, .pinned],
                        title: { $0 == .all ? "全部" : $0 == .text ? "文本" : $0 == .image ? "图片" : "置顶" },
                        selection: $filter
                    )
                    RecordStatusButton(isPaused: model.clipboardService.isRecordingPaused) {
                        let paused = model.clipboardService.setRecordingPaused(!model.clipboardService.isRecordingPaused)
                        model.showToast(paused ? "已暂停记录剪贴板" : "已恢复记录剪贴板")
                    }
                }
                OBIconButton(.gear, isActive: subView == .config, title: "剪贴板配置") {
                    subView = subView == .config ? .main : .config
                }
            }
        }
    }

    // MARK: 主视图（列表 + 预览）

    private var mainView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                historyList
                previewColumn
            }
            footer
        }
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if records.isEmpty {
                        VStack(spacing: 14) {
                            EmptyBoxView(
                                icon: .clipboard,
                                title: "还没有剪贴板记录",
                                message: "在任意应用中复制文本或图片，1 秒内自动出现在这里。"
                            )
                            HStack(spacing: 8) {
                                OBButton(title: "试试区域截图", style: .primary, action: onOpenCapture)
                            }
                        }
                        .padding(.top, 60)
                        .padding(.horizontal, 16)
                    } else {
                        ForEach(records) { record in
                            ClipRowView(
                                record: record,
                                isSelected: selected?.id == record.id,
                                onSelect: { selectedID = record.id },
                                onQuickCopy: {
                                    model.clipboardService.reuse(record)
                                    model.showToast("已复制到剪贴板")
                                }
                            )
                            .id(record.id)
                        }
                    }
                }
                .padding(8)
            }
            .onChange(of: selectedID) { _, newID in
                if let newID {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 332)
        .overlay(alignment: .trailing) { Divider().overlay(OB.hairline) }
    }

    private var previewColumn: some View {
        VStack(spacing: 0) {
            if let record = selected {
                // 头部
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(record.kind == .image ? "图片" : "文本") · \(subkindLabel(record))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(OB.ink3)
                        Text(record.kind == .image ? imageTitle(record) : textTitle(record))
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.bottom, 12)

                // 内容
                ClipboardPreviewSurface(record: record)
                    .frame(maxHeight: .infinity)

                // 底部操作
                HStack {
                    Text("\(OBTimeFormat.short(record.lastUsedAt)) · 使用 \(record.useCount) 次 · \(metaText(record))")
                        .font(.system(size: 11.5))
                        .foregroundColor(OB.ink3)
                        .lineLimit(1)
                    Spacer()
                    HStack(spacing: 6) {
                        OBButton(title: "删除", style: .ghost) {
                            model.deleteClipboardRecord(record.id)
                            model.showToast("已删除该条记录")
                        }
                        OBButton(title: record.pinned ? "取消置顶" : "置顶", style: .secondary) {
                            togglePinned(record)
                        }
                        OBButton(title: "复制到剪贴板", style: .primary, kbdShortcut: "⌘↩") {
                            model.clipboardService.reuse(record)
                            model.showToast("已复制到剪贴板")
                        }
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }
                .padding(.top, 12)
            } else {
                EmptyBoxView(icon: .clipboard, title: "选择一条记录", message: "左侧选择条目查看详情")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 16, trailing: 20))
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OB.contentBg)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(model.clipboardRecords.count) 条记录 · 呼出快捷键 ")
                .font(.system(size: 11.5))
                .foregroundColor(OB.ink3)
            Kbd(text: model.settings.hotkeyClipboard.display)
            Spacer()
            OBButton(title: "清空历史", style: .danger) {
                showClearConfirm = true
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
                        Text("剪贴板历史 · 工具配置")
                            .font(.system(size: 16, weight: .semibold))
                        Text("配置自动记录、保留上限与呼出快捷键")
                            .font(.system(size: 12))
                            .foregroundColor(OB.ink3)
                    }
                    Spacer()
                    OBButton(title: "返回列表", style: .secondary) {
                        subView = .main
                    }
                }
                .padding(.bottom, 14)

                SettingsCard {
                    SettingsRow(title: "自动监听系统剪贴板", desc: "检测文本与 PNG/TIFF 图片变化") {
                        OBToggle(isOn: !model.clipboardService.isRecordingPaused) {
                            let paused = model.clipboardService.setRecordingPaused(!model.clipboardService.isRecordingPaused)
                            model.showToast(paused ? "已暂停记录剪贴板" : "已恢复记录剪贴板")
                        }
                    }
                    SettingsRow(title: "工具直达快捷键", desc: "任意应用中按下直接呼出剪贴板列表") {
                        HotkeyButton(spec: model.settings.hotkeyClipboard, onRecord: { spec in
                            model.settings.setHotkey(spec, for: "clipboard")
                            model.showToast("快捷键已更新")
                            if !AccessibilityPermission.isTrusted {
                                _ = AccessibilityPermission.promptIfNeeded()
                                model.showToast("请在系统设置中允许辅助功能后快捷键才会生效")
                            }
                        }, onInvalid: { model.showToast($0) })
                    }
                }

                SettingsCard {
                    SettingsRow(title: "最多保留条目", desc: "超出上限后自动清理最早且未置顶的记录") {
                        StepperView(value: model.settings.clipboardMaxRecords, step: 50, range: 50...2000, unit: " 条") {
                            model.settings.clipboardMaxRecords = $0
                            enforceRetention()
                        }
                    }
                    SettingsRow(title: "自动保留天数", desc: "置顶条目不会触发自动清理") {
                        StepperView(value: model.settings.clipboardRetentionDays, step: 5, range: 7...365, unit: " 天") {
                            model.settings.clipboardRetentionDays = $0
                            enforceRetention()
                        }
                    }
                    SettingsRow(title: "清空全部本地记录", desc: "同步删除本地缩略图与图片文件") {
                        OBButton(title: "清空历史", style: .danger) { showClearConfirm = true }
                    }
                }
            }
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 28, trailing: 28))
        }
        .background(OB.configScroll)
    }

    private func enforceRetention() {
        let store = model.clipboardStore
        let limit = model.settings.clipboardMaxRecords
        let days = model.settings.clipboardRetentionDays
        Task { @MainActor in
            _ = try? await store.enforceRetention(limit: limit, days: days)
            model.reloadClipboardRecords()
        }
    }

    // MARK: 文案辅助

    private func textTitle(_ record: ClipboardRecord) -> String {
        let text = record.textContent ?? ""
        return text.split(separator: "\n").first.map(String.init) ?? "文本"
    }

    private func imageTitle(_ record: ClipboardRecord) -> String {
        let name = record.imageFile?
            .replacingOccurrences(of: "images/", with: "")
            .replacingOccurrences(of: ".png", with: "")
        return (name?.prefix(8).uppercased().map { String($0) }.joined() ?? "") + ".png"
    }

    private func subkindLabel(_ record: ClipboardRecord) -> String {
        if record.kind == .image { return "图片" }
        let text = record.textContent ?? ""
        if text.hasPrefix("http://") || text.hasPrefix("https://") { return "链接" }
        if record.textContent?.contains("\n") == true { return "多行文本" }
        return "文本"
    }

    private func metaText(_ record: ClipboardRecord) -> String {
        if record.kind == .image {
            var parts = ["\(record.imageWidth ?? 0) × \(record.imageHeight ?? 0)"]
            parts.append(OBFormat.bytes(record.byteCount))
            return parts.joined(separator: " · ")
        }
        let text = record.textContent ?? ""
        let lines = max(1, text.components(separatedBy: "\n").count)
        return "\(lines) 行 · \(text.count) 字"
    }

    private func togglePinned(_ record: ClipboardRecord) {
        let store = model.clipboardStore
        let id = record.id
        Task { @MainActor in
            try? await store.setPinned(id: id, !record.pinned)
            model.reloadClipboardRecords()
        }
    }

    private func installKeyboardMonitor() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard subView == .main, !showClearConfirm else { return event }
            guard event.window == NSApp.keyWindow else { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isEditingText = NSApp.keyWindow?.firstResponder is NSTextView

            switch event.specialKey {
            case .downArrow:
                if !flags.contains(.command) {
                    moveSelection(1)
                    return nil
                }
            case .upArrow:
                if !flags.contains(.command) {
                    moveSelection(-1)
                    return nil
                }
            case .carriageReturn:
                if flags.contains(.command) || !isEditingText {
                    if let record = selected {
                        model.clipboardService.reuse(record)
                        model.showToast("已复制到剪贴板")
                        return nil
                    }
                }
            default:
                break
            }
            return event
        }
    }

    private func moveSelection(_ delta: Int) {
        let list = records
        guard !list.isEmpty else { return }
        let currentID = selected?.id
        let idx = currentID.flatMap { id in list.firstIndex(where: { $0.id == id }) } ?? -1
        let next = list[(idx + delta + list.count) % list.count]
        selectedID = next.id
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

// MARK: - 预览内容区（原型 .preview-surface）

struct ClipboardPreviewSurface: View {
    let record: ClipboardRecord

    var body: some View {
        Group {
            if record.kind == .image {
                ImageStage(record: record)
            } else if let text = record.textContent,
                      text.hasPrefix("http://") || text.hasPrefix("https://") || looksLikeCode(text) {
                ScrollView {
                    Text(record.textContent ?? "")
                        .font(.system(size: 12.5).monospaced())
                        .foregroundColor(OB.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
                }
            } else {
                ScrollView {
                    Text(record.textContent ?? "")
                        .font(.system(size: 13.5))
                        .foregroundColor(OB.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(OB.cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(OB.hairline, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func looksLikeCode(_ text: String) -> Bool {
        let markers = ["func ", "import ", "let ", "var ", "class ", "swift", "git ", "npm ", "{", "};"]
        return markers.contains { text.contains($0) }
    }
}

/// 图片预览：点阵底 + 图片自适应。
struct ImageStage: View {
    let record: ClipboardRecord
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 点阵底
                Canvas { context, size in
                    let dot: CGFloat = 14
                    let r: CGFloat = 0.4
                    var y: CGFloat = r
                    while y < size.height {
                        var x: CGFloat = r
                        while x < size.width {
                            context.fill(
                                Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                with: .color(OB.surfaceHover)
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
                    Text("图片加载中…")
                        .font(.system(size: 12))
                        .foregroundColor(OB.ink3)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(OB.previewBg)
        .task {
            guard let path = record.imageFile else { return }
            let url = await AppModelImageLoader.url(for: path)
            if let url, let data = try? Data(contentsOf: url) {
                image = NSImage(data: data)
            }
        }
    }
}

enum AppModelImageLoader {
    static func url(for relativePath: String) async -> URL? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OneBox", isDirectory: true)
        return base.appendingPathComponent(relativePath)
    }
}

// MARK: - 历史行（原型 .clip-row）

struct ClipRowView: View {
    let record: ClipboardRecord
    let isSelected: Bool
    let onSelect: () -> Void
    let onQuickCopy: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            thumb
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if record.pinned {
                        StatusDot(standby: true)
                    }
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isSelected ? OB.accentInk : OB.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(OBTimeFormat.short(record.lastUsedAt))
                        .font(.system(size: 11))
                        .foregroundColor(OB.ink3)
                        .monospacedDigit()
                }
                HStack(spacing: 6) {
                    Text(excerpt)
                        .font(.system(size: 11.5))
                        .foregroundColor(OB.ink2)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isHovering || isSelected {
                        Button(action: onQuickCopy) {
                            OBIcon(.copy, size: 12.5, weight: 1.65)
                                .foregroundColor(OB.ink2)
                                .frame(width: 22, height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(OB.cardSurface)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("快速复制")
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 9, leading: 10, bottom: 9, trailing: 10))
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? OB.accentSoft : (isHovering ? OB.surfaceSubtle : Color.clear))
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(OB.brandYellow)
                    .frame(width: 3, height: 22)
                    .padding(.leading, 3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var thumb: some View {
        let icon = thumbIcon
        Group {
            if record.kind == .image, let thumbPath = record.thumbnailFile {
                ThumbImageView(path: thumbPath)
            } else {
                OBIcon(icon.icon, size: 16, weight: 1.65)
                    .foregroundColor(icon.color)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(icon.background)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(OB.hairline, lineWidth: 0.5)
                    )
            }
        }
    }

    private var thumbIcon: (icon: OBIcon.ID, color: Color, background: Color) {
        if record.kind == .image { return (.image, OB.ink2, OB.surfaceSubtle) }
        let text = record.textContent ?? ""
        if text.hasPrefix("http://") || text.hasPrefix("https://") {
            return (.link, OB.green, OB.greenSoft)
        }
        if text.contains("{") || text.contains("func ") || text.contains("import ") || text.contains("\n") {
            return (.code, OB.ink, OB.surfaceHover)
        }
        return (.lines, OB.ink2, OB.surfaceSubtle)
    }

    private var title: String {
        if record.kind == .image {
            return "图片 · \(record.imageWidth ?? 0) × \(record.imageHeight ?? 0)"
        }
        let text = record.textContent ?? ""
        return text.split(separator: "\n").first.map(String.init) ?? "文本"
    }

    private var excerpt: String {
        if record.kind == .image {
            return "PNG 图像 · \(OBFormat.bytes(record.byteCount))"
        }
        let text = (record.textContent ?? "")
            .replacingOccurrences(of: "\n", with: " ")
        return String(text.prefix(80))
    }
}

struct ThumbImageView: View {
    let path: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                OB.previewBg
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(OB.hairline, lineWidth: 0.5)
        )
        .task {
            if let url = await AppModelImageLoader.url(for: path), let data = try? Data(contentsOf: url) {
                image = NSImage(data: data)
            }
        }
    }
}
