import Foundation
import CoreGraphics
import ImageIO
import Testing
import Annotation

/// Annotation 模块测试：颜色模型、数据模型与纯函数渲染器。
struct AnnotationTests {

    // MARK: - 测试工具

    /// 构造 RGBA8（premultipliedLast, sRGB）测试图像。
    private func makeImage(
        width: Int,
        height: Int,
        draw: (CGContext, CGFloat, CGFloat) -> Void
    ) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        draw(context, CGFloat(width), CGFloat(height))
        return context.makeImage()!
    }

    /// 白底图。
    private func whiteImage(width: Int, height: Int) -> CGImage {
        makeImage(width: width, height: height) { context, w, h in
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
    }

    /// 灰度横向渐变图：像素颜色仅随 x 变化，便于打码断言。
    private func gradientImage(width: Int, height: Int) -> CGImage {
        makeImage(width: width, height: height) { context, w, h in
            for x in 0..<width {
                let value = CGFloat(x) * 4 / 255.0
                context.setFillColor(CGColor(srgbRed: value, green: value, blue: value, alpha: 1))
                context.fill(CGRect(x: CGFloat(x), y: 0, width: 1, height: h))
            }
        }
    }

    /// 把图像解为 RGBA8 像素缓冲，行 0 对应图像顶部。
    private func rgbaPixels(of image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { raw in
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
            let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        return buffer
    }

    /// 读取 (x, y) 像素的 RGBA 分量（0...1）。
    private func pixel(_ x: Int, _ y: Int, in buffer: [UInt8], width: Int) -> (r: Double, g: Double, b: Double, a: Double) {
        let offset = (y * width + x) * 4
        return (
            Double(buffer[offset]) / 255.0,
            Double(buffer[offset + 1]) / 255.0,
            Double(buffer[offset + 2]) / 255.0,
            Double(buffer[offset + 3]) / 255.0
        )
    }

    private func assertSimilar(
        _ actual: (r: Double, g: Double, b: Double, a: Double),
        _ expected: (r: Double, g: Double, b: Double, a: Double),
        accuracy: Double = 0.02
    ) {
        #expect(abs(actual.r - expected.r) <= accuracy)
        #expect(abs(actual.g - expected.g) <= accuracy)
        #expect(abs(actual.b - expected.b) <= accuracy)
        #expect(abs(actual.a - expected.a) <= accuracy)
    }

    // MARK: - 渲染：尺寸与空标注

    @Test func emptyAnnotationsOutputMatchesBase() throws {
        let base = gradientImage(width: 64, height: 48)
        let rendered = try AnnotationRenderer.render(base: base, annotations: [])
        #expect(rendered.width == base.width)
        #expect(rendered.height == base.height)
        // 空标注必须像素级一致。
        #expect(rgbaPixels(of: rendered) == rgbaPixels(of: base))
    }

    @Test func invalidAnnotationsAreSkippedSafely() throws {
        let base = whiteImage(width: 40, height: 40)
        let invalid: [Annotation] = [
            Annotation(kind: .arrow, rect: .zero, startPoint: CGPoint(x: 10, y: 10), endPoint: CGPoint(x: 10, y: 10)),
            Annotation(kind: .arrow, rect: .zero),
            Annotation(kind: .rectangle, rect: .zero),
            Annotation(kind: .text, rect: CGRect(x: 0, y: 0, width: 10, height: 10), text: ""),
            Annotation(kind: .text, rect: CGRect(x: 0, y: 0, width: 10, height: 10), text: nil),
            Annotation(kind: .mosaic, rect: CGRect(x: 0, y: 0, width: 0, height: 5)),
        ]
        let rendered = try AnnotationRenderer.render(base: base, annotations: invalid)
        #expect(rendered.width == base.width)
        #expect(rendered.height == base.height)
        #expect(rgbaPixels(of: rendered) == rgbaPixels(of: base))
    }

    @Test(arguments: Annotation.Kind.allCases)
    func eachKindPreservesDimensions(kind: Annotation.Kind) throws {
        let base = whiteImage(width: 80, height: 60)
        let annotation: Annotation
        switch kind {
        case .arrow:
            annotation = Annotation(
                kind: .arrow,
                rect: CGRect(x: 10, y: 10, width: 60, height: 45),
                startPoint: CGPoint(x: 10, y: 50),
                endPoint: CGPoint(x: 65, y: 12),
                strokeWidth: 4
            )
        case .rectangle:
            annotation = Annotation(kind: .rectangle, rect: CGRect(x: 10, y: 10, width: 50, height: 30), strokeWidth: 3)
        case .text:
            annotation = Annotation(kind: .text, rect: CGRect(x: 5, y: 5, width: 60, height: 20), text: "Hello OneBox", fontSize: 13)
        case .mosaic:
            annotation = Annotation(kind: .mosaic, rect: CGRect(x: 10, y: 10, width: 40, height: 40))
        }
        let rendered = try AnnotationRenderer.render(base: base, annotations: [annotation])
        #expect(rendered.width == 80)
        #expect(rendered.height == 60)
    }

    // MARK: - 矩形

    @Test func rectangleRendersBorderAndTranslucentFill() throws {
        let base = whiteImage(width: 100, height: 100)
        let annotation = Annotation(
            kind: .rectangle,
            rect: CGRect(x: 20, y: 20, width: 60, height: 60),
            color: .blue,
            strokeWidth: 4
        )
        let rendered = try AnnotationRenderer.render(base: base, annotations: [annotation])
        let pixels = rgbaPixels(of: rendered)
        // 边框中心：接近纯描边色（#0a84ff）。
        assertSimilar(pixel(50, 20, in: pixels, width: 100), (10.0 / 255.0, 132.0 / 255.0, 1.0, 1.0))
        // 内部填充：白底 × alpha 0.06。
        assertSimilar(pixel(50, 50, in: pixels, width: 100), (0.9463, 0.9536, 1.0, 1.0), accuracy: 0.03)
        // 外部：保持白底。
        assertSimilar(pixel(5, 5, in: pixels, width: 100), (1, 1, 1, 1))
    }

    @Test func rectangleStackingOrderTakesEffect() throws {
        let base = whiteImage(width: 100, height: 100)
        let rect = CGRect(x: 20, y: 20, width: 60, height: 60)
        let red = Annotation(kind: .rectangle, rect: rect, color: .red, strokeWidth: 6)
        let blue = Annotation(kind: .rectangle, rect: rect, color: .blue, strokeWidth: 6)

        let redOnly = try AnnotationRenderer.render(base: base, annotations: [red])
        assertSimilar(pixel(50, 20, in: rgbaPixels(of: redOnly), width: 100), (1, 69.0 / 255.0, 58.0 / 255.0, 1))

        // 后画的矩形必须盖在先画的之上：边框变为蓝色。
        let stacked = try AnnotationRenderer.render(base: base, annotations: [red, blue])
        assertSimilar(pixel(50, 20, in: rgbaPixels(of: stacked), width: 100), (10.0 / 255.0, 132.0 / 255.0, 1.0, 1.0))
    }

    // MARK: - 箭头

    @Test func arrowDrawsShaftAlongDirection() throws {
        let base = whiteImage(width: 100, height: 80)
        let annotation = Annotation(
            kind: .arrow,
            rect: CGRect(x: 10, y: 28, width: 70, height: 5),
            startPoint: CGPoint(x: 10, y: 30),
            endPoint: CGPoint(x: 80, y: 30),
            color: .red,
            strokeWidth: 5
        )
        let rendered = try AnnotationRenderer.render(base: base, annotations: [annotation])
        let pixels = rgbaPixels(of: rendered)
        // 箭杆中点：纯红色。
        assertSimilar(pixel(40, 30, in: pixels, width: 100), (1, 69.0 / 255.0, 58.0 / 255.0, 1))
        // 箭头实心三角内部：纯红色。
        assertSimilar(pixel(70, 30, in: pixels, width: 100), (1, 69.0 / 255.0, 58.0 / 255.0, 1))
        // 远离箭头的位置不受影响。
        assertSimilar(pixel(5, 70, in: pixels, width: 100), (1, 1, 1, 1))
    }

    // MARK: - 文字

    @Test func textRendersInkInsideRectFromTop() throws {
        let base = whiteImage(width: 100, height: 100)
        let annotation = Annotation(
            kind: .text,
            rect: CGRect(x: 10, y: 10, width: 60, height: 60),
            color: AnnotationColor(r: 0, g: 0, b: 0),
            text: "Ag",
            fontSize: 13
        )
        let rendered = try AnnotationRenderer.render(base: base, annotations: [annotation])
        let pixels = rgbaPixels(of: rendered)
        var inkTop = Int.max
        var inkBottom = Int.min
        var inkCount = 0
        for y in 0..<100 {
            for x in 0..<100 {
                if pixel(x, y, in: pixels, width: 100).r < 0.5 {
                    inkTop = min(inkTop, y)
                    inkBottom = max(inkBottom, y)
                    inkCount += 1
                }
            }
        }
        #expect(inkCount > 0)
        // 左上对齐：墨迹应集中在 rect 上半部，而不是贴着 rect 底边。
        #expect(inkTop >= 10 && inkTop <= 25)
        #expect(inkBottom < 45)
    }

    // MARK: - 打码

    @Test func mosaicChangesRegionButKeepsSurroundings() throws {
        let base = gradientImage(width: 60, height: 60)
        let annotation = Annotation(kind: .mosaic, rect: CGRect(x: 10, y: 10, width: 30, height: 30))
        let rendered = try AnnotationRenderer.render(base: base, annotations: [annotation])
        let before = rgbaPixels(of: base)
        let after = rgbaPixels(of: rendered)

        var changedInside = 0
        var checkedInside = 0
        for y in 0..<60 {
            for x in 0..<60 {
                let inside = (10..<40).contains(x) && (10..<40).contains(y)
                let offset = (y * 60 + x) * 4
                if inside {
                    checkedInside += 1
                    if Array(after[offset..<offset + 4]) != Array(before[offset..<offset + 4]) {
                        changedInside += 1
                    }
                } else {
                    // rect 之外的像素必须逐字节不变。
                    #expect(Array(after[offset..<offset + 4]) == Array(before[offset..<offset + 4]))
                }
            }
        }
        #expect(checkedInside == 900)
        #expect(changedInside > 0)
    }

    @Test func mosaicSamplesFromOriginalBaseNotPriorAnnotations() throws {
        // 底图左黑右白；先画一条贯穿打码区的黑色矩形，再打码。
        // 若打码采样被先画的标注污染，区域内会出现大片纯黑，而不是黑白块平均。
        let base = makeImage(width: 60, height: 40) { context, w, h in
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: w / 2, height: h))
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: w / 2, y: 0, width: w - w / 2, height: h))
        }
        let cover = Annotation(
            kind: .rectangle,
            rect: CGRect(x: 0, y: 0, width: 60, height: 40),
            color: AnnotationColor(r: 0, g: 0, b: 0),
            strokeWidth: 60
        )
        let mosaic = Annotation(kind: .mosaic, rect: CGRect(x: 12, y: 12, width: 36, height: 16))
        let rendered = try AnnotationRenderer.render(base: base, annotations: [cover, mosaic])
        let pixels = rgbaPixels(of: rendered)

        // 打码区横跨黑白两半：12 像素块的平均应为灰阶，而非纯黑（说明采样来自原图）。
        var grayish = 0
        for x in 12..<48 {
            let value = pixel(x, 20, in: pixels, width: 60).r
            if value > 0.15 && value < 0.85 {
                grayish += 1
            }
        }
        #expect(grayish > 0)
    }

    // MARK: - PNG 导出

    @Test func pngDataDecodesToSameSize() throws {
        let base = whiteImage(width: 77, height: 41)
        let annotations: [Annotation] = [
            Annotation(kind: .rectangle, rect: CGRect(x: 5, y: 5, width: 40, height: 20), strokeWidth: 2),
            Annotation(
                kind: .arrow,
                rect: CGRect(x: 5, y: 30, width: 60, height: 8),
                startPoint: CGPoint(x: 5, y: 34),
                endPoint: CGPoint(x: 65, y: 34),
                strokeWidth: 3
            ),
        ]
        let data = try AnnotationRenderer.pngData(base: base, annotations: annotations)
        let source = CGImageSourceCreateWithData(data as CFData, nil)
        #expect(source != nil)
        let image = CGImageSourceCreateImageAtIndex(source!, 0, nil)
        #expect(image != nil)
        #expect(image!.width == 77)
        #expect(image!.height == 41)
    }

    // MARK: - AnnotationColor

    @Test func hexParsingVariants() {
        let plain = AnnotationColor(hex: "ff453a")
        #expect(plain.r == 1)
        #expect(abs(plain.g - 69.0 / 255.0) < 1e-9)
        #expect(abs(plain.b - 58.0 / 255.0) < 1e-9)
        #expect(plain.a == 1)

        let prefixed = AnnotationColor(hex: "#ff453a")
        #expect(prefixed == plain)

        let withAlpha = AnnotationColor(hex: "#ff453a80")
        #expect(abs(withAlpha.r - 1) < 1e-9)
        #expect(abs(withAlpha.g - 69.0 / 255.0) < 1e-9)
        #expect(abs(withAlpha.b - 58.0 / 255.0) < 1e-9)
        #expect(abs(withAlpha.a - 128.0 / 255.0) < 1e-9)

        // 大小写不敏感。
        let upper = AnnotationColor(hex: "#FF453A")
        #expect(upper == plain)

        // 非法输入回退为不透明白色。
        let invalid = AnnotationColor(hex: "zzz")
        #expect(invalid == AnnotationColor(r: 1, g: 1, b: 1, a: 1))
    }

    @Test func cgColorComponents() {
        let color = AnnotationColor(hex: "#0a84ff")
        let cg = color.cgColor
        #expect(cg.numberOfComponents == 4)
        let components = cg.components!
        #expect(abs(components[0] - 10.0 / 255.0) < 1e-6)
        #expect(abs(components[1] - 132.0 / 255.0) < 1e-6)
        #expect(abs(components[2] - 1.0) < 1e-6)
        #expect(abs(components[3] - 1.0) < 1e-6)
    }

    @Test func clampOutOfRangeComponents() {
        let color = AnnotationColor(r: 1.5, g: -0.2, b: 2, a: 0.5)
        #expect(color.r == 1)
        #expect(color.g == 0)
        #expect(color.b == 1)
        #expect(color.a == 0.5)
    }

    // MARK: - Codable

    @Test func annotationCodableRoundTrip() throws {
        let annotation = Annotation(
            kind: .arrow,
            rect: CGRect(x: 1.5, y: 2.5, width: 30, height: 20),
            startPoint: CGPoint(x: 1.5, y: 20),
            endPoint: CGPoint(x: 30, y: 3),
            color: AnnotationColor(hex: "#ffd60a"),
            strokeWidth: 4,
            text: nil,
            fontSize: 13
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Annotation.self, from: encoder.encode(annotation))
        #expect(decoded == annotation)
        #expect(decoded.kind == .arrow)
    }
}
