import AppKit
import Foundation

/// 自写剪贴板时的私有标记类型。
public enum OneBoxPasteboardMarker {
    public static let type = "com.onebox.internal-write"
}

/// 供 UI/测试注入的 pasteboard 抽象（只读）。
public protocol PasteboardReading: AnyObject {
    var changeCount: Int { get }
    var types: [NSPasteboard.PasteboardType] { get }
    func string(forType type: NSPasteboard.PasteboardType) -> String?
    func data(forType type: NSPasteboard.PasteboardType) -> Data?
    func declaredTypesContain(_ type: String) -> Bool
}

extension NSPasteboard: PasteboardReading {
    /// NSPasteboard.types 声明为可选数组，协议要求非可选，因此用改名 witness 桥接。
    @_implements(PasteboardReading, types)
    public var oneBoxReadingTypes: [NSPasteboard.PasteboardType] {
        types ?? []
    }

    public func declaredTypesContain(_ type: String) -> Bool {
        (types ?? []).contains(NSPasteboard.PasteboardType(type))
    }
}
