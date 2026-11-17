import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ScreenCaptureKit

/// 截图服务：权限检查、全屏选区遮罩、跨屏拆分捕获与合并。
public final class ScreenCaptureService {

    /// 捕获用屏幕快照：frame（AppKit 全局坐标）、backing 缩放、CGDirectDisplayID。
    private struct ScreenInfo {
        let frame: CGRect
        let scale: CGFloat
        let displayID: CGDirectDisplayID
    }

    public init() {}

    // MARK: - 权限

    /// 屏幕录制权限预检（不弹窗）。
    public func authorizationStatus() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 请求屏幕录制权限（必要时弹系统授权框），返回是否已授权。
    @discardableResult
    public func requestAccess() async -> Bool {
        // CGRequestScreenCaptureAccess 会同步等待用户处理，放后台线程避免卡主线程
        await Task.detached(priority: .userInitiated) {
            CGRequestScreenCaptureAccess()
        }.value
    }

    // MARK: - 选区捕获

    /// 全屏选区：所有显示器建遮罩窗口，拖拽框选，Esc 取消，Enter 确认（defaultAction），
    /// 操作 dock 提供标注/复制/保存/取消四个按钮；完成后按选区捕获返回。
    public func requestSelectionCapture(defaultAction: SelectionAction) async throws -> SelectionOutcome {
        guard authorizationStatus() else {
            throw ScreenCaptureError.notAuthorized
        }
        let completion = await SelectionOverlayController.run(defaultAction: defaultAction)
        switch completion {
        case .canceled:
            return .canceled
        case .confirmed(let rect, let action):
            // 小于最小选区视为无效，按取消处理（正常路径下遮罩已拦截）
            guard rect.width >= SelectionOverlayController.minimumSelectionSize,
                  rect.height >= SelectionOverlayController.minimumSelectionSize else {
                return .canceled
            }
            let captured = try await capture(globalRect: rect)
            return .selected(captured, action: action)
        }
    }

    // MARK: - 矩形捕获

    /// 直接按全局 point 矩形捕获；跨屏选区按显示器拆分捕获再按 pixel 比例裁剪合并。
    public func capture(globalRect: CGRect) async throws -> CapturedImage {
        guard authorizationStatus() else {
            throw ScreenCaptureError.notAuthorized
        }
        // point 对齐取整，保证与屏幕像素网格一致
        let rect = CGRect(
            x: globalRect.minX.rounded(.down),
            y: globalRect.minY.rounded(.down),
            width: globalRect.width.rounded(.down),
            height: globalRect.height.rounded(.down)
        )
        guard rect.width >= 1, rect.height >= 1 else {
            throw ScreenCaptureError.invalidSelection
        }

        // 屏幕信息必须在主线程读取
        let screens = await MainActor.run { Self.currentScreens() }
        guard !screens.isEmpty else {
            throw ScreenCaptureError.invalidSelection
        }
        let parts = ScreenGeometry.splitRect(rect, screenFrames: screens.map(\.frame))
        guard !parts.isEmpty else {
            throw ScreenCaptureError.invalidSelection
        }

        let maxScale = screens.map(\.scale).max() ?? 2
        let canvasSize = ScreenGeometry.canvasPixelSize(for: rect, scale: maxScale)
        // AppKit 全局坐标（原点在主屏左下）→ CG 显示坐标（原点在主屏左上），回退路径要用
        let primaryFrame = screens[0].frame

        var subImages: [(globalRect: CGRect, image: CGImage)] = []
        for part in parts {
            let screen = screens[part.screenIndex]
            let image = try await capturePart(
                screen: screen,
                localRect: part.localRect,
                primaryFrame: primaryFrame
            )
            let partGlobal = part.localRect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
            subImages.append((partGlobal, image))
        }

        guard let merged = Self.composite(
            subImages: subImages,
            selectionRect: rect,
            canvasSize: canvasSize,
            scale: maxScale
        ) else {
            throw ScreenCaptureError.captureFailed("跨屏图像合成失败")
        }
        let png = try Self.pngData(of: merged)
        return CapturedImage(
            image: merged,
            pngData: png,
            pointSize: rect.size,
            pixelSize: canvasSize
        )
    }

    // MARK: - 捕获路径

