import Testing
import CoreGraphics
@testable import ScreenCapture

/// ScreenGeometry 纯函数测试：单屏/双屏/不相交/跨屏拆分、像素取整、画布尺寸。
/// 注：本仓库测试统一使用 swift-testing（本机 CLT 环境没有 XCTest 运行时）。
@Suite
struct ScreenGeometryTests {

    // MARK: - splitRect

    /// 单屏：选区完整落在唯一屏幕内，localRect 等于选区减去屏幕原点。
    @Test func splitRectSingleScreen() {
        let screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
        let parts = ScreenGeometry.splitRect(CGRect(x: 100, y: 200, width: 300, height: 400), screenFrames: screens)
        #expect(parts.count == 1)
        #expect(parts[0].screenIndex == 0)
        #expect(parts[0].localRect == CGRect(x: 100, y: 200, width: 300, height: 400))
    }

    /// 单屏但屏幕有非零原点（副屏）：本地坐标要减去屏幕 frame 的 origin。
    @Test func splitRectSingleScreenWithOffset() {
        let screens = [CGRect(x: 1920, y: 0, width: 2560, height: 1440)]
        let parts = ScreenGeometry.splitRect(CGRect(x: 2420, y: 400, width: 500, height: 600), screenFrames: screens)
        #expect(parts.count == 1)
        #expect(parts[0].screenIndex == 0)
        #expect(parts[0].localRect == CGRect(x: 500, y: 400, width: 500, height: 600))
    }

