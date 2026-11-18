import AppKit
import ApplicationServices
import Combine
import HotKeys
import OneBoxUI

// MARK: - 全局热键（事件监听 + HotKeyMatcher）

final class HotKeyCenter {
    private let matcher = HotKeyMatcher()
    private var registrations: [String: HotKeySpec] = [:]
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private let sideTracker = ModifierFlagTracker()
    private var previousFlags: NSEvent.ModifierFlags = []
    private var didNotifyMissingAX = false
    private let callbackQueue = DispatchQueue.main

    /// 无辅助功能权限时由 AppDelegate 展示引导。
    var onAccessibilityRequired: () -> Void = {}
    var onTrigger: (String) -> Void = { _ in }

    deinit {
        stopMonitors()
    }

    /// 注册/更新一个热键（仅写入表；调用 `refreshAccessibility()` 启动监听）。
    func register(id: String, spec: HotKeySpec) {
        registrations[id] = spec
        refreshMatcher()
        resyncModifierState()
    }

    func unregister(id: String) {
        registrations.removeValue(forKey: id)
        refreshMatcher()
        resyncModifierState()
        if registrations.isEmpty {
            stopMonitors()
        }
    }

    func unregisterAll() {
        registrations.removeAll()
        refreshMatcher()
        resyncModifierState()
        stopMonitors()
    }

    /// 录制快捷键时本地 monitor 会吞掉 flags，导致 tracker 与真实按键脱节；换绑后强制对齐。
    func resyncModifierState() {
        sideTracker.reset()
        previousFlags = []
    }

    /// 根据辅助功能权限启停全局监听。返回是否已在监听。
    @discardableResult
    func refreshAccessibility() -> Bool {
        guard !registrations.isEmpty else {
            stopMonitors()
            return true
        }
        return ensureMonitoring()
    }

    private func refreshMatcher() {
        let items = registrations.map { (id: $0.key, spec: $0.value) }
        matcher.setRegistrations(items)
    }

    private func ensureMonitoring() -> Bool {
        guard AccessibilityPermission.isTrusted else {
            stopMonitors()
            if !didNotifyMissingAX {
                didNotifyMissingAX = true
                onAccessibilityRequired()
            }
            return false
        }
        didNotifyMissingAX = false
        startMonitorsIfNeeded()
        return true
    }

    private func startMonitorsIfNeeded() {
        guard localMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.process(event)
            return event // 不吞键
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.process(event)
        }
    }

    private func stopMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        sideTracker.reset()
        previousFlags = []
    }

    private func process(_ event: NSEvent) {
        let now = Date()
        switch event.type {
        case .flagsChanged:
            guard let mod = ModifierKey.fromKeyCode(Int(event.keyCode)) else { return }
            let flag = flagMask(mod.kind)
            let wasDown = previousFlags.contains(flag)
            let isDown = event.modifierFlags.contains(flag)
            previousFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            for transition in sideTracker.apply(key: mod, kindWasDown: wasDown, kindIsDown: isDown) {
                switch transition {
                case .down(let key):
                    emit(matcher.handle(.modifierDown(key, at: now)))
                case .up(let key):
                    emit(matcher.handle(.modifierUp(key, at: now)))
                }
            }
        case .keyDown:
            let code = Int(event.keyCode)
            if ModifierKey.fromKeyCode(code) != nil { return }
            emit(matcher.handle(.keyDown(keyCode: code, heldModifiers: Array(sideTracker.held), at: now)))
        default:
            break
        }
    }

    private func emit(_ id: String?) {
        guard let id else { return }
        callbackQueue.async { [onTrigger] in
            onTrigger(id)
        }
    }

    private func flagMask(_ kind: ModifierKind) -> NSEvent.ModifierFlags {
        switch kind {
        case .control: return .control
        case .option: return .option
        case .shift: return .shift
        case .command: return .command
        }
    }
}
