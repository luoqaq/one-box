import AppKit
import CoreGraphics
import ScreenCaptureKit

/// 光标附近小块屏幕采样：中心像素色 + 放大镜底图。
public enum ColorSampler {

    /// 采样半径（point）。实际矩形边长 = radius*2+1。
    public static let sampleRadiusPoints: CGFloat = 7

    public struct Sample: Sendable {
        public let color: ColorValue
        public let loupeImage: CGImage
        public let globalPoint: CGPoint
    }

    /// 在全局 AppKit 坐标（主屏左下原点）采样。
    public static func sample(at globalPoint: CGPoint) async throws -> Sample {
        let layout: (screenFrame: CGRect, primaryMaxY: CGFloat)? = await MainActor.run {
            let screens = NSScreen.screens
            guard let screen = screens.first(where: { $0.frame.contains(globalPoint) }) ?? screens.first,
                  let primary = screens.first else { return nil }
            return (screen.frame, primary.frame.maxY)
        }
        guard let layout else {
            throw ColorPickError.sampleFailed("无可用显示器")
        }

        let radius = sampleRadiusPoints
        let side = radius * 2 + 1
        var rect = CGRect(
            x: globalPoint.x - radius,
            y: globalPoint.y - radius,
            width: side,
            height: side
        )
        // 夹到当前屏，避免跨屏小块失败
        rect = rect.intersection(layout.screenFrame)
        guard rect.width >= 1, rect.height >= 1 else {
            throw ColorPickError.sampleFailed("采样区域无效")
        }

        // AppKit 全局 → CG 显示坐标（主屏左上原点）
        let cgRect = CGRect(
            x: rect.minX,
            y: layout.primaryMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )

        let image = try await SCScreenshotManager.captureImage(in: cgRect)
        guard let color = centerColor(of: image) else {
            throw ColorPickError.sampleFailed("无法读取中心像素")
        }
        return Sample(color: color, loupeImage: image, globalPoint: globalPoint)
    }

    /// 读取图像几何中心像素（sRGB）。
    public static func centerColor(of image: CGImage) -> ColorValue? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return nil }
        let cx = w / 2
        let cy = h / 2

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .none
        ctx.translateBy(x: -CGFloat(cx), y: -CGFloat(cy))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // 反预乘
        let a = CGFloat(pixel[3]) / 255
        if a < 0.001 {
            return ColorValue(r: 0, g: 0, b: 0)
        }
        return ColorValue(
            r: CGFloat(pixel[0]) / 255 / a,
            g: CGFloat(pixel[1]) / 255 / a,
            b: CGFloat(pixel[2]) / 255 / a
        )
    }
}

public enum ColorPickError: Error, LocalizedError, Sendable {
    case notAuthorized
    case sampleFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "需要屏幕录制权限"
        case .sampleFailed(let msg):
            return msg
        }
    }
}
