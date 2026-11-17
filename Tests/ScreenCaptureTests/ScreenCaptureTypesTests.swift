import Foundation
import Testing
import CoreGraphics
@testable import ScreenCapture

/// 公开类型语义测试：错误文案、SelectionAction Equatable、SelectionOutcome 模式匹配。
/// 注：本仓库测试统一使用 swift-testing（本机 CLT 环境没有 XCTest 运行时）。
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

    // MARK: - SelectionAction Equatable

    @Test func selectionActionEquality() {
        #expect(SelectionAction.annotate == SelectionAction.annotate)
        #expect(SelectionAction.copy == SelectionAction.copy)
        #expect(SelectionAction.save == SelectionAction.save)
        #expect(SelectionAction.annotate != SelectionAction.copy)
        #expect(SelectionAction.copy != SelectionAction.save)
        #expect(SelectionAction.save != SelectionAction.annotate)
    }

    @Test func selectionActionSetSemantics() {
        let actions: Set<SelectionAction> = [.annotate, .copy, .save, .annotate]
        #expect(actions.count == 3)
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
        let outcome: SelectionOutcome = .selected(captured, action: .copy)

        guard case .selected(let returned, let action) = outcome else {
            Issue.record("应为 selected")
            return
        }
        #expect(returned.image === image)
        #expect(returned.pointSize == CGSize(width: 100, height: 50))
        #expect(returned.pixelSize == CGSize(width: 200, height: 100))
        #expect(returned.pngData == Data([0x89, 0x50, 0x4E, 0x47]))
        #expect(action == .copy)
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
}
