import Foundation
import Testing
import CoreGraphics
@testable import ScreenCapture

/// 公开类型语义测试：错误文案、SelectionOutcome 模式匹配。
@Suite
struct ScreenCaptureTypesTests {

    // MARK: - errorDescription

    @Test func errorDescriptionNotEmpty() {
        let errors: [ScreenCaptureError] = [
            .notAuthorized,
            .canceled,
            .captureFailed("内部错误"),
            .invalidSelection,
        ]
        for error in errors {
            let text = error.errorDescription
            #expect(text != nil)
            #expect(!text!.isEmpty, "错误 \(error) 的描述不应为空")
        }
    }

    /// 未授权错误必须给出「系统设置 > 隐私与安全性 > 屏幕录制」恢复路径提示。
    @Test func notAuthorizedContainsRecoveryPath() {
        let text = ScreenCaptureError.notAuthorized.errorDescription ?? ""
        #expect(text.contains("系统设置"))
        #expect(text.contains("隐私与安全性"))
        #expect(text.contains("屏幕录制"))
    }

    @Test func captureFailedCarriesReason() {
        let text = ScreenCaptureError.captureFailed("SCStream 超时").errorDescription ?? ""
        #expect(text.contains("SCStream 超时"))
    }

    // MARK: - SelectionOutcome

    /// 构造 1×1 测试图（不依赖真实捕获）。
    private func makeTestImage() -> CGImage? {
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context?.makeImage()
    }

    @Test func selectionOutcomeSelectedPattern() throws {
        let image = try #require(makeTestImage())
        let captured = CapturedImage(
            image: image,
            pngData: Data([0x89, 0x50, 0x4E, 0x47]),
            pointSize: CGSize(width: 100, height: 50),
            pixelSize: CGSize(width: 200, height: 100)
        )
        let outcome: SelectionOutcome = .selected(captured)

        guard case .selected(let returned) = outcome else {
            Issue.record("应为 selected")
            return
        }
        #expect(returned.image === image)
        #expect(returned.pointSize == CGSize(width: 100, height: 50))
        #expect(returned.pixelSize == CGSize(width: 200, height: 100))
        #expect(returned.pngData == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func selectionOutcomeCanceledPattern() {
        let outcome: SelectionOutcome = .canceled
        if case .selected = outcome {
            Issue.record("canceled 不应匹配到 selected")
        }
    }

    /// 覆盖全部 case 的穷举 switch，验证枚举语义完整。
    @Test func selectionOutcomeExhaustiveSwitch() {
        let outcome: SelectionOutcome = .canceled
        switch outcome {
        case .canceled:
            break  // 预期命中
        case .selected:
            Issue.record("不应出现 selected")
        }
    }

    // MARK: - CapturedImage 字段

    @Test func capturedImageFieldSemantics() throws {
        let image = try #require(makeTestImage())
        let captured = CapturedImage(
            image: image,
            pngData: Data(),
            pointSize: CGSize(width: 300, height: 200),
            pixelSize: CGSize(width: 600, height: 400)
        )
        #expect(captured.image === image)
        #expect(captured.pngData.isEmpty)
        #expect(captured.pointSize == CGSize(width: 300, height: 200))
        #expect(captured.pixelSize == CGSize(width: 600, height: 400))
    }

    // MARK: - composite 方向

    /// 上半红、下半蓝的测试图（不依赖屏幕捕获）。
    private func topRedBottomBlueImage(width: Int, height: Int) -> CGImage {
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
        // 位图上下文左下原点：y=0 是图像底部。
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height / 2)))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: CGFloat(height / 2), width: CGFloat(width), height: CGFloat(height / 2)))
        return context.makeImage()!
    }

    /// 同一套无翻转采样：返回缓冲首行/末行的红色通道，用于对比合成前后是否对调。
    private func edgeRedChannels(of image: CGImage) -> (firstRow: UInt8, lastRow: UInt8) {
        let w = image.width
        let h = image.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        }
        let lastOffset = (h - 1) * w * 4
        return (buffer[0], buffer[lastOffset])
    }

    /// 合成不得上下颠倒：粘贴/导出依赖此方向，预览里的 Y 翻转不能掩盖。
    @Test func compositePreservesVerticalOrientation() throws {
        let source = topRedBottomBlueImage(width: 8, height: 8)
        let before = edgeRedChannels(of: source)
        #expect(before.firstRow != before.lastRow, "夹具两端应可区分")

        let selection = CGRect(x: 100, y: 200, width: 8, height: 8)
        let merged = try #require(
            ScreenCaptureService.composite(
                subImages: [(globalRect: selection, image: source)],
                selectionRect: selection,
                canvasSize: CGSize(width: 8, height: 8),
                scale: 1
            )
        )
        let after = edgeRedChannels(of: merged)
        #expect(after.firstRow == before.firstRow, "合成后首行被颠倒了：\(before.firstRow) → \(after.firstRow)")
        #expect(after.lastRow == before.lastRow, "合成后末行被颠倒了：\(before.lastRow) → \(after.lastRow)")
    }
}
