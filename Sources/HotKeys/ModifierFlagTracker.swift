import Foundation

/// Tracks left/right modifier sides across `flagsChanged`-style updates.
public final class ModifierFlagTracker: @unchecked Sendable {
    public private(set) var held: Set<ModifierKey> = []

    public init() {}

    public func reset() {
        held.removeAll()
    }

    public enum Transition: Equatable, Sendable {
        case down(ModifierKey)
        case up(ModifierKey)
    }

    /// - Parameters:
    ///   - key: physical modifier key from the event keyCode
    ///   - kindWasDown: whether this kind's flag was on before the event
    ///   - kindIsDown: whether this kind's flag is on after the event
    @discardableResult
    public func apply(
        key: ModifierKey,
        kindWasDown: Bool,
        kindIsDown: Bool
    ) -> [Transition] {
        if !kindWasDown && kindIsDown {
            held.insert(key)
            return [.down(key)]
        }
        if kindWasDown && !kindIsDown {
            let removing = held.filter { $0.kind == key.kind }
            held.subtract(removing)
            return removing.map { .up($0) }
        }
        if kindIsDown {
            if held.contains(key) {
                held.remove(key)
                return [.up(key)]
            } else {
                held.insert(key)
                return [.down(key)]
            }
        }
        return []
    }
}
