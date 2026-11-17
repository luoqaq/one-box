import Foundation
import AppKit
import CoreGraphics
import ImageIO

/// 最近截图记录。
public struct CaptureRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    /// 相对存储根目录：captures/<uuid>.png
    public var file: String
    public var thumbnailFile: String?
    public var width: Int
    public var height: Int
    public var byteCount: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        file: String,
        thumbnailFile: String? = nil,
        width: Int,
        height: Int,
        byteCount: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.file = file
        self.thumbnailFile = thumbnailFile
        self.width = width
        self.height = height
        self.byteCount = byteCount
        self.createdAt = createdAt
    }
}
