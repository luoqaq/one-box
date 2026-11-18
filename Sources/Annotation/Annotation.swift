import Foundation
import CoreGraphics

/// 单条标注。坐标均为图像像素坐标系（左上原点，x 向右、y 向下）。
/// 箭头与直线使用 `startPoint`/`endPoint`，`rect` 仅作为包络盒；
/// 其余种类以 `rect` 为作用区域。
public struct Annotation: Identifiable, Codable, Equatable, Sendable {

    /// 标注种类。
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case arrow
        case line
        case rectangle
        case text
        case mosaic
    }

    /// 唯一标识。
    public var id: UUID
    /// 标注种类。
    public var kind: Kind
    /// 作用区域（像素坐标，左上原点）。箭头时为包络盒。
    public var rect: CGRect
    /// 箭头专用：尾点（像素坐标）。
    public var startPoint: CGPoint?
    /// 箭头专用：头点（像素坐标）。
    public var endPoint: CGPoint?
    /// 绘制颜色。
    public var color: AnnotationColor
    /// 线宽（像素）。
    public var strokeWidth: CGFloat
    /// 文字标注的内容。
    public var text: String?
    /// 文字字号（像素），默认 13。
    public var fontSize: CGFloat

    /// 完整成员初始化。仅 `kind` 与 `rect` 必填，其余均有默认值。
    public init(
        id: UUID = UUID(),
        kind: Kind,
        rect: CGRect,
        startPoint: CGPoint? = nil,
        endPoint: CGPoint? = nil,
        color: AnnotationColor = .red,
        strokeWidth: CGFloat = 3,
        text: String? = nil,
        fontSize: CGFloat = 13
    ) {
        self.id = id
        self.kind = kind
        self.rect = rect
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.color = color
        self.strokeWidth = strokeWidth
        self.text = text
        self.fontSize = fontSize
    }
}

/// 箭头几何计算（统一实时预览、二次编辑与导出渲染的箭头造型）。
public struct AnnotationArrowGeometry: Sendable {
    public let tip: CGPoint
    public let shaftEnd: CGPoint
    public let leftWing: CGPoint
    public let neck: CGPoint
    public let rightWing: CGPoint

    /// 根据起止点与线宽计算标准燕尾箭头的各关键点；起止点重合时返回 `nil`。
    public init?(from: CGPoint, to: CGPoint, strokeWidth: CGFloat) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length > 0, strokeWidth > 0 else { return nil }

        let ux = dx / length
        let uy = dy / length
        let px = -uy
        let py = ux

        // 极短线段按总长收缩箭头尺寸，防止箭头倒挂或畸形。
        let headLen = min(4.2 * strokeWidth, length * 0.65)
        let headWidth = headLen * 0.72
        let neckDepth = headLen * 0.75
        let shaftInset = headLen * 0.72

        let baseCenter = CGPoint(x: to.x - ux * headLen, y: to.y - uy * headLen)
        self.tip = to
        self.leftWing = CGPoint(x: baseCenter.x + px * headWidth / 2, y: baseCenter.y + py * headWidth / 2)
        self.rightWing = CGPoint(x: baseCenter.x - px * headWidth / 2, y: baseCenter.y - py * headWidth / 2)
        self.neck = CGPoint(x: to.x - ux * neckDepth, y: to.y - uy * neckDepth)
        // 箭杆略微深入燕尾内侧 3% headLen，消除抗锯齿接缝且不露出两侧或尖端。
        self.shaftEnd = CGPoint(x: to.x - ux * shaftInset, y: to.y - uy * shaftInset)
    }
}
