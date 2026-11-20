import SwiftUI
import Combine
import ToolRegistry
import ClipboardHistory
import ClipboardStore
import CaptureStore
import ScreenCapture
import ColorPicker

// MARK: - 应用模型：依赖组装 + 列表缓存 + Toast

@MainActor
public final class AppModel: ObservableObject {
    public let registry: ToolRegistry
    public let settings: AppSettings
    public let clipboardStore: ClipboardStore
    public let captureStore: CaptureStore
    public let clipboardService: ClipboardHistoryService
    public let captureService: ScreenCaptureService
    public let colorPickService: ColorPickService

    @Published public private(set) var clipboardRecords: [ClipboardRecord] = []
    @Published public private(set) var captures: [CaptureRecord] = []
    @Published public var toast: String?

    private var toastTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    public init(registry: ToolRegistry, settings: AppSettings) throws {
        self.registry = registry
        self.settings = settings
        self.clipboardStore = try ClipboardStore()
        self.captureStore = try CaptureStore()
        self.clipboardService = ClipboardHistoryService(store: clipboardStore)
        self.captureService = ScreenCaptureService()
        self.colorPickService = ColorPickService()
        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        clipboardService.onRecordsChanged = { [weak self] in
            self?.reloadClipboardRecords()
        }
    }

    // MARK: 剪贴板历史

    public func reloadClipboardRecords() {
        let store = clipboardStore
        Task { @MainActor in
            let records = await store.records(limit: 500)
            self.clipboardRecords = records
        }
    }

    public func clipboardRecord(_ id: UUID) -> ClipboardRecord? {
        clipboardRecords.first { $0.id == id }
    }


    /// 停用剪贴板工具时清空内存中的列表缓存（磁盘历史保留）。
    public func clearClipboardMemoryCache() {
        clipboardRecords = []
    }
    public func deleteClipboardRecord(_ id: UUID) {
        let store = clipboardStore
        Task { @MainActor in
            try? await store.delete(id: id)
            self.reloadClipboardRecords()
        }
    }

    public func clearClipboardHistory() {
        let store = clipboardStore
        Task { @MainActor in
            try? await store.clear()
            self.reloadClipboardRecords()
            self.showToast("本地记录已清空")
        }
    }

    // MARK: 最近截图

    public func reloadCaptures() {
        let store = captureStore
        Task { @MainActor in
            let records = await store.records(limit: 100)
            self.captures = records
        }
    }

    public func deleteCapture(_ id: UUID) {
        let store = captureStore
        Task { @MainActor in
            try? await store.delete(id: id)
            self.reloadCaptures()
        }
    }

    public func clearAllLocalData() {
        let clipStore = clipboardStore
        let capStore = captureStore
        Task { @MainActor in
            try? await clipStore.clear()
            try? await capStore.clear()
            self.reloadClipboardRecords()
            self.reloadCaptures()
            self.showToast("本地记录已清空")
        }
    }

    public func totalStorageBytes() async -> Int64 {
        await clipboardStore.totalBytes() + captureStore.totalBytes()
    }

    // MARK: Toast

    public func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if !Task.isCancelled { self.toast = nil }
        }
    }
}

// MARK: - 时间格式

enum OBTimeFormat {
    static func short(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let time = DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 \(time)"
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "M月d日"
        return "\(df.string(from: date)) \(time)"
    }

    static func captureTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let time = timeFormatter.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) {
            return "今日 \(time) 截图"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 \(time) 截图"
        }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.dateFormat = "M月d日"
        return "\(dateFormatter.string(from: date)) \(time) 截图"
    }
}

// MARK: - 工具函数

enum OBFormat {
    static func bytes(_ count: Int) -> String {
        guard count > 0 else { return "0 KB" }
        let kb = Double(count) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }

    static func bytes(_ count: Int64) -> String {
        bytes(Int(count))
    }
}
