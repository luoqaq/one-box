import Testing
@testable import HotKeys

@Suite("ModifierFlagTracker")
struct ModifierFlagTrackerTests {
    private let leftCtrl = ModifierKey(kind: .control, side: .left)
    private let rightCtrl = ModifierKey(kind: .control, side: .right)

    @Test("releasing one side while other remains")
    func releaseOneSide() {
        let tracker = ModifierFlagTracker()
        _ = tracker.apply(key: leftCtrl, kindWasDown: false, kindIsDown: true)
        _ = tracker.apply(key: rightCtrl, kindWasDown: true, kindIsDown: true)
        #expect(tracker.held == [leftCtrl, rightCtrl])

        let transitions = tracker.apply(key: rightCtrl, kindWasDown: true, kindIsDown: true)
        #expect(transitions == [.up(rightCtrl)])
        #expect(tracker.held == [leftCtrl])
    }
}
