import Foundation
import Testing
@testable import HotKeys

@Suite("HotKeyMatcher")
struct HotKeyMatcherTests {
    private let leftCtrl = ModifierKey(kind: .control, side: .left)
    private let rightCtrl = ModifierKey(kind: .control, side: .right)
    private let leftOpt = ModifierKey(kind: .option, side: .left)
    private let t0 = Date(timeIntervalSince1970: 1_000)

    @Test("chord matches left control + V, not right control")
    func chordSideSensitive() {
        let spec = HotKeySpec.makeChord(modifiers: [leftCtrl], keyCode: 9)!
        let matcher = HotKeyMatcher()
        matcher.setRegistrations([("clip", spec)])

        #expect(
            matcher.handle(.keyDown(keyCode: 9, heldModifiers: [rightCtrl], at: t0)) == nil
        )
        #expect(
            matcher.handle(.keyDown(keyCode: 9, heldModifiers: [leftCtrl], at: t0)) == "clip"
        )
    }

    @Test("either side matches left and right")
    func eitherMatchesBoth() {
        let either = ModifierKey(kind: .control, side: .either)
        let spec = HotKeySpec.makeChord(modifiers: [either], keyCode: 9)!
        let matcher = HotKeyMatcher()
        matcher.setRegistrations([("clip", spec)])

        #expect(matcher.handle(.keyDown(keyCode: 9, heldModifiers: [leftCtrl], at: t0)) == "clip")
        #expect(matcher.handle(.keyDown(keyCode: 9, heldModifiers: [rightCtrl], at: t0.addingTimeInterval(1))) == "clip")
    }

    @Test("doubleTap left control within window")
    func doubleTapWithinWindow() {
        let spec = HotKeySpec.makeDoubleTap(modifier: leftCtrl)!
        let matcher = HotKeyMatcher()
        matcher.setRegistrations([("clip", spec)])

        #expect(matcher.handle(.modifierDown(leftCtrl, at: t0)) == nil)
        #expect(matcher.handle(.modifierUp(leftCtrl, at: t0.addingTimeInterval(0.05))) == nil)
        #expect(
            matcher.handle(.modifierDown(leftCtrl, at: t0.addingTimeInterval(0.2))) == "clip"
        )
    }

    @Test("doubleTap does not fire across sides")
    func doubleTapWrongSide() {
        let spec = HotKeySpec.makeDoubleTap(modifier: leftCtrl)!
        let matcher = HotKeyMatcher()
        matcher.setRegistrations([("clip", spec)])

        _ = matcher.handle(.modifierDown(leftCtrl, at: t0))
        _ = matcher.handle(.modifierUp(leftCtrl, at: t0.addingTimeInterval(0.05)))
        #expect(matcher.handle(.modifierDown(rightCtrl, at: t0.addingTimeInterval(0.2))) == nil)
    }

    @Test("doubleTap outside 400ms window does not fire")
    func doubleTapTooSlow() {
        let spec = HotKeySpec.makeDoubleTap(modifier: leftCtrl)!
        let matcher = HotKeyMatcher()
        matcher.setRegistrations([("clip", spec)])

        _ = matcher.handle(.modifierDown(leftCtrl, at: t0))
        _ = matcher.handle(.modifierUp(leftCtrl, at: t0.addingTimeInterval(0.05)))
        #expect(
            matcher.handle(.modifierDown(leftCtrl, at: t0.addingTimeInterval(0.5))) == nil
        )
    }

    @Test("setRegistrations clears pending double-tap state so a new hotkey is live immediately")
    func setRegistrationsClearsTapState() {
        let oldSpec = HotKeySpec.makeDoubleTap(modifier: leftCtrl)!
        let newSpec = HotKeySpec.makeChord(modifiers: [leftCtrl], keyCode: 9)!
        let matcher = HotKeyMatcher()
        matcher.setRegistrations([("old", oldSpec)])

        _ = matcher.handle(.modifierDown(leftCtrl, at: t0))
        _ = matcher.handle(.modifierUp(leftCtrl, at: t0.addingTimeInterval(0.05)))

        matcher.setRegistrations([("clip", newSpec)])
        // 旧 double-tap 半截状态不得污染新注册；chord 应立即可用。
        #expect(
            matcher.handle(.modifierDown(leftCtrl, at: t0.addingTimeInterval(0.1))) == nil
        )
        #expect(
            matcher.handle(.keyDown(keyCode: 9, heldModifiers: [leftCtrl], at: t0.addingTimeInterval(0.15))) == "clip"
        )
    }

    @Test("modifiersOnly triggers when second modifier goes down")
    func modifiersOnly() {
        let spec = HotKeySpec.makeModifiersOnly(modifiers: [leftCtrl, leftOpt])!
        let matcher = HotKeyMatcher()
        matcher.setRegistrations([("clip", spec)])

        #expect(matcher.handle(.modifierDown(leftCtrl, at: t0)) == nil)
        #expect(
            matcher.handle(.modifierDown(leftOpt, at: t0.addingTimeInterval(0.1))) == "clip"
        )
    }

    @Test("modifier keyCode mapping")
    func keyCodeMapping() {
        #expect(ModifierKey.fromKeyCode(59) == leftCtrl)
        #expect(ModifierKey.fromKeyCode(62) == rightCtrl)
        #expect(ModifierKey.fromKeyCode(9) == nil)
    }
}
