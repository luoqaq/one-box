import Foundation

// MARK: - Modifier identity (kind + side)

public enum ModifierKind: String, Codable, CaseIterable, Sendable, Hashable {
    case control, option, shift, command

    public var symbol: String {
        switch self {
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        case .command: return "⌘"
        }
    }
}

/// `either` is only for migrated legacy shortcuts (match left or right).
public enum ModifierSide: String, Codable, Sendable, Hashable {
    case left, right, either

    public var labelPrefix: String {
        switch self {
        case .left: return "左"
        case .right: return "右"
        case .either: return ""
        }
    }
}

public struct ModifierKey: Codable, Equatable, Sendable, Hashable {
    public var kind: ModifierKind
    public var side: ModifierSide

    public init(kind: ModifierKind, side: ModifierSide) {
        self.kind = kind
        self.side = side
    }

    public var display: String {
        side.labelPrefix + kind.symbol
    }

    /// Carbon / HID virtual key codes for modifier keys.
    public static func fromKeyCode(_ keyCode: Int) -> ModifierKey? {
        switch keyCode {
        case 59: return ModifierKey(kind: .control, side: .left)
        case 62: return ModifierKey(kind: .control, side: .right)
        case 58: return ModifierKey(kind: .option, side: .left)
        case 61: return ModifierKey(kind: .option, side: .right)
        case 56: return ModifierKey(kind: .shift, side: .left)
        case 60: return ModifierKey(kind: .shift, side: .right)
        case 55: return ModifierKey(kind: .command, side: .left)
        case 54: return ModifierKey(kind: .command, side: .right)
        default: return nil
        }
    }

    public var keyCode: Int? {
        switch (kind, side) {
        case (.control, .left): return 59
        case (.control, .right): return 62
        case (.option, .left): return 58
        case (.option, .right): return 61
        case (.shift, .left): return 56
        case (.shift, .right): return 60
        case (.command, .left): return 55
        case (.command, .right): return 54
        default: return nil
        }
    }

    public func matches(_ held: ModifierKey) -> Bool {
        kind == held.kind && (side == .either || side == held.side)
    }
}

// MARK: - HotKeySpec

public enum HotKeySpec: Equatable, Sendable {
    case chord(modifiers: [ModifierKey], keyCode: Int)
    case modifiersOnly(modifiers: [ModifierKey])
    case doubleTap(modifier: ModifierKey)

    /// 默认：⌃⌥Space（打开工具箱）— either 侧以兼容旧行为
    public static let launcherDefault = makeChord(
        modifiers: [
            ModifierKey(kind: .control, side: .either),
            ModifierKey(kind: .option, side: .either),
        ],
        keyCode: 49
    )!

    /// 默认：⌃⌥V
    public static let clipboardDefault = makeChord(
        modifiers: [
            ModifierKey(kind: .control, side: .either),
            ModifierKey(kind: .option, side: .either),
        ],
        keyCode: 9
    )!

    /// 默认：⌃⌥⇧4
    public static let captureDefault = makeChord(
        modifiers: [
            ModifierKey(kind: .control, side: .either),
            ModifierKey(kind: .option, side: .either),
            ModifierKey(kind: .shift, side: .either),
        ],
        keyCode: 21
    )!

    /// 默认：⌃⌥C
    public static let colorPickerDefault = makeChord(
        modifiers: [
            ModifierKey(kind: .control, side: .either),
            ModifierKey(kind: .option, side: .either),
        ],
        keyCode: 8
    )!

    public static func makeChord(modifiers: [ModifierKey], keyCode: Int) -> HotKeySpec? {
        guard !modifiers.isEmpty, ModifierKey.fromKeyCode(keyCode) == nil else { return nil }
        return .chord(modifiers: modifiers, keyCode: keyCode)
    }

    public static func makeModifiersOnly(modifiers: [ModifierKey]) -> HotKeySpec? {
        let unique = Array(Set(modifiers))
        guard unique.count >= 2 else { return nil }
        return .modifiersOnly(modifiers: unique)
    }

    public static func makeDoubleTap(modifier: ModifierKey) -> HotKeySpec? {
        .doubleTap(modifier: modifier)
    }

    public var displayTokens: [String] {
        switch self {
        case .chord(let mods, let keyCode):
            return mods.map(\.display) + [Self.keyName(keyCode)]
        case .modifiersOnly(let mods):
            return mods.map(\.display)
        case .doubleTap(let mod):
            return ["双击\(mod.display)"]
        }
    }

