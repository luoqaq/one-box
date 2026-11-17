import Foundation
import CoreGraphics
import CoreText
import AppKit
import ImageIO

/// 标注渲染器：纯函数式地把标注数组叠加到基础图像上。
/// 输出图像与基础图像像素尺寸一致；标注按数组顺序叠加。
public enum AnnotationRenderer {

    /// 渲染过程中的错误。
    enum RenderError: Error {
        /// 基础图像尺寸非法（宽或高为 0）。
        case invalidImage
        /// 位图上下文创建失败。
        case cannotCreateContext
        /// 位图上下文无法产出图像。
        case cannotCreateImage
        /// PNG 输出目标创建失败。
        case cannotCreateDestination
        /// PNG 数据未能完成写入。
        case cannotFinalizeImage
    }

    /// 打码块边长（像素）。
    private static let mosaicBlockSize = 12

    /// 纯函数：把标注按数组顺序叠加到 base 上，输出与 base 像素尺寸一致。
    /// 无效标注（rect 为空、箭头起止点重合或缺失、文字为空）会被安全跳过；
    /// 当没有有效标注时直接返回 base 本身，保证像素完全一致。
    public static func render(base: CGImage, annotations: [Annotation]) throws -> CGImage {
        let width = base.width
        let height = base.height
        guard width > 0, height > 0 else { throw RenderError.invalidImage }

        let effective = annotations.filter { Self.isValid($0) }
        if effective.isEmpty {
            return base
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = Self.makeContext(width: width, height: height, colorSpace: colorSpace, data: nil) else {
            throw RenderError.cannotCreateContext
        }

        // 1:1 绘制基础图像，关闭插值保证像素原样落位。
        context.interpolationQuality = .none
        context.draw(base, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        // 打码采样必须取自原始 base 图，先于任何标注绘制单独提取。
        let mosaicSource: [UInt8]? = effective.contains { $0.kind == .mosaic }
            ? Self.pixelBuffer(of: base, width: width, height: height, colorSpace: colorSpace)
            : nil

        let pixelWidth = CGFloat(width)
        let pixelHeight = CGFloat(height)
        for annotation in effective {
            Self.draw(annotation, context: context, pixelWidth: pixelWidth, pixelHeight: pixelHeight, mosaicSource: mosaicSource)
        }

        guard let image = context.makeImage() else { throw RenderError.cannotCreateImage }
        return image
    }

    /// 渲染并导出 PNG 数据。
    public static func pngData(base: CGImage, annotations: [Annotation]) throws -> Data {
        let image = try render(base: base, annotations: annotations)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            throw RenderError.cannotCreateDestination
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw RenderError.cannotFinalizeImage
        }
        return output as Data
    }

    // MARK: - 有效性与绘制分发

    /// 判断标注是否可绘制。无效标注不抛错，直接跳过。
    private static func isValid(_ annotation: Annotation) -> Bool {
        guard isRectFinite(annotation.rect), annotation.rect.width > 0, annotation.rect.height > 0 else {
            return false
        }
        switch annotation.kind {
        case .arrow:
            guard let start = annotation.startPoint, let end = annotation.endPoint else { return false }
            return start != end
                && start.x.isFinite && start.y.isFinite
                && end.x.isFinite && end.y.isFinite
        case .rectangle, .mosaic:
            return true
        case .text:
            guard let text = annotation.text else { return false }
            return !text.isEmpty
        }
    }

    private static func draw(
        _ annotation: Annotation,
        context: CGContext,
        pixelWidth: CGFloat,
        pixelHeight: CGFloat,
        mosaicSource: [UInt8]?
    ) {
        switch annotation.kind {
        case .arrow:
            drawArrow(annotation, context: context, pixelHeight: pixelHeight)
        case .rectangle:
            drawRectangle(annotation, context: context, pixelHeight: pixelHeight)
        case .text:
            drawText(annotation, context: context, pixelHeight: pixelHeight)
        case .mosaic:
            // 打码必须依赖原始像素缓冲；缺失时跳过，不做退化兜底绘制。
            guard let source = mosaicSource else { return }
            drawMosaic(annotation, context: context, pixelWidth: pixelWidth, pixelHeight: pixelHeight, source: source)
        }
    }

    // MARK: - 箭头

    private static func drawArrow(_ annotation: Annotation, context: CGContext, pixelHeight: CGFloat) {
        guard let start = annotation.startPoint, let end = annotation.endPoint else { return }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return }

        let unitX = dx / length
        let unitY = dy / length
        let headLength = 3.5 * annotation.strokeWidth
        let headWidth = 2.8 * annotation.strokeWidth
        let headBase = CGPoint(x: end.x - unitX * headLength, y: end.y - unitY * headLength)
        let perpX = -unitY
        let perpY = unitX

        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(annotation.strokeWidth)
        context.setStrokeColor(annotation.color.cgColor)
        context.setFillColor(annotation.color.cgColor)

        // 箭杆：start → 箭头三角底边中心，圆头线帽。
        context.beginPath()
        context.move(to: CGPoint(x: start.x, y: pixelHeight - start.y))
        context.addLine(to: CGPoint(x: headBase.x, y: pixelHeight - headBase.y))
        context.strokePath()

        // 实心三角箭头，尖端落在 end 上，底边垂直于箭头方向。
        context.beginPath()
        context.move(to: CGPoint(x: end.x, y: pixelHeight - end.y))
        context.addLine(to: CGPoint(
            x: headBase.x + perpX * headWidth / 2,
            y: pixelHeight - (headBase.y + perpY * headWidth / 2)
        ))
        context.addLine(to: CGPoint(
            x: headBase.x - perpX * headWidth / 2,
            y: pixelHeight - (headBase.y - perpY * headWidth / 2)
        ))
        context.closePath()
        context.fillPath()
        context.restoreGState()
    }

