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

    /// 全屏选区：框选后原地贴图标注；对号确认返回最终图，叉/Esc 取消。
    public func requestSelectionCapture() async throws -> SelectionOutcome {
        guard authorizationStatus() else {
            throw ScreenCaptureError.notAuthorized
        }
        let completion = await SelectionOverlayController.run { [weak self] rect, excludeIDs in
            guard let self else { throw ScreenCaptureError.captureFailed("截图服务已释放") }
            return try await self.capture(globalRect: rect, excludingWindowIDs: excludeIDs)
        }
        switch completion {
        case .canceled:
            return .canceled
        case .confirmed(let captured):
            return .selected(captured)
        }
    }

    /// 对已有截图进入贴图标注（工作台「继续标注」）。
    public func requestAnnotate(captured: CapturedImage) async -> SelectionOutcome {
        let completion = await SelectionOverlayController.runAnnotate(captured: captured)
        switch completion {
        case .canceled:
            return .canceled
        case .confirmed(let result):
            return .selected(result)
        }
    }

    // MARK: - 矩形捕获

    /// 直接按全局 point 矩形捕获；跨屏选区按显示器拆分捕获再按 pixel 比例裁剪合并。
    /// `excludingWindowIDs`：本 App 遮罩窗的 CGWindowID，滤镜排除后无需 orderOut，避免画面跳变。
    public func capture(
        globalRect: CGRect,
        excludingWindowIDs: [CGWindowID] = []
    ) async throws -> CapturedImage {
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
                primaryFrame: primaryFrame,
                excludingWindowIDs: excludingWindowIDs
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
        primaryFrame: CGRect,
        excludingWindowIDs: [CGWindowID]
    ) async throws -> CGImage {
        if let image = try? await captureScreenKit(
            screen: screen,
            localRect: localRect,
            excludingWindowIDs: excludingWindowIDs
        ) {
            return image
        }
        // 回退矩形接口无法按窗排除；有遮罩 ID 时不要走它，否则会截进半透明层。
        guard excludingWindowIDs.isEmpty else {
            throw ScreenCaptureError.captureFailed("带遮罩排除的 ScreenCaptureKit 捕获失败")
        }
        return try await captureScreenKitRect(screen: screen, localRect: localRect, primaryFrame: primaryFrame)
    }
    /// ScreenCaptureKit 主路径：SCShareableContent 取显示器，SCScreenshotManager 整屏捕获后裁剪。
    private func captureScreenKit(
        screen: ScreenInfo,
        localRect: CGRect,
        excludingWindowIDs: [CGWindowID]
    ) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw ScreenCaptureError.captureFailed("找不到 displayID \(screen.displayID) 对应的显示器")
        }
        let matchedIDs = Set(
            ScreenCaptureExclusion.resolveWindowIDs(
                requested: excludingWindowIDs,
                available: content.windows.map(\.windowID)
            )
        )
        let excluded = content.windows.filter { matchedIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        // 默认 1920×1080；不设满屏原生像素时 Retina 会被系统降采样，看起来糊。
        let output = ScreenGeometry.streamOutputPixelSize(
            contentRect: filter.contentRect,
            pointPixelScale: CGFloat(filter.pointPixelScale)
        )
        configuration.width = output.width
        configuration.height = output.height
        configuration.captureResolution = .best
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
    /// destRect 使用与 AppKit 一致的左下原点；不翻转 CTM——`CGContext.draw` 已按
    /// 「图像底边落在 dest 原点、沿 +Y 铺开」绘制，再翻一次会把像素上下颠倒。
    static func composite(
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
        // 子图应按 1:1 像素落画布；用 none 避免误缩放时被双线性抹糊。
        context.interpolationQuality = .none
        for sub in subImages {
            // AppKit 全局左下原点 → 画布像素偏移（与 CGContext 默认 CTM 同向）
            let destRect = CGRect(
                x: (sub.globalRect.minX - selectionRect.minX) * scale,
                y: (sub.globalRect.minY - selectionRect.minY) * scale,
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