    /// 捕获单个屏幕上的本地矩形区域。
    /// 主路径 ScreenCaptureKit 逐屏整屏捕获 + 像素裁剪；失败回退矩形便利接口。
    private func capturePart(
        screen: ScreenInfo,
        localRect: CGRect,
        primaryFrame: CGRect
    ) async throws -> CGImage {
        if let image = try? await captureScreenKit(screen: screen, localRect: localRect) {
            return image
        }
        return try await captureScreenKitRect(screen: screen, localRect: localRect, primaryFrame: primaryFrame)
    }
    /// ScreenCaptureKit 主路径：SCShareableContent 取显示器，SCScreenshotManager 整屏捕获后裁剪。
    private func captureScreenKit(screen: ScreenInfo, localRect: CGRect) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw ScreenCaptureError.captureFailed("找不到 displayID \(screen.displayID) 对应的显示器")
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        let fullImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)

        // 按实际输出像素换算裁剪矩形（不信任整数 backingScale，避免 HiDPI 精度差异）
        let scaleX = CGFloat(fullImage.width) / screen.frame.width
        let scaleY = CGFloat(fullImage.height) / screen.frame.height
        // 本地坐标 y 轴向上、图像 y 轴向下：先翻到左上原点再换算像素
        let topLeftLocal = CGRect(
            x: localRect.minX,
            y: screen.frame.height - localRect.maxY,
            width: localRect.width,
            height: localRect.height
        )
        var cropRect = ScreenGeometry.pixelRect(for: topLeftLocal, scale: max(scaleX, scaleY))
        // 夹回图像边界，保证裁剪矩形有效
        cropRect = cropRect.intersection(CGRect(x: 0, y: 0, width: fullImage.width, height: fullImage.height))
        guard cropRect.width >= 1, cropRect.height >= 1, let cropped = fullImage.cropping(to: cropRect) else {
            throw ScreenCaptureError.captureFailed("显示 \(screen.displayID) 裁剪区域无效")
        }
        return cropped
    }

    /// 回退路径：整屏捕获或裁剪失败时，改用矩形便利接口一次捕获该区域。
    /// CGWindowListCreateImage 在 macOS 15 SDK 已被标记 unavailable（要求改用 ScreenCaptureKit），
    /// 因此回退到 SCScreenshotManager 的 display-agnostic 矩形接口（macOS 15.2+）。
    private func captureScreenKitRect(
        screen: ScreenInfo,
        localRect: CGRect,
        primaryFrame: CGRect
    ) async throws -> CGImage {
        let global = localRect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        // AppKit 全局（原点在主屏左下）→ CG 显示坐标（原点在主屏左上）：沿主屏高度翻 y 轴
        let cgRect = CGRect(
            x: global.minX,
            y: primaryFrame.maxY - global.maxY,
            width: global.width,
            height: global.height
        )
        return try await SCScreenshotManager.captureImage(in: cgRect)
    }

    // MARK: - 合成与编码

    /// 把各屏子图合成到一张与全局像素尺寸一致的画布。
    /// 画布与捕获图像同为左上原点的行序，因此把 CG 上下文翻转后按左上坐标绘制。
    private static func composite(
        subImages: [(globalRect: CGRect, image: CGImage)],
        selectionRect: CGRect,
        canvasSize: CGSize,
        scale: CGFloat
    ) -> CGImage? {
        let width = Int(canvasSize.width)
        let height = Int(canvasSize.height)
        guard width > 0, height > 0 else { return nil }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        for sub in subImages {
            // 子图在选区内的左上原点 point 偏移 → 画布像素偏移
            let destRect = CGRect(
                x: (sub.globalRect.minX - selectionRect.minX) * scale,
                y: (selectionRect.maxY - sub.globalRect.maxY) * scale,
                width: sub.globalRect.width * scale,
                height: sub.globalRect.height * scale
            )
            context.draw(sub.image, in: destRect)
        }
        return context.makeImage()
    }

    /// CGImage → PNG 数据。
    static func pngData(of image: CGImage) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenCaptureError.captureFailed("创建 PNG 编码目标失败")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenCaptureError.captureFailed("PNG 编码失败")
        }
        return output as Data
    }

    // MARK: - 屏幕信息

    @MainActor
    private static func currentScreens() -> [ScreenInfo] {
        NSScreen.screens.map { screen in
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value ?? 0
            return ScreenInfo(
                frame: screen.frame,
                scale: screen.backingScaleFactor,
                displayID: CGDirectDisplayID(displayID)
            )
        }
    }
}
