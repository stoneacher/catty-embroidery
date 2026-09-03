@testable import catrobat_embroidery_ios
import EmbroideryEngine
import StagePreview
import SwiftUI
import Testing

/// The plan-to-pixel contract: what the two geometry builders actually put in a `Path`.
///
/// **This suite exists because `/codex-review` round 1 (finding 2) showed the contract had no
/// executable coverage at all.** Two mutations left every one of the 752 package assertions
/// green: reading `points[segment.from + 1]` instead of `points[segment.to]` — which draws
/// 1-stitch stubs where a coarse plan asked for 51-stitch spans, leaving 50-interval gaps at
/// 50 000 stitches — and iterating `DotRun.indices` instead of `dottedIndices`, which rebuilds
/// all 50 001 ellipses and hands back the entire dot half of US-310's saving. Both are in the app
/// layer, which the engine suite cannot see.
///
/// It is testable at all only because US-310's file split made the builders `internal static`
/// functions over plain values. A `Path` can be walked; the `GraphicsContext` these used to be
/// buried in cannot, which is what the story's "test items not written" section had recorded as
/// the price of the design. That price turns out to be avoidable for the geometry, and only the
/// *dispatch* (which window a hosted `Canvas` asks for) is genuinely out of reach.
@Suite("Canvas stitch stroke geometry")
struct CanvasStitchStrokeTests {
    /// Identity, so a stage point maps to the numerically identical view point and the
    /// assertions can be about *which* points were used rather than about the transform.
    private static let identity = StageTransform(scale: 1, translation: .zero)

    private static func points(_ count: Int) -> [PreviewStitch] {
        (0 ..< count).map {
            PreviewStitch(position: StagePoint(x: Double($0) * 10, y: 0), color: .black)
        }
    }

    /// Every `move`/`line` pair in a path, as the coordinates actually submitted.
    ///
    /// The closure is bound to a `let` and passed as a value rather than written as a trailing
    /// closure, because SwiftFormat's `preferForLoop` rule rewrites `path.forEach { … }` into
    /// `for element in path` — and `Path` is not a `Sequence`, so the formatter's own output does
    /// not compile. Found by the PostToolUse hook doing exactly that to the first version of this
    /// file.
    private static func subpaths(_ path: Path) -> [(from: CGPoint, to: CGPoint)] {
        var pairs: [(from: CGPoint, to: CGPoint)] = []
        var pending: CGPoint?
        let collect: (Path.Element) -> Void = { element in
            switch element {
            case let .move(to: point):
                pending = point
            case let .line(to: point):
                if let start = pending { pairs.append((start, point)) }
                pending = point
            default:
                break
            }
        }
        path.forEach(collect)
        return pairs
    }

    /// `addEllipse` begins a new subpath, so counting `move` elements counts the dots.
    private static func subpathCount(_ path: Path) -> Int {
        var moves = 0
        let count: (Path.Element) -> Void = { element in
            if case .move = element { moves += 1 }
        }
        path.forEach(count)
        return moves
    }

    // MARK: - Segments

    /// **The mutation this pins**: `points[segment.from + 1]` for `points[segment.to]`. A coarse
    /// segment carries both its endpoints precisely because `to` is *not* `from + 1`, so reading
    /// the far end as an offset from the near one silently redraws a stride-1 stub per span.
    @Test("a segment is drawn between the two stitches it names")
    func aSegmentIsDrawnBetweenTheTwoStitchesItNames() throws {
        let path = CanvasStitchStroke.segmentPath(
            [StitchDrawPlan.Segment(from: 0, to: 51), StitchDrawPlan.Segment(from: 51, to: 60)],
            of: Self.points(61),
            transform: Self.identity
        )

        let drawn = Self.subpaths(path)
        try #require(drawn.count == 2)
        #expect(drawn[0].from.x == 0)
        #expect(drawn[0].to.x == 510, "the far endpoint is `to`, not `from + 1`")
        #expect(drawn[1].from.x == 510)
        #expect(drawn[1].to.x == 600)
    }

    @Test("a fine segment is still drawn between consecutive stitches")
    func aFineSegmentIsStillDrawnBetweenConsecutiveStitches() throws {
        let path = CanvasStitchStroke.segmentPath(
            [StitchDrawPlan.Segment(from: 3, to: 4)],
            of: Self.points(10),
            transform: Self.identity
        )

        let drawn = Self.subpaths(path)
        try #require(drawn.count == 1)
        #expect(drawn[0].from.x == 30)
        #expect(drawn[0].to.x == 40)
    }

