import Foundation
import CoreGraphics

/// 取色遮罩布局换算（纯函数，便于单测）。
enum ColorPickLayout {

    /// 屏幕全局点 → 覆盖窗口 content 本地点。
    /// 约定：contentView 原点为 (0,0) 且尺寸等于 `windowFrame.size`（与 PickOverlayView 一致）。
    static func contentPoint(screenPoint: CGPoint, windowFrame: CGRect) -> CGPoint {
        CGPoint(
            x: screenPoint.x - windowFrame.minX,
            y: screenPoint.y - windowFrame.minY
        )
    }
}
