import Testing
import CoreGraphics
@testable import ScreenCapture

@Suite
struct SelectionEditingTests {

    private let rect = CGRect(x: 100, y: 200, width: 300, height: 180)
    private let slop: CGFloat = 10
    private let minSize: CGFloat = 24

    // MARK: - hitTest

    @Test func hitTestPrefersCornerHandleOverInterior() {
        let hit = SelectionEditing.hitTest(
            point: CGPoint(x: 100, y: 200),
            in: rect,
            handleSlop: slop
        )
        #expect(hit == .handle(.bottomLeft))
    }

    @Test func hitTestEdgeMidpointHandle() {
        let hit = SelectionEditing.hitTest(
            point: CGPoint(x: 250, y: 380),
            in: rect,
            handleSlop: slop,
            edgeOutset: 12,
            edgeInset: 3
        )
        #expect(hit == .handle(.top))
    }

    @Test func hitTestInteriorWhenInsideAwayFromHandles() {
        let hit = SelectionEditing.hitTest(
            point: CGPoint(x: 250, y: 290),
            in: rect,
            handleSlop: slop
        )
        #expect(hit == .interior)
    }

    @Test func hitTestOutsideReturnsNone() {
        let hit = SelectionEditing.hitTest(
            point: CGPoint(x: 10, y: 10),
            in: rect,
            handleSlop: slop
        )
        #expect(hit == .none)
    }

    @Test func hitTestTopRightHandle() {
        let hit = SelectionEditing.hitTest(
            point: CGPoint(x: 400, y: 380),
            in: rect,
            handleSlop: slop
        )
        #expect(hit == .handle(.topRight))
    }

    @Test func hitTestFrameBiasedOutsideAllowsInteriorAnnotationNearEdge() {
        // 选区外侧 8pt（避开中点手柄）应命中边框拖动
        let outsideEdge = SelectionEditing.hitTest(
            point: CGPoint(x: 150, y: 192),
            in: rect,
            handleSlop: slop,
            edgeOutset: 12,
            edgeInset: 3
        )
        #expect(outsideEdge == .frame)

        // 选区内侧 6pt（超过 edgeInset=3）应让给内部标注，不误触边框
        let insideNearEdge = SelectionEditing.hitTest(
            point: CGPoint(x: 150, y: 206),
            in: rect,
            handleSlop: slop,
            edgeOutset: 12,
            edgeInset: 3
        )
        #expect(insideNearEdge == .interior)
    }

    // MARK: - move

    @Test func moveByDelta() {
        let moved = SelectionEditing.move(rect, by: CGVector(dx: 40, dy: -20))
        #expect(moved == CGRect(x: 140, y: 180, width: 300, height: 180))
    }

    // MARK: - resize

    @Test func resizeFromBottomLeftKeepsTopRightFixed() {
        let resized = SelectionEditing.resize(
            rect,
            handle: .bottomLeft,
            to: CGPoint(x: 120, y: 220),
            minimumSize: minSize
        )
        #expect(resized.minX == 120)
        #expect(resized.minY == 220)
        #expect(resized.maxX == 400)
        #expect(resized.maxY == 380)
    }

    @Test func resizeFromSingleEdgeOnlyChangesThatEdge() {
        let resizedRight = SelectionEditing.resize(
            rect,
            handle: .right,
            to: CGPoint(x: 460, y: 999),
            minimumSize: minSize
        )
        #expect(resizedRight == CGRect(x: 100, y: 200, width: 360, height: 180))

        let resizedTop = SelectionEditing.resize(
            rect,
            handle: .top,
            to: CGPoint(x: 999, y: 420),
            minimumSize: minSize
        )
        #expect(resizedTop == CGRect(x: 100, y: 200, width: 300, height: 220))
    }

    @Test func resizeEnforcesMinimumSize() {
        let resized = SelectionEditing.resize(
            rect,
            handle: .bottomLeft,
            to: CGPoint(x: 500, y: 500),
            minimumSize: minSize
        )
        #expect(resized.width >= minSize)
        #expect(resized.height >= minSize)
        #expect(resized.maxX == 400)
        #expect(resized.maxY == 380)
    }
}
