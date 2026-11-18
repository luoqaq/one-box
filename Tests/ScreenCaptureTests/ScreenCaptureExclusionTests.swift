import CoreGraphics
import Testing
@testable import ScreenCapture

/// 捕获时按窗口 ID 排除遮罩，避免先 orderOut 再截导致画面跳变。
@Suite
struct ScreenCaptureExclusionTests {

    @Test func resolveExcludedKeepsOnlyAvailableRequestedIDs() {
        let resolved = ScreenCaptureExclusion.resolveWindowIDs(
            requested: [10, 20, 30, 40],
            available: [20, 40, 99]
        )
        #expect(resolved == [20, 40])
    }

    @Test func resolveExcludedEmptyWhenNothingMatches() {
        let resolved = ScreenCaptureExclusion.resolveWindowIDs(
            requested: [1, 2],
            available: [8, 9]
        )
        #expect(resolved.isEmpty)
    }
}