    /// ADR-021 divergence #5: a rejected coordinate may reach the display list. One bad endpoint
    /// must cost its own subpath and no more — a batched `Path` with a non-finite point in it can
    /// be discarded wholesale by CoreGraphics, taking every good segment in the colour run with
    /// it.
    @Test("one undrawable endpoint costs its own segment and no others")
    func oneUndrawableEndpointCostsOnlyItsOwnSegment() {
        var points = Self.points(4)
        points[2] = PreviewStitch(position: StagePoint(x: .nan, y: 0), color: .black)

        let path = CanvasStitchStroke.segmentPath(
            [
                StitchDrawPlan.Segment(from: 0, to: 1),
                StitchDrawPlan.Segment(from: 1, to: 2),
                StitchDrawPlan.Segment(from: 2, to: 3)
            ],
            of: points,
            transform: Self.identity
        )

        #expect(Self.subpaths(path).count == 1, "only the segment not touching the bad point")
    }

    // MARK: - Dots

    /// **The mutation this pins**: iterating `run.indices` instead of `run.dottedIndices`. The
    /// plan is identical either way — this is a renderer-side loss that no plan assertion sees.
    @Test("a strided dot run draws one dot per stride, not one per stitch")
    func aStridedDotRunDrawsOnePerStride() {
        let list = displayListOfShortMoves(count: 5001)
        let plan = StitchDrawPlan.coarse(of: list, threshold: 0, target: 100)
        let run = plan.dots[0]

        let path = CanvasStitchStroke.dotPath(run, of: list.stitches, transform: Self.identity)

        #expect(run.stride == 51)
        #expect(Self.subpathCount(path) == run.count)
        #expect(Self.subpathCount(path) < list.count / 10, "iterating `indices` would draw all of them")
    }

    @Test("a fine dot run draws one dot per stitch")
    func aFineDotRunDrawsOnePerStitch() {
        let list = displayListOfShortMoves(count: 40)
        let plan = StitchDrawPlan.entire(of: list)
        let run = plan.dots[0]

        let path = CanvasStitchStroke.dotPath(run, of: list.stitches, transform: Self.identity)

        #expect(run.stride == 1)
        #expect(Self.subpathCount(path) == 40)
    }

    @Test("an undrawable dot is skipped rather than added")
    func anUndrawableDotIsSkipped() {
        var stitches = Self.points(4)
        stitches[1] = PreviewStitch(position: StagePoint(x: .infinity, y: 0), color: .black)
        var list = StitchDisplayList()
        list.append(contentsOf: stitches)

        let plan = StitchDrawPlan.entire(of: list)
        let path = CanvasStitchStroke.dotPath(plan.dots[0], of: list.stitches, transform: Self.identity)

        #expect(Self.subpathCount(path) == 3)
    }

    // MARK: - Raster eligibility

    /// **The three clauses that are about staleness, not liveness** (`/codex-review` round 1,
    /// finding 3). `forFrame` asks `canUseRaster` itself and takes this as an input precisely
    /// because "no usable raster" and "an interaction is in flight" are different questions; the
    /// branch this replaced conflated them.
    @Test("a raster is composited only when it is live-free, current and the right size")
    func aRasterIsCompositedOnlyWhenCurrentAndTheRightSize() {
        let viewport = ViewSize(width: 390, height: 500)
        let size = CGSize(width: 390, height: 500)

        #expect(CanvasStitchStroke.compositingRaster(
            canUseRaster: true, bakedKey: "key", expectedKey: "key", size: size, viewport: viewport
        ))
        // Nothing baked yet: `Optional.none == .some(key)` is false, and the frame draws it all.
        #expect(!CanvasStitchStroke.compositingRaster(
            canUseRaster: true, bakedKey: nil, expectedKey: "key", size: size, viewport: viewport
        ))
        // A stale raster — the settled count, the transform or the contrast moved.
        #expect(!CanvasStitchStroke.compositingRaster(
            canUseRaster: true, bakedKey: "old", expectedKey: "key", size: size, viewport: viewport
        ))
        // A `Canvas` smaller than the raster's viewport would *stretch* the settled layer under an
        // unstretched tail: a visibly misplaced seam, so fall back rather than composite.
        #expect(!CanvasStitchStroke.compositingRaster(
            canUseRaster: true, bakedKey: "key", expectedKey: "key",
            size: CGSize(width: 380, height: 500), viewport: viewport
        ))
        #expect(!CanvasStitchStroke.compositingRaster(
            canUseRaster: true, bakedKey: "key", expectedKey: "key",
            size: CGSize(width: 390, height: 499), viewport: viewport
        ))
        // Live: the raster's pixels were baked at another transform.
        #expect(!CanvasStitchStroke.compositingRaster(
            canUseRaster: false, bakedKey: "key", expectedKey: "key", size: size, viewport: viewport
        ))
    }

    private func displayListOfShortMoves(count: Int) -> StitchDisplayList {
        var list = StitchDisplayList()
        list.append(contentsOf: (0 ..< count).map {
            PreviewStitch(position: StagePoint(x: Double($0) * 2, y: 0), color: .black)
        })
        return list
    }
}
