import Foundation
import CoreGraphics

/// 标注用颜色。分量均以 0...1 的线性浮点存储，兼容 Codable 与并发传递。
public struct AnnotationColor: Codable, Equatable, Sendable {

    /// 红色分量，0...1。
    public var r: Double
    /// 绿色分量，0...1。
    public var g: Double
    /// 蓝色分量，0...1。
    public var b: Double
    /// 透明度，0...1。
    public var a: Double

    /// 用浮点分量构造，超界值会被钳制到 0...1。
    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = Self.clamped(r)
        self.g = Self.clamped(g)
        self.b = Self.clamped(b)
        self.a = Self.clamped(a)
    }

    /// 十六进制字符串构造。
    /// 支持 `#ff453a`、`ff453a`（不透明）与 `#ff453a80`（末两位为 alpha）三种形式；
    /// 非法输入回退为不透明白色。
    public init(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") {
            text.removeFirst()
        }
        let value: UInt64
        let hasAlpha: Bool
        if text.count == 6, let v = UInt64(text, radix: 16) {
            value = v
            hasAlpha = false
        } else if text.count == 8, let v = UInt64(text, radix: 16) {
            value = v
            hasAlpha = true
        } else {
            // 非法输入回退为不透明白色，避免调用方处理可选。
            value = 0xFFFFFF
            hasAlpha = false
        }
        if hasAlpha {
            // 8 位形式为 RRGGBBAA，末两位是 alpha（与 CSS 一致）。
            self.init(
                r: Double((value >> 24) & 0xFF) / 255.0,
                g: Double((value >> 16) & 0xFF) / 255.0,
                b: Double((value >> 8) & 0xFF) / 255.0,
                a: Double(value & 0xFF) / 255.0
            )
        } else {
            self.init(
                r: Double((value >> 16) & 0xFF) / 255.0,
                g: Double((value >> 8) & 0xFF) / 255.0,
                b: Double(value & 0xFF) / 255.0,
                a: 1.0
            )
        }
    }

    /// 系统accent风格的红色 #ff453a。
    public static let red = AnnotationColor(r: 1.0, g: 69.0 / 255.0, b: 58.0 / 255.0)
    /// 系统蓝色 #0a84ff。
    public static let blue = AnnotationColor(r: 10.0 / 255.0, g: 132.0 / 255.0, b: 1.0)
    /// 系统黄色 #ffd60a。
    public static let yellow = AnnotationColor(r: 1.0, g: 214.0 / 255.0, b: 10.0 / 255.0)
    /// 系统绿色 #30d158。
    public static let green = AnnotationColor(r: 48.0 / 255.0, g: 209.0 / 255.0, b: 88.0 / 255.0)
    /// 纯白 #ffffff。
    public static let white = AnnotationColor(r: 1.0, g: 1.0, b: 1.0)

    /// 供 CoreGraphics 绘制使用的 sRGB 颜色。
    public var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
