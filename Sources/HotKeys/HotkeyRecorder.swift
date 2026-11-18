import Foundation

/// Pure recording state machine used by the UI hotkey button.
public final class HotkeyRecorder: @unchecked Sendable {
    public enum Outcome: Equatable, Sendable {
        case completed(HotKeySpec)
        case invalid(String)
        case cancelled
        case ignore
    }

    public var doubleTapWindow: TimeInterval = 0.4

    private var held: Set<ModifierKey> = []
    private var peakHeld: Set<ModifierKey> = []
    private var pendingTap: (key: ModifierKey, upAt: Date)?
    private var armedFirstDown: (key: ModifierKey, at: Date)?
    private var sawNonModifierKey = false

    public init() {}

    public func reset() {
        held.removeAll()
        peakHeld.removeAll()
        pendingTap = nil
        armedFirstDown = nil
        sawNonModifierKey = false
    }

    public func modifierDown(_ key: ModifierKey, at: Date = Date()) -> Outcome {
        held.insert(key)
        peakHeld.formUnion(held)

        if let pending = pendingTap,
           pending.key == key,
           at.timeIntervalSince(pending.upAt) <= doubleTapWindow {
            reset()
            if let spec = HotKeySpec.makeDoubleTap(modifier: key) {
                return .completed(spec)
            }
            return .invalid("无法识别该双击修饰键")
        }

        armedFirstDown = (key, at)
        pendingTap = nil
        return .ignore
    }

    public func modifierUp(_ key: ModifierKey, at: Date = Date()) -> Outcome {
        held.remove(key)
        if let armed = armedFirstDown, armed.key == key {
            pendingTap = (key, at)
            armedFirstDown = nil
        }

        // modifiersOnly：多修饰键按过且全部松开、中间没有普通键。
        if held.isEmpty {
            let peak = peakHeld
            let sawKey = sawNonModifierKey
            peakHeld.removeAll()
            sawNonModifierKey = false
            if !sawKey, peak.count >= 2, let spec = HotKeySpec.makeModifiersOnly(modifiers: Array(peak)) {
                pendingTap = nil
                armedFirstDown = nil
                return .completed(spec)
            }
        }
        return .ignore
    }

    public func keyDown(keyCode: Int, at: Date = Date()) -> Outcome {
        if keyCode == 53 { // Escape
            reset()
            return .cancelled
        }
        if ModifierKey.fromKeyCode(keyCode) != nil {
            return .ignore
        }

        sawNonModifierKey = true
        pendingTap = nil
        armedFirstDown = nil
        let mods = Array(held)
        guard let spec = HotKeySpec.makeChord(modifiers: mods, keyCode: keyCode) else {
            return .invalid("需要至少两个键，或双击同一修饰键")
        }
        reset()
        return .completed(spec)
    }
}
