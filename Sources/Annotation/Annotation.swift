import Foundation
import CoreGraphics

/// 单条标注。坐标均为图像像素坐标系（左上原点，x 向右、y 向下）。
/// 箭头使用 `startPoint`/`endPoint`，`rect` 仅作为包络盒；
/// 其余种类以 `rect` 为作用区域。
public struct Annotation: Identifiable, Codable, Equatable, Sendable {

    /// 标注种类。
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case arrow
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