    public var display: String {
        displayTokens.joined()
    }

    public static func keyName(_ keyCode: Int) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36, 76: return "↩"
        case 53: return "⎋"
        case 48: return "⇥"
        case 51: return "⌫"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 115: return "↖"
        case 119: return "↘"
        case 116: return "⇞"
        case 121: return "⇟"
        case 0: return "A"
        case 11: return "B"
        case 8: return "C"
        case 2: return "D"
        case 14: return "E"
        case 3: return "F"
        case 5: return "G"
        case 4: return "H"
        case 34: return "I"
        case 38: return "J"
        case 40: return "K"
        case 37: return "L"
        case 46: return "M"
        case 45: return "N"
        case 31: return "O"
        case 35: return "P"
        case 12: return "Q"
        case 15: return "R"
        case 1: return "S"
        case 17: return "T"
        case 32: return "U"
        case 9: return "V"
        case 13: return "W"
        case 7: return "X"
        case 16: return "Y"
        case 6: return "Z"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        case 29: return "0"
        case 27: return "-"
        case 24: return "="
        case 33: return "["
        case 30: return "]"
        case 41: return ";"
        case 39: return "'"
        case 42: return "\\"
        case 43: return ","
        case 47: return "."
        case 44: return "/"
        case 50: return "`"
        case 82: return "Num0"
        case 83: return "Num1"
        case 84: return "Num2"
        case 85: return "Num3"
        case 86: return "Num4"
        case 87: return "Num5"
        case 88: return "Num6"
        case 89: return "Num7"
        case 91: return "Num8"
        case 92: return "Num9"
        case 65: return "Num."
        case 67: return "Num*"
        case 69: return "Num+"
        case 75: return "Num/"
        case 78: return "Num-"
        case 81: return "Num="
        case 71: return "NumClear"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:
            return "键\(keyCode)"
        }
    }
}

// MARK: - Codable (new + legacy)

extension HotKeySpec: Codable {
    private enum Kind: String, Codable {
        case chord, modifiersOnly, doubleTap
    }

    private enum CodingKeys: String, CodingKey {
        case type, modifiers, keyCode, modifier
    }

    /// Legacy flat shape: `{ "keyCode": 9, "modifiers": ["control","option"] }`
    private struct Legacy: Codable {
        var keyCode: Int
        var modifiers: [ModifierKind]
    }

    public init(from decoder: Decoder) throws {
        if let legacy = try? Legacy(from: decoder) {
            let mods = legacy.modifiers.map { ModifierKey(kind: $0, side: .either) }
            guard let spec = HotKeySpec.makeChord(modifiers: mods, keyCode: legacy.keyCode) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "invalid legacy hotkey")
                )
            }
            self = spec
            return
        }

        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(Kind.self, forKey: .type)
        switch type {
        case .chord:
            let mods = try c.decode([ModifierKey].self, forKey: .modifiers)
            let keyCode = try c.decode(Int.self, forKey: .keyCode)
            guard let spec = HotKeySpec.makeChord(modifiers: mods, keyCode: keyCode) else {
                throw DecodingError.dataCorruptedError(forKey: .keyCode, in: c, debugDescription: "invalid chord")
            }
            self = spec
        case .modifiersOnly:
            let mods = try c.decode([ModifierKey].self, forKey: .modifiers)
            guard let spec = HotKeySpec.makeModifiersOnly(modifiers: mods) else {
                throw DecodingError.dataCorruptedError(forKey: .modifiers, in: c, debugDescription: "invalid modifiersOnly")
            }
            self = spec
        case .doubleTap:
            let mod = try c.decode(ModifierKey.self, forKey: .modifier)
            self = .doubleTap(modifier: mod)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .chord(let mods, let keyCode):
            try c.encode(Kind.chord, forKey: .type)
            try c.encode(mods, forKey: .modifiers)
            try c.encode(keyCode, forKey: .keyCode)
        case .modifiersOnly(let mods):
            try c.encode(Kind.modifiersOnly, forKey: .type)
            try c.encode(mods, forKey: .modifiers)
        case .doubleTap(let mod):
            try c.encode(Kind.doubleTap, forKey: .type)
            try c.encode(mod, forKey: .modifier)
        }
    }
}
