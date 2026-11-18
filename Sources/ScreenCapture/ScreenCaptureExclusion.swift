import CoreGraphics

/// 捕获滤镜用的窗口排除：按 CGWindowID 求交，避免截进本 App 遮罩。
public enum ScreenCaptureExclusion {

    /// 只保留「请求排除」且确实出现在可共享内容里的窗口 ID（保持 requested 顺序）。
    public static func resolveWindowIDs(
        requested: [CGWindowID],
        available: [CGWindowID]
    ) -> [CGWindowID] {
        let availableSet = Set(available)
        return requested.filter { availableSet.contains($0) }
    }
}
