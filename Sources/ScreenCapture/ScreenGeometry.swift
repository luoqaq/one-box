import Foundation
import CoreGraphics

/// 屏幕几何纯函数：全局矩形与各屏幕 frame 的拆分、像素换算与画布尺寸。
/// 全部为无副作用计算，供捕获流程与 AppTarget 复用、测试。
public enum ScreenGeometry {

    /// 把全局 rect 与各屏幕 frame 求交集，拆成「屏幕索引 + 屏本地坐标矩形」列表。
    ///
    /// 屏本地坐标系：原点取该屏幕 frame 的 origin（AppKit 全局坐标系，y 轴向上），
    /// 即 localRect = intersection(globalRect, frame) - frame.origin。
    /// 只与屏幕共享边缘（交集宽或高为 0）时视为不相交，不产出子矩形。
    public static func splitRect(
        _ globalRect: CGRect,
        screenFrames: [CGRect]
    ) -> [(screenIndex: Int, localRect: CGRect)] {
        var result: [(screenIndex: Int, localRect: CGRect)] = []
        for (index, frame) in screenFrames.enumerated() {
            let section = globalRect.intersection(frame)
            // intersection 在完全不相交时返回 null rect；相邻贴边时宽高为 0，同样跳过
            guard !section.isNull, section.width > 0, section.height > 0 else { continue }
            let local = CGRect(
                x: section.minX - frame.minX,
                y: section.minY - frame.minY,
                width: section.width,
                height: section.height
            )
            result.append((screenIndex: index, localRect: local))
        }
        return result
    }

    /// point rect × scale → pixel rect。
    ///
    /// 原点与终点均向下取整、再做差得到尺寸，保证：
    /// 1. 像素边界与 point 边界对齐（原点不越过 point 边界）；
    /// 2. 像素矩形完全落在 [floor(min×scale), floor(max×scale)] 区间内，不会越界。
    public static func pixelRect(for rect: CGRect, scale: CGFloat) -> CGRect {
        let minX = (rect.minX * scale).rounded(.down)
        let minY = (rect.minY * scale).rounded(.down)
        let maxX = (rect.maxX * scale).rounded(.down)
        let maxY = (rect.maxY * scale).rounded(.down)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 组合画布像素尺寸：全局 rect 尺寸 × scale，逐边四舍五入取整。
    public static func canvasPixelSize(for globalRect: CGRect, scale: CGFloat) -> CGSize {
        CGSize(
            width: (globalRect.width * scale).rounded(),
            height: (globalRect.height * scale).rounded()
        )
    }

    /// ScreenCaptureKit 输出缓冲像素尺寸。`SCStreamConfiguration` 默认 1920×1080，
    /// 必须按 contentRect（point）× pointPixelScale 显式设为屏幕原生分辨率，否则 Retina 会被降采样。
    public static func streamOutputPixelSize(contentRect: CGRect, pointPixelScale: CGFloat) -> (width: Int, height: Int) {
        let scale = max(pointPixelScale, 1)
        return (
            width: max(1, Int((contentRect.width * scale).rounded())),
            height: max(1, Int((contentRect.height * scale).rounded()))
        )
    }

    // MARK: - 选区 ↔ 图像像素（标注坐标）

    /// AppKit 全局点（左下原点）→ 图像像素点（左上原点）。
    public static func pixelPoint(
        global: CGPoint,
        selection: CGRect,
        imageSize: CGSize
    ) -> CGPoint {
        let width = max(selection.width, 1)
        let height = max(selection.height, 1)
        let imageW = max(imageSize.width, 1)
        let imageH = max(imageSize.height, 1)
        return CGPoint(
            x: (global.x - selection.minX) / width * imageW,
            y: (selection.maxY - global.y) / height * imageH
        )
    }

    /// 图像像素点（左上原点）→ AppKit 全局点（左下原点）。
    public static func globalPoint(
        pixel: CGPoint,
        selection: CGRect,
        imageSize: CGSize
    ) -> CGPoint {
        let imageW = max(imageSize.width, 1)
        let imageH = max(imageSize.height, 1)
        return CGPoint(
            x: selection.minX + pixel.x / imageW * selection.width,
            y: selection.maxY - pixel.y / imageH * selection.height
        )
    }
}
