import AppKit
import Combine
import ToolRegistry
import OneBoxUI
import ClipboardHistory

// MARK: - 工具生命周期引擎：按需启用/懒加载，停用立即释放监听、热键与内存开销

@MainActor
final class ToolEngine {
    private let model: AppModel
    private let openDestination: (ToolDestination) -> Void
    private var cancellables: Set<AnyCancellable> = []
    private var clipboardRunning = false

    init(model: AppModel, openDestination: @escaping (ToolDestination) -> Void) {
        self.model = model
        self.openDestination = openDestination
    }

    /// 订阅注册表状态：首次启动时按当前启用状态拉起各工具运行时。
    func start() {
        if model.registry.isEnabled("clipboard") {
            startClipboard()
        }
        observeChanges()
    }

    private func observeChanges() {
        // states 是字典，任何工具变更都会触发；逐工具对账。
        model.registry.$states
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.model.registry.isEnabled("clipboard") {
                    if !self.clipboardRunning { self.startClipboard() }
                } else if self.clipboardRunning {
                    self.stopClipboard()
                }
                // 截图工具没有常驻监听：热键注册/注销由 AppDelegate 的 syncHotkeys 处理，
                // 遮罩窗口与渲染上下文在触发时才创建。
            }
            .store(in: &cancellables)
    }

    private func startClipboard() {
        model.clipboardService.start()
        model.reloadClipboardRecords()
        clipboardRunning = true
    }

    /// 停用：停止轮询、清空内存缓存（列表缓存），磁盘历史保留。
    private func stopClipboard() {
        model.clipboardService.stop()
        model.clearClipboardMemoryCache()
        clipboardRunning = false
    }
}