    // MARK: - 矩形

    private static func drawRectangle(_ annotation: Annotation, context: CGContext, pixelHeight: CGFloat) {
        // 图像像素坐标（左上原点）→ CGContext 坐标（左下原点）。
        let frame = CGRect(
            x: annotation.rect.minX,
            y: pixelHeight - annotation.rect.maxY,
            width: annotation.rect.width,
            height: annotation.rect.height
        )
        context.setFillColor(CGColor(srgbRed: annotation.color.r, green: annotation.color.g, blue: annotation.color.b, alpha: 0.06))
        context.fill(frame)
        context.setStrokeColor(annotation.color.cgColor)
        context.setLineWidth(annotation.strokeWidth)
        context.stroke(frame)
    }

    // MARK: - 文字

    private static func drawText(_ annotation: Annotation, context: CGContext, pixelHeight: CGFloat) {
        guard let text = annotation.text, !text.isEmpty, annotation.fontSize > 0 else { return }

        let font = NSFont.systemFont(ofSize: annotation.fontSize)
        // 描边宽以字号的百分比表示；负值表示“描边 + 填充”同时生效，约 1px 深色描边。
        let strokePercent = -100.0 / Double(max(annotation.fontSize, 4.0))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): annotation.color.cgColor,
            NSAttributedString.Key(kCTStrokeWidthAttributeName as String): NSNumber(value: strokePercent),
            NSAttributedString.Key(kCTStrokeColorAttributeName as String): CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55),
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)

        // Core Text 的路径是 y 向上的坐标系：把左上原点的 rect 翻转到 CGContext 坐标，
        // 使文字块在 rect 内左上对齐、按宽度自动换行。
        let path = CGPath(
            rect: CGRect(
                x: annotation.rect.minX,
                y: pixelHeight - annotation.rect.maxY,
                width: annotation.rect.width,
                height: annotation.rect.height
            ),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
    }

    // MARK: - 打码

    private static func drawMosaic(
        _ annotation: Annotation,
        context: CGContext,
        pixelWidth: CGFloat,
        pixelHeight: CGFloat,
        source: [UInt8]
    ) {
        let block = CGFloat(Self.mosaicBlockSize)
        let imageBounds = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        let area = annotation.rect.intersection(imageBounds)
        guard isRectFinite(area), !area.isNull, !area.isEmpty else { return }

        // 块网格与图像原点对齐（12px 的整数倍），块区域裁剪到标注 rect 内，
        // 保证 rect 外的像素不被改动。
        let startBlockX = Int(floor(area.minX / block)) * Self.mosaicBlockSize
        let endX = Int(ceil(area.maxX))
        let startBlockY = Int(floor(area.minY / block)) * Self.mosaicBlockSize
        let endY = Int(ceil(area.maxY))
        let width = Int(pixelWidth)
        let bytesPerRow = width * 4

        var blockX = startBlockX
        while blockX < endX {
            var blockY = startBlockY
            while blockY < endY {
                let blockRect = CGRect(x: CGFloat(blockX), y: CGFloat(blockY), width: block, height: block)
                let region = blockRect.intersection(area)
                if !region.isNull, !region.isEmpty,
                   let color = Self.averageColor(
                       in: region,
                       source: source,
                       bytesPerRow: bytesPerRow,
                       width: width,
                       height: Int(pixelHeight)
                   ) {
                    context.setFillColor(color)
                    context.fill(CGRect(
                        x: region.minX,
                        y: pixelHeight - region.maxY,
                        width: region.width,
                        height: region.height
                    ))
                }
                blockY += Self.mosaicBlockSize
            }
            blockX += Self.mosaicBlockSize
        }
    }

    /// 求区域内像素的平均颜色。source 为 RGBA8（premultipliedLast, sRGB）缓冲，
    /// 行 0 对应图像顶部，与左上原点的像素坐标系一致。
    private static func averageColor(
        in region: CGRect,
        source: [UInt8],
        bytesPerRow: Int,
        width: Int,
        height: Int
    ) -> CGColor? {
        let x0 = max(0, Int(floor(region.minX)))
        let x1 = min(width - 1, Int(ceil(region.maxX)) - 1)
        let y0 = max(0, Int(floor(region.minY)))
        let y1 = min(height - 1, Int(ceil(region.maxY)) - 1)
        guard x0 <= x1, y0 <= y1 else { return nil }

        var sumR = 0.0, sumG = 0.0, sumB = 0.0, sumA = 0.0
        var colorCount = 0.0
        let pixelCount = Double((x1 - x0 + 1) * (y1 - y0 + 1))
        for y in y0...y1 {
            for x in x0...x1 {
                let offset = y * bytesPerRow + x * 4
                let alpha = Double(source[offset + 3]) / 255.0
                if alpha > 0 {
                    // 缓冲是预乘格式，先反预乘再累加，避免半透明像素污染平均色。
                    sumR += Double(source[offset]) / 255.0 / alpha
                    sumG += Double(source[offset + 1]) / 255.0 / alpha
                    sumB += Double(source[offset + 2]) / 255.0 / alpha
                    colorCount += 1
                }
                sumA += alpha
            }
        }
        guard colorCount > 0 else { return nil }
        return CGColor(
            srgbRed: sumR / colorCount,
            green: sumG / colorCount,
            blue: sumB / colorCount,
            alpha: sumA / pixelCount
        )
    }

    /// CGRect.isFinite 在当前 SDK 下是 package 级别，这里用分量检查实现同样的语义。
    private static func isRectFinite(_ rect: CGRect) -> Bool {
        rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite && rect.height.isFinite
    }

    // MARK: - 像素工具

    /// 创建 RGBA8（premultipliedLast, sRGB）位图上下文。
    private static func makeContext(width: Int, height: Int, colorSpace: CGColorSpace, data: UnsafeMutableRawPointer?) -> CGContext? {
        CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// 把图像按原始像素提取为 RGBA8 缓冲，用于打码采样。
    private static func pixelBuffer(of image: CGImage, width: Int, height: Int, colorSpace: CGColorSpace) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { raw in
            guard let context = Self.makeContext(width: width, height: height, colorSpace: colorSpace, data: raw.baseAddress) else {
                return
            }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        return buffer
    }
}
