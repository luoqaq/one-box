import Foundation
import CoreGraphics

/// 取色结果输出格式。
public enum ColorFormat: Int, CaseIterable, Sendable, Equatable {
    case hex = 1
    case rgb = 2
    case oklch = 3

    public var title: String {
        switch self {
        case .hex: return "HEX"
        case .rgb: return "RGB"
        case .oklch: return "OKLCH"
        }
    }
}

/// sRGB 0…1 色值。
public struct ColorValue: Equatable, Sendable {
    public var r: CGFloat
    public var g: CGFloat
    public var b: CGFloat

    public init(r: CGFloat, g: CGFloat, b: CGFloat) {
        self.r = Self.clamp01(r)
        self.g = Self.clamp01(g)
        self.b = Self.clamp01(b)
    }

    public init(cgColor: CGColor) {
        let rgb = cgColor.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            intent: .defaultIntent,
            options: nil
        ) ?? cgColor
        let c = rgb.components ?? [0, 0, 0, 1]
        if c.count >= 3 {
            self.init(r: c[0], g: c[1], b: c[2])
        } else if c.count == 2 {
            self.init(r: c[0], g: c[0], b: c[0])
        } else {
            self.init(r: 0, g: 0, b: 0)
        }
    }

    public static let black = ColorValue(r: 0, g: 0, b: 0)
    public static let white = ColorValue(r: 1, g: 1, b: 1)

    public func string(format: ColorFormat) -> String {
        switch format {
        case .hex: return hexString
        case .rgb: return rgbString
        case .oklch: return oklchString
        }
    }

    /// `#RRGGBB`（大写）。
    public var hexString: String {
        let ri = Int((r * 255).rounded())
        let gi = Int((g * 255).rounded())
        let bi = Int((b * 255).rounded())
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }

    /// `rgb(r, g, b)`，通道为 0…255 整数。
    public var rgbString: String {
        let ri = Int((r * 255).rounded())
        let gi = Int((g * 255).rounded())
        let bi = Int((b * 255).rounded())
        return "rgb(\(ri), \(gi), \(bi))"
    }

    /// `oklch(L% C H)`，L 为 0…100%，C/H 保留两位小数。
    public var oklchString: String {
        let (L, C, H) = Self.srgbToOKLCH(r: r, g: g, b: b)
        let lPct = (L * 1000).rounded() / 10 // 一位小数百分比
        let cStr = String(format: "%.2f", C)
        let hStr = String(format: "%.2f", H)
        return "oklch(\(Self.trim(lPct))% \(cStr) \(hStr))"
    }

    // MARK: - OKLCH

    /// sRGB → OKLCH。H 为度数 0…360；无彩度时 H=0。
    public static func srgbToOKLCH(r: CGFloat, g: CGFloat, b: CGFloat) -> (L: CGFloat, C: CGFloat, H: CGFloat) {
        let lr = linearize(r)
        let lg = linearize(g)
        let lb = linearize(b)

        // linear sRGB → OKLab（Björn Ottosson）
        let l = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb
        let m = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb
        let s = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb

        let l_ = cbrt(l)
        let m_ = cbrt(m)
        let s_ = cbrt(s)

        let L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
        let a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
        let bb = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_

        let C = sqrt(a * a + bb * bb)
        var H = atan2(bb, a) * 180 / .pi
        if H < 0 { H += 360 }
        if C < 0.0001 { H = 0 }
        return (L, C, H)
    }

    private static func linearize(_ c: CGFloat) -> CGFloat {
        let x = clamp01(c)
        return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    }

    private static func clamp01(_ v: CGFloat) -> CGFloat {
        min(1, max(0, v))
    }

    private static func trim(_ v: CGFloat) -> String {
        if v == v.rounded() { return String(Int(v)) }
        return String(format: "%.1f", v)
    }

    private static func cbrt(_ x: CGFloat) -> CGFloat {
        CGFloat(Foundation.cbrt(Double(x)))
    }
}

/// 取色会话结果。
public enum ColorPickOutcome: Sendable, Equatable {
    case picked(ColorValue, format: ColorFormat)
    case canceled
}