    /// 双屏并列、选区跨屏：拆成两个子矩形，宽度之和等于选区宽度。
    @Test func splitRectSpanningTwoScreens() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 2560, height: 1440),
        ]
        let selection = CGRect(x: 1500, y: 100, width: 1000, height: 500)
        let parts = ScreenGeometry.splitRect(selection, screenFrames: screens)

        #expect(parts.count == 2)

        let first = parts[0]
        #expect(first.screenIndex == 0)
        #expect(first.localRect == CGRect(x: 1500, y: 100, width: 420, height: 500))

        let second = parts[1]
        #expect(second.screenIndex == 1)
        #expect(second.localRect == CGRect(x: 0, y: 100, width: 580, height: 500))

        // 跨屏总宽度守恒
        #expect(first.localRect.width + second.localRect.width == selection.width)
    }

    /// 选区与所有屏幕都不相交：不产出任何子矩形。
    @Test func splitRectDisjoint() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 2560, height: 1440),
        ]
        let parts = ScreenGeometry.splitRect(CGRect(x: 5000, y: 2000, width: 100, height: 100), screenFrames: screens)
        #expect(parts.isEmpty)
    }

    /// 选区从屏幕中部开始延伸出屏幕边缘：交集按屏幕边界截断。
    @Test func splitRectClampedToScreenEdge() {
        let screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
        let selection = CGRect(x: 1800, y: 500, width: 500, height: 700)
        let parts = ScreenGeometry.splitRect(selection, screenFrames: screens)

        #expect(parts.count == 1)
        #expect(parts[0].screenIndex == 0)
        // x 方向按屏幕右缘截断为 120；y 方向 500+700=1200 超出 1080，按底缘截断为 580
        #expect(parts[0].localRect == CGRect(x: 1800, y: 500, width: 120, height: 580))
    }

    /// 选区与屏幕共享边缘（零宽交集）：不产出子矩形。
    @Test func splitRectEdgeTouchingExcluded() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 2560, height: 1440),
        ]
        // 起点恰好在第二屏左缘，与第一屏零宽交集
        let parts = ScreenGeometry.splitRect(CGRect(x: 1920, y: 0, width: 100, height: 100), screenFrames: screens)
        #expect(parts.count == 1)
        #expect(parts[0].screenIndex == 1)
        #expect(parts[0].localRect == CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    /// 三屏（含垂直排布）跨屏中部：按索引逐屏拆分，本地坐标独立。
    @Test func splitRectThreeScreens() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1000, height: 800),     // 主屏
            CGRect(x: 1000, y: 0, width: 1000, height: 800),  // 右屏
            CGRect(x: -1000, y: 0, width: 1000, height: 800), // 左屏
        ]
        let selection = CGRect(x: -200, y: 300, width: 2000, height: 200)
        let parts = ScreenGeometry.splitRect(selection, screenFrames: screens)

        #expect(parts.count == 3)
        // parts 按屏幕数组顺序输出：主屏 → 右屏 → 左屏
        // 主屏：完整穿过，宽 1000
        #expect(parts[0].screenIndex == 0)
        #expect(parts[0].localRect == CGRect(x: 0, y: 300, width: 1000, height: 200))
        // 右屏：选区终点 x=1800，在屏幕内宽 800
        #expect(parts[1].screenIndex == 1)
        #expect(parts[1].localRect == CGRect(x: 0, y: 300, width: 800, height: 200))
        // 左屏：选区起点 x=-200，屏幕内偏移 800，宽 200
        #expect(parts[2].screenIndex == 2)
        #expect(parts[2].localRect == CGRect(x: 800, y: 300, width: 200, height: 200))
    }

    // MARK: - pixelRect

    @Test func pixelRectIntegerScaleOne() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
        #expect(ScreenGeometry.pixelRect(for: rect, scale: 1) == rect)
    }

    @Test func pixelRectScaleTwoIntegral() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
        #expect(
            ScreenGeometry.pixelRect(for: rect, scale: 2)
                == CGRect(x: 20, y: 40, width: 200, height: 100)
        )
    }

    /// 小数 point 边界：原点与终点都向下取整再做差。
    @Test func pixelRectFractionalRounding() {
        let rect = CGRect(x: 0.5, y: 0.25, width: 10.25, height: 10.75)
        // x: floor(0.5×2)=1；maxX: floor((0.5+10.25)×2)=floor(21.5)=21
        // y: floor(0.25×2)=0；maxY: floor((0.25+10.75)×2)=floor(22)=22
        #expect(
            ScreenGeometry.pixelRect(for: rect, scale: 2)
                == CGRect(x: 1, y: 0, width: 20, height: 22)
        )
    }

    @Test func pixelRectScaleThree() {
        let rect = CGRect(x: 1.3, y: 2.7, width: 4.6, height: 5.1)
        // x: floor(1.3×3)=floor(3.9)=3；maxX: floor(5.9×3)=floor(17.7)=17
        // y: floor(2.7×3)=floor(8.1)=8；maxY: floor(7.8×3)=floor(23.4)=23
        #expect(
            ScreenGeometry.pixelRect(for: rect, scale: 3)
                == CGRect(x: 3, y: 8, width: 14, height: 15)
        )
    }

    @Test func pixelRectZeroScale() {
        let rect = CGRect(x: 5, y: 7, width: 10, height: 20)
        #expect(
            ScreenGeometry.pixelRect(for: rect, scale: 0)
                == CGRect(x: 0, y: 0, width: 0, height: 0)
        )
    }

    // MARK: - canvasPixelSize

    @Test func canvasPixelSizeIntegral() {
        #expect(
            ScreenGeometry.canvasPixelSize(for: CGRect(x: 0, y: 0, width: 610, height: 320), scale: 2)
                == CGSize(width: 1220, height: 640)
        )
    }

    @Test func canvasPixelSizeFractionalRounds() {
        // 100.4 × 2 = 200.8 → 201；50.25 × 2 = 100.5 → 101
        #expect(
            ScreenGeometry.canvasPixelSize(for: CGRect(x: 0, y: 0, width: 100.4, height: 50.25), scale: 2)
                == CGSize(width: 201, height: 101)
        )
    }

    @Test func canvasPixelSizeScaleOne() {
        #expect(
            ScreenGeometry.canvasPixelSize(for: CGRect(x: 10, y: 10, width: 300, height: 400), scale: 1)
                == CGSize(width: 300, height: 400)
        )
    }
}
