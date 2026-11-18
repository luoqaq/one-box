import AppKit
import Testing
@testable import ScreenCapture

/// 截屏遮罩窗口必须能盖在其他 App 的全屏 Space 上（双屏时尤其关键）。
/// Apple DTS：用 NSPanel + nonactivatingPanel，并配 canJoinAllSpaces / fullScreenAuxiliary；
/// 普通 NSWindow 即便设了同样 flag，也会被钉在桌面 Space，或 activate 时把全屏 Space 切走。
@Suite
@MainActor
struct OverlayWindowTests {

    @Test func overlayWindowIsNonactivatingPanelForFullscreenSpaces() {
        let window = OverlayWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        defer { window.close() }

        // 静态类型即 NSPanel；再断言运行时关键能力，防止回退成 NSWindow。
        let panel: NSPanel = window
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.collectionBehavior.contains(.stationary))
        #expect(panel.hidesOnDeactivate == false)
    }
}
