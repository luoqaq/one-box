import Foundation
import CoreGraphics
import Testing
import ColorPicker

struct ColorFormatsTests {

    @Test func blackHexAndRGB() {
        let c = ColorValue.black
        #expect(c.hexString == "#000000")
        #expect(c.rgbString == "rgb(0, 0, 0)")
    }

    @Test func whiteHexAndRGB() {
        let c = ColorValue.white
        #expect(c.hexString == "#FFFFFF")
        #expect(c.rgbString == "rgb(255, 255, 255)")
    }

    @Test func primaryBlueHex() {
        let c = ColorValue(r: 0, g: 122 / 255, b: 1)
        #expect(c.hexString == "#007AFF")
        #expect(c.string(format: .hex) == "#007AFF")
        #expect(c.string(format: .rgb) == "rgb(0, 122, 255)")
    }

    @Test func blackOKLCHNearZero() {
        let (L, C, H) = ColorValue.srgbToOKLCH(r: 0, g: 0, b: 0)
        #expect(abs(L) < 0.001)
        #expect(C < 0.001)
        #expect(H == 0)
        #expect(ColorValue.black.oklchString.hasPrefix("oklch(0%"))
    }

    @Test func whiteOKLCHNearOne() {
        let (L, C, _) = ColorValue.srgbToOKLCH(r: 1, g: 1, b: 1)
        #expect(abs(L - 1) < 0.01)
        #expect(C < 0.02)
        let s = ColorValue.white.oklchString
        #expect(s.hasPrefix("oklch("))
        #expect(s.contains("%"))
    }

    @Test func redHasHueNearZeroOr360() {
        let (L, C, H) = ColorValue.srgbToOKLCH(r: 1, g: 0, b: 0)
        #expect(L > 0.5)
        #expect(C > 0.1)
        #expect(H < 40 || H > 320)
    }

    @Test func formatTitlesAndCases() {
        #expect(ColorFormat.hex.title == "HEX")
        #expect(ColorFormat.rgb.title == "RGB")
        #expect(ColorFormat.oklch.title == "OKLCH")
        #expect(ColorFormat.allCases.map(\.rawValue) == [1, 2, 3])
    }

    @Test func cgColorInit() {
        let cg = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let c = ColorValue(cgColor: cg)
        #expect(c.hexString == "#FF0000")
    }

    @Test func outcomeEquality() {
        let a = ColorPickOutcome.picked(ColorValue.black, format: .hex)
        let b = ColorPickOutcome.picked(ColorValue.black, format: .hex)
        #expect(a == b)
        #expect(ColorPickOutcome.canceled == .canceled)
    }
}
