import AppKit
import CryptoKit
import Testing
@testable import ClipboardHistory
import ClipboardStore

/// 注入用 FakePasteboard：实现 PasteboardReading（读）与 PasteboardWriting（reuse 写）。
/// 本机命令行工具链无 XCTest，测试使用 Swift Testing。
final class FakePasteboard: PasteboardReading, PasteboardWriting, @unchecked Sendable {
    var currentChangeCount = 0

    /// 当前 pasteboard 上的声明类型与内容（模拟外部 App 写入的状态）
    var declared: [NSPasteboard.PasteboardType] = []
    var strings: [NSPasteboard.PasteboardType: String] = [:]
    var datas: [NSPasteboard.PasteboardType: Data] = [:]

    /// reuse 写入的记录（验证写入行为）
    private(set) var wroteDeclaredTypes: [NSPasteboard.PasteboardType] = []
    private(set) var wroteStrings: [NSPasteboard.PasteboardType: String] = [:]
    private(set) var wroteDatas: [NSPasteboard.PasteboardType: Data] = [:]

    var changeCount: Int { currentChangeCount }
    var types: [NSPasteboard.PasteboardType] { declared }

    func string(forType type: NSPasteboard.PasteboardType) -> String? { strings[type] }
    func data(forType type: NSPasteboard.PasteboardType) -> Data? { datas[type] }
    func declaredTypesContain(_ type: String) -> Bool {
        declared.contains(NSPasteboard.PasteboardType(type))
    }

    func declareTypes(_ types: [NSPasteboard.PasteboardType], owner: Any?) -> Int {
        wroteDeclaredTypes = types
        declared = types
        strings = [:]
        datas = [:]
        return types.count
    }

    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool {
        wroteStrings[type] = string
        strings[type] = string
        return true
    }

    func setData(_ data: Data?, forType type: NSPasteboard.PasteboardType) -> Bool {
        guard let data else { return false }
        wroteDatas[type] = data
        datas[type] = data
        return true
    }

    /// 模拟外部 App 写入纯文本。
    func writeExternalText(_ text: String) {
        declared = [.string]
        strings = [.string: text]
        datas = [:]
        currentChangeCount += 1
    }

    /// 模拟外部 App 写入 PNG 图片。
    func writeExternalPNG(_ png: Data) {
        declared = [.png]
        datas = [.png: png]
        strings = [:]
        currentChangeCount += 1
    }

    /// 模拟外部 App 写入 TIFF 图片（无 PNG 类型）。
    func writeExternalTIFF(_ tiff: Data) {
        declared = [.tiff]
        datas = [.tiff: tiff]
        strings = [:]
        currentChangeCount += 1
    }

    /// 模拟 OneBox 自写（带私有标记）。
    func writeSelfMarkedText(_ text: String) {
        let marker = NSPasteboard.PasteboardType(OneBoxPasteboardMarker.type)
        declared = [.string, marker]
        strings = [.string: text]
        datas = [:]
        currentChangeCount += 1
    }

    /// 清空写入记录（用于分段验证）。
    func resetWrites() {
        wroteDeclaredTypes = []
        wroteStrings = [:]
        wroteDatas = [:]
    }


}

@MainActor
final class ClipboardHistoryServiceTests {

    private let dir: URL
    private let store: ClipboardStore
    private let pasteboard = FakePasteboard()
    private let service: ClipboardHistoryService

