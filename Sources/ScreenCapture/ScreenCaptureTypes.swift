import Foundation
import CoreGraphics

/// 一次选区截图的产物：同时保留 CGImage、PNG 数据和两种尺寸，
/// 标注与复制流程不需要重复编码。
public struct CapturedImage: Sendable {
    /// 捕获结果（像素图）。
    public let image: CGImage
    /// 与 image 一致的 PNG 编码数据。
    public let pngData: Data
    /// 选区 point 尺寸。
    public let pointSize: CGSize
    /// 输出像素尺寸。
    public let pixelSize: CGSize

    public init(image: CGImage, pngData: Data, pointSize: CGSize, pixelSize: CGSize) {
        self.image = image
        self.pngData = pngData
        self.pointSize = pointSize
        self.pixelSize = pixelSize
    }
}

/// 选区确认后的动作，由调用方决定后续流程。
public enum SelectionAction: Sendable, Equatable {
    /// 进入标注编辑器。
    case annotate
    /// 写入剪贴板。
    case copy
    /// 保存为 PNG 文件。
    case save

    /// dock / 提示胶囊里展示的按钮文案。
    var title: String {
        switch self {
        case .annotate: return "标注"
        case .copy: return "复制"
        case .save: return "保存"
        }
    }
}

/// 选区交互的最终结果：取消，或带着动作返回截图。
public enum SelectionOutcome: Sendable {
    /// 用户按 Esc、点击「取消」或选区无效。
    case canceled
    /// 确认选区并完成捕获。
    case selected(CapturedImage, action: SelectionAction)
}

/// 截图相关错误。notAuthorized 附带系统设置恢复路径文案。
public enum ScreenCaptureError: Error, LocalizedError {
    /// 未获得屏幕录制权限。
    case notAuthorized
    /// 用户主动取消。
    case canceled
    /// 底层捕获失败，携带原因。
    case captureFailed(String)
    /// 选区无效（空矩形或不与任何屏幕相交）。
    case invalidSelection

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "未获得「屏幕录制」权限。请打开 系统设置 > 隐私与安全性 > 屏幕录制，勾选 OneBox 后重启应用，再重新截图。"
        case .canceled:
            return "截图已取消。"
        case .captureFailed(let reason):
            return "截图失败：\(reason)"
        case .invalidSelection:
            return "选区无效，请重新框选。"
        }
    }
}
