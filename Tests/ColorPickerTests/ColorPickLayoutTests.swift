import Foundation
import CoreGraphics
import Testing
@testable import ColorPicker

@Suite("ColorPickLayout")
struct ColorPickLayoutTests {

    @Test("main screen origin window keeps local ≈ screen")
    func mainScreenNearOrigin() {
        let window = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let screenPoint = CGPoint(x: 400, y: 600)
        let local = ColorPickLayout.contentPoint(screenPoint: screenPoint, windowFrame: window)
        #expect(local == CGPoint(x: 400, y: 600))
    }

    @Test("large / secondary display subtracts window origin so HUD stays near cursor")
    func largeDisplayOffset() {
        // 外接大屏常见：原点不在 (0,0)
        let window = CGRect(x: 1920, y: -200, width: 2560, height: 1440)
        let screenPoint = CGPoint(x: 1920 + 120, y: -200 + 800)
        let local = ColorPickLayout.contentPoint(screenPoint: screenPoint, windowFrame: window)
        #expect(local == CGPoint(x: 120, y: 800))
    }
}
