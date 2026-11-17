import AppKit
import ClipboardStore
import Combine
import Foundation

/// 写入能力：reuse 需要写回 pasteboard。NSPasteboard 原生满足，测试由 FakePasteboard 实现。
internal protocol PasteboardWriting: AnyObject {
    @discardableResult
    func declareTypes(_ types: [NSPasteboard.PasteboardType], owner: Any?) -> Int
    @discardableResult
    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool
    @discardableResult
    func setData(_ data: Data?, forType type: NSPasteboard.PasteboardType) -> Bool
}

extension NSPasteboard: PasteboardWriting {}

/// 剪贴板历史服务：轮询 changeCount、规范化、去重、自写抑制、复用。
/// UI 只依赖本类型，不接触 pasteboard、轮询和哈希细节。
@MainActor
public final class ClipboardHistoryService: ObservableObject {

    private let store: ClipboardStore
    private let pasteboard: PasteboardReading
    private var timer: DispatchSourceTimer?
    private var lastSeenChangeCount: Int = 0

    /// 轮询间隔（测试可注入）；监听中修改会即时生效。
    public var pollInterval: TimeInterval = 0.5 {
        didSet {
            guard isMonitoring, pollInterval != oldValue else { return }
            startTimer()
        }
    }
    public private(set) var isMonitoring: Bool = false
    /// 暂停时不读剪贴板内容，但轮询继续跟踪 changeCount，恢复后不误读暂停期间的旧内容。
    public private(set) var isRecordingPaused: Bool = false
    /// 最近一次采集错误（调试用，正常为 nil）。
    public private(set) var lastError: String?
    /// 列表变化回调（主线程调用）。
    public var onRecordsChanged: (() -> Void)?

    public init(store: ClipboardStore, pasteboard: PasteboardReading = NSPasteboard.general) {
        self.store = store
        self.pasteboard = pasteboard
    }

    deinit {
        // stop() 是正路；deinit 兜底取消 timer，保证对象可释放。
        timer?.cancel()
        timer = nil
    }

    // MARK: - 监听

    /// 开始监听（默认每 0.5s 轮询 changeCount）。
    /// 记录当前 changeCount，启动前已在剪贴板里的内容不会进历史。
    public func start() {
        guard !isMonitoring else { return }
        lastSeenChangeCount = pasteboard.changeCount
        isMonitoring = true
        startTimer()
    }

    /// 停止监听：停止轮询（停用工具时释放开销）。
    public func stop() {
        timer?.cancel()
        timer = nil
        isMonitoring = false
    }

    /// 暂停/恢复记录。返回当前暂停状态。
    @discardableResult
    public func setRecordingPaused(_ paused: Bool) -> Bool {
        isRecordingPaused = paused
        return isRecordingPaused
    }

    // MARK: - 复用

    /// 复用历史：写回 pasteboard 并附带私有标记（监听器据此跳过本次自写），
    /// 同时更新 lastUsedAt/useCount。
    public func reuse(_ record: ClipboardRecord) {
        guard let writer = pasteboard as? PasteboardWriting else {
            lastError = "当前 pasteboard 不支持写入，无法复用"
            return
        }
        let marker = NSPasteboard.PasteboardType(OneBoxPasteboardMarker.type)
        Task { [store] in
            do {
                switch record.kind {
                case .text:
                    guard let text = record.textContent else {
                        throw Self.error("文本记录缺少内容")
                    }
                    writer.declareTypes([.string, marker], owner: nil)
                    writer.setString(text, forType: .string)
                case .image:
                    guard let url = await store.imageURL(of: record),
                          let png = try? Data(contentsOf: url) else {
                        throw Self.error("图片记录缺少文件")
                    }
                    writer.declareTypes([.png, marker], owner: nil)
                    writer.setData(png, forType: .png)
                }
                try await store.updateUsed(id: record.id)
                self.onRecordsChanged?()
            } catch {
                self.lastError = "复用历史失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - 轮询

    private func startTimer() {
        timer?.cancel()
        let interval = max(0.01, pollInterval)
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + interval, repeating: interval)
        // weak 引用：stop 后即使 timer 未清干净也不延长生命周期。
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.pollOnce() }
        }
        source.resume()
        timer = source
    }

    private func pollOnce() {
        let current = pasteboard.changeCount
        guard current != lastSeenChangeCount else { return }
        lastSeenChangeCount = current
        // 暂停：只跟踪 changeCount，不读内容。
        if isRecordingPaused { return }
        // 自写回环：跳过自己写回的内容。
        if pasteboard.declaredTypesContain(OneBoxPasteboardMarker.type) { return }
        guard let content = PasteboardNormalizer.read(from: pasteboard) else { return }
        store(content)
    }

    /// hash 去重入库：命中 → updateUsed；未命中 → insert/insertImage。任何错误跳过本次不崩。
    private func store(_ content: PasteboardNormalizer.NormalizedContent) {
        Task { [store, content] in
            do {
                if let existing = await store.record(contentHash: content.hash) {
                    try await store.updateUsed(id: existing.id)
                } else if let text = content.text {
                    _ = try await store.insert(text: text, hash: content.hash)
                } else if let png = content.pngData {
                    _ = try await store.insertImage(png: png, hash: content.hash)
                }
                self.onRecordsChanged?()
            } catch {
                self.lastError = "记录剪贴板失败：\(error.localizedDescription)"
            }
        }
    }

    private static func error(_ message: String) -> NSError {
        NSError(
            domain: "OneBox.ClipboardHistory", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
