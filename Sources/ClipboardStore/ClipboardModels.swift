import Foundation
import AppKit
import CoreGraphics
import ImageIO

/// 剪贴板历史记录。存储「怎么存」，不关心内容来自哪个 App。
public struct ClipboardRecord: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: Int, Codable, Sendable {
        case text = 0
        case image = 1
    }

    public var id: UUID
    public var kind: Kind
    public var textContent: String?
    public var contentHash: String
    /// 相对存储根目录的路径：images/<uuid>.png
    public var imageFile: String?
    /// 相对存储根目录的路径：thumbnails/<uuid>.png
    public var thumbnailFile: String?
    public var imageWidth: Int?
    public var imageHeight: Int?
    public var byteCount: Int
    public var createdAt: Date
    public var lastUsedAt: Date
    public var useCount: Int
    public var pinned: Bool

    public init(
        id: UUID = UUID(),
        kind: Kind,
        textContent: String? = nil,
        contentHash: String,
        imageFile: String? = nil,
        thumbnailFile: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        byteCount: Int = 0,
        createdAt: Date = Date(),
        lastUsedAt: Date = Date(),
        useCount: Int = 0,
        pinned: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.textContent = textContent
        self.contentHash = contentHash
        self.imageFile = imageFile
        self.thumbnailFile = thumbnailFile
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.byteCount = byteCount
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
        self.pinned = pinned
    }
}

/// 列表过滤器。
public enum ClipboardRecordFilter: Sendable, Equatable {
    case all
    case text
    case image
    case pinned
}
