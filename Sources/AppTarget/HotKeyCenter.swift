import AppKit
import Carbon.HIToolbox
import Combine
import ToolRegistry
import ToolLauncherUI
import OneBoxUI
import ClipboardHistory
import ScreenCapture
import CaptureStore

// MARK: - 全局热键（Carbon RegisterEventHotKey）

final class HotKeyCenter {
    struct Registration {
        let id: String
        let ref: EventHotKeyRef
        var spec: HotKeySpec
    }

    private var handler: EventHandlerRef?
    private var registrations: [String: Registration] = [:]
    private let callbackQueue = DispatchQueue.main
    var onTrigger: (String) -> Void = { _ in }

    init() {
        installHandler()
    }

    /// 注册/更新一个热键；返回 false 表示组合被占用或非法。
    @discardableResult
    func register(id: String, spec: HotKeySpec) -> Bool {
        // 至少一个修饰键，避免吞掉普通按键。
        guard !spec.modifiers.isEmpty else { return false }
        unregister(id: id)

        var carbonModifiers: UInt32 = 0
        if spec.modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if spec.modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if spec.modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if spec.modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }

        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(spec.keyCode),
            carbonModifiers,
            EventHotKeyID(signature: OSType(0x4F425831), id: UInt32(id.hashValue & 0x7FFFFFFF)),
            GetEventMonitorTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let ref = hotKeyRef else { return false }
        registrations[id] = Registration(id: id, ref: ref, spec: spec)
        return true
    }

    func unregister(id: String) {
        if let reg = registrations.removeValue(forKey: id) {
            UnregisterEventHotKey(reg.ref)
        }
    }

    func unregisterAll() {
        for id in Array(registrations.keys) {
            unregister(id: id)
        }
    }

    private func installHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                               nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            center.handleHotKey(signature: hkID.signature, rawID: hkID.id)
            return noErr
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventMonitorTarget(), callback, 1, &eventSpec, selfPtr, &handler)
    }

    private func handleHotKey(signature: OSType, rawID: UInt32) {
        guard signature == OSType(0x4F425831) else { return }
        // hash 值反查 id 不可靠，改为遍历比对注册表 hash。
        guard let reg = registrations.values.first(where: { UInt32($0.id.hashValue & 0x7FFFFFFF) == rawID }) else { return }
        let id = reg.id
        callbackQueue.async { [onTrigger] in
            onTrigger(id)
        }
    }
}
