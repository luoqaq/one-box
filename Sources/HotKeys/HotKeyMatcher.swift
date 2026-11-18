import Foundation

/// Observes synthetic key events and matches against registered `HotKeySpec`s.
public final class HotKeyMatcher: @unchecked Sendable {
    public enum Event: Sendable {
        case modifierDown(ModifierKey, at: Date)
        case modifierUp(ModifierKey, at: Date)
        case keyDown(keyCode: Int, heldModifiers: [ModifierKey], at: Date)
    }

    public var doubleTapWindow: TimeInterval = 0.4

    private var registrations: [(id: String, spec: HotKeySpec)] = []
    private var held: Set<ModifierKey> = []
    private var pendingTap: (key: ModifierKey, upAt: Date)?
    private var armedFirstDown: (key: ModifierKey, at: Date)?

    public init() {}

    public func setRegistrations(_ items: [(id: String, spec: HotKeySpec)]) {
        registrations = items
        // 更换热键后清掉半截双击 / 按住状态，避免第一次按新键被旧状态吞掉。
        held.removeAll()
        clearTapState()
    }

    @discardableResult
    public func handle(_ event: Event) -> String? {
        switch event {
        case .modifierDown(let key, let at):
            return handleModifierDown(key, at: at)
        case .modifierUp(let key, let at):
            handleModifierUp(key, at: at)
            return nil
        case .keyDown(let keyCode, let heldModifiers, _):
            clearTapState()
            return matchChord(keyCode: keyCode, held: heldModifiers)
        }
    }

    private func handleModifierDown(_ key: ModifierKey, at: Date) -> String? {
        held.insert(key)

        if let pending = pendingTap,
           pending.key == key,
           at.timeIntervalSince(pending.upAt) <= doubleTapWindow {
            clearTapState()
            if let id = matchDoubleTap(key) {
                return id
            }
        } else {
            armedFirstDown = (key, at)
            pendingTap = nil
        }

        return matchModifiersOnly()
    }

    private func handleModifierUp(_ key: ModifierKey, at: Date) {
        held.remove(key)
        if let armed = armedFirstDown, armed.key == key {
            pendingTap = (key, at)
            armedFirstDown = nil
        }
    }

    private func clearTapState() {
        pendingTap = nil
        armedFirstDown = nil
    }

    private func matchDoubleTap(_ key: ModifierKey) -> String? {
        for item in registrations {
            if case .doubleTap(let required) = item.spec, required.matches(key) {
                return item.id
            }
        }
        return nil
    }

    private func matchModifiersOnly() -> String? {
        let heldList = Array(held)
        for item in registrations {
            guard case .modifiersOnly(let required) = item.spec else { continue }
            if modifiersMatch(required: required, held: heldList, exact: true) {
                return item.id
            }
        }
        return nil
    }

    private func matchChord(keyCode: Int, held heldMods: [ModifierKey]) -> String? {
        guard ModifierKey.fromKeyCode(keyCode) == nil else { return nil }
        for item in registrations {
            guard case .chord(let required, let code) = item.spec, code == keyCode else { continue }
            if modifiersMatch(required: required, held: heldMods, exact: false) {
                return item.id
            }
        }
        return nil
    }

    /// Each required modifier consumes one matching held key. `exact` also requires no leftover held keys.
    private func modifiersMatch(required: [ModifierKey], held: [ModifierKey], exact: Bool) -> Bool {
        var remaining = held
        for req in required {
            guard let idx = remaining.firstIndex(where: { req.matches($0) }) else { return false }
            remaining.remove(at: idx)
        }
        return exact ? remaining.isEmpty : true
    }
}
