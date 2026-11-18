import Foundation

/// 对外取色入口：拉起遮罩并返回结果（调用方负责权限与剪贴板写入）。
public final class ColorPickService: Sendable {
    public init() {}

    @MainActor
    public func requestPick() async -> ColorPickOutcome {
        await ColorPickOverlayController.run()
    }
}