    init() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ob-cliphistory-tests-\(UUID().uuidString)", isDirectory: true)
        store = try ClipboardStore(directory: dir)
        service = ClipboardHistoryService(store: store, pasteboard: pasteboard)
        service.pollInterval = 0.05
    }

    deinit {
        try? FileManager.default.removeItem(at: dir)
    }

    /// 等待条件成立。await 让出主 actor，轮询 timer 的处理任务得以执行。
    private func waitUntil(
        timeout: TimeInterval = 3,
        _ condition: @escaping () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return await condition()
    }

    // MARK: - 自写标记

    @Test func selfWriteMarkerIsSkipped() async throws {
        defer { service.stop() }
        service.start()

        pasteboard.writeExternalText("正常内容")
        let ok = await waitUntil { await self.store.count() == 1 }
        #expect(ok, "外部写入应被记录")

        pasteboard.writeSelfMarkedText("onebox 自写内容")
        try await Task.sleep(nanoseconds: 400_000_000)
        let count = await store.count()
        #expect(count == 1, "带自写标记的内容不应进入历史")
        #expect(service.lastError == nil)
    }

    // MARK: - 去重

    @Test func duplicateTextOnlyUpdatesUsed() async throws {
        defer { service.stop() }
        service.start()

        pasteboard.writeExternalText("重复内容")
        var ok = await waitUntil { await self.store.count() == 1 }
        #expect(ok)

        // 相同文本再次进入剪贴板：只 updateUsed，不新增
        pasteboard.writeExternalText("重复内容")
        let expectedHash = SHA256.hash(data: Data("重复内容".utf8)).hexString
        ok = await waitUntil { await self.store.record(contentHash: expectedHash)?.useCount == 1 }
        #expect(ok, "重复内容应更新 useCount")

        let records = await store.records()
        #expect(records.count == 1, "重复内容不应新增条目")
        #expect(records[0].textContent == "重复内容")
        #expect(records[0].kind == .text)
        #expect(records[0].useCount == 1)
        #expect(records[0].byteCount == "重复内容".utf8.count)
    }

    // MARK: - 图片规范化

    @Test func imageNormalizationHashStable() {
        let (png, tiff) = Self.makeImagePair(width: 12, height: 9)

        // 同一图像：以 PNG 类型读取与以 TIFF 类型读取，规范化后 hash 必须一致。
        let pngBoard = FakePasteboard()
        pngBoard.writeExternalPNG(png)
        let fromPNG = PasteboardNormalizer.read(from: pngBoard)

        let tiffBoard = FakePasteboard()
        tiffBoard.writeExternalTIFF(tiff)
        let fromTIFF = PasteboardNormalizer.read(from: tiffBoard)

        #expect(fromPNG != nil)
        #expect(fromTIFF != nil)
        #expect(fromPNG?.hash == fromTIFF?.hash, "同一图像不同剪贴板类型应得到相同 hash")
        #expect(fromPNG?.pngData == fromTIFF?.pngData)
        #expect(fromPNG?.kind == .image)
        #expect(fromPNG?.text == nil)
        #expect(
            fromPNG?.hash == SHA256.hash(data: fromPNG!.pngData!).hexString,
            "图片 hash 应等于规范化 PNG 字节"
        )
    }

    @Test func imageRecordInsertedOnceWithDuplicateUpdate() async throws {
        defer { service.stop() }
        let (png, tiff) = Self.makeImagePair(width: 10, height: 10)
        service.start()

        pasteboard.writeExternalPNG(png)
        var ok = await waitUntil { await self.store.count() == 1 }
        #expect(ok, "图片首次应入库")

        // 同一图像换一种剪贴板类型再次出现：命中 hash，只更新使用信息
        pasteboard.writeExternalTIFF(tiff)
        ok = await waitUntil {
            guard await self.store.count() == 1 else { return false }
            let first = await self.store.records().first
            return first?.useCount == 1
        }
        #expect(ok, "同图不同类型应命中去重并更新 useCount")

        let records = await store.records()
        #expect(records.count == 1)
        #expect(records[0].kind == .image)
        #expect(records[0].useCount == 1)
        #expect(records[0].imageWidth == 10)
        #expect(records[0].imageHeight == 10)
    }

    // MARK: - 暂停

    @Test func pausedChangeCountTrackedWithoutReading() async throws {
        defer { service.stop() }
        service.start()
        #expect(service.setRecordingPaused(true))
        #expect(service.isRecordingPaused)

        pasteboard.writeExternalText("暂停期间的内容")
        // 留出多个轮询周期，暂停期间 changeCount 应被跟踪
        try await Task.sleep(nanoseconds: 400_000_000)
        var count = await store.count()
        #expect(count == 0, "暂停期间不应读取内容")

        service.setRecordingPaused(false)
        // 恢复后等待多个轮询周期：暂停期间写入的旧内容不应被误读
        try await Task.sleep(nanoseconds: 400_000_000)
        count = await store.count()
        #expect(count == 0, "恢复后不应读取暂停期间的旧内容")

        // 恢复后的新写入正常记录
        pasteboard.writeExternalText("恢复后的新内容")
        let ok = await waitUntil { await self.store.count() == 1 }
        #expect(ok)
    }

    // MARK: - stop

    @Test func stopStopsPolling() async throws {
        defer { service.stop() }
        service.start()
        pasteboard.writeExternalText("停止前的内容")
        let ok = await waitUntil { await self.store.count() == 1 }
        #expect(ok)

        service.stop()
        #expect(!service.isMonitoring)

        pasteboard.writeExternalText("停止后的内容")
        try await Task.sleep(nanoseconds: 400_000_000)
        let records = await store.records()
        #expect(records.count == 1, "stop 后不应再轮询入库")
        #expect(records.first?.textContent == "停止前的内容")
    }

    @Test func startDoesNotReadPreexistingContent() async throws {
        defer { service.stop() }
        pasteboard.writeExternalText("启动前就存在的内容")
        service.start()
        try await Task.sleep(nanoseconds: 400_000_000)
        let count = await store.count()
        #expect(count == 0, "start 不应把启动前已有内容读进历史")
    }

    // MARK: - 空白文本

    @Test func blankTextNotStored() async throws {
        defer { service.stop() }
        service.start()
        for blank in ["", "   ", "\n\t  \n"] {
            pasteboard.writeExternalText(blank)
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        let count = await store.count()
        #expect(count == 0, "空白文本不应入库")
    }

    // MARK: - reuse

    @Test func reuseTextWritesMarkerAndUpdatesUsed() async throws {
        defer { service.stop() }
        service.start()
        pasteboard.writeExternalText("要复用的文本")
        var ok = await waitUntil { await self.store.count() == 1 }
        #expect(ok)

        let record = await store.records()[0]
        #expect(record.useCount == 0)
        pasteboard.resetWrites()

        service.reuse(record)
        ok = await waitUntil { await self.store.record(id: record.id)?.useCount == 1 }
        #expect(ok, "reuse 应更新 useCount")

        let marker = NSPasteboard.PasteboardType(OneBoxPasteboardMarker.type)
        #expect(pasteboard.wroteDeclaredTypes.contains(.string), "reuse 文本应写 string 类型")
        #expect(pasteboard.wroteDeclaredTypes.contains(marker), "reuse 必须声明私有标记")
        #expect(pasteboard.wroteStrings[.string] == "要复用的文本")
    }

    @Test func reuseImageWritesMarkerAndUpdatesUsed() async throws {
        defer { service.stop() }
        let (png, _) = Self.makeImagePair(width: 8, height: 6)
        let record = try await store.insertImage(png: png, hash: "reuse-image-test")
        #expect(record.useCount == 0)

        service.reuse(record)
        let ok = await waitUntil { await self.store.record(id: record.id)?.useCount == 1 }
        #expect(ok, "reuse 图片应更新 useCount")

        let marker = NSPasteboard.PasteboardType(OneBoxPasteboardMarker.type)
        #expect(pasteboard.wroteDeclaredTypes.contains(.png), "reuse 图片应写 png 类型")
        #expect(pasteboard.wroteDeclaredTypes.contains(marker), "reuse 必须声明私有标记")
        let written = pasteboard.wroteDatas[.png]
        #expect(written != nil, "应从 store 文件读取 PNG 写回")
        if let written, let url = await store.imageURL(of: record) {
            let fileData = try Data(contentsOf: url)
            #expect(written == fileData, "写回的 PNG 应与存储文件一致")
        }
    }

    // MARK: - 文本规范化

    @Test func textNormalization() {
        let board = FakePasteboard()
        board.writeExternalText("普通文本")
        let content = PasteboardNormalizer.read(from: board)
        #expect(content?.text == "普通文本")
        #expect(content?.kind == .text)
        #expect(content?.pngData == nil)
        #expect(
            content?.hash == SHA256.hash(data: Data("普通文本".utf8)).hexString,
            "文本 hash 应等于 UTF-8 字节的 SHA-256"
        )

        // 空白文本与无内容 pasteboard 都返回 nil
        let blank = FakePasteboard()
        blank.writeExternalText("  \n\t ")
        #expect(PasteboardNormalizer.read(from: blank) == nil)
        let none = FakePasteboard()
        #expect(PasteboardNormalizer.read(from: none) == nil)
    }

    // MARK: - 辅助

    /// 生成确定性测试图像，返回 (pngData, tiffData)——同一像素内容的两种编码。
    private static func makeImagePair(width: Int, height: Int) -> (Data, Data) {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = NSSize(width: width, height: height)
        for x in 0..<width {
            for y in 0..<height {
                rep.setColor(
                    NSColor(
                        calibratedRed: Double(x) / Double(max(1, width - 1)),
                        green: Double(y) / Double(max(1, height - 1)),
                        blue: 0.5, alpha: 1
                    ),
                    atX: x, y: y
                )
            }
        }
        let png = rep.representation(using: .png, properties: [:])!
        let tiff = rep.tiffRepresentation!
        return (png, tiff)
    }
}

private extension SHA256Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
