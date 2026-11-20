import CoreGraphics
import Foundation

/// 选区框选后的命中与几何变换（AppKit 全局坐标，原点在左下）。
public enum SelectionEditing {

    /// 8 向缩放手柄：四角 + 四边中点。
    public enum Handle: CaseIterable, Equatable, Sendable {
        case bottomLeft
        case bottom
        case bottomRight
        case right
        case topRight
        case top
        case topLeft
        case left
    }

    public enum Hit: Equatable, Sendable {
        case none
        /// 选区内部（远离边框），供标注绘制或整体拖动。
        case interior
        /// 贴边框的环带，供拖动整个选区位置。
        case frame
        case handle(Handle)
    }

    /// 计算 8 个手柄在 `rect` 上的中心点。
    public static func handlePositions(in rect: CGRect) -> [(Handle, CGPoint)] {
        [
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.bottom, CGPoint(x: rect.midX, y: rect.minY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.right, CGPoint(x: rect.maxX, y: rect.midY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.maxY)),
            (.top, CGPoint(x: rect.midX, y: rect.maxY)),
            (.topLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.left, CGPoint(x: rect.minX, y: rect.midY)),
        ]
    }

    /// 优先 8 个手柄；再命中边框环带（向选区外侧偏置，尽量把内部让给标注起笔）；最后才是内部。
    public static func hitTest(
        point: CGPoint,
        in rect: CGRect,
        handleSlop: CGFloat,
        edgeOutset: CGFloat = 0,
        edgeInset: CGFloat = 0
    ) -> Hit {
        let slop2 = handleSlop * handleSlop
        var best: (Handle, CGFloat)?
        for (handle, center) in handlePositions(in: rect) {
            let dx = point.x - center.x
            let dy = point.y - center.y
            let d2 = dx * dx + dy * dy
            if d2 <= slop2, best.map({ d2 < $0.1 }) ?? true {
                best = (handle, d2)
            }
        }
        if let best {
            return .handle(best.0)
        }
        if edgeOutset > 0 || edgeInset > 0 {
            let outer = rect.insetBy(dx: -edgeOutset, dy: -edgeOutset)
            let inner = rect.insetBy(dx: edgeInset, dy: edgeInset)
            if outer.contains(point) {
                if inner.width <= 0 || inner.height <= 0 || !inner.contains(point) {
                    return .frame
                }
                return .interior
            }
            return .none
        }
        return rect.contains(point) ? .interior : .none
    }

    public static func move(_ rect: CGRect, by delta: CGVector) -> CGRect {
        rect.offsetBy(dx: delta.dx, dy: delta.dy)
    }

    /// 拖动某一手柄，对边/对角为固定锚点；宽高不低于 `minimumSize`。
    public static func resize(
        _ rect: CGRect,
        handle: Handle,
        to point: CGPoint,
        minimumSize: CGFloat
    ) -> CGRect {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        switch handle {
        case .bottomLeft:
            minX = min(point.x, maxX - minimumSize)
            minY = min(point.y, maxY - minimumSize)
        case .bottom:
            minY = min(point.y, maxY - minimumSize)
        case .bottomRight:
            maxX = max(point.x, minX + minimumSize)
            minY = min(point.y, maxY - minimumSize)
        case .right:
            maxX = max(point.x, minX + minimumSize)
        case .topRight:
            maxX = max(point.x, minX + minimumSize)
            maxY = max(point.y, minY + minimumSize)
        case .top:
            maxY = max(point.y, minY + minimumSize)
        case .topLeft:
            minX = min(point.x, maxX - minimumSize)
            maxY = max(point.y, minY + minimumSize)
        case .left:
            minX = min(point.x, maxX - minimumSize)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
