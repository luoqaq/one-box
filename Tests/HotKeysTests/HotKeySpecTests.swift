import Foundation
import Testing
@testable import HotKeys

@Suite("HotKeySpec")
struct HotKeySpecTests {
    @Test("legacy JSON migrates to chord with either sides")
    func legacyMigration() throws {
        let json = """
        {"keyCode":9,"modifiers":["control","option"]}
        """.data(using: .utf8)!
        let spec = try JSONDecoder().decode(HotKeySpec.self, from: json)
        guard case .chord(let mods, let keyCode) = spec else {
            Issue.record("expected chord, got \(spec)")
            return
        }
        #expect(keyCode == 9)
        #expect(mods.count == 2)
        #expect(mods.contains(where: { $0.kind == .control && $0.side == .either }))
        #expect(mods.contains(where: { $0.kind == .option && $0.side == .either }))
    }

    @Test("chord display uses side labels and key name")
    func chordDisplay() {
        let spec = HotKeySpec.makeChord(
            modifiers: [
                ModifierKey(kind: .control, side: .left),
                ModifierKey(kind: .option, side: .right),
            ],
            keyCode: 9
        )!
        #expect(spec.displayTokens == ["左⌃", "右⌥", "V"])
        #expect(spec.display == "左⌃右⌥V")
    }

    @Test("doubleTap display")
    func doubleTapDisplay() {
        let spec = HotKeySpec.makeDoubleTap(modifier: ModifierKey(kind: .control, side: .left))!
        #expect(spec.displayTokens == ["双击左⌃"])
    }

    @Test("either side displays without left/right prefix")
    func eitherDisplay() {
        let key = ModifierKey(kind: .shift, side: .either)
        #expect(key.display == "⇧")
    }

    @Test("validate rejects bare key and single modifier")
    func validateRules() {
        #expect(HotKeySpec.makeChord(modifiers: [], keyCode: 9) == nil)
        #expect(HotKeySpec.makeModifiersOnly(modifiers: [ModifierKey(kind: .control, side: .left)]) == nil)
        #expect(
            HotKeySpec.makeModifiersOnly(modifiers: [
                ModifierKey(kind: .control, side: .left),
                ModifierKey(kind: .option, side: .left),
            ]) != nil
        )
        #expect(HotKeySpec.makeDoubleTap(modifier: ModifierKey(kind: .control, side: .left)) != nil)
    }

    @Test("round-trip new format")
    func roundTrip() throws {
        let original = HotKeySpec.makeDoubleTap(modifier: ModifierKey(kind: .control, side: .right))!
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotKeySpec.self, from: data)
        #expect(decoded == original)
    }

    @Test("expanded key names")
    func keyNames() {
        #expect(HotKeySpec.keyName(126) == "↑")
        #expect(HotKeySpec.keyName(124) == "→")
        #expect(HotKeySpec.keyName(125) == "↓")
        #expect(HotKeySpec.keyName(123) == "←")
        #expect(HotKeySpec.keyName(18) == "1")
        #expect(HotKeySpec.keyName(83) == "Num1")
    }
}
